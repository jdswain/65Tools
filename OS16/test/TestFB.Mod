MODULE TestFB;
  IMPORT SYSTEM;
  CONST SccCtl=0822H; SccData=0823H; FBBase=700000H;
  VAR i: INTEGER; a: LONGINT;
  PROCEDURE Wr(ch: CHAR);                (* the SCC, channel A: wait for room *)
    VAR b: BYTE;
  BEGIN
    REPEAT SYSTEM.GET(0, SccCtl, b) UNTIL ODD(b DIV 4);
    b := ORD(ch); SYSTEM.PUT(0, SccData, b)
  END Wr;
  PROCEDURE PutB(a: LONGINT; val: INTEGER);
    VAR b: BYTE;
  BEGIN b := val; SYSTEM.PUT(a DIV 10000H, a MOD 10000H, b) END PutB;
BEGIN
  Wr("A");
  a := FBBase; i := 0;
  WHILE i < 160 DO PutB(a + i DIV 2, 011H); INC(i) END;
  Wr("B")
END TestFB.
