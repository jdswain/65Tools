MODULE EmCore; (* The 65C816 of the Tang Nano 20K SoC: cpu_65c816.v of
   ../../Verilog65C816, translated state for state.

   The core is a state machine with one bus cycle a state and no dummy
   cycles; so is this. Step runs one state: the bus access of that state
   (or an internal cycle) through the procedures the system has set with
   SetBus, which add the wait states, then the transition. A Verilog
   clock edge assigns every register at once from the values before it;
   here the assignments are ordered so that each reads the old values,
   as there.

   Its semantics are those of the WDC chip, which the core was checked
   against with the SingleStepTests vectors (em16 -harte checks this
   module against the same), and so differ from em16's own CPU (EmCPU):
   TCD sets N and Z, JMP keeps the program bank, PEI pushes the pointer,
   TXS with 8 bit index registers clears the high byte of S, the new
   stack instructions cross pages in emulation mode, decimal arithmetic
   takes its flags as the 65C816 does. What is the core's own: its cycle
   counts, WDM is a two byte no-operation, a block move takes two cycles
   a byte and an interrupt between bytes. ABORT and NMI are not wired on
   the SoC and are left out.

   For em16, a fetch from 00:0000 stops the processor, and so does STP. *)

  IMPORT EmHost, EmSym;

  CONST
    (* states *)
    sFetch = 0; sOp1 = 1; sOp2 = 2; sOp3 = 3; sPtrL = 4; sPtrH = 5; sPtrB = 6;
    sRdL = 7; sRdH = 8; sWrL = 9; sWrH = 10; sWbL = 11; sWbH = 12; sPush = 13; sPull = 14;
    sVecL = 15; sVecH = 16; sMvR = 17; sMvW = 18; sWai = 19; sStp = 20;
    (* addressing modes *)
    mdnon = 0; mdimm = 1; mddp = 2; mddpx = 3; mddpy = 4; mdabs = 5; mdabx = 6; mdaby = 7;
    mdabl = 8; mdalx = 9; mdidx = 10; mdidp = 11; mdidy = 12; mdidl = 13; mdily = 14;
    mdsr = 15; mdsry = 16; mdrel = 17; mdrll = 18; mdiab = 19; mdiax = 20; mdial = 21;
    (* classes *)
    clspc = 0; clrd = 1; clwr = 2; clmw = 3; cljmp = 4; cljsr = 5;
    (* operations *)
    opora = 0; opand = 1; opeor = 2; opadc = 3; opsbc = 4; opcmp = 5; oplda = 6; opbit = 7;
    opldx = 8; opldy = 9; opcpx = 10; opcpy = 11; opsta = 12; opstx = 13; opsty = 14;
    opstz = 15; opasl = 16; oprol = 17; oplsr = 18; opror = 19; opinc = 20; opdec = 21;
    optsb = 22; optrb = 23; oprep = 24; opsep = 25; opnop = 26;
    (* after the last push *)
    ppFetch = 0; ppVec = 1; ppPtr = 2;

  TYPE
    Reader* = PROCEDURE (addr: INTEGER): INTEGER;
    Writer* = PROCEDURE (addr, data: INTEGER);
    Idler* = PROCEDURE;
    Line* = PROCEDURE (): BOOLEAN;

  VAR
    (* the registers *)
    A*, X*, Y*, S*, D*, PC*, DBR*, PBR*: INTEGER;
    fC*, fZ*, fI*, fD*, fX*, fM*, fV*, fN*, fE*: INTEGER;
    (* the state machine *)
    state*, IR: INTEGER;
    dMode, dCls, dOp: INTEGER;
    tlo, tmid, tptr, ptrBank, taddr, tdata: INTEGER;
    wrap16, stk16: BOOLEAN;
    pushQ: ARRAY 4 OF INTEGER;    (* bytes to push, the first at pushQ[0] *)
    pushN, postPush, pullIdx, vec: INTEGER;
    irq1, irq2: BOOLEAN;          (* the IRQ input's synchronizer; TRUE: asserted *)
    stopped*, trace*: BOOLEAN;
    (* the decode table *)
    mode, cls, op: ARRAY 256 OF INTEGER;
    mnem: ARRAY 800 OF CHAR;
    (* the bus *)
    read, peek: Reader; write: Writer; idle: Idler; irqLine: Line;

  PROCEDURE SetTrace*(on: BOOLEAN);
  BEGIN trace := on
  END SetTrace;

  PROCEDURE SetBus*(r, p: Reader; w: Writer; i: Idler; irq: Line);
  BEGIN read := r; peek := p; write := w; idle := i; irqLine := irq
  END SetBus;

  (* --- helpers --- *)

  PROCEDURE M16(): BOOLEAN;
  BEGIN RETURN (fE = 0) & (fM = 0)
  END M16;

  PROCEDURE X16(): BOOLEAN;
  BEGIN RETURN (fE = 0) & (fX = 0)
  END X16;

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
  BEGIN v := AND(v, 0FFH); IF v >= 80H THEN v := v - 100H END; RETURN v
  END Sext8;

  (* the accumulator as wide as it is *)
  PROCEDURE Av(): INTEGER;
    VAR r: INTEGER;
  BEGIN IF M16() THEN r := A ELSE r := Lo(A) END; RETURN r
  END Av;

  PROCEDURE Pbyte(brk: INTEGER): INTEGER;
    VAR m, x: INTEGER;
  BEGIN
    IF fE # 0 THEN m := 1; x := brk ELSE m := fM; x := fX END;
    RETURN fN * 128 + fV * 64 + m * 32 + x * 16 + fD * 8 + fI * 4 + fZ * 2 + fC
  END Pbyte;

  PROCEDURE LdA(v: INTEGER);
  BEGIN
    IF M16() THEN A := W16(v); fN := Bit(A, 15); fZ := B(A = 0)
    ELSE A := ORA(AND(A, 0FF00H), Lo(v)); fN := Bit(v, 7); fZ := B(Lo(v) = 0)
    END
  END LdA;

  PROCEDURE LdX(v: INTEGER);
  BEGIN
    IF X16() THEN X := W16(v); fN := Bit(X, 15); fZ := B(X = 0)
    ELSE X := Lo(v); fN := Bit(v, 7); fZ := B(X = 0)
    END
  END LdX;

  PROCEDURE LdY(v: INTEGER);
  BEGIN
    IF X16() THEN Y := W16(v); fN := Bit(Y, 15); fZ := B(Y = 0)
    ELSE Y := Lo(v); fN := Bit(v, 7); fZ := B(Y = 0)
    END
  END LdY;

  (* P := v, by PLP, RTI, REP, SEP *)
  PROCEDURE SetP(v: INTEGER);
  BEGIN
    fN := Bit(v, 7); fV := Bit(v, 6); fD := Bit(v, 3); fI := Bit(v, 2); fZ := Bit(v, 1); fC := Bit(v, 0);
    IF fE = 0 THEN
      fM := Bit(v, 5); fX := Bit(v, 4);
      IF fX # 0 THEN X := Lo(X); Y := Lo(Y) END
    END
  END SetP;

  PROCEDURE CmpFlags(r, m: INTEGER; w: BOOLEAN);
    VAR t: INTEGER;
  BEGIN
    IF w THEN t := W16(r) + 0FFFFH - W16(m) + 1;
      fC := Bit(t, 16); fN := Bit(t, 15); fZ := B(W16(t) = 0)
    ELSE t := Lo(r) + 0FFH - Lo(m) + 1;
      fC := Bit(t, 8); fN := Bit(t, 7); fZ := B(Lo(t) = 0)
    END
  END CmpFlags;

  (* decimal add of the low 2 (w FALSE) or 4 digits; c the carry in and
     out, top the result's top bit before the last correction *)
  PROCEDURE DAdd(a, b, cin: INTEGER; w: BOOLEAN; VAR c, top: INTEGER): INTEGER;
    VAR n0, n1, n2, n3, c0, c1, c2, c3, r: INTEGER;
  BEGIN
    n0 := AND(a, 0FH) + AND(b, 0FH) + cin; c0 := B(n0 > 9); IF c0 # 0 THEN n0 := n0 + 6 END;
    n1 := AND(a DIV 10H, 0FH) + AND(b DIV 10H, 0FH) + c0;
    IF ~w THEN top := Bit(n1, 3) END;
    c1 := B(n1 > 9); IF c1 # 0 THEN n1 := n1 + 6 END;
    n2 := AND(a DIV 100H, 0FH) + AND(b DIV 100H, 0FH) + c1; c2 := B(n2 > 9); IF c2 # 0 THEN n2 := n2 + 6 END;
    n3 := AND(a DIV 1000H, 0FH) + AND(b DIV 1000H, 0FH) + c2;
    IF w THEN top := Bit(n3, 3) END;
    c3 := B(n3 > 9); IF c3 # 0 THEN n3 := n3 + 6 END;
    IF w THEN c := c3; r := AND(n3, 0FH) * 1000H + AND(n2, 0FH) * 100H + AND(n1, 0FH) * 10H + AND(n0, 0FH)
    ELSE c := c1; r := AND(n1, 0FH) * 10H + AND(n0, 0FH)
    END;
    RETURN r
  END DAdd;

  (* a - b decimal, cin the inverted borrow *)
  PROCEDURE DSub(a, b, cin: INTEGER; w: BOOLEAN; VAR c: INTEGER): INTEGER;
    VAR n0, n1, n2, n3, c0, c1, c2, c3, r: INTEGER;
  BEGIN
    n0 := AND(a, 0FH) + 0FH - AND(b, 0FH) + cin; c0 := Bit(n0, 4); IF c0 = 0 THEN n0 := n0 - 6 END;
    n1 := AND(a DIV 10H, 0FH) + 0FH - AND(b DIV 10H, 0FH) + c0; c1 := Bit(n1, 4); IF c1 = 0 THEN n1 := n1 - 6 END;
    n2 := AND(a DIV 100H, 0FH) + 0FH - AND(b DIV 100H, 0FH) + c1; c2 := Bit(n2, 4); IF c2 = 0 THEN n2 := n2 - 6 END;
    n3 := AND(a DIV 1000H, 0FH) + 0FH - AND(b DIV 1000H, 0FH) + c2; c3 := Bit(n3, 4); IF c3 = 0 THEN n3 := n3 - 6 END;
    IF w THEN c := c3; r := AND(n3, 0FH) * 1000H + AND(n2, 0FH) * 100H + AND(n1, 0FH) * 10H + AND(n0, 0FH)
    ELSE c := c1; r := AND(n1, 0FH) * 10H + AND(n0, 0FH)
    END;
    RETURN r
  END DSub;

  PROCEDURE Adc(m: INTEGER);
    VAR t, c, top, r: INTEGER;
  BEGIN
    IF fD # 0 THEN
      r := DAdd(Av(), m, fC, M16(), c, top);
      IF M16() THEN fV := B((Bit(A, 15) = Bit(m, 15)) & (Bit(A, 15) # top))
      ELSE fV := B((Bit(A, 7) = Bit(m, 7)) & (Bit(A, 7) # top))
      END;
      fC := c; LdA(r)
    ELSIF M16() THEN t := A + W16(m) + fC;
      fV := B((Bit(A, 15) = Bit(m, 15)) & (Bit(A, 15) # Bit(t, 15))); fC := Bit(t, 16); LdA(t)
    ELSE t := Lo(A) + Lo(m) + fC;
      fV := B((Bit(A, 7) = Bit(m, 7)) & (Bit(A, 7) # Bit(t, 7))); fC := Bit(t, 8); LdA(t)
    END
  END Adc;

  PROCEDURE Sbc(m: INTEGER);
    VAR t, c, r: INTEGER;
  BEGIN
    IF fD # 0 THEN
      r := DSub(Av(), m, fC, M16(), c);
      IF M16() THEN t := A + 0FFFFH - W16(m) + fC; fV := B((Bit(A, 15) # Bit(m, 15)) & (Bit(A, 15) # Bit(t, 15)))
      ELSE t := Lo(A) + 0FFH - Lo(m) + fC; fV := B((Bit(A, 7) # Bit(m, 7)) & (Bit(A, 7) # Bit(t, 7)))
      END;
      fC := c; LdA(r)
    ELSIF M16() THEN t := A + 0FFFFH - W16(m) + fC;
      fV := B((Bit(A, 15) # Bit(m, 15)) & (Bit(A, 15) # Bit(t, 15))); fC := Bit(t, 16); LdA(t)
    ELSE t := Lo(A) + 0FFH - Lo(m) + fC;
      fV := B((Bit(A, 7) # Bit(m, 7)) & (Bit(A, 7) # Bit(t, 7))); fC := Bit(t, 8); LdA(t)
    END
  END Sbc;

  (* the read class with its whole operand *)
  PROCEDURE ExecRd(m: INTEGER);
    VAR o: INTEGER;
  BEGIN o := dOp;
    CASE o OF
      opora: LdA(ORA(Av(), m))
    | opand: LdA(AND(Av(), m))
    | opeor: LdA(EOR(Av(), m))
    | opadc: Adc(m)
    | opsbc: Sbc(m)
    | opcmp: CmpFlags(Av(), m, M16())
    | oplda: LdA(m)
    | opldx: LdX(m)
    | opldy: LdY(m)
    | opcpx: CmpFlags(X, m, X16())
    | opcpy: CmpFlags(Y, m, X16())
    | opbit:
        fZ := B(AND(Av(), m) = 0);
        IF IR # 89H THEN
          IF M16() THEN fN := Bit(m, 15); fV := Bit(m, 14) ELSE fN := Bit(m, 7); fV := Bit(m, 6) END
        END
    | oprep: SetP(AND(Pbyte(fX), 0FFH - Lo(m)))
    | opsep: SetP(ORA(Pbyte(fX), Lo(m)))
    ELSE (* WDM *)
    END
  END ExecRd;

  (* shift, step, test-and-set: result to A or to tdata *)
  PROCEDURE RmwCore(o, m: INTEGER; toA: BOOLEAN);
    VAR r, c: INTEGER; setc: BOOLEAN;
  BEGIN c := fC; setc := TRUE;
    IF o = opasl THEN r := W16(m * 2); IF M16() THEN c := Bit(m, 15) ELSE c := Bit(m, 7) END
    ELSIF o = oprol THEN r := W16(m * 2 + fC); IF M16() THEN c := Bit(m, 15) ELSE c := Bit(m, 7) END
    ELSIF o = oplsr THEN
      IF M16() THEN r := W16(m) DIV 2 ELSE r := Lo(m) DIV 2 END; c := Bit(m, 0)
    ELSIF o = opror THEN
      IF M16() THEN r := W16(m) DIV 2 + fC * 8000H ELSE r := Lo(m) DIV 2 + fC * 80H END; c := Bit(m, 0)
    ELSIF o = opinc THEN r := W16(m + 1); setc := FALSE
    ELSIF o = opdec THEN r := W16(m - 1); setc := FALSE
    ELSIF o = optsb THEN r := ORA(W16(m), Av()); setc := FALSE
    ELSIF o = optrb THEN r := AND(W16(m), 0FFFFH - Av()); setc := FALSE
    ELSE r := W16(m); setc := FALSE
    END;
    IF setc THEN fC := c END;
    IF (o = optsb) OR (o = optrb) THEN fZ := B(AND(Av(), m) = 0)
    ELSIF M16() THEN fN := Bit(r, 15); fZ := B(r = 0)
    ELSE fN := Bit(r, 7); fZ := B(Lo(r) = 0)
    END;
    IF toA THEN
      IF M16() THEN A := r ELSE A := ORA(AND(A, 0FF00H), Lo(r)) END
    ELSE tdata := r
    END
  END RmwCore;

  PROCEDURE Push8(v: INTEGER);
  BEGIN pushQ[0] := Lo(v); pushN := 1; stk16 := FALSE; postPush := ppFetch; state := sPush
  END Push8;

  PROCEDURE Push16(v: INTEGER);
  BEGIN pushQ[0] := Hi(v); pushQ[1] := Lo(v); pushN := 2; stk16 := TRUE; postPush := ppFetch; state := sPush
  END Push16;

  PROCEDURE SDec;
  BEGIN
    IF (fE # 0) & ~stk16 THEN S := 100H + Lo(S - 1) ELSE S := W16(S - 1) END
  END SDec;

  PROCEDURE SInc;
  BEGIN
    IF (fE # 0) & ~stk16 THEN S := 100H + Lo(S + 1) ELSE S := W16(S + 1) END
  END SInc;

  (* interrupt entry: IRQ, BRK, COP *)
  PROCEDURE IntEntry(pushedPC, brk, v: INTEGER);
  BEGIN
    IF fE # 0 THEN
      pushQ[0] := Hi(pushedPC); pushQ[1] := Lo(pushedPC); pushQ[2] := Pbyte(brk); pushN := 3
    ELSE
      pushQ[0] := PBR; pushQ[1] := Hi(pushedPC); pushQ[2] := Lo(pushedPC); pushQ[3] := Pbyte(brk); pushN := 4
    END;
    fI := 1; fD := 0; PBR := 0; vec := v;
    postPush := ppVec; stk16 := FALSE; state := sPush
  END IntEntry;

  PROCEDURE Rd16(): BOOLEAN;
    VAR r: BOOLEAN;
  BEGIN
    IF (dOp = oprep) OR (dOp = opsep) OR (dOp = opnop) THEN r := FALSE
    ELSIF (dOp = opldx) OR (dOp = opldy) OR (dOp = opcpx) OR (dOp = opcpy) OR (dOp = opstx) OR (dOp = opsty) THEN r := X16()
    ELSE r := M16()
    END;
    RETURN r
  END Rd16;

  PROCEDURE St16(): BOOLEAN;
    VAR r: BOOLEAN;
  BEGIN
    IF (dOp = opldx) OR (dOp = opldy) OR (dOp = opcpx) OR (dOp = opcpy) OR (dOp = opstx) OR (dOp = opsty) THEN r := X16()
    ELSE r := M16()
    END;
    RETURN r
  END St16;

  PROCEDURE StVal(): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF dOp = opsta THEN r := A ELSIF dOp = opstx THEN r := X ELSIF dOp = opsty THEN r := Y ELSE r := 0 END;
    RETURN r
  END StVal;

  PROCEDURE Taddr1(): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF wrap16 THEN r := ORA(AND(taddr, 0FF0000H), W16(taddr + 1)) ELSE r := A24(taddr + 1) END;
    RETURN r
  END Taddr1;

  PROCEDURE SpPush(): INTEGER;
    VAR r: INTEGER;
  BEGIN IF (fE # 0) & ~stk16 THEN r := 100H + Lo(S) ELSE r := S END; RETURN r
  END SpPush;

  PROCEDURE SpPull(): INTEGER;
    VAR r: INTEGER;
  BEGIN IF (fE # 0) & ~stk16 THEN r := 100H + Lo(S + 1) ELSE r := W16(S + 1) END; RETURN r
  END SpPull;

  PROCEDURE Dpw(): BOOLEAN;      (* direct page wrap: E and DL = 0 *)
  BEGIN RETURN (fE # 0) & (Lo(D) = 0)
  END Dpw;

  PROCEDURE Intr(): BOOLEAN;
  BEGIN RETURN irq2 & (fI = 0)
  END Intr;

  PROCEDURE Btake(): BOOLEAN;
    VAR r: BOOLEAN; f, s: INTEGER;
  BEGIN s := Bit(IR, 5); f := IR DIV 40H;
    IF f = 0 THEN r := fN = s
    ELSIF f = 1 THEN r := fV = s
    ELSIF f = 2 THEN r := (fC = s) OR (IR = 80H)
    ELSE r := fZ = s
    END;
    RETURN r
  END Btake;

  PROCEDURE Decode(o: INTEGER);
  BEGIN IR := o; dMode := mode[o]; dCls := cls[o]; dOp := op[o]
  END Decode;

  (* the next state of a read, write or read-modify-write *)
  PROCEDURE DataState(): INTEGER;
    VAR r: INTEGER;
  BEGIN IF dCls = clwr THEN r := sWrL ELSE r := sRdL END; RETURN r
  END DataState;

  (* --- the trace --- *)

  PROCEDURE ErrStr(s: ARRAY OF CHAR);
  BEGIN EmHost.Str(EmHost.err, s)
  END ErrStr;

  PROCEDURE Flag(f: INTEGER; ch: CHAR);
  BEGIN IF f # 0 THEN EmHost.Ch(EmHost.err, ch) ELSE EmHost.Ch(EmHost.err, ".") END
  END Flag;

  (* an instruction as it starts: where, the opcode, the registers *)
  PROCEDURE Trace(o: INTEGER; cycles: LONGINT);
    VAR i: INTEGER;
  BEGIN
    EmSym.Word(PBR * 10000H + PC); EmHost.Ch(EmHost.err, " "); EmHost.ToHex(EmHost.err, o, 2);
    EmHost.Ch(EmHost.err, " ");
    FOR i := 0 TO 2 DO EmHost.Ch(EmHost.err, mnem[o * 3 + i]) END;
    ErrStr(" A="); EmHost.ToHex(EmHost.err, A, 4); ErrStr(" X="); EmHost.ToHex(EmHost.err, X, 4);
    ErrStr(" Y="); EmHost.ToHex(EmHost.err, Y, 4); ErrStr(" S="); EmHost.ToHex(EmHost.err, S, 4);
    ErrStr(" D="); EmHost.ToHex(EmHost.err, D, 4); ErrStr(" DB="); EmHost.ToHex(EmHost.err, DBR, 2);
    ErrStr(" P="); Flag(fN, "N"); Flag(fV, "V"); Flag(fM, "M"); Flag(fX, "X");
    Flag(fD, "D"); Flag(fI, "I"); Flag(fZ, "Z"); Flag(fC, "C");
    ErrStr(" E="); EmHost.ToHex(EmHost.err, fE, 1);
    ErrStr(" "); EmHost.Int(EmHost.err, cycles);
    EmHost.Ln(EmHost.err)
  END Trace;

  (* --- the state machine --- *)

  (* The fetch state: an interrupt, or an opcode read and the one cycle
     instructions done at once. *)
  PROCEDURE Fetch(cycles: LONGINT);
    VAR o, t: INTEGER;
  BEGIN
    IF Intr() THEN idle; IntEntry(PC, 0, 0FFEEH + 10H * fE)   (* IRQ: native $FFEE, emulation $FFFE *)
    ELSIF (PBR = 0) & (PC = 0) THEN stopped := TRUE; idle
    ELSE
      IF trace THEN Trace(peek(PBR * 10000H + PC), cycles) END;
      o := read(PBR * 10000H + PC);
      PC := W16(PC + 1);
      CASE o OF
        18H: fC := 0
      | 38H: fC := 1
      | 58H: fI := 0
      | 78H: fI := 1
      | 0B8H: fV := 0
      | 0D8H: fD := 0
      | 0F8H: fD := 1
      | 0EAH:
      | 0AH: RmwCore(opasl, Av(), TRUE)
      | 2AH: RmwCore(oprol, Av(), TRUE)
      | 4AH: RmwCore(oplsr, Av(), TRUE)
      | 6AH: RmwCore(opror, Av(), TRUE)
      | 1AH: RmwCore(opinc, Av(), TRUE)
      | 3AH: RmwCore(opdec, Av(), TRUE)
      | 0AAH: LdX(A)
      | 0A8H: LdY(A)
      | 8AH: LdA(X)
      | 98H: LdA(Y)
      | 0BAH: LdX(S)
      | 9AH: IF fE # 0 THEN S := 100H + Lo(X) ELSE S := X END
      | 9BH: LdY(X)
      | 0BBH: LdX(Y)
      | 1BH: IF fE # 0 THEN S := 100H + Lo(A) ELSE S := A END
      | 3BH: A := S; fN := Bit(S, 15); fZ := B(S = 0)
      | 5BH: D := A; fN := Bit(A, 15); fZ := B(A = 0)
      | 7BH: A := D; fN := Bit(D, 15); fZ := B(D = 0)
      | 0E8H: LdX(X + 1)
      | 0CAH: LdX(X - 1)
      | 0C8H: LdY(Y + 1)
      | 88H: LdY(Y - 1)
      | 0EBH: fN := Bit(A, 15); fZ := B(Hi(A) = 0); A := Lo(A) * 256 + Hi(A)
      | 0FBH: t := fE; fE := fC; fC := t;
          IF fE # 0 THEN fM := 1; fX := 1; X := Lo(X); Y := Lo(Y); S := 100H + Lo(S) END
      | 08H: Push8(Pbyte(1))
      | 0BH: Push16(D)
      | 48H: IF M16() THEN Push16(A) ELSE Push8(A) END
      | 4BH: Push8(PBR)
      | 5AH: IF X16() THEN Push16(Y) ELSE Push8(Y) END
      | 8BH: Push8(DBR)
      | 0DAH: IF X16() THEN Push16(X) ELSE Push8(X) END
      | 28H, 2BH, 68H, 7AH, 0ABH, 0FAH, 40H, 60H, 6BH:
          Decode(o); pullIdx := 0; state := sPull;
          stk16 := (o = 2BH) OR (o = 6BH) OR (o = 0ABH)
      | 0CBH: state := sWai
      | 0DBH: state := sStp; stopped := TRUE
      ELSE Decode(o); state := sOp1
      END
    END
  END Fetch;

  PROCEDURE Op1;
    VAR r, pcn, md: INTEGER;
  BEGIN r := read(PBR * 10000H + PC); pcn := W16(PC + 1); PC := pcn;
    IF IR = 00H THEN IntEntry(pcn, 1, 0FFE6H + 18H * fE)            (* BRK: $FFE6 / $FFFE *)
    ELSIF IR = 02H THEN IntEntry(pcn, 1, 0FFE4H + 10H * fE)         (* COP: $FFE4 / $FFF4 *)
    ELSIF (IR = 44H) OR (IR = 54H) THEN DBR := r; state := sOp2     (* MVP/MVN: destination bank *)
    ELSIF (IR = 62H) OR (IR = 0F4H) OR (IR = 82H) THEN tlo := r; state := sOp2
    ELSIF IR = 0D4H THEN                                             (* PEI *)
      IF Dpw() THEN tptr := Hi(D) * 256 + r ELSE tptr := W16(D + r) END;
      ptrBank := 0; state := sPtrL
    ELSE md := dMode;
      CASE md OF
        mdrel: IF Btake() THEN PC := W16(pcn + Sext8(r)) ELSE PC := pcn END; state := sFetch
      | mdimm:
          IF Rd16() THEN tlo := r; state := sOp2 ELSE ExecRd(r); state := sFetch END
      | mddp:
          IF Dpw() THEN taddr := Hi(D) * 256 + r ELSE taddr := W16(D + r) END;
          wrap16 := TRUE; state := DataState()
      | mddpx:
          IF Dpw() THEN taddr := Hi(D) * 256 + Lo(r + X) ELSE taddr := W16(D + r + X) END;
          wrap16 := TRUE; state := DataState()
      | mddpy:
          IF Dpw() THEN taddr := Hi(D) * 256 + Lo(r + Y) ELSE taddr := W16(D + r + Y) END;
          wrap16 := TRUE; state := DataState()
      | mdsr: taddr := W16(S + r); wrap16 := TRUE; state := DataState()
      | mdidx:
          IF Dpw() THEN tptr := Hi(D) * 256 + Lo(r + X) ELSE tptr := W16(D + r + X) END;
          ptrBank := 0; state := sPtrL
      | mdidp, mdidy, mdidl, mdily:
          IF Dpw() THEN tptr := Hi(D) * 256 + r ELSE tptr := W16(D + r) END;
          ptrBank := 0; state := sPtrL
      | mdsry: tptr := W16(S + r); ptrBank := 0; state := sPtrL
      ELSE tlo := r; state := sOp2
      END
    END
  END Op1;

  (* the return address goes first, then on to the pointer or the fetch *)
  PROCEDURE PushPC(after: INTEGER);
  BEGIN pushQ[0] := Hi(PC); pushQ[1] := Lo(PC); pushN := 2; stk16 := FALSE; postPush := after; state := sPush
  END PushPC;

  PROCEDURE Op2;
    VAR r, pcn, md, w: INTEGER;
  BEGIN r := read(PBR * 10000H + PC); pcn := W16(PC + 1); w := r * 256 + tlo;
    IF (IR = 44H) OR (IR = 54H) THEN PC := pcn; tmid := r; state := sMvR
    ELSIF IR = 62H THEN PC := pcn; Push16(pcn + w)                       (* PER *)
    ELSIF IR = 0F4H THEN PC := pcn; Push16(w)                            (* PEA *)
    ELSIF IR = 82H THEN PC := W16(pcn + w); state := sFetch              (* BRL *)
    ELSIF IR = 20H THEN PushPC(ppFetch); PC := w                         (* JSR a: pushes the old PC *)
    ELSIF IR = 0FCH THEN PushPC(ppPtr); PC := pcn; tptr := W16(w + X); ptrBank := PBR   (* JSR (a,X) *)
    ELSIF IR = 4CH THEN PC := w; state := sFetch                         (* JMP a *)
    ELSIF (IR = 6CH) OR (IR = 0DCH) THEN PC := pcn; tptr := w; ptrBank := 0; state := sPtrL
    ELSIF IR = 7CH THEN PC := pcn; tptr := W16(w + X); ptrBank := PBR; state := sPtrL
    ELSE PC := pcn; md := dMode;
      CASE md OF
        mdimm: ExecRd(w); state := sFetch
      | mdabs: taddr := DBR * 10000H + w; wrap16 := FALSE; state := DataState()
      | mdabx: taddr := A24(DBR * 10000H + w + X); wrap16 := FALSE; state := DataState()
      | mdaby: taddr := A24(DBR * 10000H + w + Y); wrap16 := FALSE; state := DataState()
      ELSE tmid := r; state := sOp3
      END
    END
  END Op2;

  PROCEDURE Op3;
    VAR r, oldPC: INTEGER;
  BEGIN r := read(PBR * 10000H + PC); oldPC := PC; PC := W16(PC + 1);
    IF IR = 5CH THEN PBR := r; PC := tmid * 256 + tlo; state := sFetch                 (* JML *)
    ELSIF IR = 22H THEN                                                              (* JSL *)
      pushQ[0] := PBR; pushQ[1] := Hi(oldPC); pushQ[2] := Lo(oldPC); pushN := 3; stk16 := TRUE;
      postPush := ppFetch; PBR := r; PC := tmid * 256 + tlo; state := sPush
    ELSE
      taddr := r * 10000H + tmid * 256 + tlo;
      IF dMode = mdalx THEN taddr := A24(taddr + X) END;
      wrap16 := FALSE; state := DataState()
    END
  END Op3;

  PROCEDURE PtrH;
    VAR r, md: INTEGER;
  BEGIN r := read(ptrBank * 10000H + W16(tptr + 1));
    IF (IR = 6CH) OR (IR = 7CH) OR (IR = 0FCH) THEN PC := r * 256 + tlo; state := sFetch
    ELSIF IR = 0D4H THEN Push16(r * 256 + tlo)
    ELSIF IR = 0DCH THEN tmid := r; state := sPtrB
    ELSE md := dMode;
      IF (md = mdidl) OR (md = mdily) THEN tmid := r; state := sPtrB
      ELSIF (md = mdidy) OR (md = mdsry) THEN
        taddr := A24(DBR * 10000H + r * 256 + tlo + Y); wrap16 := FALSE; state := DataState()
      ELSE taddr := DBR * 10000H + r * 256 + tlo; wrap16 := FALSE; state := DataState()
      END
    END
  END PtrH;

  PROCEDURE PtrB;
    VAR r: INTEGER;
  BEGIN r := read(ptrBank * 10000H + W16(tptr + 2));
    IF IR = 0DCH THEN PC := tmid * 256 + tlo; PBR := r; state := sFetch
    ELSE
      taddr := r * 10000H + tmid * 256 + tlo;
      IF dMode = mdily THEN taddr := A24(taddr + Y) END;
      wrap16 := FALSE; state := DataState()
    END
  END PtrB;

  PROCEDURE RdL;
    VAR r: INTEGER;
  BEGIN r := read(taddr);
    IF Rd16() THEN tlo := r; state := sRdH
    ELSIF dCls = clmw THEN RmwCore(dOp, r, FALSE); state := sWbL
    ELSE ExecRd(r); state := sFetch
    END
  END RdL;

  PROCEDURE RdH;
    VAR r: INTEGER;
  BEGIN r := read(Taddr1());
    IF dCls = clmw THEN RmwCore(dOp, r * 256 + tlo, FALSE); state := sWbL
    ELSE ExecRd(r * 256 + tlo); state := sFetch
    END
  END RdH;

  PROCEDURE PushState;
    VAR i: INTEGER;
  BEGIN write(SpPush(), pushQ[0]);
    SDec;
    FOR i := 0 TO 2 DO pushQ[i] := pushQ[i + 1] END;
    DEC(pushN);
    IF pushN = 0 THEN
      IF (fE # 0) & stk16 THEN S := 100H + Lo(S) END;     (* back to page 1 *)
      IF postPush = ppVec THEN state := sVecL
      ELSIF postPush = ppPtr THEN state := sPtrL
      ELSE state := sFetch
      END
    END
  END PushState;

  PROCEDURE PullState;
    VAR r, o, idx: INTEGER;
  BEGIN r := read(SpPull()); SInc; idx := pullIdx; INC(pullIdx); o := IR;
    IF o = 28H THEN SetP(r); state := sFetch
    ELSIF o = 0ABH THEN DBR := r; fN := Bit(r, 7); fZ := B(r = 0);
      IF fE # 0 THEN S := 100H + Lo(S) END; state := sFetch
    ELSIF o = 2BH THEN
      IF idx = 0 THEN tlo := r
      ELSE D := r * 256 + tlo; fN := Bit(r, 7); fZ := B(D = 0);
        IF fE # 0 THEN S := 100H + Lo(S) END; state := sFetch
      END
    ELSIF (o = 68H) OR (o = 7AH) OR (o = 0FAH) THEN
      IF ((o = 68H) & ~M16()) OR ((o # 68H) & ~X16()) THEN
        IF o = 68H THEN LdA(r) ELSIF o = 7AH THEN LdY(r) ELSE LdX(r) END; state := sFetch
      ELSIF idx = 0 THEN tlo := r
      ELSE
        IF o = 68H THEN LdA(r * 256 + tlo) ELSIF o = 7AH THEN LdY(r * 256 + tlo) ELSE LdX(r * 256 + tlo) END;
        state := sFetch
      END
    ELSIF o = 60H THEN
      IF idx = 0 THEN tlo := r ELSE PC := W16(r * 256 + tlo + 1); state := sFetch END
    ELSIF o = 6BH THEN
      IF idx = 0 THEN tlo := r
      ELSIF idx = 1 THEN PC := W16(r * 256 + tlo + 1)
      ELSE PBR := r; IF fE # 0 THEN S := 100H + Lo(S) END; state := sFetch
      END
    ELSE (* RTI *)
      IF idx = 0 THEN SetP(r)
      ELSIF idx = 1 THEN tlo := r
      ELSIF idx = 2 THEN PC := r * 256 + tlo; IF fE # 0 THEN state := sFetch END
      ELSE PBR := r; state := sFetch
      END
    END
  END PullState;

  PROCEDURE MvW;
  BEGIN write(DBR * 10000H + Y, Lo(tdata));
    IF X16() THEN
      IF IR = 54H THEN X := W16(X + 1); Y := W16(Y + 1) ELSE X := W16(X - 1); Y := W16(Y - 1) END
    ELSE
      IF IR = 54H THEN X := Lo(X + 1); Y := Lo(Y + 1) ELSE X := Lo(X - 1); Y := Lo(Y - 1) END
    END;
    IF A = 0 THEN A := 0FFFFH; state := sFetch
    ELSE A := A - 1;
      IF Intr() THEN PC := W16(PC - 3); state := sFetch ELSE state := sMvR END
    END
  END MvW;

  (* One state: its bus cycle, then the transition. The IRQ input reaches
     the core through two flip-flops. *)
  PROCEDURE Step*(cycles: LONGINT);
    VAR s: INTEGER;
  BEGIN s := state;
    CASE s OF
      sFetch: Fetch(cycles)
    | sOp1: Op1
    | sOp2: Op2
    | sOp3: Op3
    | sPtrL: tlo := read(ptrBank * 10000H + tptr); state := sPtrH
    | sPtrH: PtrH
    | sPtrB: PtrB
    | sRdL: RdL
    | sRdH: RdH
    | sWrL: write(taddr, Lo(StVal())); IF St16() THEN state := sWrH ELSE state := sFetch END
    | sWrH: write(Taddr1(), Hi(StVal())); state := sFetch
    | sWbL: write(taddr, Lo(tdata)); IF Rd16() THEN state := sWbH ELSE state := sFetch END
    | sWbH: write(Taddr1(), Hi(tdata)); state := sFetch
    | sPush: PushState
    | sPull: PullState
    | sVecL: PC := ORA(AND(PC, 0FF00H), read(vec)); state := sVecH
    | sVecH: PC := ORA(Lo(PC), read(W16(vec + 1)) * 256); state := sFetch
    | sMvR: tdata := read(tmid * 10000H + X); state := sMvW
    | sMvW: MvW
    | sWai: idle;
        IF irq2 THEN
          IF fI = 0 THEN IntEntry(PC, 0, 0FFEEH + 10H * fE) ELSE state := sFetch END
        END
    | sStp: idle
    END;
    irq2 := irq1; irq1 := irqLine()
  END Step;

  (* As the core comes out of reset: emulation mode, the reset vector. *)
  PROCEDURE Reset*;
  BEGIN
    state := sVecL; vec := 0FFFCH;
    fE := 1; fM := 1; fX := 1; fI := 1; fD := 0; fC := 0; fZ := 0; fV := 0; fN := 0;
    A := 0; X := 0; Y := 0; S := 1FFH; D := 0; DBR := 0; PBR := 0; PC := 0;
    Decode(0); tlo := 0; tmid := 0; tptr := 0; ptrBank := 0; taddr := 0; wrap16 := FALSE;
    tdata := 0; pushN := 0; stk16 := FALSE; postPush := ppFetch; pullIdx := 0;
    irq1 := FALSE; irq2 := FALSE; stopped := FALSE
  END Reset;

  (* At an instruction boundary? For the test against the vectors. *)
  PROCEDURE AtFetch*(): BOOLEAN;
  BEGIN RETURN state = sFetch
  END AtFetch;

  (* Set the registers, at the start of an instruction. *)
  PROCEDURE SetState*(pc, s, p, a, x, y, dbr, d, pbr, e: INTEGER);
  BEGIN
    PC := pc; S := s; A := a; X := x; Y := y; DBR := dbr; D := d; PBR := pbr; fE := e;
    fN := Bit(p, 7); fV := Bit(p, 6); fM := Bit(p, 5); fX := Bit(p, 4);
    fD := Bit(p, 3); fI := Bit(p, 2); fZ := Bit(p, 1); fC := Bit(p, 0);
    state := sFetch; stopped := FALSE; irq1 := FALSE; irq2 := FALSE
  END SetState;

  PROCEDURE GetP*(): INTEGER;
  BEGIN RETURN fN * 128 + fV * 64 + fM * 32 + fX * 16 + fD * 8 + fI * 4 + fZ * 2 + fC
  END GetP;

  PROCEDURE Init;
    VAR i: INTEGER;
  BEGIN
    FOR i := 0 TO 255 DO mode[i] := mdnon; cls[i] := clspc; op[i] := opnop END;
    (* the decode of cpu_65c816.v, by tools/gencore.py *)
    mode[001H] := mdidx; cls[001H] := clrd; op[001H] := opora;
    mode[003H] := mdsr; cls[003H] := clrd; op[003H] := opora;
    mode[004H] := mddp; cls[004H] := clmw; op[004H] := optsb;
    mode[005H] := mddp; cls[005H] := clrd; op[005H] := opora;
    mode[006H] := mddp; cls[006H] := clmw; op[006H] := opasl;
    mode[007H] := mdidl; cls[007H] := clrd; op[007H] := opora;
    mode[009H] := mdimm; cls[009H] := clrd; op[009H] := opora;
    mode[00CH] := mdabs; cls[00CH] := clmw; op[00CH] := optsb;
    mode[00DH] := mdabs; cls[00DH] := clrd; op[00DH] := opora;
    mode[00EH] := mdabs; cls[00EH] := clmw; op[00EH] := opasl;
    mode[00FH] := mdabl; cls[00FH] := clrd; op[00FH] := opora;
    mode[010H] := mdrel;
    mode[011H] := mdidy; cls[011H] := clrd; op[011H] := opora;
    mode[012H] := mdidp; cls[012H] := clrd; op[012H] := opora;
    mode[013H] := mdsry; cls[013H] := clrd; op[013H] := opora;
    mode[014H] := mddp; cls[014H] := clmw; op[014H] := optrb;
    mode[015H] := mddpx; cls[015H] := clrd; op[015H] := opora;
    mode[016H] := mddpx; cls[016H] := clmw; op[016H] := opasl;
    mode[017H] := mdily; cls[017H] := clrd; op[017H] := opora;
    mode[019H] := mdaby; cls[019H] := clrd; op[019H] := opora;
    mode[01CH] := mdabs; cls[01CH] := clmw; op[01CH] := optrb;
    mode[01DH] := mdabx; cls[01DH] := clrd; op[01DH] := opora;
    mode[01EH] := mdabx; cls[01EH] := clmw; op[01EH] := opasl;
    mode[01FH] := mdalx; cls[01FH] := clrd; op[01FH] := opora;
    mode[020H] := mdabs; cls[020H] := cljsr;
    mode[021H] := mdidx; cls[021H] := clrd; op[021H] := opand;
    mode[022H] := mdabl; cls[022H] := cljsr;
    mode[023H] := mdsr; cls[023H] := clrd; op[023H] := opand;
    mode[024H] := mddp; cls[024H] := clrd; op[024H] := opbit;
    mode[025H] := mddp; cls[025H] := clrd; op[025H] := opand;
    mode[026H] := mddp; cls[026H] := clmw; op[026H] := oprol;
    mode[027H] := mdidl; cls[027H] := clrd; op[027H] := opand;
    mode[029H] := mdimm; cls[029H] := clrd; op[029H] := opand;
    mode[02CH] := mdabs; cls[02CH] := clrd; op[02CH] := opbit;
    mode[02DH] := mdabs; cls[02DH] := clrd; op[02DH] := opand;
    mode[02EH] := mdabs; cls[02EH] := clmw; op[02EH] := oprol;
    mode[02FH] := mdabl; cls[02FH] := clrd; op[02FH] := opand;
    mode[030H] := mdrel;
    mode[031H] := mdidy; cls[031H] := clrd; op[031H] := opand;
    mode[032H] := mdidp; cls[032H] := clrd; op[032H] := opand;
    mode[033H] := mdsry; cls[033H] := clrd; op[033H] := opand;
    mode[034H] := mddpx; cls[034H] := clrd; op[034H] := opbit;
    mode[035H] := mddpx; cls[035H] := clrd; op[035H] := opand;
    mode[036H] := mddpx; cls[036H] := clmw; op[036H] := oprol;
    mode[037H] := mdily; cls[037H] := clrd; op[037H] := opand;
    mode[039H] := mdaby; cls[039H] := clrd; op[039H] := opand;
    mode[03CH] := mdabx; cls[03CH] := clrd; op[03CH] := opbit;
    mode[03DH] := mdabx; cls[03DH] := clrd; op[03DH] := opand;
    mode[03EH] := mdabx; cls[03EH] := clmw; op[03EH] := oprol;
    mode[03FH] := mdalx; cls[03FH] := clrd; op[03FH] := opand;
    mode[041H] := mdidx; cls[041H] := clrd; op[041H] := opeor;
    mode[042H] := mdimm; cls[042H] := clrd; op[042H] := opnop;
    mode[043H] := mdsr; cls[043H] := clrd; op[043H] := opeor;
    mode[045H] := mddp; cls[045H] := clrd; op[045H] := opeor;
    mode[046H] := mddp; cls[046H] := clmw; op[046H] := oplsr;
    mode[047H] := mdidl; cls[047H] := clrd; op[047H] := opeor;
    mode[049H] := mdimm; cls[049H] := clrd; op[049H] := opeor;
    mode[04CH] := mdabs; cls[04CH] := cljmp;
    mode[04DH] := mdabs; cls[04DH] := clrd; op[04DH] := opeor;
    mode[04EH] := mdabs; cls[04EH] := clmw; op[04EH] := oplsr;
    mode[04FH] := mdabl; cls[04FH] := clrd; op[04FH] := opeor;
    mode[050H] := mdrel;
    mode[051H] := mdidy; cls[051H] := clrd; op[051H] := opeor;
    mode[052H] := mdidp; cls[052H] := clrd; op[052H] := opeor;
    mode[053H] := mdsry; cls[053H] := clrd; op[053H] := opeor;
    mode[055H] := mddpx; cls[055H] := clrd; op[055H] := opeor;
    mode[056H] := mddpx; cls[056H] := clmw; op[056H] := oplsr;
    mode[057H] := mdily; cls[057H] := clrd; op[057H] := opeor;
    mode[059H] := mdaby; cls[059H] := clrd; op[059H] := opeor;
    mode[05CH] := mdabl; cls[05CH] := cljmp;
    mode[05DH] := mdabx; cls[05DH] := clrd; op[05DH] := opeor;
    mode[05EH] := mdabx; cls[05EH] := clmw; op[05EH] := oplsr;
    mode[05FH] := mdalx; cls[05FH] := clrd; op[05FH] := opeor;
    mode[061H] := mdidx; cls[061H] := clrd; op[061H] := opadc;
    mode[062H] := mdrll;
    mode[063H] := mdsr; cls[063H] := clrd; op[063H] := opadc;
    mode[064H] := mddp; cls[064H] := clwr; op[064H] := opstz;
    mode[065H] := mddp; cls[065H] := clrd; op[065H] := opadc;
    mode[066H] := mddp; cls[066H] := clmw; op[066H] := opror;
    mode[067H] := mdidl; cls[067H] := clrd; op[067H] := opadc;
    mode[069H] := mdimm; cls[069H] := clrd; op[069H] := opadc;
    mode[06CH] := mdiab; cls[06CH] := cljmp;
    mode[06DH] := mdabs; cls[06DH] := clrd; op[06DH] := opadc;
    mode[06EH] := mdabs; cls[06EH] := clmw; op[06EH] := opror;
    mode[06FH] := mdabl; cls[06FH] := clrd; op[06FH] := opadc;
    mode[070H] := mdrel;
    mode[071H] := mdidy; cls[071H] := clrd; op[071H] := opadc;
    mode[072H] := mdidp; cls[072H] := clrd; op[072H] := opadc;
    mode[073H] := mdsry; cls[073H] := clrd; op[073H] := opadc;
    mode[074H] := mddpx; cls[074H] := clwr; op[074H] := opstz;
    mode[075H] := mddpx; cls[075H] := clrd; op[075H] := opadc;
    mode[076H] := mddpx; cls[076H] := clmw; op[076H] := opror;
    mode[077H] := mdily; cls[077H] := clrd; op[077H] := opadc;
    mode[079H] := mdaby; cls[079H] := clrd; op[079H] := opadc;
    mode[07CH] := mdiax; cls[07CH] := cljmp;
    mode[07DH] := mdabx; cls[07DH] := clrd; op[07DH] := opadc;
    mode[07EH] := mdabx; cls[07EH] := clmw; op[07EH] := opror;
    mode[07FH] := mdalx; cls[07FH] := clrd; op[07FH] := opadc;
    mode[080H] := mdrel;
    mode[081H] := mdidx; cls[081H] := clwr; op[081H] := opsta;
    mode[082H] := mdrll;
    mode[083H] := mdsr; cls[083H] := clwr; op[083H] := opsta;
    mode[084H] := mddp; cls[084H] := clwr; op[084H] := opsty;
    mode[085H] := mddp; cls[085H] := clwr; op[085H] := opsta;
    mode[086H] := mddp; cls[086H] := clwr; op[086H] := opstx;
    mode[087H] := mdidl; cls[087H] := clwr; op[087H] := opsta;
    mode[089H] := mdimm; cls[089H] := clrd; op[089H] := opbit;
    mode[08CH] := mdabs; cls[08CH] := clwr; op[08CH] := opsty;
    mode[08DH] := mdabs; cls[08DH] := clwr; op[08DH] := opsta;
    mode[08EH] := mdabs; cls[08EH] := clwr; op[08EH] := opstx;
    mode[08FH] := mdabl; cls[08FH] := clwr; op[08FH] := opsta;
    mode[090H] := mdrel;
    mode[091H] := mdidy; cls[091H] := clwr; op[091H] := opsta;
    mode[092H] := mdidp; cls[092H] := clwr; op[092H] := opsta;
    mode[093H] := mdsry; cls[093H] := clwr; op[093H] := opsta;
    mode[094H] := mddpx; cls[094H] := clwr; op[094H] := opsty;
    mode[095H] := mddpx; cls[095H] := clwr; op[095H] := opsta;
    mode[096H] := mddpy; cls[096H] := clwr; op[096H] := opstx;
    mode[097H] := mdily; cls[097H] := clwr; op[097H] := opsta;
    mode[099H] := mdaby; cls[099H] := clwr; op[099H] := opsta;
    mode[09CH] := mdabs; cls[09CH] := clwr; op[09CH] := opstz;
    mode[09DH] := mdabx; cls[09DH] := clwr; op[09DH] := opsta;
    mode[09EH] := mdabx; cls[09EH] := clwr; op[09EH] := opstz;
    mode[09FH] := mdalx; cls[09FH] := clwr; op[09FH] := opsta;
    mode[0A0H] := mdimm; cls[0A0H] := clrd; op[0A0H] := opldy;
    mode[0A1H] := mdidx; cls[0A1H] := clrd; op[0A1H] := oplda;
    mode[0A2H] := mdimm; cls[0A2H] := clrd; op[0A2H] := opldx;
    mode[0A3H] := mdsr; cls[0A3H] := clrd; op[0A3H] := oplda;
    mode[0A4H] := mddp; cls[0A4H] := clrd; op[0A4H] := opldy;
    mode[0A5H] := mddp; cls[0A5H] := clrd; op[0A5H] := oplda;
    mode[0A6H] := mddp; cls[0A6H] := clrd; op[0A6H] := opldx;
    mode[0A7H] := mdidl; cls[0A7H] := clrd; op[0A7H] := oplda;
    mode[0A9H] := mdimm; cls[0A9H] := clrd; op[0A9H] := oplda;
    mode[0ACH] := mdabs; cls[0ACH] := clrd; op[0ACH] := opldy;
    mode[0ADH] := mdabs; cls[0ADH] := clrd; op[0ADH] := oplda;
    mode[0AEH] := mdabs; cls[0AEH] := clrd; op[0AEH] := opldx;
    mode[0AFH] := mdabl; cls[0AFH] := clrd; op[0AFH] := oplda;
    mode[0B0H] := mdrel;
    mode[0B1H] := mdidy; cls[0B1H] := clrd; op[0B1H] := oplda;
    mode[0B2H] := mdidp; cls[0B2H] := clrd; op[0B2H] := oplda;
    mode[0B3H] := mdsry; cls[0B3H] := clrd; op[0B3H] := oplda;
    mode[0B4H] := mddpx; cls[0B4H] := clrd; op[0B4H] := opldy;
    mode[0B5H] := mddpx; cls[0B5H] := clrd; op[0B5H] := oplda;
    mode[0B6H] := mddpy; cls[0B6H] := clrd; op[0B6H] := opldx;
    mode[0B7H] := mdily; cls[0B7H] := clrd; op[0B7H] := oplda;
    mode[0B9H] := mdaby; cls[0B9H] := clrd; op[0B9H] := oplda;
    mode[0BCH] := mdabx; cls[0BCH] := clrd; op[0BCH] := opldy;
    mode[0BDH] := mdabx; cls[0BDH] := clrd; op[0BDH] := oplda;
    mode[0BEH] := mdaby; cls[0BEH] := clrd; op[0BEH] := opldx;
    mode[0BFH] := mdalx; cls[0BFH] := clrd; op[0BFH] := oplda;
    mode[0C0H] := mdimm; cls[0C0H] := clrd; op[0C0H] := opcpy;
    mode[0C1H] := mdidx; cls[0C1H] := clrd; op[0C1H] := opcmp;
    mode[0C2H] := mdimm; cls[0C2H] := clrd; op[0C2H] := oprep;
    mode[0C3H] := mdsr; cls[0C3H] := clrd; op[0C3H] := opcmp;
    mode[0C4H] := mddp; cls[0C4H] := clrd; op[0C4H] := opcpy;
    mode[0C5H] := mddp; cls[0C5H] := clrd; op[0C5H] := opcmp;
    mode[0C6H] := mddp; cls[0C6H] := clmw; op[0C6H] := opdec;
    mode[0C7H] := mdidl; cls[0C7H] := clrd; op[0C7H] := opcmp;
    mode[0C9H] := mdimm; cls[0C9H] := clrd; op[0C9H] := opcmp;
    mode[0CCH] := mdabs; cls[0CCH] := clrd; op[0CCH] := opcpy;
    mode[0CDH] := mdabs; cls[0CDH] := clrd; op[0CDH] := opcmp;
    mode[0CEH] := mdabs; cls[0CEH] := clmw; op[0CEH] := opdec;
    mode[0CFH] := mdabl; cls[0CFH] := clrd; op[0CFH] := opcmp;
    mode[0D0H] := mdrel;
    mode[0D1H] := mdidy; cls[0D1H] := clrd; op[0D1H] := opcmp;
    mode[0D2H] := mdidp; cls[0D2H] := clrd; op[0D2H] := opcmp;
    mode[0D3H] := mdsry; cls[0D3H] := clrd; op[0D3H] := opcmp;
    mode[0D5H] := mddpx; cls[0D5H] := clrd; op[0D5H] := opcmp;
    mode[0D6H] := mddpx; cls[0D6H] := clmw; op[0D6H] := opdec;
    mode[0D7H] := mdily; cls[0D7H] := clrd; op[0D7H] := opcmp;
    mode[0D9H] := mdaby; cls[0D9H] := clrd; op[0D9H] := opcmp;
    mode[0DCH] := mdial; cls[0DCH] := cljmp;
    mode[0DDH] := mdabx; cls[0DDH] := clrd; op[0DDH] := opcmp;
    mode[0DEH] := mdabx; cls[0DEH] := clmw; op[0DEH] := opdec;
    mode[0DFH] := mdalx; cls[0DFH] := clrd; op[0DFH] := opcmp;
    mode[0E0H] := mdimm; cls[0E0H] := clrd; op[0E0H] := opcpx;
    mode[0E1H] := mdidx; cls[0E1H] := clrd; op[0E1H] := opsbc;
    mode[0E2H] := mdimm; cls[0E2H] := clrd; op[0E2H] := opsep;
    mode[0E3H] := mdsr; cls[0E3H] := clrd; op[0E3H] := opsbc;
    mode[0E4H] := mddp; cls[0E4H] := clrd; op[0E4H] := opcpx;
    mode[0E5H] := mddp; cls[0E5H] := clrd; op[0E5H] := opsbc;
    mode[0E6H] := mddp; cls[0E6H] := clmw; op[0E6H] := opinc;
    mode[0E7H] := mdidl; cls[0E7H] := clrd; op[0E7H] := opsbc;
    mode[0E9H] := mdimm; cls[0E9H] := clrd; op[0E9H] := opsbc;
    mode[0ECH] := mdabs; cls[0ECH] := clrd; op[0ECH] := opcpx;
    mode[0EDH] := mdabs; cls[0EDH] := clrd; op[0EDH] := opsbc;
    mode[0EEH] := mdabs; cls[0EEH] := clmw; op[0EEH] := opinc;
    mode[0EFH] := mdabl; cls[0EFH] := clrd; op[0EFH] := opsbc;
    mode[0F0H] := mdrel;
    mode[0F1H] := mdidy; cls[0F1H] := clrd; op[0F1H] := opsbc;
    mode[0F2H] := mdidp; cls[0F2H] := clrd; op[0F2H] := opsbc;
    mode[0F3H] := mdsry; cls[0F3H] := clrd; op[0F3H] := opsbc;
    mode[0F5H] := mddpx; cls[0F5H] := clrd; op[0F5H] := opsbc;
    mode[0F6H] := mddpx; cls[0F6H] := clmw; op[0F6H] := opinc;
    mode[0F7H] := mdily; cls[0F7H] := clrd; op[0F7H] := opsbc;
    mode[0F9H] := mdaby; cls[0F9H] := clrd; op[0F9H] := opsbc;
    mode[0FCH] := mdiax; cls[0FCH] := cljsr;
    mode[0FDH] := mdabx; cls[0FDH] := clrd; op[0FDH] := opsbc;
    mode[0FEH] := mdabx; cls[0FEH] := clmw; op[0FEH] := opinc;
    mode[0FFH] := mdalx; cls[0FFH] := clrd; op[0FFH] := opsbc;
    mnem := "BRKORACOPORATSBORAASLORAPHPORAASLPHDTSBORAASLORABPLORAORAORATRBORAASLORACLCORAINCTCSTRBORAASLORAJSRANDJSLANDBITANDROLANDPLPANDROLPLDBITANDROLANDBMIANDANDANDBITANDROLANDSECANDDECTSCBITANDROLANDRTIEORWDMEORMVPEORLSREORPHAEORLSRPHKJMPEORLSREORBVCEOREOREORMVNEORLSREORCLIEORPHYTCDJMLEORLSREORRTSADCPERADCSTZADCRORADCPLAADCRORRTLJMPADCRORADCBVSADCADCADCSTZADCRORADCSEIADCPLYTDCJMPADCRORADCBRASTABRLSTASTYSTASTXSTADEYBITTXAPHBSTYSTASTXSTABCCSTASTASTASTYSTASTXSTATYASTATXSTXYSTZSTASTZSTALDYLDALDXLDALDYLDALDXLDATAYLDATAXPLBLDYLDALDXLDABCSLDALDALDALDYLDALDXLDACLVLDATSXTYXLDYLDALDXLDACPYCMPREPCMPCPYCMPDECCMPINYCMPDEXWAICPYCMPDECCMPBNECMPCMPCMPPEICMPDECCMPCLDCMPPHXSTPJMLCMPDECCMPCPXSBCSEPSBCCPXSBCINCSBCINXSBCNOPXBACPXSBCINCSBCBEQSBCSBCSBCPEASBCINCSBCSEDSBCPLXXCEJSRSBCINCSBC";
  END Init;

BEGIN Init; read := NIL; write := NIL; idle := NIL; irqLine := NIL; trace := FALSE; Reset
END EmCore.
