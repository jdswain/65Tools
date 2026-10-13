MODULE ASG; (* Code generator of the 65xx assembler.

   Port of shared/src/codegen.c and of the section handling of
   shared/src/elf_file.c. Owns the sections and their code, the location
   counter and the processor state that decides operand sizes; chooses
   the addressing mode of an instruction and emits it according to its
   format in the table of ASC.

   The interpreter (ASI) runs the program several times. Every pass
   regenerates the code from nothing, so the generator is told when a
   pass and when a section begins. *)

  IMPORT ASH, ASC, ASS;

  CONST
    (* operand size modifiers, written after a mnemonic or directive *)
    MNone* = 0;
    MByte* = 1;      (* .b *)
    MDirect* = 2;    (* .d *)
    MWord* = 3;      (* .w *)
    MAbs* = 4;       (* .a *)
    MLong* = 5;      (* .l *)
    MFloat* = 6;     (* .f *)
    MZero* = 7;      (* .0 *)
    MBit7* = 8;      (* .7 *)

    (* section types and flags; the values are those of ELF *)
    Progbits* = 1; Nobits* = 8;
    Write* = 1; Alloc* = 2; Exec* = 4; DPage* = 8; Stack* = 10H; TLS* = 400H;

    maxSections* = 32;
    maxReloc* = 1023;    (* the loaders accept fewer than 1024 *)
    BlockSize = 1024;

  TYPE
    (* Block and Op (in ASI) are exported in name only: the stage-0
       compiler cannot re-export a record with a field of a private
       recursive pointer type. *)
    Block* = POINTER TO BlockDesc;
    BlockDesc* = RECORD
      next: Block;
      d: ARRAY BlockSize OF BYTE
    END;

    (* A run of code at consecutive addresses. Setting the location
       counter starts a new one, so the formats that carry addresses
       know where each part of a section belongs. *)
    Extent* = POINTER TO ExtentDesc;
    ExtentDesc* = RECORD
      addr*, offset*: LONGINT;   (* address of the byte at offset *)
      next*: Extent
    END;

    Section* = POINTER TO SectionDesc;
    SectionDesc* = RECORD
      name*: ASS.Ident;
      no*: INTEGER;              (* 0, 1, ... in order of creation *)
      type*, flags*: INTEGER;
      org*: LONGINT;             (* address of its first byte *)
      size*: LONGINT;
      extents*: Extent;
      next*: Section;
      lastExt: Extent;
      first, last: Block;        (* the code, in blocks; last holds the end *)
      lastBase: LONGINT          (* offset of the first byte of last *)
    END;

  VAR
    sections*: Section;          (* all sections, in order of creation *)
    nofSections*: INTEGER;
    text*: Section;              (* the default code section *)
    entry*: LONGINT;             (* start address of the program *)
    defaultCpu*: INTEGER;        (* processor selected when a section begins *)
    machine*: INTEGER;           (* processor the program last selected *)
    reloc*: ARRAY maxReloc OF LONGINT;   (* offsets in text of relocatable calls *)
    nofReloc*: INTEGER;

    cur: Section;
    lastSect: Section;
    addr: LONGINT;               (* location counter *)
    longa, longi: BOOLEAN;       (* 16 bit accumulator / index registers *)
    dpage, dbreg, pbreg: LONGINT;
    final: BOOLEAN;              (* the last pass, in which errors are reported *)
    relocOverflow: BOOLEAN;

  (* --- sections --- *)

  PROCEDURE ThisSection*(name: ARRAY OF CHAR): Section;
    VAR s: Section;
  BEGIN s := sections;
    WHILE (s # NIL) & (s.name # name) DO s := s.next END;
    RETURN s
  END ThisSection;

  (* The section called name, created if there is none; NIL if there are
     too many sections. *)
  PROCEDURE NewSection*(name: ARRAY OF CHAR; type, flags: INTEGER): Section;
    VAR s: Section;
  BEGIN s := ThisSection(name);
    IF (s = NIL) & (nofSections < maxSections) THEN
      NEW(s); ASH.Copy(name, s.name); s.no := nofSections; s.type := type; s.flags := flags;
      s.org := 0; s.size := 0; s.next := NIL;
      IF lastSect = NIL THEN sections := s ELSE lastSect.next := s END;
      lastSect := s; INC(nofSections)
    END;
    RETURN s
  END NewSection;

  PROCEDURE IsCode*(s: Section): BOOLEAN;
  BEGIN RETURN (s.type = Progbits) & ODD(s.flags DIV Exec)
  END IsCode;

  (* The byte at offset off of section s. *)
  PROCEDURE Get*(s: Section; off: LONGINT): INTEGER;
    VAR b: Block; x: INTEGER;
  BEGIN x := 0;
    IF (s.type # Nobits) & (off >= 0) & (off < s.size) THEN
      IF off >= s.lastBase THEN b := s.last; off := off - s.lastBase
      ELSE b := s.first;
        WHILE off >= BlockSize DO b := b.next; off := off - BlockSize END
      END;
      x := b.d[off]
    END;
    RETURN x
  END Get;

  (* --- location counter and processor state --- *)

  PROCEDURE Here*(): LONGINT;
  BEGIN RETURN addr
  END Here;

  PROCEDURE Size*(): LONGINT;
  BEGIN RETURN cur.size
  END Size;

  PROCEDURE Current*(): Section;
  BEGIN RETURN cur
  END Current;

  (* Continue generating code at address a. *)
  PROCEDURE SetAddr*(a: LONGINT);
    VAR e: Extent;
  BEGIN
    IF (cur.lastExt # NIL) & (cur.lastExt.offset = cur.size) THEN
      cur.lastExt.addr := a  (*nothing generated at the old address*)
    ELSIF (a # addr) OR (cur.lastExt = NIL) THEN
      NEW(e); e.addr := a; e.offset := cur.size; e.next := NIL;
      IF cur.lastExt = NIL THEN cur.extents := e ELSE cur.lastExt.next := e END;
      cur.lastExt := e
    END;
    IF cur.size = 0 THEN cur.org := a END;
    addr := a
  END SetAddr;

  PROCEDURE LongA*(): BOOLEAN; BEGIN RETURN longa END LongA;
  PROCEDURE SetLongA*(b: BOOLEAN); BEGIN longa := b END SetLongA;
  PROCEDURE LongI*(): BOOLEAN; BEGIN RETURN longi END LongI;
  PROCEDURE SetLongI*(b: BOOLEAN); BEGIN longi := b END SetLongI;
  PROCEDURE DPageReg*(): LONGINT; BEGIN RETURN dpage END DPageReg;
  PROCEDURE SetDPageReg*(x: LONGINT); BEGIN dpage := x END SetDPageReg;
  PROCEDURE DBReg*(): LONGINT; BEGIN RETURN dbreg END DBReg;
  PROCEDURE SetDBReg*(x: LONGINT); BEGIN dbreg := x END SetDBReg;
  PROCEDURE PBReg*(): LONGINT; BEGIN RETURN pbreg END PBReg;
  PROCEDURE SetPBReg*(x: LONGINT); BEGIN pbreg := x END SetPBReg;
  PROCEDURE SetEntry*(x: LONGINT); BEGIN entry := x END SetEntry;
  PROCEDURE SetDefaultCpu*(c: INTEGER); BEGIN defaultCpu := c; machine := c END SetDefaultCpu;

  (* Assemble for processor c from here on. *)
  PROCEDURE SetCpu*(c: INTEGER);
  BEGIN ASC.Select(c); machine := c
  END SetCpu;

  PROCEDURE BeginPass*(isFinal: BOOLEAN);
  BEGIN final := isFinal; nofReloc := 0; relocOverflow := FALSE; entry := 0; machine := defaultCpu
  END BeginPass;

  (* Start generating section s from nothing. *)
  PROCEDURE BeginSection*(s: Section);
  BEGIN cur := s;
    s.size := 0; s.extents := NIL; s.lastExt := NIL; s.last := s.first; s.lastBase := 0;
    addr := 0; SetAddr(0);
    longa := FALSE; longi := FALSE; dpage := 0; dbreg := 0; pbreg := 0;
    ASC.Select(defaultCpu)
  END BeginSection;

  (* --- emission --- *)

  PROCEDURE o(b: LONGINT);
    VAR off: LONGINT; blk: Block;
  BEGIN
    IF cur.type # Nobits THEN
      off := cur.size - cur.lastBase;
      IF cur.last = NIL THEN NEW(blk); blk.next := NIL; cur.first := blk; cur.last := blk
      ELSIF off = BlockSize THEN
        IF cur.last.next = NIL THEN NEW(blk); blk.next := NIL; cur.last.next := blk END;
        cur.last := cur.last.next; cur.lastBase := cur.size; off := 0
      END;
      cur.last.d[off] := b MOD 100H
    END;
    INC(cur.size); INC(addr)
  END o;

  PROCEDURE Byte*(b: LONGINT);
  BEGIN o(b)
  END Byte;

  PROCEDURE Word*(w: LONGINT);
  BEGIN o(w); o(w DIV 100H)
  END Word;

  PROCEDURE Long*(l: LONGINT);
  BEGIN o(l); o(l DIV 100H); o(l DIV 10000H); o(l DIV 1000000H)
  END Long;

  (* Note a call at the location counter for the loader to relocate. *)
  PROCEDURE AddReloc;
  BEGIN
    IF cur = text THEN
      IF nofReloc < maxReloc THEN reloc[nofReloc] := addr - cur.org; INC(nofReloc)
      ELSE relocOverflow := TRUE
      END
    END
  END AddReloc;

  PROCEDURE RelocOverflow*(): BOOLEAN;
  BEGIN RETURN relocOverflow
  END RelocOverflow;

  (* --- instructions --- *)

  PROCEDURE InstrError(src: ASS.Source; line, op, mode: INTEGER);
    VAR m: ASC.Mnemonic; s, t: ARRAY 48 OF CHAR;
  BEGIN
    ASC.Name(op, m); ASH.Copy(m, s);
    ASC.ModeName(mode, t);
    IF t[0] # 0X THEN ASH.Append(" ", s); ASH.Append(t, s) ELSE ASH.Append(" without operand", s) END;
    ASH.Append(" is not supported by the ", s);
    ASC.CpuName(ASC.Cpu(), t);
    ASS.Error(src, line, s, t)
  END InstrError;

  (* The 8 bit branch offset to target, emitted at the location counter. *)
  PROCEDURE Rel8(target: LONGINT; src: ASS.Source; line: INTEGER);
    VAR r: LONGINT;
  BEGIN r := target - (addr + 1);
    IF final & ((r > 127) OR (r < -128)) THEN ASS.Error(src, line, "branch out of range", "") END;
    o(r)
  END Rel8;

  PROCEDURE Rel16(target: LONGINT; src: ASS.Source; line: INTEGER);
    VAR r: LONGINT;
  BEGIN r := target - (addr + 2);
    IF final & ((r > 32767) OR (r < -32768)) THEN ASS.Error(src, line, "branch out of range", "") END;
    o(r); o(r DIV 100H)
  END Rel16;

  (* A block move names banks: a small value is the bank itself, a
     larger one an address in the bank. *)
  PROCEDURE Bank(a: LONGINT): LONGINT;
  BEGIN
    IF (a < 0) OR (a >= 100H) THEN a := a DIV 10000H END;
    RETURN a
  END Bank;

  PROCEDURE InDirectPage(a: LONGINT): BOOLEAN;
  BEGIN RETURN (a >= 0) & (a < 100H) OR (dpage # 0) & (a >= dpage) & (a - dpage < 100H)
  END InDirectPage;

  (* The parser cannot tell "addr" from "dp" or "long": the forms look
     alike and differ only in the size of the operand. Choose here, by
     the modifier if one was written and by the value otherwise. A mode
     the instruction lacks is not chosen, so "jmp $10" stays absolute. *)
  PROCEDURE Resolve(op, modifier: INTEGER; VAR mode: INTEGER; VAR a: LONGINT;
      src: ASS.Source; line: INTEGER);
    VAR dp, long: BOOLEAN; m: INTEGER;
  BEGIN
    long := modifier = MLong;
    dp := (modifier = MDirect) OR (modifier = MByte) OR
      InDirectPage(a) & (modifier # MAbs) & (modifier # MWord) & ~long;
    m := mode;
    IF mode = ASC.mAbs THEN
      IF dp THEN m := ASC.mDP ELSIF long THEN m := ASC.mAbsL END
    ELSIF mode = ASC.mAbsX THEN
      IF dp THEN m := ASC.mDPX ELSIF long OR (a > 0FFFFH) THEN m := ASC.mAbsLX END
    ELSIF mode = ASC.mAbsY THEN
      IF dp THEN m := ASC.mDPY END
    ELSIF mode = ASC.mAbsIndX THEN
      IF dp THEN m := ASC.mDPIndX END
    ELSIF mode = ASC.mAbsInd THEN
      IF long OR (a > 0FFFFH) & (modifier # MAbs) THEN m := ASC.mAbsIndL
      ELSIF dp THEN m := ASC.mDPInd
      END
    ELSIF mode = ASC.mAbsIndL THEN
      IF dp THEN m := ASC.mDPIndL END
    END;
    IF (m # mode) & ASC.Has(op, m) THEN mode := m
    ELSIF ~ASC.Has(op, mode) THEN
      (* an indirect address the instruction takes from the direct page
         only: use that form, as the C assembler did, but say so *)
      IF mode = ASC.mAbsInd THEN m := ASC.mDPInd
      ELSIF mode = ASC.mAbsIndL THEN m := ASC.mDPIndL
      ELSE m := mode
      END;
      IF (m # mode) & ASC.Has(op, m) THEN mode := m;
        IF final & ~InDirectPage(a) THEN
          ASS.Warn(src, line, "address truncated to the direct page", "")
        END
      END
    END;
    (* an address in the page the direct page register points to *)
    IF (a >= 100H) & (dpage # 0) & (a >= dpage) & (a - dpage < 100H) &
       ((mode = ASC.mDP) OR (mode = ASC.mDPX) OR (mode = ASC.mDPY) OR (mode = ASC.mDPInd) OR
        (mode = ASC.mDPIndL) OR (mode = ASC.mDPIndX) OR (mode = ASC.mDPIndY) OR
        (mode = ASC.mDPIndLY)) THEN
      a := a - dpage
    END
  END Resolve;

  (* Emit instruction op. The operands a1, a2, a3 are in the order they
     were written; mode tells how many of them there are. src and line
     locate the instruction for messages. *)
  PROCEDURE Instr*(op, mode, modifier: INTEGER; a1, a2, a3: LONGINT;
      src: ASS.Source; line: INTEGER);
    VAR form, code: INTEGER; r: LONGINT; wide: BOOLEAN;
  BEGIN
    Resolve(op, modifier, mode, a1, src, line);
    IF ~ASC.Find(op, mode, form, code) THEN
      IF final THEN InstrError(src, line, op, mode) END
    ELSE
      CASE form OF
        ASC.fImpl: o(code)
      | ASC.fByte: o(code); o(a1)
      | ASC.fWord: o(code); o(a1); o(a1 DIV 100H)
      | ASC.fLong: o(code); o(a1); o(a1 DIV 100H); o(a1 DIV 10000H)
      | ASC.fImmA, ASC.fImmX:
          IF form = ASC.fImmA THEN wide := longa ELSE wide := longi END;
          IF modifier = MByte THEN wide := FALSE
          ELSIF (modifier = MWord) OR (modifier = MAbs) THEN wide := TRUE
          END;
          o(code); o(a1);
          IF wide THEN o(a1 DIV 100H) END
      | ASC.fRel: o(code); Rel8(a1, src, line)
      | ASC.fRelL: o(code); Rel16(a1, src, line)
      | ASC.fBra:
          r := a1 - (addr + 2);
          IF (r > 127) OR (r < -128) THEN
            IF final THEN ASS.Warn(src, line, "BRA promoted to BRL", "") END;
            o(82H); Rel16(a1, src, line)
          ELSE o(code); o(r)
          END
      | ASC.fBrl:
          r := a1 - (addr + 2);
          IF (r > 127) OR (r < -128) THEN o(code); Rel16(a1, src, line)
          ELSE
            IF final THEN ASS.Warn(src, line, "BRL demoted to BRA", "") END;
            o(80H); o(r)
          END
      | ASC.fWordR: AddReloc; o(code); o(a1); o(a1 DIV 100H)
      | ASC.fLongR: AddReloc; o(code); o(a1); o(a1 DIV 100H); o(a1 DIV 10000H)
      | ASC.fMove: o(code); o(Bank(a2)); o(Bank(a1))
      | ASC.fBitZ: o(code + a1 MOD 8 * 10H); o(a2)
      | ASC.fBitA: o(code); o(a1); o(a2); o(a2 DIV 100H)
      | ASC.fBitZR: o(code + a1 MOD 8 * 10H); o(a2); Rel8(a3, src, line)
      | ASC.fBitAR: o(code); o(a2); o(a1); o(a1 DIV 100H); Rel8(a3, src, line)
      | ASC.fImmZ: o(code); o(a1); o(a2)
      | ASC.fJsb: o(code + a1 MOD 8 * 10H)
      END
    END
  END Instr;

  PROCEDURE Init*;
  BEGIN
    sections := NIL; lastSect := NIL; nofSections := 0; nofReloc := 0;
    relocOverflow := FALSE; entry := 0; final := FALSE;
    (* the standard sections, in the order they have in an ELF file *)
    cur := NewSection("stack", Nobits, Write + Alloc + Stack);
    cur := NewSection("dp", Nobits, Write + Alloc + DPage);
    cur := NewSection("tls", Nobits, Write + Alloc + TLS);
    cur := NewSection("bss", Nobits, Write + Alloc);
    cur := NewSection("data", Progbits, Write + Alloc);
    cur := NewSection("rodata", Progbits, Alloc);
    text := NewSection("text", Progbits, Alloc + Exec);
    cur := text; addr := 0
  END Init;

BEGIN defaultCpu := ASC.c6502; machine := defaultCpu; Init
END ASG.
