MODULE Out;
  IMPORT SYSTEM;
  CONST ACIA_DATA = 0C000H;

  PROCEDURE Char*(ch: CHAR);
  BEGIN
    SYSTEM.PUT(0, ACIA_DATA, ch)
  END Char;

  PROCEDURE Ln*;
  BEGIN
    SYSTEM.PUT(0, ACIA_DATA, 0AX)
  END Ln;

  PROCEDURE String*(VAR s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (s[i] # 0X) DO
      Char(s[i]); i := i + 1
    END
  END String;

  PROCEDURE Int*(x, n: INTEGER);
    VAR i, d: INTEGER;
        buf: ARRAY 6 OF CHAR;
        neg: BOOLEAN;
  BEGIN
    neg := FALSE;
    IF x < 0 THEN
      neg := TRUE; x := -x
    END;
    i := 0;
    REPEAT
      d := x MOD 10;
      x := x DIV 10;
      buf[i] := CHR(d + ORD("0"));
      i := i + 1
    UNTIL x = 0;
    IF neg THEN
      buf[i] := "-"; i := i + 1
    END;
    WHILE n > i DO
      Char(" "); n := n - 1
    END;
    REPEAT
      i := i - 1; Char(buf[i])
    UNTIL i = 0
  END Int;

  PROCEDURE HexNibble(d: INTEGER);
  BEGIN
    d := AND(d, 0FH);
    IF d < 10 THEN
      Char(CHR(d + ORD("0")))
    ELSE
      Char(CHR(d - 10 + ORD("A")))
    END
  END HexNibble;

  PROCEDURE Hex*(x: INTEGER);
  BEGIN
    HexNibble(LSR(x, 12));
    HexNibble(LSR(x, 8));
    HexNibble(LSR(x, 4));
    HexNibble(x)
  END Hex;

  PROCEDURE Bool*(b: BOOLEAN);
  BEGIN
    IF b THEN Char("T") ELSE Char("F") END
  END Bool;

  PROCEDURE Real*(x: REAL; n: INTEGER);
    VAR e, i, d: INTEGER;
        y: REAL;
        buf: ARRAY 8 OF CHAR;
        neg: BOOLEAN;
  BEGIN
    neg := FALSE;
    IF x < 0.0 THEN neg := TRUE; x := -x END;
    IF x = 0.0 THEN
      i := 11; IF neg THEN i := 12 END;
      WHILE n > i DO Char(" "); n := n - 1 END;
      IF neg THEN Char("-") END;
      Char("0"); Char("."); Char("0"); Char("0"); Char("0"); Char("0"); Char("0");
      Char("E"); Char("+"); Char("0"); Char("0")
    ELSE
      e := 0;
      WHILE x >= 10.0 DO x := x / 10.0; e := e + 1 END;
      WHILE x < 1.0 DO x := x * 10.0; e := e - 1 END;
      i := 0;
      WHILE i < 6 DO
        d := FLOOR(x);
        IF d > 9 THEN d := 9 END;
        buf[i] := CHR(d + ORD("0"));
        y := FLT(d);
        x := x - y;
        x := x * 10.0;
        i := i + 1
      END;
      i := 11; IF neg THEN i := 12 END;
      IF (e > 99) OR (e < -99) THEN i := i + 1 END;
      WHILE n > i DO Char(" "); n := n - 1 END;
      IF neg THEN Char("-") END;
      Char(buf[0]); Char(".");
      Char(buf[1]); Char(buf[2]); Char(buf[3]); Char(buf[4]); Char(buf[5]);
      Char("E");
      IF e < 0 THEN Char("-"); e := -e ELSE Char("+") END;
      IF e >= 100 THEN
        Char(CHR(e DIV 100 + ORD("0")));
        e := e MOD 100
      END;
      Char(CHR(e DIV 10 + ORD("0")));
      Char(CHR(e MOD 10 + ORD("0")))
    END
  END Real;

BEGIN
  Char("O"); Char("K"); Ln()
END Out.
