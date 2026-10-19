MODULE Payload;
(* B3 test payload: a dependency-free module (IMPORT SYSTEM only) that Boot
   relocates offline with MakePayload, loads off the floppy, and SYSTEM.EXECs.
   Prints to serial so a successful hand-off is visible, then returns. *)
  IMPORT SYSTEM;
  CONST Serial = 0200H;
  VAR msg: ARRAY 24 OF CHAR;
  PROCEDURE Wr(ch: CHAR);
  BEGIN SYSTEM.PUT(0, Serial, ORD(ch)) END Wr;
  PROCEDURE Str(s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO Wr(s[i]); INC(i) END
  END Str;
BEGIN
  msg := "PAYLOAD RUNNING"; Str(msg); Wr(0DX); Wr(0AX)
END Payload.
