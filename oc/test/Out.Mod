MODULE Out; (* Output on the serial port: channel A of the board's Z85C30
   SCC (em16 -fpga writes it to standard output). While the display is in
   text mode (OS16's text boot, the boot ROM's with D held, or a serial
   boot from MiniMon), on the text screen too, from the line after the
   last one written on it, until something sets the graphics mode. *)
  IMPORT SYSTEM;
  CONST
    SccCtl = 0822H;    (* RR0 bit 2: the transmit buffer is empty *)
    SccData = 0823H;
    VideoCtl = 0380H;  (* bit 0: text mode *)
    Rows = 48; Cols = 128; TextBpr = 256; Attr = 07H;   (* 128 x 48 cells at $70:0000, a character and an attribute *)

  VAR row, col: INTEGER;   (* the text screen's cursor *)

  PROCEDURE Cell(r, c: INTEGER; ch: CHAR);
    VAR b: BYTE;
  BEGIN SYSTEM.PUT(70H, r * TextBpr + c * 2, ch); b := Attr; SYSTEM.PUT(70H, r * TextBpr + c * 2 + 1, b)
  END Cell;

  PROCEDURE NewLine;
    VAR i, w: INTEGER;
  BEGIN col := 0; INC(row);
    IF row = Rows THEN row := Rows - 1;
      i := 0; WHILE i < (Rows - 1) * TextBpr DO SYSTEM.GET(70H, i + TextBpr, w); SYSTEM.PUT(70H, i, w); INC(i, 2) END;
      i := 0; WHILE i < Cols DO Cell(row, i, " "); INC(i) END
    END
  END NewLine;

  PROCEDURE Char*(ch: CHAR);
    VAR b: BYTE;
  BEGIN
    REPEAT SYSTEM.GET(0, SccCtl, b) UNTIL ODD(b DIV 4);
    SYSTEM.PUT(0, SccData, ch);
    SYSTEM.GET(0, VideoCtl, b);
    IF ODD(b) THEN
      IF ch = 0DX THEN col := 0
      ELSIF ch = 0AX THEN NewLine
      ELSE Cell(row, col, ch); INC(col); IF col = Cols THEN NewLine END
      END
    END
  END Char;

  PROCEDURE Ln*;
  BEGIN
    Char(0AX)
  END Ln;

  PROCEDURE String*(s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (s[i] # 0X) DO
      Char(s[i]); i := i + 1
    END
  END String;

  (* the names of the host runtime's Out *)
  PROCEDURE Write*(ch: CHAR);
  BEGIN Char(ch)
  END Write;

  PROCEDURE WriteString*(s: ARRAY OF CHAR);
  BEGIN String(s)
  END WriteString;

  PROCEDURE Int*(x, n: INTEGER);
    VAR i, d: INTEGER;
        buf: ARRAY 6 OF CHAR;
        neg: BOOLEAN;
  BEGIN
    (* the digits from x made not positive, which -32768 can be: each
       the last digit of -x, and x what is left of it *)
    neg := x < 0;
    IF ~neg THEN x := -x END;
    i := 0;
    REPEAT
      d := (10 - x MOD 10) MOD 10;
      x := (x + d) DIV 10;
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

  PROCEDURE Init;   (* the transmitter on, 8 bits (WR5); the text screen's first free line *)
    VAR b: BYTE; c: INTEGER; blank: BOOLEAN;
  BEGIN
    SYSTEM.GET(0, SccCtl, b);   (* the register pointer back to 0 *)
    b := 5; SYSTEM.PUT(0, SccCtl, b); b := 68H; SYSTEM.PUT(0, SccCtl, b);
    row := 0; col := 0;
    SYSTEM.GET(0, VideoCtl, b);
    IF ODD(b) THEN
      row := Rows; blank := TRUE;
      WHILE blank & (row > 0) DO
        DEC(row); c := 0;
        WHILE blank & (c < Cols) DO SYSTEM.GET(70H, row * TextBpr + c * 2, b); blank := (b = 20H) OR (b = 0); INC(c) END
      END;
      IF ~blank THEN INC(row) END;
      IF row = Rows THEN row := Rows - 1; NewLine END
    END
  END Init;

BEGIN
  Init;
  Char("O"); Char("K"); Ln()
END Out.
