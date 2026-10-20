MODULE SCSIManager; (* The SCSI bus (model: SCSIManager, a BusDriver): the
   53C80 of the carrier's Z85C80, card 3 of the SoC's external bus at
   $0830, worked by programmed I/O as the initiator at ID 7.

   Command runs one command on a target: arbitration, selection with ATN,
   IDENTIFY (LUN 0), then whatever phase the target asks for, a byte at a
   time by REQ and ACK, until it releases the bus: the command, the data
   in or out, the status and COMMAND COMPLETE. Reset resets the bus and
   asks each target what it is (INQUIRY); a SCSIDisk is made for a disk,
   a DiskPartition for each of its partitions. *)

  IMPORT SYSTEM, Driver, BusDriver;

  CONST
    (* 53C80 registers *)
    ODR = 0830H;   (* W: output data; R: current SCSI data *)
    ICR = 0831H;   (* initiator command *)
    MR  = 0832H;   (* mode *)
    TCR = 0833H;   (* target command: the phase expected *)
    CSB = 0834H;   (* R: current SCSI bus status; W: select enable *)
    BSR = 0835H;   (* R: bus and status *)
    RPI = 0837H;   (* R: reset parity/interrupt *)
    (* ICR bits *)
    icrDB = 1; icrATN = 2; icrSEL = 4; icrBSY = 8; icrACK = 10H; icrLA = 20H; icrAIP = 40H; icrRST = 80H;
    (* CSB bits *)
    csbBSY = 40H; csbREQ = 20H; csbPhase = 1CH;   (* MSG, C/D, I/O *)
    (* phases, as CSB has them *)
    phDataOut = 0; phDataIn = 4; phCommand = 8; phStatus = 0CH; phMsgOut = 18H; phMsgIn = 1CH;
    ownID = 80H;   (* ID 7 *)

    MaxTargets* = 7;   (* IDs 0 to 6 *)
    MaxWait = 30000;
    (* Command's errors, negative; 0 and above is the status byte *)
    errNoTarget* = -1;   (* nothing answered the selection *)
    errBus* = -2;        (* the bus was not free, or a target stopped answering *)
    (* status bytes *)
    Good* = 0; CheckCondition* = 2; Busy* = 8;
    (* INQUIRY peripheral device types *)
    typeDisk* = 0; typeNone* = -1;

  TYPE
    SCSIManager* = POINTER TO SCSIManagerDesc;
    SCSIManagerDesc* = RECORD (BusDriver.BusDriverDesc)
      types*: ARRAY MaxTargets OF INTEGER   (* each target's device type, typeNone: none; set by Reset *)
    END;

  PROCEDURE Put(reg, val: INTEGER);
    VAR b: BYTE;
  BEGIN b := val; SYSTEM.PUT(0, reg, b)
  END Put;

  PROCEDURE Get(reg: INTEGER): INTEGER;
    VAR b: BYTE; v: INTEGER;
  BEGIN SYSTEM.GET(0, reg, b); v := b
  RETURN v
  END Get;

  (* until AND(reg, mask) = val, a bounded while *)
  PROCEDURE Wait(reg, mask, val: INTEGER): BOOLEAN;
    VAR n: INTEGER; ok: BOOLEAN;
  BEGIN n := 0; ok := AND(Get(reg), mask) = val;
    WHILE ~ok & (n < MaxWait) DO ok := AND(Get(reg), mask) = val; INC(n) END
  RETURN ok
  END Wait;

  (* until the target asks for a byte (TRUE) or has released the bus *)
  PROCEDURE NextPhase(): BOOLEAN;
    VAR n, v: INTEGER;
  BEGIN n := 0; v := AND(Get(CSB), csbREQ + csbBSY);
    WHILE (v = csbBSY) & (n < MaxWait) DO v := AND(Get(CSB), csbREQ + csbBSY); INC(n) END
  RETURN v = csbREQ + csbBSY
  END NextPhase;

  (* Arbitrate as ID 7 and select target t with ATN, leaving ATN asserted:
     0, or an error. *)
  PROCEDURE Select(t: INTEGER): INTEGER;
    VAR res: INTEGER;
  BEGIN
    res := 0;
    Put(TCR, 0); Put(ICR, 0); Put(ODR, ownID);
    IF ~Wait(CSB, csbBSY, 0) THEN res := errBus
    ELSE
      Put(MR, 1);                                         (* arbitrate *)
      IF ~Wait(ICR, icrAIP, icrAIP) OR (AND(Get(ICR), icrLA) # 0) THEN res := errBus
      ELSE
        Put(ICR, icrSEL + icrBSY);
        Put(ODR, ownID + ASL(1, t));
        Put(ICR, icrDB + icrATN + icrSEL + icrBSY);
        Put(MR, 0);
        Put(ICR, icrDB + icrATN + icrSEL);                (* BSY released: selecting *)
        IF ~Wait(CSB, csbBSY, csbBSY) THEN res := errNoTarget END;
        Put(ICR, icrATN)                                  (* SEL and the data bus released *)
      END
    END;
    Put(MR, 0)
  RETURN res
  END Select;

  (* A byte out in the current phase; atn: ATN held on after it. *)
  PROCEDURE SendByte(b: INTEGER; atn: BOOLEAN): BOOLEAN;
    VAR a: INTEGER; ok: BOOLEAN;
  BEGIN
    IF atn THEN a := icrATN ELSE a := 0 END;
    Put(ODR, b); Put(ICR, a + icrDB); Put(ICR, a + icrDB + icrACK);
    ok := Wait(CSB, csbREQ, 0);
    Put(ICR, a)
  RETURN ok
  END SendByte;

  (* A byte in in the current phase. *)
  PROCEDURE ReceiveByte(VAR b: INTEGER): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN
    b := Get(ODR); Put(ICR, icrACK);
    ok := Wait(CSB, csbREQ, 0);
    Put(ICR, 0)
  RETURN ok
  END ReceiveByte;

  (* Run the n byte command cdb on target t, the data in or out through
     data (at most len bytes moved; the rest the target asks for is padded
     or dropped): the status byte, or an error. *)
  PROCEDURE (b: SCSIManager) Command*(t: INTEGER; VAR cdb: ARRAY OF BYTE; n: INTEGER;
                                     VAR data: ARRAY OF BYTE; len: INTEGER): INTEGER;
    VAR res, phase, ci, di, v: INTEGER; ok, idSent: BOOLEAN;
  BEGIN
    res := Select(t);
    IF res = 0 THEN
      res := errBus; ok := TRUE; ci := 0; di := 0; idSent := FALSE;
      WHILE ok & NextPhase() DO
        phase := AND(Get(CSB), csbPhase);
        Put(TCR, phase DIV 4);                            (* phase match *)
        IF phase = phMsgOut THEN
          IF idSent THEN ok := SendByte(8, FALSE)         (* NO OPERATION *)
          ELSE ok := SendByte(80H, FALSE); idSent := TRUE (* IDENTIFY, LUN 0 *)
          END
        ELSIF phase = phCommand THEN
          IF ci < n THEN v := cdb[ci] ELSE v := 0 END;
          ok := SendByte(v, FALSE); INC(ci)
        ELSIF phase = phDataOut THEN
          IF di < len THEN v := data[di] ELSE v := 0 END;
          ok := SendByte(v, FALSE); INC(di)
        ELSIF phase = phDataIn THEN
          ok := ReceiveByte(v);
          IF di < len THEN data[di] := v END; INC(di)
        ELSIF phase = phStatus THEN ok := ReceiveByte(res)
        ELSIF phase = phMsgIn THEN ok := ReceiveByte(v)   (* COMMAND COMPLETE, or one ignored *)
        ELSE ok := FALSE
        END
      END;
      IF ~ok THEN res := errBus END;
      Put(ICR, 0); Put(TCR, 0)
    END
  RETURN res
  END Command;

  (* INQUIRY: target t's peripheral device type, typeNone if nothing is there *)
  PROCEDURE Inquire(b: SCSIManager; t: INTEGER): INTEGER;
    VAR cdb: ARRAY 6 OF BYTE; data: ARRAY 36 OF BYTE; i, type: INTEGER;
  BEGIN
    FOR i := 0 TO 5 DO cdb[i] := 0 END; cdb[0] := 12H; cdb[4] := 36;
    FOR i := 0 TO 35 DO data[i] := 0 END;
    type := typeNone;
    IF b.Command(t, cdb, 6, data, 36) = Good THEN
      IF data[0] # 7FH THEN type := AND(data[0], 1FH) END   (* 7FH: no such LUN *)
    END
  RETURN type
  END Inquire;

  (* Reset the bus and find what is on it. *)
  PROCEDURE (b: SCSIManager) Reset* OVERRIDE;
    VAR t, i: INTEGER;
  BEGIN
    Put(MR, 0); Put(TCR, 0);
    Put(ICR, icrRST); i := 0; WHILE i < 100 DO INC(i) END; Put(ICR, 0);
    t := Get(RPI);                                        (* the reset's interrupt cleared *)
    FOR t := 0 TO MaxTargets - 1 DO b.types[t] := Inquire(b, t) END
  END Reset;

  (* The bus, reset and scanned. *)
  PROCEDURE New*(): SCSIManager;
    VAR b: SCSIManager;
  BEGIN NEW(b); Driver.SetName(b, "SCSI"); b.Reset
  RETURN b
  END New;

END SCSIManager.
