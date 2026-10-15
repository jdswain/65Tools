MODULE EmSym; (* The symbols of the program loaded, for the traces: the
   addresses and names of an ELF file's symbol table. *)

  IMPORT EmHost;

  CONST maxSyms = 200000; maxStr = 4000000;

  VAR
    nofSyms: INTEGER;
    symAddr, symLabel: ARRAY maxSyms OF INTEGER;
    strtab: ARRAY maxStr OF CHAR;

  (* The symbol table: count entries of address and offset of the name in
     the string table. *)
  PROCEDURE SetSymbolCount*(n: INTEGER);
  BEGIN IF n > maxSyms THEN n := maxSyms END; nofSyms := n
  END SetSymbolCount;

  PROCEDURE SetSymbol*(i, addr, label: INTEGER);
  BEGIN IF i < maxSyms THEN symAddr[i] := addr; symLabel[i] := label END
  END SetSymbol;

  PROCEDURE SetStrtab*(VAR s: ARRAY OF BYTE; n: INTEGER);
    VAR i: INTEGER;
  BEGIN
    IF n > maxStr - 1 THEN n := maxStr - 1 END;
    FOR i := 0 TO n - 1 DO strtab[i] := CHR(s[i]) END;
    strtab[n] := 0X
  END SetStrtab;

  (* The address of a symbol, 0 if there is none. *)
  PROCEDURE Symbol*(label: ARRAY OF CHAR): INTEGER;
    VAR i, j, k, r: INTEGER;
  BEGIN r := -1; i := 0;
    WHILE (r < 0) & (i < nofSyms) DO
      j := symLabel[i]; k := 0;
      WHILE (j >= 0) & (j < maxStr) & (k < LEN(label)) & (label[k] # 0X) & (strtab[j] = label[k]) DO INC(j); INC(k) END;
      IF (j >= 0) & (j < maxStr) & ((k = LEN(label)) OR (label[k] = 0X)) & (strtab[j] = 0X) THEN r := symAddr[i] END;
      INC(i)
    END;
    IF r < 0 THEN
      EmHost.Str(EmHost.err, "Symbol '"); EmHost.Str(EmHost.err, label); EmHost.Str(EmHost.err, "' not found.");
      EmHost.Ln(EmHost.err); r := 0
    END;
    RETURN r
  END Symbol;

  PROCEDURE ErrSym(i: INTEGER);
    VAR j: INTEGER;
  BEGIN j := symLabel[i];
    WHILE (j >= 0) & (j < maxStr) & (strtab[j] # 0X) DO EmHost.Ch(EmHost.err, strtab[j]); INC(j) END
  END ErrSym;

  (* An address on standard error: bank, colon, and the symbol at it (or
     two before it), else four digits. *)
  PROCEDURE Word*(ea: INTEGER);
    VAR i: INTEGER; found: BOOLEAN;
  BEGIN EmHost.ToHex(EmHost.err, ea DIV 10000H, 2); EmHost.Ch(EmHost.err, ":");
    i := 0; found := FALSE;
    WHILE ~found & (i < nofSyms) DO
      IF symAddr[i] = ea THEN ErrSym(i); found := TRUE
      ELSIF symAddr[i] = ea - 2 THEN ErrSym(i); EmHost.Str(EmHost.err, "+2"); found := TRUE
      END;
      INC(i)
    END;
    IF ~found THEN EmHost.ToHex(EmHost.err, ea, 4) END
  END Word;

BEGIN nofSyms := 0
END EmSym.
