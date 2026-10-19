MODULE Floppy; (* The WD1793 floppy disk controller at the FPGA SoC's
   external bus card 0, $0800 (model: Floppy, a BlockDriver): 720K 3.5"
   disks, 9 sectors of 512 bytes, 2 sides, 80 tracks. *)
  IMPORT SYSTEM, Driver, BlockDriver;

  CONST
    (* FDC register addresses (WD1773 at FPGA ext-bus card window $0800) *)
    CMD    = 0800H;  (* W: command, R: status *)
    STATUS = 0800H;
    TRACK  = 0801H;
    SECTOR = 0802H;
    DATA   = 0803H;
    CTRL   = 0806H;  (* W: drive control, R: drive status *)

    (* WD1793 commands *)
    cmdRestore = 0;
    cmdSeek    = 10H;
    cmdRead    = 80H;
    cmdWrite   = 0A0H;

    (* Status register bits *)
    stBusy     = 1;
    stDRQ      = 2;
    stNotReady = 80H;

    (* Drive control bits *)
    ctrlMotorOn = 20H;
    ctrlDrive0  = 2;
    ctrlDrive1  = 4;

    (* Disk geometry: 720K 3.5" *)
    SectorsPerTrack* = 9;
    SidesPerDisk*    = 2;
    SectorsPerCyl    = 18;  (* SectorsPerTrack * SidesPerDisk *)
    BlockSize*       = BlockDriver.BlockSize;
    MaxRetries       = 10000;

    (* Get/Set keys *)
    keyError*  = 0;
    keyTrack*  = 1;

  TYPE
    Floppy* = POINTER TO FloppyDesc;
    FloppyDesc* = RECORD (BlockDriver.BlockDriverDesc)
      drive: INTEGER;      (* drive number, 0 or 1 *)
      curTrack: INTEGER;   (* current head position, -1: unknown *)
      error: INTEGER       (* last error code: 0 = OK *)
    END;

  (* --- Low-level register access --- *)

  PROCEDURE PutReg(reg, val: INTEGER);
    VAR b: BYTE;
  BEGIN b := val; SYSTEM.PUT(0, reg, b)
  END PutReg;

  PROCEDURE GetReg(reg: INTEGER; VAR val: INTEGER);
    VAR b: BYTE;
  BEGIN SYSTEM.GET(0, reg, b); val := b
  END GetReg;

  (* --- Status polling --- *)

  PROCEDURE WaitNotBusy(): BOOLEAN;
    VAR s, n: INTEGER; done: BOOLEAN;
  BEGIN
    n := 0; done := FALSE;
    REPEAT
      GetReg(STATUS, s);
      INC(n);
      IF s MOD 2 = 0 THEN done := TRUE END
    UNTIL done OR (n >= MaxRetries)
  RETURN done
  END WaitNotBusy;

  PROCEDURE WaitDRQ(): BOOLEAN;
    VAR s, n: INTEGER; ok: BOOLEAN;
  BEGIN
    n := 0; ok := FALSE;
    REPEAT
      GetReg(STATUS, s);
      INC(n);
      IF s DIV 2 MOD 2 = 1 THEN ok := TRUE  (* DRQ set *)
      ELSIF s MOD 2 = 0 THEN ok := FALSE; n := MaxRetries  (* Busy cleared without DRQ *)
      END
    UNTIL ok OR (n >= MaxRetries)
  RETURN ok
  END WaitDRQ;

  (* --- Drive selection and motor control --- *)

  PROCEDURE SelectDrive(drive, side: INTEGER);
    VAR ctl: INTEGER;
  BEGIN
    ctl := ctrlMotorOn;
    IF drive = 0 THEN ctl := ctl + ctrlDrive0
    ELSE ctl := ctl + ctrlDrive1
    END;
    IF side = 1 THEN INC(ctl) END;
    PutReg(CTRL, ctl)
  END SelectDrive;

  (* --- Seek to track --- *)

  PROCEDURE Seek(d: Floppy; track: INTEGER): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN
    ok := TRUE;
    IF track # d.curTrack THEN
      IF track = 0 THEN
        PutReg(CMD, cmdRestore);
        ok := WaitNotBusy()
      ELSE
        PutReg(DATA, track);
        PutReg(CMD, cmdSeek);
        ok := WaitNotBusy()
      END;
      IF ok THEN d.curTrack := track END
    END
  RETURN ok
  END Seek;

  (* --- Block I/O --- *)

  PROCEDURE (d: Floppy) ReadBlock*(blockNum: INTEGER; VAR buf: ARRAY OF BYTE): INTEGER OVERRIDE;
    VAR track, side, sector, i, s, res: INTEGER;
  BEGIN
    d.error := 0; res := 0;

    track := blockNum DIV SectorsPerCyl;
    side := blockNum DIV SectorsPerTrack MOD SidesPerDisk;
    sector := blockNum MOD SectorsPerTrack + 1;

    SelectDrive(d.drive, side);

    IF ~Seek(d, track) THEN d.error := 1; res := -1 END;

    IF res = 0 THEN
      PutReg(SECTOR, sector);
      PutReg(CMD, cmdRead);
      IF ~WaitDRQ() THEN d.error := 2; res := -2 END
    END;

    IF res = 0 THEN
      i := 0;
      WHILE (i < BlockSize) & (res = 0) DO
        GetReg(DATA, s);
        buf[i] := s;
        INC(i)
      END
    END;

    IF res = 0 THEN
      IF ~WaitNotBusy() THEN d.error := 4; res := -4 END
    END;

    IF res = 0 THEN
      GetReg(STATUS, s);
      IF s DIV 8 MOD 2 = 1 THEN d.error := 5; res := -5
      ELSIF s DIV 16 MOD 2 = 1 THEN d.error := 6; res := -6
      END
    END
  RETURN res
  END ReadBlock;

  PROCEDURE (d: Floppy) WriteBlock*(blockNum: INTEGER; VAR buf: ARRAY OF BYTE): INTEGER OVERRIDE;
    VAR track, side, sector, i, s, res: INTEGER;
  BEGIN
    d.error := 0; res := 0;

    track := blockNum DIV SectorsPerCyl;
    side := blockNum DIV SectorsPerTrack MOD SidesPerDisk;
    sector := blockNum MOD SectorsPerTrack + 1;

    SelectDrive(d.drive, side);

    IF ~Seek(d, track) THEN d.error := 1; res := -1 END;

    IF res = 0 THEN
      PutReg(SECTOR, sector);
      PutReg(CMD, cmdWrite);
      IF ~WaitDRQ() THEN d.error := 2; res := -2 END
    END;

    IF res = 0 THEN
      i := 0;
      WHILE (i < BlockSize) & (res = 0) DO
        s := buf[i];
        PutReg(DATA, s);
        INC(i)
      END
    END;

    IF res = 0 THEN
      IF ~WaitNotBusy() THEN d.error := 4; res := -4 END
    END;

    IF res = 0 THEN
      GetReg(STATUS, s);
      IF s DIV 8 MOD 2 = 1 THEN d.error := 5; res := -5
      ELSIF s DIV 64 MOD 2 = 1 THEN d.error := 7; res := -7
      END
    END
  RETURN res
  END WriteBlock;

  (* --- Get/Set control parameters --- *)

  PROCEDURE (d: Floppy) Get*(key: INTEGER; VAR val: INTEGER) OVERRIDE;
  BEGIN
    IF key = keyError THEN val := d.error
    ELSIF key = keyTrack THEN val := d.curTrack
    ELSE val := -1
    END
  END Get;

  PROCEDURE (d: Floppy) Set*(key: INTEGER; val: INTEGER) OVERRIDE;
  BEGIN
    IF key = keyError THEN d.error := val END
  END Set;

  (* --- Creation --- *)

  (* The driver of drive 0 or 1, named FD0 or FD1. *)
  PROCEDURE New*(drive: INTEGER): Floppy;
    VAR d: Floppy; name: ARRAY 4 OF CHAR;
  BEGIN
    NEW(d); d.drive := drive; d.curTrack := -1; d.error := 0;
    name[0] := "F"; name[1] := "D"; name[2] := CHR(ORD("0") + drive); name[3] := 0X;
    Driver.SetName(d, name);
    RETURN d
  END New;

END Floppy.
