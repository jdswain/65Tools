MODULE EmPower; (* The SoC's soft power and power LED, rtl/power.v of the
   Verilog repository, at $0480 (mirrored through $04BF):

     +0  STATUS   read: bit 0 KEY, the power key is down; bit 1 PRESSED,
                  set when it goes down (write 1 to clear); bit 7 OFF, the
                  off burst is running
     +1  CONTROL  bit 0 LED, lit (1 at reset); bit 1 BLINK; bit 2 IE,
                  PRESSED raises ISTAT bit 5 (0 at reset)
     +2  OFF      write $A5: the supply off, after the 50 ms burst; other
                  values are ignored; reads 0
     +3           reads 0

   The power key is F12 in em16's window (Key), which the keyboard also
   reports over ADB, as the real one does. Held for 4 seconds it turns the
   supply off whatever the CPU does. em16 starts with the key up, so the
   RTL's rule for a key held since reset does not arise, and the 10 ms
   debounce is left out: a press is seen at once. The supply going off ends
   the run (off), with a message. The LED is kept but not shown. *)

  IMPORT EmHost;

  CONST
    OffMs = 50; HoldMs = 4000;

  VAR
    ms: LONGINT;                (* cycles in a millisecond (SetClock) *)
    key, pressed, ie, blink, led: BOOLEAN;
    burstEnd, holdEnd: LONGINT; (* -1: none *)
    down: BOOLEAN;              (* the key, as the window last set it *)
    off*: BOOLEAN;              (* the supply is off: the run ends *)

  PROCEDURE SetClock*(hz: LONGINT);
  BEGIN ms := hz DIV 1000
  END SetClock;

  PROCEDURE PowerOff(why: ARRAY OF CHAR);
  BEGIN
    IF ~off THEN off := TRUE;
      EmHost.Ln(EmHost.out); EmHost.Str(EmHost.out, "em16: the supply turned off ("); EmHost.Str(EmHost.out, why);
      EmHost.Str(EmHost.out, ")"); EmHost.Ln(EmHost.out)
    END
  END PowerOff;

  PROCEDURE Tick*(now: LONGINT);
  BEGIN
    IF down & ~key THEN key := TRUE; pressed := TRUE; holdEnd := now + HoldMs * ms
    ELSIF ~down & key THEN key := FALSE; holdEnd := -1
    END;
    IF (holdEnd >= 0) & (now >= holdEnd) THEN holdEnd := -1; PowerOff("the power key held") END;
    IF (burstEnd >= 0) & (now >= burstEnd) THEN burstEnd := -1; PowerOff("OFF") END
  END Tick;

  PROCEDURE Irq*(): BOOLEAN;
  BEGIN RETURN pressed & ie
  END Irq;

  PROCEDURE Read*(a: INTEGER; now: LONGINT): INTEGER;
    VAR r, v: INTEGER;
  BEGIN Tick(now); r := AND(a, 3); v := 0;
    IF r = 0 THEN
      IF key THEN INC(v) END; IF pressed THEN INC(v, 2) END; IF burstEnd >= 0 THEN INC(v, 80H) END
    ELSIF r = 1 THEN
      IF led THEN INC(v) END; IF blink THEN INC(v, 2) END; IF ie THEN INC(v, 4) END
    END;
    RETURN v
  END Read;

  PROCEDURE Write*(a, v: INTEGER; now: LONGINT);
    VAR r: INTEGER;
  BEGIN Tick(now); r := AND(a, 3);
    IF r = 0 THEN IF AND(v, 2) # 0 THEN pressed := FALSE END
    ELSIF r = 1 THEN led := ODD(v); blink := ODD(v DIV 2); ie := ODD(v DIV 4)
    ELSIF (r = 2) & (AND(v, 0FFH) = 0A5H) & (burstEnd < 0) THEN burstEnd := now + OffMs * ms
    END
  END Write;

  (* the power key, from the window: 1 down, 0 up *)
  PROCEDURE Key*(d: INTEGER);
  BEGIN down := d # 0
  END Key;

  PROCEDURE Reset*;
  BEGIN key := FALSE; pressed := FALSE; ie := FALSE; blink := FALSE; led := TRUE;
    burstEnd := -1; holdEnd := -1; off := FALSE
  END Reset;

BEGIN ms := 40500; down := FALSE; Reset
END EmPower.
