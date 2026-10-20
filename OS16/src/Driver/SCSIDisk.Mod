MODULE SCSIDisk; (* A disk on the SCSI bus, all of it (model: SCSIDisk, a
   BlockDriver): its blocks by READ(10) and WRITE(10) through the
   SCSIManager of its bus, its size by READ CAPACITY. Its partitions are
   DiskPartitions on it.

   A CHECK CONDITION is answered with REQUEST SENSE and the command tried
   once more: a disk reports UNIT ATTENTION to the first command after a
   reset. *)

  IMPORT Driver, BlockDriver, SCSIManager;

  CONST
    BlockSize = BlockDriver.BlockSize;
    (* sense keys *)
    senseNotReady = 2; senseProtect = 7;

  TYPE
    SCSIDisk* = POINTER TO SCSIDiskDesc;
    SCSIDiskDesc* = RECORD (BlockDriver.BlockDriverDesc)
      bus*: SCSIManager.SCSIManager;
      target*: INTEGER;   (* its SCSI ID *)
      blocks: LONGINT;    (* from READ CAPACITY; 0: not known *)
      sense: INTEGER      (* the sense key of the last CHECK CONDITION *)
    END;

  VAR none: ARRAY 1 OF BYTE;

  (* REQUEST SENSE: the sense key *)
  PROCEDURE Sense(d: SCSIDisk): INTEGER;
    VAR cdb: ARRAY 6 OF BYTE; data: ARRAY 18 OF BYTE; i, key: INTEGER;
  BEGIN
    FOR i := 0 TO 5 DO cdb[i] := 0 END; cdb[0] := 3; cdb[4] := 18;
    FOR i := 0 TO 17 DO data[i] := 0 END;
    IF d.bus.Command(d.target, cdb, 6, data, 18) = SCSIManager.Good THEN key := AND(data[2], 0FH)
    ELSE key := -1
    END
  RETURN key
  END Sense;

  (* the command, tried again after a CHECK CONDITION: 0, or an error *)
  PROCEDURE Run(d: SCSIDisk; VAR cdb: ARRAY OF BYTE; n: INTEGER; VAR data: ARRAY OF BYTE; len: INTEGER): INTEGER;
    VAR st, tries, res: INTEGER;
  BEGIN
    tries := 0;
    REPEAT
      st := d.bus.Command(d.target, cdb, n, data, len); INC(tries);
      IF st = SCSIManager.CheckCondition THEN d.sense := Sense(d) END
    UNTIL (st # SCSIManager.CheckCondition) OR (tries = 2);
    IF st = SCSIManager.Good THEN res := 0
    ELSIF st < 0 THEN res := -BlockDriver.errMedium
    ELSIF (st = SCSIManager.CheckCondition) & (d.sense = senseProtect) THEN res := -BlockDriver.errProtected
    ELSIF (st = SCSIManager.CheckCondition) & (d.sense = senseNotReady) THEN res := -BlockDriver.errMedium
    ELSE res := -BlockDriver.errIO
    END
  RETURN res
  END Run;

  (* a 10 byte READ or WRITE of block n *)
  PROCEDURE Transfer(d: SCSIDisk; op: INTEGER; n: LONGINT; VAR buf: ARRAY OF BYTE): INTEGER;
    VAR cdb: ARRAY 10 OF BYTE; i, res: INTEGER;
  BEGIN
    IF (n < 0) OR (n >= d.Blocks()) THEN res := -BlockDriver.errRange
    ELSE
      FOR i := 0 TO 9 DO cdb[i] := 0 END;
      cdb[0] := op;
      cdb[2] := n DIV 1000000H MOD 100H; cdb[3] := n DIV 10000H MOD 100H;
      cdb[4] := n DIV 100H MOD 100H; cdb[5] := n MOD 100H;
      cdb[8] := 1;                                        (* one block *)
      res := Run(d, cdb, 10, buf, BlockSize)
    END
  RETURN res
  END Transfer;

  PROCEDURE (d: SCSIDisk) ReadBlock*(n: LONGINT; VAR buf: ARRAY OF BYTE): INTEGER OVERRIDE;
  BEGIN RETURN Transfer(d, 28H, n, buf)
  END ReadBlock;

  PROCEDURE (d: SCSIDisk) WriteBlock*(n: LONGINT; VAR buf: ARRAY OF BYTE): INTEGER OVERRIDE;
  BEGIN RETURN Transfer(d, 2AH, n, buf)
  END WriteBlock;

  (* READ CAPACITY, the first time: its last block + 1 *)
  PROCEDURE (d: SCSIDisk) Blocks*(): LONGINT OVERRIDE;
    VAR cdb: ARRAY 10 OF BYTE; data: ARRAY 8 OF BYTE; i: INTEGER; last: LONGINT;
  BEGIN
    IF d.blocks = 0 THEN
      FOR i := 0 TO 9 DO cdb[i] := 0 END; cdb[0] := 25H;
      FOR i := 0 TO 7 DO data[i] := 0 END;
      IF Run(d, cdb, 10, data, 8) = 0 THEN
        last := 0;
        FOR i := 0 TO 3 DO last := last * 100H + data[i] END;
        d.blocks := last + 1
      END
    END
  RETURN d.blocks
  END Blocks;

  (* The disk at ID target on bus, named SD and its ID; NIL if no disk is
     there (Reset found none) or it does not answer. *)
  PROCEDURE New*(bus: SCSIManager.SCSIManager; target: INTEGER): SCSIDisk;
    VAR d: SCSIDisk; cdb: ARRAY 6 OF BYTE; i: INTEGER; name: ARRAY 4 OF CHAR;
  BEGIN
    d := NIL;
    IF (target >= 0) & (target < SCSIManager.MaxTargets) & (bus.types[target] = SCSIManager.typeDisk) THEN
      NEW(d); d.bus := bus; d.target := target; d.blocks := 0; d.sense := 0;
      name[0] := "S"; name[1] := "D"; name[2] := CHR(ORD("0") + target); name[3] := 0X;
      Driver.SetName(d, name);
      FOR i := 0 TO 5 DO cdb[i] := 0 END;                 (* TEST UNIT READY: clears UNIT ATTENTION *)
      IF (Run(d, cdb, 6, none, 0) # 0) OR (d.Blocks() = 0) THEN d := NIL END
    END
  RETURN d
  END New;

END SCSIDisk.
