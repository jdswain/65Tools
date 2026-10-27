MODULE EmADB; (* The SoC's Apple Desktop Bus host, rtl/adb_host.v, with a
   keyboard (address 2) and a mouse (address 3) on the bus, fed by the
   display window.

   Registers: 0 command (writing it starts a transaction), 1 status
   {busy, done, timeout, srq, count}, 2 length of a Listen's data, 3
   write bit 0: bus reset, read bit 0: collision, 8-15 data. Writes while
   busy are ignored.

   A transaction takes as long as on the wire, from the host's timing
   parameters: attention 800 us, sync 70 us, 8 command bits and a stop
   bit of 100 us. A Talk then waits for the device: one with something to
   say answers after 200 us with a start bit, its bytes and a stop bit,
   and the host ends 150 us after the last edge; one with nothing to say
   is silent, as a real one is, and the host times out after 300 us. A
   device other than the one addressed that has something to say pulls
   the command's stop bit low: SRQ. *)

  CONST
    usAttn = 800; usSync = 70; usBit = 100; usTlt = 200; usTltMax = 300;
    usRxEnd = 150; usLow0 = 65; usReset = 3000;
    perUs = 252;                    (* cycles per 10 us at 25.2 MHz *)
    kbdSize = 32;

  VAR
    cmd, len: INTEGER;
    busy, done, timeout, srq: BOOLEAN;
    count: INTEGER;
    data: ARRAY 8 OF INTEGER;
    endTime: LONGINT;
    (* the keyboard: key events, bit 7 for up *)
    kbdEvents: ARRAY kbdSize OF INTEGER;
    kbdHead, kbdTail, kbdAddr, kbdHandler: INTEGER;
    (* the mouse *)
    mouseAddr, mouseHandler, mouseDx, mouseDy: INTEGER;
    mouseButton, mouseMoved: BOOLEAN;
    (* the answer of the transaction under way *)
    rx: ARRAY 8 OF INTEGER;
    rxCount: INTEGER;
    rxTimeout, rxSrq, resetting: BOOLEAN;
    talks*: LONGINT;                (* transactions started, for EmSoC's pacing *)

  PROCEDURE Cycles(us: INTEGER): LONGINT;
    VAR c: LONGINT;
  BEGIN c := us; RETURN c * perUs DIV 10
  END Cycles;

  PROCEDURE KbdHasData(): BOOLEAN;
  BEGIN RETURN kbdHead # kbdTail
  END KbdHasData;

  PROCEDURE MouseHasData(): BOOLEAN;
  BEGIN RETURN mouseMoved
  END MouseHasData;

  PROCEDURE ResetDevices;
  BEGIN kbdHead := 0; kbdTail := 0; kbdAddr := 2; kbdHandler := 2;
    mouseAddr := 3; mouseHandler := 1; mouseDx := 0; mouseDy := 0;
    mouseButton := FALSE; mouseMoved := FALSE
  END ResetDevices;

  PROCEDURE Clamp(x: INTEGER): INTEGER;
  BEGIN IF x < -64 THEN x := -64 ELSIF x > 63 THEN x := 63 END; RETURN x
  END Clamp;

  (* What the device at addr answers to Talk register reg: rxCount bytes
     in rx, 0 for silence. *)
  PROCEDURE Talk(addr, reg: INTEGER);
    VAR a, dx, dy: INTEGER;
  BEGIN rxCount := 0;
    IF addr = kbdAddr THEN
      IF (reg = 0) & KbdHasData() THEN
        rx[0] := kbdEvents[kbdHead]; kbdHead := (kbdHead + 1) MOD kbdSize;
        IF KbdHasData() THEN rx[1] := kbdEvents[kbdHead]; kbdHead := (kbdHead + 1) MOD kbdSize
        ELSE rx[1] := 0FFH
        END;
        rxCount := 2
      ELSIF reg = 3 THEN rx[0] := 60H + kbdAddr; rx[1] := kbdHandler; rxCount := 2
      END
    ELSIF addr = mouseAddr THEN
      IF (reg = 0) & MouseHasData() THEN   (* what is beyond 7 bits waits for the next Talk *)
        IF mouseButton THEN a := 0 ELSE a := 80H END;
        dx := Clamp(mouseDx); dy := Clamp(mouseDy);
        rx[0] := a + AND(dy, 7FH); rx[1] := 80H + AND(dx, 7FH);
        mouseDx := mouseDx - dx; mouseDy := mouseDy - dy;
        mouseMoved := (mouseDx # 0) OR (mouseDy # 0); rxCount := 2
      ELSIF reg = 3 THEN rx[0] := 60H + mouseAddr; rx[1] := mouseHandler; rxCount := 2
      END
    END
  END Talk;

  (* Listen register 3: a new address and handler. *)
  PROCEDURE Listen(addr, reg: INTEGER);
  BEGIN
    IF (reg = 3) & (len >= 2) & (data[1] # 0FEH) THEN
      IF addr = kbdAddr THEN kbdAddr := AND(data[0], 0FH); kbdHandler := data[1]
      ELSIF addr = mouseAddr THEN mouseAddr := AND(data[0], 0FH); mouseHandler := data[1]
      END
    END
  END Listen;

  PROCEDURE Start(c: INTEGER; now: LONGINT);
    VAR addr, code, reg, us: INTEGER;
  BEGIN INC(talks); cmd := c; busy := TRUE; done := FALSE; timeout := FALSE; srq := FALSE; count := 0;
    addr := c DIV 16; code := AND(c DIV 4, 3); reg := AND(c, 3);
    us := usAttn + usSync + 9 * usBit;                  (* command and its stop bit *)
    rxSrq := (KbdHasData() & (addr # kbdAddr)) OR (MouseHasData() & (addr # mouseAddr));
    rxTimeout := FALSE; rxCount := 0; resetting := FALSE;
    IF code = 3 THEN Talk(addr, reg);
      IF rxCount = 0 THEN us := us + usTltMax; rxTimeout := TRUE
      ELSE us := us + usTlt + usBit * (1 + 8 * rxCount) + usLow0 + usRxEnd
      END
    ELSIF (code = 2) & (len # 0) THEN
      us := us + usBit * (2 + 8 * len); Listen(addr, reg)
    ELSIF AND(c, 0FH) = 0 THEN ResetDevices          (* SendReset *)
    ELSIF AND(c, 0FH) = 1 THEN                           (* Flush *)
      IF addr = kbdAddr THEN kbdHead := kbdTail ELSIF addr = mouseAddr THEN mouseMoved := FALSE END
    END;
    endTime := now + Cycles(us)
  END Start;

  PROCEDURE Tick*(now: LONGINT);
    VAR i: INTEGER;
  BEGIN
    IF busy & (now >= endTime) THEN
      busy := FALSE; done := TRUE;
      IF ~resetting THEN
        timeout := rxTimeout; srq := rxSrq; count := rxCount;
        FOR i := 0 TO rxCount - 1 DO data[i] := rx[i] END
      END
    END
  END Tick;

  PROCEDURE Read*(reg: INTEGER; now: LONGINT): INTEGER;
    VAR r: INTEGER;
  BEGIN Tick(now); reg := AND(reg, 0FH);
    IF reg = 0 THEN r := cmd
    ELSIF reg = 1 THEN r := count;
      IF busy THEN r := r + 80H END; IF done THEN r := r + 40H END;
      IF timeout THEN r := r + 20H END; IF srq THEN r := r + 10H END
    ELSIF reg = 2 THEN r := len
    ELSIF reg = 3 THEN r := 0
    ELSIF reg >= 8 THEN r := data[reg - 8]
    ELSE r := 0FFH
    END;
    RETURN r
  END Read;

  PROCEDURE Write*(reg, v: INTEGER; now: LONGINT);
  BEGIN Tick(now); reg := AND(reg, 0FH);
    IF ~busy THEN
      IF reg = 0 THEN Start(v, now)
      ELSIF reg = 2 THEN len := v
      ELSIF reg = 3 THEN
        IF ODD(v) THEN busy := TRUE; done := FALSE; resetting := TRUE; ResetDevices;
          endTime := now + Cycles(usReset)
        END
      ELSIF reg >= 8 THEN data[reg - 8] := v
      END
    END
  END Write;

  (* --- input from the window (another thread) --- *)

  PROCEDURE KbdPut(ev: INTEGER);
    VAR next: INTEGER;
  BEGIN next := (kbdTail + 1) MOD kbdSize;
    IF next # kbdHead THEN kbdEvents[kbdTail] := ev; kbdTail := next END
  END KbdPut;

  PROCEDURE KeyDown*(kc: INTEGER);
  BEGIN KbdPut(AND(kc, 7FH))
  END KeyDown;

  PROCEDURE KeyUp*(kc: INTEGER);
  BEGIN KbdPut(80H + AND(kc, 7FH))
  END KeyUp;

  PROCEDURE MouseMove*(dx, dy: INTEGER);
  BEGIN mouseDx := mouseDx + dx; mouseDy := mouseDy + dy; mouseMoved := TRUE
  END MouseMove;

  PROCEDURE MouseButton*(pressed: INTEGER);
  BEGIN mouseButton := pressed # 0; mouseMoved := TRUE
  END MouseButton;

  PROCEDURE Reset*;
    VAR i: INTEGER;
  BEGIN cmd := 0; len := 0; busy := FALSE; done := FALSE; timeout := FALSE; srq := FALSE; count := 0;
    FOR i := 0 TO 7 DO data[i] := 0 END; ResetDevices
  END Reset;

BEGIN talks := 0; Reset
END EmADB.
