MODULE Env;
  (* Program arguments for the emulator: Seed sets them before the
     assembler starts. *)

  CONST maxArgs = 8;

  VAR args: ARRAY maxArgs OF ARRAY 32 OF CHAR;
    n: INTEGER;

  PROCEDURE Add*(s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    IF n < maxArgs THEN i := 0;
      WHILE (i < 31) & (i < LEN(s)) & (s[i] # 0X) DO args[n][i] := s[i]; INC(i) END;
      args[n][i] := 0X; INC(n)
    END
  END Add;

  PROCEDURE ArgCount*(): INTEGER;
  BEGIN RETURN n
  END ArgCount;

  PROCEDURE Arg*(i: INTEGER; VAR s: ARRAY OF CHAR);
    VAR j: INTEGER;
  BEGIN j := 0;
    IF (i >= 0) & (i < n) THEN
      WHILE (j < LEN(s) - 1) & (args[i][j] # 0X) DO s[j] := args[i][j]; INC(j) END
    END;
    s[j] := 0X
  END Arg;

BEGIN n := 0
END Env.
