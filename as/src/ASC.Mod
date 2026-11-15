MODULE ASC; (* CPU definitions for the 65xx assembler.

   Mnemonics, addressing modes, instruction formats and the encoding table
   of each supported processor. Port of shared/src/gen_02.c, gen_C02.c,
   gen_RC02.c, gen_816.c and gen_RC19.c: one table row (mode, format,
   opcode byte) replaces each case of the C switch statements. The rows
   are written as text; see D.

   The 65C832 and the 65C816X are the 65C816 with the instructions the
   core of Verilog65C816 adds behind the WDM opcode (docs/65C832.md
   there): MUL, UML, DIV, UDV, ASL/LSR/ASR/ROL/ROR #n and BSW, and on the
   65C832 XFE. Their rows are those of the 65C816 and rows whose opcode
   follows a WDM prefix ($42); see P. The 65C816X is the core as the Tang
   Nano 20K builds it, without the 65C832's modes.

   A leaf module. The scanner (ASS) takes the mnemonics from here; the
   code generator (ASG) looks instructions up with Find and emits them
   according to their format.

   The mnemonic constants shadow the predeclared INC, DEC, AND, ASL, LSR,
   ROL, EOR and ORA, so this module does not use those procedures. *)

  CONST
    (* processors; up to cR6501Q the values are the ELF e_machine numbers
       (see Machine) *)
    c65C816* = 1; c65C02* = 2; c6502* = 3; cR65C02* = 4; cC19* = 5; cR6501Q* = 6;
    c65C832* = 7; c65C816X* = 8;

    (* addressing modes, as written in the source. The parser produces the
       general form (mAbs for a plain address, mPair for "a, b", ...); ASG
       narrows it to direct page or widens it to long where that applies. *)
    mAbs* = 0;       (* A: addr *)
    mAcc* = 1;       (* B: A *)
    mAbsX* = 2;      (* C: addr,X *)
    mAbsY* = 3;      (* D: addr,Y *)
    mAbsL* = 4;      (* E: long *)
    mAbsLX* = 5;     (* F: long,X *)
    mAbsInd* = 6;    (* G: (addr) *)
    mAbsIndX* = 7;   (* H: (addr,X) *)
    mDP* = 8;        (* I: dp *)
    mDPX* = 9;       (* J: dp,X *)
    mDPY* = 10;      (* K: dp,Y *)
    mDPInd* = 11;    (* L: (dp) *)
    mDPIndL* = 12;   (* M: [dp] *)
    mImpl* = 13;     (* N: no operand *)
    mAbsIndL* = 14;  (* O: [addr] *)
    mPair* = 15;     (* P: a,b: block move, or C19 bit/immediate with address *)
    mDPIndX* = 16;   (* Q: (dp,X); the C19 writes (dp),X *)
    mDPIndY* = 17;   (* R: (dp),Y *)
    mDPIndLY* = 18;  (* S: [dp],Y *)
    mImm* = 19;      (* T: #const *)
    mSR* = 20;       (* U: sr,S *)
    mSRIY* = 21;     (* V: (sr,S),Y *)
    mTriple* = 22;   (* W: a,b,c: C19 bit test and branch *)
    nofModes* = 23;

    (* instruction formats: how the operands follow the opcode byte *)
    fImpl* = 0;      (* a: opcode only *)
    fByte* = 1;      (* b: one byte *)
    fWord* = 2;      (* c: two bytes *)
    fLong* = 3;      (* d: three bytes *)
    fImmA* = 4;      (* e: immediate, as wide as the accumulator *)
    fImmX* = 5;      (* f: immediate, as wide as the index registers *)
    fRel* = 6;       (* g: 8 bit relative branch *)
    fRelL* = 7;      (* h: 16 bit relative *)
    fBra* = 8;       (* i: BRA, promoted to BRL when out of range *)
    fBrl* = 9;       (* j: BRL, demoted to BRA when in range *)
    fWordR* = 10;    (* k: two bytes, relocatable call *)
    fLongR* = 11;    (* l: three bytes, relocatable call *)
    fMove* = 12;     (* m: block move: destination bank, source bank *)
    fBitZ* = 13;     (* n: bit number in the opcode, zero page address *)
    fBitA* = 14;     (* o: bit mask, absolute address *)
    fBitZR* = 15;    (* p: bit number in the opcode, zero page address, branch *)
    fBitAR* = 16;    (* q: bit mask, absolute address, branch *)
    fImmZ* = 17;     (* r: immediate, zero page address *)
    fJsb* = 18;      (* s: vector number in the opcode *)

    maxEnt = 372;    (* rows of the largest table, the 65C832's *)

    (* mnemonics, in alphabetical order. DIV is a word of Oberon, so its
       constant is Div; "div" is the scanner's operator, which the parser
       takes for the instruction at the start of a statement. *)
    ADC = 0; ADD = 1; AND = 2; ASL = 3; ASR = 4; BAR = 5; BAS = 6;
    BBR = 7; BBS = 8; BCC = 9; BCS = 10; BEQ = 11; BGE = 12; BIT = 13;
    BMI = 14; BNE = 15; BPL = 16; BRA = 17; BRK = 18; BRL = 19;
    BSW = 20; BVC = 21; BVS = 22; CLC = 23; CLD = 24; CLI = 25;
    CLV = 26; CLW = 27; CMP = 28; COP = 29; CPX = 30; CPY = 31;
    DEC = 32; DEX = 33; DEY = 34; Div* = 35; EOR = 36; EXC = 37;
    INC = 38; INI = 39; INX = 40; INY = 41; JML = 42; JMP = 43;
    JPI = 44; JSB = 45; JSL = 46; JSR = 47; LAB = 48; LAI = 49;
    LAN = 50; LDA = 51; LDX = 52; LDY = 53; LII = 54; LSR = 55;
    MPA = 56; MPY = 57; MUL = 58; MVN = 59; MVP = 60; NEG = 61;
    NOP = 62; NXT = 63; ORA = 64; PEA = 65; PEI = 66; PER = 67;
    PHA = 68; PHB = 69; PHD = 70; PHI = 71; PHK = 72; PHP = 73;
    PHW = 74; PHX = 75; PHY = 76; PIA = 77; PLA = 78; PLB = 79;
    PLD = 80; PLI = 81; PLP = 82; PLW = 83; PLX = 84; PLY = 85;
    PSH = 86; PUL = 87; RBA = 88; REP = 89; RMB = 90; RND = 91;
    ROL = 92; ROR = 93; RTI = 94; RTL = 95; RTS = 96; SBA = 97;
    SBC = 98; SEC = 99; SED = 100; SEI = 101; SEP = 102; SMB = 103;
    STA = 104; STI = 105; STP = 106; STX = 107; STY = 108; STZ = 109;
    SWA = 110; TAD = 111; TAS = 112; TAW = 113; TAX = 114; TAY = 115;
    TCD = 116; TCS = 117; TDA = 118; TDC = 119; TIP = 120; TRB = 121;
    TSA = 122; TSB = 123; TSC = 124; TSX = 125; TWA = 126; TXA = 127;
    TXS = 128; TXY = 129; TYA = 130; TYX = 131; UDV = 132; UML = 133;
    WAI = 134; WDM = 135; XBA = 136; XCE = 137; XFE = 138;
    nofInstr* = 139;

  TYPE Mnemonic* = ARRAY 4 OF CHAR;

  VAR cpu: INTEGER;   (* the processor the table is loaded for; 0 = none *)
    names: ARRAY nofInstr OF Mnemonic;
    (* the encoding table of the current processor, grouped by mnemonic:
       the rows of instruction op are first[op] .. first[op+1]-1 *)
    first: ARRAY 140 OF INTEGER;   (* nofInstr + 1 *)
    tabMode, tabForm, tabCode: ARRAY maxEnt OF BYTE;
    tabPre: ARRAY maxEnt OF BOOLEAN;   (* the opcode follows a WDM *)
    nofEnt, curOp: INTEGER;
    overflow, prefix: BOOLEAN;

  (* --- building a table --- *)

  (* Start the rows of instruction op. The Enter procedures list the
     mnemonics in ascending order, so the rows of one instruction are
     contiguous and an instruction without rows gets an empty range. *)
  PROCEDURE I(op: INTEGER);
  BEGIN
    WHILE curOp < op DO curOp := curOp + 1; first[curOp] := nofEnt END
  END I;

  PROCEDURE E(mode, form, code: INTEGER);
  BEGIN
    IF nofEnt < maxEnt THEN
      tabMode[nofEnt] := mode; tabForm[nofEnt] := form; tabCode[nofEnt] := code;
      tabPre[nofEnt] := prefix;
      nofEnt := nofEnt + 1; first[curOp + 1] := nofEnt
    ELSE overflow := TRUE
    END
  END E;

  PROCEDURE HexVal(ch: CHAR): INTEGER;
    VAR d: INTEGER;
  BEGIN
    IF ch <= "9" THEN d := ORD(ch) - 30H ELSE d := ORD(ch) - 37H END;
    RETURN d
  END HexVal;

  (* The rows of instruction op. Each is four characters: the letter of
     the mode, the letter of the format (both given with the constants
     above) and the opcode byte in hexadecimal. The tables are text and
     not statements because every call costs the loader a relocation,
     and a module may have about a thousand. *)
  PROCEDURE D(op: INTEGER; rows: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN I(op); i := 0;
    WHILE (i + 3 < LEN(rows)) & (rows[i] # 0X) DO
      E(ORD(rows[i]) - ORD("A"), ORD(rows[i + 1]) - ORD("a"),
        HexVal(rows[i + 2]) * 10H + HexVal(rows[i + 3]));
      i := i + 4;
      IF (i < LEN(rows)) & (rows[i] = " ") THEN i := i + 1 END
    END
  END D;

  (* Rows as D's, of opcodes that follow the WDM prefix. *)
  PROCEDURE P(op: INTEGER; rows: ARRAY OF CHAR);
  BEGIN prefix := TRUE; D(op, rows); prefix := FALSE
  END P;

  PROCEDURE Enter6502;
  BEGIN
    D(ADC, "Tb69 Ac6D Ib65 Cc7D Dc79 Jb75 Qb61 Rb71");
    D(AND, "Tb29 Ac2D Ib25 Cc3D Dc39 Jb35 Qb21 Rb31");
    D(ASL, "Na0A Ba0A Ac0E Ib06 Cc1E Jb16");
    D(BCC, "Ag90 Ig90");
    D(BCS, "AgB0 IgB0");
    D(BEQ, "AgF0 IgF0");
    D(BIT, "Ac2C Ib24");
    D(BMI, "Ig30 Ag30");
    D(BNE, "AgD0 IgD0");
    D(BPL, "Ag10 Ig10");
    D(BRK, "Na00 Tb00");
    D(BVC, "Ag50 Ig50");
    D(BVS, "Ag70 Ig70");
    D(CLC, "Na18");
    D(CLD, "NaD8");
    D(CLI, "Na58");
    D(CLV, "NaB8");
    D(CMP, "TbC9 AcCD IbC5 CcDD DcD9 JbD5 QbC1 RbD1");
    D(CPX, "TbE0 AcEC IbE4");
    D(CPY, "TbC0 AcCC IbC4");
    D(DEC, "AcCE IbC6 CcDE JbD6");
    D(DEX, "NaCA");
    D(DEY, "Na88");
    D(EOR, "Tb49 Ac4D Ib45 Cc5D Dc59 Jb55 Qb41 Rb51");
    D(INC, "AcEE IbE6 CcFE JbF6");
    D(INX, "NaE8");
    D(INY, "NaC8");
    D(JMP, "Ic4C Ac4C Gc6C");
    D(JSR, "Ic20 Ac20");
    D(LDA, "TbA9 AcAD IbA5 CcBD DcB9 JbB5 QbA1 RbB1");
    D(LDX, "TbA2 AcAE IbA6 DcBE KbB6");
    D(LDY, "TbA0 AcAC IbA4 CcBC JbB4");
    D(LSR, "Ba4A Na4A Ac4E Ib46 Cc5E Jb56");
    D(NOP, "NaEA");
    D(ORA, "Tb09 Ac0D Ib05 Cc1D Dc19 Jb15 Qb01 Rb11");
    D(PHA, "Na48");
    D(PHP, "Na08");
    D(PLA, "Na68");
    D(PLP, "Na28");
    D(ROL, "Ba2A Na2A Ac2E Ib26 Cc3E Jb36");
    D(ROR, "Na6A Ba6A Ac6E Ib66 Cc7E Jb76");
    D(RTI, "Na40");
    D(RTS, "Na60");
    D(SBC, "TbE9 AcED IbE5 CcFD DcF9 JbF5 QbE1 RbF1");
    D(SEC, "Na38");
    D(SED, "NaF8");
    D(SEI, "Na78");
    D(STA, "Ac8D Ib85 Cc9D Dc99 Jb95 Qb81 Rb91");
    D(STX, "Ac8E Ib86 Kb96");
    D(STY, "Ac8C Ib84 Jb94");
    D(TAX, "NaAA");
    D(TAY, "NaA8");
    D(TSX, "NaBA");
    D(TXA, "Na8A");
    D(TXS, "Na9A");
    D(TYA, "Na98")
  END Enter6502;

  PROCEDURE Enter65C02;
  BEGIN
    D(ADC, "Tb69 Ac6D Ib65 Lb72 Cc7D Dc79 Jb75 Qb61 Rb71");
    D(AND, "Tb29 Ac2D Ib25 Lb32 Cc3D Dc39 Jb35 Qb21 Rb31");
    D(ASL, "Na0A Ba0A Ac0E Ib06 Cc1E Jb16");
    D(BCC, "Ig90 Ag90");
    D(BCS, "IgB0 AgB0");
    D(BEQ, "IgF0 AgF0");
    D(BIT, "Tb89 Ac2C Ib24 Cc3C Jb34");
    D(BMI, "Ig30 Ag30");
    D(BNE, "IgD0 AgD0");
    D(BPL, "Ig10 Ag10");
    D(BRA, "Ig80 Ag80");
    D(BRK, "Na00 Tb00");
    D(BVC, "Ig50 Ag50");
    D(BVS, "Ig70 Ag70");
    D(CLC, "Na18");
    D(CLD, "NaD8");
    D(CLI, "Na58");
    D(CLV, "NaB8");
    D(CMP, "TbC9 AcCD IbC5 LbD2 CcDD DcD9 JbD5 QbC1 RbD1");
    D(CPX, "TbE0 AcEC IbE4");
    D(CPY, "TbC0 AcCC IbC4");
    D(DEC, "Ba3A Na3A AcCE IbC6 CcDE JbD6");
    D(DEX, "NaCA");
    D(DEY, "Na88");
    D(EOR, "Tb49 Ac4D Ib45 Lb52 Cc5D Dc59 Jb55 Qb41 Rb51");
    D(INC, "Ba1A Na1A AcEE IbE6 CcFE JbF6");
    D(INX, "NaE8");
    D(INY, "NaC8");
    D(JMP, "Ic4C Ac4C Gc6C Hc7C");
    D(JSR, "Ic20 Ac20");
    D(LDA, "TbA9 AcAD IbA5 LbB2 CcBD DcB9 JbB5 QbA1 RbB1");
    D(LDX, "TbA2 AcAE IbA6 DcBE KbB6");
    D(LDY, "TbA0 AcAC IbA4 CcBC JbB4");
    D(LSR, "Ba4A Na4A Ac4E Ib46 Cc5E Jb56");
    D(NOP, "NaEA");
    D(ORA, "Tb09 Ac0D Ib05 Lb12 Cc1D Dc19 Jb15 Qb01 Rb11");
    D(PHA, "Na48");
    D(PHP, "Na08");
    D(PHX, "NaDA");
    D(PHY, "Na5A");
    D(PLA, "Na68");
    D(PLP, "Na28");
    D(PLX, "NaFA");
    D(PLY, "Na7A");
    D(ROL, "Ba2A Na2A Ac2E Ib26 Cc3E Jb36");
    D(ROR, "Ba6A Na6A Ac6E Ib66 Cc7E Jb76");
    D(RTI, "Na40");
    D(RTS, "Na60");
    D(SBC, "TbE9 AcED IbE5 LbF2 CcFD DcF9 JbF5 QbE1 RbF1");
    D(SEC, "Na38");
    D(SED, "NaF8");
    D(SEI, "Na78");
    D(STA, "Ac8D Ib85 Lb92 Cc9D Kc99 Dc99 Jb95 Qb81 Rb91");
    D(STX, "Ac8E Ib86 Kb96");
    D(STY, "Ac8C Ib84 Jb94");
    D(STZ, "Ac9C Ib64 Cc9E Jb74");
    D(TAX, "NaAA");
    D(TAY, "NaA8");
    D(TRB, "Ac1C Ib14");
    D(TSB, "Ac0C Ib04");
    D(TSX, "NaBA");
    D(TXA, "Na8A");
    D(TXS, "Na9A");
    D(TYA, "Na98")
  END Enter65C02;

  PROCEDURE EnterR65C02;
  BEGIN
    D(ADC, "Tb69 Ac6D Ib65 Qb61 Rb71 Jb75 Cc7D Dc79 Lb72");
    D(AND, "Tb29 Ac2D Ib25 Qb21 Rb31 Jb35 Cc3D Dc39 Lb32");
    D(ASL, "Ac0E Ib06 Na0A Ba0A Jb16 Cc1E");
    D(BBR, "Wp0F");
    D(BBS, "Wp8F");
    D(BCC, "Ig90 Ag90");
    D(BCS, "IgB0 AgB0");
    D(BEQ, "IgF0 AgF0");
    D(BIT, "Tb89 Ib24 Ac2C");
    D(BMI, "Ig30 Ag30");
    D(BNE, "IgD0 AgD0");
    D(BPL, "Ig10 Ag10");
    D(BRA, "Ig80 Ag80");
    D(BRK, "Na00 Tb00");
    D(BVC, "Ig50 Ag50");
    D(BVS, "Ig70 Ag70");
    D(CLC, "Na18");
    D(CLD, "NaD8");
    D(CLI, "Na58");
    D(CLV, "NaB8");
    D(CMP, "TbC9 AcCD IbC5 QbC1 RbD1 JbD5 CcDD DcD9 GbD2");
    D(CPX, "TbE0 AcEC IbE4");
    D(CPY, "TbC0 AcCC IbC4");
    D(DEC, "AcCE IbC6 Na3A Ba3A JbD6 CcDE");
    D(DEX, "NaCA");
    D(DEY, "Na88");
    D(EOR, "Tb49 Ac4D Ib45 Lb41 Rb51 Jb55 Cc5D Dc59");
    D(INC, "AcEE IbE6 Na1A Ba1A JbF6 CcFE");
    D(INX, "NaE8");
    D(INY, "NaC8");
    D(JMP, "Ic4C Ac4C Gc6C Hc7C");
    D(JSR, "Ic20 Ac20");
    D(LDA, "TbA9 AcAD IbA5 QbA1 RbB1 JbB5 CcBD DcB9 LbB2");
    D(LDX, "TbA2 AcAE IbA6 DcBE KbB6");
    D(LDY, "TbA0 AcAC IbA4 JbB4 CcBC");
    D(LSR, "Ac4E Ib46 Na4A Ba4A Jb56 Cc5E");
    D(NOP, "NaEA");
    D(ORA, "Tb09 Ac0D Ib05 Lb01 Qb11 Jb15 Cc1D Dc19 Gc12");
    D(PHA, "Na48");
    D(PHP, "Na08");
    D(PHX, "NaDA");
    D(PHY, "Na5A");
    D(PLA, "Na68");
    D(PLP, "Na28");
    D(PLX, "NaFA");
    D(PLY, "Na7A");
    D(RMB, "Pn07");
    D(ROL, "Ac2E Ib26 Na2A Ba2A Jb36 Cc3E");
    D(ROR, "Ac6E Ib66 Na6A Ba6A Jb76 Cc7E");
    D(RTI, "Na40");
    D(RTS, "Na60");
    D(SBC, "TbE9 AcED IbE5 LbE1 QbF1 JbF5 CcFD DcF9 GcF2");
    D(SEC, "Na38");
    D(SED, "NaF8");
    D(SEI, "Na78");
    D(SMB, "Pn87");
    D(STA, "Ac8D Ib85 Qb81 Rb91 Jb95 Cc9D Kc99 Dc99 Gc92");
    D(STX, "Ac8E Ib86 Kb96");
    D(STY, "Ac8C Ib84 Jb94");
    D(STZ, "Ac9C Ib64 Jb74 Cc9E");
    D(TAX, "NaAA");
    D(TAY, "NaA8");
    D(TSX, "NaBA");
    D(TXA, "Na8A");
    D(TXS, "Na9A");
    D(TYA, "Na98")
  END EnterR65C02;

  (* The 65C816; xops: and the instructions after WDM; c832: and XFE *)
  PROCEDURE Enter65C816(xops, c832: BOOLEAN);
  BEGIN
    D(ADC, "Te69 Ac6D Ed6F Ib65 Lb72 Mb67 Cc7D Fd7F Dc79 Jb75 Qb61 Rb71 Sb77 Ub63 Vb73");
    D(AND, "Te29 Ac2D Ed2F Ib25 Lb32 Mb27 Cc3D Fd3F Dc39 Jb35 Qb21 Rb31 Sb37 Ub23 Vb33");
    D(ASL, "Na0A Ba0A Ac0E Ib06 Cc1E Jb16");
    IF xops THEN P(ASL, "Tb0A"); P(ASR, "Tb8A") END;
    D(BCC, "Ig90 Ag90");
    D(BCS, "IgB0 AgB0");
    D(BEQ, "IgF0 AgF0");
    D(BIT, "Te89 Ac2C Ib24 Cc3C Jb34");
    D(BMI, "Ig30 Ag30");
    D(BNE, "IgD0 AgD0");
    D(BPL, "Ig10 Ag10");
    D(BRA, "Ii80 Ai80");
    D(BRK, "Na00 Tb00");
    D(BRL, "Ij82 Aj82");
    IF xops THEN P(BSW, "NaEB BaEB") END;
    D(BVC, "Ig50 Ag50");
    D(BVS, "Ig70 Ag70");
    D(CLC, "Na18");
    D(CLD, "NaD8");
    D(CLI, "Na58");
    D(CLV, "NaB8");
    D(CMP, "TeC9 AcCD EdCF IbC5 LbD2 MbC7 CcDD FdDF DcD9 JbD5 QbC1 RbD1 SbD7 UbC3 VbD3");
    D(COP, "Tb02");
    D(CPX, "TfE0 AcEC IbE4");
    D(CPY, "TfC0 AcCC IbC4");
    D(DEC, "Ba3A Na3A AcCE IbC6 CcDE JbD6");
    D(DEX, "NaCA");
    D(DEY, "Na88");
    IF xops THEN  (* the modes of CMP *)
      P(Div, "TeC9 AcCD EdCF IbC5 LbD2 MbC7 CcDD FdDF DcD9 JbD5 QbC1 RbD1 SbD7 UbC3 VbD3")
    END;
    D(EOR, "Te49 Ac4D Ed4F Ib45 Lb52 Mb47 Cc5D Fd5F Dc59 Jb55 Qb41 Rb51 Sb57 Ub43 Vb53");
    D(INC, "Ba1A Na1A AcEE IbE6 CcFE JbF6");
    D(INX, "NaE8");
    D(INY, "NaC8");
    D(JML, "Id5C Ad5C Ed5C GcDC OcDC");
    D(JMP, "Ic4C Ac4C Gc6C Hc7C Ed5C OcDC");
    D(JSL, "Il22 Al22 El22");
    D(JSR, "Ik20 Ak20 HcFC El22");
    D(LDA, "TeA9 AcAD EdAF IbA5 LbB2 MbA7 CcBD FdBF DcB9 JbB5 QbA1 RbB1 SbB7 UbA3 VbB3");
    D(LDX, "TfA2 AcAE IbA6 DcBE KbB6");
    D(LDY, "TfA0 AcAC IbA4 CcBC JbB4");
    D(LSR, "Ba4A Na4A Ac4E Ib46 Cc5E Jb56");
    IF xops THEN P(LSR, "Tb4A");  (* MUL: the modes of ADC *)
      P(MUL, "Te69 Ac6D Ed6F Ib65 Lb72 Mb67 Cc7D Fd7F Dc79 Jb75 Qb61 Rb71 Sb77 Ub63 Vb73")
    END;
    D(MVN, "Pm54");
    D(MVP, "Pm44");
    D(NOP, "NaEA");
    D(ORA, "Te09 Ac0D Ed0F Ib05 Lb12 Mb07 Cc1D Fd1F Dc19 Jb15 Qb01 Rb11 Sb17 Ub03 Vb13");
    D(PEA, "TcF4 AcF4");
    D(PEI, "LbD4");
    D(PER, "Th62 Ih62 Ah62");
    D(PHA, "Na48");
    D(PHB, "Na8B");
    D(PHD, "Na0B");
    D(PHK, "Na4B");
    D(PHP, "Na08");
    D(PHX, "NaDA");
    D(PHY, "Na5A");
    D(PLA, "Na68");
    D(PLB, "NaAB");
    D(PLD, "Na2B");
    D(PLP, "Na28");
    D(PLX, "NaFA");
    D(PLY, "Na7A");
    D(REP, "TbC2");
    D(ROL, "Ba2A Na2A Ac2E Ib26 Cc3E Jb36");
    IF xops THEN P(ROL, "Tb2A") END;
    D(ROR, "Ba6A Na6A Ac6E Ib66 Cc7E Jb76");
    IF xops THEN P(ROR, "Tb6A") END;
    D(RTI, "Na40");
    D(RTL, "Na6B");
    D(RTS, "Na60");
    D(SBC, "TeE9 AcED EdEF IbE5 LbF2 MbE7 CcFD FdFF DcF9 JbF5 QbE1 RbF1 SbF7 UbE3 VbF3");
    D(SEC, "Na38");
    D(SED, "NaF8");
    D(SEI, "Na78");
    D(SEP, "TbE2");
    D(STA, "Ac8D Ed8F Ib85 Lb92 Mb87 Cc9D Fd9F Kc99 Dc99 Jb95 Qb81 Rb91 Sb97 Ub83 Vb93");
    D(STP, "NaDB");
    D(STX, "Ac8E Ib86 Kb96");
    D(STY, "Ac8C Ib84 Jb94");
    D(STZ, "Ac9C Ib64 Cc9E Jb74");
    D(SWA, "NaEB");
    D(TAD, "Na5B");
    D(TAS, "Na1B");
    D(TAX, "NaAA");
    D(TAY, "NaA8");
    D(TCD, "Na5B");
    D(TCS, "Na1B");
    D(TDA, "Na7B");
    D(TDC, "Na7B");
    D(TRB, "Ac1C Ib14");
    D(TSA, "Na3B");
    D(TSB, "Ac0C Ib04");
    D(TSC, "Na3B");
    D(TSX, "NaBA");
    D(TXA, "Na8A");
    D(TXS, "Na9A");
    D(TXY, "Na9B");
    D(TYA, "Na98");
    D(TYX, "NaBB");
    IF xops THEN  (* UDV: the modes of EOR; UML: of AND *)
      P(UDV, "Te49 Ac4D Ed4F Ib45 Lb52 Mb47 Cc5D Fd5F Dc59 Jb55 Qb41 Rb51 Sb57 Ub43 Vb53");
      P(UML, "Te29 Ac2D Ed2F Ib25 Lb32 Mb27 Cc3D Fd3F Dc39 Jb35 Qb21 Rb31 Sb37 Ub23 Vb33")
    END;
    D(WAI, "NaCB");
    D(WDM, "Tb42");
    D(XBA, "NaEB");
    D(XCE, "NaFB");
    IF c832 THEN P(XFE, "NaFB") END
  END Enter65C816;

  PROCEDURE EnterC19;
  BEGIN
    D(ADC, "Tb69 Ib65 Jb75 Ac6D Cc7D Dc79 Lb61 Qb71");
    D(ADD, "Tb89 Ib64 Jb74");
    D(AND, "Tb29 Ib25 Jb35 Ac2D Cc3D Dc39 Lb21 Qb31");
    D(ASL, "Ba0A Na0A Ib06 Jb16 Ac0E Cc1E");
    D(ASR, "Na3A Ba3A");
    D(BAR, "WqE2");
    D(BAS, "WqF2");
    D(BBR, "Wp0F");
    D(BBS, "Wp8F");
    D(BCC, "Ig90 Ag90");
    D(BCS, "IgB0 AgB0");
    D(BEQ, "AgF0 IgF0");
    D(BIT, "Ib24 Ac2C");
    D(BMI, "Ig30 Ag30");
    D(BNE, "IgD0 AgD0");
    D(BPL, "Ig10 Ag10");
    D(BRA, "Ig80 Ag80");
    D(BRK, "Na00 Tb00");
    D(BVC, "Ig50 Ag50");
    D(BVS, "Ig70 Ag70");
    D(CLC, "Na18");
    D(CLD, "NaD8");
    D(CLI, "Na58");
    D(CLV, "NaB8");
    D(CLW, "Na52");
    D(CMP, "TbC9 IbC5 JbD5 AcCD CcDD DcD9 LbC1 QbD1");
    D(CPX, "TbE0 IbE4 AcEC");
    D(CPY, "TbC0 IbC4 AcCC");
    D(DEC, "IbC6 JbD6 AcCE CcDE");
    D(DEX, "NaCA");
    D(DEY, "Na88");
    D(EOR, "Tb49 Ib45 Jb55 Ac4D Cc5D Dc59 Lb41 Qb51");
    D(EXC, "JbD4");
    D(INC, "IbE6 JbF6 AcEE CcFE");
    D(INI, "NaBB");
    D(INX, "NaE8");
    D(INY, "NaC8");
    D(JMP, "Ic4C Ac4C Gc6C Hc7C");
    D(JPI, "Gc0C");
    D(JSB, "Ts0B Is0B");
    D(JSR, "Ic20 Ac20");
    D(LAB, "Na13 Ba13");
    D(LAI, "NaEB");
    D(LAN, "NaAB");
    D(LDA, "TbA9 IbA5 JbB5 AcAD CcBD DcB9 LbA1 QbB1");
    D(LDX, "TbA2 IbA6 KbB6 AcAE DcBE");
    D(LDY, "TbA0 IbA4 JbB4 AcAC CcBC");
    D(LII, "Na9B");
    D(LSR, "Na4A Ba4A Ib46 Jb56 Ac4E Cc5E");
    D(MPA, "Na12");
    D(MPY, "Na02");
    D(NEG, "Na1A Ba1A");
    D(NOP, "NaEA");
    D(NXT, "Na8B");
    D(ORA, "Tb09 Ib05 Jb15 Ac0D Cc1D Dc19 Lb01 Qb11");
    D(PHA, "Na48");
    D(PHI, "NaCB");
    D(PHP, "Na08");
    D(PHW, "Na23");
    D(PHX, "NaDA");
    D(PHY, "Na5A");
    D(PIA, "NaFB");
    D(PLA, "Na68");
    D(PLI, "NaDB");
    D(PLP, "Na28");
    D(PLW, "Na33");
    D(PLX, "NaFA");
    D(PLY, "Na7A");
    D(PSH, "Na22");
    D(PUL, "Na32");
    D(RBA, "PoC2");
    D(RMB, "Pn07");
    D(RND, "Na42");
    D(ROL, "Na2A Ba2A Ib26 Jb36 Ac2E Cc3E");
    D(ROR, "Na6A Ba6A Ib66 Jb76 Ac6E Cc7E");
    D(RTI, "Na40");
    D(RTS, "Na60");
    D(SBA, "PoD2");
    D(SBC, "TbE9 IbE5 JbF5 AcED CcFD DcF9 LbE1 QbF1");
    D(SEC, "Na38");
    D(SED, "NaF8");
    D(SEI, "Na78");
    D(SMB, "Pn87");
    D(STA, "Ib85 Jb95 Ac8D Cc9D Kc99 Dc99 Lb81 Qb91");
    D(STI, "PrB2");
    D(STX, "Ib86 Kb96 Ac8E");
    D(STY, "Ib84 Jb94 Ac8C");
    D(TAW, "Na62");
    D(TAX, "NaAA");
    D(TAY, "NaA8");
    D(TIP, "Na03");
    D(TSX, "NaBA");
    D(TWA, "Na72");
    D(TXA, "Na8A");
    D(TXS, "Na9A");
    D(TYA, "Na98")
  END EnterC19;

  (* --- queries --- *)

  PROCEDURE Known*(c: INTEGER): BOOLEAN;
  BEGIN RETURN (c >= c65C816) & (c <= c65C816X)
  END Known;

  (* The ELF e_machine number of processor c. ELF has none for the
     65C832 or the 65C816X; their programs are marked 65C816 code. *)
  PROCEDURE Machine*(c: INTEGER): INTEGER;
  BEGIN
    IF (c = c65C832) OR (c = c65C816X) THEN c := c65C816 END;
    RETURN c
  END Machine;

  (* Processor c has the instructions after WDM. *)
  PROCEDURE Extended*(c: INTEGER): BOOLEAN;
  BEGIN RETURN (c = c65C832) OR (c = c65C816X)
  END Extended;

  (* Instruction op is one of those after WDM that are spelled like no
     other: the scanner takes these for mnemonics only in a source that
     has chosen a processor with them, so that elsewhere they are names
     (OS16's Numerics.s has a routine mul). DIV is an operator besides. *)
  PROCEDURE Extension*(op: INTEGER): BOOLEAN;
  BEGIN RETURN (op = BSW) OR (op = MUL) OR (op = UDV) OR (op = UML) OR (op = XFE)
  END Extension;

  (* Load the encoding table of processor c. *)
  PROCEDURE Select*(c: INTEGER);
  BEGIN
    IF c # cpu THEN
      cpu := c; nofEnt := 0; curOp := 0; first[0] := 0; first[1] := 0;
      IF c = c65C816 THEN Enter65C816(FALSE, FALSE)
      ELSIF c = c65C816X THEN Enter65C816(TRUE, FALSE)
      ELSIF c = c65C832 THEN Enter65C816(TRUE, TRUE)
      ELSIF c = c65C02 THEN Enter65C02
      ELSIF c = c6502 THEN Enter6502
      ELSIF (c = cR65C02) OR (c = cR6501Q) THEN EnterR65C02
      ELSIF c = cC19 THEN EnterC19
      END;
      I(nofInstr);
      ASSERT(~overflow)
    END
  END Select;

  PROCEDURE Cpu*(): INTEGER;
  BEGIN RETURN cpu
  END Cpu;

  (* Look up instruction op with addressing mode mode. code is the
     opcode byte, plus $4200 if it follows the WDM prefix. *)
  PROCEDURE Find*(op, mode: INTEGER; VAR form, code: INTEGER): BOOLEAN;
    VAR i, n: INTEGER;
  BEGIN i := first[op]; n := first[op + 1];
    WHILE (i < n) & (tabMode[i] # mode) DO i := i + 1 END;
    IF i < n THEN form := tabForm[i]; code := tabCode[i];
      IF tabPre[i] THEN code := code + 4200H END
    END;
    RETURN i < n
  END Find;

  PROCEDURE Has*(op, mode: INTEGER): BOOLEAN;
    VAR form, code: INTEGER;
  BEGIN RETURN Find(op, mode, form, code)
  END Has;

  (* Number of operand expressions the parser supplies for a mode. *)
  PROCEDURE Operands*(mode: INTEGER): INTEGER;
    VAR n: INTEGER;
  BEGIN
    IF (mode = mImpl) OR (mode = mAcc) THEN n := 0
    ELSIF mode = mPair THEN n := 2
    ELSIF mode = mTriple THEN n := 3
    ELSE n := 1
    END;
    RETURN n
  END Operands;

  PROCEDURE Name*(op: INTEGER; VAR s: Mnemonic);
  BEGIN s := names[op]
  END Name;

  (* The operand syntax of a mode, for messages. *)
  PROCEDURE ModeName*(mode: INTEGER; VAR s: ARRAY OF CHAR);
  BEGIN
    CASE mode OF
      mAbs: s := "addr" | mAcc: s := "A" | mAbsX: s := "addr,X"
    | mAbsY: s := "addr,Y" | mAbsL: s := "long" | mAbsLX: s := "long,X"
    | mAbsInd: s := "(addr)" | mAbsIndX: s := "(addr,X)" | mDP: s := "dp"
    | mDPX: s := "dp,X" | mDPY: s := "dp,Y" | mDPInd: s := "(dp)"
    | mDPIndL: s := "[dp]" | mImpl: s := "" | mAbsIndL: s := "[addr]"
    | mPair: s := "a,b" | mDPIndX: s := "(dp,X)" | mDPIndY: s := "(dp),Y"
    | mDPIndLY: s := "[dp],Y" | mImm: s := "#const" | mSR: s := "sr,S"
    | mSRIY: s := "(sr,S),Y" | mTriple: s := "a,b,c"
    END
  END ModeName;

  PROCEDURE CpuName*(c: INTEGER; VAR s: ARRAY OF CHAR);
  BEGIN
    IF c = c65C816 THEN s := "65C816"
    ELSIF c = c65C02 THEN s := "65C02"
    ELSIF c = c6502 THEN s := "6502"
    ELSIF c = cR65C02 THEN s := "R65C02"
    ELSIF c = cC19 THEN s := "C19"
    ELSIF c = cR6501Q THEN s := "R6501Q"
    ELSIF c = c65C832 THEN s := "65C832"
    ELSIF c = c65C816X THEN s := "65C816X"
    ELSE s := "none"
    END
  END CpuName;

  PROCEDURE N(op: INTEGER; name: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE (i < 3) & (name[i] # 0X) DO names[op][i] := name[i]; i := i + 1 END;
    names[op][i] := 0X
  END N;

BEGIN cpu := 0; nofEnt := 0; curOp := 0; overflow := FALSE; prefix := FALSE;
  N(ADC, "adc"); N(ADD, "add"); N(AND, "and"); N(ASL, "asl"); N(ASR, "asr");
  N(BAR, "bar"); N(BAS, "bas"); N(BBR, "bbr"); N(BBS, "bbs"); N(BCC, "bcc");
  N(BCS, "bcs"); N(BEQ, "beq"); N(BGE, "bge"); N(BIT, "bit"); N(BMI, "bmi");
  N(BNE, "bne"); N(BPL, "bpl"); N(BRA, "bra"); N(BRK, "brk"); N(BRL, "brl");
  N(BSW, "bsw"); N(BVC, "bvc"); N(BVS, "bvs"); N(CLC, "clc"); N(CLD, "cld"); N(CLI, "cli");
  N(CLV, "clv"); N(CLW, "clw"); N(CMP, "cmp"); N(COP, "cop"); N(CPX, "cpx");
  N(CPY, "cpy"); N(DEC, "dec"); N(DEX, "dex"); N(DEY, "dey"); N(Div, "div"); N(EOR, "eor");
  N(EXC, "exc"); N(INC, "inc"); N(INI, "ini"); N(INX, "inx"); N(INY, "iny");
  N(JML, "jml"); N(JMP, "jmp"); N(JPI, "jpi"); N(JSB, "jsb"); N(JSL, "jsl");
  N(JSR, "jsr"); N(LAB, "lab"); N(LAI, "lai"); N(LAN, "lan"); N(LDA, "lda");
  N(LDX, "ldx"); N(LDY, "ldy"); N(LII, "lii"); N(LSR, "lsr"); N(MPA, "mpa");
  N(MPY, "mpy"); N(MUL, "mul"); N(MVN, "mvn"); N(MVP, "mvp"); N(NEG, "neg"); N(NOP, "nop");
  N(NXT, "nxt"); N(ORA, "ora"); N(PEA, "pea"); N(PEI, "pei"); N(PER, "per");
  N(PHA, "pha"); N(PHB, "phb"); N(PHD, "phd"); N(PHI, "phi"); N(PHK, "phk");
  N(PHP, "php"); N(PHW, "phw"); N(PHX, "phx"); N(PHY, "phy"); N(PIA, "pia");
  N(PLA, "pla"); N(PLB, "plb"); N(PLD, "pld"); N(PLI, "pli"); N(PLP, "plp");
  N(PLW, "plw"); N(PLX, "plx"); N(PLY, "ply"); N(PSH, "psh"); N(PUL, "pul");
  N(RBA, "rba"); N(REP, "rep"); N(RMB, "rmb"); N(RND, "rnd"); N(ROL, "rol");
  N(ROR, "ror"); N(RTI, "rti"); N(RTL, "rtl"); N(RTS, "rts"); N(SBA, "sba");
  N(SBC, "sbc"); N(SEC, "sec"); N(SED, "sed"); N(SEI, "sei"); N(SEP, "sep");
  N(SMB, "smb"); N(STA, "sta"); N(STI, "sti"); N(STP, "stp"); N(STX, "stx");
  N(STY, "sty"); N(STZ, "stz"); N(SWA, "swa"); N(TAD, "tad"); N(TAS, "tas");
  N(TAW, "taw"); N(TAX, "tax"); N(TAY, "tay"); N(TCD, "tcd"); N(TCS, "tcs");
  N(TDA, "tda"); N(TDC, "tdc"); N(TIP, "tip"); N(TRB, "trb"); N(TSA, "tsa");
  N(TSB, "tsb"); N(TSC, "tsc"); N(TSX, "tsx"); N(TWA, "twa"); N(TXA, "txa");
  N(TXS, "txs"); N(TXY, "txy"); N(TYA, "tya"); N(TYX, "tyx");
  N(UDV, "udv"); N(UML, "uml"); N(WAI, "wai");
  N(WDM, "wdm"); N(XBA, "xba"); N(XCE, "xce"); N(XFE, "xfe")
END ASC.
