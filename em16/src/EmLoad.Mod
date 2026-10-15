MODULE EmLoad; (* Loading programs: ELF executables of the assembler, and
   the .816 modules of the Oberon compiler, which are relocated into
   bank 1 with their variables in bank 0 from $1000, their imports
   loaded from the same directory or the -I directories when they are
   not on the command line. Also the compiler's run time traps, with a
   heap for NEW, and the manifest at $0D00 that tells OS16's Modules
   which modules are loaded.

   The messages are those of em16's main.cpp, which the test scripts
   read. *)

  IMPORT Files, EmHost, EmSym, EmMem, EmCPU;

  CONST
    out = EmHost.out; err = EmHost.err;
    moduleBank = 1; moduleVarBase = 1000H; bankSize = 10000H;
    moduleTable = 0E00H; manifestBase = 0D00H;
    maxExports = 64; maxImports = 16; maxModules = 64; maxPaths = 16;
    (* ELF *)
    emW65C816 = 1; emW65C02 = 2; em6502 = 3; emR65C02 = 4; emR65C19 = 5; emR6501 = 6;

  TYPE
    Name = ARRAY 64 OF CHAR;
    Path* = ARRAY 256 OF CHAR;
    Module = POINTER TO ModuleDesc;
    ModuleDesc = RECORD
      name: Name;
      bank, base, var, size, entry: INTEGER;
      nofExports: INTEGER;           (* including the unused entry 0 *)
      exports: ARRAY maxExports OF INTEGER;
      next: Module
    END;

  VAR
    modules: Module;                 (* the last loaded first *)
    loadAddress*, varAddress*, moduleIndex: INTEGER;
    entries*: ARRAY maxModules OF INTEGER;  (* to initialise, in order *)
    nofEntries*: INTEGER;
    searchDir: Path;
    paths: ARRAY maxPaths OF Path;
    nofPaths: INTEGER;
    heapTop, heapBank, heapLimit: INTEGER;
    elfBuf: ARRAY 1000000 OF BYTE;
    tdData: ARRAY 65536 OF BYTE;      (* read before any recursive LoadMod *)

  (* --- output --- *)

  PROCEDURE Str(s: ARRAY OF CHAR); BEGIN EmHost.Str(out, s) END Str;
  PROCEDURE Int(x: LONGINT); BEGIN EmHost.Int(out, x) END Int;
  PROCEDURE Hex(x: LONGINT; w: INTEGER); BEGIN EmHost.Hex(out, x, w) END Hex;
  PROCEDURE Ln; BEGIN EmHost.Ln(out) END Ln;

  (* --- reading files --- *)

  PROCEDURE Byte(VAR r: Files.Rider; VAR ok: BOOLEAN): INTEGER;
    VAR b: BYTE; v: INTEGER;
  BEGIN Files.ReadByte(r, b);
    IF r.eof THEN ok := FALSE; v := 0 ELSE v := b END;
    RETURN v
  END Byte;

  PROCEDURE Word16(VAR r: Files.Rider; VAR ok: BOOLEAN): INTEGER;
    VAR l: INTEGER;
  BEGIN l := Byte(r, ok);
    RETURN l + Byte(r, ok) * 100H
  END Word16;

  (* A 32 bit little endian integer, signed. *)
  PROCEDURE Word32(VAR r: Files.Rider; VAR ok: BOOLEAN): INTEGER;
    VAR l: INTEGER;
  BEGIN l := Word16(r, ok);
    RETURN l + ASL(Word16(r, ok), 16)
  END Word32;

  PROCEDURE ReadName(VAR r: Files.Rider; first: INTEGER; VAR name: ARRAY OF CHAR);
    VAR ch, n: INTEGER; ok: BOOLEAN;
  BEGIN n := 0; name[n] := CHR(first); INC(n); ok := TRUE;
    ch := Byte(r, ok);
    WHILE ok & (ch # 0) DO
      IF n < 63 THEN name[n] := CHR(ch); INC(n) END;
      ch := Byte(r, ok)
    END;
    name[n] := 0X
  END ReadName;

  (* --- strings --- *)

  PROCEDURE Length(s: ARRAY OF CHAR): INTEGER;
    VAR i: INTEGER;
  BEGIN i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END; RETURN i
  END Length;

  PROCEDURE Append(s: ARRAY OF CHAR; VAR d: ARRAY OF CHAR);
    VAR i, j: INTEGER;
  BEGIN i := Length(d); j := 0;
    WHILE (j < LEN(s)) & (s[j] # 0X) & (i < LEN(d) - 1) DO d[i] := s[j]; INC(i); INC(j) END;
    d[i] := 0X
  END Append;

  PROCEDURE Equal(a, b: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE (i < LEN(a)) & (i < LEN(b)) & (a[i] # 0X) & (a[i] = b[i]) DO INC(i) END;
    RETURN ((i = LEN(a)) OR (a[i] = 0X)) & ((i = LEN(b)) OR (b[i] = 0X))
  END Equal;

  (* --- the search path --- *)

  PROCEDURE AddPath*(p: ARRAY OF CHAR);
    VAR n: INTEGER;
  BEGIN
    IF nofPaths < maxPaths THEN
      paths[nofPaths][0] := 0X; Append(p, paths[nofPaths]);
      n := Length(paths[nofPaths]);
      IF (n > 0) & (paths[nofPaths][n-1] # "/") & (n < 254) THEN
        paths[nofPaths][n] := "/"; paths[nofPaths][n+1] := 0X
      END;
      INC(nofPaths)
    END
  END AddPath;

  PROCEDURE ModulePath(dir, name: ARRAY OF CHAR; VAR path: ARRAY OF CHAR);
  BEGIN path[0] := 0X; Append(dir, path); Append(name, path); Append(".816", path)
  END ModulePath;

  PROCEDURE Find(name: ARRAY OF CHAR): Module;
    VAR m: Module;
  BEGIN m := modules;
    WHILE (m # NIL) & ~Equal(m.name, name) DO m := m.next END;
    RETURN m
  END Find;

  (* --- the ELF loader --- *)

  PROCEDURE Fail(msg: ARRAY OF CHAR);
  BEGIN EmHost.Str(err, msg); EmHost.Ln(err); EmHost.Exit(1)
  END Fail;

  PROCEDURE Configured(s: ARRAY OF CHAR);
  BEGIN Str("Configured for "); Str(s); Ln
  END Configured;

  (* Load the segments of an ELF executable, lowest address first, and
     its symbols; return its entry point. *)
  PROCEDURE LoadELF*(name: ARRAY OF CHAR): INTEGER;
    TYPE Seg = RECORD addr, len, off: INTEGER END;
    VAR f: Files.File; r: Files.Rider; ok: BOOLEAN;
      machine, entry, phoff, shoff, phnum, shnum, shstrndx: INTEGER;
      segs: ARRAY 16 OF Seg; t: Seg; nseg, i, j, k, n, type, size, off, count, addr: INTEGER;
  BEGIN ok := TRUE; f := Files.Old(name);
    IF f = NIL THEN Fail("Invalid ELF file") END;
    Files.Set(r, f, 0);
    IF (Byte(r, ok) # 7FH) OR (Byte(r, ok) # ORD("E")) OR (Byte(r, ok) # ORD("L")) OR (Byte(r, ok) # ORD("F")) OR ~ok THEN
      Fail("Invalid ELF file")
    END;
    Files.Set(r, f, 18); machine := Word16(r, ok);
    Files.Set(r, f, 24); entry := Word32(r, ok); phoff := Word32(r, ok); shoff := Word32(r, ok);
    Files.Set(r, f, 44); phnum := Word16(r, ok); i := Word16(r, ok); shnum := Word16(r, ok); shstrndx := Word16(r, ok);
    IF machine = emW65C816 THEN Configured("65C816."); EmCPU.SetStackPage(100H)
    ELSIF machine = emW65C02 THEN Configured("65C02."); EmCPU.SetStackPage(100H)
    ELSIF machine = em6502 THEN Configured("6502."); EmCPU.SetStackPage(100H)
    ELSIF machine = emR65C02 THEN Configured("R65C02."); EmCPU.SetStackPage(100H)
    ELSIF machine = emR65C19 THEN Configured("L28 (R65C19).");
      EmCPU.SetCpuType(EmCPU.l28); EmCPU.SetStackPage(100H); EmMem.EnableL28;
      EmMem.SetUartBase(1FFFFFH); EmMem.SetFdcBase(640H); EmMem.SetViaBase(0)
    ELSIF machine = emR6501 THEN Configured("R6501Q."); EmCPU.SetStackPage(0)
    END;
    (* the loadable segments, sorted by address so that a higher one
       overwrites what a lower one ran into *)
    nseg := 0; i := 0;
    WHILE (i < phnum) & (nseg < 16) DO
      Files.Set(r, f, phoff + i * 32);
      type := Word32(r, ok); off := Word32(r, ok); j := Word32(r, ok); addr := Word32(r, ok);
      n := Word32(r, ok);
      IF ~ok THEN Fail("Malformed ELF file") END;
      IF (type = 1) & (addr > 0) & (n > 0) THEN
        segs[nseg].addr := addr; segs[nseg].len := n; segs[nseg].off := off; INC(nseg)
      END;
      INC(i)
    END;
    FOR i := 0 TO nseg - 2 DO
      FOR j := i + 1 TO nseg - 1 DO
        IF segs[j].addr < segs[i].addr THEN t := segs[i]; segs[i] := segs[j]; segs[j] := t END
      END
    END;
    FOR i := 0 TO nseg - 1 DO
      IF segs[i].off + segs[i].len <= Files.Length(f) THEN
        Str("Read segment into "); EmHost.CoutHex(segs[i].addr);
        Str(", length "); EmHost.Cout(segs[i].len); Ln;
        Files.Set(r, f, segs[i].off); addr := segs[i].addr;
        FOR k := 0 TO segs[i].len - 1 DO EmMem.SetByte(addr + k, Byte(r, ok)) END
      END
    END;
    (* the string table (that of the section names, which the assembler
       shares with the symbols) and the symbol table, for the trace *)
    Files.Set(r, f, shoff + shstrndx * 40 + 16); off := Word32(r, ok); size := Word32(r, ok);
    IF size > LEN(elfBuf) THEN size := LEN(elfBuf) END;
    Files.Set(r, f, off);
    FOR k := 0 TO size - 1 DO elfBuf[k] := Byte(r, ok) END;
    EmSym.SetStrtab(elfBuf, size);
    count := 0;
    FOR i := 0 TO shnum - 1 DO
      Files.Set(r, f, shoff + i * 40 + 4);
      IF Word32(r, ok) = 2 THEN
        Files.Set(r, f, shoff + i * 40 + 16); off := Word32(r, ok); size := Word32(r, ok);
        count := size DIV 16;
        Files.Set(r, f, off);
        FOR j := 0 TO count - 1 DO
          n := Word32(r, ok); addr := Word32(r, ok); k := Word32(r, ok); k := Word32(r, ok);
          EmSym.SetSymbol(j, addr, n)
        END
      END
    END;
    EmSym.SetSymbolCount(count);
    RETURN entry
  END LoadELF;

  (* --- the .816 loader --- *)

  PROCEDURE ImportName(VAR import: ARRAY OF Module; mno, nofImports: INTEGER): Module;
    VAR m: Module;
  BEGIN
    IF (mno > 0) & (mno <= nofImports) & (mno < maxImports) THEN m := import[mno] ELSE m := NIL END;
    RETURN m
  END ImportName;

  (* Patch the instruction at addr, relocated by its opcode: JSR, JSL
     (within the module, or to an import's export: bank byte mno, address
     exno), LDA # (a module's variables) or PER (an import's procedure). *)
  PROCEDURE Relocate(addr, base, varBase: INTEGER; VAR import: ARRAY OF Module; nofImports: INTEGER);
    VAR op, w, b, mno, exno, target, full, v, per: INTEGER; m: Module;
  BEGIN op := EmMem.GetByte(addr);
    IF op = 20H THEN
      w := EmMem.GetByte(addr + 1) + EmMem.GetByte(addr + 2) * 100H;
      v := AND(w + base, 0FFFFH);
      EmMem.SetByte(addr + 1, AND(v, 0FFH)); EmMem.SetByte(addr + 2, v DIV 100H);
      Str("  JSR relocation at $"); Hex(addr, 6); Str(": $"); Hex(AND(v - base, 0FFFFH), 4);
      Str(" -> $"); Hex(v, 4); Ln
    ELSIF op = 22H THEN
      b := EmMem.GetByte(addr + 3);
      w := EmMem.GetByte(addr + 1) + EmMem.GetByte(addr + 2) * 100H;
      m := ImportName(import, b, nofImports);
      IF (b > 0) & (m # NIL) THEN mno := b; exno := w;
        IF (exno > 0) & (exno < m.nofExports) THEN
          full := moduleBank * bankSize + m.base + m.exports[exno];
          Str("  JSL import fixup at $"); Hex(addr, 6); Str(": mno="); Int(mno); Str(" exno="); Int(exno);
          Str(" -> "); Str(m.name); Str(" $"); Hex(AND(full DIV 10000H, 0FFH), 2); Str(":"); Hex(AND(full, 0FFFFH), 4); Ln;
          EmMem.SetByte(addr + 1, AND(full, 0FFH)); EmMem.SetByte(addr + 2, AND(full DIV 100H, 0FFH));
          EmMem.SetByte(addr + 3, AND(full DIV 10000H, 0FFH))
        ELSE
          Str("  Warning: Invalid exno "); Int(exno); Str(" for module "); Str(m.name);
          Str(" (has "); Int(m.nofExports - 1); Str(" exports)"); Ln
        END
      ELSE
        target := moduleBank * bankSize + base + w;
        EmMem.SetByte(addr + 1, AND(target, 0FFH)); EmMem.SetByte(addr + 2, AND(target DIV 100H, 0FFH));
        EmMem.SetByte(addr + 3, AND(target DIV 10000H, 0FFH));
        Str("  JSL relocation at $"); Hex(addr, 6); Str(": $"); Hex(w, 4); Str(" -> $");
        Hex(AND(target DIV 10000H, 0FFH), 2); Str(":"); Hex(AND(target, 0FFFFH), 4); Ln
      END
    ELSIF op = 0A9H THEN
      w := EmMem.GetByte(addr + 1) + EmMem.GetByte(addr + 2) * 100H;
      IF w = 0 THEN v := varBase
      ELSE m := ImportName(import, w, nofImports);
        IF m # NIL THEN v := m.var
        ELSE Str("Warning: LDA relocation mno "); Int(w); Str(" not found"); Ln; v := 0
        END
      END;
      v := AND(v, 0FFFFH);
      EmMem.SetByte(addr + 1, AND(v, 0FFH)); EmMem.SetByte(addr + 2, v DIV 100H);
      Str("  LDA relocation at $"); Hex(addr, 6); Str(": operand=$"); Hex(w, 4);
      Str(" -> var_base $"); Hex(v, 4); Ln
    ELSIF op = 62H THEN
      w := EmMem.GetByte(addr + 1) + EmMem.GetByte(addr + 2) * 100H;
      mno := w DIV 100H; exno := AND(w, 0FFH);
      m := ImportName(import, mno, nofImports);
      IF m # NIL THEN
        IF (exno > 0) & (exno < m.nofExports) THEN
          target := m.base + m.exports[exno];
          per := AND(target - AND(addr, 0FFFFH) - 3, 0FFFFH);
          EmMem.SetByte(addr + 1, AND(per, 0FFH)); EmMem.SetByte(addr + 2, per DIV 100H);
          Str("  PER import fixup at $"); Hex(addr, 6); Str(": mno="); Int(mno); Str(" exno="); Int(exno);
          Str(" -> "); Str(m.name); Str(" addr=$"); Hex(target, 4); Str(" (PER operand=$"); Hex(per, 4);
          Str(")"); Ln
        ELSE
          Str("  Warning: Invalid exno "); Int(exno); Str(" for module "); Str(m.name);
          Str(" (has "); Int(m.nofExports - 1); Str(" exports)"); Ln
        END
      ELSE Str("Warning: PER relocation mno "); Int(mno); Str(" not found"); Ln
      END
    ELSE
      Str("Warning: Relocation at $"); Hex(addr, 6); Str(" points to unknown opcode $"); Hex(op, 2); Ln
    END
  END Relocate;

  PROCEDURE Error(msg: ARRAY OF CHAR);
  BEGIN Str(msg); Ln
  END Error;

  (* Load the module in the file name; return its entry point (24 bits),
     0 if it could not be loaded. *)
  PROCEDURE LoadMod*(fname: ARRAY OF CHAR): INTEGER;
    VAR f: Files.File; r: Files.Rider; ok, bad, found: BOOLEAN;
      name, impName: Name; depPath: Path;
      import: ARRAY maxImports OF Module; nofImports, missing, si: INTEGER;
      key, version, size, entryPoint, pos, ch, i, n, b, depEntry: INTEGER;
      base, varBase, tdSize, varSize, strSize, strAt, tdAt, codeLength, bankAddress: INTEGER;
      expVal, nofent, fileEntry, expIdx, w: INTEGER;
      exportValues: ARRAY maxExports OF INTEGER;
      fixP, fixD, fixT, tdFixups, offset, mno, exno, lo, hi, addr, vtFixups, relocCount, ra, op, operand: INTEGER;
      bankReloc: BOOLEAN;
      m, info: Module; result, moduleIdx: INTEGER;

    PROCEDURE Check(cond: BOOLEAN; msg: ARRAY OF CHAR; VAR bad: BOOLEAN);
    BEGIN IF ~cond & ~bad THEN Error(msg); bad := TRUE END
    END Check;

  BEGIN result := 0; ok := TRUE; bad := FALSE; entryPoint := 0;
    IF searchDir[0] = 0X THEN
      i := Length(fname) - 1;
      WHILE (i >= 0) & (fname[i] # "/") DO DEC(i) END;
      IF (i >= 0) & (i + 1 < LEN(searchDir)) THEN
        FOR n := 0 TO i DO searchDir[n] := fname[n] END; searchDir[i + 1] := 0X
      END
    END;
    Configured("65C816."); EmCPU.SetStackPage(100H);
    f := Files.Old(fname);
    IF f = NIL THEN Str("Error: Cannot open file "); Str(fname); Ln; bad := TRUE END;
    (* name, key, version, size *)
    IF ~bad THEN
      Files.Set(r, f, 0);
      n := 0; ch := Byte(r, ok);
      WHILE ok & (ch # 0) & (n < 63) DO name[n] := CHR(ch); INC(n); ch := Byte(r, ok) END;
      name[n] := 0X;
      Check(ok, "Error: Unexpected end of file reading module name", bad)
    END;
    IF ~bad THEN
      Str("Module: "); Str(name); Ln;
      key := Word32(r, ok); Check(ok, "Error: Cannot read key", bad)
    END;
    IF ~bad THEN version := Byte(r, ok); Check(ok, "Error: Cannot read version", bad) END;
    IF ~bad THEN size := Word32(r, ok); Check(ok, "Error: Cannot read size", bad) END;
    IF ~bad THEN
      Str("Key: "); Hex(key, 8); Str(", Version: "); Int(version); Str(", Size: "); Int(size); Str(" bytes"); Ln;
      (* the entry point, four bytes before the final "O" *)
      pos := Files.Pos(r);
      IF Files.Length(f) >= 5 THEN
        Files.Set(r, f, Files.Length(f) - 5); entryPoint := Word32(r, ok);
        Str("Entry point: $"); Hex(entryPoint, 4); Str(" ("); Int(entryPoint); Str(")"); Ln
      END;
      Files.Set(r, f, pos); ok := TRUE;
      (* imports: mno 1 is the first *)
      nofImports := 0; missing := 0;
      FOR i := 0 TO maxImports - 1 DO import[i] := NIL END;
      ch := Byte(r, ok);
      WHILE ok & (ch # 0) DO
        ReadName(r, ch, impName);
        Files.Set(r, f, Files.Pos(r) + 4);           (* the key *)
        INC(nofImports);
        IF nofImports < maxImports THEN
          import[nofImports] := Find(impName);
          IF import[nofImports] = NIL THEN
            found := FALSE;
            ModulePath(searchDir, impName, depPath);
            IF EmHost.FileExists(depPath) # 0 THEN found := TRUE END;
            si := 0;
            WHILE ~found & (si < nofPaths) DO
              ModulePath(paths[si], impName, depPath);
              IF EmHost.FileExists(depPath) # 0 THEN found := TRUE END;
              INC(si)
            END;
            IF found THEN
              Str("  Auto-loading dependency: "); Str(depPath); Ln;
              depEntry := LoadMod(depPath);
              IF (depEntry # 0) & (nofEntries < maxModules) THEN entries[nofEntries] := depEntry; INC(nofEntries) END;
              import[nofImports] := Find(impName)
            ELSE
              Str("  Error: Module '"); Str(impName); Str("' not found");
              IF searchDir[0] # 0X THEN Str(" (looked in "); Str(searchDir) END;
              FOR si := 0 TO nofPaths - 1 DO
                IF (si = 0) & (searchDir[0] = 0X) THEN Str(" (looked in ") ELSE Str(", ") END;
                Str(paths[si])
              END;
              Str(")"); Ln
            END
          END;
          IF import[nofImports] # NIL THEN
            Str("  Import mno "); Int(nofImports); Str(": "); Str(impName); Str(" -> loaded at $");
            Hex(import[nofImports].base, 4); Ln
          ELSE
            Str("  Import mno "); Int(nofImports); Str(": "); Str(impName); Str(" -> NOT FOUND"); Ln;
            INC(missing)
          END
        END;
        ch := Byte(r, ok)
      END;
      IF missing > 0 THEN
        EmHost.Drain(out);
        EmHost.Str(err, "Error: "); EmHost.Int(err, missing); EmHost.Str(err, " import(s) could not be resolved for module '");
        EmHost.Str(err, name); EmHost.Str(err, "'."); EmHost.Ln(err);
        EmHost.Str(err, "  Use -I <dir> to specify search paths for module dependencies."); EmHost.Ln(err);
        bad := TRUE
      END
    END;
    IF ~bad THEN
      base := loadAddress; varBase := varAddress;
      Str("Loading module at base address $"); Hex(base, 4); Str(" (bank "); Int(moduleBank); Str(")"); Ln;
      (* type descriptors, which go after the variables and strings (v2) *)
      ok := TRUE; tdSize := Word32(r, ok);
      Check(ok, "Error: Cannot read type descriptor size", bad)
    END;
    IF ~bad THEN
      Check(tdSize <= LEN(tdData), "Error: Cannot read type descriptor data", bad);
      IF ~bad THEN
        FOR i := 0 TO tdSize - 1 DO tdData[i] := Byte(r, ok) END;
        Check(ok, "Error: Cannot read type descriptor data", bad)
      END
    END;
    IF ~bad THEN varSize := Word32(r, ok); Check(ok, "Error: Cannot read variable size", bad) END;
    IF ~bad THEN strSize := Word32(r, ok); Check(ok, "Error: Cannot read string size", bad) END;
    IF ~bad THEN
      Str("String length: "); Int(strSize); Str(" bytes"); Ln;
      IF strSize > 0 THEN
        IF version >= 2 THEN strAt := varSize ELSE strAt := tdSize + varSize END;
        FOR i := 0 TO strSize - 1 DO b := Byte(r, ok); EmMem.SetByte(varBase + strAt + i, b) END;
        Check(ok, "Error: Cannot read string section", bad)
      END
    END;
    IF ~bad THEN
      IF tdSize > 0 THEN
        IF version >= 2 THEN tdAt := varSize + strSize ELSE tdAt := 0 END;
        FOR i := 0 TO tdSize - 1 DO EmMem.SetByte(varBase + tdAt + i, tdData[i]) END;
        Str("Type descriptors: "); Int(tdSize); Str(" bytes loaded at $"); Hex(varBase + tdAt, 4); Ln
      END;
      (* the code, which must not straddle a bank *)
      codeLength := Word32(r, ok); Check(ok, "Error: Cannot read code length", bad)
    END;
    IF ~bad THEN
      Str("Code length: "); Int(codeLength); Str(" bytes"); Ln;
      IF AND(base, bankSize - 1) + codeLength > bankSize THEN
        base := AND(base, -bankSize) + bankSize; loadAddress := base;
        Str("  (bumped to bank boundary: base now $"); Hex(moduleBank * bankSize + base, 6); Str(")"); Ln
      END;
      bankAddress := moduleBank * bankSize;
      Check(Files.Pos(r) + codeLength <= Files.Length(f), "Error: Cannot read code section", bad)
    END;
    IF ~bad THEN
      Str("Loading code at bank "); Int(moduleBank); Str(":$"); Hex(base, 4);
      Str(" (absolute $"); Hex(bankAddress + base, 6); Str(")"); Ln;
      FOR i := 0 TO codeLength - 1 DO EmMem.SetByte(bankAddress + base + i, Byte(r, ok)) END;
      (* the commands: name and value *)
      Str("Exports:"); Ln;
      ch := Byte(r, ok);
      WHILE ok & (ch # 0) DO
        ReadName(r, ch, impName); expVal := Word32(r, ok);
        Str("  "); Str(impName); Str(" = $"); Hex(expVal, 4); Ln;
        ch := Byte(r, ok)
      END;
      ok := TRUE; nofent := Word32(r, ok); fileEntry := Word32(r, ok);
      Check(ok, "Error: Cannot read nofent/entry", bad)
    END;
    IF ~bad THEN
      Str("nofent: "); Int(nofent); Str(", entry: $"); Hex(fileEntry, 4); Ln;
      (* the entries, by export number from 1, up to -1 *)
      FOR i := 0 TO maxExports - 1 DO exportValues[i] := 0 END;
      expIdx := 1; w := Word32(r, ok);
      WHILE ok & (w # -1) DO
        IF expIdx < maxExports THEN
          exportValues[expIdx] := w; Str("  export["); Int(expIdx); Str("] = $"); Hex(w, 4); Ln; INC(expIdx)
        END;
        w := Word32(r, ok)
      END;
      ok := TRUE; fixP := Word32(r, ok); fixD := Word32(r, ok); fixT := Word32(r, ok);
      Check(ok, "Error reading fixup information", bad)
    END;
    IF ~bad THEN
      (* type descriptor fixups: ancestors in this or an imported module *)
      tdFixups := Word32(r, ok); Check(ok, "Error reading TD fixup count", bad)
    END;
    IF ~bad & (tdFixups > 0) THEN
      Str("Processing "); Int(tdFixups); Str(" TD fixups:"); Ln;
      i := 0;
      WHILE i < tdFixups DO
        offset := Word16(r, ok); mno := Word16(r, ok);
        IF ~ok THEN Str("Error reading TD fixup entry "); Int(i); Ln; i := tdFixups
        ELSE
          lo := EmMem.GetWord(varBase + offset); hi := EmMem.GetWord(varBase + offset + 2);
          addr := hi * 10000H + lo;
          IF mno = 0 THEN w := varBase
          ELSE m := ImportName(import, mno, nofImports);
            IF m # NIL THEN w := m.var ELSE w := 0; Str("  Warning: TD fixup mno "); Int(mno); Str(" not resolved"); Ln END
          END;
          addr := addr + AND(w, 0FFFFH);
          EmMem.SetWord(varBase + offset, AND(addr, 0FFFFH));
          EmMem.SetWord(varBase + offset + 2, AND(LSR(addr, 16), 0FFFFH));
          Str("  TD fixup["); Int(i); Str("]: offset="); Int(offset); Str(" mno="); Int(mno);
          Str(" -> $"); Hex(AND(addr, 0FFFFH), 4); Ln;
          INC(i)
        END
      END
    END;
    (* method tables (v2): own methods by offset, inherited ones by export *)
    IF ~bad & (version >= 2) THEN
      vtFixups := Word32(r, ok); Check(ok, "Error reading vtable fixup count", bad);
      IF ~bad & (vtFixups > 0) THEN
        Str("Processing "); Int(vtFixups); Str(" vtable fixups:"); Ln;
        i := 0;
        WHILE i < vtFixups DO
          offset := Word32(r, ok); mno := Word16(r, ok); exno := Word16(r, ok);
          IF ~ok THEN Str("Error reading vtable fixup entry "); Int(i); Ln; i := vtFixups
          ELSE
            IF mno = 0 THEN
              w := EmMem.GetWord(varBase + offset); addr := AND(base + w, 0FFFFH);
              EmMem.SetWord(varBase + offset, addr);
              Str("  vtable fixup["); Int(i); Str("]: offset="); Int(offset); Str(" own off=$"); Hex(w, 4);
              Str(" -> $"); Hex(addr, 4); Ln
            ELSE m := ImportName(import, mno, nofImports);
              IF m # NIL THEN
                IF (exno > 0) & (exno < m.nofExports) THEN
                  addr := AND(m.base + m.exports[exno], 0FFFFH);
                  EmMem.SetWord(varBase + offset, addr);
                  Str("  vtable fixup["); Int(i); Str("]: offset="); Int(offset); Str(" mno="); Int(mno);
                  Str(" exno="); Int(exno); Str(" -> "); Str(m.name); Str(" $"); Hex(addr, 4); Ln
                ELSE
                  Str("  Warning: vtable fixup invalid exno "); Int(exno); Str(" for module "); Str(m.name); Ln
                END
              ELSE Str("  Warning: vtable fixup mno "); Int(mno); Str(" not resolved"); Ln
              END
            END;
            INC(i)
          END
        END
      END
    END;
    IF ~bad THEN
      (* the module is known before its relocations are done *)
      NEW(info); info.name := name;
      info.bank := AND((moduleBank * bankSize + base) DIV 10000H, 0FFH);
      info.base := base; info.var := varBase; info.size := codeLength;
      info.entry := entryPoint + base; info.nofExports := expIdx;
      FOR i := 0 TO maxExports - 1 DO info.exports[i] := exportValues[i] END;
      info.next := modules; modules := info;
      moduleIdx := moduleIndex; INC(moduleIndex);
      EmMem.SetByte(moduleTable + moduleIdx * 2, AND(varBase, 0FFH));
      EmMem.SetByte(moduleTable + moduleIdx * 2 + 1, AND(varBase DIV 100H, 0FFH));
      Str("Module "); Str(name); Str(" loaded: Bank "); Int(info.bank); Str(", Code $"); Hex(base, 4);
      Str("-$"); Hex(base + codeLength - 1, 4); Str(", Vars $"); Hex(varBase, 4); Str(", Entry $");
      Hex(info.entry, 4); Str(", MT["); Int(moduleIdx); Str("]=$"); Hex(varBase, 4); Ln;
      (* relocations; bit 31 marks a data bank operand *)
      ok := TRUE; relocCount := Word32(r, ok);
      IF ok THEN
        IF (relocCount >= 0) & (relocCount < 65536) THEN
          Str("Processing "); Int(relocCount); Str(" relocations:"); Ln;
          FOR i := 0 TO relocCount - 1 DO
            w := Word32(r, ok);
            IF ok THEN
              bankReloc := w < 0;
              IF bankReloc THEN w := AND(w, 7FFFFFFFH) END;
              ra := bankAddress + base + w;
              IF bankReloc THEN op := EmMem.GetByte(ra);
                IF op = 0A9H THEN
                  operand := EmMem.GetByte(ra + 1) + EmMem.GetByte(ra + 2) * 100H;
                  EmMem.SetByte(ra + 1, 0); EmMem.SetByte(ra + 2, 0);
                  Str("  BANK relocation at $"); Hex(ra, 6); Str(": operand=$"); Hex(operand, 4);
                  Str(" -> bank $"); Hex(0, 4); Ln
                ELSE
                  Str("Warning: Bank relocation at $"); Hex(ra, 6); Str(" points to unknown opcode $"); Hex(op, 2); Ln
                END
              ELSE Relocate(ra, base, varBase, import, nofImports)
              END
            END
          END;
          IF relocCount > 0 THEN Ln END;
          loadAddress := loadAddress + codeLength;
          varAddress := varAddress + tdSize + varSize + strSize
        ELSE Str("Invalid relocation count: "); Int(relocCount); Ln
        END
      END;
      result := moduleBank * bankSize + base + entryPoint;
      Str("Entry point: Bank "); Int(AND(result DIV 10000H, 0FFH)); Str(":$"); Hex(AND(result, 0FFFFH), 4);
      Str(" (24-bit: $"); Hex(result, 6); Str(")"); Ln;
      Str("Module loaded successfully"); Ln; Ln
    END;
    RETURN result
  END LoadMod;

  PROCEDURE ClearEntries*;
  BEGIN nofEntries := 0
  END ClearEntries;

  (* A module's initialisation, to be run (0: none). *)
  PROCEDURE AddEntry*(e: INTEGER);
  BEGIN IF nofEntries < maxModules THEN entries[nofEntries] := e; INC(nofEntries) END
  END AddEntry;

  (* --- the manifest --- *)

  PROCEDURE Put(VAR a: INTEGER; v, n: INTEGER);       (* n bytes of v, little endian *)
    VAR i: INTEGER;
  BEGIN FOR i := 1 TO n DO EmMem.SetByte(a, AND(v, 0FFH)); v := LSR(v, 8); INC(a) END
  END Put;

  (* At $0D00 for OS16's Modules: the number of modules, then for each in
     load order its name, bank, base (24 bits), variables, exports; then
     where the next module's code and variables go. *)
  PROCEDURE WriteManifest*;
    VAR m: Module; list: ARRAY maxModules OF Module; n, i, j, addr, k: INTEGER;
  BEGIN addr := manifestBase; n := 0; m := modules;
    WHILE (m # NIL) & (n < maxModules) DO list[n] := m; INC(n); m := m.next END;
    Put(addr, n, 2);
    FOR i := n - 1 TO 0 BY -1 DO m := list[i]; j := 0;
      WHILE m.name[j] # 0X DO EmMem.SetByte(addr, ORD(m.name[j])); INC(addr); INC(j) END;
      EmMem.SetByte(addr, 0); INC(addr);
      Put(addr, m.bank, 2);
      Put(addr, moduleBank * bankSize + m.base, 4);
      Put(addr, m.var, 2);
      IF m.nofExports > 0 THEN k := m.nofExports - 1 ELSE k := 0 END;
      Put(addr, k, 2);
      j := 1;
      WHILE (j < m.nofExports) & (j <= maxExports) DO Put(addr, m.exports[j], 2); INC(j) END
    END;
    Put(addr, moduleBank * bankSize + loadAddress, 4);
    Put(addr, varAddress, 2);
    Str("Boot manifest: "); Int(n); Str(" modules, "); Int(addr - manifestBase); Str(" bytes at $");
    Hex(manifestBase, 4); Str("-$"); Hex(addr - 1, 4); Str(" (nextCode=$"); Hex(loadAddress, 4);
    Str(" nextVar=$"); Hex(varAddress, 4); Str(")"); Ln
  END WriteManifest;

  (* --- the run time's traps --- *)

  PROCEDURE HeapAlloc(size: INTEGER): INTEGER;
    VAR addr, i: INTEGER;
  BEGIN size := AND(size + 1, 0FFFEH);
    IF heapTop + size > heapLimit THEN Str("OUT OF MEMORY"); Ln; addr := 0
    ELSE addr := heapTop; heapTop := heapTop + size;
      FOR i := 0 TO size - 1 DO EmMem.SetByte(heapBank * 10000H + AND(addr + i, 0FFFFH), 0) END;
      addr := AND(addr, 0FFFFH)
    END;
    RETURN addr
  END HeapAlloc;

  (* BRK #0 stops (a module's initialisation has returned); #10 is NEW:
     A = size, returns A = address and X = bank; the rest are run time
     errors. *)
  PROCEDURE Trap(n: INTEGER);
  BEGIN
    IF n = 0 THEN EmCPU.Stop
    ELSIF n = 10 THEN EmCPU.SetA(HeapAlloc(EmCPU.GetA())); EmCPU.SetX(heapBank)
    ELSE
      Str("TRAP "); Int(n); Str(" at "); Hex(EmCPU.GetPBR(), 2); Str(":"); Hex(EmCPU.GetPC() - 2, 4); Ln;
      EmCPU.Stop
    END
  END Trap;

  PROCEDURE InitHeap*;
  BEGIN heapTop := varAddress; heapBank := 0;
    Str("Heap initialized at $"); Hex(heapTop, 4); Str(" (bank "); Int(heapBank); Str(")"); Ln;
    EmCPU.SetTrapHandler(Trap)
  END InitHeap;

BEGIN
  modules := NIL; loadAddress := 0; varAddress := moduleVarBase; moduleIndex := 0;
  nofEntries := 0; searchDir[0] := 0X; nofPaths := 0;
  heapTop := 0; heapBank := 0; heapLimit := 0BFFFH
END EmLoad.
