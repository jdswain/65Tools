MODULE EmLoad; (* Loading programs: ELF executables of the assembler, and
   the run time traps of the machines other than -fpga (where BRK goes
   through the vectors, to OS16's InterruptManager). Oberon modules are
   not loaded here: OS16 boots on -fpga as on the board and its
   ModuleManager loads them (../../OS16/doc/OS16_MemoryManagement.md). *)

  IMPORT Files, EmHost, EmSym, EmMem, EmCPU;

  CONST
    out = EmHost.out; err = EmHost.err;
    (* ELF *)
    emW65C816 = 1; emW65C02 = 2; em6502 = 3; emR65C02 = 4; emR65C19 = 5; emR6501 = 6;

  TYPE
    Path* = ARRAY 256 OF CHAR;

  VAR
    elfBuf: ARRAY 1000000 OF BYTE;

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

  (* --- the run time's traps --- *)

  (* BRK #0 stops (a program's end); the rest are run time errors. *)
  PROCEDURE Trap(n: INTEGER);
  BEGIN
    IF n = 0 THEN EmCPU.Stop
    ELSE
      Str("TRAP "); Int(n); Str(" at "); Hex(EmCPU.GetPBR(), 2); Str(":"); Hex(EmCPU.GetPC() - 2, 4); Ln;
      EmCPU.Stop
    END
  END Trap;

  PROCEDURE InitTraps*;
  BEGIN EmCPU.SetTrapHandler(Trap)
  END InitTraps;

END EmLoad.
