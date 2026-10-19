MODULE ModuleLoader; (* Loads, relocates and links .816 modules from the file
   system at run time (model: ModuleLoader). *)
  IMPORT SYSTEM, FatFS, Out;

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
    baseAddrs: ARRAY MaxModules OF LONGINT;    (* 24-bit module code base *)
    varAddrs: ARRAY MaxModules OF INTEGER;
    exportCounts: ARRAY MaxModules OF INTEGER;
    exports: ARRAY MaxModules, MaxExports OF INTEGER;
    entries: ARRAY MaxModules OF INTEGER;   (* per-module entry offset — kept for linking *)
    count*: INTEGER;
    loadAddr: LONGINT;                        (* 24-bit next-code pointer *)
    varAddr: INTEGER;
    linkBase: INTEGER;   (* Find() lower bound; MakeImage raises it so a linked
                            kernel re-links its own copies and stays self-contained *)
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
    result := -1; i := linkBase;
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

  (* Read a 32-bit little-endian .816 field as a full LONGINT — used for the
     section sizes (td/var/str/code), which can exceed 64 KB, so read loops and
     cross-section file positioning stay correct. *)
  PROCEDURE ReadLong(VAR r: FatFS.Rider; VAR x: LONGINT);
    VAR lo, hi: INTEGER; xh: LONGINT;
  BEGIN
    FatFS.ReadInt(r, lo);
    FatFS.ReadInt(r, hi);
    x := lo;                    (* sign-extends: undo it (sizes are >= 0) *)
    IF x < 0 THEN x := x + 10000H END;
    xh := hi; x := x + xh * 10000H
  END ReadLong;

  (* Read a 32-bit field but keep only the low 16 bits — for values the loader
     handles as 16-bit within-bank quantities (offsets, counts, identity). *)
  PROCEDURE ReadLong16(VAR r: FatFS.Rider; VAR x: INTEGER);
    VAR hi: INTEGER;
  BEGIN FatFS.ReadInt(r, x); FatFS.ReadInt(r, hi)
  END ReadLong16;

  PROCEDURE SkipLong(VAR r: FatFS.Rider);
    VAR dummy: INTEGER;
  BEGIN ReadLong16(r, dummy)
  END SkipLong;

  PROCEDURE SkipBytes(VAR r: FatFS.Rider; n: INTEGER);
    VAR b: BYTE; i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < n) & ~r.eof DO
      FatFS.Read(r, b); INC(i)
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

  (* ---- 24-bit access: a LONGINT address is split into bank:offset per byte,
     so a value straddling a bank boundary reads/writes correctly. ---- *)

  PROCEDURE GetB(a: LONGINT): INTEGER;
  BEGIN RETURN GetByte(a DIV 10000H, a MOD 10000H)
  END GetB;

  PROCEDURE PutB(a: LONGINT; val: INTEGER);
  BEGIN PutByte(a DIV 10000H, a MOD 10000H, val)
  END PutB;

  PROCEDURE GetW(a: LONGINT): INTEGER;
  BEGIN RETURN ORA(GetB(a), ASL(GetB(a + 1), 8))
  END GetW;

  PROCEDURE PutW(a: LONGINT; val: INTEGER);
  BEGIN PutB(a, AND(val, 0FFH)); PutB(a + 1, AND(LSR(val, 8), 0FFH))
  END PutW;

  (* Read a 24/32-bit LE value (two words) from the bank-0 boot manifest. *)
  PROCEDURE Get24(a: INTEGER): LONGINT;
    VAR lo, hi: LONGINT;
  BEGIN lo := GetWord(0, a); hi := GetWord(0, a + 2); RETURN lo + hi * 10000H
  END Get24;

  (* ---- Search path management ---- *)

  PROCEDURE AddPath*(VAR path: ARRAY OF CHAR);
  BEGIN
    IF pathCount < MaxPaths THEN
      CopyStr(path, paths[pathCount]);
      INC(pathCount)
    END
  END AddPath;

  (* ---- Relocation engine ---- *)

  PROCEDURE ApplyBankReloc(bankAddr: LONGINT; modVarBase: INTEGER;
                           VAR impMap: ARRAY OF INTEGER; impCount: INTEGER);
  BEGIN
    IF GetB(bankAddr) = 0A9H THEN  (* LDA #imm16 — data bank is always 0 *)
      PutW(bankAddr + 1, 0)
    END
  END ApplyBankReloc;

  (* Relocate one site at the 24-bit address bankAddr in a module whose code base
     is the 24-bit modBase. Modules are placed wholly within one bank, so JSR and
     PER stay in-bank (16-bit); JSL carries a full 24-bit target. *)
  PROCEDURE ApplyReloc(bankAddr, modBase: LONGINT; modVarBase: INTEGER;
                       VAR impMap: ARRAY OF INTEGER; impCount: INTEGER);
    VAR opcode, addr, bankByte, mno, exno, targetIdx, varBase, operand: INTEGER;
        targetA: LONGINT;
  BEGIN
    opcode := GetB(bankAddr);

    IF opcode = 20H THEN  (* JSR — intra-module, in-bank 16-bit *)
      addr := GetW(bankAddr + 1);
      PutW(bankAddr + 1, modBase + addr)              (* low 16 = in-bank offset *)

    ELSIF opcode = 22H THEN  (* JSL — 3-byte far address *)
      bankByte := GetB(bankAddr + 3);
      addr := GetW(bankAddr + 1);
      IF (bankByte > 0) & (bankByte <= impCount) & (impMap[bankByte] >= 0) THEN
        mno := bankByte; exno := addr; targetIdx := impMap[mno];
        IF (exno > 0) & (exno < exportCounts[targetIdx]) THEN
          targetA := baseAddrs[targetIdx] + exports[targetIdx, exno];
          PutW(bankAddr + 1, targetA MOD 10000H);
          PutB(bankAddr + 3, targetA DIV 10000H)
        ELSE Out.String("JSL: bad exno "); Out.Int(exno, 1); Out.Ln
        END
      ELSE                                             (* intra-module far call *)
        targetA := modBase + addr;
        PutW(bankAddr + 1, targetA MOD 10000H);
        PutB(bankAddr + 3, targetA DIV 10000H)
      END

    ELSIF opcode = 0A9H THEN  (* LDA #imm16 — var base reloc *)
      operand := GetW(bankAddr + 1);
      IF operand = 0 THEN varBase := modVarBase
      ELSE
        mno := operand;
        IF (mno <= impCount) & (impMap[mno] >= 0) THEN varBase := varAddrs[impMap[mno]]
        ELSE varBase := 0; Out.String("LDA: mno not found "); Out.Int(mno, 1); Out.Ln
        END
      END;
      PutW(bankAddr + 1, varBase)

    ELSIF opcode = 62H THEN  (* PER — imported procedure variable, PC-relative *)
      operand := GetW(bankAddr + 1);
      mno := AND(LSR(operand, 8), 0FFH);
      exno := AND(operand, 0FFH);
      IF (mno > 0) & (mno <= impCount) & (impMap[mno] >= 0) THEN
        targetIdx := impMap[mno];
        IF (exno > 0) & (exno < exportCounts[targetIdx]) THEN
          targetA := baseAddrs[targetIdx] + exports[targetIdx, exno];
          PutW(bankAddr + 1, targetA - bankAddr - 3)   (* 16-bit PC-relative *)
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

  PROCEDURE LoadEx(name: ARRAY OF CHAR; VAR res: INTEGER; exec: BOOLEAN);
    VAR f: FatFS.File;
        r: FatFS.Rider;
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
        modVarBase: INTEGER;
        modBase: LONGINT;
        tdSize, varSize, strSize, codeLen: LONGINT;
        bi: LONGINT;                       (* 32-bit byte-loop counter *)
        nofent, entryPoint: INTEGER;
        expIdx, expVal: INTEGER;
        relocCount, relocAddr, relocHi, actualAddr: INTEGER;
        bankAddr: LONGINT;
        isBankReloc: BOOLEAN;
        tdFixupCount, byteOffset, fixMno: INTEGER;
        lo, hi, tdAddr: INTEGER;
        fixVarBase: INTEGER;
        vtFixCount, vtExno, vtIdx, vtBase: INTEGER;
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
        f := FatFS.Old(path);
        INC(pi)
      END;

      IF f = NIL THEN
        Out.String("Module not found: "); Out.String(nm); Out.Ln;
        res := -1
      ELSE
        FatFS.Set(r, f, 0);

        (* Read module name *)
        FatFS.ReadString(r, modName);

        (* Read key (4 bytes) *)
        ReadLong16(r, key);

        (* Read version (1 byte) *)
        FatFS.Read(r, b);
        version := b;

        (* Read size (4 bytes) *)
        ReadLong16(r, size);

        (* Parse imports *)
        impCount := 0;
        i := 0;
        WHILE i < MaxImports DO impMap[i] := -1; INC(i) END;

        FatFS.Read(r, b);
        WHILE (b # 0) & ~r.eof DO
          INC(impCount);
          (* Read import name - first byte already in b *)
          IF impCount < MaxImports THEN
            i := 0;
            impNames[impCount][0] := CHR(b);
            i := 1;
            FatFS.Read(r, b);
            WHILE (b # 0) & ~r.eof & (i < 31) DO
              impNames[impCount][i] := CHR(b);
              INC(i);
              FatFS.Read(r, b)
            END;
            (* Skip remaining name chars if longer than 31 *)
            WHILE (b # 0) & ~r.eof DO FatFS.Read(r, b) END;
            impNames[impCount][i] := 0X;
            (* Skip key (4 bytes) *)
            SkipLong(r);

            (* Find or auto-load dependency *)
            impMap[impCount] := Find(impNames[impCount]);
            IF impMap[impCount] < 0 THEN
              LoadEx(impNames[impCount], depRes, exec);
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
            WHILE (b # 0) & ~r.eof DO FatFS.Read(r, b) END;
            SkipLong(r)
          END;
          FatFS.Read(r, b)  (* Read first byte of next import or 0 *)
        END;

        IF res = 0 THEN
          (* Snapshot data base (code base is chosen once codeLen is known,
             below, so the module can be kept wholly within one bank) *)
          modVarBase := varAddr;

          (* Read type descriptors *)
          ReadLong(r, tdSize);
          IF tdSize > 0 THEN
            bi := 0;
            WHILE (bi < tdSize) & ~r.eof DO
              FatFS.Read(r, b);
              PutByte(0, modVarBase + bi, b);
              INC(bi)
            END
          END;

          (* Read var_size *)
          ReadLong(r, varSize);

          (* Read string section *)
          ReadLong(r, strSize);
          IF strSize > 0 THEN
            bi := 0;
            WHILE (bi < strSize) & ~r.eof DO
              FatFS.Read(r, b);
              PutByte(0, modVarBase + tdSize + varSize + bi, b);
              INC(bi)
            END
          END;

          (* Read code section. Place the module wholly within one bank: the
             65C816 PC is 16-bit and wraps at a bank boundary, so no procedure
             (hence no module) may straddle one. Bump to the next bank if it
             would not fit in the current bank's remaining space. *)
          ReadLong(r, codeLen);
          IF loadAddr MOD 10000H + codeLen > 10000H THEN
            loadAddr := (loadAddr DIV 10000H + 1) * 10000H
          END;
          modBase := loadAddr;
          bi := 0;
          WHILE (bi < codeLen) & ~r.eof DO
            FatFS.Read(r, b);
            PutB(modBase + bi, b);              (* 24-bit placement *)
            INC(bi)
          END;

          (* Skip export procedures (name + value pairs until null) *)
          FatFS.Read(r, b);
          WHILE (b # 0) & ~r.eof DO
            (* Skip procedure name *)
            WHILE (b # 0) & ~r.eof DO FatFS.Read(r, b) END;
            (* Skip value (4 bytes) *)
            SkipLong(r);
            FatFS.Read(r, b)
          END;

          (* Read nofent and entry point *)
          ReadLong16(r, nofent);
          ReadLong16(r, entryPoint);

          (* Read export values until -1 sentinel *)
          expIdx := 1;
          ReadLong16(r, expVal);
          WHILE (expVal # -1) & ~r.eof & (expIdx < MaxExports) DO
            exports[count, expIdx] := expVal;
            INC(expIdx);
            ReadLong16(r, expVal)
          END;
          exportCounts[count] := expIdx;

          (* Skip fixorgP, fixorgD, fixorgT *)
          SkipLong(r); SkipLong(r); SkipLong(r);

          (* Process TD fixups *)
          ReadLong16(r, tdFixupCount);
          i := 0;
          WHILE (i < tdFixupCount) & ~r.eof DO
            FatFS.ReadInt(r, byteOffset);
            FatFS.ReadInt(r, fixMno);
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

          (* Process vtable fixups (v2+): each fills a method slot with the
             absolute in-bank code address of its implementation. Entry layout
             offset(4) mno(2) exno(2). This section must be consumed even when
             empty, otherwise the relocation count below is read from the wrong
             file offset (leaving the module unrelocated). mno=0: own method,
             the slot holds a code offset -> add this module's base. mno>0:
             imported inherited method -> resolve via (mno, exno). *)
          ReadLong16(r, vtFixCount);
          i := 0;
          WHILE (i < vtFixCount) & ~r.eof DO
            ReadLong16(r, byteOffset);         (* offset written as 4 bytes *)
            FatFS.ReadInt(r, fixMno);
            FatFS.ReadInt(r, vtExno);
            IF fixMno = 0 THEN
              lo := GetWord(0, modVarBase + byteOffset);
              vtBase := modBase MOD 10000H;
              PutWord(0, modVarBase + byteOffset, vtBase + lo)
            ELSIF (fixMno <= impCount) & (impMap[fixMno] >= 0) THEN
              vtIdx := impMap[fixMno];
              IF (vtExno > 0) & (vtExno < exportCounts[vtIdx]) THEN
                vtBase := baseAddrs[vtIdx] MOD 10000H;
                PutWord(0, modVarBase + byteOffset, vtBase + exports[vtIdx, vtExno])
              END
            END;
            INC(i)
          END;

          (* Register module in tracking arrays *)
          CopyStr(modName, names[count]);
          banks[count] := modBase DIV 10000H;   (* the bank the module landed in *)
          baseAddrs[count] := modBase;
          varAddrs[count] := modVarBase;
          entries[count] := entryPoint;

          (* Write module table entry *)
          PutWord(0, ModTableBase + count * 2, modVarBase);

          (* Process relocation table *)
          ReadLong16(r, relocCount);
          i := 0;
          WHILE (i < relocCount) & ~r.eof DO
            FatFS.ReadInt(r, relocAddr);
            FatFS.ReadInt(r, relocHi);
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

          FatFS.Close(f);

          (* Execute module initialization (skipped when only linking) *)
          IF exec THEN
            Out.String("Exec "); Out.String(modName);
            Out.String(" at "); Out.Int(modBase DIV 10000H, 1);
            Out.String(":"); Out.Hex((modBase + entryPoint) MOD 10000H); Out.Ln;
            SYSTEM.EXEC((modBase + entryPoint) MOD 10000H, (modBase + entryPoint) DIV 10000H)
          END
        ELSE
          FatFS.Close(f)
        END
      END
    END
  END LoadEx;

  (* Runtime entry: load a module and run its init. *)
  PROCEDURE Load*(name: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN LoadEx(name, res, TRUE)
  END Load;

  (* MakeImage entry: load + relocate into memory but DON'T run init, so the
     linked bytes can be snapshotted into a kernel image. *)
  PROCEDURE Link*(name: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN LoadEx(name, res, FALSE)
  END Link;

  (* ---- Accessors + image writer (for MakeImage) ---- *)

  PROCEDURE Count*(): INTEGER;    BEGIN RETURN count END Count;
  PROCEDURE CodeTop*(): LONGINT;  BEGIN RETURN loadAddr END CodeTop;   (* 24-bit *)
  PROCEDURE VarTop*(): INTEGER;   BEGIN RETURN varAddr END VarTop;

  (* Restrict Find() to modules loaded at index >= b, so a subsequent link
     session builds a fresh, self-contained module set. *)
  PROCEDURE SetLinkBase*(b: INTEGER);  BEGIN linkBase := b END SetLinkBase;

  (* Place the next linked module's code/data at explicit addresses. MakeImage
     uses this to link the kernel clear of the build-time heap: the runtime
     loader writes a module's data at varAddr, but em16 (and later the memory
     manager) put the heap at the same next-free address, and Files keeps the
     FileDesc it is reading FROM on that heap — so linking on top of it clobbers
     the open file mid-read. Linking into a region above the heap avoids that. *)
  PROCEDURE SetLinkAddr*(code: LONGINT; var: INTEGER);
  BEGIN loadAddr := code; varAddr := var
  END SetLinkAddr;

  PROCEDURE Wr(VAR r: FatFS.Rider; v: INTEGER);
    VAR b: BYTE;
  BEGIN b := v; FatFS.Write(r, b)
  END Wr;

  PROCEDURE Put4(VAR r: FatFS.Rider; v: LONGINT);   (* 32-bit LE *)
  BEGIN FatFS.WriteInt(r, v MOD 10000H); FatFS.WriteInt(r, v DIV 10000H MOD 10000H)
  END Put4;

  (* Snapshot the modules linked in [firstMod..count) into an OS16 kernel image:
     header, module manifest ($0D00 shape), then the linked code (bank CodeBank
     [codeBase..CodeTop)) and data (bank 0 [varBase..VarTop)). The image loads
     back to those same addresses at boot — no relocation. *)
  PROCEDURE WriteImage*(fname: ARRAY OF CHAR; firstMod: INTEGER; codeBase: LONGINT;
                        varBase: INTEGER; VAR res: INTEGER);
    VAR f: FatFS.File; r: FatFS.Rider;
        i, j, varLen: INTEGER; ci, codeLen, entry: LONGINT;
  BEGIN
    res := 0;
    codeLen := loadAddr - codeBase;
    varLen := varAddr - varBase;
    entry := baseAddrs[count - 1] + entries[count - 1];  (* last linked = main *)
    f := FatFS.New(fname);
    IF f = NIL THEN res := -1
    ELSE
      FatFS.Set(r, f, 0);
      Wr(r, ORD("O")); Wr(r, ORD("S")); Wr(r, ORD("1")); Wr(r, ORD("6"));
      Wr(r, 1);                              (* version *)
      Put4(r, entry);
      Put4(r, codeBase); Put4(r, codeLen);
      Put4(r, varBase);  Put4(r, varLen);
      (* manifest: kernel modules [firstMod..count) in $0D00 shape; base_addr and
         the trailing next-code pointer are 24-bit (two words: low, high). *)
      FatFS.WriteInt(r, count - firstMod);
      i := firstMod;
      WHILE i < count DO
        FatFS.WriteString(r, names[i]);
        FatFS.WriteInt(r, banks[i]);
        Put4(r, baseAddrs[i]);               (* 24-bit *)
        FatFS.WriteInt(r, varAddrs[i]);
        FatFS.WriteInt(r, exportCounts[i] - 1);
        j := 1;
        WHILE j < exportCounts[i] DO FatFS.WriteInt(r, exports[i, j]); INC(j) END;
        INC(i)
      END;
      Put4(r, loadAddr);                     (* next free code addr (24-bit) *)
      FatFS.WriteInt(r, varAddr);            (* next free var addr *)
      ci := 0;
      WHILE ci < codeLen DO Wr(r, GetB(codeBase + ci)); INC(ci) END;
      i := 0;
      WHILE i < varLen DO Wr(r, GetByte(0, varBase + i)); INC(i) END;
      FatFS.Register(f)
    END
  END WriteImage;

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
      (* Read base_addr (24-bit) *)
      baseAddrs[count] := Get24(maddr); maddr := maddr + 4;
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
    loadAddr := Get24(maddr); maddr := maddr + 4;
    varAddr := GetWord(0, maddr); maddr := maddr + 2
  END ReadManifest;

BEGIN
  count := 0;
  loadAddr := 0;
  varAddr := VarBase;
  linkBase := 0;
  pathCount := 0;
  paths[0] := "Library/Modules/";
  pathCount := 1;
  ReadManifest
END ModuleLoader.
