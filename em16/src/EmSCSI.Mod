MODULE EmSCSI; (* The SCSI half of the carrier board's Z85C80, a 53C80
   (5380), with one disk on the bus at ID 0 whose blocks are an image
   file of 512 byte blocks: what is in the file, from block 0, as with no
   partition map a FAT volume made by hdiutil (tools/mkdisk.sh).

   Registers at $0830-$0837, the 5380's:
     read                           write
     0 current SCSI data            output data
     1 initiator command            initiator command
     2 mode                         mode
     3 target command               target command
     4 current SCSI bus status      select enable
     5 bus and status               start DMA send
     6 input data                   start DMA target receive
     7 reset parity/interrupt       start DMA initiator receive

   The initiator is the 53C80, ID 7 by convention, and works the bus a
   signal at a time as a polled driver does: arbitration (mode bit 0,
   then AIP and LA in the initiator command register), selection (the
   IDs on the data bus, SEL, BSY released), then each byte by REQ and
   ACK, the phase read from the bus status register and copied to the
   target command register so that "phase match" holds.

   DMA (EmDMA's channel 0): with mode bit 1 set, a write to register 5
   starts a DMA send and one to register 7 a DMA initiator receive
   (register 6, target receive, is accepted and does nothing). DRQ (Drq)
   then asks for each byte while the target asserts REQ in the phase the
   target command register names; the engine's /DACK cycles, DackRead and
   DackWrite, take or give the byte and the chip does the REQ/ACK
   handshake itself. The CPU's accesses to slot 4 ($0840, pseudo-DMA) are
   the same cycles without EOP. EOP (the engine's TC) with a byte sets End
   of DMA (bus and status bit 7) and interrupts if mode bit 3 is set; so
   does the target asking in another phase while DMA is still on (phase
   mismatch: a short transfer). Clearing mode bit 1 ends DMA and clears
   End of DMA. The target command register's bit 7 (last byte sent) is set
   once a send's EOP byte has gone across, which here is at once, and
   cleared with mode bit 1.

   The interrupt (bus and status bit 4, cleared by reading register 7)
   comes from a SCSI bus reset, and from the loss of BSY while mode bit 2
   (monitor busy) is set, which also sets busy error.

   The disk answers a selection at once and takes no time: REQ follows
   ACK's release in the same instant. It goes from selection to MESSAGE
   OUT if ATN is asserted (IDENTIFY sets the LUN, ABORT and BUS DEVICE
   RESET are obeyed, other messages are ignored), then COMMAND, the data,
   STATUS and MESSAGE IN (COMMAND COMPLETE), and releases the bus.
   Commands: TEST UNIT READY, REQUEST SENSE, FORMAT UNIT (nothing to do),
   READ(6), WRITE(6), INQUIRY, MODE SELECT(6) (ignored), MODE SENSE(6)
   (header and block descriptor), START STOP UNIT, PREVENT ALLOW MEDIUM
   REMOVAL, READ CAPACITY, READ(10), WRITE(10), VERIFY(10) and
   SYNCHRONIZE CACHE. Any other gets CHECK CONDITION, ILLEGAL REQUEST.
   As a real disk does, it reports UNIT ATTENTION (power on or reset) to
   the first command after power on or a bus reset other than INQUIRY
   and REQUEST SENSE.

   With -scsitiming (SetTiming, under -fpga) the disk takes the time a
   3.5 inch drive of about 1990 takes (round figures of the Quantum
   ProDrive LPS's time, not one drive's datasheet): REQ comes when the
   drive would assert it, not at once. Its geometry is 32 sectors a track and 4 heads (128 blocks a
   cylinder; 320 cylinders for 20 MB), turning at 3600 rpm: a sector every
   0.52 ms, about 1 MB/s off the platters. A seek of d cylinders takes
   3 ms + 27 ms * sqrt(d / cylinders): 4.5 ms to the next, 19 ms a third
   of the way over, 30 ms all the way. Each command takes 0.5 ms of the
   controller's before its first REQ of data or status. A read waits for
   the seek and for its first block to come round, and each block is
   sent once it has been read into the buffer; the drive reads on into
   the buffer behind the blocks asked for, up to 128 blocks (64K) more, so
   a read that follows on is served from the buffer, at the bus's speed.
   Crossing to the next cylinder takes a track to track seek (the
   cylinders skewed for it); the next head nothing. A write takes its
   blocks into the buffer as fast as they come, then writes them, the
   seek overlapping the transfer, and sends STATUS only once they are on
   the platters (no write cache); it empties the read buffer. After power
   on the drive answers no selection for 1 s and is NOT READY (2, 04h,
   01h: becoming ready) to TEST UNIT READY, READ CAPACITY and the media
   commands until it has spun up, 5 s after power on; START UNIT without
   Immed waits for it. A bus reset does not spin it down. The time comes
   from the system (Tick), as monotonic system clock cycles. *)

  IMPORT EmHost;

  CONST
    image = 2;                      (* EmHost's disk number *)
    blockSize = 512; idBit = 1;       (* ID 0 on the data bus *)
    ioL = 4;                        (* the phase lines, MSG C/D I/O, as register 4 has them *)
    phDataOut = 0; phDataIn = 4; phCommand = 8; phStatus = 0CH; phMsgOut = 18H; phMsgIn = 1CH;
    free = 0; selected = 1; transfer = 2;
    (* what the data phase moves *)
    xNone = 0; xBuffer = 1; xRead = 2; xWrite = 3; xDiscard = 4;
    good = 0; checkCondition = 2;
    (* -scsitiming: the drive's geometry and read-ahead *)
    spt = 32; heads = 4; bpc = 128;   (* bpc: spt * heads *)
    raMax = 128;

  VAR
    odr, icr, mode, tcr, ser: INTEGER;
    aip, irq, busyErr: BOOLEAN;
    dmaSend, dmaRecv, endDma, lastSent: BOOLEAN;
    (* the disk *)
    mounted, readOnly, unitAttention, identified, acked: BOOLEAN;
    blocks, state, phase, out, lun: INTEGER;
    req: BOOLEAN;
    cdb: ARRAY 12 OF INTEGER; nCdb, cdbLen: INTEGER;
    data: ARRAY blockSize OF BYTE; dataLen, dataPos: INTEGER;
    xfer, lba, count, status: INTEGER;
    senseKey, asc, ascq: INTEGER;
    (* -scsitiming *)
    timed: BOOLEAN;
    t: LONGINT;                     (* the time, the system clock's cycles, as last told *)
    pend: BOOLEAN; reqAt: LONGINT;  (* REQ to be asserted at reqAt *)
    due: LONGINT;                   (* no REQ before it *)
    cmdT: LONGINT;                  (* the command's last byte *)
    rev, secT, ovh, settle, stroke, t2t, selAt, readyAt: LONGINT;
    cyls, cyl: INTEGER;             (* the cylinders; the one the heads are on *)
    (* the read buffer: blocks lo..hb, hb read at ht, the drive reading on to
       lim; resume: it had stopped, and reads on from resumeAt *)
    valid, resume: BOOLEAN;
    lo, hb, lim: INTEGER; ht, resumeAt: LONGINT;
    wLba, wCount: INTEGER;          (* the write's blocks *)

  (* -scsitiming: the disk takes a real drive's time *)
  PROCEDURE SetTiming*;
  BEGIN timed := TRUE
  END SetTiming;

  PROCEDURE Mount*(name: ARRAY OF CHAR): BOOLEAN;
    VAR k, size: INTEGER;
  BEGIN mounted := FALSE;
    k := EmHost.DiskOpen(image, name); size := EmHost.DiskSize(image);
    IF k = 0 THEN EmHost.Str(EmHost.out, "SCSI: Cannot open disk image: "); EmHost.Str(EmHost.out, name)
    ELSIF size < blockSize THEN EmHost.Str(EmHost.out, "SCSI: Disk image too small: "); EmHost.Str(EmHost.out, name)
    ELSE mounted := TRUE; readOnly := k = 2; blocks := size DIV blockSize;
      EmHost.Str(EmHost.out, "SCSI: Mounted disk at ID 0 ("); EmHost.Int(EmHost.out, blocks);
      EmHost.Str(EmHost.out, " blocks");
      IF readOnly THEN EmHost.Str(EmHost.out, ", read-only") END;
      EmHost.Str(EmHost.out, "): "); EmHost.Str(EmHost.out, name)
    END;
    EmHost.Ln(EmHost.out);
    RETURN mounted
  END Mount;

  (* --- the disk --- *)

  PROCEDURE Sense(key, code: INTEGER);
  BEGIN senseKey := key; asc := code; ascq := 0
  END Sense;

  PROCEDURE BusFree;
  BEGIN
    IF (state # free) & ODD(mode DIV 4) & ~ODD(icr DIV 8) THEN busyErr := TRUE; irq := TRUE END;
    state := free; req := FALSE; pend := FALSE; phase := 0; acked := FALSE
  END BusFree;

  PROCEDURE DiskReset;
  BEGIN state := free; req := FALSE; pend := FALSE; phase := 0; acked := FALSE;
    unitAttention := TRUE; Sense(0, 0)
  END DiskReset;

  (* The target asks for a byte in phase ph: REQ at once, or with
     -scsitiming no sooner than due. *)
  PROCEDURE Request(ph, byte: INTEGER);
  BEGIN phase := ph; out := byte;
    IF timed & (due > t) THEN req := FALSE; pend := TRUE; reqAt := due ELSE req := TRUE; pend := FALSE END
  END Request;

  (* --- the drive's time, with -scsitiming --- *)

  PROCEDURE ISqrt(n: LONGINT): LONGINT;
    VAR x, y: LONGINT;
  BEGIN
    IF n < 2 THEN x := n
    ELSE x := n; y := (x + 1) DIV 2;
      WHILE y < x DO x := y; y := (x + n DIV x) DIV 2 END
    END;
    RETURN x
  END ISqrt;

  (* the heads from cylinder a to b *)
  PROCEDURE Seek(a, b: INTEGER): LONGINT;
    VAR d, c, r: LONGINT;
  BEGIN d := ABS(a - b); c := cyls;
    IF d = 0 THEN r := 0 ELSE r := settle + (stroke - settle) * ISqrt(d * 1000000) DIV ISqrt(c * 1000000) END;
    RETURN r
  END Seek;

  (* when sector s next starts under the heads, at x or after *)
  PROCEDURE RotStart(x: LONGINT; s: INTEGER): LONGINT;
    VAR b: LONGINT;
  BEGIN b := x - x MOD rev + s * secT; IF b < x THEN b := b + rev END;
    RETURN b
  END RotStart;

  (* The drive reads the next block, hb + 1, into the buffer: a sector on
     from the last, a track to track seek more onto the next cylinder; or
     after a stop (resume), from resumeAt once the heads are on its
     cylinder and it has come round. *)
  PROCEDURE Step;
    VAR b: INTEGER; x: LONGINT;
  BEGIN b := hb + 1;
    IF resume THEN x := resumeAt; IF ht > x THEN x := ht END;
      IF b DIV bpc # cyl THEN x := x + Seek(cyl, b DIV bpc); cyl := b DIV bpc END;
      ht := RotStart(x, b MOD spt) + secT; resume := FALSE
    ELSIF b MOD bpc = 0 THEN ht := ht + t2t + secT; cyl := b DIV bpc
    ELSE ht := ht + secT
    END;
    hb := b;
    IF hb - lo > 2 * raMax THEN lo := hb - 2 * raMax END
  END Step;

  (* The read-ahead, on its own until x: the blocks read by then. *)
  PROCEDURE Advance(x: LONGINT);
    VAR n: LONGINT; go: BOOLEAN;
  BEGIN go := TRUE;
    WHILE go & valid & ~resume & (hb < lim) DO
      n := ht + secT; IF (hb + 1) MOD bpc = 0 THEN n := n + t2t END;
      IF n <= x THEN Step ELSE go := FALSE END
    END
  END Advance;

  (* A read of n blocks from l at t: from the buffer, from the read-ahead
     on its way to them, or from a seek and the wait for l to come round. *)
  PROCEDURE StartRead(l, n: INTEGER);
  BEGIN Advance(t);
    IF valid & (l >= lo) & ((l <= hb + 1) OR (hb < lim) & (l <= lim)) THEN
      IF hb >= lim THEN resume := TRUE; resumeAt := t + ovh END      (* the buffer had filled: it reads on *)
    ELSE valid := TRUE; lo := l; hb := l - 1; resume := TRUE; resumeAt := t + ovh
    END;
    lim := l + n - 1 + raMax; IF lim >= blocks THEN lim := blocks - 1 END
  END StartRead;

  (* Block k in the buffer: no REQ for it sooner. The blocks before hb were
     read by a time already passed. *)
  PROCEDURE Ready(k: INTEGER);
  BEGIN
    WHILE hb < k DO Step END;
    IF (k = hb) & (ht > due) THEN due := ht END
  END Ready;

  (* The write's blocks are all in the buffer (now, t): when they are on
     the platters, the seek having started with the command. *)
  PROCEDURE WriteDone(): LONGINT;
    VAR x: LONGINT; b, c: INTEGER;
  BEGIN c := wLba DIV bpc; x := cmdT + ovh + Seek(cyl, c); cyl := c;
    IF t > x THEN x := t END;
    x := RotStart(x, wLba MOD spt); b := wLba;
    REPEAT x := x + secT; INC(b);
      IF (b MOD bpc = 0) & (b < wLba + wCount) THEN x := x + t2t; cyl := b DIV bpc END
    UNTIL b = wLba + wCount;
    RETURN x
  END WriteDone;

  (* the commands a drive still spinning up answers NOT READY *)
  PROCEDURE Media(op: INTEGER): BOOLEAN;
  BEGIN RETURN (op = 0) OR (op = 4) OR (op = 8) OR (op = 0AH) OR (op = 25H) OR (op = 28H) OR (op = 2AH)
      OR (op = 2FH) OR (op = 35H)
  END Media;

  PROCEDURE Load;
    VAR k, i: INTEGER;
  BEGIN k := EmHost.DiskRead(image, lba * blockSize, data);
    IF k < 0 THEN k := 0 END;
    FOR i := k TO blockSize - 1 DO data[i] := 0 END;
    dataLen := blockSize; dataPos := 0
  END Load;

  PROCEDURE Finish(s: INTEGER);
  BEGIN status := s; xfer := xNone; Request(phStatus, s)
  END Finish;

  PROCEDURE Check(key, code: INTEGER);
  BEGIN Sense(key, code); Finish(checkCondition)
  END Check;

  (* Start the data phase, or go to STATUS if there is nothing to move. *)
  PROCEDURE StartData;
  BEGIN dataPos := 0;
    IF (xfer = xRead) & (count > 0) THEN IF timed THEN Ready(lba) END; Load; Request(phDataIn, data[0])
    ELSIF (xfer = xWrite) & (count > 0) THEN dataLen := blockSize; Request(phDataOut, 0)
    ELSIF (xfer = xBuffer) & (dataLen > 0) THEN Request(phDataIn, data[0])
    ELSIF (xfer = xDiscard) & (dataLen > 0) THEN Request(phDataOut, 0)
    ELSE Finish(good)
    END
  END StartData;

  PROCEDURE Put(i, v: INTEGER);
  BEGIN data[i] := AND(v, 0FFH)
  END Put;

  PROCEDURE PutStr(i: INTEGER; s: ARRAY OF CHAR; w: INTEGER);
    VAR k: INTEGER;
  BEGIN k := 0;
    WHILE k < w DO
      IF (k < LEN(s)) & (s[k] # 0X) THEN data[i + k] := ORD(s[k]) ELSE data[i + k] := 20H END;
      INC(k)
    END
  END PutStr;

  (* reply with the first n bytes of data, at most alloc *)
  PROCEDURE Reply(n, alloc: INTEGER);
  BEGIN IF alloc < n THEN n := alloc END;
    xfer := xBuffer; dataLen := n; StartData
  END Reply;

  PROCEDURE ReadWrite(write: BOOLEAN);
  BEGIN
    IF lba + count > blocks THEN Check(5, 21H)                (* LBA out of range *)
    ELSIF write & readOnly THEN Check(7, 27H)                 (* write protected *)
    ELSE
      IF write THEN xfer := xWrite;
        IF timed THEN Advance(t); valid := FALSE; wLba := lba; wCount := count END
      ELSE xfer := xRead;
        IF timed & (count > 0) THEN StartRead(lba, count) END
      END;
      StartData
    END
  END ReadWrite;

  PROCEDURE Run;
    VAR op, i, alloc: INTEGER;
  BEGIN op := cdb[0]; cmdT := t; due := t + ovh;              (* the controller's time *)
    IF ~identified THEN lun := cdb[1] DIV 32 END;
    FOR i := 0 TO blockSize - 1 DO data[i] := 0 END;
    IF op = 12H THEN                                          (* INQUIRY *)
      IF lun # 0 THEN Put(0, 7FH) END;                        (* no such LUN *)
      Put(2, 2); Put(3, 2); Put(4, 31);                       (* SCSI-2, 36 bytes *)
      PutStr(8, "EM16", 8); PutStr(16, "SCSI DISK", 16); PutStr(32, "1.0", 4);
      Reply(36, cdb[4])
    ELSIF op = 3 THEN                                         (* REQUEST SENSE *)
      IF unitAttention & (lun = 0) THEN unitAttention := FALSE; Sense(6, 29H) END;
      IF lun # 0 THEN Sense(5, 25H) END;
      Put(0, 70H); Put(2, senseKey); Put(7, 10); Put(12, asc); Put(13, ascq);
      alloc := cdb[4]; IF alloc = 0 THEN alloc := 4 END;
      Sense(0, 0); Reply(18, alloc)
    ELSIF lun # 0 THEN Check(5, 25H)                          (* logical unit not supported *)
    ELSIF unitAttention THEN unitAttention := FALSE; Check(6, 29H)   (* power on or reset *)
    ELSIF timed & (t < readyAt) & Media(op) THEN Check(2, 4); ascq := 1   (* becoming ready *)
    ELSIF (op = 0) OR (op = 4) OR (op = 1BH) OR (op = 1EH) OR (op = 35H) THEN
      IF timed & (op = 1BH) & ODD(cdb[4]) & ~ODD(cdb[1]) & (readyAt > due) THEN due := readyAt END;   (* START UNIT *)
      Finish(good)
    ELSIF op = 8 THEN
      lba := AND(cdb[1], 1FH) * 10000H + cdb[2] * 100H + cdb[3]; count := cdb[4];
      IF count = 0 THEN count := 256 END;
      ReadWrite(FALSE)
    ELSIF op = 0AH THEN
      lba := AND(cdb[1], 1FH) * 10000H + cdb[2] * 100H + cdb[3]; count := cdb[4];
      IF count = 0 THEN count := 256 END;
      ReadWrite(TRUE)
    ELSIF (op = 28H) OR (op = 2AH) OR (op = 2FH) THEN
      lba := ((cdb[2] * 100H + cdb[3]) * 100H + cdb[4]) * 100H + cdb[5];
      count := cdb[7] * 100H + cdb[8];
      IF op = 2FH THEN                                        (* VERIFY: the blocks read *)
        IF lba + count > blocks THEN Check(5, 21H)
        ELSE IF timed & (count > 0) THEN StartRead(lba, count); Ready(lba + count - 1) END; Finish(good)
        END
      ELSE ReadWrite(op = 2AH)
      END
    ELSIF op = 25H THEN                                       (* READ CAPACITY *)
      i := blocks - 1;
      Put(0, i DIV 1000000H); Put(1, i DIV 10000H); Put(2, i DIV 100H); Put(3, i);
      Put(6, 2);                                              (* 512 *)
      Reply(8, 8)
    ELSIF op = 1AH THEN                                       (* MODE SENSE(6) *)
      Put(0, 11); IF readOnly THEN Put(2, 80H) END; Put(3, 8);
      Put(5, blocks DIV 10000H); Put(6, blocks DIV 100H); Put(7, blocks); Put(10, 2);
      Reply(12, cdb[4])
    ELSIF op = 15H THEN xfer := xDiscard; dataLen := cdb[4]; StartData   (* MODE SELECT(6) *)
    ELSE Check(5, 20H)                                        (* invalid command operation code *)
    END
  END Run;

  PROCEDURE CdbLength(op: INTEGER): INTEGER;
    VAR g, k: INTEGER;
  BEGIN g := op DIV 32;
    IF g = 0 THEN k := 6 ELSIF (g = 1) OR (g = 2) THEN k := 10 ELSIF g = 5 THEN k := 12 ELSE k := 6 END;
    RETURN k
  END CdbLength;

  (* A byte has gone across in the current phase; b is what the initiator sent. *)
  PROCEDURE Handle(b: INTEGER);
  BEGIN
    IF phase = phMsgOut THEN
      IF b >= 80H THEN lun := AND(b, 7); identified := TRUE END;
      IF b = 6 THEN BusFree                                   (* ABORT *)
      ELSIF b = 0CH THEN DiskReset                            (* BUS DEVICE RESET *)
      ELSIF ODD(icr DIV 2) THEN Request(phMsgOut, 0)          (* ATN still: more messages *)
      ELSE nCdb := 0; Request(phCommand, 0)
      END
    ELSIF phase = phCommand THEN
      IF nCdb = 0 THEN cdbLen := CdbLength(b) END;
      cdb[nCdb] := b; INC(nCdb);
      IF nCdb = cdbLen THEN Run ELSE Request(phCommand, 0) END
    ELSIF phase = phDataIn THEN
      INC(dataPos);
      IF dataPos < dataLen THEN Request(phDataIn, data[dataPos])
      ELSIF xfer = xRead THEN INC(lba); DEC(count);
        IF count > 0 THEN IF timed THEN Ready(lba) END; Load; Request(phDataIn, data[0]) ELSE Finish(good) END
      ELSE Finish(good)
      END
    ELSIF phase = phDataOut THEN
      IF xfer = xWrite THEN data[dataPos] := b END;
      INC(dataPos);
      IF dataPos < dataLen THEN Request(phDataOut, 0)
      ELSIF xfer = xWrite THEN
        EmHost.DiskWrite(image, lba * blockSize, data); INC(lba); DEC(count);
        IF count > 0 THEN dataPos := 0; Request(phDataOut, 0)
        ELSE IF timed THEN due := WriteDone() END; Finish(good)
        END
      ELSE Finish(good)
      END
    ELSIF phase = phStatus THEN Request(phMsgIn, 0)           (* COMMAND COMPLETE *)
    ELSIF phase = phMsgIn THEN BusFree
    END
  END Handle;

  (* --- the bus --- *)

  (* The initiator drives the data bus while asked to, except against a
     target driving it (I/O asserted), and its ID while it arbitrates. *)
  PROCEDURE Bus(): INTEGER;
    VAR v: INTEGER;
  BEGIN v := 0;
    IF ODD(icr) & ~((state = transfer) & (AND(phase, ioL) # 0)) THEN v := odr END;
    IF aip THEN v := ORA(v, odr) END;
    IF (state = transfer) & req & (AND(phase, ioL) # 0) THEN v := ORA(v, out) END;
    RETURN v
  END Bus;

  (* The disk sees the bus change. *)
  PROCEDURE Update;
    VAR b: INTEGER; sel, bsy, ack: BOOLEAN;
  BEGIN sel := ODD(icr DIV 4); bsy := ODD(icr DIV 8); ack := ODD(icr DIV 16);
    IF state = free THEN
      IF mounted & sel & ~bsy & ~aip & (AND(Bus(), idBit) # 0) & (~timed OR (t >= selAt)) THEN state := selected END
    ELSIF state = selected THEN
      IF ~sel THEN state := transfer; identified := FALSE; nCdb := 0;
        IF ODD(icr DIV 2) THEN Request(phMsgOut, 0) ELSE Request(phCommand, 0) END
      END
    ELSIF req & ~acked & ack THEN
      acked := TRUE; req := FALSE;
      IF AND(phase, ioL) # 0 THEN b := out ELSIF ODD(icr) THEN b := odr ELSE b := 0 END;
      out := b
    ELSIF acked & ~ack THEN acked := FALSE; Handle(out)
    END
  END Update;

  PROCEDURE Parity(v: INTEGER): INTEGER;
    VAR p: INTEGER;
  BEGIN p := 1;
    WHILE v # 0 DO IF ODD(v) THEN p := 1 - p END; v := v DIV 2 END;
    RETURN p
  END Parity;

  PROCEDURE BusStatus(): INTEGER;
    VAR v: INTEGER;
  BEGIN v := 0;
    IF ODD(icr DIV 80H) THEN v := v + 80H END;
    IF (state # free) OR ODD(icr DIV 8) OR aip THEN v := v + 40H END;
    IF req THEN v := v + 20H END;
    IF state = transfer THEN v := v + phase END;
    IF ODD(icr DIV 4) THEN v := v + 2 END;
    IF ODD(icr) OR aip OR (state = transfer) & req & (AND(phase, ioL) # 0) THEN
      v := v + Parity(Bus())                                  (* whoever drives the bus drives DBP *)
    END;
    RETURN v
  END BusStatus;

  (* The target asks in the phase the target command register names. *)
  PROCEDURE Match(): BOOLEAN;
  BEGIN RETURN (state = transfer) & req & (AND(tcr, 7) * 4 = phase)
  END Match;

  PROCEDURE Drq*(): BOOLEAN;
  BEGIN
    RETURN ODD(mode DIV 2) & ~endDma & Match()
      & (dmaSend & (AND(phase, ioL) = 0) OR dmaRecv & (AND(phase, ioL) # 0))
  END Drq;

  (* After a DMA byte: the target asking in another phase interrupts. *)
  PROCEDURE Mismatch;
  BEGIN
    IF ODD(mode DIV 2) & (dmaSend OR dmaRecv) & ~endDma & (state = transfer) & req & ~Match() THEN
      irq := TRUE
    END
  END Mismatch;

  PROCEDURE Eop;
  BEGIN endDma := TRUE; IF ODD(mode DIV 8) THEN irq := TRUE END
  END Eop;

  (* The time, now, from the system before it touches the chip, and as it
     passes (EmSoC.Pass, the DMA engine at its own time): with -scsitiming
     a REQ due by now is asserted (a phase mismatch interrupting), and a
     selection held while the drive was starting is answered. *)
  PROCEDURE Tick*(now: LONGINT);
  BEGIN
    IF now > t THEN t := now END;
    IF pend & (t >= reqAt) THEN pend := FALSE; req := TRUE; Mismatch END;
    IF timed & (state = free) THEN Update END
  END Tick;

  (* A /DACK read, the engine's with eop its terminal count, or the CPU's
     at slot 4: the input data register, and the handshake. *)
  PROCEDURE DackRead*(eop: BOOLEAN): INTEGER;
    VAR v: INTEGER;
  BEGIN
    IF dmaRecv & ODD(mode DIV 2) & Match() & (AND(phase, ioL) # 0) THEN
      v := out; req := FALSE; acked := FALSE; Handle(v);
      IF eop THEN Eop END;
      Mismatch
    ELSE v := Bus()
    END;
    RETURN v
  END DackRead;

  (* A /DACK write: the output data register, and the handshake. *)
  PROCEDURE DackWrite*(v: INTEGER; eop: BOOLEAN);
  BEGIN
    IF dmaSend & ODD(mode DIV 2) & Match() & (AND(phase, ioL) = 0) THEN
      odr := v; req := FALSE; acked := FALSE; Handle(v);
      IF eop THEN Eop; lastSent := TRUE END;
      Mismatch
    END
  END DackWrite;

  PROCEDURE BusAndStatus(): INTEGER;
    VAR v, p: INTEGER;
  BEGIN v := 0;
    IF state = transfer THEN p := phase ELSE p := 0 END;
    IF endDma THEN v := v + 80H END;
    IF Drq() THEN v := v + 40H END;
    IF irq THEN v := v + 10H END;
    IF AND(tcr, 7) * 4 = p THEN v := v + 8 END;
    IF busyErr THEN v := v + 4 END;
    IF ODD(icr DIV 2) THEN v := v + 2 END;
    IF ODD(icr DIV 16) THEN v := v + 1 END;
    RETURN v
  END BusAndStatus;

  (* --- the chip --- *)

  PROCEDURE ResetChip*;
  BEGIN odr := 0; icr := 0; mode := 0; tcr := 0; ser := 0; aip := FALSE; irq := FALSE; busyErr := FALSE;
    dmaSend := FALSE; dmaRecv := FALSE; endDma := FALSE; lastSent := FALSE
  END ResetChip;

  (* Power on: the chip, the disk, and the drive's time from 0 *)
  PROCEDURE Reset*;
    VAR hz: LONGINT;
  BEGIN ResetChip; DiskReset;
    hz := EmHost.hz; t := 0; due := 0; cmdT := 0;
    rev := hz DIV 60; secT := rev DIV spt; ovh := hz DIV 2000;            (* 3600 rpm; 0.5 ms *)
    settle := hz * 3 DIV 1000; stroke := hz * 30 DIV 1000;                (* 3 ms; 30 ms *)
    cyls := (blocks + bpc - 1) DIV bpc; IF cyls < 1 THEN cyls := 1 END;
    t2t := Seek(0, 1); selAt := hz; readyAt := hz * 5;                    (* 1 s; 5 s *)
    cyl := 0; valid := FALSE; resume := FALSE; lo := 0; hb := -1; lim := -1; ht := 0; resumeAt := 0
  END Reset;

  PROCEDURE Irq*(): BOOLEAN;
  BEGIN RETURN irq
  END Irq;

  PROCEDURE Read*(reg: INTEGER): INTEGER;
    VAR v: INTEGER;
  BEGIN reg := AND(reg, 7);
    IF (reg = 0) OR (reg = 6) THEN v := Bus()
    ELSIF reg = 1 THEN v := AND(icr, 9FH); IF aip THEN v := v + 40H END
    ELSIF reg = 2 THEN v := mode
    ELSIF reg = 3 THEN v := tcr; IF lastSent THEN v := v + 80H END
    ELSIF reg = 4 THEN v := BusStatus()
    ELSIF reg = 5 THEN v := BusAndStatus()
    ELSE irq := FALSE; busyErr := FALSE; v := 0
    END;
    RETURN v
  END Read;

  (* A register as Read gives it, but changing nothing: for the trace. *)
  PROCEDURE Peek*(reg: INTEGER): INTEGER;
    VAR v: INTEGER;
  BEGIN IF AND(reg, 7) = 7 THEN v := 0 ELSE v := Read(reg) END; RETURN v
  END Peek;

  PROCEDURE Write*(reg, v: INTEGER);
  BEGIN reg := AND(reg, 7);
    IF reg = 0 THEN odr := v
    ELSIF reg = 1 THEN
      IF ODD(v DIV 80H) & ~ODD(icr DIV 80H) THEN              (* SCSI bus reset *)
        mode := 0; tcr := 0; aip := FALSE; irq := TRUE; DiskReset;
        dmaSend := FALSE; dmaRecv := FALSE; endDma := FALSE
      END;
      icr := AND(v, 9FH)
    ELSIF reg = 2 THEN mode := v;
      IF ~ODD(v) THEN aip := FALSE
      ELSIF (state = free) & ~ODD(icr DIV 4) THEN aip := TRUE  (* the bus is free: arbitrating *)
      END;
      IF ~ODD(v DIV 2) THEN dmaSend := FALSE; dmaRecv := FALSE; endDma := FALSE; lastSent := FALSE END
    ELSIF reg = 3 THEN tcr := AND(v, 0FH)
    ELSIF reg = 4 THEN ser := v
    ELSIF reg = 5 THEN
      IF ODD(mode DIV 2) THEN dmaSend := TRUE; dmaRecv := FALSE; endDma := FALSE; lastSent := FALSE END
    ELSIF reg = 7 THEN
      IF ODD(mode DIV 2) THEN dmaRecv := TRUE; dmaSend := FALSE; endDma := FALSE END
    END;
    Update
  END Write;

BEGIN mounted := FALSE; readOnly := FALSE; blocks := 0; timed := FALSE; Reset
END EmSCSI.
