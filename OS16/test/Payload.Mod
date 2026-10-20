MODULE Payload;
(* B3 test payload: a dependency-free module (IMPORT SYSTEM only) that Boot
   relocates offline with MakePayload, loads off the floppy, and SYSTEM.EXECs.
   Prints to serial so a successful hand-off is visible, then returns. *)
  IMPORT SYSTEM;
  CONST SccCtl = 0822H; SccData = 0823H;   (* the Z85C30 SCC, channel A *)
  VAR msg: ARRAY 24 OF CHAR;
  PROCEDURE Wr(ch: CHAR);                (* the SCC, channel A: wait for room *)
    VAR b: BYTE;
  BEGIN
    REPEAT SYSTEM.GET(0, SccCtl, b) UNTIL ODD(b DIV 4);
    b := ORD(ch); SYSTEM.PUT(0, SccData, b)
  END Wr;
  PROCEDURE Str(s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO Wr(s[i]); INC(i) END
  END Str;
BEGIN
  msg := "PAYLOAD RUNNING"; Str(msg); Wr(0DX); Wr(0AX)
END Payload.
