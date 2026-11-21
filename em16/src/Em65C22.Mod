MODULE Em65C22; (* A W65C22N VIA, the Mini816's: its ports and their
   handshakes, the two timers, the shift register and the interrupts, in
   the cycles of PHI2 (the board passes their count, now).

   The board wires it with SetPins: the input pins of the ports (PortA,
   PortB: a procedure each, read when the pins are), and a procedure told
   the output pins of port B and CA2 and CB2 each time they change
   (Lines). CA1 and CB1 are inputs the board drives (SetCA1, SetCB1); an
   active edge sets the flag, latches the port when ACR enables it, and
   ends a handshake.

   Timer 1 counts from its latch, at the latch + 2 cycles a period in
   free run, and drives PB7 when ACR bit 7 is set: low from the write of
   T1C-H to the time-out in one-shot mode, inverted at each time-out in
   free run. Timer 2 times out once, or counts PB6's falling edges. The
   shift register runs at 2 x (T2's low byte + 2) cycles a bit (and in
   free run repeats its byte), at 2 cycles a bit under PHI2, or on CB1's
   edges; it shifts out on CB2, MSB first, or shifts CB2 in.

   The device keeps itself up to date when it is read or written and
   when Tick is called, which the board does between instructions. *)

  CONST
    (* IFR's bits *)
    fCA2 = 1; fCA1 = 2; fSR = 4; fCB2 = 8; fCB1 = 16; fT2 = 32; fT1 = 64;

  TYPE
    Pins* = PROCEDURE (): INTEGER;
    (* the output lines: port B's pins, CA2, CB2 (0 or 1), at now *)
    Lines* = PROCEDURE (pb, ca2, cb2: INTEGER; now: LONGINT);

  VAR
    ora, orb, ddra, ddrb, acr, pcr, ifr, ier, sr: INTEGER;
    ila, ilb: INTEGER;              (* the ports latched by CA1, CB1 *)
    t1l, t1n: INTEGER;              (* T1's latch; the value it was loaded with at t1at *)
    t1at, t1due: LONGINT;           (* its load, its next time-out *)
    t1armed: BOOLEAN;               (* a one-shot time-out still to interrupt *)
    pb7: INTEGER;                   (* PB7 as T1 drives it *)
    t2l, t2n: INTEGER;              (* T2's low latch; its count at t2at *)
    t2at, t2due: LONGINT;
    t2armed: BOOLEAN;
    srN: INTEGER;                   (* the bits shifted, 8 a byte; -1: not running *)
    srNext: LONGINT;                (* the next bit's time *)
    ca1, cb1, ca2, cb2: INTEGER;    (* the lines' levels *)
    ca2Pulse, cb2Pulse: LONGINT;    (* a pulse output's end *)
    pb6: INTEGER;                   (* PB6 as last seen, for T2's count *)
    portA, portB: Pins; lines: Lines;
    last: LONGINT;                  (* the time it is up to *)
    never: LONGINT;                 (* a time not reached *)

  PROCEDURE Lo(v: INTEGER): INTEGER;
  BEGIN RETURN AND(v, 0FFH)
  END Lo;

  PROCEDURE PullUp(): INTEGER;
  BEGIN RETURN 0FFH
  END PullUp;

  PROCEDURE NoLines(pb, ca2, cb2: INTEGER; now: LONGINT);
  END NoLines;

  PROCEDURE SetPins*(a, b: Pins; l: Lines);
  BEGIN portA := a; portB := b; lines := l
  END SetPins;

  (* the pins of port B as driven: ORB where DDRB is 1, PB7 from T1 when
     ACR bit 7 is set, the inputs pulled up *)
  PROCEDURE PbOut(): INTEGER;
    VAR v: INTEGER;
  BEGIN v := ORA(AND(orb, ddrb), 0FFH - ddrb);
    IF ODD(acr DIV 128) THEN v := AND(v, 7FH) + pb7 * 128 END;
    RETURN v
  END PbOut;

  PROCEDURE Changed(now: LONGINT);
  BEGIN lines(PbOut(), ca2, cb2, now)
  END Changed;

  PROCEDURE IrqFlags(): INTEGER;
    VAR v: INTEGER;
  BEGIN v := AND(ifr, 7FH); IF AND(v, ier) # 0 THEN v := v + 80H END; RETURN v
  END IrqFlags;

  PROCEDURE Irq*(): BOOLEAN;
  BEGIN RETURN AND(AND(ifr, ier), 7FH) # 0
  END Irq;

  (* CA2 and CB2 as outputs, by PCR: a manual level, or high at rest in the
     handshake and pulse modes; an input reads 1 (pulled up) *)
  PROCEDURE Ca2Mode(): INTEGER;
  BEGIN RETURN AND(pcr DIV 2, 7)
  END Ca2Mode;

  PROCEDURE Cb2Mode(): INTEGER;
  BEGIN RETURN AND(pcr DIV 32, 7)
  END Cb2Mode;

  PROCEDURE SrMode(): INTEGER;
  BEGIN RETURN AND(acr DIV 4, 7)
  END SrMode;

  PROCEDURE SetLevels(now: LONGINT);
    VAR a, b, m: INTEGER;
  BEGIN a := ca2; b := cb2;
    m := Ca2Mode(); IF m = 6 THEN ca2 := 0 ELSIF (m = 7) OR (m < 4) THEN ca2 := 1 END;
    m := Cb2Mode(); IF m = 6 THEN cb2 := 0 ELSIF ((m = 7) OR (m < 4)) & (SrMode() < 4) THEN cb2 := 1 END;
    IF (a # ca2) OR (b # cb2) THEN Changed(now) END
  END SetLevels;

  (* --- the timers and the shift register, brought up to now --- *)

  (* a bit's time, a period of CB1's shift clock: 2 cycles under PHI2,
     else T2's low byte + 2 low and as long high (W65C22 data sheet,
     figures 2-9 and 2-11) *)
  PROCEDURE SrPeriod(): INTEGER;
    VAR m, p: INTEGER;
  BEGIN m := SrMode();
    IF (m = 2) OR (m = 6) THEN p := 2 ELSE p := 2 * (t2l + 2) END;
    RETURN p
  END SrPeriod;

  (* the first bit as CB1 first falls, half a period on *)
  PROCEDURE SrStart(now: LONGINT);
    VAR m: INTEGER;
  BEGIN m := SrMode(); ifr := AND(ifr, 0FFH - fSR);
    IF (m = 0) OR (m = 3) OR (m = 7) THEN srN := -1; srNext := never   (* off, or clocked by CB1 *)
    ELSE srN := 0; srNext := now + SrPeriod() DIV 2
    END;
    IF (m = 3) OR (m = 7) THEN srN := 0 END
  END SrStart;

  (* one bit shifted: out on CB2, MSB first, or CB2 in *)
  PROCEDURE SrBit(now: LONGINT);
    VAR m, b: INTEGER;
  BEGIN m := SrMode();
    IF m >= 4 THEN b := sr DIV 128; sr := AND(sr * 2, 0FFH) + b;
      IF cb2 # b THEN cb2 := b; Changed(now) END
    ELSE sr := AND(sr * 2, 0FFH) + 1                (* CB2 pulled up *)
    END;
    INC(srN);
    IF srN = 8 THEN
      IF m = 4 THEN srN := 0                        (* free run *)
      ELSE ifr := ORA(ifr, fSR); srN := -1; srNext := never
      END
    END
  END SrBit;

  PROCEDURE Update(now: LONGINT);
  BEGIN
    WHILE t1due <= now DO
      IF t1armed OR ODD(acr DIV 64) THEN ifr := ORA(ifr, fT1) END;
      IF ODD(acr DIV 64) THEN                       (* free run: reload *)
        IF ODD(acr DIV 128) THEN pb7 := 1 - pb7; Changed(t1due) END;
        t1at := t1due; t1n := t1l; t1due := t1at + t1l + 2
      ELSE
        IF t1armed & ODD(acr DIV 128) THEN pb7 := 1; Changed(t1due) END;
        t1armed := FALSE; t1at := t1due; t1n := 0FFFFH; t1due := t1at + 10000H
      END
    END;
    WHILE t2due <= now DO
      IF t2armed & ~ODD(acr DIV 32) & ((SrMode() = 0) OR (SrMode() = 3) OR (SrMode() = 7)) THEN
        ifr := ORA(ifr, fT2)
      END;
      t2armed := FALSE; t2at := t2due; t2n := 0FFFFH; t2due := t2at + 10000H
    END;
    WHILE srNext <= now DO
      SrBit(srNext); IF srN >= 0 THEN srNext := srNext + SrPeriod() END
    END;
    IF (ca2Pulse <= now) & (ca2 = 0) & (Ca2Mode() = 5) THEN ca2 := 1; ca2Pulse := never; Changed(now) END;
    IF (cb2Pulse <= now) & (cb2 = 0) & (Cb2Mode() = 5) THEN cb2 := 1; cb2Pulse := never; Changed(now) END;
    last := now
  END Update;

  PROCEDURE Tick*(now: LONGINT);
  BEGIN IF now > last THEN Update(now) END
  END Tick;

  PROCEDURE T1Count(now: LONGINT): INTEGER;
    VAR e: INTEGER;
  BEGIN e := now - t1at; RETURN AND(t1n + 1 - e, 0FFFFH)
  END T1Count;

  PROCEDURE T2Count(now: LONGINT): INTEGER;
    VAR e, r: INTEGER;
  BEGIN
    IF ODD(acr DIV 32) THEN r := t2n ELSE e := now - t2at; r := AND(t2n + 1 - e, 0FFFFH) END;
    RETURN r
  END T2Count;

  (* the port handshakes: a read or write of ORA (a), of ORB (b) *)
  PROCEDURE PortA(now: LONGINT);
    VAR m: INTEGER;
  BEGIN m := Ca2Mode();
    ifr := AND(ifr, 0FFH - fCA1); IF (m # 1) & (m # 3) THEN ifr := AND(ifr, 0FFH - fCA2) END;
    IF (m = 4) OR (m = 5) THEN
      IF ca2 # 0 THEN ca2 := 0; Changed(now) END;
      IF m = 5 THEN ca2Pulse := now + 1 END
    END
  END PortA;

  PROCEDURE PortB(now: LONGINT; write: BOOLEAN);
    VAR m: INTEGER;
  BEGIN m := Cb2Mode();
    ifr := AND(ifr, 0FFH - fCB1); IF (m # 1) & (m # 3) THEN ifr := AND(ifr, 0FFH - fCB2) END;
    IF write & ((m = 4) OR (m = 5)) THEN
      IF cb2 # 0 THEN cb2 := 0; Changed(now) END;
      IF m = 5 THEN cb2Pulse := now + 1 END
    END
  END PortB;

  (* PB6's falling edges, counted by T2 in pulse counting mode *)
  PROCEDURE CountPB6(now: LONGINT);
    VAR b: INTEGER;
  BEGIN b := LSR(portB(), 6) MOD 2;
    IF (pb6 = 1) & (b = 0) & ODD(acr DIV 32) THEN
      t2n := AND(t2n - 1, 0FFFFH);
      IF (t2n = 0FFFFH) & t2armed THEN ifr := ORA(ifr, fT2); t2armed := FALSE END
    END;
    pb6 := b
  END CountPB6;

  PROCEDURE Read*(reg: INTEGER; now: LONGINT): INTEGER;
    VAR v: INTEGER;
  BEGIN Tick(now); reg := AND(reg, 0FH);
    CASE reg OF
      0: IF ODD(acr DIV 2) THEN v := ilb ELSE v := portB() END;
        v := ORA(AND(orb, ddrb), AND(v, 0FFH - ddrb));
        IF ODD(acr DIV 128) THEN v := AND(v, 7FH) + pb7 * 128 END;
        PortB(now, FALSE)
    | 1, 15: IF ODD(acr) THEN v := ila ELSE v := ORA(AND(ora, ddra), AND(portA(), 0FFH - ddra)) END;
        IF reg = 1 THEN PortA(now) END
    | 2: v := ddrb
    | 3: v := ddra
    | 4: v := Lo(T1Count(now)); ifr := AND(ifr, 0FFH - fT1)
    | 5: v := T1Count(now) DIV 256
    | 6: v := Lo(t1l)
    | 7: v := t1l DIV 256
    | 8: v := Lo(T2Count(now)); ifr := AND(ifr, 0FFH - fT2)
    | 9: v := T2Count(now) DIV 256
    | 10: v := sr; SrStart(now)
    | 11: v := acr
    | 12: v := pcr
    | 13: v := IrqFlags()
    | 14: v := ier + 80H
    END;
    RETURN v
  END Read;

  PROCEDURE Write*(reg, v: INTEGER; now: LONGINT);
    VAR old: INTEGER;
  BEGIN Tick(now); reg := AND(reg, 0FH); v := AND(v, 0FFH);
    CASE reg OF
      0: old := PbOut(); orb := v; PortB(now, TRUE); IF PbOut() # old THEN Changed(now) END; CountPB6(now)
    | 1, 15: ora := v; IF reg = 1 THEN PortA(now) END
    | 2: old := PbOut(); ddrb := v; IF PbOut() # old THEN Changed(now) END; CountPB6(now)
    | 3: ddra := v
    | 4, 6: t1l := AND(t1l, 0FF00H) + v
    | 5: t1l := AND(t1l, 0FFH) + v * 256; t1at := now; t1n := t1l; t1due := now + t1l + 2;
        t1armed := TRUE; ifr := AND(ifr, 0FFH - fT1);
        IF ODD(acr DIV 128) & (pb7 # 0) THEN pb7 := 0; Changed(now) END
    | 7: t1l := AND(t1l, 0FFH) + v * 256; ifr := AND(ifr, 0FFH - fT1)
    | 8: t2l := v
    | 9: t2at := now; t2n := t2l + v * 256; t2armed := TRUE; ifr := AND(ifr, 0FFH - fT2);
        IF ODD(acr DIV 32) THEN t2due := never ELSE t2due := now + t2n + 2 END
    | 10: sr := v; SrStart(now)
    | 11: old := PbOut(); acr := v;
        IF ODD(acr DIV 32) THEN t2n := T2Count(now); t2due := never END;
        IF (SrMode() = 0) & (srN >= 0) THEN srN := -1; srNext := never END;
        IF PbOut() # old THEN Changed(now) END; SetLevels(now)
    | 12: pcr := v; SetLevels(now)
    | 13: ifr := AND(ifr, 0FFH - AND(v, 7FH))
    | 14: IF v >= 80H THEN ier := ORA(ier, AND(v, 7FH)) ELSE ier := AND(ier, 0FFH - v) END
    END
  END Write;

  (* the input lines: an active edge (PCR bit 0, 4: 1 the rising) *)
  PROCEDURE SetCA1*(level: INTEGER; now: LONGINT);
    VAR pos: BOOLEAN;
  BEGIN Tick(now); pos := ODD(pcr);
    IF (level # ca1) & ((level = 1) = pos) THEN
      ifr := ORA(ifr, fCA1);
      IF ODD(acr) THEN ila := ORA(AND(ora, ddra), AND(portA(), 0FFH - ddra)) END;
      IF (Ca2Mode() = 4) & (ca2 = 0) THEN ca2 := 1; Changed(now) END
    END;
    ca1 := level
  END SetCA1;

  PROCEDURE SetCB1*(level: INTEGER; now: LONGINT);
    VAR pos: BOOLEAN; m: INTEGER;
  BEGIN Tick(now); pos := ODD(pcr DIV 16);
    IF (level # cb1) & ((level = 1) = pos) THEN
      ifr := ORA(ifr, fCB1);
      IF ODD(acr DIV 2) THEN ilb := ORA(AND(orb, ddrb), AND(portB(), 0FFH - ddrb)) END;
      IF (Cb2Mode() = 4) & (cb2 = 0) THEN cb2 := 1; Changed(now) END
    END;
    m := SrMode();
    IF (level # cb1) & ((m = 3) OR (m = 7)) & (srN >= 0) & ((level = 1) = (m = 3)) THEN SrBit(now) END;
    cb1 := level
  END SetCB1;

  PROCEDURE Reset*;
  BEGIN
    ora := 0; orb := 0; ddra := 0; ddrb := 0; acr := 0; pcr := 0; ifr := 0; ier := 0; sr := 0;
    ila := 0; ilb := 0; t1l := 0FFFFH; t1n := 0FFFFH; t1at := last; t1due := never; t1armed := FALSE;
    pb7 := 1; t2l := 0FFH; t2n := 0FFFFH; t2at := last; t2due := never; t2armed := FALSE;
    srN := -1; srNext := never; ca2 := 1; cb2 := 1; ca2Pulse := never; cb2Pulse := never;
    pb6 := 1; Changed(last)
  END Reset;

BEGIN never := 1000000; never := never * never * 1000000;
  portA := PullUp; portB := PullUp; lines := NoLines; last := 0; ca1 := 1; cb1 := 1; Reset
END Em65C22.
