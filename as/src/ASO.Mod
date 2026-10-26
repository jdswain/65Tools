MODULE ASO; (* Output of the 65xx assembler.

   Writes the assembled program in the format the name of the output
   file asks for: an ELF executable or object file, a plain binary,
   MOS paper tape (TIM), Intel hex, Motorola S-records, a Verilog
   memory file, or an Oberon module for the 65C816 (.816) with its symbol file (.smb). Port of the
   writers in shared/src/elf_file.c.

   The .816 and .smb layouts are those of the Oberon compiler (ORGW and
   ORB.Export), so that Oberon modules can import a module written in
   assembler and the loader cannot tell the two apart. *)

  IMPORT Files, ASH, ASC, ASS, ASB, ASG;

  CONST
    (* output formats *)
    Unsupported* = 0; Exec* = 1; Object* = 2; Binary* = 3; TIM* = 4;
    Intel* = 5; S19* = 6; S28* = 7; S37* = 8; Mod816* = 9; Mem* = 10;

    (* ELF *)
    EhdrSize = 52; PhdrSize = 32; ShdrSize = 40; SymSize = 16;
    ETRel = 1; ETExec = 2;
    SHTSymtab = 2; SHTStrtab = 3;
    PTLoad = 1; PFX = 1; PFW = 2; PFR = 4;
    OSABI = 66;         (* OS16 *)
    FixedSections = 3;  (* null, .shstrtab, .symtab precede the program's *)
    StrFixed = 19;      (* length of 0X ".shstrtab" 0X ".symtab" 0X *)

    (* symbol files *)
    SymVersion = 6; LegacySymVersion = 1;
    Const = 1; Var = 2; Par = 3; Proc = 10;

    RecLen = 16;        (* data bytes of a record in the text formats *)
    MemFill = 0FFH;     (* between the runs of code in a memory file *)

  VAR F: Files.File; R: Files.Rider;
    sum: ARRAY 4 OF LONGINT;   (* of the bytes written, by position in a word *)
    count: LONGINT;            (* bytes written *)

  (* --- writing --- *)

  PROCEDURE W1(x: LONGINT);
  BEGIN x := x MOD 100H;
    Files.WriteByte(R, x); sum[count MOD 4] := sum[count MOD 4] + x; INC(count)
  END W1;

  PROCEDURE W2(x: LONGINT);
  BEGIN W1(x); W1(x DIV 100H)
  END W2;

  PROCEDURE W4(x: LONGINT);
  BEGIN W1(x); W1(x DIV 100H); W1(x DIV 10000H); W1(x DIV 1000000H)
  END W4;

  (* the characters of s and a closing 0X *)
  PROCEDURE WString(s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO W1(ORD(s[i])); INC(i) END;
    W1(0)
  END WString;

  (* variable length number, as Files.WriteNum of Oberon *)
  PROCEDURE WNum(x: LONGINT);
  BEGIN
    WHILE (x < -64) OR (x >= 64) DO W1(x MOD 128 + 128); x := x DIV 128 END;
    W1(x MOD 128)
  END WNum;

  PROCEDURE WChar(ch: CHAR);
  BEGIN Files.WriteByte(R, ORD(ch))
  END WChar;

  PROCEDURE WText(s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO Files.WriteByte(R, ORD(s[i])); INC(i) END
  END WText;

  PROCEDURE WHex(x: LONGINT; n: INTEGER);
    VAR s: ARRAY 12 OF CHAR;
  BEGIN ASH.HexStr(x, n, TRUE, s); WText(s)
  END WHex;

  (* the n bytes at offset off of section s *)
  PROCEDURE WCode(s: ASG.Section; off, n: LONGINT);
    VAR i: LONGINT;
  BEGIN i := 0;
    WHILE i < n DO W1(ASG.Get(s, off + i)); INC(i) END
  END WCode;

  PROCEDURE Create(name: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER;
  BEGIN F := Files.New(name);
    IF F # NIL THEN Files.Set(R, F, 0) ELSE ASS.Error(NIL, 0, "cannot create ", name) END;
    count := 0;
    FOR i := 0 TO 3 DO sum[i] := 0 END;
    RETURN F # NIL
  END Create;

  PROCEDURE Close;
  BEGIN Files.Register(F); Files.Close(F)
  END Close;

  PROCEDURE HasData(s: ASG.Section): BOOLEAN;
  BEGIN RETURN (s.type = ASG.Progbits) & (s.size > 0)
  END HasData;

  (* length of the extent e of section s *)
  PROCEDURE ExtentSize(s: ASG.Section; e: ASG.Extent): LONGINT;
    VAR n: LONGINT;
  BEGIN
    IF e.next # NIL THEN n := e.next.offset - e.offset ELSE n := s.size - e.offset END;
    RETURN n
  END ExtentSize;

  (* The symbols of the program that go into an object file: those with
     an integer value, in alphabetical order. *)
  PROCEDURE Symbols(VAR n: INTEGER): ASB.Object;
    VAR list, obj: ASB.Object; m: INTEGER;
  BEGIN list := ASB.Sorted(ASB.Top(), m); n := 0;
    WHILE (list # NIL) & (list.val.form # ASB.Int) DO list := list.link END;
    obj := list;
    WHILE obj # NIL DO INC(n);
      WHILE (obj.link # NIL) & (obj.link.val.form # ASB.Int) DO obj.link := obj.link.link END;
      obj := obj.link
    END;
    RETURN list
  END Symbols;

  (* --- ELF --- *)

  (* A section header. The string table is section 1, to which the
     symbol table links; its info is the index of its first global. *)
  PROCEDURE Shdr(name, type, flags, addr, offset, size: LONGINT);
  BEGIN W4(name); W4(type); W4(flags); W4(addr); W4(offset); W4(size);
    IF type = SHTSymtab THEN W4(1); W4(1); W4(0); W4(SymSize)
    ELSIF type = SHTStrtab THEN W4(1); W4(0); W4(0); W4(0)
    ELSE W4(0); W4(0); W4(0); W4(0)
    END
  END Shdr;

  (* An ELF file: the section name string table, which also holds the
     symbol names, the symbol table, and the sections of the program. An
     executable has a program header for each run of code or data, so a
     section assembled at several addresses is loaded to all of them. *)
  PROCEDURE WriteELF(name: ARRAY OF CHAR; exec: BOOLEAN);
    VAR s: ASG.Section; e: ASG.Extent; syms, obj: ASB.Object;
      nofSyms, nofPh, flags: INTEGER;
      strSize, symSize, offset, dataStart, nameOff: LONGINT;
  BEGIN
    syms := Symbols(nofSyms);
    strSize := StrFixed; s := ASG.sections;
    WHILE s # NIL DO strSize := strSize + ASH.Length(s.name) + 1; s := s.next END;
    obj := syms;
    WHILE obj # NIL DO strSize := strSize + ASH.Length(obj.name) + 1; obj := obj.link END;
    symSize := (nofSyms + 1) * SymSize;
    nofPh := 0;
    IF exec THEN s := ASG.sections;
      WHILE s # NIL DO
        IF s.size > 0 THEN e := s.extents;
          WHILE e # NIL DO
            IF ExtentSize(s, e) > 0 THEN INC(nofPh) END;
            e := e.next
          END
        END;
        s := s.next
      END
    END;
    dataStart := EhdrSize + nofPh * PhdrSize + strSize + symSize;
    offset := dataStart; s := ASG.sections;
    WHILE s # NIL DO
      IF HasData(s) THEN offset := offset + s.size END;
      s := s.next
    END;
    IF Create(name) THEN
      (* file header *)
      W1(7FH); W1(ORD("E")); W1(ORD("L")); W1(ORD("F"));
      W1(1); W1(1); W1(1); W1(OSABI); W4(0); W4(0);
      IF exec THEN W2(ETExec) ELSE W2(ETRel) END;
      W2(ASG.machine); W4(1); W4(ASG.entry);
      IF exec THEN W4(EhdrSize) ELSE W4(0) END;
      W4(offset); W4(0);
      W2(EhdrSize); W2(PhdrSize); W2(nofPh); W2(ShdrSize);
      W2(FixedSections + ASG.nofSections); W2(1);
      (* program headers *)
      IF exec THEN offset := dataStart; s := ASG.sections;
        WHILE s # NIL DO
          IF s.size > 0 THEN e := s.extents;
            flags := PFR;
            IF ASG.IsCode(s) THEN flags := flags + PFX END;
            IF ODD(s.flags DIV ASG.Write) THEN flags := flags + PFW END;
            WHILE e # NIL DO
              IF ExtentSize(s, e) > 0 THEN
                W4(PTLoad);
                IF HasData(s) THEN W4(offset + e.offset) ELSE W4(offset) END;
                W4(e.addr); W4(e.addr);
                IF HasData(s) THEN W4(ExtentSize(s, e)) ELSE W4(0) END;
                W4(ExtentSize(s, e)); W4(flags); W4(0)
              END;
              e := e.next
            END
          END;
          IF HasData(s) THEN offset := offset + s.size END;
          s := s.next
        END
      END;
      (* string table *)
      W1(0); WString(".shstrtab"); WString(".symtab");
      s := ASG.sections;
      WHILE s # NIL DO WString(s.name); s := s.next END;
      obj := syms;
      WHILE obj # NIL DO WString(obj.name); obj := obj.link END;
      (* symbol table *)
      W4(0); W4(0); W4(0); W4(0);
      nameOff := StrFixed; s := ASG.sections;
      WHILE s # NIL DO nameOff := nameOff + ASH.Length(s.name) + 1; s := s.next END;
      obj := syms;
      WHILE obj # NIL DO
        W4(nameOff); W4(obj.val.i); W4(0);
        IF obj.expo THEN W1(10H) ELSE W1(0) END;   (*binding global or local*)
        W1(0); W2(0);
        nameOff := nameOff + ASH.Length(obj.name) + 1; obj := obj.link
      END;
      (* code and data *)
      s := ASG.sections;
      WHILE s # NIL DO
        IF HasData(s) THEN WCode(s, 0, s.size) END;
        s := s.next
      END;
      (* section headers *)
      offset := EhdrSize + nofPh * PhdrSize;
      Shdr(0, 0, 0, 0, 0, 0);
      Shdr(1, SHTStrtab, 0, 0, offset, strSize);
      Shdr(11, SHTSymtab, 0, 0, offset + strSize, symSize);
      offset := dataStart; nameOff := StrFixed; s := ASG.sections;
      WHILE s # NIL DO
        Shdr(nameOff, s.type, s.flags, s.org, offset, s.size);
        IF HasData(s) THEN offset := offset + s.size END;
        nameOff := nameOff + ASH.Length(s.name) + 1; s := s.next
      END;
      Close
    END
  END WriteELF;

  (* --- binary and text formats --- *)

  (* The code sections, one after the other. *)
  PROCEDURE WriteBinary(name: ARRAY OF CHAR);
    VAR s: ASG.Section;
  BEGIN
    IF Create(name) THEN s := ASG.sections;
      WHILE s # NIL DO
        IF HasData(s) & ASG.IsCode(s) THEN WCode(s, 0, s.size) END;
        s := s.next
      END;
      Close
    END
  END WriteBinary;

  (* sum of the n low bytes of x *)
  PROCEDURE ByteSum(x: LONGINT; n: INTEGER): LONGINT;
    VAR s: LONGINT;
  BEGIN s := 0;
    WHILE n > 0 DO s := s + x MOD 100H; x := x DIV 100H; DEC(n) END;
    RETURN s
  END ByteSum;

  (* One record of a text format: n bytes at offset off of section s,
     which are loaded at address addr. *)
  PROCEDURE Record(format: INTEGER; s: ASG.Section; off, addr: LONGINT; n: INTEGER);
    VAR i, b, digits: INTEGER; cs: LONGINT;
  BEGIN
    IF format = TIM THEN  (* ;LLAAAA data CCCC, the checksum a 16 bit sum *)
      WChar(";"); WHex(n, 2); WHex(addr, 4);
      cs := n + ByteSum(addr, 2);
      FOR i := 0 TO n - 1 DO b := ASG.Get(s, off + i); WHex(b, 2); cs := cs + b END;
      WHex(cs, 4)
    ELSIF format = Intel THEN  (* :LLAAAA00 data CC *)
      WChar(":"); WHex(n, 2); WHex(addr, 4); WText("00");
      cs := n + ByteSum(addr, 2);
      FOR i := 0 TO n - 1 DO b := ASG.Get(s, off + i); WHex(b, 2); cs := cs + b END;
      WHex(-cs, 2)
    ELSE  (* S1/S2/S3: Sn LL address data CC, LL counting all that follows *)
      digits := (format - S19) * 2 + 4;
      WChar("S"); WChar(CHR(ORD("1") + format - S19));
      WHex(n + digits DIV 2 + 1, 2); WHex(addr, digits);
      cs := n + digits DIV 2 + 1 + ByteSum(addr, digits DIV 2);
      FOR i := 0 TO n - 1 DO b := ASG.Get(s, off + i); WHex(b, 2); cs := cs + b END;
      WHex(-cs - 1, 2)
    END;
    WChar(0AX)
  END Record;

  (* Paper tape, Intel hex or S-records: every run of code and data, at
     its address, in records of RecLen bytes. *)
  PROCEDURE WriteText(name: ARRAY OF CHAR; format: INTEGER);
    VAR s: ASG.Section; e: ASG.Extent;
      off, end, addr, upper: LONGINT; n, digits: INTEGER; cs: LONGINT;
  BEGIN
    IF Create(name) THEN
      upper := 0; s := ASG.sections;
      WHILE s # NIL DO
        IF HasData(s) THEN e := s.extents;
          WHILE e # NIL DO
            off := e.offset; end := off + ExtentSize(s, e); addr := e.addr;
            WHILE off < end DO
              n := RecLen;
              IF end - off < n THEN n := end - off END;
              IF format = Intel THEN
                (* a record does not cross a 64K boundary, and the upper
                   half of its address is set by a record of type 04 *)
                IF addr MOD 10000H + n > 10000H THEN n := 10000H - addr MOD 10000H END;
                IF addr DIV 10000H # upper THEN
                  upper := addr DIV 10000H;
                  WText(":02000004"); WHex(upper, 4);
                  WHex(-(6 + ByteSum(upper, 2)), 2); WChar(0AX)
                END;
                Record(format, s, off, addr MOD 10000H, n)
              ELSE Record(format, s, off, addr, n)
              END;
              off := off + n; addr := addr + n
            END;
            e := e.next
          END
        END;
        s := s.next
      END;
      (* the closing record *)
      IF format = TIM THEN WText(";00")
      ELSIF format = Intel THEN WText(":00000001FF")
      ELSE  (* S9/S8/S7 with the start address *)
        digits := (format - S19) * 2 + 4; addr := ASG.entry;
        WChar("S"); WChar(CHR(ORD("9") - (format - S19)));
        WHex(digits DIV 2 + 1, 2); WHex(addr, digits);
        cs := digits DIV 2 + 1 + ByteSum(addr, digits DIV 2);
        WHex(-cs - 1, 2)
      END;
      WChar(0AX);
      Close
    END
  END WriteText;

  (* One byte of a memory file, RecLen to a line; n counts those on
     the line. *)
  PROCEDURE MemByte(b: INTEGER; VAR n: INTEGER);
  BEGIN
    IF n = RecLen THEN WChar(0AX); n := 0 ELSIF n > 0 THEN WChar(" ") END;
    WHex(b, 2); INC(n)
  END MemByte;

  (* A Verilog memory file, as $readmemh reads it into reg [7:0] rom [0:n]:
     the bytes of the program from its lowest address to its highest, the
     gaps between the runs of code filled with MemFill. There are no
     @address lines, because the address in one counts from the start of
     the Verilog array, not of the processor's memory, and Gowin's
     synthesis truncates it to the width of the data. A comment gives the
     range, so the first byte belongs at the base of the ROM. *)
  PROCEDURE WriteMem(name: ARRAY OF CHAR);
    VAR s, bs: ASG.Section; e, be: ASG.Extent;
      pos, lo, hi, off, end: LONGINT; n, digits: INTEGER; first: BOOLEAN;
  BEGIN
    IF Create(name) THEN
      (* the range *)
      first := TRUE; lo := 0; hi := 0; s := ASG.sections;
      WHILE s # NIL DO
        IF HasData(s) THEN e := s.extents;
          WHILE e # NIL DO
            end := e.addr + ExtentSize(s, e);
            IF end > e.addr THEN
              IF first OR (e.addr < lo) THEN lo := e.addr END;
              IF first OR (end > hi) THEN hi := end END;
              first := FALSE
            END;
            e := e.next
          END
        END;
        s := s.next
      END;
      IF ~first THEN
        digits := ASH.HexDigits(hi - 1, 4);
        WText("// $"); WHex(lo, digits); WText("-$"); WHex(hi - 1, digits); WChar(0AX)
      END;
      (* the runs in order of address: each time the lowest that reaches
         past what is written *)
      pos := lo; n := 0;
      WHILE pos < hi DO
        be := NIL; bs := NIL; s := ASG.sections;
        WHILE s # NIL DO
          IF HasData(s) THEN e := s.extents;
            WHILE e # NIL DO
              IF (e.addr + ExtentSize(s, e) > pos) & ((be = NIL) OR (e.addr < be.addr)) THEN
                be := e; bs := s
              END;
              e := e.next
            END
          END;
          s := s.next
        END;
        WHILE pos < be.addr DO MemByte(MemFill, n); INC(pos) END;
        off := be.offset + (pos - be.addr); end := be.offset + ExtentSize(bs, be);
        WHILE off < end DO MemByte(ASG.Get(bs, off), n); INC(off); INC(pos) END
      END;
      IF n > 0 THEN WChar(0AX) END;
      Close
    END
  END WriteMem;

  (* --- Oberon modules --- *)

  (* The exported symbols, in alphabetical order, which is the order of
     their export numbers; "_init" is the module body, not an export. *)
  PROCEDURE Exports(VAR n: INTEGER; VAR init: ASB.Object): ASB.Object;
    VAR list, obj, prev, next: ASB.Object; m: INTEGER;
  BEGIN list := Symbols(m); n := 0; init := NIL; prev := NIL; obj := list;
    WHILE obj # NIL DO next := obj.link;
      IF obj.name = "_init" THEN init := obj END;
      IF obj.expo & (obj.name # "_init") THEN INC(n); prev := obj
      ELSIF prev = NIL THEN list := next
      ELSE prev.link := next
      END;
      obj := next
    END;
    RETURN list
  END Exports;

  PROCEDURE TypeByte(ref: INTEGER);   (*reference to a predeclared type*)
  BEGIN W1(-ref)
  END TypeByte;

  (* The symbol file, as ORB.Export writes it for a module that exports
     procedures only. Every export is a procedure; without a ".proc"
     declaration it has no parameters and no result. key is the
     checksum that identifies this version of the interface. *)
  PROCEDURE WriteSymbols(name, modid: ARRAY OF CHAR; exports: ASB.Object;
      version: INTEGER; VAR key: ARRAY OF INTEGER);
    VAR obj: ASB.Object; sig: ASB.Signature; exno, i: INTEGER; s: LONGINT;
  BEGIN
    FOR i := 0 TO 3 DO key[i] := 0 END;
    IF Create(name) THEN
      W4(0); W4(0);   (*the key goes here*)
      WString(modid); W1(version);
      obj := exports; exno := 1;
      WHILE obj # NIL DO
        sig := ASB.ThisSignature(obj.name);
        W1(Const); WString(obj.name);
        W1(0); W1(Proc);   (*an anonymous procedure type*)
        IF version >= SymVersion THEN W1(0) END;   (*not a method*)
        IF sig = NIL THEN TypeByte(ASB.NoTyp)
        ELSE TypeByte(sig.restype);
          (* the parameters, last one first *)
          i := sig.nofpar;
          WHILE i > 0 DO DEC(i);
            IF sig.parvar[i] THEN W1(Par) ELSE W1(Var) END;
            W1(0); TypeByte(sig.partype[i])
          END
        END;
        W1(0);   (*end of parameters*)
        W1(0);   (*not re-exported*)
        WNum(exno); INC(exno);
        obj := obj.link
      END;
      REPEAT W1(0) UNTIL count MOD 4 = 0;
      (* the key: the sum of the file's words, taken modulo 2^32 *)
      s := 0;
      FOR i := 0 TO 3 DO s := s DIV 100H + sum[i]; key[i] := s MOD 100H END;
      Files.Set(R, F, 4);
      FOR i := 0 TO 3 DO Files.WriteByte(R, key[i]) END;
      Close
    END
  END WriteSymbols;

  (* An Oberon module: the text section is its code, the bss section its
     variables (zeroed by the loader, in bank 0), the exported symbols
     are its procedures and "_init" is its body. A module made by the
     assembler has no strings or type descriptors, and its variables are
     not exported. Addresses in code and in bss are relocated by the
     loader: ASG.RelCode, RelLong and RelData. *)
  PROCEDURE WriteModule(name: ARRAY OF CHAR; legacy: BOOLEAN);
    VAR text: ASG.Section; exports, init, obj: ASB.Object; sig: ASB.Signature;
      nofExp, i, version: INTEGER; entry: LONGINT;
      modid: ASS.Ident; smb: ASH.Path; key: ARRAY 4 OF INTEGER;
  BEGIN text := ASG.text;
    ASH.Base(name, modid); ASH.SetExt(name, ".smb", smb);
    exports := Exports(nofExp, init);
    IF legacy THEN version := LegacySymVersion ELSE version := SymVersion END;
    WriteSymbols(smb, modid, exports, version, key);
    (* with no body, an RTL after the code is the entry *)
    IF init # NIL THEN entry := init.val.i - text.org ELSE entry := text.size END;
    IF ASG.RelocOverflow() THEN ASS.Error(NIL, 0, "too many relocatable calls", "") END;
    IF (ASS.errcnt = 0) & Create(name) THEN
      WString(modid);
      FOR i := 0 TO 3 DO W1(key[i]) END;
      IF legacy THEN W1(1) ELSE W1(2) END;   (*layout version*)
      W4(0);   (*size, which the loaders do not use*)
      FOR i := 0 TO ASB.nofImports - 1 DO
        WString(ASB.imports[i].name); W4(ASB.imports[i].key)
      END;
      W1(0);
      W4(0);   (*type descriptors*)
      W4(ASG.bss.size);   (*variables*)
      W4(0);   (*strings*)
      IF init # NIL THEN W4(text.size); WCode(text, 0, text.size)
      ELSE W4(text.size + 1); WCode(text, 0, text.size); W1(6BH)   (*RTL*)
      END;
      (* commands: the procedures without parameters and result *)
      obj := exports;
      WHILE obj # NIL DO
        sig := ASB.ThisSignature(obj.name);
        IF (sig = NIL) OR (sig.nofpar = 0) & (sig.restype = ASB.NoTyp) THEN
          WString(obj.name); W4(obj.val.i - text.org)
        END;
        obj := obj.link
      END;
      W1(0);
      W4(nofExp + 1); W4(entry);
      (* entries, by export number *)
      obj := exports;
      WHILE obj # NIL DO W4(obj.val.i - text.org); obj := obj.link END;
      W4(-1);   (*no pointer variables*)
      W4(0); W4(0); W4(0);   (*no fixup chains*)
      W4(0);   (*no type descriptor fixups*)
      IF ~legacy THEN W4(0) END;   (*no method table fixups*)
      W4(ASG.nofReloc);
      FOR i := 0 TO ASG.nofReloc - 1 DO W4(ASG.Reloc(i)) END;
      W4(entry); W1(ORD("O"));
      Close;
      ASH.Str("  "); ASH.Str(name); ASH.Str("  "); ASH.Int(text.size);
      ASH.Str(" bytes code, "); ASH.Int(nofExp); ASH.Str(" exports"); ASH.Ln
    END
  END WriteModule;

  (* --- entry points --- *)

  (* The format the name of an output file asks for. *)
  PROCEDURE Format*(name: ARRAY OF CHAR): INTEGER;
    VAR ext: ARRAY 16 OF CHAR; f: INTEGER;
  BEGIN ASH.Ext(name, ext);
    IF ext[0] = 0X THEN f := Exec
    ELSIF ext = ".o" THEN f := Object
    ELSIF ext = ".bin" THEN f := Binary
    ELSIF ext = ".tim" THEN f := TIM
    ELSIF ext = ".hex" THEN f := Intel
    ELSIF ext = ".s19" THEN f := S19
    ELSIF ext = ".s28" THEN f := S28
    ELSIF ext = ".s37" THEN f := S37
    ELSIF ext = ".mem" THEN f := Mem
    ELSIF ext = ".816" THEN f := Mod816
    ELSE f := Unsupported
    END;
    RETURN f
  END Format;

  (* The processor a program is assembled for unless it says otherwise:
     the 65C816 for the formats of the operating system, the 6502 for
     those that are loaded into a ROM. *)
  PROCEDURE DefaultCpu*(format: INTEGER): INTEGER;
    VAR c: INTEGER;
  BEGIN
    IF (format = Exec) OR (format = Object) OR (format = Mod816) THEN c := ASC.c65C816
    ELSE c := ASC.c6502
    END;
    RETURN c
  END DefaultCpu;

  (* Write the assembled program to file `name`. legacy selects the
     .816 and .smb layouts of the C compiler. *)
  PROCEDURE Write*(name: ARRAY OF CHAR; format: INTEGER; legacy: BOOLEAN);
  BEGIN
    IF format = Exec THEN WriteELF(name, TRUE)
    ELSIF format = Object THEN WriteELF(name, FALSE)
    ELSIF format = Binary THEN WriteBinary(name)
    ELSIF format = Mod816 THEN WriteModule(name, legacy)
    ELSIF format = Mem THEN WriteMem(name)
    ELSIF format # Unsupported THEN WriteText(name, format)
    END
  END Write;

END ASO.
