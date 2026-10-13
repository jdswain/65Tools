MODULE ASC; (* CPU definitions for the 65xx assembler.

   Mnemonics, addressing modes, instruction formats and the encoding table
   of each supported processor. Port of shared/src/gen_02.c, gen_C02.c,
   gen_RC02.c, gen_816.c and gen_RC19.c: one table row (mode, format,
   opcode byte) replaces each case of the C switch statements.

   A leaf module. The scanner (ASS) takes the mnemonics from here; the
   code generator (ASG) looks instructions up with Find and emits them
   according to their format.

   The mnemonic constants shadow the predeclared INC, DEC, AND, ASL, LSR,
   ROL, EOR and ORA, so this module does not use those procedures. *)

  CONST
    (* processors; the values are the ELF e_machine numbers *)
    c65C816* = 1; c65C02* = 2; c6502* = 3; cR65C02* = 4; cC19* = 5; cR6501Q* = 6;

    (* addressing modes, as written in the source. The parser produces the
       general form (mAbs for a plain address, mPair for "a, b", ...); ASG
       narrows it to direct page or widens it to long where that applies. *)
    mAbs* = 0;       (* addr *)
    mAcc* = 1;       (* A *)
    mAbsX* = 2;      (* addr,X *)
    mAbsY* = 3;      (* addr,Y *)
    mAbsL* = 4;      (* long *)
    mAbsLX* = 5;     (* long,X *)
    mAbsInd* = 6;    (* (addr) *)
    mAbsIndX* = 7;   (* (addr,X) *)
    mDP* = 8;        (* dp *)
    mDPX* = 9;       (* dp,X *)
    mDPY* = 10;      (* dp,Y *)
    mDPInd* = 11;    (* (dp) *)
    mDPIndL* = 12;   (* [dp] *)
    mImpl* = 13;     (* no operand *)
    mAbsIndL* = 14;  (* [addr] *)
    mPair* = 15;     (* a,b: block move, or C19 bit/immediate with address *)
    mDPIndX* = 16;   (* (dp,X); the C19 writes (dp),X *)
    mDPIndY* = 17;   (* (dp),Y *)
    mDPIndLY* = 18;  (* [dp],Y *)
    mImm* = 19;      (* #const *)
    mSR* = 20;       (* sr,S *)
    mSRIY* = 21;     (* (sr,S),Y *)
    mTriple* = 22;   (* a,b,c: C19 bit test and branch *)
    nofModes* = 23;

    (* instruction formats: how the operands follow the opcode byte *)
    fImpl* = 0;      (* opcode only *)
    fByte* = 1;      (* one byte *)
    fWord* = 2;      (* two bytes *)
    fLong* = 3;      (* three bytes *)
    fImmA* = 4;      (* immediate, as wide as the accumulator *)
    fImmX* = 5;      (* immediate, as wide as the index registers *)
    fRel* = 6;       (* 8 bit relative branch *)
    fRelL* = 7;      (* 16 bit relative *)
    fBra* = 8;       (* BRA, promoted to BRL when out of range *)
    fBrl* = 9;       (* BRL, demoted to BRA when in range *)
    fWordR* = 10;    (* two bytes, relocatable call *)
    fLongR* = 11;    (* three bytes, relocatable call *)
    fMove* = 12;     (* block move: destination bank, source bank *)
    fBitZ* = 13;     (* bit number in the opcode, zero page address *)
    fBitA* = 14;     (* bit mask, absolute address *)
    fBitZR* = 15;    (* bit number in the opcode, zero page address, branch *)
    fBitAR* = 16;    (* bit mask, absolute address, branch *)
    fImmZ* = 17;     (* immediate, zero page address *)
    fJsb* = 18;      (* vector number in the opcode *)

    maxEnt = 304;    (* rows of the largest table, the 65C816's *)

    (* mnemonics, in alphabetical order *)
    ADC = 0; ADD = 1; AND = 2; ASL = 3; ASR = 4; BAR = 5; BAS = 6;
    BBR = 7; BBS = 8; BCC = 9; BCS = 10; BEQ = 11; BGE = 12; BIT = 13;
    BMI = 14; BNE = 15; BPL = 16; BRA = 17; BRK = 18; BRL = 19;
    BVC = 20; BVS = 21; CLC = 22; CLD = 23; CLI = 24; CLV = 25;
    CLW = 26; CMP = 27; COP = 28; CPX = 29; CPY = 30; DEC = 31;
    DEX = 32; DEY = 33; EOR = 34; EXC = 35; INC = 36; INI = 37;
    INX = 38; INY = 39; JML = 40; JMP = 41; JPI = 42; JSB = 43;
    JSL = 44; JSR = 45; LAB = 46; LAI = 47; LAN = 48; LDA = 49;
    LDX = 50; LDY = 51; LII = 52; LSR = 53; MPA = 54; MPY = 55;
    MVN = 56; MVP = 57; NEG = 58; NOP = 59; NXT = 60; ORA = 61;
    PEA = 62; PEI = 63; PER = 64; PHA = 65; PHB = 66; PHD = 67;
    PHI = 68; PHK = 69; PHP = 70; PHW = 71; PHX = 72; PHY = 73;
    PIA = 74; PLA = 75; PLB = 76; PLD = 77; PLI = 78; PLP = 79;
    PLW = 80; PLX = 81; PLY = 82; PSH = 83; PUL = 84; RBA = 85;
    REP = 86; RMB = 87; RND = 88; ROL = 89; ROR = 90; RTI = 91;
    RTL = 92; RTS = 93; SBA = 94; SBC = 95; SEC = 96; SED = 97;
    SEI = 98; SEP = 99; SMB = 100; STA = 101; STI = 102; STP = 103;
    STX = 104; STY = 105; STZ = 106; SWA = 107; TAD = 108; TAS = 109;
    TAW = 110; TAX = 111; TAY = 112; TCD = 113; TCS = 114; TDA = 115;
    TDC = 116; TIP = 117; TRB = 118; TSA = 119; TSB = 120; TSC = 121;
    TSX = 122; TWA = 123; TXA = 124; TXS = 125; TXY = 126; TYA = 127;
    TYX = 128; WAI = 129; WDM = 130; XBA = 131; XCE = 132;
    nofInstr* = 133;

  TYPE Mnemonic* = ARRAY 4 OF CHAR;

  VAR cpu: INTEGER;   (* the processor the table is loaded for; 0 = none *)
    names: ARRAY nofInstr OF Mnemonic;
    (* the encoding table of the current processor, grouped by mnemonic:
       the rows of instruction op are first[op] .. first[op+1]-1 *)
    first: ARRAY 134 OF INTEGER;   (* nofInstr + 1 *)
    tabMode, tabForm, tabCode: ARRAY maxEnt OF BYTE;
    nofEnt, curOp: INTEGER;
    overflow: BOOLEAN;

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
      nofEnt := nofEnt + 1; first[curOp + 1] := nofEnt
    ELSE overflow := TRUE
    END
  END E;

  PROCEDURE Enter6502;
  BEGIN
    I(ADC); E(mImm, fByte, 69H); E(mAbs, fWord, 6DH); E(mDP, fByte, 65H); E(mAbsX, fWord, 7DH);
      E(mAbsY, fWord, 79H); E(mDPX, fByte, 75H); E(mDPIndX, fByte, 61H); E(mDPIndY, fByte, 71H);
    I(AND); E(mImm, fByte, 29H); E(mAbs, fWord, 2DH); E(mDP, fByte, 25H); E(mAbsX, fWord, 3DH);
      E(mAbsY, fWord, 39H); E(mDPX, fByte, 35H); E(mDPIndX, fByte, 21H); E(mDPIndY, fByte, 31H);
    I(ASL); E(mImpl, fImpl, 0AH); E(mAcc, fImpl, 0AH); E(mAbs, fWord, 0EH); E(mDP, fByte, 06H);
      E(mAbsX, fWord, 1EH); E(mDPX, fByte, 16H);
    I(BCC); E(mAbs, fRel, 90H); E(mDP, fRel, 90H);
    I(BCS); E(mAbs, fRel, 0B0H); E(mDP, fRel, 0B0H);
    I(BEQ); E(mAbs, fRel, 0F0H); E(mDP, fRel, 0F0H);
    I(BIT); E(mAbs, fWord, 2CH); E(mDP, fByte, 24H);
    I(BMI); E(mDP, fRel, 30H); E(mAbs, fRel, 30H);
    I(BNE); E(mAbs, fRel, 0D0H); E(mDP, fRel, 0D0H);
    I(BPL); E(mAbs, fRel, 10H); E(mDP, fRel, 10H);
    I(BRK); E(mImpl, fImpl, 00H); E(mImm, fByte, 00H);
    I(BVC); E(mAbs, fRel, 50H); E(mDP, fRel, 50H);
    I(BVS); E(mAbs, fRel, 70H); E(mDP, fRel, 70H);
    I(CLC); E(mImpl, fImpl, 18H);
    I(CLD); E(mImpl, fImpl, 0D8H);
    I(CLI); E(mImpl, fImpl, 58H);
    I(CLV); E(mImpl, fImpl, 0B8H);
    I(CMP); E(mImm, fByte, 0C9H); E(mAbs, fWord, 0CDH); E(mDP, fByte, 0C5H); E(mAbsX, fWord, 0DDH);
      E(mAbsY, fWord, 0D9H); E(mDPX, fByte, 0D5H); E(mDPIndX, fByte, 0C1H); E(mDPIndY, fByte, 0D1H);
    I(CPX); E(mImm, fByte, 0E0H); E(mAbs, fWord, 0ECH); E(mDP, fByte, 0E4H);
    I(CPY); E(mImm, fByte, 0C0H); E(mAbs, fWord, 0CCH); E(mDP, fByte, 0C4H);
    I(DEC); E(mAbs, fWord, 0CEH); E(mDP, fByte, 0C6H); E(mAbsX, fWord, 0DEH); E(mDPX, fByte, 0D6H);
    I(DEX); E(mImpl, fImpl, 0CAH);
    I(DEY); E(mImpl, fImpl, 88H);
    I(EOR); E(mImm, fByte, 49H); E(mAbs, fWord, 4DH); E(mDP, fByte, 45H); E(mAbsX, fWord, 5DH);
      E(mAbsY, fWord, 59H); E(mDPX, fByte, 55H); E(mDPIndX, fByte, 41H); E(mDPIndY, fByte, 51H);
    I(INC); E(mAbs, fWord, 0EEH); E(mDP, fByte, 0E6H); E(mAbsX, fWord, 0FEH); E(mDPX, fByte, 0F6H);
    I(INX); E(mImpl, fImpl, 0E8H);
    I(INY); E(mImpl, fImpl, 0C8H);
    I(JMP); E(mDP, fWord, 4CH); E(mAbs, fWord, 4CH); E(mAbsInd, fWord, 6CH);
    I(JSR); E(mDP, fWord, 20H); E(mAbs, fWord, 20H);
    I(LDA); E(mImm, fByte, 0A9H); E(mAbs, fWord, 0ADH); E(mDP, fByte, 0A5H); E(mAbsX, fWord, 0BDH);
      E(mAbsY, fWord, 0B9H); E(mDPX, fByte, 0B5H); E(mDPIndX, fByte, 0A1H); E(mDPIndY, fByte, 0B1H);
    I(LDX); E(mImm, fByte, 0A2H); E(mAbs, fWord, 0AEH); E(mDP, fByte, 0A6H); E(mAbsY, fWord, 0BEH);
      E(mDPY, fByte, 0B6H);
    I(LDY); E(mImm, fByte, 0A0H); E(mAbs, fWord, 0ACH); E(mDP, fByte, 0A4H); E(mAbsX, fWord, 0BCH);
      E(mDPX, fByte, 0B4H);
    I(LSR); E(mAcc, fImpl, 4AH); E(mImpl, fImpl, 4AH); E(mAbs, fWord, 4EH); E(mDP, fByte, 46H);
      E(mAbsX, fWord, 5EH); E(mDPX, fByte, 56H);
    I(NOP); E(mImpl, fImpl, 0EAH);
    I(ORA); E(mImm, fByte, 09H); E(mAbs, fWord, 0DH); E(mDP, fByte, 05H); E(mAbsX, fWord, 1DH);
      E(mAbsY, fWord, 19H); E(mDPX, fByte, 15H); E(mDPIndX, fByte, 01H); E(mDPIndY, fByte, 11H);
    I(PHA); E(mImpl, fImpl, 48H);
    I(PHP); E(mImpl, fImpl, 08H);
    I(PLA); E(mImpl, fImpl, 68H);
    I(PLP); E(mImpl, fImpl, 28H);
    I(ROL); E(mAcc, fImpl, 2AH); E(mImpl, fImpl, 2AH); E(mAbs, fWord, 2EH); E(mDP, fByte, 26H);
      E(mAbsX, fWord, 3EH); E(mDPX, fByte, 36H);
    I(ROR); E(mImpl, fImpl, 6AH); E(mAcc, fImpl, 6AH); E(mAbs, fWord, 6EH); E(mDP, fByte, 66H);
      E(mAbsX, fWord, 7EH); E(mDPX, fByte, 76H);
    I(RTI); E(mImpl, fImpl, 40H);
    I(RTS); E(mImpl, fImpl, 60H);
    I(SBC); E(mImm, fByte, 0E9H); E(mAbs, fWord, 0EDH); E(mDP, fByte, 0E5H); E(mAbsX, fWord, 0FDH);
      E(mAbsY, fWord, 0F9H); E(mDPX, fByte, 0F5H); E(mDPIndX, fByte, 0E1H); E(mDPIndY, fByte, 0F1H);
    I(SEC); E(mImpl, fImpl, 38H);
    I(SED); E(mImpl, fImpl, 0F8H);
    I(SEI); E(mImpl, fImpl, 78H);
    I(STA); E(mAbs, fWord, 8DH); E(mDP, fByte, 85H); E(mAbsX, fWord, 9DH); E(mAbsY, fWord, 99H);
      E(mDPX, fByte, 95H); E(mDPIndX, fByte, 81H); E(mDPIndY, fByte, 91H);
    I(STX); E(mAbs, fWord, 8EH); E(mDP, fByte, 86H); E(mDPY, fByte, 96H);
    I(STY); E(mAbs, fWord, 8CH); E(mDP, fByte, 84H); E(mDPX, fByte, 94H);
    I(TAX); E(mImpl, fImpl, 0AAH);
    I(TAY); E(mImpl, fImpl, 0A8H);
    I(TSX); E(mImpl, fImpl, 0BAH);
    I(TXA); E(mImpl, fImpl, 8AH);
    I(TXS); E(mImpl, fImpl, 9AH);
    I(TYA); E(mImpl, fImpl, 98H)
  END Enter6502;

  PROCEDURE Enter65C02;
  BEGIN
    I(ADC); E(mImm, fByte, 69H); E(mAbs, fWord, 6DH); E(mDP, fByte, 65H); E(mDPInd, fByte, 72H);
      E(mAbsX, fWord, 7DH); E(mAbsY, fWord, 79H); E(mDPX, fByte, 75H); E(mDPIndX, fByte, 61H);
      E(mDPIndY, fByte, 71H);
    I(AND); E(mImm, fByte, 29H); E(mAbs, fWord, 2DH); E(mDP, fByte, 25H); E(mDPInd, fByte, 32H);
      E(mAbsX, fWord, 3DH); E(mAbsY, fWord, 39H); E(mDPX, fByte, 35H); E(mDPIndX, fByte, 21H);
      E(mDPIndY, fByte, 31H);
    I(ASL); E(mImpl, fImpl, 0AH); E(mAcc, fImpl, 0AH); E(mAbs, fWord, 0EH); E(mDP, fByte, 06H);
      E(mAbsX, fWord, 1EH); E(mDPX, fByte, 16H);
    I(BCC); E(mDP, fRel, 90H); E(mAbs, fRel, 90H);
    I(BCS); E(mDP, fRel, 0B0H); E(mAbs, fRel, 0B0H);
    I(BEQ); E(mDP, fRel, 0F0H); E(mAbs, fRel, 0F0H);
    I(BIT); E(mImm, fByte, 89H); E(mAbs, fWord, 2CH); E(mDP, fByte, 24H); E(mAbsX, fWord, 3CH);
      E(mDPX, fByte, 34H);
    I(BMI); E(mDP, fRel, 30H); E(mAbs, fRel, 30H);
    I(BNE); E(mDP, fRel, 0D0H); E(mAbs, fRel, 0D0H);
    I(BPL); E(mDP, fRel, 10H); E(mAbs, fRel, 10H);
    I(BRA); E(mDP, fRel, 80H); E(mAbs, fRel, 80H);
    I(BRK); E(mImpl, fImpl, 00H); E(mImm, fByte, 00H);
    I(BVC); E(mDP, fRel, 50H); E(mAbs, fRel, 50H);
    I(BVS); E(mDP, fRel, 70H); E(mAbs, fRel, 70H);
    I(CLC); E(mImpl, fImpl, 18H);
    I(CLD); E(mImpl, fImpl, 0D8H);
    I(CLI); E(mImpl, fImpl, 58H);
    I(CLV); E(mImpl, fImpl, 0B8H);
    I(CMP); E(mImm, fByte, 0C9H); E(mAbs, fWord, 0CDH); E(mDP, fByte, 0C5H); E(mDPInd, fByte, 0D2H);
      E(mAbsX, fWord, 0DDH); E(mAbsY, fWord, 0D9H); E(mDPX, fByte, 0D5H); E(mDPIndX, fByte, 0C1H);
      E(mDPIndY, fByte, 0D1H);
    I(CPX); E(mImm, fByte, 0E0H); E(mAbs, fWord, 0ECH); E(mDP, fByte, 0E4H);
    I(CPY); E(mImm, fByte, 0C0H); E(mAbs, fWord, 0CCH); E(mDP, fByte, 0C4H);
    I(DEC); E(mAcc, fImpl, 3AH); E(mImpl, fImpl, 3AH); E(mAbs, fWord, 0CEH); E(mDP, fByte, 0C6H);
      E(mAbsX, fWord, 0DEH); E(mDPX, fByte, 0D6H);
    I(DEX); E(mImpl, fImpl, 0CAH);
    I(DEY); E(mImpl, fImpl, 88H);
    I(EOR); E(mImm, fByte, 49H); E(mAbs, fWord, 4DH); E(mDP, fByte, 45H); E(mDPInd, fByte, 52H);
      E(mAbsX, fWord, 5DH); E(mAbsY, fWord, 59H); E(mDPX, fByte, 55H); E(mDPIndX, fByte, 41H);
      E(mDPIndY, fByte, 51H);
    I(INC); E(mAcc, fImpl, 1AH); E(mImpl, fImpl, 1AH); E(mAbs, fWord, 0EEH); E(mDP, fByte, 0E6H);
      E(mAbsX, fWord, 0FEH); E(mDPX, fByte, 0F6H);
    I(INX); E(mImpl, fImpl, 0E8H);
    I(INY); E(mImpl, fImpl, 0C8H);
    I(JMP); E(mDP, fWord, 4CH); E(mAbs, fWord, 4CH); E(mAbsInd, fWord, 6CH);
      E(mAbsIndX, fWord, 7CH);
    I(JSR); E(mDP, fWord, 20H); E(mAbs, fWord, 20H);
    I(LDA); E(mImm, fByte, 0A9H); E(mAbs, fWord, 0ADH); E(mDP, fByte, 0A5H); E(mDPInd, fByte, 0B2H);
      E(mAbsX, fWord, 0BDH); E(mAbsY, fWord, 0B9H); E(mDPX, fByte, 0B5H); E(mDPIndX, fByte, 0A1H);
      E(mDPIndY, fByte, 0B1H);
    I(LDX); E(mImm, fByte, 0A2H); E(mAbs, fWord, 0AEH); E(mDP, fByte, 0A6H); E(mAbsY, fWord, 0BEH);
      E(mDPY, fByte, 0B6H);
    I(LDY); E(mImm, fByte, 0A0H); E(mAbs, fWord, 0ACH); E(mDP, fByte, 0A4H); E(mAbsX, fWord, 0BCH);
      E(mDPX, fByte, 0B4H);
    I(LSR); E(mAcc, fImpl, 4AH); E(mImpl, fImpl, 4AH); E(mAbs, fWord, 4EH); E(mDP, fByte, 46H);
      E(mAbsX, fWord, 5EH); E(mDPX, fByte, 56H);
    I(NOP); E(mImpl, fImpl, 0EAH);
    I(ORA); E(mImm, fByte, 09H); E(mAbs, fWord, 0DH); E(mDP, fByte, 05H); E(mDPInd, fByte, 12H);
      E(mAbsX, fWord, 1DH); E(mAbsY, fWord, 19H); E(mDPX, fByte, 15H); E(mDPIndX, fByte, 01H);
      E(mDPIndY, fByte, 11H);
    I(PHA); E(mImpl, fImpl, 48H);
    I(PHP); E(mImpl, fImpl, 08H);
    I(PHX); E(mImpl, fImpl, 0DAH);
    I(PHY); E(mImpl, fImpl, 5AH);
    I(PLA); E(mImpl, fImpl, 68H);
    I(PLP); E(mImpl, fImpl, 28H);
    I(PLX); E(mImpl, fImpl, 0FAH);
    I(PLY); E(mImpl, fImpl, 7AH);
    I(ROL); E(mAcc, fImpl, 2AH); E(mImpl, fImpl, 2AH); E(mAbs, fWord, 2EH); E(mDP, fByte, 26H);
      E(mAbsX, fWord, 3EH); E(mDPX, fByte, 36H);
    I(ROR); E(mAcc, fImpl, 6AH); E(mImpl, fImpl, 6AH); E(mAbs, fWord, 6EH); E(mDP, fByte, 66H);
      E(mAbsX, fWord, 7EH); E(mDPX, fByte, 76H);
    I(RTI); E(mImpl, fImpl, 40H);
    I(RTS); E(mImpl, fImpl, 60H);
    I(SBC); E(mImm, fByte, 0E9H); E(mAbs, fWord, 0EDH); E(mDP, fByte, 0E5H); E(mDPInd, fByte, 0F2H);
      E(mAbsX, fWord, 0FDH); E(mAbsY, fWord, 0F9H); E(mDPX, fByte, 0F5H); E(mDPIndX, fByte, 0E1H);
      E(mDPIndY, fByte, 0F1H);
    I(SEC); E(mImpl, fImpl, 38H);
    I(SED); E(mImpl, fImpl, 0F8H);
    I(SEI); E(mImpl, fImpl, 78H);
    I(STA); E(mAbs, fWord, 8DH); E(mDP, fByte, 85H); E(mDPInd, fByte, 92H); E(mAbsX, fWord, 9DH);
      E(mDPY, fWord, 99H); E(mAbsY, fWord, 99H); E(mDPX, fByte, 95H); E(mDPIndX, fByte, 81H);
      E(mDPIndY, fByte, 91H);
    I(STX); E(mAbs, fWord, 8EH); E(mDP, fByte, 86H); E(mDPY, fByte, 96H);
    I(STY); E(mAbs, fWord, 8CH); E(mDP, fByte, 84H); E(mDPX, fByte, 94H);
    I(STZ); E(mAbs, fWord, 9CH); E(mDP, fByte, 64H); E(mAbsX, fWord, 9EH); E(mDPX, fByte, 74H);
    I(TAX); E(mImpl, fImpl, 0AAH);
    I(TAY); E(mImpl, fImpl, 0A8H);
    I(TRB); E(mAbs, fWord, 1CH); E(mDP, fByte, 14H);
    I(TSB); E(mAbs, fWord, 0CH); E(mDP, fByte, 04H);
    I(TSX); E(mImpl, fImpl, 0BAH);
    I(TXA); E(mImpl, fImpl, 8AH);
    I(TXS); E(mImpl, fImpl, 9AH);
    I(TYA); E(mImpl, fImpl, 98H)
  END Enter65C02;

  PROCEDURE EnterR65C02;
  BEGIN
    I(ADC); E(mImm, fByte, 69H); E(mAbs, fWord, 6DH); E(mDP, fByte, 65H); E(mDPIndX, fByte, 61H);
      E(mDPIndY, fByte, 71H); E(mDPX, fByte, 75H); E(mAbsX, fWord, 7DH); E(mAbsY, fWord, 79H);
      E(mDPInd, fByte, 72H);
    I(AND); E(mImm, fByte, 29H); E(mAbs, fWord, 2DH); E(mDP, fByte, 25H); E(mDPIndX, fByte, 21H);
      E(mDPIndY, fByte, 31H); E(mDPX, fByte, 35H); E(mAbsX, fWord, 3DH); E(mAbsY, fWord, 39H);
      E(mDPInd, fByte, 32H);
    I(ASL); E(mAbs, fWord, 0EH); E(mDP, fByte, 06H); E(mImpl, fImpl, 0AH); E(mAcc, fImpl, 0AH);
      E(mDPX, fByte, 16H); E(mAbsX, fWord, 1EH);
    I(BBR); E(mTriple, fBitZR, 0FH);
    I(BBS); E(mTriple, fBitZR, 8FH);
    I(BCC); E(mDP, fRel, 90H); E(mAbs, fRel, 90H);
    I(BCS); E(mDP, fRel, 0B0H); E(mAbs, fRel, 0B0H);
    I(BEQ); E(mDP, fRel, 0F0H); E(mAbs, fRel, 0F0H);
    I(BIT); E(mImm, fByte, 89H); E(mDP, fByte, 24H); E(mAbs, fWord, 2CH);
    I(BMI); E(mDP, fRel, 30H); E(mAbs, fRel, 30H);
    I(BNE); E(mDP, fRel, 0D0H); E(mAbs, fRel, 0D0H);
    I(BPL); E(mDP, fRel, 10H); E(mAbs, fRel, 10H);
    I(BRA); E(mDP, fRel, 80H); E(mAbs, fRel, 80H);
    I(BRK); E(mImpl, fImpl, 00H); E(mImm, fByte, 00H);
    I(BVC); E(mDP, fRel, 50H); E(mAbs, fRel, 50H);
    I(BVS); E(mDP, fRel, 70H); E(mAbs, fRel, 70H);
    I(CLC); E(mImpl, fImpl, 18H);
    I(CLD); E(mImpl, fImpl, 0D8H);
    I(CLI); E(mImpl, fImpl, 58H);
    I(CLV); E(mImpl, fImpl, 0B8H);
    I(CMP); E(mImm, fByte, 0C9H); E(mAbs, fWord, 0CDH); E(mDP, fByte, 0C5H);
      E(mDPIndX, fByte, 0C1H); E(mDPIndY, fByte, 0D1H); E(mDPX, fByte, 0D5H); E(mAbsX, fWord, 0DDH);
      E(mAbsY, fWord, 0D9H); E(mAbsInd, fByte, 0D2H);
    I(CPX); E(mImm, fByte, 0E0H); E(mAbs, fWord, 0ECH); E(mDP, fByte, 0E4H);
    I(CPY); E(mImm, fByte, 0C0H); E(mAbs, fWord, 0CCH); E(mDP, fByte, 0C4H);
    I(DEC); E(mAbs, fWord, 0CEH); E(mDP, fByte, 0C6H); E(mImpl, fImpl, 3AH); E(mAcc, fImpl, 3AH);
      E(mDPX, fByte, 0D6H); E(mAbsX, fWord, 0DEH);
    I(DEX); E(mImpl, fImpl, 0CAH);
    I(DEY); E(mImpl, fImpl, 88H);
    I(EOR); E(mImm, fByte, 49H); E(mAbs, fWord, 4DH); E(mDP, fByte, 45H); E(mDPInd, fByte, 41H);
      E(mDPIndY, fByte, 51H); E(mDPX, fByte, 55H); E(mAbsX, fWord, 5DH); E(mAbsY, fWord, 59H);
    I(INC); E(mAbs, fWord, 0EEH); E(mDP, fByte, 0E6H); E(mImpl, fImpl, 1AH); E(mAcc, fImpl, 1AH);
      E(mDPX, fByte, 0F6H); E(mAbsX, fWord, 0FEH);
    I(INX); E(mImpl, fImpl, 0E8H);
    I(INY); E(mImpl, fImpl, 0C8H);
    I(JMP); E(mDP, fWord, 4CH); E(mAbs, fWord, 4CH); E(mAbsInd, fWord, 6CH);
      E(mAbsIndX, fWord, 7CH);
    I(JSR); E(mDP, fWord, 20H); E(mAbs, fWord, 20H);
    I(LDA); E(mImm, fByte, 0A9H); E(mAbs, fWord, 0ADH); E(mDP, fByte, 0A5H);
      E(mDPIndX, fByte, 0A1H); E(mDPIndY, fByte, 0B1H); E(mDPX, fByte, 0B5H); E(mAbsX, fWord, 0BDH);
      E(mAbsY, fWord, 0B9H); E(mDPInd, fByte, 0B2H);
    I(LDX); E(mImm, fByte, 0A2H); E(mAbs, fWord, 0AEH); E(mDP, fByte, 0A6H); E(mAbsY, fWord, 0BEH);
      E(mDPY, fByte, 0B6H);
    I(LDY); E(mImm, fByte, 0A0H); E(mAbs, fWord, 0ACH); E(mDP, fByte, 0A4H); E(mDPX, fByte, 0B4H);
      E(mAbsX, fWord, 0BCH);
    I(LSR); E(mAbs, fWord, 4EH); E(mDP, fByte, 46H); E(mImpl, fImpl, 4AH); E(mAcc, fImpl, 4AH);
      E(mDPX, fByte, 56H); E(mAbsX, fWord, 5EH);
    I(NOP); E(mImpl, fImpl, 0EAH);
    I(ORA); E(mImm, fByte, 09H); E(mAbs, fWord, 0DH); E(mDP, fByte, 05H); E(mDPInd, fByte, 01H);
      E(mDPIndX, fByte, 11H); E(mDPX, fByte, 15H); E(mAbsX, fWord, 1DH); E(mAbsY, fWord, 19H);
      E(mAbsInd, fWord, 12H);
    I(PHA); E(mImpl, fImpl, 48H);
    I(PHP); E(mImpl, fImpl, 08H);
    I(PHX); E(mImpl, fImpl, 0DAH);
    I(PHY); E(mImpl, fImpl, 5AH);
    I(PLA); E(mImpl, fImpl, 68H);
    I(PLP); E(mImpl, fImpl, 28H);
    I(PLX); E(mImpl, fImpl, 0FAH);
    I(PLY); E(mImpl, fImpl, 7AH);
    I(RMB); E(mPair, fBitZ, 07H);
    I(ROL); E(mAbs, fWord, 2EH); E(mDP, fByte, 26H); E(mImpl, fImpl, 2AH); E(mAcc, fImpl, 2AH);
      E(mDPX, fByte, 36H); E(mAbsX, fWord, 3EH);
    I(ROR); E(mAbs, fWord, 6EH); E(mDP, fByte, 66H); E(mImpl, fImpl, 6AH); E(mAcc, fImpl, 6AH);
      E(mDPX, fByte, 76H); E(mAbsX, fWord, 7EH);
    I(RTI); E(mImpl, fImpl, 40H);
    I(RTS); E(mImpl, fImpl, 60H);
    I(SBC); E(mImm, fByte, 0E9H); E(mAbs, fWord, 0EDH); E(mDP, fByte, 0E5H); E(mDPInd, fByte, 0E1H);
      E(mDPIndX, fByte, 0F1H); E(mDPX, fByte, 0F5H); E(mAbsX, fWord, 0FDH); E(mAbsY, fWord, 0F9H);
      E(mAbsInd, fWord, 0F2H);
    I(SEC); E(mImpl, fImpl, 38H);
    I(SED); E(mImpl, fImpl, 0F8H);
    I(SEI); E(mImpl, fImpl, 78H);
    I(SMB); E(mPair, fBitZ, 87H);
    I(STA); E(mAbs, fWord, 8DH); E(mDP, fByte, 85H); E(mDPIndX, fByte, 81H); E(mDPIndY, fByte, 91H);
      E(mDPX, fByte, 95H); E(mAbsX, fWord, 9DH); E(mDPY, fWord, 99H); E(mAbsY, fWord, 99H);
      E(mAbsInd, fWord, 92H);
    I(STX); E(mAbs, fWord, 8EH); E(mDP, fByte, 86H); E(mDPY, fByte, 96H);
    I(STY); E(mAbs, fWord, 8CH); E(mDP, fByte, 84H); E(mDPX, fByte, 94H);
    I(STZ); E(mAbs, fWord, 9CH); E(mDP, fByte, 64H); E(mDPX, fByte, 74H); E(mAbsX, fWord, 9EH);
    I(TAX); E(mImpl, fImpl, 0AAH);
    I(TAY); E(mImpl, fImpl, 0A8H);
    I(TSX); E(mImpl, fImpl, 0BAH);
    I(TXA); E(mImpl, fImpl, 8AH);
    I(TXS); E(mImpl, fImpl, 9AH);
    I(TYA); E(mImpl, fImpl, 98H)
  END EnterR65C02;

  PROCEDURE Enter65C816;
  BEGIN
    I(ADC); E(mImm, fImmA, 69H); E(mAbs, fWord, 6DH); E(mAbsL, fLong, 6FH); E(mDP, fByte, 65H);
      E(mDPInd, fByte, 72H); E(mDPIndL, fByte, 67H); E(mAbsX, fWord, 7DH); E(mAbsLX, fLong, 7FH);
      E(mAbsY, fWord, 79H); E(mDPX, fByte, 75H); E(mDPIndX, fByte, 61H); E(mDPIndY, fByte, 71H);
      E(mDPIndLY, fByte, 77H); E(mSR, fByte, 63H); E(mSRIY, fByte, 73H);
    I(AND); E(mImm, fImmA, 29H); E(mAbs, fWord, 2DH); E(mAbsL, fLong, 2FH); E(mDP, fByte, 25H);
      E(mDPInd, fByte, 32H); E(mDPIndL, fByte, 27H); E(mAbsX, fWord, 3DH); E(mAbsLX, fLong, 3FH);
      E(mAbsY, fWord, 39H); E(mDPX, fByte, 35H); E(mDPIndX, fByte, 21H); E(mDPIndY, fByte, 31H);
      E(mDPIndLY, fByte, 37H); E(mSR, fByte, 23H); E(mSRIY, fByte, 33H);
    I(ASL); E(mImpl, fImpl, 0AH); E(mAcc, fImpl, 0AH); E(mAbs, fWord, 0EH); E(mDP, fByte, 06H);
      E(mAbsX, fWord, 1EH); E(mDPX, fByte, 16H);
    I(BCC); E(mDP, fRel, 90H); E(mAbs, fRel, 90H);
    I(BCS); E(mDP, fRel, 0B0H); E(mAbs, fRel, 0B0H);
    I(BEQ); E(mDP, fRel, 0F0H); E(mAbs, fRel, 0F0H);
    I(BIT); E(mImm, fImmA, 89H); E(mAbs, fWord, 2CH); E(mDP, fByte, 24H); E(mAbsX, fWord, 3CH);
      E(mDPX, fByte, 34H);
    I(BMI); E(mDP, fRel, 30H); E(mAbs, fRel, 30H);
    I(BNE); E(mDP, fRel, 0D0H); E(mAbs, fRel, 0D0H);
    I(BPL); E(mDP, fRel, 10H); E(mAbs, fRel, 10H);
    I(BRA); E(mDP, fBra, 80H); E(mAbs, fBra, 80H);
    I(BRK); E(mImpl, fImpl, 00H); E(mImm, fByte, 00H);
    I(BRL); E(mDP, fBrl, 82H); E(mAbs, fBrl, 82H);
    I(BVC); E(mDP, fRel, 50H); E(mAbs, fRel, 50H);
    I(BVS); E(mDP, fRel, 70H); E(mAbs, fRel, 70H);
    I(CLC); E(mImpl, fImpl, 18H);
    I(CLD); E(mImpl, fImpl, 0D8H);
    I(CLI); E(mImpl, fImpl, 58H);
    I(CLV); E(mImpl, fImpl, 0B8H);
    I(CMP); E(mImm, fImmA, 0C9H); E(mAbs, fWord, 0CDH); E(mAbsL, fLong, 0CFH); E(mDP, fByte, 0C5H);
      E(mDPInd, fByte, 0D2H); E(mDPIndL, fByte, 0C7H); E(mAbsX, fWord, 0DDH);
      E(mAbsLX, fLong, 0DFH); E(mAbsY, fWord, 0D9H); E(mDPX, fByte, 0D5H); E(mDPIndX, fByte, 0C1H);
      E(mDPIndY, fByte, 0D1H); E(mDPIndLY, fByte, 0D7H); E(mSR, fByte, 0C3H); E(mSRIY, fByte, 0D3H);
    I(COP); E(mImm, fByte, 02H);
    I(CPX); E(mImm, fImmX, 0E0H); E(mAbs, fWord, 0ECH); E(mDP, fByte, 0E4H);
    I(CPY); E(mImm, fImmX, 0C0H); E(mAbs, fWord, 0CCH); E(mDP, fByte, 0C4H);
    I(DEC); E(mAcc, fImpl, 3AH); E(mImpl, fImpl, 3AH); E(mAbs, fWord, 0CEH); E(mDP, fByte, 0C6H);
      E(mAbsX, fWord, 0DEH); E(mDPX, fByte, 0D6H);
    I(DEX); E(mImpl, fImpl, 0CAH);
    I(DEY); E(mImpl, fImpl, 88H);
    I(EOR); E(mImm, fImmA, 49H); E(mAbs, fWord, 4DH); E(mAbsL, fLong, 4FH); E(mDP, fByte, 45H);
      E(mDPInd, fByte, 52H); E(mDPIndL, fByte, 47H); E(mAbsX, fWord, 5DH); E(mAbsLX, fLong, 5FH);
      E(mAbsY, fWord, 59H); E(mDPX, fByte, 55H); E(mDPIndX, fByte, 41H); E(mDPIndY, fByte, 51H);
      E(mDPIndLY, fByte, 57H); E(mSR, fByte, 43H); E(mSRIY, fByte, 53H);
    I(INC); E(mAcc, fImpl, 1AH); E(mImpl, fImpl, 1AH); E(mAbs, fWord, 0EEH); E(mDP, fByte, 0E6H);
      E(mAbsX, fWord, 0FEH); E(mDPX, fByte, 0F6H);
    I(INX); E(mImpl, fImpl, 0E8H);
    I(INY); E(mImpl, fImpl, 0C8H);
    I(JML); E(mDP, fLong, 5CH); E(mAbs, fLong, 5CH); E(mAbsL, fLong, 5CH); E(mAbsInd, fWord, 0DCH);
      E(mAbsIndL, fWord, 0DCH);
    I(JMP); E(mDP, fWord, 4CH); E(mAbs, fWord, 4CH); E(mAbsInd, fWord, 6CH);
      E(mAbsIndX, fWord, 7CH); E(mAbsL, fLong, 5CH); E(mAbsIndL, fWord, 0DCH);
    I(JSL); E(mDP, fLongR, 22H); E(mAbs, fLongR, 22H); E(mAbsL, fLongR, 22H);
    I(JSR); E(mDP, fWordR, 20H); E(mAbs, fWordR, 20H); E(mAbsIndX, fWord, 0FCH);
      E(mAbsL, fLongR, 22H);
    I(LDA); E(mImm, fImmA, 0A9H); E(mAbs, fWord, 0ADH); E(mAbsL, fLong, 0AFH); E(mDP, fByte, 0A5H);
      E(mDPInd, fByte, 0B2H); E(mDPIndL, fByte, 0A7H); E(mAbsX, fWord, 0BDH);
      E(mAbsLX, fLong, 0BFH); E(mAbsY, fWord, 0B9H); E(mDPX, fByte, 0B5H); E(mDPIndX, fByte, 0A1H);
      E(mDPIndY, fByte, 0B1H); E(mDPIndLY, fByte, 0B7H); E(mSR, fByte, 0A3H); E(mSRIY, fByte, 0B3H);
    I(LDX); E(mImm, fImmX, 0A2H); E(mAbs, fWord, 0AEH); E(mDP, fByte, 0A6H); E(mAbsY, fWord, 0BEH);
      E(mDPY, fByte, 0B6H);
    I(LDY); E(mImm, fImmX, 0A0H); E(mAbs, fWord, 0ACH); E(mDP, fByte, 0A4H); E(mAbsX, fWord, 0BCH);
      E(mDPX, fByte, 0B4H);
    I(LSR); E(mAcc, fImpl, 4AH); E(mImpl, fImpl, 4AH); E(mAbs, fWord, 4EH); E(mDP, fByte, 46H);
      E(mAbsX, fWord, 5EH); E(mDPX, fByte, 56H);
    I(MVN); E(mPair, fMove, 54H);
    I(MVP); E(mPair, fMove, 44H);
    I(NOP); E(mImpl, fImpl, 0EAH);
    I(ORA); E(mImm, fImmA, 09H); E(mAbs, fWord, 0DH); E(mAbsL, fLong, 0FH); E(mDP, fByte, 05H);
      E(mDPInd, fByte, 12H); E(mDPIndL, fByte, 07H); E(mAbsX, fWord, 1DH); E(mAbsLX, fLong, 1FH);
      E(mAbsY, fWord, 19H); E(mDPX, fByte, 15H); E(mDPIndX, fByte, 01H); E(mDPIndY, fByte, 11H);
      E(mDPIndLY, fByte, 17H); E(mSR, fByte, 03H); E(mSRIY, fByte, 13H);
    I(PEA); E(mImm, fWord, 0F4H); E(mAbs, fWord, 0F4H);
    I(PEI); E(mDPInd, fByte, 0D4H);
    I(PER); E(mImm, fRelL, 62H); E(mDP, fRelL, 62H); E(mAbs, fRelL, 62H);
    I(PHA); E(mImpl, fImpl, 48H);
    I(PHB); E(mImpl, fImpl, 8BH);
    I(PHD); E(mImpl, fImpl, 0BH);
    I(PHK); E(mImpl, fImpl, 4BH);
    I(PHP); E(mImpl, fImpl, 08H);
    I(PHX); E(mImpl, fImpl, 0DAH);
    I(PHY); E(mImpl, fImpl, 5AH);
    I(PLA); E(mImpl, fImpl, 68H);
    I(PLB); E(mImpl, fImpl, 0ABH);
    I(PLD); E(mImpl, fImpl, 2BH);
    I(PLP); E(mImpl, fImpl, 28H);
    I(PLX); E(mImpl, fImpl, 0FAH);
    I(PLY); E(mImpl, fImpl, 7AH);
    I(REP); E(mImm, fByte, 0C2H);
    I(ROL); E(mAcc, fImpl, 2AH); E(mImpl, fImpl, 2AH); E(mAbs, fWord, 2EH); E(mDP, fByte, 26H);
      E(mAbsX, fWord, 3EH); E(mDPX, fByte, 36H);
    I(ROR); E(mAcc, fImpl, 6AH); E(mImpl, fImpl, 6AH); E(mAbs, fWord, 6EH); E(mDP, fByte, 66H);
      E(mAbsX, fWord, 7EH); E(mDPX, fByte, 76H);
    I(RTI); E(mImpl, fImpl, 40H);
    I(RTL); E(mImpl, fImpl, 6BH);
    I(RTS); E(mImpl, fImpl, 60H);
    I(SBC); E(mImm, fImmA, 0E9H); E(mAbs, fWord, 0EDH); E(mAbsL, fLong, 0EFH); E(mDP, fByte, 0E5H);
      E(mDPInd, fByte, 0F2H); E(mDPIndL, fByte, 0E7H); E(mAbsX, fWord, 0FDH);
      E(mAbsLX, fLong, 0FFH); E(mAbsY, fWord, 0F9H); E(mDPX, fByte, 0F5H); E(mDPIndX, fByte, 0E1H);
      E(mDPIndY, fByte, 0F1H); E(mDPIndLY, fByte, 0F7H); E(mSR, fByte, 0E3H); E(mSRIY, fByte, 0F3H);
    I(SEC); E(mImpl, fImpl, 38H);
    I(SED); E(mImpl, fImpl, 0F8H);
    I(SEI); E(mImpl, fImpl, 78H);
    I(SEP); E(mImm, fByte, 0E2H);
    I(STA); E(mAbs, fWord, 8DH); E(mAbsL, fLong, 8FH); E(mDP, fByte, 85H); E(mDPInd, fByte, 92H);
      E(mDPIndL, fByte, 87H); E(mAbsX, fWord, 9DH); E(mAbsLX, fLong, 9FH); E(mDPY, fWord, 99H);
      E(mAbsY, fWord, 99H); E(mDPX, fByte, 95H); E(mDPIndX, fByte, 81H); E(mDPIndY, fByte, 91H);
      E(mDPIndLY, fByte, 97H); E(mSR, fByte, 83H); E(mSRIY, fByte, 93H);
    I(STP); E(mImpl, fImpl, 0DBH);
    I(STX); E(mAbs, fWord, 8EH); E(mDP, fByte, 86H); E(mDPY, fByte, 96H);
    I(STY); E(mAbs, fWord, 8CH); E(mDP, fByte, 84H); E(mDPX, fByte, 94H);
    I(STZ); E(mAbs, fWord, 9CH); E(mDP, fByte, 64H); E(mAbsX, fWord, 9EH); E(mDPX, fByte, 74H);
    I(SWA); E(mImpl, fImpl, 0EBH);
    I(TAD); E(mImpl, fImpl, 5BH);
    I(TAS); E(mImpl, fImpl, 1BH);
    I(TAX); E(mImpl, fImpl, 0AAH);
    I(TAY); E(mImpl, fImpl, 0A8H);
    I(TCD); E(mImpl, fImpl, 5BH);
    I(TCS); E(mImpl, fImpl, 1BH);
    I(TDA); E(mImpl, fImpl, 7BH);
    I(TDC); E(mImpl, fImpl, 7BH);
    I(TRB); E(mAbs, fWord, 1CH); E(mDP, fByte, 14H);
    I(TSA); E(mImpl, fImpl, 3BH);
    I(TSB); E(mAbs, fWord, 0CH); E(mDP, fByte, 04H);
    I(TSC); E(mImpl, fImpl, 3BH);
    I(TSX); E(mImpl, fImpl, 0BAH);
    I(TXA); E(mImpl, fImpl, 8AH);
    I(TXS); E(mImpl, fImpl, 9AH);
    I(TXY); E(mImpl, fImpl, 9BH);
    I(TYA); E(mImpl, fImpl, 98H);
    I(TYX); E(mImpl, fImpl, 0BBH);
    I(WAI); E(mImpl, fImpl, 0CBH);
    I(WDM); E(mImm, fByte, 42H);
    I(XBA); E(mImpl, fImpl, 0EBH);
    I(XCE); E(mImpl, fImpl, 0FBH)
  END Enter65C816;

  PROCEDURE EnterC19;
  BEGIN
    I(ADC); E(mImm, fByte, 69H); E(mDP, fByte, 65H); E(mDPX, fByte, 75H); E(mAbs, fWord, 6DH);
      E(mAbsX, fWord, 7DH); E(mAbsY, fWord, 79H); E(mDPInd, fByte, 61H); E(mDPIndX, fByte, 71H);
    I(ADD); E(mImm, fByte, 89H); E(mDP, fByte, 64H); E(mDPX, fByte, 74H);
    I(AND); E(mImm, fByte, 29H); E(mDP, fByte, 25H); E(mDPX, fByte, 35H); E(mAbs, fWord, 2DH);
      E(mAbsX, fWord, 3DH); E(mAbsY, fWord, 39H); E(mDPInd, fByte, 21H); E(mDPIndX, fByte, 31H);
    I(ASL); E(mAcc, fImpl, 0AH); E(mImpl, fImpl, 0AH); E(mDP, fByte, 06H); E(mDPX, fByte, 16H);
      E(mAbs, fWord, 0EH); E(mAbsX, fWord, 1EH);
    I(ASR); E(mImpl, fImpl, 3AH); E(mAcc, fImpl, 3AH);
    I(BAR); E(mTriple, fBitAR, 0E2H);
    I(BAS); E(mTriple, fBitAR, 0F2H);
    I(BBR); E(mTriple, fBitZR, 0FH);
    I(BBS); E(mTriple, fBitZR, 8FH);
    I(BCC); E(mDP, fRel, 90H); E(mAbs, fRel, 90H);
    I(BCS); E(mDP, fRel, 0B0H); E(mAbs, fRel, 0B0H);
    I(BEQ); E(mAbs, fRel, 0F0H); E(mDP, fRel, 0F0H);
    I(BIT); E(mDP, fByte, 24H); E(mAbs, fWord, 2CH);
    I(BMI); E(mDP, fRel, 30H); E(mAbs, fRel, 30H);
    I(BNE); E(mDP, fRel, 0D0H); E(mAbs, fRel, 0D0H);
    I(BPL); E(mDP, fRel, 10H); E(mAbs, fRel, 10H);
    I(BRA); E(mDP, fRel, 80H); E(mAbs, fRel, 80H);
    I(BRK); E(mImpl, fImpl, 00H); E(mImm, fByte, 00H);
    I(BVC); E(mDP, fRel, 50H); E(mAbs, fRel, 50H);
    I(BVS); E(mDP, fRel, 70H); E(mAbs, fRel, 70H);
    I(CLC); E(mImpl, fImpl, 18H);
    I(CLD); E(mImpl, fImpl, 0D8H);
    I(CLI); E(mImpl, fImpl, 58H);
    I(CLV); E(mImpl, fImpl, 0B8H);
    I(CLW); E(mImpl, fImpl, 52H);
    I(CMP); E(mImm, fByte, 0C9H); E(mDP, fByte, 0C5H); E(mDPX, fByte, 0D5H); E(mAbs, fWord, 0CDH);
      E(mAbsX, fWord, 0DDH); E(mAbsY, fWord, 0D9H); E(mDPInd, fByte, 0C1H); E(mDPIndX, fByte, 0D1H);
    I(CPX); E(mImm, fByte, 0E0H); E(mDP, fByte, 0E4H); E(mAbs, fWord, 0ECH);
    I(CPY); E(mImm, fByte, 0C0H); E(mDP, fByte, 0C4H); E(mAbs, fWord, 0CCH);
    I(DEC); E(mDP, fByte, 0C6H); E(mDPX, fByte, 0D6H); E(mAbs, fWord, 0CEH); E(mAbsX, fWord, 0DEH);
    I(DEX); E(mImpl, fImpl, 0CAH);
    I(DEY); E(mImpl, fImpl, 88H);
    I(EOR); E(mImm, fByte, 49H); E(mDP, fByte, 45H); E(mDPX, fByte, 55H); E(mAbs, fWord, 4DH);
      E(mAbsX, fWord, 5DH); E(mAbsY, fWord, 59H); E(mDPInd, fByte, 41H); E(mDPIndX, fByte, 51H);
    I(EXC); E(mDPX, fByte, 0D4H);
    I(INC); E(mDP, fByte, 0E6H); E(mDPX, fByte, 0F6H); E(mAbs, fWord, 0EEH); E(mAbsX, fWord, 0FEH);
    I(INI); E(mImpl, fImpl, 0BBH);
    I(INX); E(mImpl, fImpl, 0E8H);
    I(INY); E(mImpl, fImpl, 0C8H);
    I(JMP); E(mDP, fWord, 4CH); E(mAbs, fWord, 4CH); E(mAbsInd, fWord, 6CH);
      E(mAbsIndX, fWord, 7CH);
    I(JPI); E(mAbsInd, fWord, 0CH);
    I(JSB); E(mImm, fJsb, 0BH); E(mDP, fJsb, 0BH);
    I(JSR); E(mDP, fWord, 20H); E(mAbs, fWord, 20H);
    I(LAB); E(mImpl, fImpl, 13H); E(mAcc, fImpl, 13H);
    I(LAI); E(mImpl, fImpl, 0EBH);
    I(LAN); E(mImpl, fImpl, 0ABH);
    I(LDA); E(mImm, fByte, 0A9H); E(mDP, fByte, 0A5H); E(mDPX, fByte, 0B5H); E(mAbs, fWord, 0ADH);
      E(mAbsX, fWord, 0BDH); E(mAbsY, fWord, 0B9H); E(mDPInd, fByte, 0A1H); E(mDPIndX, fByte, 0B1H);
    I(LDX); E(mImm, fByte, 0A2H); E(mDP, fByte, 0A6H); E(mDPY, fByte, 0B6H); E(mAbs, fWord, 0AEH);
      E(mAbsY, fWord, 0BEH);
    I(LDY); E(mImm, fByte, 0A0H); E(mDP, fByte, 0A4H); E(mDPX, fByte, 0B4H); E(mAbs, fWord, 0ACH);
      E(mAbsX, fWord, 0BCH);
    I(LII); E(mImpl, fImpl, 9BH);
    I(LSR); E(mImpl, fImpl, 4AH); E(mAcc, fImpl, 4AH); E(mDP, fByte, 46H); E(mDPX, fByte, 56H);
      E(mAbs, fWord, 4EH); E(mAbsX, fWord, 5EH);
    I(MPA); E(mImpl, fImpl, 12H);
    I(MPY); E(mImpl, fImpl, 02H);
    I(NEG); E(mImpl, fImpl, 1AH); E(mAcc, fImpl, 1AH);
    I(NOP); E(mImpl, fImpl, 0EAH);
    I(NXT); E(mImpl, fImpl, 8BH);
    I(ORA); E(mImm, fByte, 09H); E(mDP, fByte, 05H); E(mDPX, fByte, 15H); E(mAbs, fWord, 0DH);
      E(mAbsX, fWord, 1DH); E(mAbsY, fWord, 19H); E(mDPInd, fByte, 01H); E(mDPIndX, fByte, 11H);
    I(PHA); E(mImpl, fImpl, 48H);
    I(PHI); E(mImpl, fImpl, 0CBH);
    I(PHP); E(mImpl, fImpl, 08H);
    I(PHW); E(mImpl, fImpl, 23H);
    I(PHX); E(mImpl, fImpl, 0DAH);
    I(PHY); E(mImpl, fImpl, 5AH);
    I(PIA); E(mImpl, fImpl, 0FBH);
    I(PLA); E(mImpl, fImpl, 68H);
    I(PLI); E(mImpl, fImpl, 0DBH);
    I(PLP); E(mImpl, fImpl, 28H);
    I(PLW); E(mImpl, fImpl, 33H);
    I(PLX); E(mImpl, fImpl, 0FAH);
    I(PLY); E(mImpl, fImpl, 7AH);
    I(PSH); E(mImpl, fImpl, 22H);
    I(PUL); E(mImpl, fImpl, 32H);
    I(RBA); E(mPair, fBitA, 0C2H);
    I(RMB); E(mPair, fBitZ, 07H);
    I(RND); E(mImpl, fImpl, 42H);
    I(ROL); E(mImpl, fImpl, 2AH); E(mAcc, fImpl, 2AH); E(mDP, fByte, 26H); E(mDPX, fByte, 36H);
      E(mAbs, fWord, 2EH); E(mAbsX, fWord, 3EH);
    I(ROR); E(mImpl, fImpl, 6AH); E(mAcc, fImpl, 6AH); E(mDP, fByte, 66H); E(mDPX, fByte, 76H);
      E(mAbs, fWord, 6EH); E(mAbsX, fWord, 7EH);
    I(RTI); E(mImpl, fImpl, 40H);
    I(RTS); E(mImpl, fImpl, 60H);
    I(SBA); E(mPair, fBitA, 0D2H);
    I(SBC); E(mImm, fByte, 0E9H); E(mDP, fByte, 0E5H); E(mDPX, fByte, 0F5H); E(mAbs, fWord, 0EDH);
      E(mAbsX, fWord, 0FDH); E(mAbsY, fWord, 0F9H); E(mDPInd, fByte, 0E1H); E(mDPIndX, fByte, 0F1H);
    I(SEC); E(mImpl, fImpl, 38H);
    I(SED); E(mImpl, fImpl, 0F8H);
    I(SEI); E(mImpl, fImpl, 78H);
    I(SMB); E(mPair, fBitZ, 87H);
    I(STA); E(mDP, fByte, 85H); E(mDPX, fByte, 95H); E(mAbs, fWord, 8DH); E(mAbsX, fWord, 9DH);
      E(mDPY, fWord, 99H); E(mAbsY, fWord, 99H); E(mDPInd, fByte, 81H); E(mDPIndX, fByte, 91H);
    I(STI); E(mPair, fImmZ, 0B2H);
    I(STX); E(mDP, fByte, 86H); E(mDPY, fByte, 96H); E(mAbs, fWord, 8EH);
    I(STY); E(mDP, fByte, 84H); E(mDPX, fByte, 94H); E(mAbs, fWord, 8CH);
    I(TAW); E(mImpl, fImpl, 62H);
    I(TAX); E(mImpl, fImpl, 0AAH);
    I(TAY); E(mImpl, fImpl, 0A8H);
    I(TIP); E(mImpl, fImpl, 03H);
    I(TSX); E(mImpl, fImpl, 0BAH);
    I(TWA); E(mImpl, fImpl, 72H);
    I(TXA); E(mImpl, fImpl, 8AH);
    I(TXS); E(mImpl, fImpl, 9AH);
    I(TYA); E(mImpl, fImpl, 98H)
  END EnterC19;

  (* --- queries --- *)

  PROCEDURE Known*(c: INTEGER): BOOLEAN;
  BEGIN RETURN (c >= c65C816) & (c <= cR6501Q)
  END Known;

  (* Load the encoding table of processor c. *)
  PROCEDURE Select*(c: INTEGER);
  BEGIN
    IF c # cpu THEN
      cpu := c; nofEnt := 0; curOp := 0; first[0] := 0; first[1] := 0;
      IF c = c65C816 THEN Enter65C816
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

  (* Look up instruction op with addressing mode mode. *)
  PROCEDURE Find*(op, mode: INTEGER; VAR form, code: INTEGER): BOOLEAN;
    VAR i, n: INTEGER;
  BEGIN i := first[op]; n := first[op + 1];
    WHILE (i < n) & (tabMode[i] # mode) DO i := i + 1 END;
    IF i < n THEN form := tabForm[i]; code := tabCode[i] END;
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
    ELSE s := "none"
    END
  END CpuName;

  PROCEDURE N(op: INTEGER; name: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE (i < 3) & (name[i] # 0X) DO names[op][i] := name[i]; i := i + 1 END;
    names[op][i] := 0X
  END N;

BEGIN cpu := 0; nofEnt := 0; curOp := 0; overflow := FALSE;
  N(ADC, "adc"); N(ADD, "add"); N(AND, "and"); N(ASL, "asl"); N(ASR, "asr");
  N(BAR, "bar"); N(BAS, "bas"); N(BBR, "bbr"); N(BBS, "bbs"); N(BCC, "bcc");
  N(BCS, "bcs"); N(BEQ, "beq"); N(BGE, "bge"); N(BIT, "bit"); N(BMI, "bmi");
  N(BNE, "bne"); N(BPL, "bpl"); N(BRA, "bra"); N(BRK, "brk"); N(BRL, "brl");
  N(BVC, "bvc"); N(BVS, "bvs"); N(CLC, "clc"); N(CLD, "cld"); N(CLI, "cli");
  N(CLV, "clv"); N(CLW, "clw"); N(CMP, "cmp"); N(COP, "cop"); N(CPX, "cpx");
  N(CPY, "cpy"); N(DEC, "dec"); N(DEX, "dex"); N(DEY, "dey"); N(EOR, "eor");
  N(EXC, "exc"); N(INC, "inc"); N(INI, "ini"); N(INX, "inx"); N(INY, "iny");
  N(JML, "jml"); N(JMP, "jmp"); N(JPI, "jpi"); N(JSB, "jsb"); N(JSL, "jsl");
  N(JSR, "jsr"); N(LAB, "lab"); N(LAI, "lai"); N(LAN, "lan"); N(LDA, "lda");
  N(LDX, "ldx"); N(LDY, "ldy"); N(LII, "lii"); N(LSR, "lsr"); N(MPA, "mpa");
  N(MPY, "mpy"); N(MVN, "mvn"); N(MVP, "mvp"); N(NEG, "neg"); N(NOP, "nop");
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
  N(TXS, "txs"); N(TXY, "txy"); N(TYA, "tya"); N(TYX, "tyx"); N(WAI, "wai");
  N(WDM, "wdm"); N(XBA, "xba"); N(XCE, "xce")
END ASC.
