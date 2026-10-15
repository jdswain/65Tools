MODULE EmVIA; (* The 6522 VIA, with timer 1 for interrupts, and behind its
   ports the microcontroller of an ADB keyboard and mouse.

   Port A carries ADB commands and responses, port B bit 0 strobes a
   command and reads back data available (bit 1) and service request
   (bit 4); the keyboard and mouse raise CA1. The window of the video
   display calls AdbKeyDown and the rest from its own thread. *)

  CONST
    ifrCA1 = 2; ifrT2 = 20H; ifrT1 = 40H; ifrIRQ = 80H;
    kbdBufSize = 32;

  VAR
    ora, orb, ddra, ddrb: INTEGER;
    t1Counter, t1Latch, t2Counter, t2LatchLo: INTEGER;
    sr, acr, pcr, ifr, ier: INTEGER;
    t1Running: BOOLEAN;

    (* the ADB devices *)
    kbdAddress, kbdHandler: INTEGER;
    kbdEvents: ARRAY kbdBufSize OF INTEGER;   (* bit 7: key up *)
    kbdHead, kbdTail: INTEGER;
    mouseAddress, mouseHandler, mouseDx, mouseDy: INTEGER;
    mouseButton, mouseMoved: BOOLEAN;
    response: ARRAY 2 OF INTEGER;
    responseLen, responsePos: INTEGER;

  (* --- ADB --- *)

  PROCEDURE AdbReset;
  BEGIN
    kbdHead := 0; kbdTail := 0; kbdAddress := 2; kbdHandler := 2;
    mouseDx := 0; mouseDy := 0; mouseButton := FALSE; mouseMoved := FALSE;
    mouseAddress := 3; mouseHandler := 3;
    responseLen := 0; responsePos := 0
  END AdbReset;

  PROCEDURE KbdHasData(): BOOLEAN;
  BEGIN RETURN kbdHead # kbdTail
  END KbdHasData;

  PROCEDURE Clamp(x: INTEGER): INTEGER;
  BEGIN
    IF x < -64 THEN x := -64 ELSIF x > 63 THEN x := 63 END;
    RETURN x
  END Clamp;

  PROCEDURE Answer(a, b: INTEGER);
  BEGIN response[0] := a; response[1] := b; responseLen := 2; responsePos := 0
  END Answer;

  PROCEDURE ProcessTalk(addr, reg: INTEGER);
    VAR a, b: INTEGER;
  BEGIN
    IF addr = kbdAddress THEN
      IF reg = 0 THEN
        IF KbdHasData() THEN
          a := kbdEvents[kbdHead]; kbdHead := (kbdHead + 1) MOD kbdBufSize;
          IF KbdHasData() THEN
            b := kbdEvents[kbdHead]; kbdHead := (kbdHead + 1) MOD kbdBufSize
          ELSE b := 0FFH
          END;
          Answer(a, b)
        END
      ELSIF reg = 3 THEN
        IF KbdHasData() THEN a := 20H ELSE a := 0 END;
        Answer(ORA(a, AND(kbdAddress, 0FH)), kbdHandler)
      END
    ELSIF addr = mouseAddress THEN
      IF reg = 0 THEN
        IF mouseMoved OR mouseButton THEN
          IF mouseButton THEN a := 0 ELSE a := 80H END;
          Answer(ORA(a, AND(Clamp(mouseDy), 7FH)), ORA(80H, AND(Clamp(mouseDx), 7FH)));
          mouseDx := 0; mouseDy := 0; mouseMoved := FALSE
        END
      ELSIF reg = 3 THEN
        IF mouseMoved OR mouseButton THEN a := 20H ELSE a := 0 END;
        Answer(ORA(a, AND(mouseAddress, 0FH)), mouseHandler)
      END
    END
  END ProcessTalk;

  PROCEDURE ProcessFlush(addr: INTEGER);
  BEGIN
    IF addr = kbdAddress THEN kbdHead := 0; kbdTail := 0
    ELSIF addr = mouseAddress THEN mouseDx := 0; mouseDy := 0; mouseMoved := FALSE
    END
  END ProcessFlush;

  (* A command byte: address (4 bits), command (2), register (2). *)
  PROCEDURE AdbCommand(cmd: INTEGER);
    VAR code: INTEGER;
  BEGIN responseLen := 0; responsePos := 0;
    IF AND(cmd, 0FH) = 0 THEN AdbReset
    ELSE code := AND(cmd DIV 4, 3);
      IF code = 0 THEN ProcessFlush(AND(cmd DIV 16, 0FH))
      ELSIF code = 3 THEN ProcessTalk(AND(cmd DIV 16, 0FH), AND(cmd, 3))
      END
    END
  END AdbCommand;

  PROCEDURE HasResponse(): BOOLEAN;
  BEGIN RETURN responsePos < responseLen
  END HasResponse;

  PROCEDURE ReadResponse(): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF responsePos < responseLen THEN r := response[responsePos]; INC(responsePos)
    ELSE r := 0FFH
    END;
    RETURN r
  END ReadResponse;

  PROCEDURE KbdPut(ev: INTEGER);
    VAR next: INTEGER;
  BEGIN next := (kbdTail + 1) MOD kbdBufSize;
    IF next # kbdHead THEN kbdEvents[kbdTail] := ev; kbdTail := next END
  END KbdPut;

  (* --- the VIA --- *)

  PROCEDURE UpdateIRQ;
  BEGIN
    IF AND(AND(ifr, ier), 7FH) # 0 THEN ifr := ORA(ifr, ifrIRQ)
    ELSE ifr := AND(ifr, 7FH)
    END
  END UpdateIRQ;

  PROCEDURE SignalSRQ;
  BEGIN ifr := ORA(ifr, ifrCA1); UpdateIRQ
  END SignalSRQ;

  PROCEDURE AdbKeyDown*(kc: INTEGER);
  BEGIN KbdPut(AND(kc, 7FH)); SignalSRQ
  END AdbKeyDown;

  PROCEDURE AdbKeyUp*(kc: INTEGER);
  BEGIN KbdPut(ORA(80H, AND(kc, 7FH))); SignalSRQ
  END AdbKeyUp;

  PROCEDURE AdbMouseMove*(dx, dy: INTEGER);
  BEGIN mouseDx := mouseDx + dx; mouseDy := mouseDy + dy; mouseMoved := TRUE; SignalSRQ
  END AdbMouseMove;

  PROCEDURE AdbMouseButton*(pressed: INTEGER);
  BEGIN mouseButton := pressed # 0; mouseMoved := TRUE; SignalSRQ
  END AdbMouseButton;

  PROCEDURE Reset*;
  BEGIN
    ora := 0; orb := 0; ddra := 0; ddrb := 0;
    t1Counter := 0; t1Latch := 0; t2Counter := 0; t2LatchLo := 0;
    t1Running := FALSE; sr := 0; acr := 0; pcr := 0; ifr := 0; ier := 0;
    AdbReset
  END Reset;

  PROCEDURE PortA(): INTEGER;
    VAR r: INTEGER;
  BEGIN ifr := AND(ifr, 0FFH - ifrCA1); UpdateIRQ;
    IF HasResponse() THEN r := ReadResponse() ELSE r := 0FFH END;
    RETURN r
  END PortA;

  PROCEDURE GetByte*(ea: INTEGER): INTEGER;
    VAR r, reg, inputs: INTEGER;
  BEGIN reg := AND(ea, 0FH); r := 0;
    CASE reg OF
      0: inputs := 0;
        IF HasResponse() THEN inputs := 2 END;
        IF KbdHasData() OR mouseMoved THEN inputs := ORA(inputs, 10H) END;
        r := ORA(AND(orb, ddrb), AND(inputs, 0FFH - ddrb))
    | 1, 0FH: r := PortA()
    | 2: r := ddrb
    | 3: r := ddra
    | 4: ifr := AND(ifr, 0FFH - ifrT1); UpdateIRQ; r := AND(t1Counter, 0FFH)
    | 5: r := AND(t1Counter DIV 256, 0FFH)
    | 6: r := AND(t1Latch, 0FFH)
    | 7: r := AND(t1Latch DIV 256, 0FFH)
    | 8: ifr := AND(ifr, 0FFH - ifrT2); UpdateIRQ; r := AND(t2Counter, 0FFH)
    | 9: r := AND(t2Counter DIV 256, 0FFH)
    | 0AH: r := sr
    | 0BH: r := acr
    | 0CH: r := pcr
    | 0DH: r := ifr
    | 0EH: r := ORA(ier, 80H)
    END;
    RETURN r
  END GetByte;

  PROCEDURE SetByte*(ea, data: INTEGER);
    VAR reg, old: INTEGER;
  BEGIN reg := AND(ea, 0FH);
    CASE reg OF
      0: old := orb; orb := data;
        IF ODD(data) & ~ODD(old) THEN AdbCommand(ora) END
    | 1, 0FH: ora := data
    | 2: ddrb := data
    | 3: ddra := data
    | 4, 6: t1Latch := ORA(AND(t1Latch, 0FF00H), data)
    | 5: t1Latch := ORA(AND(t1Latch, 0FFH), data * 256); t1Counter := t1Latch;
        ifr := AND(ifr, 0FFH - ifrT1); t1Running := TRUE; UpdateIRQ
    | 7: t1Latch := ORA(AND(t1Latch, 0FFH), data * 256);
        ifr := AND(ifr, 0FFH - ifrT1); UpdateIRQ
    | 8: t2LatchLo := data
    | 9: t2Counter := ORA(data * 256, t2LatchLo); ifr := AND(ifr, 0FFH - ifrT2); UpdateIRQ
    | 0AH: sr := data
    | 0BH: acr := data
    | 0CH: pcr := data
    | 0DH: ifr := AND(ifr, 0FFH - AND(data, 7FH)); UpdateIRQ
    | 0EH:
        IF data >= 80H THEN ier := ORA(ier, AND(data, 7FH))
        ELSE ier := AND(ier, 0FFH - AND(data, 7FH))
        END;
        UpdateIRQ
    END
  END SetByte;

  (* Count timer 1 down by the cycles the last instruction took. *)
  PROCEDURE Tick*(elapsed: INTEGER);
    VAR overshoot: INTEGER;
  BEGIN
    IF t1Running THEN
      IF elapsed >= t1Counter THEN
        ifr := ORA(ifr, ifrT1);
        IF AND(acr, 40H) # 0 THEN   (* free running: reload from the latch *)
          overshoot := elapsed - t1Counter;
          t1Counter := AND(t1Latch - overshoot MOD (t1Latch + 1), 0FFFFH)
        ELSE t1Running := FALSE; t1Counter := 0
        END;
        UpdateIRQ
      ELSE t1Counter := t1Counter - elapsed
      END
    END
  END Tick;

  PROCEDURE IrqPending*(): BOOLEAN;
  BEGIN RETURN AND(AND(ifr, ier), 7FH) # 0
  END IrqPending;

BEGIN Reset
END EmVIA.
