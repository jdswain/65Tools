MODULE EmTimer; (* The SoC's tick timer (rtl/timer.v of the Verilog
   repository): a 16-bit down-counter on the SoC's clock that sets PENDING
   every RELOAD cycles, and a 32-bit count of those ticks. Its interrupt goes
   through the interrupt status register at $0440 (EmSoC).

   Registers at $0450, mirrored every 16 bytes:
     +0, +1  RELOAD   the period in cycles, low first; 0 means 65536. A
                      write takes effect at the next tick, or at enabling.
     +2      CTRL     bit 0 EN. Setting it starts a period of RELOAD
                      cycles; clearing it stops the timer and the count.
     +3      STATUS   bit 0 PENDING, set at each tick; write 1 to clear
     +4, +5  NOW      the down-counter as latched by a read of +8: cycles
                      left until the next tick, minus 1
     +8..+B  TICKS    ticks since reset, low first; reading +8 latches the
                      other three bytes and NOW
   Unlisted offsets read 0.

   Time: the ticks are counted when asked for, from the cycle the next one
   is due; Tick is called often enough for PENDING to raise the IRQ within
   a few dozen cycles of the RTL's. *)

  VAR
    reload: INTEGER;
    en, pending: BOOLEAN;
    next: LONGINT;                  (* the cycle the next tick is due *)
    ticks, ticksL, nowL: INTEGER;
    held: INTEGER;                  (* the counter, while stopped *)

  PROCEDURE Period(): INTEGER;
    VAR p: INTEGER;
  BEGIN p := reload; IF p = 0 THEN p := 10000H END;
    RETURN p
  END Period;

  (* The ticks due by now. The first is at next, which was set with the
     period then; the rest are RELOAD apart, as RELOAD is now. *)
  PROCEDURE Tick*(now: LONGINT);
    VAR k: INTEGER; p: INTEGER;
  BEGIN
    IF en & (now >= next) THEN p := Period();
      k := (now - next) DIV p + 1;
      ticks := ticks + k; next := next + k * p; pending := TRUE
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
      IF en THEN nowL := next - now - 1 ELSE nowL := held END
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
      IF ODD(v) & ~en THEN next := now + Period()
      ELSIF ~ODD(v) & en THEN held := next - now - 1
      END;
      en := ODD(v)
    ELSIF (r = 3) & ODD(v) THEN pending := FALSE
    END
  END Write;

  PROCEDURE Reset*;
  BEGIN reload := 0; en := FALSE; pending := FALSE; next := 0;
    ticks := 0; ticksL := 0; nowL := 0; held := 0
  END Reset;

BEGIN Reset
END EmTimer.
