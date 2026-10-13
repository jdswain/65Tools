MODULE Dump;
  (* Prints the files the assembler wrote, for comparison with those of
     the host assembler: the output file in hexadecimal, 16 bytes to a
     line, and the listing as it is. *)
  IMPORT Files, Env, Out;

  VAR name: ARRAY 32 OF CHAR;

  PROCEDURE HexDigit(d: INTEGER);
  BEGIN
    IF d < 10 THEN Out.Write(CHR(d + 30H)) ELSE Out.Write(CHR(d + 57H)) END
  END HexDigit;

  PROCEDURE Hex(name: ARRAY OF CHAR);
    VAR F: Files.File; R: Files.Rider; b: BYTE; n: INTEGER;
  BEGIN F := Files.Old(name);
    IF F = NIL THEN Out.WriteString("no file "); Out.WriteString(name); Out.Ln
    ELSE Files.Set(R, F, 0); n := 0;
      Files.ReadByte(R, b);
      WHILE ~R.eof DO
        HexDigit(b DIV 10H); HexDigit(b MOD 10H); INC(n);
        IF n = 16 THEN Out.Ln; n := 0 END;
        Files.ReadByte(R, b)
      END;
      IF n # 0 THEN Out.Ln END
    END
  END Hex;

  PROCEDURE Text(name: ARRAY OF CHAR);
    VAR F: Files.File; R: Files.Rider; b: BYTE;
  BEGIN F := Files.Old(name);
    IF F = NIL THEN Out.WriteString("no file "); Out.WriteString(name); Out.Ln
    ELSE Files.Set(R, F, 0);
      Files.ReadByte(R, b);
      WHILE ~R.eof DO Out.Write(CHR(b)); Files.ReadByte(R, b) END
    END
  END Text;

BEGIN
  Out.WriteString("--- output"); Out.Ln;
  Env.Arg(2, name); Hex(name);
  Out.WriteString("--- listing"); Out.Ln;
  Text("sample.lst");
  Out.WriteString("--- end"); Out.Ln
END Dump.
