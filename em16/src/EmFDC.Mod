MODULE EmFDC; (* The WD1793 floppy disk controller with two 720K drives,
   whose disks are image files: 80 tracks, 2 sides, 9 sectors of 512
   bytes, in the order track, side, sector.

   Registers: 0 status/command, 1 track, 2 sector, 3 data, 6 drive
   status/control. A command takes effect after a few reads of a status
   register, as a real drive takes time; reads and writes then move the
   sector a byte at a time through the data register. *)

  IMPORT EmHost;

  CONST
    notReady = 80H; rnf = 10H; track0 = 4; drq = 2; busy = 1;
    delayRestore = 3; delaySeek = 3; delayRead = 2; delayWrite = 2;
    tracks = 80; sides = 2; sectors = 9; sectorSize = 512;
    (* pending operations *)
    none = 0; restore = 1; seek = 2; read = 3; write = 4;

  VAR
    status, command, track, sector, data, driveControl: INTEGER;
    drive, side: INTEGER;
    motorOn, writing: BOOLEAN;
    buf: ARRAY sectorSize OF BYTE;
    bufPos, pending, delay: INTEGER;
    mounted: ARRAY 2 OF BOOLEAN;

  PROCEDURE ClearBuf;
    VAR i: INTEGER;
  BEGIN FOR i := 0 TO sectorSize - 1 DO buf[i] := 0 END
  END ClearBuf;

  PROCEDURE Reset*;
  BEGIN
    status := 0; command := 0; track := 0; sector := 1; data := 0;
    driveControl := 0; drive := 0; side := 0; motorOn := FALSE;
    bufPos := 0; writing := FALSE; pending := none; delay := 0;
    ClearBuf
  END Reset;

  PROCEDURE Mount*(d: INTEGER; name: ARRAY OF CHAR): BOOLEAN;
    VAR r: INTEGER; ok: BOOLEAN;
  BEGIN ok := FALSE;
    IF (d >= 0) & (d <= 1) THEN
      mounted[d] := FALSE;
      r := EmHost.DiskOpen(d, name);
      IF r = 0 THEN
        EmHost.Str(EmHost.out, "WD1793: Cannot open disk image: "); EmHost.Str(EmHost.out, name)
      ELSE mounted[d] := TRUE; ok := TRUE;
        EmHost.Str(EmHost.out, "WD1793: Mounted disk "); EmHost.Int(EmHost.out, d);
        IF r = 2 THEN EmHost.Str(EmHost.out, " (read-only)") END;
        EmHost.Str(EmHost.out, ": "); EmHost.Str(EmHost.out, name)
      END;
      EmHost.Ln(EmHost.out)
    END;
    RETURN ok
  END Mount;

  (* The offset of the current sector in the image, -1 if there is none. *)
  PROCEDURE Offset(): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF (track >= tracks) OR (side >= sides) OR (sector < 1) OR (sector > sectors) THEN r := -1
    ELSE r := ((track * sides + side) * sectors + sector - 1) * sectorSize
    END;
    RETURN r
  END Offset;

  PROCEDURE DriveStatus(): INTEGER;
    VAR v: INTEGER; intrq, dataReq: BOOLEAN;
  BEGIN v := 0;
    intrq := AND(status, busy) = 0;
    dataReq := AND(status, drq) # 0;
    IF ~intrq THEN v := ORA(v, 80H) END;
    IF ~(intrq OR dataReq) THEN v := ORA(v, 40H) END;
    IF ~motorOn THEN v := ORA(v, 20H) END;
    RETURN v
  END DriveStatus;

  PROCEDURE Complete;
    VAR n, i: INTEGER;
  BEGIN
    IF pending = restore THEN track := 0; status := track0
    ELSIF pending = seek THEN track := data; status := 0;
      IF track = 0 THEN status := track0 END
    ELSIF pending = read THEN
      IF Offset() >= 0 THEN
        n := EmHost.DiskRead(drive, Offset(), buf);
        IF n < 0 THEN n := 0 END;
        FOR i := n TO sectorSize - 1 DO buf[i] := 0 END
      END;
      bufPos := 0; writing := FALSE; status := busy + drq
    ELSIF pending = write THEN
      bufPos := 0; writing := TRUE; ClearBuf; status := busy + drq
    END;
    pending := none
  END Complete;

  PROCEDURE Countdown;
  BEGIN
    IF (pending # none) & (delay > 0) THEN DEC(delay);
      IF delay = 0 THEN Complete END
    END
  END Countdown;

  PROCEDURE GetByte*(ea: INTEGER): INTEGER;
    VAR r, reg: INTEGER;
  BEGIN reg := AND(ea, 0FH); r := 0;
    IF reg = 0 THEN Countdown; r := status
    ELSIF reg = 1 THEN r := track
    ELSIF reg = 2 THEN r := sector
    ELSIF reg = 3 THEN
      IF ~writing & (AND(status, drq) # 0) THEN
        data := buf[bufPos]; INC(bufPos);
        IF bufPos >= sectorSize THEN status := AND(status, 0FFH - drq - busy) END
      END;
      r := data
    ELSIF reg = 6 THEN Countdown; r := DriveStatus()
    END;
    RETURN r
  END GetByte;

  (* Start a command that needs the drive; ready says whether it is. *)
  PROCEDURE Start(op, d: INTEGER; ready: BOOLEAN);
  BEGIN
    IF ~ready THEN status := notReady; pending := none
    ELSE status := busy; pending := op; delay := d
    END
  END Start;

  PROCEDURE StartTransfer(op, d: INTEGER);
  BEGIN
    IF ~motorOn OR ~mounted[drive] THEN status := notReady; pending := none
    ELSIF Offset() < 0 THEN status := rnf; pending := none
    ELSE status := busy; pending := op; delay := d
    END
  END StartTransfer;

  PROCEDURE Execute(cmd: INTEGER);
  BEGIN
    IF AND(cmd, 0F0H) = 0 THEN Start(restore, delayRestore, motorOn & mounted[drive])
    ELSIF AND(cmd, 0F0H) = 10H THEN Start(seek, delaySeek, motorOn & mounted[drive])
    ELSIF AND(cmd, 0E0H) = 80H THEN StartTransfer(read, delayRead)
    ELSIF AND(cmd, 0E0H) = 0A0H THEN StartTransfer(write, delayWrite)
    ELSIF AND(cmd, 0F0H) = 0D0H THEN   (* force interrupt *)
      pending := none; delay := 0;
      status := AND(status, 0FFH - busy - drq); writing := FALSE; bufPos := 0;
      IF track = 0 THEN status := ORA(status, track0) END;
      IF ~motorOn OR ~mounted[drive] THEN status := ORA(status, notReady) END
    END
  END Execute;

  PROCEDURE SetByte*(ea, val: INTEGER);
    VAR reg: INTEGER;
  BEGIN reg := AND(ea, 0FH);
    IF reg = 0 THEN command := val; Execute(val)
    ELSIF reg = 1 THEN track := val
    ELSIF reg = 2 THEN sector := val
    ELSIF reg = 3 THEN data := val;
      IF writing & (AND(status, drq) # 0) THEN
        buf[bufPos] := val; INC(bufPos);
        IF bufPos >= sectorSize THEN
          IF mounted[drive] & (Offset() >= 0) THEN EmHost.DiskWrite(drive, Offset(), buf) END;
          status := AND(status, 0FFH - drq - busy); writing := FALSE
        END
      END
    ELSIF reg = 6 THEN driveControl := val; side := AND(val, 1);
      IF AND(val, 2) # 0 THEN drive := 0 END;
      IF AND(val, 4) # 0 THEN drive := 1 END;
      motorOn := AND(val, 20H) # 0
    END
  END SetByte;

BEGIN mounted[0] := FALSE; mounted[1] := FALSE; Reset
END EmFDC.
