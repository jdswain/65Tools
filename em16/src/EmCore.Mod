MODULE EmCore; (* The 65C816 of the Tang Nano 20K SoC: cpu_65c816.v of
   ../../Verilog65C816, translated state for state and cycle for cycle.

   The core is a state machine with no dummy cycles; so is this. Its
   states that use the bus (the pointer, data, stack, vector and block
   move states) make one bus cycle each, through the procedures the
   system has set with SetBus, which add the wait states. The others
   (the opcode, the operands, the setup of a push, WAI, STP, the opcode
   after a WDM prefix, a multiply or divide) take no bus cycle: they run
   a clock at a time, and take their bytes from the instruction queue.

   The queue holds the 8 bytes from PC on, as the core read them: a fill
   reads the aligned word holding the next byte to fetch and keeps the
   bytes from it to the word's end (4 - addr MOD 4; one byte from
   memory that has no 32-bit read, the I/O block and the external bus),
   in the cycles the core is off the bus, when the bytes will fit (at
   most 4 queued once this cycle's bytes are taken) or after a jump. A
   fill holds the bus until its memory is ready, so a state that uses
   the bus first waits for one in flight; the states that do not keep
   running. The opcode is taken from the queue in one cycle and all the
   operand bytes in the next, once they are there. A jump (a taken
   branch, a jump, call or return, an interrupt) empties the queue and
   starts a fill at its target in the next cycle off the bus; a fill
   then in flight still holds the bus, and its bytes are dropped. A
   store to bytes already queued does not change them (Store reports
   it, with SetSMC).

   A read's operand and an implied opcode are executed in the next
   cycle, as the next opcode is taken (xp, lp), and an interrupt, a pull
   or return taken behind one, or an empty queue wait a cycle for it; a
   push, WAI and STP take a cycle of setup (sImp). So a CLI's effect,
   like a REP or SEP's, comes an instruction late for an IRQ.

   Step runs a clock (a state without a bus cycle) or a state with its
   bus cycle. A Verilog clock edge assigns every register at once from
   the values before it; here the assignments are ordered so that each
   reads the old values, as there.

   Its semantics are those of the WDC chip, which the core was checked
   against with the SingleStepTests vectors (em16 -harte checks this
   module against the same), and so differ from em16's own CPU (EmCPU):
   TCD sets N and Z, JMP keeps the program bank, PEI pushes the pointer,
   TXS with 8 bit index registers clears the high byte of S, the new
   stack instructions cross pages in emulation mode, decimal arithmetic
   takes its flags as the 65C816 does. What is the core's own: its cycle
   counts, a block move takes two cycles a byte and an interrupt between
   bytes. ABORT and NMI are not wired on the SoC and are left out.

   The core's extensions (../../Verilog65C816/docs). The banked direct
   page and stack (BankedDP.md): WDM $B1 sets the mode and WDM $B0 clears
   it; in native mode with it set, D is a page number, the direct page is
   at D * 100H and the stack at Hi(D) * 10000H + S. WDM as a prefix
   (65C832.md), the byte after it the opcode: an ADC, AND, CMP or EOR
   opcode makes MUL, UML, DIV or UDV in its addressing mode, $0A, $4A,
   $8A, $2A and $6A with a count ASL, LSR, ASR, ROL and ROR by it, $EB
   BSW, $FB XFE, and any other a two byte no-operation. A multiply or
   divide is worked out at once and written when sMd has run the core's
   cycles for it, a bit a cycle.

   And the core is a 65C832 (65C832.md) when built with C832 = 1: E16 = 0
   is a native mode with an accumulator of 32 bits (E8 = 1) or 16, and
   index registers of 32 bits; XFE exchanges E16 and V with E8 and C. The
   Tang Nano builds it with C832 = 0, and so does this unless SetC832
   turns it on (em16 -c832): E16 then stays 1 and XFE does nothing.

   For em16, taking an opcode at 00:0000 stops the processor, and so
   does STP. *)

  IMPORT EmHost, EmSym;

  CONST
    (* states *)
    sFetch = 0; sOps = 1; sPtrL = 4; sPtrH = 5; sPtrB = 6;
    sRdL = 7; sRdH = 8; sWrL = 9; sWrH = 10; sWbL = 11; sWbH = 12; sPush = 13; sPull = 14;
    sVecL = 15; sVecH = 16; sMvR = 17; sMvW = 18; sWai = 19; sStp = 20; sImp = 21;
    sXop = 22; sMd = 23;
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
    (* after the WDM prefix *)
    opmul = 27; opuml = 28; opdiv = 29; opudv = 30; opshf = 31;
    (* after the last push *)
    ppFetch = 0; ppVec = 1; ppPtr = 2;
    (* kinds of opcode at the queue's head *)
    kOps = 0; kLocal = 1; kSetup = 2; kPull = 3;

  TYPE
    Reader* = PROCEDURE (addr: INTEGER): INTEGER;
    Writer* = PROCEDURE (addr, data: INTEGER);
    (* A queue fill of the word holding addr, its bus cycle starting at
       cycle at: the bytes from addr to the word's end, or the one byte of
       a memory without a 32-bit read, in word[0..n-1]; the cycles to its
       ready, at least 1. It does not pass the time. *)
    Fetcher* = PROCEDURE (addr: INTEGER; at: LONGINT; VAR word: ARRAY OF INTEGER; VAR n: INTEGER): INTEGER;
    Waiter* = PROCEDURE (cycles: INTEGER);
    Clock* = PROCEDURE (): LONGINT;
    Line* = PROCEDURE (): BOOLEAN;

  VAR
    (* the registers; A, X and Y are 32 bits, X and Y 0 above their width *)
    A*, X*, Y*, S*, D*, PC*, DBR*, PBR*: INTEGER;
    fC*, fZ*, fI*, fD*, fX*, fM*, fV*, fN*, fE*: INTEGER;
    fE16*: INTEGER;          (* 0: 65C832 native mode, fE its E8 *)
    xb*: BOOLEAN;            (* banked direct page and stack *)
    c832: BOOLEAN;           (* the core built with the 65C832 mode *)
    (* the state machine *)
    state*, IR: INTEGER;
    irx: BOOLEAN;            (* IR followed a WDM prefix *)
    dMode, dCls, dOp, dLen: INTEGER;
    tlo, tmid, tptr, ptrBank, taddr, tdata: INTEGER;
    taddrAlt, rb: INTEGER;   (* a wide access: its first address, the byte at taddr *)
    mvS, mvD: INTEGER;       (* a block move's source and destination *)
    wrap16, stk16: BOOLEAN;
    pushQ: ARRAY 4 OF INTEGER;    (* bytes to push, the first at pushQ[0] *)
    pushN, postPush, pullIdx, vec: INTEGER;
    xp, lp: BOOLEAN;              (* an execute pending: of xm (a read), of IR (implied) *)
    xm: INTEGER;
    (* a multiply or divide in sMd: its cycles to go, and what it leaves *)
    mdN, mdA, mdX, mdV: INTEGER; mdZero: BOOLEAN;
    irq1, irq2: BOOLEAN;          (* the IRQ input's synchronizer; TRUE: asserted *)
    (* the instruction queue: qn bytes, the first, at PC, in q[qh]; fa the
       offset in PBR of the next byte to fetch. The fill in flight: of
       faddr, ready in the cycle before fEnd, its bytes fw[0..fn-1];
       fdrop: a jump since, its bytes are dropped. *)
    q: ARRAY 8 OF INTEGER;
    qh, qn, fa, faddr, fn: INTEGER;
    fw: ARRAY 4 OF INTEGER;
    fbusy, fdrop: BOOLEAN;
    fEnd: LONGINT;
    take: INTEGER;                (* this cycle: bytes taken from the queue *)
    jmp: BOOLEAN; jpc, jbank: INTEGER;   (* this cycle: PC out of sequence, to jbank:jpc *)
    opAt: INTEGER;                (* the instruction's opcode's address *)
    stopped*, trace*: BOOLEAN;
    smc: BOOLEAN; smcHits*: INTEGER;      (* stores to queued bytes: SetSMC *)
    traceAt, traceSkip, traceLeft: INTEGER;   (* TraceFrom's *)
    (* the decode table *)
    mode, cls, op, kind, len: ARRAY 256 OF INTEGER;
    mnem: ARRAY 800 OF CHAR;
    (* the bus *)
    read: Reader; write: Writer; fetch: Fetcher; wait: Waiter; clock: Clock; irqLine: Line;

  PROCEDURE SetTrace*(on: BOOLEAN);
  BEGIN trace := on
  END SetTrace;

  (* Report each store to bytes in the queue: code written by stores that
     the board would not run as written. *)
  PROCEDURE SetSMC*(on: BOOLEAN);
  BEGIN smc := on
  END SetSMC;

  (* The core as built with C832 = 1, the 65C832 mode, or (FALSE, as the
     Tang Nano builds it) without. *)
  PROCEDURE SetC832*(on: BOOLEAN);
  BEGIN c832 := on
  END SetC832;

  (* The trace on when the instruction at at is reached for the skip+1th
     time, and off again after count instructions. *)
  PROCEDURE TraceFrom*(at, skip, count: INTEGER);
  BEGIN traceAt := at; traceSkip := skip; traceLeft := count
  END TraceFrom;

  PROCEDURE SetBus*(r: Reader; w: Writer; f: Fetcher; wt: Waiter; c: Clock; irq: Line);
  BEGIN read := r; write := w; fetch := f; wait := wt; clock := c; irqLine := irq
  END SetBus;

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
  BEGIN v := AND(v, 0FFH); IF v >= 80H THEN v := v - 100H END; RETURN v
  END Sext8;

  (* 6502 emulation: E8 and E16 *)
  PROCEDURE Emu(): BOOLEAN;
  BEGIN RETURN (fE # 0) & (fE16 # 0)
  END Emu;

  (* The accumulator's width in bits: 8, 16, or 32 in 65C832 native mode
     with E8 = 1 *)
  PROCEDURE Aw(): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF (fM # 0) OR Emu() THEN r := 8 ELSIF (fE16 = 0) & (fE # 0) THEN r := 32 ELSE r := 16 END;
    RETURN r
  END Aw;

  (* the index registers': 8, 16, or 32 in 65C832 native mode *)
  PROCEDURE Xw(): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF (fX # 0) OR Emu() THEN r := 8 ELSIF fE16 = 0 THEN r := 32 ELSE r := 16 END;
    RETURN r
  END Xw;

  PROCEDURE Wmask(w: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN IF w = 32 THEN r := -1 ELSE r := ASL(1, w) - 1 END; RETURN r
  END Wmask;

  (* the accumulator as wide as it is *)
  PROCEDURE Av(): INTEGER;
  BEGIN RETURN AND(A, Wmask(Aw()))
  END Av;

  (* v into the accumulator's low w bits, the bits above kept *)
  PROCEDURE SetA(v, w: INTEGER);
  BEGIN
    IF w = 32 THEN A := v
    ELSIF w = 16 THEN A := ORA(AND(A, -10000H), W16(v))
    ELSE A := ORA(AND(A, -100H), Lo(v))
    END
  END SetA;

  PROCEDURE Pbyte(brk: INTEGER): INTEGER;
    VAR m, x: INTEGER;
  BEGIN
    IF Emu() THEN m := 1; x := brk ELSE m := fM; x := fX END;
    RETURN fN * 128 + fV * 64 + m * 32 + x * 16 + fD * 8 + fI * 4 + fZ * 2 + fC
  END Pbyte;

  PROCEDURE LdA(v: INTEGER);
    VAR w: INTEGER;
  BEGIN w := Aw(); SetA(v, w); fN := Bit(v, w - 1); fZ := B(AND(v, Wmask(w)) = 0)
  END LdA;

  PROCEDURE LdX(v: INTEGER);
    VAR w: INTEGER;
  BEGIN w := Xw(); X := AND(v, Wmask(w)); fN := Bit(v, w - 1); fZ := B(X = 0)
  END LdX;

  PROCEDURE LdY(v: INTEGER);
    VAR w: INTEGER;
  BEGIN w := Xw(); Y := AND(v, Wmask(w)); fN := Bit(v, w - 1); fZ := B(Y = 0)
  END LdY;

  (* P := v, by PLP, RTI, REP, SEP *)
  PROCEDURE SetP(v: INTEGER);
  BEGIN
    fN := Bit(v, 7); fV := Bit(v, 6); fD := Bit(v, 3); fI := Bit(v, 2); fZ := Bit(v, 1); fC := Bit(v, 0);
    IF ~Emu() THEN
      fM := Bit(v, 5); fX := Bit(v, 4);
      IF fX # 0 THEN X := Lo(X); Y := Lo(Y) END
    END
  END SetP;

  (* The carry out of a w-bit sum r of a, b (both at w bits) and a carry
     in; at 32 bits r is the sum as it wrapped. *)
  PROCEDURE Carry(a, b, r, w: INTEGER): INTEGER;
    VAR c: INTEGER;
  BEGIN
    IF w = 32 THEN c := Bit(ORA(AND(a, b), AND(ORA(a, b), -1 - r)), 31) ELSE c := Bit(r, w) END;
    RETURN c
  END Carry;

  PROCEDURE CmpFlags(r, m, w: INTEGER);
    VAR t, nm: INTEGER;
  BEGIN r := AND(r, Wmask(w)); nm := AND(-1 - m, Wmask(w)); t := r + nm + 1;
    fC := Carry(r, nm, t, w); fN := Bit(t, w - 1); fZ := B(AND(t, Wmask(w)) = 0)
  END CmpFlags;

  (* decimal add of w DIV 4 digits; c the carry in and out, top the
     result's top bit before the last correction *)
  PROCEDURE DAdd(a, b, cin, w: INTEGER; VAR c, top: INTEGER): INTEGER;
    VAR i, n, r: INTEGER;
  BEGIN r := 0; c := cin; top := 0;
    FOR i := 0 TO w DIV 4 - 1 DO
      n := LSR(a, 4 * i) MOD 16 + LSR(b, 4 * i) MOD 16 + c;
      IF i = w DIV 4 - 1 THEN top := Bit(n, 3) END;
      c := B(n > 9); IF c # 0 THEN n := n + 6 END;
      r := ORA(r, ASL(AND(n, 0FH), 4 * i))
    END;
    RETURN r
  END DAdd;

  (* a - b decimal, cin the inverted borrow *)
  PROCEDURE DSub(a, b, cin, w: INTEGER; VAR c: INTEGER): INTEGER;
    VAR i, n, r: INTEGER;
  BEGIN r := 0; c := cin;
    FOR i := 0 TO w DIV 4 - 1 DO
      n := LSR(a, 4 * i) MOD 16 + 0FH - LSR(b, 4 * i) MOD 16 + c;
      c := Bit(n, 4); IF c = 0 THEN n := n - 6 END;
      r := ORA(r, ASL(AND(n, 0FH), 4 * i))
    END;
    RETURN r
  END DSub;

  PROCEDURE Adc(m: INTEGER);
    VAR w, a, t, c, top, r: INTEGER;
  BEGIN w := Aw(); a := Av();
    IF fD # 0 THEN
      r := DAdd(a, m, fC, w, c, top);
      fV := B((Bit(a, w - 1) = Bit(m, w - 1)) & (Bit(a, w - 1) # top));
      fC := c; LdA(r)
    ELSE t := a + m + fC;
      fV := B((Bit(a, w - 1) = Bit(m, w - 1)) & (Bit(a, w - 1) # Bit(t, w - 1)));
      fC := Carry(a, m, t, w); LdA(t)
    END
  END Adc;

  PROCEDURE Sbc(m: INTEGER);
    VAR w, a, nm, t, c, r: INTEGER;
  BEGIN w := Aw(); a := Av(); nm := AND(-1 - m, Wmask(w)); t := a + nm + fC;
    fV := B((Bit(a, w - 1) # Bit(m, w - 1)) & (Bit(a, w - 1) # Bit(t, w - 1)));
    IF fD # 0 THEN r := DSub(a, m, fC, w, c); fC := c; LdA(r)
    ELSE fC := Carry(a, nm, t, w); LdA(t)
    END
  END Sbc;

  (* ASL, LSR, ASR, ROL, ROR #n (IR $0A, $4A, $8A, $2A, $6A) of A, the
     count modulo the width; C the last bit out, or carried round, and
     unchanged by a count of 0 *)
  PROCEDURE Shf(n: INTEGER);
    VAR w, k, a, r, mk: INTEGER;
  BEGIN w := Aw(); mk := Wmask(w); a := Av(); k := n MOD w; r := a;
    IF k # 0 THEN
      IF IR = 0AH THEN r := AND(ASL(a, k), mk); fC := Bit(a, w - k)
      ELSIF IR = 4AH THEN r := LSR(a, k); fC := Bit(a, k - 1)
      ELSIF IR = 8AH THEN r := LSR(a, k); fC := Bit(a, k - 1);
        IF Bit(a, w - 1) # 0 THEN r := ORA(r, mk - LSR(mk, k)) END
      ELSIF IR = 2AH THEN r := AND(ORA(ASL(a, k), LSR(a, w - k)), mk); fC := Bit(r, 0)
      ELSE r := AND(ORA(LSR(a, k), ASL(a, w - k)), mk); fC := Bit(r, w - 1)
      END
    END;
    LdA(r)
  END Shf;

  (* the read class with its whole operand *)
  PROCEDURE ExecRd(m: INTEGER);
    VAR o, w: INTEGER;
  BEGIN o := dOp;
    CASE o OF
      opora: LdA(ORA(Av(), m))
    | opand: LdA(AND(Av(), m))
    | opeor: LdA(EOR(Av(), m))
    | opadc: Adc(m)
    | opsbc: Sbc(m)
    | opcmp: CmpFlags(Av(), m, Aw())
    | oplda: LdA(m)
    | opldx: LdX(m)
    | opldy: LdY(m)
    | opcpx: CmpFlags(X, m, Xw())
    | opcpy: CmpFlags(Y, m, Xw())
    | opbit: w := Aw();
        fZ := B(AND(Av(), m) = 0);
        IF IR # 89H THEN fN := Bit(m, w - 1); fV := Bit(m, w - 2) END
    | oprep: SetP(AND(Pbyte(fX), 0FFH - Lo(m)))
    | opsep: SetP(ORA(Pbyte(fX), Lo(m)))
    | opshf: Shf(Lo(m))
    ELSE (* NOP *)
    END
  END ExecRd;

  (* shift, step, test-and-set at A's width: result to A or to tdata *)
  PROCEDURE RmwCore(o, m: INTEGER; toA: BOOLEAN);
    VAR w, r, c: INTEGER; setc: BOOLEAN;
  BEGIN w := Aw(); c := fC; setc := TRUE;
    IF o = opasl THEN r := ASL(m, 1); c := Bit(m, w - 1)
    ELSIF o = oprol THEN r := ASL(m, 1) + fC; c := Bit(m, w - 1)
    ELSIF o = oplsr THEN r := LSR(m, 1); c := Bit(m, 0)
    ELSIF o = opror THEN r := ORA(LSR(m, 1), ASL(fC, w - 1)); c := Bit(m, 0)
    ELSIF o = opinc THEN r := m + 1; setc := FALSE
    ELSIF o = opdec THEN r := m - 1; setc := FALSE
    ELSIF o = optsb THEN r := ORA(m, Av()); setc := FALSE
    ELSIF o = optrb THEN r := AND(m, -1 - Av()); setc := FALSE
    ELSE r := m; setc := FALSE
    END;
    r := AND(r, Wmask(w));
    IF setc THEN fC := c END;
    IF (o = optsb) OR (o = optrb) THEN fZ := B(AND(Av(), m) = 0)
    ELSE fN := Bit(r, w - 1); fZ := B(r = 0)
    END;
    IF toA THEN SetA(r, w) ELSE tdata := r END
  END RmwCore;

  (* An implied opcode (IR), the cycle after its fetch. Transfers take the
     whole source and keep as much as the destination holds; TCS, TCD,
     TSC and TDC are 16 bits. *)
  PROCEDURE ExecImp;
    VAR o, t, w: INTEGER;
  BEGIN o := IR;
    IF irx THEN                                          (* after the WDM prefix *)
      IF o = 0FBH THEN                                   (* XFE: C and E8, V and E16 *)
        IF c832 THEN
          t := fE; fE := fC; fC := t; t := fE16; fE16 := fV; fV := t;
          IF (fE # 0) & (fE16 # 0) THEN fM := 1; fX := 1; X := Lo(X); Y := Lo(Y); S := 100H + Lo(S)
          ELSIF fE16 # 0 THEN X := W16(X); Y := W16(Y)   (* 65C816 native *)
          END
        END
      ELSIF o = 0EBH THEN w := Aw();                     (* BSW: A's bytes reversed *)
        IF w = 32 THEN
          LdA(ORA(ORA(ASL(Lo(A), 24), ASL(Hi(A), 16)), ORA(ASL(Lo(LSR(A, 16)), 8), LSR(A, 24))))
        ELSIF w = 16 THEN LdA(Lo(A) * 256 + Hi(A))
        ELSE LdA(A)
        END
      ELSIF o = 0B0H THEN xb := FALSE                    (* the banked mode off *)
      ELSIF o = 0B1H THEN xb := TRUE                     (* on *)
      END
    ELSE
      CASE o OF
        18H: fC := 0
      | 38H: fC := 1
      | 58H: fI := 0
      | 78H: fI := 1
      | 0B8H: fV := 0
      | 0D8H: fD := 0
      | 0F8H: fD := 1
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
      | 9AH: IF Emu() THEN S := 100H + Lo(X) ELSE S := W16(X) END
      | 9BH: LdY(X)
      | 0BBH: LdX(Y)
      | 1BH: IF Emu() THEN S := 100H + Lo(A) ELSE S := W16(A) END
      | 3BH: A := ORA(AND(A, -10000H), S); fN := Bit(S, 15); fZ := B(S = 0)
      | 5BH: D := W16(A); fN := Bit(D, 15); fZ := B(D = 0)
      | 7BH: A := ORA(AND(A, -10000H), D); fN := Bit(D, 15); fZ := B(D = 0)
      | 0E8H: LdX(X + 1)
      | 0CAH: LdX(X - 1)
      | 0C8H: LdY(Y + 1)
      | 88H: LdY(Y - 1)
      | 0EBH: fN := Bit(A, 15); fZ := B(Hi(A) = 0); A := ORA(AND(A, -10000H), Lo(A) * 256 + Hi(A))
      | 0FBH: t := fE; fE := fC; fC := t;                (* XCE: C and E8 *)
          IF (fE # 0) & (fE16 # 0) THEN fM := 1; fX := 1; X := Lo(X); Y := Lo(Y); S := 100H + Lo(S) END
      ELSE (* NOP *)
      END
    END
  END ExecImp;

  (* The pending execute, if any *)
  PROCEDURE Pending;
  BEGIN
    IF xp THEN ExecRd(xm) END;
    IF lp THEN ExecImp END;
    xp := FALSE; lp := FALSE
  END Pending;

  (* PC out of sequence: the queue empties, a fill in flight is dropped *)
  PROCEDURE Jump(v: INTEGER);
  BEGIN PC := W16(v); jmp := TRUE; jpc := PC; jbank := PBR
  END Jump;

  (* ... and PBR with it *)
  PROCEDURE JumpL(b, v: INTEGER);
  BEGIN PBR := b; Jump(v); jbank := b
  END JumpL;

  PROCEDURE Push8(v: INTEGER);
  BEGIN pushQ[0] := Lo(v); pushN := 1; stk16 := FALSE; postPush := ppFetch; state := sPush
  END Push8;

  PROCEDURE Push16(v: INTEGER);
  BEGIN pushQ[0] := Hi(v); pushQ[1] := Lo(v); pushN := 2; stk16 := TRUE; postPush := ppFetch; state := sPush
  END Push16;

  (* PHA, PHX, PHY in 65C832 native mode *)
  PROCEDURE Push32(v: INTEGER);
  BEGIN pushQ[0] := Lo(LSR(v, 24)); pushQ[1] := Lo(LSR(v, 16)); pushQ[2] := Hi(v); pushQ[3] := Lo(v);
    pushN := 4; stk16 := FALSE; postPush := ppFetch; state := sPush
  END Push32;

  (* a push of A, X or Y at width w *)
  PROCEDURE PushW(v, w: INTEGER);
  BEGIN IF w = 32 THEN Push32(v) ELSIF w = 16 THEN Push16(v) ELSE Push8(v) END
  END PushW;

  PROCEDURE SDec;
  BEGIN
    IF Emu() & ~stk16 THEN S := 100H + Lo(S - 1) ELSE S := W16(S - 1) END
  END SDec;

  PROCEDURE SInc;
  BEGIN
    IF Emu() & ~stk16 THEN S := 100H + Lo(S + 1) ELSE S := W16(S + 1) END
  END SInc;

  (* an interrupt's vector: in emulation, 65C816 native or 65C832 native mode *)
  PROCEDURE Vec(e, n16, n32: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN IF Emu() THEN r := e ELSIF fE16 = 0 THEN r := n32 ELSE r := n16 END; RETURN r
  END Vec;

  (* interrupt entry: IRQ, BRK, COP *)
  PROCEDURE IntEntry(pushedPC, brk, v: INTEGER);
  BEGIN
    IF Emu() THEN
      pushQ[0] := Hi(pushedPC); pushQ[1] := Lo(pushedPC); pushQ[2] := Pbyte(brk); pushN := 3
    ELSE
      pushQ[0] := PBR; pushQ[1] := Hi(pushedPC); pushQ[2] := Lo(pushedPC); pushQ[3] := Pbyte(brk); pushN := 4
    END;
    fI := 1; fD := 0; PBR := 0; vec := v;
    postPush := ppVec; stk16 := FALSE; state := sPush
  END IntEntry;

  (* the operation works on X or Y *)
  PROCEDURE Xwide(): BOOLEAN;
  BEGIN RETURN (dOp = opldx) OR (dOp = opldy) OR (dOp = opcpx) OR (dOp = opcpy) OR (dOp = opstx) OR (dOp = opsty)
  END Xwide;

  (* the width of a read's or read-modify-write's operand *)
  PROCEDURE Rw(): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF (dOp = oprep) OR (dOp = opsep) OR (dOp = opnop) OR (dOp = opshf) THEN r := 8
    ELSIF Xwide() THEN r := Xw()
    ELSE r := Aw()
    END;
    RETURN r
  END Rw;

  (* ... and of a store's *)
  PROCEDURE Sw(): INTEGER;
    VAR r: INTEGER;
  BEGIN IF Xwide() THEN r := Xw() ELSE r := Aw() END; RETURN r
  END Sw;

  (* a multiply or divide *)
  PROCEDURE Dmd(): BOOLEAN;
  BEGIN RETURN (dOp >= opmul) & (dOp <= opudv)
  END Dmd;

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

  (* In the banked mode, the direct page's offset in its bank, and the bank
     of the direct page, the stack and their pointers. *)
  PROCEDURE Dbase(): INTEGER;
    VAR r: INTEGER;
  BEGIN IF xb & ~Emu() THEN r := Lo(D) * 256 ELSE r := D END; RETURN r
  END Dbase;

  PROCEDURE Dbank(): INTEGER;
    VAR r: INTEGER;
  BEGIN IF xb & ~Emu() THEN r := Hi(D) ELSE r := 0 END; RETURN r
  END Dbank;

  PROCEDURE SpPush(): INTEGER;
    VAR r: INTEGER;
  BEGIN IF Emu() & ~stk16 THEN r := 100H + Lo(S) ELSE r := Dbank() * 10000H + S END; RETURN r
  END SpPush;

  PROCEDURE SpPull(): INTEGER;
    VAR r: INTEGER;
  BEGIN IF Emu() & ~stk16 THEN r := 100H + Lo(S + 1) ELSE r := Dbank() * 10000H + W16(S + 1) END; RETURN r
  END SpPull;

  PROCEDURE Dpw(): BOOLEAN;      (* direct page wrap: emulation and DL = 0 *)
  BEGIN RETURN Emu() & (Lo(D) = 0)
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
  BEGIN IR := o; irx := FALSE; dMode := mode[o]; dCls := cls[o]; dOp := op[o]
  END Decode;

  (* The opcode after a WDM prefix: MUL, UML, DIV or UDV in the addressing
     mode of an ADC, AND, CMP or EOR opcode, or a shift by a count (TRUE),
     or else implied (XFE, BSW, the banked mode's $B0 and $B1, or a
     no-operation). *)
  PROCEDURE XDecode(o: INTEGER): BOOLEAN;
    VAR p: INTEGER; x: BOOLEAN;
  BEGIN IR := o; irx := TRUE; dMode := mdnon; dCls := clspc; dOp := opnop; dLen := len[o]; x := FALSE;
    p := op[o];
    IF (cls[o] = clrd) & ((p = opadc) OR (p = opand) OR (p = opcmp) OR (p = opeor)) THEN
      dMode := mode[o]; dCls := clrd; x := TRUE;
      IF p = opadc THEN dOp := opmul ELSIF p = opand THEN dOp := opuml
      ELSIF p = opcmp THEN dOp := opdiv ELSE dOp := opudv
      END
    END;
    IF (o = 0AH) OR (o = 2AH) OR (o = 4AH) OR (o = 6AH) OR (o = 8AH) THEN
      dMode := mdimm; dCls := clrd; dOp := opshf; dLen := 1; x := TRUE
    END;
    RETURN x
  END XDecode;

  (* the next state of a read, write or read-modify-write *)
  PROCEDURE DataState(): INTEGER;
    VAR r: INTEGER;
  BEGIN IF dCls = clwr THEN r := sWrL ELSE r := sRdL END; RETURN r
  END DataState;

  (* the queue's ith byte *)
  PROCEDURE Qb(i: INTEGER): INTEGER;
  BEGIN RETURN q[AND(qh + i, 7)]
  END Qb;

  (* --- the trace --- *)

  PROCEDURE ErrStr(s: ARRAY OF CHAR);
  BEGIN EmHost.Str(EmHost.err, s)
  END ErrStr;

  PROCEDURE Flag(f: INTEGER; ch: CHAR);
  BEGIN IF f # 0 THEN EmHost.Ch(EmHost.err, ch) ELSE EmHost.Ch(EmHost.err, ".") END
  END Flag;

  (* an instruction as it starts: where, the opcode, the registers (A, X
     and Y in 8 digits in 65C832 native mode) *)
  PROCEDURE Trace(o: INTEGER; cycles: LONGINT);
    VAR i, n: INTEGER;
  BEGIN
    IF fE16 = 0 THEN n := 8 ELSE n := 4 END;
    EmSym.Word(PBR * 10000H + PC); EmHost.Ch(EmHost.err, " "); EmHost.ToHex(EmHost.err, o, 2);
    EmHost.Ch(EmHost.err, " ");
    FOR i := 0 TO 2 DO EmHost.Ch(EmHost.err, mnem[o * 3 + i]) END;
    ErrStr(" A="); EmHost.ToHex(EmHost.err, A, n); ErrStr(" X="); EmHost.ToHex(EmHost.err, X, n);
    ErrStr(" Y="); EmHost.ToHex(EmHost.err, Y, n); ErrStr(" S="); EmHost.ToHex(EmHost.err, S, 4);
    ErrStr(" D="); EmHost.ToHex(EmHost.err, D, 4); ErrStr(" DB="); EmHost.ToHex(EmHost.err, DBR, 2);
    ErrStr(" P="); Flag(fN, "N"); Flag(fV, "V"); Flag(fM, "M"); Flag(fX, "X");
    Flag(fD, "D"); Flag(fI, "I"); Flag(fZ, "Z"); Flag(fC, "C");
    ErrStr(" E="); EmHost.ToHex(EmHost.err, fE, 1);
    IF fE16 = 0 THEN ErrStr(" E16=0") END;
    ErrStr(" "); EmHost.Int(EmHost.err, cycles);
    EmHost.Ln(EmHost.err)
  END Trace;

  PROCEDURE Addr(a: INTEGER);
  BEGIN EmHost.ToHex(EmHost.err, a DIV 10000H, 2); EmHost.Ch(EmHost.err, ":"); EmHost.ToHex(EmHost.err, W16(a), 4)
  END Addr;

  (* A store by a state of the core: the bytes queued from PC on are not
     changed by it (on the board; nor here, as the queue holds what was
     read). *)
  PROCEDURE Store(a, v: INTEGER);
  BEGIN
    IF (smc OR trace) & (qn > 0) & (a DIV 10000H = PBR) & (W16(a - PC) < qn) THEN INC(smcHits);
      ErrStr("store to queued code at "); Addr(a); ErrStr(", PC "); Addr(opAt); EmHost.Ln(EmHost.err)
    END;
    write(a, v)
  END Store;

  (* --- the multiply and divide --- *)

  (* v, at w bits, as a signed or an unsigned number *)
  PROCEDURE Signed(v, w: INTEGER): LONGINT;
    VAR r: LONGINT;
  BEGIN r := v; IF (w < 32) & (Bit(v, w - 1) # 0) THEN r := r - ASL(1, w) END; RETURN r
  END Signed;

  PROCEDURE Unsigned(v: INTEGER): LONGINT;
    VAR r, k: LONGINT;
  BEGIN r := v; IF r < 0 THEN k := 10000H; r := r + k * 10000H END; RETURN r
  END Unsigned;

  (* MUL, UML, DIV or UDV of A by xm at A's width, from sOps, sRdL or
     sRdH: the result worked out now, written by Md when it has taken the
     core's cycles, which are one a bit of the width and these: MUL 4,
     UML 2, DIV 6, UDV 4, and a divide by 0 1 (V set). *)
  PROCEDURE MdStart;
    VAR w, mk, a, b, lo, hi: INTEGER; sa, sb, p, qq, rr: LONGINT; sg: BOOLEAN;
  BEGIN w := Aw(); mk := Wmask(w); a := Av(); b := AND(xm, mk);
    sg := (dOp = opmul) OR (dOp = opdiv); mdZero := FALSE;
    IF sg THEN sa := Signed(a, w); sb := Signed(b, w) ELSE sa := Unsigned(a); sb := Unsigned(b) END;
    IF (dOp = opmul) OR (dOp = opuml) THEN
      p := sa * sb; lo := p; hi := LSR(p, w);
      mdA := AND(lo, mk); mdX := AND(hi, mk);
      IF sg & (Bit(mdA, w - 1) # 0) THEN mdV := B(mdX # mk) ELSE mdV := B(mdX # 0) END;
      IF sg THEN mdN := w + 4 ELSE mdN := w + 2 END
    ELSIF b = 0 THEN mdZero := TRUE; mdN := 1
    ELSE
      qq := sa DIV sb; rr := sa - qq * sb; lo := qq; hi := rr;   (* rounded down *)
      mdA := AND(lo, mk); mdX := AND(hi, mk);
      mdV := B(sg & (a = mk - LSR(mk, 1)) & (b = mk));          (* the most negative by -1 *)
      IF sg THEN mdN := w + 6 ELSE mdN := w + 4 END
    END;
    state := sMd
  END MdStart;

  PROCEDURE Md;
  BEGIN DEC(mdN);
    IF mdN = 0 THEN
      IF mdZero THEN fV := 1
      ELSE LdA(mdA); X := AND(mdX, Wmask(Xw())); fV := mdV
      END;
      state := sFetch
    END
  END Md;

  (* --- the states without a bus cycle: a clock each --- *)

  (* The opcode: the pending execute, an interrupt, or the opcode taken
     from the queue's head. *)
  PROCEDURE Fetch(intr: BOOLEAN; cycles: LONGINT);
    VAR o, k: INTEGER;
  BEGIN o := Qb(0);
    IF (xp OR lp) & (intr OR (qn = 0) OR (kind[o] = kPull)) THEN Pending   (* the execute first: fetch again *)
    ELSIF intr THEN IntEntry(PC, 0, Vec(0FFFEH, 0FFEEH, 0FFDEH))           (* IRQ *)
    ELSIF qn # 0 THEN Pending;
      IF (PBR = 0) & (PC = 0) THEN stopped := TRUE
      ELSE
        IF (traceAt >= 0) & (PBR * 10000H + PC = traceAt) THEN
          IF traceSkip > 0 THEN DEC(traceSkip) ELSE trace := TRUE; traceAt := -1 END
        END;
        IF trace THEN Trace(o, cycles);
          IF traceLeft > 0 THEN DEC(traceLeft); IF traceLeft = 0 THEN trace := FALSE END END
        END;
        opAt := PBR * 10000H + PC; PC := W16(PC + 1); take := 1;
        IF o = 42H THEN state := sXop                      (* the WDM prefix: the opcode follows *)
        ELSE Decode(o); k := kind[o];
          IF k = kPull THEN pullIdx := 0; state := sPull; stk16 := (o = 2BH) OR (o = 6BH) OR (o = 0ABH)
          ELSE dLen := len[o];
            IF k = kLocal THEN lp := TRUE
            ELSIF k = kSetup THEN state := sImp
            ELSE state := sOps
            END
          END
        END
      END
    END
  END Fetch;

  (* The opcode after a WDM prefix, from the queue. Not an instruction
     boundary: no interrupt is taken here. *)
  PROCEDURE Xop;
  BEGIN
    IF qn # 0 THEN PC := W16(PC + 1); take := 1;
      IF XDecode(Qb(0)) THEN state := sOps ELSE lp := TRUE; state := sFetch END
    END
  END Xop;

  (* A push, WAI or STP, a cycle after its fetch *)
  PROCEDURE Imp;
    VAR o: INTEGER;
  BEGIN o := IR;
    CASE o OF
      08H: Push8(Pbyte(1))
    | 0BH: Push16(D)
    | 48H: PushW(A, Aw())
    | 4BH: Push8(PBR)
    | 5AH: PushW(Y, Xw())
    | 8BH: Push8(DBR)
    | 0DAH: PushW(X, Xw())
    | 0CBH: state := sWai
    | 0DBH: state := sStp; stopped := TRUE
    ELSE state := sFetch
    END
  END Imp;

  (* The operand bytes, all at once when they are queued: b1-b4, PC at b1,
     pce past the instruction. An immediate is as wide as its register. *)
  PROCEDURE Olen(): INTEGER;
    VAR r, w: INTEGER;
  BEGIN r := dLen;
    IF dMode = mdimm THEN w := Rw(); IF w = 32 THEN INC(r, 3) ELSIF w = 16 THEN INC(r) END END;
    RETURN r
  END Olen;

  PROCEDURE Ops;
    VAR olen, o, b1, b2, b3, w, rw, pcn, pce, md: INTEGER;
  BEGIN olen := Olen();
    IF qn >= olen THEN
      b1 := Qb(0); b2 := Qb(1); b3 := Qb(2); w := b2 * 256 + b1;
      pcn := W16(PC + 1); pce := W16(PC + olen); PC := pce; take := olen;
      IF irx THEN o := 01H ELSE o := IR END;               (* after the prefix none of these *)
      IF o = 00H THEN IntEntry(pce, 1, Vec(0FFFEH, 0FFE6H, 0FFD6H))         (* BRK *)
      ELSIF o = 02H THEN IntEntry(pce, 1, Vec(0FFF4H, 0FFE4H, 0FFD4H))      (* COP *)
      ELSIF (o = 44H) OR (o = 54H) THEN DBR := b1; tmid := b2; state := sMvR;  (* MVP/MVN: dest, src bank *)
        mvS := A24(b2 * 10000H + X); mvD := A24(b1 * 10000H + Y)             (* bank:0000 + X, Y *)
      ELSIF o = 62H THEN Push16(pce + w)                                   (* PER *)
      ELSIF o = 0F4H THEN Push16(w)                                        (* PEA *)
      ELSIF o = 82H THEN Jump(pce + w); state := sFetch                    (* BRL *)
      ELSIF o = 0D4H THEN                                                  (* PEI *)
        IF Dpw() THEN tptr := Hi(D) * 256 + b1 ELSE tptr := W16(Dbase() + b1) END;
        ptrBank := Dbank(); state := sPtrL
      ELSIF o = 20H THEN                                                   (* JSR a *)
        pushQ[0] := Hi(pcn); pushQ[1] := Lo(pcn); pushN := 2; stk16 := FALSE; postPush := ppFetch;
        Jump(w); state := sPush
      ELSIF o = 0FCH THEN                                                  (* JSR (a,X) *)
        pushQ[0] := Hi(pcn); pushQ[1] := Lo(pcn); pushN := 2; stk16 := FALSE; postPush := ppPtr;
        tptr := W16(w + X); ptrBank := PBR; state := sPush
      ELSIF o = 4CH THEN Jump(w); state := sFetch                          (* JMP a *)
      ELSIF (o = 6CH) OR (o = 0DCH) THEN tptr := w; ptrBank := 0; state := sPtrL   (* JMP (a), JML [a] *)
      ELSIF o = 7CH THEN tptr := W16(w + X); ptrBank := PBR; state := sPtrL         (* JMP (a,X) *)
      ELSIF o = 5CH THEN JumpL(b3, w); state := sFetch                     (* JML *)
      ELSIF o = 22H THEN                                                   (* JSL *)
        pushQ[0] := PBR; pushQ[1] := Hi(pce - 1); pushQ[2] := Lo(pce - 1); pushN := 3; stk16 := TRUE;
        postPush := ppFetch; JumpL(b3, w); state := sPush
      ELSE md := dMode;
        CASE md OF
          mdrel: IF Btake() THEN Jump(pce + Sext8(b1)) END; state := sFetch
        | mdimm: rw := Rw();
            IF rw = 32 THEN xm := ORA(ASL(Qb(3), 24), b3 * 10000H + w)
            ELSIF rw = 16 THEN xm := w
            ELSE xm := b1
            END;
            IF Dmd() THEN MdStart ELSE xp := TRUE; state := sFetch END
        | mddp:
            IF Dpw() THEN taddr := Hi(D) * 256 + b1 ELSE taddr := Dbank() * 10000H + W16(Dbase() + b1) END;
            wrap16 := TRUE; state := DataState()
        | mddpx:
            IF Dpw() THEN taddr := Hi(D) * 256 + Lo(b1 + X) ELSE taddr := Dbank() * 10000H + W16(Dbase() + b1 + X) END;
            wrap16 := TRUE; state := DataState()
        | mddpy:
            IF Dpw() THEN taddr := Hi(D) * 256 + Lo(b1 + Y) ELSE taddr := Dbank() * 10000H + W16(Dbase() + b1 + Y) END;
            wrap16 := TRUE; state := DataState()
        | mdsr: taddr := Dbank() * 10000H + W16(S + b1); wrap16 := TRUE; state := DataState()
        | mdidx:
            IF Dpw() THEN tptr := Hi(D) * 256 + Lo(b1 + X) ELSE tptr := W16(Dbase() + b1 + X) END;
            ptrBank := Dbank(); state := sPtrL
        | mdidp, mdidy, mdidl, mdily:
            IF Dpw() THEN tptr := Hi(D) * 256 + b1 ELSE tptr := W16(Dbase() + b1) END;
            ptrBank := Dbank(); state := sPtrL
        | mdsry: tptr := W16(S + b1); ptrBank := Dbank(); state := sPtrL
        | mdabs: taddr := DBR * 10000H + w; wrap16 := FALSE; state := DataState()
        | mdabx: taddr := A24(DBR * 10000H + w + X); wrap16 := FALSE; state := DataState()
        | mdaby: taddr := A24(DBR * 10000H + w + Y); wrap16 := FALSE; state := DataState()
        ELSE (* abl, alx *)
          taddr := b3 * 10000H + w;
          IF md = mdalx THEN taddr := A24(taddr + X) END;
          wrap16 := FALSE; state := DataState()
        END
      END
    END
  END Ops;

  PROCEDURE Wai;
  BEGIN
    IF irq2 THEN
      IF fI = 0 THEN IntEntry(PC, 0, Vec(0FFFEH, 0FFEEH, 0FFDEH)) ELSE state := sFetch END
    END
  END Wai;

  (* --- the states with a bus cycle --- *)

  PROCEDURE PtrH;
    VAR r, o, md: INTEGER;
  BEGIN r := read(ptrBank * 10000H + W16(tptr + 1));
    IF irx THEN o := 01H ELSE o := IR END;
    IF (o = 6CH) OR (o = 7CH) OR (o = 0FCH) THEN Jump(r * 256 + tlo); state := sFetch
    ELSIF o = 0D4H THEN Push16(r * 256 + tlo)
    ELSIF o = 0DCH THEN tmid := r; state := sPtrB
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
    IF (IR = 0DCH) & ~irx THEN Jump(tmid * 256 + tlo); PBR := r; state := sFetch
    ELSE
      taddr := r * 10000H + tmid * 256 + tlo;
      IF dMode = mdily THEN taddr := A24(taddr + Y) END;
      wrap16 := FALSE; state := DataState()
    END
  END PtrB;

  (* The data is latched, not used: a read's execute runs in the next
     opcode's cycle, a read-modify-write's in its write, a multiply's or
     divide's in sMd. A wide operand's next bytes are read in sRdH. *)
  PROCEDURE RdL;
  BEGIN xm := read(taddr);
    IF Rw() # 8 THEN taddrAlt := taddr; taddr := Taddr1(); rb := 1; state := sRdH
    ELSIF dCls = clmw THEN state := sWbL
    ELSIF Dmd() THEN MdStart
    ELSE xp := TRUE; state := sFetch
    END
  END RdL;

  PROCEDURE RdH;
  BEGIN xm := ORA(xm, ASL(read(taddr), 8 * rb));
    IF rb # Rw() DIV 8 - 1 THEN taddr := Taddr1(); INC(rb)
    ELSIF dCls = clmw THEN taddr := taddrAlt; state := sWbL
    ELSIF Dmd() THEN MdStart
    ELSE xp := TRUE; state := sFetch
    END
  END RdH;

  PROCEDURE PushState;
    VAR i: INTEGER;
  BEGIN Store(SpPush(), pushQ[0]);
    SDec;
    FOR i := 0 TO 2 DO pushQ[i] := pushQ[i + 1] END;
    DEC(pushN);
    IF pushN = 0 THEN
      IF Emu() & stk16 THEN S := 100H + Lo(S) END;      (* back to page 1 *)
      IF postPush = ppVec THEN state := sVecL
      ELSIF postPush = ppPtr THEN state := sPtrL
      ELSE state := sFetch
      END
    END
  END PushState;

  PROCEDURE PullState;
    VAR r, o, idx, w: INTEGER;
  BEGIN r := read(SpPull()); SInc; idx := pullIdx; INC(pullIdx); o := IR;
    IF o = 28H THEN SetP(r); state := sFetch
    ELSIF o = 0ABH THEN DBR := r; fN := Bit(r, 7); fZ := B(r = 0);
      IF Emu() THEN S := 100H + Lo(S) END; state := sFetch
    ELSIF o = 2BH THEN
      IF idx = 0 THEN tlo := r
      ELSE D := r * 256 + tlo; fN := Bit(r, 7); fZ := B(D = 0);
        IF Emu() THEN S := 100H + Lo(S) END; state := sFetch
      END
    ELSIF (o = 68H) OR (o = 7AH) OR (o = 0FAH) THEN       (* 1, 2 or 4 bytes *)
      IF o = 68H THEN w := Aw() ELSE w := Xw() END;
      IF idx = 0 THEN tdata := r ELSE tdata := ORA(tdata, ASL(r, 8 * idx)) END;
      IF idx = w DIV 8 - 1 THEN
        IF o = 68H THEN LdA(tdata) ELSIF o = 7AH THEN LdY(tdata) ELSE LdX(tdata) END;
        state := sFetch
      END
    ELSIF o = 60H THEN
      IF idx = 0 THEN tlo := r ELSE Jump(r * 256 + tlo + 1); state := sFetch END
    ELSIF o = 6BH THEN
      IF idx = 0 THEN tlo := r
      ELSIF idx = 1 THEN Jump(r * 256 + tlo + 1)
      ELSE PBR := r; IF Emu() THEN S := 100H + Lo(S) END; state := sFetch
      END
    ELSE (* RTI *)
      IF idx = 0 THEN SetP(r)
      ELSIF idx = 1 THEN tlo := r
      ELSIF idx = 2 THEN Jump(r * 256 + tlo); IF Emu() THEN state := sFetch END
      ELSE PBR := r; state := sFetch
      END
    END
  END PullState;

  (* X and Y step at their width and the addresses follow them; the count
     is A at its wide width, 32 bits in 65C832 native mode with E8 = 1 *)
  PROCEDURE MvW;
    VAR mk: INTEGER; done: BOOLEAN;
  BEGIN Store(mvD, Lo(tdata)); mk := Wmask(Xw());
    IF IR = 54H THEN X := AND(X + 1, mk); Y := AND(Y + 1, mk) ELSE X := AND(X - 1, mk); Y := AND(Y - 1, mk) END;
    mvS := A24(tmid * 10000H + X); mvD := A24(DBR * 10000H + Y);
    IF (fE16 = 0) & (fE # 0) THEN done := A = 0; A := A - 1
    ELSE done := W16(A) = 0; A := ORA(AND(A, -10000H), W16(A - 1))
    END;
    IF done THEN state := sFetch
    ELSIF Intr() THEN Jump(PC - 3); state := sFetch
    ELSE state := sMvR
    END
  END MvW;

  (* --- the queue --- *)

  (* The fill in flight lands its bytes *)
  PROCEDURE Land;
    VAR i: INTEGER;
  BEGIN
    FOR i := 0 TO fn - 1 DO q[AND(qh + qn + i, 7)] := fw[i] END;
    qn := qn + fn; fa := W16(fa + fn)
  END Land;

  (* The edge at the end of a cycle without a bus cycle of the core's own:
     the bytes taken, the fill landing (rdy: its ready is in this cycle),
     a jump, and the next fill. s the state the cycle ran, intr whether
     an interrupt was pending in it, pbr PBR in it. *)
  PROCEDURE Queue(s: INTEGER; rdy, intr: BOOLEAN; pbr: INTEGER);
    VAR qc, fa0, nf: INTEGER; stn, stf, start, busy, drop: BOOLEAN;
  BEGIN
    qh := AND(qh + take, 7); qn := qn - take; qc := qn; fa0 := fa; busy := fbusy; drop := fdrop;
    IF busy THEN nf := fn ELSE nf := 0 END;
    IF jmp THEN qn := 0; fa := jpc
    ELSIF busy & rdy & ~drop THEN Land
    END;
    IF busy & rdy THEN fbusy := FALSE; fdrop := FALSE ELSIF busy & jmp THEN fdrop := TRUE END;
    stn := (s # sFetch) OR ~intr;
    stf := stn & (jmp OR (qc + nf <= 4)); stn := stn & (jmp OR (qc <= 4));
    IF busy THEN start := rdy & ((drop OR jmp) & stn OR ~(drop OR jmp) & stf) ELSE start := stn END;
    IF start THEN
      IF jmp THEN faddr := jbank * 10000H + jpc; fa := jpc
      ELSIF busy & ~drop THEN faddr := pbr * 10000H + W16(fa0 + nf)
      ELSE faddr := pbr * 10000H + fa0
      END;
      fbusy := TRUE; fdrop := FALSE;
      fEnd := clock() + fetch(faddr, clock(), fw, fn)
    END
  END Queue;

  (* A state that uses the bus waits for a fill in flight. *)
  PROCEDURE WaitFill;
    VAR n: INTEGER;
  BEGIN n := fEnd - clock();
    IF n > 0 THEN wait(n) END;
    IF ~fdrop THEN Land END;
    fbusy := FALSE; fdrop := FALSE;
    IF n >= 2 THEN irq1 := irqLine(); irq2 := irq1 ELSE irq2 := irq1; irq1 := irqLine() END
  END WaitFill;

  (* One clock of a state without a bus cycle, or a state with its bus
     cycle (after any fill in flight). The IRQ input reaches the core
     through two flip-flops, the second clocked as a bus cycle ends or
     in a cycle without one. *)
  PROCEDURE Step*(cycles: LONGINT);
    VAR s, pbr: INTEGER; rdy, intr, busy: BOOLEAN; t: LONGINT;
  BEGIN s := state; take := 0; jmp := FALSE;
    IF (s >= sPtrL) & (s <= sMvW) THEN
      IF fbusy THEN WaitFill END;
      t := clock();
      CASE s OF
        sPtrL: tlo := read(ptrBank * 10000H + tptr); state := sPtrH
      | sPtrH: PtrH
      | sPtrB: PtrB
      | sRdL: RdL
      | sRdH: RdH
      | sWrL: Store(taddr, Lo(StVal()));
          IF Sw() # 8 THEN taddr := Taddr1(); rb := 1; state := sWrH ELSE state := sFetch END
      | sWrH: Store(taddr, Lo(LSR(StVal(), 8 * rb)));
          IF rb # Sw() DIV 8 - 1 THEN taddr := Taddr1(); INC(rb) ELSE state := sFetch END
      | sWbL: RmwCore(dOp, xm, FALSE); Store(taddr, Lo(tdata));
          IF Rw() # 8 THEN taddr := Taddr1(); rb := 1; state := sWbH ELSE state := sFetch END
      | sWbH: Store(taddr, Lo(LSR(tdata, 8 * rb)));
          IF rb # Rw() DIV 8 - 1 THEN taddr := Taddr1(); INC(rb) ELSE state := sFetch END
      | sPush: PushState
      | sPull: PullState
      | sVecL: tlo := read(vec); state := sVecH
      | sVecH: Jump(read(W16(vec + 1)) * 256 + tlo); state := sFetch
      | sMvR: tdata := read(mvS); state := sMvW
      | sMvW: MvW
      END;
      IF jmp THEN qn := 0; fa := jpc END;
      IF clock() - t >= 2 THEN irq1 := irqLine(); irq2 := irq1 ELSE irq2 := irq1; irq1 := irqLine() END
    ELSIF fbusy & (clock() + 1 < fEnd) & ((s = sFetch) & (qn = 0) & ~xp & ~lp & ~Intr() OR (s = sOps) & (qn < Olen())
        OR (s = sXop) & (qn = 0)) THEN
      (* waiting for the fill in flight, which is not ready yet: the cycles
         before its ready change nothing but irq1 *)
      wait(fEnd - 1 - clock()); irq1 := irqLine()
    ELSE
      busy := fbusy; rdy := fbusy & (clock() + 1 >= fEnd); intr := Intr(); pbr := PBR;
      CASE s OF
        sFetch: Fetch(intr, clock())
      | sOps: Ops
      | sImp: Imp
      | sWai: Wai
      | sStp:
      | sXop: Xop
      | sMd: Md
      END;
      wait(1);
      Queue(s, rdy, intr, pbr);
      IF ~busy OR rdy THEN irq2 := irq1 END; irq1 := irqLine()
    END
  END Step;

  (* An instruction's deferred execute, before its registers are read, as
     tb_harte does. *)
  PROCEDURE Settle*;
  BEGIN IF state = sFetch THEN Pending END
  END Settle;

  PROCEDURE Empty;
  BEGIN qh := 0; qn := 0; fa := PC; fbusy := FALSE; fdrop := FALSE; xp := FALSE; lp := FALSE
  END Empty;

  (* As the core comes out of reset: emulation mode, the reset vector. *)
  PROCEDURE Reset*;
  BEGIN
    state := sVecL; vec := 0FFFCH;
    fE := 1; fE16 := 1; fM := 1; fX := 1; fI := 1; fD := 0; fC := 0; fZ := 0; fV := 0; fN := 0;
    A := 0; X := 0; Y := 0; S := 1FFH; D := 0; DBR := 0; PBR := 0; PC := 0; xb := FALSE;
    Decode(0); dLen := 1; tlo := 0; tmid := 0; tptr := 0; ptrBank := 0; taddr := 0; wrap16 := FALSE;
    tdata := 0; pushN := 0; stk16 := FALSE; postPush := ppFetch; pullIdx := 0; xm := 0;
    taddrAlt := 0; rb := 0; mvS := 0; mvD := 0; mdN := 0; mdA := 0; mdX := 0; mdV := 0; mdZero := FALSE;
    irq1 := FALSE; irq2 := FALSE; stopped := FALSE; Empty; smcHits := 0; opAt := 0
  END Reset;

  (* At an instruction boundary? For the test against the vectors. *)
  PROCEDURE AtFetch*(): BOOLEAN;
  BEGIN RETURN state = sFetch
  END AtFetch;

  (* Set the registers, at the start of an instruction, the queue empty;
     65C816 (E16 = 1). *)
  PROCEDURE SetState*(pc, s, p, a, x, y, dbr, d, pbr, e: INTEGER);
  BEGIN
    PC := pc; S := s; A := a; X := x; Y := y; DBR := dbr; D := d; PBR := pbr; fE := e; fE16 := 1;
    fN := Bit(p, 7); fV := Bit(p, 6); fM := Bit(p, 5); fX := Bit(p, 4);
    fD := Bit(p, 3); fI := Bit(p, 2); fZ := Bit(p, 1); fC := Bit(p, 0);
    state := sFetch; stopped := FALSE; irq1 := FALSE; irq2 := FALSE; xb := FALSE; irx := FALSE; Empty
  END SetState;

  PROCEDURE GetP*(): INTEGER;
  BEGIN RETURN fN * 128 + fV * 64 + fM * 32 + fX * 16 + fD * 8 + fI * 4 + fZ * 2 + fC
  END GetP;

  (* The bytes an opcode takes from the queue in sOps (an immediate's
     second byte, which hangs on m or x, aside), and what it does in sFetch:
     an implied opcode, a push, WAI or STP, a pull or return, or else on
     to sOps. *)
  PROCEDURE InitKinds;
    VAR i, md: INTEGER;
  BEGIN
    FOR i := 0 TO 255 DO kind[i] := kOps; md := mode[i];
      IF (i = 44H) OR (i = 54H) OR (i = 0F4H) THEN len[i] := 2
      ELSIF (i = 00H) OR (i = 02H) OR (i = 0D4H) THEN len[i] := 1
      ELSIF (md = mdabs) OR (md = mdabx) OR (md = mdaby) OR (md = mdrll) OR (md = mdiab) OR (md = mdiax) OR (md = mdial) THEN len[i] := 2
      ELSIF (md = mdabl) OR (md = mdalx) THEN len[i] := 3
      ELSE len[i] := 1
      END
    END;
    kind[18H] := kLocal; kind[38H] := kLocal; kind[58H] := kLocal; kind[78H] := kLocal;
    kind[0B8H] := kLocal; kind[0D8H] := kLocal; kind[0F8H] := kLocal; kind[0EAH] := kLocal;
    kind[0AH] := kLocal; kind[2AH] := kLocal; kind[4AH] := kLocal; kind[6AH] := kLocal;
    kind[1AH] := kLocal; kind[3AH] := kLocal;
    kind[0AAH] := kLocal; kind[0A8H] := kLocal; kind[8AH] := kLocal; kind[98H] := kLocal;
    kind[0BAH] := kLocal; kind[9AH] := kLocal; kind[9BH] := kLocal; kind[0BBH] := kLocal;
    kind[1BH] := kLocal; kind[3BH] := kLocal; kind[5BH] := kLocal; kind[7BH] := kLocal;
    kind[0E8H] := kLocal; kind[0CAH] := kLocal; kind[0C8H] := kLocal; kind[88H] := kLocal;
    kind[0EBH] := kLocal; kind[0FBH] := kLocal;
    kind[08H] := kSetup; kind[0BH] := kSetup; kind[48H] := kSetup; kind[4BH] := kSetup;
    kind[5AH] := kSetup; kind[8BH] := kSetup; kind[0DAH] := kSetup; kind[0CBH] := kSetup; kind[0DBH] := kSetup;
    kind[28H] := kPull; kind[2BH] := kPull; kind[68H] := kPull; kind[7AH] := kPull;
    kind[0ABH] := kPull; kind[0FAH] := kPull; kind[40H] := kPull; kind[60H] := kPull; kind[6BH] := kPull
  END InitKinds;

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

BEGIN Init; InitKinds; c832 := FALSE; read := NIL; write := NIL; fetch := NIL; wait := NIL; clock := NIL; irqLine := NIL;
  trace := FALSE; smc := FALSE; traceAt := -1; Reset
END EmCore.
