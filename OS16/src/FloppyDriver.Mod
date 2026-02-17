MODULE FloppyDriver;
  IMPORT SYSTEM, Driver;

  CONST
    (* FDC register addresses (WD1793 at I/O slot $C010) *)
    CMD    = 0C010H;  (* W: command, R: status *)
    STATUS = 0C010H;
    TRACK  = 0C011H;
    SECTOR = 0C012H;
    DATA   = 0C013H;
    CTRL   = 0C016H;  (* W: drive control, R: drive status *)

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
    BlockSize*       = 512;
    MaxRetries       = 10000;

    (* Get/Set keys *)
    keyError*  = 0;
    keyTrack*  = 1;

  VAR
    driveNum: INTEGER;   (* drive number for this instance *)
    curTrack: INTEGER;   (* current head position *)
    error: INTEGER;      (* last error code: 0 = OK *)

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

  PROCEDURE Seek(track: INTEGER): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN
    ok := TRUE;
    IF track # curTrack THEN
      IF track = 0 THEN
        PutReg(CMD, cmdRestore);
        ok := WaitNotBusy()
      ELSE
        PutReg(DATA, track);
        PutReg(CMD, cmdSeek);
        ok := WaitNotBusy()
      END;
      IF ok THEN curTrack := track END
    END
  RETURN ok
  END Seek;

  (* --- Block I/O (matching Driver.BlockDriver interface) --- *)

  PROCEDURE ReadBlock*(d: Driver.BlockDriver; blockNum: INTEGER; VAR buf: ARRAY OF BYTE): INTEGER;
    VAR track, side, sector, i, s, res: INTEGER;
  BEGIN
    error := 0; res := 0;

    track := blockNum DIV SectorsPerCyl;
    side := blockNum DIV SectorsPerTrack MOD SidesPerDisk;
    sector := blockNum MOD SectorsPerTrack + 1;

    SelectDrive(driveNum, side);

    IF ~Seek(track) THEN error := 1; res := -1 END;

    IF res = 0 THEN
      PutReg(SECTOR, sector);
      PutReg(CMD, cmdRead);
      IF ~WaitDRQ() THEN error := 2; res := -2 END
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
      IF ~WaitNotBusy() THEN error := 4; res := -4 END
    END;

    IF res = 0 THEN
      GetReg(STATUS, s);
      IF s DIV 8 MOD 2 = 1 THEN error := 5; res := -5
      ELSIF s DIV 16 MOD 2 = 1 THEN error := 6; res := -6
      END
    END
  RETURN res
  END ReadBlock;

  PROCEDURE WriteBlock*(d: Driver.BlockDriver; blockNum: INTEGER; VAR buf: ARRAY OF BYTE): INTEGER;
    VAR track, side, sector, i, s, res: INTEGER;
  BEGIN
    error := 0; res := 0;

    track := blockNum DIV SectorsPerCyl;
    side := blockNum DIV SectorsPerTrack MOD SidesPerDisk;
    sector := blockNum MOD SectorsPerTrack + 1;

    SelectDrive(driveNum, side);

    IF ~Seek(track) THEN error := 1; res := -1 END;

    IF res = 0 THEN
      PutReg(SECTOR, sector);
      PutReg(CMD, cmdWrite);
      IF ~WaitDRQ() THEN error := 2; res := -2 END
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
      IF ~WaitNotBusy() THEN error := 4; res := -4 END
    END;

    IF res = 0 THEN
      GetReg(STATUS, s);
      IF s DIV 8 MOD 2 = 1 THEN error := 5; res := -5
      ELSIF s DIV 64 MOD 2 = 1 THEN error := 7; res := -7
      END
    END
  RETURN res
  END WriteBlock;

  (* --- Get/Set control parameters --- *)

  PROCEDURE Get*(d: Driver.BlockDriver; key: INTEGER; VAR val: INTEGER);
  BEGIN
    IF key = keyError THEN val := error
    ELSIF key = keyTrack THEN val := curTrack
    ELSE val := -1
    END
  END Get;

  PROCEDURE Set*(d: Driver.BlockDriver; key: INTEGER; val: INTEGER);
  BEGIN
    IF key = keyError THEN error := val END
  END Set;

  (* --- Initialization --- *)

  PROCEDURE Init*(drive: INTEGER; VAR drv: Driver.BlockDriver);
  BEGIN
    driveNum := drive;
    curTrack := -1;
    error := 0;
    NEW(drv);
    drv.name[0] := "F";
    drv.name[1] := "D";
    drv.name[2] := CHR(ORD("0") + drive);
    drv.name[3] := 0X;
    drv.read := ReadBlock;
    drv.write := WriteBlock;
    drv.get := Get;
    drv.set := Set
  END Init;

BEGIN
  driveNum := -1;
  curTrack := -1;
  error := 0
END FloppyDriver.
