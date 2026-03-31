MODULE Modules;
  IMPORT SYSTEM, Files, Out;

  CONST
    MaxModules* = 16;
    MaxExports = 64;
    MaxImports = 16;
    MaxPaths = 4;
    CodeBank = 1;
    BankSize = 10000H;
    VarBase = 1000H;
    ModTableBase = 0E00H;
    ManifestBase = 0D00H;

  TYPE
    ModName* = ARRAY 32 OF CHAR;
    PathName = ARRAY 64 OF CHAR;

  VAR
    names: ARRAY MaxModules OF ModName;
    banks: ARRAY MaxModules OF INTEGER;
    baseAddrs: ARRAY MaxModules OF INTEGER;
    varAddrs: ARRAY MaxModules OF INTEGER;
    exportCounts: ARRAY MaxModules OF INTEGER;
    exports: ARRAY MaxModules, MaxExports OF INTEGER;
    count*: INTEGER;
    loadAddr: INTEGER;
    varAddr: INTEGER;
    paths: ARRAY MaxPaths OF PathName;
    pathCount: INTEGER;

  (* ---- String helpers ---- *)

  PROCEDURE StrEq(VAR a, b: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER; eq: BOOLEAN;
  BEGIN
    i := 0; eq := TRUE;
    WHILE eq & (i < LEN(a)) & (i < LEN(b)) & (a[i] # 0X) DO
      IF a[i] # b[i] THEN eq := FALSE
      ELSE INC(i)
      END
    END;
    IF eq THEN
      (* Check both are at null *)
      IF (i < LEN(a)) & (a[i] # 0X) THEN eq := FALSE
      ELSIF (i < LEN(b)) & (b[i] # 0X) THEN eq := FALSE
      END
    END
  RETURN eq
  END StrEq;

  PROCEDURE Find(VAR name: ARRAY OF CHAR): INTEGER;
    VAR i, result: INTEGER;
  BEGIN
    result := -1; i := 0;
    WHILE (i < count) & (result < 0) DO
      IF StrEq(names[i], name) THEN result := i END;
      INC(i)
    END
  RETURN result
  END Find;

  PROCEDURE StrLen(VAR s: ARRAY OF CHAR): INTEGER;
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END
  RETURN i
  END StrLen;

  PROCEDURE CopyStr(VAR src: ARRAY OF CHAR; VAR dst: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(src)) & (i < LEN(dst) - 1) & (src[i] # 0X) DO
      dst[i] := src[i]; INC(i)
    END;
    dst[i] := 0X
  END CopyStr;

  PROCEDURE AppendStr(VAR src: ARRAY OF CHAR; VAR dst: ARRAY OF CHAR);
    VAR i, j: INTEGER;
  BEGIN
    j := StrLen(dst);
    i := 0;
    WHILE (i < LEN(src)) & (j < LEN(dst) - 1) & (src[i] # 0X) DO
      dst[j] := src[i]; INC(i); INC(j)
    END;
    dst[j] := 0X
  END AppendStr;

  (* ---- File format helpers ---- *)

  PROCEDURE ReadLong(VAR r: Files.Rider; VAR x: INTEGER);
    VAR hi: INTEGER;
  BEGIN
    Files.ReadInt(r, x);
    Files.ReadInt(r, hi);
    IF hi # 0 THEN
      Out.String("LONG!"); Out.Ln
    END
  END ReadLong;

  PROCEDURE SkipLong(VAR r: Files.Rider);
    VAR dummy: INTEGER;
  BEGIN
    ReadLong(r, dummy)
  END SkipLong;

  PROCEDURE SkipBytes(VAR r: Files.Rider; n: INTEGER);
    VAR b: BYTE; i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < n) & ~r.eof DO
      Files.Read(r, b); INC(i)
    END
  END SkipBytes;

  (* ---- Bank memory access ---- *)

  PROCEDURE GetByte(bank, addr: INTEGER): INTEGER;
    VAR b: BYTE; v: INTEGER;
  BEGIN
    SYSTEM.GET(bank, addr, b);
    v := b
  RETURN v
  END GetByte;

  PROCEDURE PutByte(bank, addr, val: INTEGER);
    VAR b: BYTE;
  BEGIN
    b := val;
    SYSTEM.PUT(bank, addr, b)
  END PutByte;

  PROCEDURE GetWord(bank, addr: INTEGER): INTEGER;
    VAR lo, hi: INTEGER;
  BEGIN
    lo := GetByte(bank, addr);
    hi := GetByte(bank, addr + 1)
  RETURN ORA(lo, ASL(hi, 8))
  END GetWord;

  PROCEDURE PutWord(bank, addr, val: INTEGER);
  BEGIN
    PutByte(bank, addr, AND(val, 0FFH));
    PutByte(bank, addr + 1, AND(LSR(val, 8), 0FFH))
  END PutWord;

  (* ---- Search path management ---- *)

  PROCEDURE AddPath*(VAR path: ARRAY OF CHAR);
  BEGIN
    IF pathCount < MaxPaths THEN
      CopyStr(path, paths[pathCount]);
      INC(pathCount)
    END
  END AddPath;

  (* ---- Relocation engine ---- *)

  PROCEDURE ApplyBankReloc(bankAddr, modVarBase: INTEGER;
                           VAR impMap: ARRAY OF INTEGER; impCount: INTEGER);
    VAR opcode, operand, varBank: INTEGER;
  BEGIN
    opcode := GetByte(CodeBank, bankAddr);
    IF opcode = 0A9H THEN  (* LDA #imm16 *)
      operand := GetWord(CodeBank, bankAddr + 1);
      varBank := 0;  (* data always in bank 0 *)
      PutWord(CodeBank, bankAddr + 1, varBank)
    END
  END ApplyBankReloc;

  PROCEDURE ApplyReloc(bankAddr, modBase, modVarBase: INTEGER;
                       VAR impMap: ARRAY OF INTEGER; impCount: INTEGER);
    VAR opcode, addr, bankByte, mno, exno: INTEGER;
        targetIdx, targetAddr, fullAddr, varBase: INTEGER;
        perAddr, perOffset, operand: INTEGER;
  BEGIN
    opcode := GetByte(CodeBank, bankAddr);

    IF opcode = 20H THEN  (* JSR - intra-module *)
      addr := GetWord(CodeBank, bankAddr + 1);
      addr := addr + modBase;
      PutWord(CodeBank, bankAddr + 1, addr)

    ELSIF opcode = 22H THEN  (* JSL - 3-byte address *)
      bankByte := GetByte(CodeBank, bankAddr + 3);
      addr := GetWord(CodeBank, bankAddr + 1);
      IF (bankByte > 0) & (bankByte <= impCount) & (impMap[bankByte] >= 0) THEN
        (* Inter-module import *)
        mno := bankByte;
        exno := addr;
        targetIdx := impMap[mno];
        IF (exno > 0) & (exno < exportCounts[targetIdx]) THEN
          targetAddr := exports[targetIdx, exno];
          fullAddr := baseAddrs[targetIdx] + targetAddr;
          PutWord(CodeBank, bankAddr + 1, fullAddr);
          PutByte(CodeBank, bankAddr + 3, banks[targetIdx])
        ELSE
          Out.String("JSL: bad exno "); Out.Int(exno, 1); Out.Ln
        END
      ELSE
        (* Intra-module *)
        addr := addr + modBase;
        PutWord(CodeBank, bankAddr + 1, addr);
        PutByte(CodeBank, bankAddr + 3, CodeBank)
      END

    ELSIF opcode = 0A9H THEN  (* LDA #imm16 - var base reloc *)
      operand := GetWord(CodeBank, bankAddr + 1);
      IF operand = 0 THEN
        varBase := modVarBase
      ELSE
        mno := operand;
        IF (mno <= impCount) & (impMap[mno] >= 0) THEN
          varBase := varAddrs[impMap[mno]]
        ELSE
          varBase := 0;
          Out.String("LDA: mno not found "); Out.Int(mno, 1); Out.Ln
        END
      END;
      PutWord(CodeBank, bankAddr + 1, varBase)

    ELSIF opcode = 62H THEN  (* PER - imported procedure variable *)
      operand := GetWord(CodeBank, bankAddr + 1);
      mno := AND(LSR(operand, 8), 0FFH);
      exno := AND(operand, 0FFH);
      IF (mno > 0) & (mno <= impCount) & (impMap[mno] >= 0) THEN
        targetIdx := impMap[mno];
        IF (exno > 0) & (exno < exportCounts[targetIdx]) THEN
          targetAddr := baseAddrs[targetIdx] + exports[targetIdx, exno];
          perAddr := bankAddr;
          perOffset := targetAddr - perAddr - 3;
          PutWord(CodeBank, bankAddr + 1, perOffset)
        END
      END

    ELSE
      Out.String("Reloc: unknown opcode "); Out.Hex(opcode); Out.Ln
    END
  END ApplyReloc;

  (* ---- Main Load procedure ---- *)

  PROCEDURE BuildPath(VAR dir, name, out: ARRAY OF CHAR);
    VAR i, j: INTEGER;
  BEGIN
    i := 0; j := 0;
    WHILE (j < LEN(dir)) & (dir[j] # 0X) & (i < LEN(out) - 5) DO
      out[i] := dir[j]; INC(i); INC(j)
    END;
    j := 0;
    WHILE (j < LEN(name)) & (name[j] # 0X) & (i < LEN(out) - 5) DO
      out[i] := name[j]; INC(i); INC(j)
    END;
    out[i] := "."; INC(i);
    out[i] := "8"; INC(i);
    out[i] := "1"; INC(i);
    out[i] := "6"; INC(i);
    out[i] := 0X
  END BuildPath;

  PROCEDURE Load*(name: ARRAY OF CHAR; VAR res: INTEGER);
    VAR f: Files.File;
        r: Files.Rider;
        nm: ARRAY 64 OF CHAR;
        path: ARRAY 64 OF CHAR;
        modName: ModName;
        impNames: ARRAY MaxImports OF ModName;
        impMap: ARRAY MaxImports OF INTEGER;
        impCount: INTEGER;
        found: BOOLEAN;
        i, j, pi: INTEGER;
        b: BYTE;
        key, version, size: INTEGER;
        modBase, modVarBase: INTEGER;
        tdSize, varSize, strSize, codeLen: INTEGER;
        nofent, entryPoint: INTEGER;
        expIdx, expVal: INTEGER;
        relocCount, relocAddr, relocHi, actualAddr: INTEGER;
        bankAddr: INTEGER;
        isBankReloc: BOOLEAN;
        tdFixupCount, byteOffset, fixMno: INTEGER;
        lo, hi, tdAddr: INTEGER;
        fixVarBase: INTEGER;
        depRes: INTEGER;
  BEGIN
    res := 0;
    (* Copy name to local for use with VAR-param procs *)
    i := 0;
    WHILE (i < LEN(name)) & (i < 63) & (name[i] # 0X) DO
      nm[i] := name[i]; INC(i)
    END;
    nm[i] := 0X;

    IF Find(nm) >= 0 THEN
      (* Already loaded *)
    ELSE
      (* Search for module file *)
      f := NIL;
      pi := 0;
      WHILE (pi < pathCount) & (f = NIL) DO
        BuildPath(paths[pi], nm, path);
        f := Files.Old(path);
        INC(pi)
      END;

      IF f = NIL THEN
        Out.String("Module not found: "); Out.String(nm); Out.Ln;
        res := -1
      ELSE
        Files.Set(r, f, 0);

        (* Read module name *)
        Files.ReadString(r, modName);

        (* Read key (4 bytes) *)
        ReadLong(r, key);

        (* Read version (1 byte) *)
        Files.Read(r, b);
        version := b;

        (* Read size (4 bytes) *)
        ReadLong(r, size);

        (* Parse imports *)
        impCount := 0;
        i := 0;
        WHILE i < MaxImports DO impMap[i] := -1; INC(i) END;

        Files.Read(r, b);
        WHILE (b # 0) & ~r.eof DO
          INC(impCount);
          (* Read import name - first byte already in b *)
          IF impCount < MaxImports THEN
            i := 0;
            impNames[impCount][0] := CHR(b);
            i := 1;
            Files.Read(r, b);
            WHILE (b # 0) & ~r.eof & (i < 31) DO
              impNames[impCount][i] := CHR(b);
              INC(i);
              Files.Read(r, b)
            END;
            (* Skip remaining name chars if longer than 31 *)
            WHILE (b # 0) & ~r.eof DO Files.Read(r, b) END;
            impNames[impCount][i] := 0X;
            (* Skip key (4 bytes) *)
            SkipLong(r);

            (* Find or auto-load dependency *)
            impMap[impCount] := Find(impNames[impCount]);
            IF impMap[impCount] < 0 THEN
              Load(impNames[impCount], depRes);
              IF depRes = 0 THEN
                impMap[impCount] := Find(impNames[impCount]);
                IF impMap[impCount] < 0 THEN
                  Out.String("Import not resolved: ");
                  Out.String(impNames[impCount]); Out.Ln;
                  res := -2
                END
              ELSE
                Out.String("Failed to load dep: ");
                Out.String(impNames[impCount]); Out.Ln;
                res := -2
              END
            END
          ELSE
            (* Skip this import entry *)
            WHILE (b # 0) & ~r.eof DO Files.Read(r, b) END;
            SkipLong(r)
          END;
          Files.Read(r, b)  (* Read first byte of next import or 0 *)
        END;

        IF res = 0 THEN
          (* Snapshot base addresses (after recursive loads advanced them) *)
          modBase := loadAddr;
          modVarBase := varAddr;

          (* Read type descriptors *)
          ReadLong(r, tdSize);
          IF tdSize > 0 THEN
            i := 0;
            WHILE (i < tdSize) & ~r.eof DO
              Files.Read(r, b);
              PutByte(0, modVarBase + i, b);
              INC(i)
            END
          END;

          (* Read var_size *)
          ReadLong(r, varSize);

          (* Read string section *)
          ReadLong(r, strSize);
          IF strSize > 0 THEN
            i := 0;
            WHILE (i < strSize) & ~r.eof DO
              Files.Read(r, b);
              PutByte(0, modVarBase + tdSize + varSize + i, b);
              INC(i)
            END
          END;

          (* Read code section into bank 1 *)
          ReadLong(r, codeLen);
          i := 0;
          WHILE (i < codeLen) & ~r.eof DO
            Files.Read(r, b);
            PutByte(CodeBank, modBase + i, b);
            INC(i)
          END;

          (* Skip export procedures (name + value pairs until null) *)
          Files.Read(r, b);
          WHILE (b # 0) & ~r.eof DO
            (* Skip procedure name *)
            WHILE (b # 0) & ~r.eof DO Files.Read(r, b) END;
            (* Skip value (4 bytes) *)
            SkipLong(r);
            Files.Read(r, b)
          END;

          (* Read nofent and entry point *)
          ReadLong(r, nofent);
          ReadLong(r, entryPoint);

          (* Read export values until -1 sentinel *)
          expIdx := 1;
          ReadLong(r, expVal);
          WHILE (expVal # -1) & ~r.eof & (expIdx < MaxExports) DO
            exports[count, expIdx] := expVal;
            INC(expIdx);
            ReadLong(r, expVal)
          END;
          exportCounts[count] := expIdx;

          (* Skip fixorgP, fixorgD, fixorgT *)
          SkipLong(r); SkipLong(r); SkipLong(r);

          (* Process TD fixups *)
          ReadLong(r, tdFixupCount);
          i := 0;
          WHILE (i < tdFixupCount) & ~r.eof DO
            Files.ReadInt(r, byteOffset);
            Files.ReadInt(r, fixMno);
            lo := GetWord(0, modVarBase + byteOffset);
            hi := GetWord(0, modVarBase + byteOffset + 2);
            IF fixMno = 0 THEN
              fixVarBase := modVarBase
            ELSIF (fixMno <= impCount) & (impMap[fixMno] >= 0) THEN
              fixVarBase := varAddrs[impMap[fixMno]]
            ELSE
              fixVarBase := 0
            END;
            tdAddr := lo + fixVarBase;
            PutWord(0, modVarBase + byteOffset, tdAddr);
            (* hi word gets fixVarBase high bits if needed (usually 0) *)
            PutWord(0, modVarBase + byteOffset + 2, hi);
            INC(i)
          END;

          (* Register module in tracking arrays *)
          CopyStr(modName, names[count]);
          banks[count] := CodeBank;
          baseAddrs[count] := modBase;
          varAddrs[count] := modVarBase;

          (* Write module table entry *)
          PutWord(0, ModTableBase + count * 2, modVarBase);

          (* Process relocation table *)
          ReadLong(r, relocCount);
          i := 0;
          WHILE (i < relocCount) & ~r.eof DO
            Files.ReadInt(r, relocAddr);
            Files.ReadInt(r, relocHi);
            isBankReloc := (relocHi < 0);
            actualAddr := relocAddr;
            bankAddr := modBase + actualAddr;
            IF isBankReloc THEN
              ApplyBankReloc(bankAddr, modVarBase, impMap, impCount)
            ELSE
              ApplyReloc(bankAddr, modBase, modVarBase, impMap, impCount)
            END;
            INC(i)
          END;

          (* Update load addresses for next module *)
          loadAddr := loadAddr + codeLen;
          varAddr := varAddr + tdSize + varSize + strSize;
          INC(count);

          Files.Close(f);

          (* Execute module initialization *)
          Out.String("Exec "); Out.String(modName);
          Out.String(" at "); Out.Hex(modBase + entryPoint); Out.Ln;
          SYSTEM.EXEC(modBase + entryPoint, CodeBank)
        ELSE
          Files.Close(f)
        END
      END
    END
  END Load;

  (* ---- Init: read boot manifest ---- *)

  PROCEDURE ReadManifest;
    VAR maddr, mc, i, j, b, ec: INTEGER;
        ch: INTEGER;
  BEGIN
    maddr := ManifestBase;
    mc := GetWord(0, maddr);
    maddr := maddr + 2;
    i := 0;
    WHILE i < mc DO
      (* Read name (null-terminated) *)
      j := 0;
      ch := GetByte(0, maddr); INC(maddr);
      WHILE (ch # 0) & (j < 31) DO
        names[count][j] := CHR(ch);
        INC(j);
        ch := GetByte(0, maddr); INC(maddr)
      END;
      (* Skip remaining chars if name > 31 *)
      WHILE ch # 0 DO
        ch := GetByte(0, maddr); INC(maddr)
      END;
      names[count][j] := 0X;

      (* Read bank *)
      banks[count] := GetWord(0, maddr); maddr := maddr + 2;
      (* Read base_addr *)
      baseAddrs[count] := GetWord(0, maddr); maddr := maddr + 2;
      (* Read var_addr *)
      varAddrs[count] := GetWord(0, maddr); maddr := maddr + 2;
      (* Read export_count (number of export values written) *)
      ec := GetWord(0, maddr); maddr := maddr + 2;
      exportCounts[count] := ec + 1;  (* match C++ export_count: exno < export_count *)
      (* Read export values (indices 1..ec) *)
      j := 1;
      WHILE (j <= ec) & (j < MaxExports) DO
        exports[count, j] := GetWord(0, maddr); maddr := maddr + 2;
        INC(j)
      END;

      INC(count); INC(i)
    END;

    (* Read next available load addresses (written by emulator after module entries) *)
    loadAddr := GetWord(0, maddr); maddr := maddr + 2;
    varAddr := GetWord(0, maddr); maddr := maddr + 2
  END ReadManifest;

BEGIN
  count := 0;
  loadAddr := 0;
  varAddr := VarBase;
  pathCount := 0;
  paths[0] := "Library/Modules/";
  pathCount := 1;
  ReadManifest
END Modules.
