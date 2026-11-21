MODULE EmW816; (* The W65C816S, the chip, a bus cycle at a time, for the
   Mini816 (../../../Hardware/Mini816/docs/em16-profile.md).

   An instruction makes its bus cycles in the order of WDC's data sheet
   (table 5-7), each through the procedure SetBus set: the cycle's
   address, its kind (VDA, VPA, VPB, a write, MLB) and a write's data; a
   read returns the byte. An internal operation is a cycle with neither
   VDA nor VPA, at the address the chip puts out, which a board decoding
   VDA and VPA does not select; so is the dummy write of a read-modify-
   write in emulation mode. The cycles, their addresses and their kinds
   are the chip's, the dummy cycles included, and em16 -harte816 checks
   them against the SingleStepTests vectors, cycle by cycle.

   The semantics are those of EmCore, the SoC's core, checked against the
   same vectors, without its extensions: TCD sets N and Z, JMP keeps the
   program bank, PEI pushes the pointer, decimal arithmetic takes its
   flags as the 65C816 does. In emulation mode the direct page wraps in
   its page when DL = 0 (but for [d] and PEI), the stack in page 1 (but
   for the new instructions, PLB among them, which run with a 16 bit S
   and leave it in page 1).

   Interrupts are taken between instructions: NMI (an edge, Nmi), IRQ (a
   level, the Line SetBus set, when I = 0). ABORT is left out: the
   Mini816 ties it high. WAI waits a cycle at a time for IRQ or NMI, and
   with I = 1 an IRQ ends it without being taken; STP stops the chip
   until Reset.

   With trace (SetTrace, em16 -t) each instruction is written to standard
   error before it runs: where, the opcode, the registers, the cycles. *)

  IMPORT EmHost;

  CONST
    (* a cycle's kind *)
    vda* = 1; vpa* = 2; vpb* = 4; wr* = 8; mlb* = 16;
    (* addressing modes *)
    imm = 0; dp = 1; dpx = 2; dpy = 3; idp = 4; idx = 5; idy = 6; idl = 7; ily = 8;
    ab = 9; abx = 10; aby = 11; abl = 12; alx = 13; sr = 14; sry = 15;
    (* operations *)
    opOra = 0; opAnd = 1; opEor = 2; opAdc = 3; opSta = 4; opLda = 5; opCmp = 6; opSbc = 7;
    opLdx = 8; opLdy = 9; opCpx = 10; opCpy = 11; opBit = 12; opStx = 13; opSty = 14; opStz = 15;
    opAsl = 16; opRol = 17; opLsr = 18; opRor = 19; opInc = 20; opDec = 21; opTsb = 22; opTrb = 23;

  TYPE
    (* a bus cycle: its address, kind and, for a write, data; a read's byte *)
    Bus* = PROCEDURE (addr, kind, data: INTEGER): INTEGER;
    Line* = PROCEDURE (): BOOLEAN;

  VAR
    (* the registers; X and Y 0 above 8 bits when x = 1 *)
    A*, X*, Y*, S*, D*, PC*, DBR*, PBR*: INTEGER;
    fC*, fZ*, fI*, fD*, fX*, fM*, fV*, fN*, fE*: INTEGER;
    stopped*, waiting*, trace: BOOLEAN;
    cycles*: LONGINT;           (* the bus cycles run *)
    opAt*: INTEGER;             (* the instruction's opcode's address *)
    nmi: BOOLEAN;               (* an NMI edge not yet taken *)
    wrap16: BOOLEAN;            (* the operand's second byte: in bank 0, 16 bit wrap *)
    bus: Bus; irqLine: Line;

  PROCEDURE SetTrace*(on: BOOLEAN);
  BEGIN trace := on
  END SetTrace;

  PROCEDURE SetBus*(b: Bus; irq: Line);
  BEGIN bus := b; irqLine := irq
  END SetBus;

  (* An NMI: its falling edge, taken before the next instruction *)
  PROCEDURE Nmi*;
  BEGIN nmi := TRUE
  END Nmi;

  (* --- helpers --- *)

  PROCEDURE B(b: BOOLEAN): INTEGER;
    VAR r: INTEGER;
  BEGIN IF b THEN r := 1 ELSE r := 0 END; RETURN r
  END B;

  PROCEDURE Bit(v, n: INTEGER): INTEGER;
  BEGIN RETURN LSR(v, n) MOD 2
  END Bit;

  PROCEDURE W16(v: INTEGER): INTEGER;
  BEGIN RETURN AND(v, 0FFFFH)
  END W16;

  PROCEDURE A24(v: INTEGER): INTEGER;
  BEGIN RETURN AND(v, 0FFFFFFH)
  END A24;

  PROCEDURE Lo(v: INTEGER): INTEGER;
  BEGIN RETURN AND(v, 0FFH)
  END Lo;

  PROCEDURE Hi(v: INTEGER): INTEGER;
  BEGIN RETURN AND(v DIV 256, 0FFH)
  END Hi;

  PROCEDURE Sext8(v: INTEGER): INTEGER;
  BEGIN v := Lo(v); IF v >= 80H THEN v := v - 100H END; RETURN v
  END Sext8;

  PROCEDURE Join(bank, a: INTEGER): INTEGER;
  BEGIN RETURN Lo(bank) * 10000H + W16(a)
  END Join;

  (* the widths: TRUE for 16 bits *)
  PROCEDURE Mw(): BOOLEAN;
  BEGIN RETURN fM = 0
  END Mw;

  PROCEDURE Xw(): BOOLEAN;
  BEGIN RETURN fX = 0
  END Xw;

  PROCEDURE Av(): INTEGER;
    VAR r: INTEGER;
  BEGIN IF Mw() THEN r := W16(A) ELSE r := Lo(A) END; RETURN r
  END Av;

  PROCEDURE GetP*(): INTEGER;
  BEGIN RETURN fN * 128 + fV * 64 + fM * 32 + fX * 16 + fD * 8 + fI * 4 + fZ * 2 + fC
  END GetP;

  (* P as pushed: in emulation mode bit 4 is B, 1 for BRK, COP and PHP *)
  PROCEDURE PushedP(b: INTEGER): INTEGER;
    VAR p: INTEGER;
  BEGIN p := GetP(); IF fE # 0 THEN p := ORA(AND(p, 0CFH), 20H + b * 10H) END; RETURN p
  END PushedP;

  (* P := v, by PLP, RTI, REP, SEP: M and X stay 1 in emulation mode *)
  PROCEDURE SetP(v: INTEGER);
  BEGIN
    fN := Bit(v, 7); fV := Bit(v, 6); fD := Bit(v, 3); fI := Bit(v, 2); fZ := Bit(v, 1); fC := Bit(v, 0);
    IF fE = 0 THEN fM := Bit(v, 5); fX := Bit(v, 4);
      IF fX # 0 THEN X := Lo(X); Y := Lo(Y) END
    END
  END SetP;

  PROCEDURE NZ(v: INTEGER; wide: BOOLEAN);
  BEGIN
    IF wide THEN fN := Bit(v, 15); fZ := B(W16(v) = 0) ELSE fN := Bit(v, 7); fZ := B(Lo(v) = 0) END
  END NZ;

  PROCEDURE LdA(v: INTEGER);
  BEGIN
    IF Mw() THEN A := W16(v) ELSE A := ORA(AND(A, 0FF00H), Lo(v)) END; NZ(v, Mw())
  END LdA;

  PROCEDURE LdX(v: INTEGER);
  BEGIN IF Xw() THEN X := W16(v) ELSE X := Lo(v) END; NZ(v, Xw())
  END LdX;

  PROCEDURE LdY(v: INTEGER);
  BEGIN IF Xw() THEN Y := W16(v) ELSE Y := Lo(v) END; NZ(v, Xw())
  END LdY;

  (* the flags of r - m at 8 or 16 bits *)
  PROCEDURE Compare(r, m: INTEGER; wide: BOOLEAN);
    VAR t: INTEGER;
  BEGIN
    IF wide THEN t := W16(r) - W16(m); fC := B(t >= 0) ELSE t := Lo(r) - Lo(m); fC := B(t >= 0) END;
    NZ(t, wide)
  END Compare;

  (* decimal add of n digits; c the carry in and out, top the result's top
     bit before the last correction *)
  PROCEDURE DAdd(a, b, cin, n: INTEGER; VAR c, top: INTEGER): INTEGER;
    VAR i, s, r: INTEGER;
  BEGIN r := 0; c := cin; top := 0;
    FOR i := 0 TO n - 1 DO
      s := LSR(a, 4 * i) MOD 16 + LSR(b, 4 * i) MOD 16 + c;
      IF i = n - 1 THEN top := Bit(s, 3) END;
      c := B(s > 9); IF c # 0 THEN s := s + 6 END;
      r := ORA(r, ASL(AND(s, 0FH), 4 * i))
    END;
    RETURN r
  END DAdd;

  (* a - b decimal, cin the inverted borrow *)
  PROCEDURE DSub(a, b, cin, n: INTEGER; VAR c: INTEGER): INTEGER;
    VAR i, s, r: INTEGER;
  BEGIN r := 0; c := cin;
    FOR i := 0 TO n - 1 DO
      s := LSR(a, 4 * i) MOD 16 + 0FH - LSR(b, 4 * i) MOD 16 + c;
      c := Bit(s, 4); IF c = 0 THEN s := s - 6 END;
      r := ORA(r, ASL(AND(s, 0FH), 4 * i))
    END;
    RETURN r
  END DSub;

  PROCEDURE Adc(m: INTEGER);
    VAR w, a, t, c, top, r: INTEGER;
  BEGIN IF Mw() THEN w := 16 ELSE w := 8 END; a := Av();
    IF fD # 0 THEN
      r := DAdd(a, m, fC, w DIV 4, c, top);
      fV := B((Bit(a, w - 1) = Bit(m, w - 1)) & (Bit(a, w - 1) # top));
      fC := c; LdA(r)
    ELSE t := a + m + fC;
      fV := B((Bit(a, w - 1) = Bit(m, w - 1)) & (Bit(a, w - 1) # Bit(t, w - 1)));
      fC := Bit(t, w); LdA(t)
    END
  END Adc;

  PROCEDURE Sbc(m: INTEGER);
    VAR w, a, nm, t, c, r: INTEGER;
  BEGIN IF Mw() THEN w := 16 ELSE w := 8 END; a := Av();
    nm := AND(-1 - m, ASL(1, w) - 1); t := a + nm + fC;
    fV := B((Bit(a, w - 1) # Bit(m, w - 1)) & (Bit(a, w - 1) # Bit(t, w - 1)));
    IF fD # 0 THEN r := DSub(a, m, fC, w DIV 4, c); fC := c; LdA(r)
    ELSE fC := Bit(t, w); LdA(t)
    END
  END Sbc;

  (* a read's operation with its operand m *)
  PROCEDURE Exec(o, m: INTEGER);
  BEGIN
    CASE o OF
      opOra: LdA(ORA(Av(), m))
    | opAnd: LdA(AND(Av(), m))
    | opEor: LdA(EOR(Av(), m))
    | opAdc: Adc(m)
    | opSbc: Sbc(m)
    | opCmp: Compare(A, m, Mw())
    | opLda: LdA(m)
    | opLdx: LdX(m)
    | opLdy: LdY(m)
    | opCpx: Compare(X, m, Xw())
    | opCpy: Compare(Y, m, Xw())
    | opBit: fZ := B(AND(Av(), m) = 0);
        IF Mw() THEN fN := Bit(m, 15); fV := Bit(m, 14) ELSE fN := Bit(m, 7); fV := Bit(m, 6) END
    END
  END Exec;

  (* a read-modify-write's result from m, its flags set *)
  PROCEDURE Modify(o, m: INTEGER): INTEGER;
    VAR w, r: INTEGER;
  BEGIN IF Mw() THEN w := 16 ELSE w := 8 END;
    CASE o OF
      opAsl: r := ASL(m, 1); fC := Bit(m, w - 1)
    | opRol: r := ASL(m, 1) + fC; fC := Bit(m, w - 1)
    | opLsr: r := LSR(m, 1); fC := Bit(m, 0)
    | opRor: r := ORA(LSR(m, 1), ASL(fC, w - 1)); fC := Bit(m, 0)
    | opInc: r := m + 1
    | opDec: r := m - 1
    | opTsb: r := ORA(m, Av())
    | opTrb: r := AND(m, -1 - Av())
    END;
    r := AND(r, ASL(1, w) - 1);
    IF (o = opTsb) OR (o = opTrb) THEN fZ := B(AND(Av(), m) = 0) ELSE NZ(r, Mw()) END;
    RETURN r
  END Modify;

  (* --- bus cycles --- *)

  PROCEDURE Cycle(a, kind, data: INTEGER): INTEGER;
  BEGIN INC(cycles); RETURN bus(A24(a), kind, data)
  END Cycle;

  (* an opcode fetch *)
  PROCEDURE Op(): INTEGER;
    VAR v: INTEGER;
  BEGIN opAt := Join(PBR, PC); v := Cycle(opAt, vda + vpa, 0); PC := W16(PC + 1); RETURN v
  END Op;

  (* an operand byte *)
  PROCEDURE Prg(): INTEGER;
    VAR v: INTEGER;
  BEGIN v := Cycle(Join(PBR, PC), vpa, 0); PC := W16(PC + 1); RETURN v
  END Prg;

  PROCEDURE Rd(a: INTEGER): INTEGER;
  BEGIN RETURN Cycle(a, vda, 0)
  END Rd;

  PROCEDURE Wr(a, v: INTEGER);
    VAR t: INTEGER;
  BEGIN t := Cycle(a, vda + wr, Lo(v))
  END Wr;

  (* an internal operation, its address on the bus *)
  PROCEDURE Io(a: INTEGER);
    VAR t: INTEGER;
  BEGIN t := Cycle(a, 0, 0)
  END Io;

  (* ... at PBR:PC, as most are *)
  PROCEDURE IoPC;
  BEGIN Io(Join(PBR, PC))
  END IoPC;

  (* ... at the operand byte just read *)
  PROCEDURE IoOp;
  BEGIN Io(Join(PBR, PC - 1))
  END IoOp;

  (* --- the stack --- *)

  PROCEDURE Push(v: INTEGER);
  BEGIN Wr(S, v); IF fE # 0 THEN S := 100H + Lo(S - 1) ELSE S := W16(S - 1) END
  END Push;

  PROCEDURE Pull(): INTEGER;
  BEGIN IF fE # 0 THEN S := 100H + Lo(S + 1) ELSE S := W16(S + 1) END; RETURN Rd(S)
  END Pull;

  (* the new instructions': S 16 bits while they run *)
  PROCEDURE PushN(v: INTEGER);
  BEGIN Wr(S, v); S := W16(S - 1)
  END PushN;

  PROCEDURE PullN(): INTEGER;
  BEGIN S := W16(S + 1); RETURN Rd(S)
  END PullN;

  (* ... and S back in page 1 after them, in emulation mode *)
  PROCEDURE Page1;
  BEGIN IF fE # 0 THEN S := 100H + Lo(S) END
  END Page1;

  (* --- addressing --- *)

  (* the direct page's byte o, o perhaps indexed: in its page in emulation
     mode with DL = 0 *)
  PROCEDURE DpAt(o: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF (fE # 0) & (Lo(D) = 0) THEN r := D + Lo(o) ELSE r := W16(D + o) END;
    RETURN r
  END DpAt;

  (* the cycle taken when DL # 0 *)
  PROCEDURE DpPenalty;
  BEGIN IF Lo(D) # 0 THEN IoOp END
  END DpPenalty;

  (* The effective address of the data of mode m, its cycles run; always
     the index cycle for a store or read-modify-write (st); wrap16 set for
     an address in bank 0 that wraps at 16 bits (direct page, stack). *)
  PROCEDURE Ea(m: INTEGER; st: BOOLEAN): INTEGER;
    VAR o, lo, hi, bk, p, base, ea, i: INTEGER;
  BEGIN wrap16 := FALSE; ea := 0;
    CASE m OF
      dp: o := Prg(); DpPenalty; ea := DpAt(o); wrap16 := TRUE
    | dpx, dpy: o := Prg(); DpPenalty; IoOp;
        IF m = dpx THEN i := X ELSE i := Y END; ea := DpAt(o + i); wrap16 := TRUE
    | idp: o := Prg(); DpPenalty; lo := Rd(DpAt(o)); hi := Rd(DpAt(o + 1));
        ea := Join(DBR, hi * 256 + lo)
    | idx: o := Prg(); DpPenalty; IoOp; lo := Rd(DpAt(o + X)); hi := Rd(DpAt(o + X + 1));
        ea := Join(DBR, hi * 256 + lo)
    | idy: o := Prg(); DpPenalty; lo := Rd(DpAt(o)); hi := Rd(DpAt(o + 1));
        base := Join(DBR, hi * 256 + lo); ea := A24(base + Y);
        IF st OR Xw() OR (lo + Lo(Y) > 0FFH) THEN Io(base - lo + Lo(lo + Y)) END
    | idl, ily: o := Prg(); DpPenalty;
        lo := Rd(W16(D + o)); hi := Rd(W16(D + o + 1)); bk := Rd(W16(D + o + 2));
        ea := Join(bk, hi * 256 + lo); IF m = ily THEN ea := A24(ea + Y) END
    | ab: lo := Prg(); hi := Prg(); ea := Join(DBR, hi * 256 + lo)
    | abx, aby: lo := Prg(); hi := Prg(); base := Join(DBR, hi * 256 + lo);
        IF m = abx THEN i := X ELSE i := Y END; ea := A24(base + i);
        IF st OR Xw() OR (lo + Lo(i) > 0FFH) THEN Io(base - lo + Lo(lo + i)) END
    | abl, alx: lo := Prg(); hi := Prg(); bk := Prg(); ea := Join(bk, hi * 256 + lo);
        IF m = alx THEN ea := A24(ea + X) END
    | sr: o := Prg(); IoOp; ea := W16(S + o); wrap16 := TRUE
    | sry: o := Prg(); IoOp; p := W16(S + o); lo := Rd(p); hi := Rd(W16(p + 1)); Io(W16(p + 1));
        ea := A24(Join(DBR, hi * 256 + lo) + Y)
    END;
    RETURN ea
  END Ea;

  (* the address of the data's second byte *)
  PROCEDURE Next(ea: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN IF wrap16 THEN r := W16(ea + 1) ELSE r := A24(ea + 1) END; RETURN r
  END Next;

  (* --- the instructions by class --- *)

  PROCEDURE Read(o, m: INTEGER);
    VAR ea, v: INTEGER; wide: BOOLEAN;
  BEGIN
    IF (o = opLdx) OR (o = opLdy) OR (o = opCpx) OR (o = opCpy) THEN wide := Xw() ELSE wide := Mw() END;
    IF m = imm THEN v := Prg(); IF wide THEN v := v + Prg() * 256 END
    ELSE ea := Ea(m, FALSE); v := Rd(ea); IF wide THEN v := v + Rd(Next(ea)) * 256 END
    END;
    Exec(o, v)
  END Read;

  PROCEDURE Store(o, m: INTEGER);
    VAR ea, v: INTEGER; wide: BOOLEAN;
  BEGIN
    IF o = opStx THEN v := X; wide := Xw()
    ELSIF o = opSty THEN v := Y; wide := Xw()
    ELSIF o = opStz THEN v := 0; wide := Mw()
    ELSE v := A; wide := Mw()
    END;
    ea := Ea(m, TRUE); Wr(ea, Lo(v)); IF wide THEN Wr(Next(ea), Hi(v)) END
  END Store;

  PROCEDURE Rmw(o, m: INTEGER);
    VAR ea, v, r, t: INTEGER;
  BEGIN ea := Ea(m, TRUE);
    v := Cycle(ea, vda + mlb, 0); IF Mw() THEN v := v + Cycle(Next(ea), vda + mlb, 0) * 256 END;
    IF fE # 0 THEN t := Cycle(ea, wr + mlb, v)        (* the dummy write *)
    ELSIF Mw() THEN t := Cycle(Next(ea), mlb, 0)
    ELSE t := Cycle(ea, mlb, 0)
    END;
    r := Modify(o, v);
    IF Mw() THEN t := Cycle(Next(ea), vda + wr + mlb, Hi(r)) END;
    t := Cycle(ea, vda + wr + mlb, Lo(r))
  END Rmw;

  (* ASL A and the like, INC A, DEC A *)
  PROCEDURE RmwA(o: INTEGER);
    VAR r: INTEGER;
  BEGIN IoPC; r := Modify(o, Av());
    IF Mw() THEN A := r ELSE A := ORA(AND(A, 0FF00H), r) END
  END RmwA;

  PROCEDURE Branch(take: BOOLEAN);
    VAR o, t: INTEGER;
  BEGIN o := Prg();
    IF take THEN t := W16(PC + Sext8(o)); IoOp;
      IF (fE # 0) & (Hi(t) # Hi(PC)) THEN IoOp END;
      PC := t
    END
  END Branch;

  (* an interrupt's entry: PC (the return) and P (b its B) pushed, the
     vector in emulation and native mode *)
  PROCEDURE Enter(b, ve, vn: INTEGER);
    VAR v, lo, hi: INTEGER;
  BEGIN
    IF fE = 0 THEN Push(PBR); v := vn ELSE v := ve END;
    Push(Hi(PC)); Push(Lo(PC)); Push(PushedP(b));
    fI := 1; fD := 0; PBR := 0;
    lo := Cycle(v, vda + vpb, 0); hi := Cycle(v + 1, vda + vpb, 0); PC := hi * 256 + lo
  END Enter;

  PROCEDURE Interrupt(ve, vn: INTEGER);
  BEGIN IoPC; IoPC; Enter(0, ve, vn)
  END Interrupt;

  (* a block move's byte: MVN (inc) or MVP *)
  PROCEDURE Move(inc: BOOLEAN);
    VAR dst, src, v, d: INTEGER;
  BEGIN dst := Prg(); src := Prg();
    v := Rd(Join(src, X)); Wr(Join(dst, Y), v); Io(Join(dst, Y)); Io(Join(dst, Y));
    DBR := dst; IF inc THEN d := 1 ELSE d := -1 END;
    IF Xw() THEN X := W16(X + d); Y := W16(Y + d) ELSE X := Lo(X + d); Y := Lo(Y + d) END;
    A := W16(A - 1); IF A # 0FFFFH THEN PC := W16(PC - 3) END
  END Move;

  PROCEDURE Execute(o: INTEGER);
    VAR lo, hi, bk, p, t, v: INTEGER;
  BEGIN
    CASE o OF
    (* the ALU group: (d,X), d,S, d, [d], #, a, al, (d),Y, (d), (d,S),Y, d,X, [d],Y, a,Y, a,X, al,X *)
      01H, 21H, 41H, 61H, 0A1H, 0C1H, 0E1H: Read(o DIV 32, idx)
    | 03H, 23H, 43H, 63H, 0A3H, 0C3H, 0E3H: Read(o DIV 32, sr)
    | 05H, 25H, 45H, 65H, 0A5H, 0C5H, 0E5H: Read(o DIV 32, dp)
    | 07H, 27H, 47H, 67H, 0A7H, 0C7H, 0E7H: Read(o DIV 32, idl)
    | 09H, 29H, 49H, 69H, 0A9H, 0C9H, 0E9H: Read(o DIV 32, imm)
    | 0DH, 2DH, 4DH, 6DH, 0ADH, 0CDH, 0EDH: Read(o DIV 32, ab)
    | 0FH, 2FH, 4FH, 6FH, 0AFH, 0CFH, 0EFH: Read(o DIV 32, abl)
    | 11H, 31H, 51H, 71H, 0B1H, 0D1H, 0F1H: Read(o DIV 32, idy)
    | 12H, 32H, 52H, 72H, 0B2H, 0D2H, 0F2H: Read(o DIV 32, idp)
    | 13H, 33H, 53H, 73H, 0B3H, 0D3H, 0F3H: Read(o DIV 32, sry)
    | 15H, 35H, 55H, 75H, 0B5H, 0D5H, 0F5H: Read(o DIV 32, dpx)
    | 17H, 37H, 57H, 77H, 0B7H, 0D7H, 0F7H: Read(o DIV 32, ily)
    | 19H, 39H, 59H, 79H, 0B9H, 0D9H, 0F9H: Read(o DIV 32, aby)
    | 1DH, 3DH, 5DH, 7DH, 0BDH, 0DDH, 0FDH: Read(o DIV 32, abx)
    | 1FH, 3FH, 5FH, 7FH, 0BFH, 0DFH, 0FFH: Read(o DIV 32, alx)
    | 81H: Store(opSta, idx)
    | 83H: Store(opSta, sr)
    | 85H: Store(opSta, dp)
    | 87H: Store(opSta, idl)
    | 8DH: Store(opSta, ab)
    | 8FH: Store(opSta, abl)
    | 91H: Store(opSta, idy)
    | 92H: Store(opSta, idp)
    | 93H: Store(opSta, sry)
    | 95H: Store(opSta, dpx)
    | 97H: Store(opSta, ily)
    | 99H: Store(opSta, aby)
    | 9DH: Store(opSta, abx)
    | 9FH: Store(opSta, alx)
    (* the index registers, BIT, STZ *)
    | 0A2H: Read(opLdx, imm)
    | 0A6H: Read(opLdx, dp)
    | 0AEH: Read(opLdx, ab)
    | 0B6H: Read(opLdx, dpy)
    | 0BEH: Read(opLdx, aby)
    | 0A0H: Read(opLdy, imm)
    | 0A4H: Read(opLdy, dp)
    | 0ACH: Read(opLdy, ab)
    | 0B4H: Read(opLdy, dpx)
    | 0BCH: Read(opLdy, abx)
    | 0E0H: Read(opCpx, imm)
    | 0E4H: Read(opCpx, dp)
    | 0ECH: Read(opCpx, ab)
    | 0C0H: Read(opCpy, imm)
    | 0C4H: Read(opCpy, dp)
    | 0CCH: Read(opCpy, ab)
    | 86H: Store(opStx, dp)
    | 8EH: Store(opStx, ab)
    | 96H: Store(opStx, dpy)
    | 84H: Store(opSty, dp)
    | 8CH: Store(opSty, ab)
    | 94H: Store(opSty, dpx)
    | 64H: Store(opStz, dp)
    | 74H: Store(opStz, dpx)
    | 9CH: Store(opStz, ab)
    | 9EH: Store(opStz, abx)
    | 24H: Read(opBit, dp)
    | 2CH: Read(opBit, ab)
    | 34H: Read(opBit, dpx)
    | 3CH: Read(opBit, abx)
    | 89H: v := Prg(); IF Mw() THEN v := v + Prg() * 256 END; fZ := B(AND(Av(), v) = 0)
    (* read-modify-write *)
    | 06H: Rmw(opAsl, dp)
    | 0EH: Rmw(opAsl, ab)
    | 16H: Rmw(opAsl, dpx)
    | 1EH: Rmw(opAsl, abx)
    | 26H: Rmw(opRol, dp)
    | 2EH: Rmw(opRol, ab)
    | 36H: Rmw(opRol, dpx)
    | 3EH: Rmw(opRol, abx)
    | 46H: Rmw(opLsr, dp)
    | 4EH: Rmw(opLsr, ab)
    | 56H: Rmw(opLsr, dpx)
    | 5EH: Rmw(opLsr, abx)
    | 66H: Rmw(opRor, dp)
    | 6EH: Rmw(opRor, ab)
    | 76H: Rmw(opRor, dpx)
    | 7EH: Rmw(opRor, abx)
    | 0C6H: Rmw(opDec, dp)
    | 0CEH: Rmw(opDec, ab)
    | 0D6H: Rmw(opDec, dpx)
    | 0DEH: Rmw(opDec, abx)
    | 0E6H: Rmw(opInc, dp)
    | 0EEH: Rmw(opInc, ab)
    | 0F6H: Rmw(opInc, dpx)
    | 0FEH: Rmw(opInc, abx)
    | 04H: Rmw(opTsb, dp)
    | 0CH: Rmw(opTsb, ab)
    | 14H: Rmw(opTrb, dp)
    | 1CH: Rmw(opTrb, ab)
    | 0AH: RmwA(opAsl)
    | 2AH: RmwA(opRol)
    | 4AH: RmwA(opLsr)
    | 6AH: RmwA(opRor)
    | 1AH: RmwA(opInc)
    | 3AH: RmwA(opDec)
    (* branches *)
    | 10H: Branch(fN = 0)
    | 30H: Branch(fN # 0)
    | 50H: Branch(fV = 0)
    | 70H: Branch(fV # 0)
    | 90H: Branch(fC = 0)
    | 0B0H: Branch(fC # 0)
    | 0D0H: Branch(fZ = 0)
    | 0F0H: Branch(fZ # 0)
    | 80H: Branch(TRUE)
    | 82H: lo := Prg(); hi := Prg(); IoOp; PC := W16(PC + hi * 256 + lo)
    (* jumps, calls, returns *)
    | 4CH: lo := Prg(); hi := Prg(); PC := hi * 256 + lo
    | 5CH: lo := Prg(); hi := Prg(); bk := Prg(); PBR := bk; PC := hi * 256 + lo
    | 6CH: lo := Prg(); hi := Prg(); p := hi * 256 + lo;
        lo := Rd(p); hi := Rd(W16(p + 1)); PC := hi * 256 + lo
    | 7CH: lo := Prg(); hi := Prg(); IoOp; p := W16(hi * 256 + lo + X);
        lo := Rd(Join(PBR, p)); hi := Rd(Join(PBR, p + 1)); PC := hi * 256 + lo
    | 0DCH: lo := Prg(); hi := Prg(); p := hi * 256 + lo;
        lo := Rd(p); hi := Rd(W16(p + 1)); bk := Rd(W16(p + 2)); PBR := bk; PC := hi * 256 + lo
    | 20H: lo := Prg(); hi := Prg(); IoOp; t := W16(PC - 1); Push(Hi(t)); Push(Lo(t));
        PC := hi * 256 + lo
    | 22H: lo := Prg(); hi := Prg(); PushN(PBR); Io(W16(S + 1)); bk := Prg(); t := W16(PC - 1);
        PushN(Hi(t)); PushN(Lo(t)); Page1; PBR := bk; PC := hi * 256 + lo
    | 0FCH: lo := Prg(); PushN(Hi(PC)); PushN(Lo(PC)); hi := Prg(); IoOp;
        p := W16(hi * 256 + lo + X); lo := Rd(Join(PBR, p)); hi := Rd(Join(PBR, p + 1)); Page1;
        PC := hi * 256 + lo
    | 60H: IoPC; IoPC; lo := Pull(); hi := Pull(); Io(S); PC := W16(hi * 256 + lo + 1)
    | 6BH: IoPC; IoPC; lo := PullN(); hi := PullN(); bk := PullN(); Page1;
        PBR := bk; PC := W16(hi * 256 + lo + 1)
    | 40H: IoPC; IoPC; SetP(Pull()); lo := Pull(); hi := Pull();
        IF fE = 0 THEN PBR := Pull() END; PC := hi * 256 + lo
    | 00H: t := Prg(); Enter(1, 0FFFEH, 0FFE6H)
    | 02H: t := Prg(); Enter(1, 0FFF4H, 0FFE4H)
    (* the stack *)
    | 08H: IoPC; Push(PushedP(1))
    | 28H: IoPC; IoPC; SetP(Pull())
    | 48H: IoPC; IF Mw() THEN Push(Hi(A)) END; Push(Lo(A))
    | 0DAH: IoPC; IF Xw() THEN Push(Hi(X)) END; Push(Lo(X))
    | 5AH: IoPC; IF Xw() THEN Push(Hi(Y)) END; Push(Lo(Y))
    | 68H: IoPC; IoPC; v := Pull(); IF Mw() THEN v := v + Pull() * 256 END; LdA(v)
    | 0FAH: IoPC; IoPC; v := Pull(); IF Xw() THEN v := v + Pull() * 256 END; LdX(v)
    | 7AH: IoPC; IoPC; v := Pull(); IF Xw() THEN v := v + Pull() * 256 END; LdY(v)
    | 8BH: IoPC; Push(DBR)
    | 4BH: IoPC; Push(PBR)
    | 0ABH: IoPC; IoPC; DBR := PullN(); Page1; NZ(DBR, FALSE)
    | 0BH: IoPC; PushN(Hi(D)); PushN(Lo(D)); Page1
    | 2BH: IoPC; IoPC; lo := PullN(); hi := PullN(); Page1; D := hi * 256 + lo; NZ(D, TRUE)
    | 0F4H: lo := Prg(); hi := Prg(); PushN(hi); PushN(lo); Page1
    | 0D4H: lo := Prg(); DpPenalty; p := lo; lo := Rd(W16(D + p)); hi := Rd(W16(D + p + 1));
        PushN(hi); PushN(lo); Page1
    | 62H: lo := Prg(); hi := Prg(); IoOp; t := W16(PC + hi * 256 + lo);
        PushN(Hi(t)); PushN(Lo(t)); Page1
    (* the flags *)
    | 18H: IoPC; fC := 0
    | 38H: IoPC; fC := 1
    | 58H: IoPC; fI := 0
    | 78H: IoPC; fI := 1
    | 0B8H: IoPC; fV := 0
    | 0D8H: IoPC; fD := 0
    | 0F8H: IoPC; fD := 1
    | 0C2H: v := Prg(); IoOp; SetP(AND(GetP(), 0FFH - v))
    | 0E2H: v := Prg(); IoOp; SetP(ORA(GetP(), v))
    | 0FBH: IoPC; t := fE; fE := fC; fC := t;
        IF fE # 0 THEN fM := 1; fX := 1; X := Lo(X); Y := Lo(Y); S := 100H + Lo(S) END
    (* transfers, steps *)
    | 0AAH: IoPC; LdX(A)
    | 0A8H: IoPC; LdY(A)
    | 8AH: IoPC; LdA(X)
    | 98H: IoPC; LdA(Y)
    | 0BAH: IoPC; LdX(S)
    | 9AH: IoPC; IF fE # 0 THEN S := 100H + Lo(X) ELSE S := X END
    | 9BH: IoPC; LdY(X)
    | 0BBH: IoPC; LdX(Y)
    | 1BH: IoPC; IF fE # 0 THEN S := 100H + Lo(A) ELSE S := W16(A) END
    | 3BH: IoPC; A := S; NZ(A, TRUE)
    | 5BH: IoPC; D := W16(A); NZ(D, TRUE)
    | 7BH: IoPC; A := D; NZ(A, TRUE)
    | 0E8H: IoPC; LdX(X + 1)
    | 0CAH: IoPC; LdX(X - 1)
    | 0C8H: IoPC; LdY(Y + 1)
    | 88H: IoPC; LdY(Y - 1)
    | 0EBH: IoPC; IoPC; A := Lo(A) * 256 + Hi(A); NZ(A, FALSE)
    (* the rest *)
    | 54H: Move(TRUE)
    | 44H: Move(FALSE)
    | 0CBH: IoPC; IoPC; waiting := TRUE
    | 0DBH: IoPC; IoPC; stopped := TRUE
    | 42H: IoPC; PC := W16(PC + 1)                  (* WDM: its byte not read *)
    | 0EAH: IoPC
    END
  END Execute;

  PROCEDURE Show(o: INTEGER);
    VAR e: INTEGER;
  BEGIN e := EmHost.err;
    EmHost.Hex(e, opAt, 6); EmHost.Str(e, " "); EmHost.Hex(e, o, 2);
    EmHost.Str(e, "  A="); EmHost.Hex(e, A, 4); EmHost.Str(e, " X="); EmHost.Hex(e, X, 4);
    EmHost.Str(e, " Y="); EmHost.Hex(e, Y, 4); EmHost.Str(e, " S="); EmHost.Hex(e, S, 4);
    EmHost.Str(e, " D="); EmHost.Hex(e, D, 4); EmHost.Str(e, " B="); EmHost.Hex(e, DBR, 2);
    EmHost.Str(e, " P="); EmHost.Hex(e, GetP(), 2); IF fE # 0 THEN EmHost.Str(e, " e") END;
    EmHost.Str(e, "  "); EmHost.Int(e, cycles); EmHost.Ln(e)
  END Show;

  (* One instruction, or an interrupt's entry, or a cycle of WAI *)
  PROCEDURE Step*;
    VAR v: INTEGER;
  BEGIN
    IF waiting THEN
      IF nmi OR irqLine() THEN waiting := FALSE ELSE IoPC END
    END;
    IF ~waiting & ~stopped THEN
      IF nmi THEN nmi := FALSE; Interrupt(0FFFAH, 0FFEAH)
      ELSIF (fI = 0) & irqLine() THEN Interrupt(0FFFEH, 0FFEEH)
      ELSE v := Op(); IF trace THEN Show(v) END; Execute(v)
      END
    END
  END Step;

  (* RESB: emulation mode, the vector at $00FFFC *)
  PROCEDURE Reset*;
    VAR i, lo, hi: INTEGER;
  BEGIN
    fE := 1; fM := 1; fX := 1; fD := 0; fI := 1; X := Lo(X); Y := Lo(Y); S := 100H + Lo(S);
    D := 0; DBR := 0; PBR := 0; stopped := FALSE; waiting := FALSE; nmi := FALSE;
    FOR i := 1 TO 5 DO IoPC END;
    lo := Cycle(0FFFCH, vda + vpb, 0); hi := Cycle(0FFFDH, vda + vpb, 0); PC := hi * 256 + lo
  END Reset;

  (* The registers as they are given, for em16 -harte816 *)
  PROCEDURE SetState*(pc, s, p, a, x, y, dbr, d, pbr, e: INTEGER);
  BEGIN PC := pc; S := s; A := a; X := x; Y := y; DBR := dbr; D := d; PBR := pbr; fE := e;
    fN := Bit(p, 7); fV := Bit(p, 6); fM := Bit(p, 5); fX := Bit(p, 4);
    fD := Bit(p, 3); fI := Bit(p, 2); fZ := Bit(p, 1); fC := Bit(p, 0);
    stopped := FALSE; waiting := FALSE; nmi := FALSE
  END SetState;

END EmW816.
