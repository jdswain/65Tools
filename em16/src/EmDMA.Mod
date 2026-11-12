MODULE EmDMA; (* The SoC's DMA engine (rtl/dma.v of the Verilog repository;
   its docs/DMA.md is the specification): three channels that move bytes
   between the SDRAM and the carrier's chips, one byte an external bus
   cycle. Channel 0 serves the 53C80 (EmSCSI), channel 1 the 82077AA
   (Em82077); with -wd1793 channel 1 has no device and never runs.
   Channel 2 serves the ENC424J600 (EmEth), which has no request line: it
   runs unpaced, each cycle an access to its data port, $0851, at the
   window software latched first; never with TC.

   Registers at $0400, 16 bytes a channel ($0410 channel 1, $0420 channel
   2; $0430-$043F reads 0 and ignores writes):
     +0..+2 ADDR    the next byte's address, low first
     +4..+6 COUNT   the bytes left
     +8     CTRL    0 EN, 1 DIR (1 = memory to device), 2 TC on the last
                    byte, 3 IE
     +9     STATUS  7 BUSY, 6 DRQ (channel 2: always 1), 0 DONE (write 1
                    to clear)
   CTRL's TC reads 0 on channel 2.
   ADDR and COUNT are written only while the channel is not BUSY. A CTRL
   write always sets IE; EN = 0 stops the channel, EN = 1 starts it if it
   is stopped (taking DIR and TC), and keeps it running if it runs. A start
   with COUNT = 0 is DONE at once. DONE with IE raises the IRQ: ISTAT bits
   1, 2 and 6.

   Time: a byte takes 17 cycles of the SoC's clock (the bus cycle, the
   bridge's gap, and the wait before the engine looks at DRQ again), and
   the engine keeps its own time a little behind the CPU's, catching up
   at each Tick: the chips are asked for DRQ, and given the byte, at the
   cycle the engine reaches. Channel 2 takes a cycle less (16 at 25.2 MHz,
   as tb_dma measures it). Channels that ask take turns, round robin. The
   bytes go straight to and from the memory; the cache drops any line a
   byte lands in, as there. Not modelled: the RTL's gathering into words
   and its line buffer (the order of the bytes in memory is the same), the
   SDRAM port's time, and the CPU waiting for the external bus while a DMA
   cycle has it. A channel starts no sooner than the CPU's write buffer
   is empty (EmSDRAM.BufferEmpty), as wr_busy holds the engine. *)

  IMPORT EmHost, Em82077, EmSCSI, EmEth, EmSDRAM;

  CONST N = 3;                      (* channels *)

  VAR
    cycle: INTEGER;                 (* SoC cycles a byte: the bus cycle 3T + H + 1, 4, DRQ_HOLD; 17 at 25.2 MHz, 25 at 40.5 *)
    addr, cnt: ARRAY N OF INTEGER;
    en, dir, tc, ie, done: ARRAY N OF BOOLEAN;
    t: LONGINT;                     (* the engine's time *)
    last: INTEGER;                  (* the channel that had the last byte *)
    floppy: BOOLEAN;                (* channel 1 has the 82077AA *)

  (* -wd1793: no 82077AA, so nothing on channel 1 *)
  PROCEDURE NoFloppy*;
  BEGIN floppy := FALSE
  END NoFloppy;

  PROCEDURE Drq(c: INTEGER; at: LONGINT): BOOLEAN;
    VAR r: BOOLEAN;
  BEGIN
    IF c = 0 THEN EmSCSI.Tick(at); r := EmSCSI.Drq() ELSIF c = 1 THEN r := floppy & Em82077.Drq(at) ELSE r := TRUE END;
    RETURN r
  END Drq;

  PROCEDURE Ready(c: INTEGER; at: LONGINT): BOOLEAN;
  BEGIN RETURN en[c] & (cnt[c] > 0) & Drq(c, at)
  END Ready;

  (* One byte for channel c, at the engine's time at. *)
  PROCEDURE Move(c: INTEGER; at: LONGINT);
    VAR a, v: INTEGER; end: BOOLEAN;
  BEGIN last := c; a := AND(addr[c], 7FFFFFH); end := tc[c] & (cnt[c] = 1);
    IF dir[c] THEN v := EmSDRAM.Peek(a);
      IF c = 0 THEN EmSCSI.DackWrite(v, end) ELSIF c = 1 THEN Em82077.DackWrite(v, end, at)
      ELSE EmEth.Write(1, v, at)
      END
    ELSE
      IF c = 0 THEN v := EmSCSI.DackRead(end) ELSIF c = 1 THEN v := Em82077.DackRead(end, at)
      ELSE v := EmEth.Read(1, at)
      END;
      EmSDRAM.Poke(a, v); EmSDRAM.Invalidate(a)
    END;
    addr[c] := AND(addr[c] + 1, 0FFFFFFH); DEC(cnt[c]);
    IF cnt[c] = 0 THEN en[c] := FALSE; done[c] := TRUE END
  END Move;

  PROCEDURE Running(): BOOLEAN;
  BEGIN RETURN en[0] OR en[1] OR en[2]
  END Running;

  PROCEDURE Tick*(now: LONGINT);
    VAR c, k, d: INTEGER;
  BEGIN
    IF ~Running() THEN t := now
    ELSE
      WHILE t + cycle <= now DO
        c := -1; k := 1;
        WHILE (c < 0) & (k <= N) DO d := (last + k) MOD N; IF Ready(d, t) THEN c := d END; INC(k) END;
        IF c >= 0 THEN Move(c, t); IF c = 2 THEN t := t - 1 END END;    (* channel 2: a cycle less *)
        t := t + cycle
      END
    END
  END Tick;

  PROCEDURE Irq*(): BOOLEAN;
  BEGIN RETURN done[0] & ie[0] OR done[1] & ie[1] OR done[2] & ie[2]
  END Irq;

  (* channel c's DONE & IE, for the interrupt status at $0440 *)
  PROCEDURE IrqCh*(c: INTEGER): BOOLEAN;
  BEGIN RETURN done[c] & ie[c]
  END IrqCh;

  PROCEDURE Byte(x, n: INTEGER): INTEGER;          (* byte n of x *)
  BEGIN WHILE n > 0 DO x := x DIV 100H; DEC(n) END;
    RETURN AND(x, 0FFH)
  END Byte;

  PROCEDURE SetByte(VAR x: INTEGER; n, v: INTEGER);
    VAR m: INTEGER;
  BEGIN m := 1; WHILE n > 0 DO m := m * 100H; DEC(n) END;
    x := x - AND(x DIV m, 0FFH) * m + AND(v, 0FFH) * m
  END SetByte;

  PROCEDURE Read*(reg: INTEGER; now: LONGINT): INTEGER;
    VAR c, r, v: INTEGER;
  BEGIN Tick(now); c := AND(reg DIV 16, 3); r := AND(reg, 15); v := 0;
    IF c = 3 THEN
    ELSIF r <= 2 THEN v := Byte(addr[c], r)
    ELSIF (r >= 4) & (r <= 6) THEN v := Byte(cnt[c], r - 4)
    ELSIF r = 8 THEN
      IF en[c] THEN v := 1 END;
      IF dir[c] THEN v := v + 2 END;
      IF tc[c] & (c < 2) THEN v := v + 4 END;
      IF ie[c] THEN v := v + 8 END
    ELSIF r = 9 THEN
      IF en[c] THEN v := 80H END;
      IF Drq(c, now) THEN v := v + 40H END;
      IF done[c] THEN v := v + 1 END
    END;
    RETURN v
  END Read;

  PROCEDURE Write*(reg, v: INTEGER; now: LONGINT);
    VAR c, r: INTEGER;
  BEGIN Tick(now); c := AND(reg DIV 16, 3); r := AND(reg, 15);
    IF c = 3 THEN
    ELSIF (r <= 2) & ~en[c] THEN SetByte(addr[c], r, v)
    ELSIF (r >= 4) & (r <= 6) & ~en[c] THEN SetByte(cnt[c], r - 4, v)
    ELSIF r = 8 THEN ie[c] := ODD(v DIV 8);
      IF ~ODD(v) THEN en[c] := FALSE
      ELSIF ~en[c] THEN
        dir[c] := ODD(v DIV 2); tc[c] := ODD(v DIV 4) & (c < 2); done[c] := FALSE;
        IF cnt[c] = 0 THEN done[c] := TRUE
        ELSE IF ~Running() THEN t := now; IF EmSDRAM.BufferEmpty() > t THEN t := EmSDRAM.BufferEmpty() END END; en[c] := TRUE   (* once wr_busy falls *)
        END
      END
    ELSIF (r = 9) & ODD(v) THEN done[c] := FALSE
    END
  END Write;

  PROCEDURE Reset*;
    VAR c: INTEGER;
  BEGIN cycle := 3 * ((EmHost.hz + 8399999) DIV 8400000) + (EmHost.hz + 25199999) DIV 25200000 + 1 + 4
      + (EmHost.hz + 6250000) DIV 12500000;

    FOR c := 0 TO N - 1 DO
      addr[c] := 0; cnt[c] := 0;
      en[c] := FALSE; dir[c] := FALSE; tc[c] := FALSE; ie[c] := FALSE; done[c] := FALSE
    END;
    t := 0; last := 0
  END Reset;

BEGIN floppy := TRUE; Reset
END EmDMA.
