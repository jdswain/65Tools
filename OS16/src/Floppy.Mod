MODULE Floppy; (* The floppy drives of the carrier's Intel 82077AA, card 0
   of the FPGA SoC's external bus at $0800 (model: Floppy, a
   BlockDriver): 3.5" disks of 80 tracks, 2 sides and 512 byte sectors,
   9 a track (720K), 18 (1.44M) or 36 (2.88M).

   The controller is worked by polling, without DMA or interrupts: taken
   out of reset once, SPECIFY non-DMA, CONFIGURE implied seek (so a read
   or write moves the head itself), then READ and WRITE DATA a sector at
   a time. Each drive is recalibrated, and its density found by reading
   sector 0 at each data rate in turn, the first time it is used.
   Without a terminal count a one sector transfer ends "end of
   cylinder" (ST0 $40, ST1 $80): that is success. *)
  IMPORT SYSTEM, Driver, BlockDriver;

  CONST
    (* 82077AA registers *)
    DOR  = 0802H;  (* motors 7-4, DMA gate 3, /RESET 2, drive select 1-0 *)
    MSR  = 0804H;  (* R: RQM 7, DIO 6, non-DMA execution 5, busy 4 *)
    FIFO = 0805H;
    CCR  = 0807H;  (* W: data rate *)
    rqm = 80H; dio = 40H; ndma = 20H; cb = 10H;

    (* commands *)
    cmdSpecify = 3; cmdRecalibrate = 7; cmdSenseInt = 8;
    cmdConfigure = 13H; cmdWrite = 45H; cmdRead = 46H;   (* MFM *)

    BlockSize* = BlockDriver.BlockSize;
    SidesPerDisk* = 2;
    MaxWait = 30000;   (* 816 INTEGER is 16-bit signed *)

    (* Get/Set keys *)
    keyError*  = 0;    (* the last error, below; 0 = OK *)
    keyTrack*  = 1;    (* the cylinder last read or written *)
    keySectors* = 2;   (* sectors a track: 9, 18 or 36; 0 until known *)

    (* errors *)
    errController* = 1;  (* the controller did not answer *)
    errNoDisk* = 2;      (* no disk, or none it can read *)
    errRead* = 3;        (* the sector was not read *)
    errWrite* = 4;       (* the sector was not written *)
    errProtected* = 5;   (* the disk is write protected *)

  TYPE
    Floppy* = POINTER TO FloppyDesc;
    FloppyDesc* = RECORD (BlockDriver.BlockDriverDesc)
      drive: INTEGER;      (* drive number, 0 or 1 *)
      rate: INTEGER;       (* CCR data rate of its disk *)
      spt: INTEGER;        (* sectors a track, 0: not yet known *)
      curTrack: INTEGER;   (* cylinder last used, -1: unknown *)
      error: INTEGER       (* last error code: 0 = OK *)
    END;

  VAR
    ready: BOOLEAN;        (* the controller is set up *)
    st: ARRAY 8 OF INTEGER;  (* the last result phase *)
    probe: ARRAY BlockSize OF BYTE;  (* sector 0, read to find the density *)

  (* --- Low-level register access --- *)

  PROCEDURE PutReg(reg, val: INTEGER);
    VAR b: BYTE;
  BEGIN b := val; SYSTEM.PUT(0, reg, b)
  END PutReg;

  PROCEDURE GetReg(reg: INTEGER): INTEGER;
    VAR b: BYTE; v: INTEGER;
  BEGIN SYSTEM.GET(0, reg, b); v := b
  RETURN v
  END GetReg;

  (* --- The controller --- *)

  (* until MSR AND mask = val, a bounded while *)
  PROCEDURE WaitMSR(mask, val: INTEGER): BOOLEAN;
    VAR n, m: INTEGER; ok: BOOLEAN;
  BEGIN m := 0; ok := AND(GetReg(MSR), mask) = val;
    WHILE ~ok & (m < 100) DO
      n := 0;
      WHILE ~ok & (n < MaxWait) DO ok := AND(GetReg(MSR), mask) = val; INC(n) END;
      INC(m)
    END
  RETURN ok
  END WaitMSR;

  (* a command or parameter byte *)
  PROCEDURE Cmd(v: INTEGER): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN ok := WaitMSR(rqm + dio, rqm);
    IF ok THEN PutReg(FIFO, v) END
  RETURN ok
  END Cmd;

  (* the result phase into st: how many bytes *)
  PROCEDURE Result(): INTEGER;
    VAR n: INTEGER;
  BEGIN n := 0;
    IF WaitMSR(rqm, rqm) THEN
      WHILE (n < LEN(st)) & (AND(GetReg(MSR), rqm + dio + cb) = rqm + dio + cb) DO
        st[n] := GetReg(FIFO); INC(n)
      END
    END
  RETURN n
  END Result;

  (* SENSE INTERRUPT STATUS: TRUE if an interrupt was pending *)
  PROCEDURE SenseInt(): BOOLEAN;
  BEGIN RETURN Cmd(cmdSenseInt) & (Result() = 2)
  END SenseInt;

  (* motor on and the drive selected: 1CH or 2DH *)
  PROCEDURE Select(d: Floppy);
  BEGIN PutReg(DOR, ASL(10H, d.drive) + 0CH + d.drive)
  END Select;

  (* Out of reset, collect its four ready changes, polled non-DMA
     transfers, implied seeks. *)
  PROCEDURE InitController(): BOOLEAN;
    VAR i: INTEGER; any: BOOLEAN;
  BEGIN
    PutReg(DOR, 0); PutReg(DOR, 1CH);
    i := 0; WHILE i < 4 DO any := SenseInt(); INC(i) END;
    ready := Cmd(cmdSpecify) & Cmd(0DFH) & Cmd(3)              (* 3 ms steps, non-DMA *)
      & Cmd(cmdConfigure) & Cmd(0) & Cmd(50H) & Cmd(0)         (* implied seek, no polling *)
  RETURN ready
  END InitController;

  PROCEDURE Recalibrate(d: Floppy): BOOLEAN;
    VAR n: INTEGER; ok, done: BOOLEAN;
  BEGIN
    ok := Cmd(cmdRecalibrate) & Cmd(d.drive); n := 0; done := FALSE;
    WHILE ok & ~done & (n < MaxWait) DO done := SenseInt(); INC(n) END;
    IF done THEN d.curTrack := 0 END
  RETURN ok & done
  END Recalibrate;

  (* READ or WRITE DATA of one sector, the bytes through buf *)
  PROCEDURE Transfer(d: Floppy; cmd, block: INTEGER; VAR buf: ARRAY OF BYTE): BOOLEAN;
    VAR c, h, r, i, v: INTEGER; ok: BOOLEAN;
  BEGIN
    c := block DIV (SidesPerDisk * d.spt); h := block DIV d.spt MOD SidesPerDisk; r := block MOD d.spt + 1;
    Select(d); PutReg(CCR, d.rate);
    ok := Cmd(cmd) & Cmd(h * 4 + d.drive) & Cmd(c) & Cmd(h) & Cmd(r)
      & Cmd(2) & Cmd(r) & Cmd(1BH) & Cmd(0FFH);
    i := 0;
    WHILE ok & WaitMSR(rqm, rqm) & (AND(GetReg(MSR), ndma) # 0) DO
      IF cmd = cmdRead THEN v := GetReg(FIFO); IF i < BlockSize THEN buf[i] := v END
      ELSIF i < BlockSize THEN PutReg(FIFO, buf[i])
      ELSE PutReg(FIFO, 0)
      END;
      INC(i)
    END;
    ok := ok & (Result() = 7) & (i = BlockSize) & (st[2] = 0)
      & ((AND(st[0], 0C0H) = 0) OR (AND(st[0], 0C0H) = 40H) & (st[1] = 80H));
    IF ok THEN d.curTrack := c END
  RETURN ok
  END Transfer;

  (* Set the controller up, recalibrate the drive and find its density:
     its sector 0 read at 250, 500 and 1000 kbit/s in turn. *)
  PROCEDURE Prepare(d: Floppy): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN
    IF ~ready & ~InitController() THEN d.error := errController
    ELSE
      Select(d);
      IF ~Recalibrate(d) THEN d.error := errController
      ELSE
        d.rate := 2; d.spt := 9; ok := Transfer(d, cmdRead, 0, probe);
        IF ~ok THEN d.rate := 0; d.spt := 18; ok := Transfer(d, cmdRead, 0, probe) END;
        IF ~ok THEN d.rate := 3; d.spt := 36; ok := Transfer(d, cmdRead, 0, probe) END;
        IF ~ok THEN d.spt := 0; d.error := errNoDisk END
      END
    END
  RETURN d.spt # 0
  END Prepare;

  (* --- Block I/O --- *)

  PROCEDURE (d: Floppy) ReadBlock*(blockNum: INTEGER; VAR buf: ARRAY OF BYTE): INTEGER OVERRIDE;
    VAR res: INTEGER;
  BEGIN
    d.error := 0; res := 0;
    IF (d.spt = 0) & ~Prepare(d) THEN res := -d.error
    ELSIF ~Transfer(d, cmdRead, blockNum, buf) THEN d.error := errRead; res := -errRead
    END
  RETURN res
  END ReadBlock;

  PROCEDURE (d: Floppy) WriteBlock*(blockNum: INTEGER; VAR buf: ARRAY OF BYTE): INTEGER OVERRIDE;
    VAR res: INTEGER;
  BEGIN
    d.error := 0; res := 0;
    IF (d.spt = 0) & ~Prepare(d) THEN res := -d.error
    ELSIF ~Transfer(d, cmdWrite, blockNum, buf) THEN
      IF ODD(st[1] DIV 2) THEN d.error := errProtected ELSE d.error := errWrite END;  (* ST1 NW *)
      res := -d.error
    END
  RETURN res
  END WriteBlock;

  (* --- Get/Set control parameters --- *)

  PROCEDURE (d: Floppy) Get*(key: INTEGER; VAR val: INTEGER) OVERRIDE;
  BEGIN
    IF key = keyError THEN val := d.error
    ELSIF key = keyTrack THEN val := d.curTrack
    ELSIF key = keySectors THEN val := d.spt
    ELSE val := -1
    END
  END Get;

  PROCEDURE (d: Floppy) Set*(key: INTEGER; val: INTEGER) OVERRIDE;
  BEGIN
    IF key = keyError THEN d.error := val END
  END Set;

  (* --- Creation --- *)

  (* The driver of drive 0 or 1, named FD0 or FD1. The disk is looked at
     when it is first read or written. *)
  PROCEDURE New*(drive: INTEGER): Floppy;
    VAR d: Floppy; name: ARRAY 4 OF CHAR;
  BEGIN
    NEW(d); d.drive := drive; d.rate := 2; d.spt := 0; d.curTrack := -1; d.error := 0;
    name[0] := "F"; name[1] := "D"; name[2] := CHR(ORD("0") + drive); name[3] := 0X;
    Driver.SetName(d, name);
    RETURN d
  END New;

BEGIN
  ready := FALSE
END Floppy.
