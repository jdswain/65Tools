MODULE Out;
  (* The interface of the POSIX runtime's Out, on the emulator's ACIA. *)
  IMPORT SYSTEM;
  CONST ACIA_DATA = 0C000H;

  PROCEDURE Write*(ch: CHAR);
  BEGIN SYSTEM.PUT(0, ACIA_DATA, ch)
  END Write;

  PROCEDURE WriteString*(s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO Write(s[i]); INC(i) END
  END WriteString;

  PROCEDURE WriteInt*(n: INTEGER);
    VAR d: ARRAY 8 OF CHAR; i: INTEGER;
  BEGIN i := 0;
    IF n < 0 THEN Write("-"); n := -n END;
    REPEAT d[i] := CHR(n MOD 10 + 30H); n := n DIV 10; INC(i) UNTIL n = 0;
    WHILE i > 0 DO DEC(i); Write(d[i]) END
  END WriteInt;

  PROCEDURE Ln*();
  BEGIN SYSTEM.PUT(0, ACIA_DATA, 0AX)
  END Ln;
END Out.
