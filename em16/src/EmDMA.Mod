MODULE EmDMA; (* The SoC's DMA engine (rtl/dma.v of the Verilog repository;
   its docs/DMA.md is the specification): two channels that move bytes
   between the SDRAM and the carrier's chips, one byte an external bus
   cycle. Channel 0 serves the 53C80 (EmSCSI), channel 1 the 82077AA
   (Em82077); with -wd1793 channel 1 has no device and never runs.

   Registers at $0400, 16 bytes a channel ($0410 channel 1), mirrored
   at $0420:
     +0..+2 ADDR    the next byte's address, low first
     +4..+6 COUNT   the bytes left
     +8     CTRL    0 EN, 1 DIR (1 = memory to device), 2 TC on the last
                    byte, 3 IE
     +9     STATUS  7 BUSY, 6 DRQ, 0 DONE (write 1 to clear)
   ADDR and COUNT are written only while the channel is not BUSY. A CTRL
   write always sets IE; EN = 0 stops the channel, EN = 1 starts it if it
   is stopped (taking DIR and TC), and keeps it running if it runs. A start
   with COUNT = 0 is DONE at once. DONE with IE raises the IRQ.

   Time: a byte takes 17 cycles of the SoC's clock (the bus cycle, the
   bridge's gap, and the wait before the engine looks at DRQ again), and
   the engine keeps its own time a little behind the CPU's, catching up
   at each Tick: the chips are asked for DRQ, and given the byte, at the
   cycle the engine reaches. When both channels ask they take turns. The
   bytes go straight to and from the memory; the cache drops any line a
   byte lands in, as there. Not modelled: the RTL's gathering into words
   and its line buffer (the order of the bytes in memory is the same), the
   SDRAM port's time, and the CPU waiting for the external bus while a DMA
   cycle has it. *)

  IMPORT Em82077, EmSCSI, EmSDRAM;

  CONST
    cycle = 17;                     (* SoC cycles a byte *)

  VAR
    addr, cnt: ARRAY 2 OF INTEGER;
    en, dir, tc, ie, done: ARRAY 2 OF BOOLEAN;
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
    IF c = 0 THEN r := EmSCSI.Drq() ELSE r := floppy & Em82077.Drq(at) END;
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
      IF c = 0 THEN EmSCSI.DackWrite(v, end) ELSE Em82077.DackWrite(v, end, at) END
    ELSE
      IF c = 0 THEN v := EmSCSI.DackRead(end) ELSE v := Em82077.DackRead(end, at) END;
      EmSDRAM.Poke(a, v); EmSDRAM.Invalidate(a)
    END;
    addr[c] := AND(addr[c] + 1, 0FFFFFFH); DEC(cnt[c]);
    IF cnt[c] = 0 THEN en[c] := FALSE; done[c] := TRUE END
  END Move;

  PROCEDURE Tick*(now: LONGINT);
    VAR r0, r1: BOOLEAN; c: INTEGER;
  BEGIN
    IF ~en[0] & ~en[1] THEN t := now
    ELSE
      WHILE t + cycle <= now DO
        r0 := Ready(0, t); r1 := Ready(1, t);
        IF r0 & r1 THEN c := 1 - last ELSIF r1 THEN c := 1 ELSE c := 0 END;
        IF r0 OR r1 THEN Move(c, t) END;
        t := t + cycle
      END
    END
  END Tick;

  PROCEDURE Irq*(): BOOLEAN;
  BEGIN RETURN done[0] & ie[0] OR done[1] & ie[1]
  END Irq;

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
  BEGIN Tick(now); c := AND(reg DIV 16, 1); r := AND(reg, 15); v := 0;
    IF r <= 2 THEN v := Byte(addr[c], r)
    ELSIF (r >= 4) & (r <= 6) THEN v := Byte(cnt[c], r - 4)
    ELSIF r = 8 THEN
      IF en[c] THEN v := 1 END;
      IF dir[c] THEN v := v + 2 END;
      IF tc[c] THEN v := v + 4 END;
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
  BEGIN Tick(now); c := AND(reg DIV 16, 1); r := AND(reg, 15);
    IF (r <= 2) & ~en[c] THEN SetByte(addr[c], r, v)
    ELSIF (r >= 4) & (r <= 6) & ~en[c] THEN SetByte(cnt[c], r - 4, v)
    ELSIF r = 8 THEN ie[c] := ODD(v DIV 8);
      IF ~ODD(v) THEN en[c] := FALSE
      ELSIF ~en[c] THEN
        dir[c] := ODD(v DIV 2); tc[c] := ODD(v DIV 4); done[c] := FALSE;
        IF cnt[c] = 0 THEN done[c] := TRUE
        ELSE en[c] := TRUE;
          IF ~en[1 - c] THEN t := now END
        END
      END
    ELSIF (r = 9) & ODD(v) THEN done[c] := FALSE
    END
  END Write;

  PROCEDURE Reset*;
    VAR c: INTEGER;
  BEGIN
    FOR c := 0 TO 1 DO
      addr[c] := 0; cnt[c] := 0;
      en[c] := FALSE; dir[c] := FALSE; tc[c] := FALSE; ie[c] := FALSE; done[c] := FALSE
    END;
    t := 0; last := 0
  END Reset;

BEGIN floppy := TRUE; Reset
END EmDMA.
