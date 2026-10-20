MODULE Em82077; (* The Intel 82077AA floppy disk controller of the carrier
   board (docs/Hardware.md of the Verilog repository), in PC/AT mode, with
   two 3.5" drives whose disks are image files in the order track, side,
   sector: 720K (9 sectors a track, 250 kbit/s), 1.44M (18, 500 kbit/s) or
   2.88M (36, 1 Mbit/s); 80 tracks, 2 sides, 512 byte sectors.

   Registers, card 0 of the external bus, $0800-$0807:
     2 DOR  r/w  bits 7-4 motors D-A, 3 DMA gate (enables INT),
                 2 /RESET (0 holds the controller in reset), 1-0 drive select
     3 TDR  r/w  bits 1-0, no effect
     4 MSR  r    7 RQM, 6 DIO, 5 non-DMA execution, 4 busy, 3-0 drive seeking
       DSR  w    7 software reset, 1-0 data rate (0 500K, 1 300K, 2 250K, 3 1M)
     5 FIFO r/w  commands, parameters, data and results
     7 DIR  r    7 disk changed (the selected drive)
       CCR  w    1-0 data rate
   0 and 1 (SRA, SRB, PS/2 mode only) and 6 read $FF.

   Commands: READ DATA, WRITE DATA, VERIFY, FORMAT TRACK, READ ID,
   RECALIBRATE, SEEK, RELATIVE SEEK, SENSE INTERRUPT STATUS, SENSE DRIVE
   STATUS, SPECIFY, CONFIGURE (implied seek, polling), VERSION, DUMPREG,
   LOCK, PERPENDICULAR MODE (accepted, no effect). Any other is invalid:
   one result byte, $80. The deleted data, READ TRACK and SCAN commands
   are not modelled.

   There is no DMA: transfers are polled, after SPECIFY has set ND (bit 0
   of its second byte). A read, write or format started without it ends
   at once with an overrun and a warning on standard error. In non-DMA
   execution the CPU moves each byte through the FIFO while MSR shows
   RQM, and INT is asserted while it does. With no TC (the DMA's
   terminal count) a multi-sector transfer ends after the sector EOT
   names, so a polled transfer ends as on any PC: ST0 $40 (abnormal
   termination) with ST1 $80 (end of cylinder), and the result's
   C, H and R point past the last sector.

   As on the chip: the controller is in reset until DOR bit 2 is set, and
   coming out of reset (that, or DSR bit 7) it raises INT and holds a
   ready-change status for each of the four drives, which four SENSE
   INTERRUPT STATUS commands collect unless CONFIGURE has turned polling
   off; a seek or recalibrate raises INT when it is done, for SENSE
   INTERRUPT STATUS to collect; a read or write must name the cylinder the
   head is on, unless implied seek is on; the data rate must suit the disk
   (a 1.44M image read at 250K gives "missing address mark"); DSKCHG is
   set at reset and while a drive is empty, and a step with a disk in the
   drive clears it.

   Time: a step takes SPECIFY's step rate, (16 - SRT) ms at 500K, longer
   at the slower rates, and a read, write or READ ID finds its sector
   1 ms after it is started. The bytes of a sector are there as fast as
   the CPU takes them: the FIFO never overruns. With no disk, or with the
   motor off, there is no index pulse; the chip would then wait forever,
   this ends the command with "missing address mark" instead. Not
   modelled: head load and unload times, the FIFO threshold, precompensation,
   the power down modes. *)

  IMPORT EmHost;

  CONST
    ms = 25200;                     (* cycles of the SoC's clock in a millisecond *)
    sectorSize = 512; tracks = 80; sides = 2;
    rqm = 80H; dio = 40H; ndma = 20H; cb = 10H;
    (* phases *)
    idle = 0; command = 1; waiting = 2; execRead = 3; execWrite = 4; execFormat = 5; result = 6;
    (* operations that wait for their sector *)
    opRead = 1; opWrite = 2; opVerify = 3; opFormat = 4; opReadID = 5;

  VAR
    dor, tdr, rate, srt, hut, hlt: INTEGER;
    nonDma, warned: BOOLEAN;
    eis, efifo, poll, fifothr, pretrk, lock, perp: INTEGER;
    phase, op: INTEGER;
    cmd: ARRAY 9 OF INTEGER; nCmd, need: INTEGER;
    res: ARRAY 10 OF INTEGER; nRes, resPos: INTEGER;
    intr: BOOLEAN;                  (* INT from a result phase *)
    ready: LONGINT;                 (* when a waiting operation finds its sector *)
    (* the drives *)
    pcn, spt, pendSt0: ARRAY 4 OF INTEGER;
    mounted, readOnly, changed, seeking, pend: ARRAY 4 OF BOOLEAN;
    seekEnd: ARRAY 4 OF LONGINT;
    seekTo, seekSt0: ARRAY 4 OF INTEGER;
    (* the transfer *)
    drv, head, c, h, r, n, eot, fill, sc, nextID: INTEGER;
    mt: BOOLEAN;
    buf: ARRAY sectorSize OF BYTE;
    pos: INTEGER;

  PROCEDURE Mount*(d: INTEGER; name: ARRAY OF CHAR): BOOLEAN;
    VAR k, size: INTEGER; ok: BOOLEAN;
  BEGIN ok := FALSE;
    IF (d >= 0) & (d <= 1) THEN
      mounted[d] := FALSE; changed[d] := TRUE;
      k := EmHost.DiskOpen(d, name); size := EmHost.DiskSize(d);
      IF k = 0 THEN
        EmHost.Str(EmHost.out, "82077AA: Cannot open disk image: "); EmHost.Str(EmHost.out, name)
      ELSIF (size # 737280) & (size # 1474560) & (size # 2949120) THEN
        EmHost.Str(EmHost.out, "82077AA: Not a 720K, 1.44M or 2.88M disk image: "); EmHost.Str(EmHost.out, name)
      ELSE
        mounted[d] := TRUE; readOnly[d] := k = 2; ok := TRUE;
        spt[d] := size DIV (tracks * sides * sectorSize);
        EmHost.Str(EmHost.out, "82077AA: Mounted disk "); EmHost.Int(EmHost.out, d);
        IF spt[d] = 9 THEN EmHost.Str(EmHost.out, " (720K")
        ELSIF spt[d] = 18 THEN EmHost.Str(EmHost.out, " (1.44M")
        ELSE EmHost.Str(EmHost.out, " (2.88M")
        END;
        IF readOnly[d] THEN EmHost.Str(EmHost.out, ", read-only") END;
        EmHost.Str(EmHost.out, "): "); EmHost.Str(EmHost.out, name)
      END;
      EmHost.Ln(EmHost.out)
    END;
    RETURN ok
  END Mount;

  PROCEDURE MotorOn(d: INTEGER): BOOLEAN;
    VAR m: INTEGER;
  BEGIN m := 16; WHILE d > 0 DO m := m * 2; DEC(d) END;
    RETURN ODD(dor DIV m)
  END MotorOn;

  (* the cycles a step takes at the current data rate *)
  PROCEDURE StepTime(): INTEGER;
    VAR t: INTEGER;
  BEGIN t := (16 - srt) * ms;
    IF rate = 1 THEN t := t * 5 DIV 3 ELSIF rate = 2 THEN t := t * 2 ELSIF rate = 3 THEN t := t DIV 2 END;
    RETURN t
  END StepTime;

  (* The data rate a disk is read at. *)
  PROCEDURE RateFor(d: INTEGER): INTEGER;
    VAR k: INTEGER;
  BEGIN
    IF spt[d] = 9 THEN k := 2 ELSIF spt[d] = 18 THEN k := 0 ELSE k := 3 END;
    RETURN k
  END RateFor;

  (* The controller's reset: DOR bit 2 low, or DSR bit 7. *)
  PROCEDURE Clear;
    VAR d: INTEGER;
  BEGIN phase := idle; nCmd := 0; nRes := 0; resPos := 0; intr := FALSE; op := 0;
    FOR d := 0 TO 3 DO seeking[d] := FALSE; pend[d] := FALSE END;
    IF lock = 0 THEN eis := 0; efifo := 1; poll := 0; fifothr := 0; pretrk := 0 END
  END Clear;

  (* Out of reset: four drives whose ready line changed, unless polling is off. *)
  PROCEDURE Release;
    VAR d: INTEGER;
  BEGIN Clear;
    IF poll = 0 THEN FOR d := 0 TO 3 DO pend[d] := TRUE; pendSt0[d] := 0C0H + d END END
  END Release;

  PROCEDURE Reset*;
    VAR d: INTEGER;
  BEGIN dor := 0; tdr := 0; rate := 2; srt := 8; hut := 15; hlt := 1; nonDma := FALSE;
    lock := 0; perp := 0; Clear;
    FOR d := 0 TO 3 DO pcn[d] := 0; changed[d] := TRUE END
  END Reset;

  PROCEDURE Result1(v: INTEGER);
  BEGIN res[0] := v; nRes := 1; resPos := 0; phase := result
  END Result1;

  (* the end of a read, write, verify, format or READ ID *)
  PROCEDURE Finish(st0, st1, st2: INTEGER);
  BEGIN
    res[0] := st0 + head * 4 + drv; res[1] := st1; res[2] := st2;
    res[3] := c; res[4] := h; res[5] := r; res[6] := n;
    nRes := 7; resPos := 0; phase := result; intr := TRUE; op := 0
  END Finish;

  (* Whether the drive can find sectors at all: a disk, spinning, at the
     right data rate, on a track that has them. *)
  PROCEDURE Readable(): BOOLEAN;
  BEGIN
    RETURN (drv <= 1) & mounted[drv] & MotorOn(drv) & (rate = RateFor(drv)) & (pcn[drv] < tracks)
  END Readable;

  PROCEDURE Offset(): INTEGER;
  BEGIN RETURN ((pcn[drv] * sides + head) * spt[drv] + r - 1) * sectorSize
  END Offset;

  (* The sector C H R N of the command, on the track under the head. *)
  PROCEDURE StartSector;
    VAR k, i: INTEGER;
  BEGIN
    IF ~Readable() THEN Finish(40H, 1, 0)                   (* missing address mark *)
    ELSIF c # pcn[drv] THEN Finish(40H, 4, 10H)             (* no data, wrong cylinder *)
    ELSIF (h # head) OR (r < 1) OR (r > spt[drv]) OR (n # 2) THEN Finish(40H, 4, 0)
    ELSIF op = opRead THEN
      k := EmHost.DiskRead(drv, Offset(), buf);
      IF k < 0 THEN k := 0 END;
      FOR i := k TO sectorSize - 1 DO buf[i] := 0 END;
      pos := 0; phase := execRead
    ELSIF op = opWrite THEN pos := 0; phase := execWrite
    END
  END StartSector;

  (* After a sector: the next, or the end at EOT. *)
  PROCEDURE NextSector;
  BEGIN
    IF r # eot THEN INC(r); StartSector
    ELSIF mt & (head = 0) THEN head := 1; h := h - 2 * (h MOD 2) + 1; r := 1; StartSector
    ELSE INC(c); r := 1;
      IF mt THEN h := h - 2 * (h MOD 2) + 1 END;
      Finish(40H, 80H, 0)                                   (* end of cylinder *)
    END
  END NextSector;

  PROCEDURE Verify;
  BEGIN
    WHILE op = opVerify DO
      IF ~Readable() THEN Finish(40H, 1, 0)
      ELSIF c # pcn[drv] THEN Finish(40H, 4, 10H)
      ELSIF (h # head) OR (r < 1) OR (r > spt[drv]) OR (n # 2) THEN Finish(40H, 4, 0)
      ELSIF r # eot THEN INC(r)
      ELSIF mt & (head = 0) THEN head := 1; h := h - 2 * (h MOD 2) + 1; r := 1
      ELSE INC(c); r := 1; IF mt THEN h := h - 2 * (h MOD 2) + 1 END;
        Finish(40H, 80H, 0)
      END
    END
  END Verify;

  (* A waiting operation reaches its sector. *)
  PROCEDURE Arrive;
  BEGIN
    IF op = opReadID THEN
      IF Readable() THEN c := pcn[drv]; h := head; nextID := nextID MOD spt[drv] + 1; r := nextID; n := 2;
        Finish(0, 0, 0)
      ELSE Finish(40H, 1, 0)
      END
    ELSIF op = opFormat THEN
      IF ~Readable() THEN Finish(40H, 1, 0)
      ELSIF readOnly[drv] THEN Finish(40H, 2, 0)            (* not writable *)
      ELSE pos := 0; phase := execFormat
      END
    ELSIF (op = opWrite) & Readable() & readOnly[drv] THEN Finish(40H, 2, 0)
    ELSIF op = opVerify THEN Verify
    ELSE StartSector
    END
  END Arrive;

  (* Time passes: seeks end, waiting operations find their sector. *)
  PROCEDURE Update(now: LONGINT);
    VAR d: INTEGER;
  BEGIN
    FOR d := 0 TO 3 DO
      IF seeking[d] & (now >= seekEnd[d]) THEN
        seeking[d] := FALSE; pcn[d] := seekTo[d]; pend[d] := TRUE; pendSt0[d] := seekSt0[d]
      END
    END;
    IF (phase = waiting) & (now >= ready) THEN Arrive END
  END Update;

  PROCEDURE Tick*(now: LONGINT);
  BEGIN Update(now)
  END Tick;

  PROCEDURE Irq*(): BOOLEAN;
    VAR p: BOOLEAN; d: INTEGER;
  BEGIN p := intr;
    FOR d := 0 TO 3 DO p := p OR pend[d] END;
    IF nonDma & ((phase = execRead) OR (phase = execWrite) OR (phase = execFormat)) THEN p := TRUE END;
    RETURN p & ODD(dor DIV 8) & ODD(dor DIV 4)
  END Irq;

  (* Move the head of drive d to track t; recal: a RECALIBRATE. *)
  PROCEDURE Seek(d, t: INTEGER; recal: BOOLEAN; now: LONGINT);
    VAR steps: INTEGER;
  BEGIN
    steps := t - pcn[d]; IF steps < 0 THEN steps := -steps END;
    seekSt0[d] := 20H + head * 4 + d;                       (* seek end *)
    IF recal THEN
      IF d > 1 THEN steps := 79; t := pcn[d]; seekSt0[d] := 70H + d   (* no drive: no track 0 *)
      ELSIF steps > 79 THEN steps := 79; t := pcn[d] - 79; seekSt0[d] := 70H + head * 4 + d
      END
    END;
    IF (steps > 0) & (d <= 1) & mounted[d] THEN changed[d] := FALSE END;
    seekTo[d] := t; seeking[d] := TRUE; pend[d] := FALSE;
    seekEnd[d] := now + steps * StepTime() + ms DIV 10
  END Seek;

  PROCEDURE Bytes(k: INTEGER): INTEGER;
    VAR b: INTEGER;
  BEGIN
    IF (AND(k, 1FH) = 6) OR (AND(k, 3FH) = 5) OR (AND(k, 1FH) = 16H) THEN b := 9
    ELSIF AND(k, 0BFH) = 0DH THEN b := 6
    ELSIF (k = 3) OR (k = 0FH) OR (AND(k, 0BFH) = 8FH) THEN b := 3
    ELSIF k = 13H THEN b := 4
    ELSIF (AND(k, 0BFH) = 0AH) OR (k = 7) OR (k = 4) OR (k = 12H) THEN b := 2
    ELSIF (k = 8) OR (k = 10H) OR (k = 0EH) OR (AND(k, 7FH) = 14H) THEN b := 1
    ELSE b := 0
    END;
    RETURN b
  END Bytes;

  (* read, write, verify, format, READ ID: off to find the sector *)
  PROCEDURE Begin(o: INTEGER; now: LONGINT);
  BEGIN op := o; ready := now + ms;
    IF (o = opRead) OR (o = opWrite) OR (o = opVerify) THEN
      mt := cmd[0] >= 80H; c := cmd[2]; h := cmd[3]; r := cmd[4]; n := cmd[5]; eot := cmd[6];
      IF (eis = 1) & (c # pcn[drv]) & (drv <= 1) THEN
        ready := ready + ABS(c - pcn[drv]) * StepTime(); pcn[drv] := c;
        IF mounted[drv] THEN changed[drv] := FALSE END
      END
    ELSE c := pcn[drv]; h := head; r := 1; n := 2
    END;
    IF o = opFormat THEN n := cmd[2]; sc := cmd[3]; fill := cmd[5] END;
    IF ~nonDma & (o # opVerify) & (o # opReadID) THEN
      IF ~warned THEN warned := TRUE;
        EmHost.Str(EmHost.err, "82077AA: DMA is not emulated; set ND with SPECIFY for polled transfers");
        EmHost.Ln(EmHost.err)
      END;
      Finish(40H, 10H, 0)                                   (* overrun *)
    ELSE phase := waiting
    END
  END Begin;

  PROCEDURE Execute(now: LONGINT);
    VAR k, d, t: INTEGER;
  BEGIN k := cmd[0]; phase := idle;
    IF need > 1 THEN drv := AND(cmd[1], 3); head := AND(cmd[1] DIV 4, 1) END;
    IF AND(k, 1FH) = 6 THEN Begin(opRead, now)
    ELSIF AND(k, 3FH) = 5 THEN Begin(opWrite, now)
    ELSIF AND(k, 1FH) = 16H THEN Begin(opVerify, now)
    ELSIF AND(k, 0BFH) = 0DH THEN Begin(opFormat, now)
    ELSIF AND(k, 0BFH) = 0AH THEN Begin(opReadID, now)
    ELSIF k = 3 THEN srt := cmd[1] DIV 16; hut := AND(cmd[1], 15); hlt := cmd[2] DIV 2; nonDma := ODD(cmd[2])
    ELSIF k = 4 THEN
      t := 28H + head * 4 + drv;                            (* ready, two sided *)
      IF pcn[drv] = 0 THEN t := t + 10H END;
      IF (drv <= 1) & mounted[drv] & readOnly[drv] THEN t := t + 40H END;
      Result1(t)
    ELSIF k = 7 THEN head := 0; Seek(drv, 0, TRUE, now)
    ELSIF k = 0FH THEN Seek(drv, cmd[2], FALSE, now)
    ELSIF AND(k, 0BFH) = 8FH THEN
      IF ODD(k DIV 40H) THEN t := pcn[drv] + cmd[2] ELSE t := pcn[drv] - cmd[2] END;
      IF t < 0 THEN t := 0 ELSIF t > 255 THEN t := 255 END;
      Seek(drv, t, FALSE, now)
    ELSIF k = 8 THEN
      d := 0; WHILE (d < 4) & ~pend[d] DO INC(d) END;
      IF d = 4 THEN Result1(80H)
      ELSE pend[d] := FALSE; res[0] := pendSt0[d]; res[1] := pcn[d]; nRes := 2; resPos := 0; phase := result
      END
    ELSIF k = 13H THEN
      eis := AND(cmd[2] DIV 40H, 1); efifo := AND(cmd[2] DIV 20H, 1); poll := AND(cmd[2] DIV 10H, 1);
      fifothr := AND(cmd[2], 15); pretrk := cmd[3]
    ELSIF k = 10H THEN Result1(90H)
    ELSIF k = 0EH THEN
      FOR d := 0 TO 3 DO res[d] := pcn[d] END;
      res[4] := srt * 16 + hut; res[5] := hlt * 2; res[6] := eot;
      IF nonDma THEN INC(res[5]) END;
      res[7] := lock * 80H + AND(perp, 3FH);
      res[8] := eis * 40H + efifo * 20H + poll * 10H + fifothr; res[9] := pretrk;
      nRes := 10; resPos := 0; phase := result
    ELSIF AND(k, 7FH) = 14H THEN lock := k DIV 80H; Result1(lock * 10H)
    ELSIF k = 12H THEN perp := cmd[1]
    END
  END Execute;

  PROCEDURE MSR(): INTEGER;
    VAR v, d, m: INTEGER;
  BEGIN v := 0;
    IF ODD(dor DIV 4) THEN
      IF phase = idle THEN v := rqm
      ELSIF phase = command THEN v := rqm + cb
      ELSIF phase = waiting THEN v := cb
      ELSIF phase = execRead THEN v := rqm + dio + cb
      ELSIF (phase = execWrite) OR (phase = execFormat) THEN v := rqm + cb
      ELSIF phase = result THEN v := rqm + dio + cb
      END;
      IF nonDma & (phase >= waiting) & (phase <= execFormat) THEN v := v + ndma END;
      m := 1;
      FOR d := 0 TO 3 DO IF seeking[d] THEN v := v + m END; m := m * 2 END
    END;
    RETURN v
  END MSR;

  PROCEDURE ReadFIFO(): INTEGER;
    VAR v: INTEGER;
  BEGIN v := 0;
    IF phase = result THEN
      v := res[resPos]; INC(resPos); intr := FALSE;
      IF resPos >= nRes THEN phase := idle END
    ELSIF phase = execRead THEN
      v := buf[pos]; INC(pos);
      IF pos = sectorSize THEN NextSector END
    END;
    RETURN v
  END ReadFIFO;

  PROCEDURE WriteFIFO(v: INTEGER; now: LONGINT);
    VAR i: INTEGER;
  BEGIN
    IF (phase = idle) OR (phase = command) THEN
      IF phase = idle THEN
        cmd[0] := v; nCmd := 1; need := Bytes(v);
        IF need = 0 THEN Result1(80H) ELSE phase := command END
      ELSE cmd[nCmd] := v; INC(nCmd)
      END;
      IF (phase = command) & (nCmd = need) THEN Execute(now) END
    ELSIF phase = execWrite THEN
      buf[pos] := v; INC(pos);
      IF pos = sectorSize THEN EmHost.DiskWrite(drv, Offset(), buf); NextSector END
    ELSIF phase = execFormat THEN
      cmd[1 + pos MOD 4] := v; INC(pos);
      IF pos MOD 4 = 0 THEN                                 (* an ID: C H R N *)
        c := cmd[1]; h := cmd[2]; r := cmd[3]; n := cmd[4];
        IF (c = pcn[drv]) & (r >= 1) & (r <= spt[drv]) THEN
          FOR i := 0 TO sectorSize - 1 DO buf[i] := fill END;
          EmHost.DiskWrite(drv, Offset(), buf)
        END;
        IF pos DIV 4 = sc THEN Finish(0, 0, 0) END
      END
    END
  END WriteFIFO;

  PROCEDURE Read*(reg: INTEGER; now: LONGINT): INTEGER;
    VAR v: INTEGER;
  BEGIN reg := AND(reg, 7); Update(now);
    IF reg = 2 THEN v := dor
    ELSIF reg = 3 THEN v := AND(tdr, 3)
    ELSIF reg = 4 THEN v := MSR()
    ELSIF reg = 5 THEN IF ODD(dor DIV 4) THEN v := ReadFIFO() ELSE v := 0 END
    ELSIF reg = 7 THEN
      IF changed[AND(dor, 3)] OR (AND(dor, 3) > 1) OR ~mounted[AND(dor, 3)] THEN v := 80H ELSE v := 0 END
    ELSE v := 0FFH
    END;
    RETURN v
  END Read;

  (* A register as Read gives it, but changing nothing: for the trace. *)
  PROCEDURE Peek*(reg: INTEGER): INTEGER;
    VAR v: INTEGER;
  BEGIN reg := AND(reg, 7);
    IF reg = 5 THEN v := 0;
      IF ODD(dor DIV 4) & (phase = result) THEN v := res[resPos]
      ELSIF ODD(dor DIV 4) & (phase = execRead) THEN v := buf[pos]
      END
    ELSIF reg = 2 THEN v := dor
    ELSIF reg = 3 THEN v := AND(tdr, 3)
    ELSIF reg = 4 THEN v := MSR()
    ELSIF reg = 7 THEN
      IF changed[AND(dor, 3)] OR (AND(dor, 3) > 1) OR ~mounted[AND(dor, 3)] THEN v := 80H ELSE v := 0 END
    ELSE v := 0FFH
    END;
    RETURN v
  END Peek;

  PROCEDURE Write*(reg, v: INTEGER; now: LONGINT);
    VAR old: INTEGER;
  BEGIN reg := AND(reg, 7); Update(now);
    IF reg = 2 THEN old := dor; dor := v;
      IF ~ODD(v DIV 4) THEN Clear
      ELSIF ~ODD(old DIV 4) THEN Release
      END
    ELSIF reg = 3 THEN tdr := v
    ELSIF reg = 4 THEN rate := AND(v, 3); IF v >= 80H THEN Release END
    ELSIF reg = 5 THEN IF ODD(dor DIV 4) THEN WriteFIFO(v, now) END
    ELSIF reg = 7 THEN rate := AND(v, 3)
    END
  END Write;

BEGIN mounted[0] := FALSE; mounted[1] := FALSE; mounted[2] := FALSE; mounted[3] := FALSE;
  spt[0] := 18; spt[1] := 18; spt[2] := 18; spt[3] := 18; warned := FALSE; nextID := 0; Reset
END Em82077.
