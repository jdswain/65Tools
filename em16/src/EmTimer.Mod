MODULE EmTimer; (* The SoC's tick timer (rtl/timer.v of the Verilog
   repository): a 16-bit down-counter that sets PENDING every RELOAD
   counts, and a 32-bit count of those ticks. Its interrupt goes through
   the interrupt status register at $0440 (EmSoC).

   It counts at 25.2 MHz whatever the system clock: a count is 252 /
   (EmHost.hz / 100 kHz) of a system clock, spread evenly by a phase
   accumulator that is cleared when the timer is enabled (soc.v's TNUM and
   TDEN). So count k after the enabling edge is in the clock ceil(TDEN * k /
   TNUM), and RELOAD 63000 is 2.5 ms at any clock. At 25.2 MHz a count is a
   clock.

   Registers at $0450, mirrored every 16 bytes:
     +0, +1  RELOAD   the period in counts, low first; 0 means 65536. A
                      write takes effect at the next tick, or at enabling.
     +2      CTRL     bit 0 EN. Setting it starts a period of RELOAD
                      counts; clearing it stops the timer and the count.
     +3      STATUS   bit 0 PENDING, set at each tick; write 1 to clear
     +4, +5  NOW      the down-counter as latched by a read of +8: counts
                      left until the next tick, minus 1
     +8..+B  TICKS    ticks since reset, low first; reading +8 latches the
                      other three bytes and NOW
   Unlisted offsets read 0.

   Time: the ticks are counted when asked for, from the count the next one
   is due at; Tick is called often enough for PENDING to raise the IRQ
   within a few dozen cycles of the RTL's. *)

  IMPORT EmHost;

  CONST TNUM = 252;

  VAR
    tden: LONGINT;                  (* EmHost.hz / 100 kHz *)
    reload: INTEGER;
    en, pending: BOOLEAN;
    tEn: LONGINT;                   (* the cycle the timer was enabled *)
    next: LONGINT;                  (* the count, from tEn, the next tick is due at *)
    ticks, ticksL, nowL: INTEGER;
    held: INTEGER;                  (* the counter, while stopped *)

  PROCEDURE Period(): INTEGER;
    VAR p: INTEGER;
  BEGIN p := reload; IF p = 0 THEN p := 10000H END;
    RETURN p
  END Period;

  PROCEDURE Counts(now: LONGINT): LONGINT;           (* counts since tEn *)
  BEGIN RETURN (now - tEn) * TNUM DIV tden
  END Counts;

  (* The ticks due by now. The first is at next, which was set with the
     period then; the rest are RELOAD apart, as RELOAD is now. *)
  PROCEDURE Tick*(now: LONGINT);
    VAR k, c: LONGINT; p: INTEGER;
  BEGIN
    IF en THEN c := Counts(now);
      IF c >= next THEN p := Period();
        k := (c - next) DIV p + 1;
        ticks := ticks + k; next := next + k * p; pending := TRUE
      END
    END
  END Tick;

  PROCEDURE Irq*(): BOOLEAN;
  BEGIN RETURN pending
  END Irq;

  PROCEDURE Byte(x, n: INTEGER): INTEGER;          (* byte n of x *)
  BEGIN WHILE n > 0 DO x := x DIV 100H; DEC(n) END;
    RETURN AND(x, 0FFH)
  END Byte;

  PROCEDURE Read*(reg: INTEGER; now: LONGINT): INTEGER;
    VAR r, v: INTEGER;
  BEGIN Tick(now); r := AND(reg, 15); v := 0;
    IF r <= 1 THEN v := Byte(reload, r)
    ELSIF r = 2 THEN IF en THEN v := 1 END
    ELSIF r = 3 THEN IF pending THEN v := 1 END
    ELSIF (r = 4) OR (r = 5) THEN v := Byte(nowL, r - 4)
    ELSIF r = 8 THEN v := Byte(ticks, 0); ticksL := ticks;
      IF en THEN nowL := next - Counts(now) - 1 ELSE nowL := held END
    ELSIF (r >= 9) & (r <= 11) THEN v := Byte(ticksL, r - 8)
    END;
    RETURN v
  END Read;

  PROCEDURE Write*(reg, v: INTEGER; now: LONGINT);
    VAR r: INTEGER;
  BEGIN Tick(now); r := AND(reg, 15);
    IF r = 0 THEN reload := reload - Byte(reload, 0) + AND(v, 0FFH)
    ELSIF r = 1 THEN reload := Byte(reload, 0) + AND(v, 0FFH) * 100H
    ELSIF r = 2 THEN
      IF ODD(v) & ~en THEN tEn := now; next := Period()
      ELSIF ~ODD(v) & en THEN held := next - Counts(now) - 1
      END;
      en := ODD(v)
    ELSIF (r = 3) & ODD(v) THEN pending := FALSE
    END
  END Write;

  PROCEDURE Reset*;
  BEGIN tden := EmHost.hz DIV 100000; reload := 0; en := FALSE; pending := FALSE; next := 0; tEn := 0;
    ticks := 0; ticksL := 0; nowL := 0; held := 0
  END Reset;

BEGIN Reset
END EmTimer.
