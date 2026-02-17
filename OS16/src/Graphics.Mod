(* Simple Graphics with no translation matrix or alpha *)
MODULE Graphics;

IMPORT SYSTEM;

PROCEDURE SetPixel*(x, y: INTEGER; c: INTEGER);
  CONST BytesPerRow = 160;
  VAR bank, addr, val, pos: INTEGER; b: BYTE;
BEGIN
  (* Determine bank: video starts at bank 2, crosses to bank 3 at row ~410 *)
  IF (y > 409) OR ((y = 409) & (x >= 384)) THEN
    bank := 3
  ELSE
    bank := 2
  END;
  (* 16-bit modular arithmetic gives correct offset within bank *)
  addr := y * BytesPerRow + x DIV 4;
  (* Read byte, clear 2-bit pixel field, insert new color *)
  SYSTEM.GET(bank, addr, b);
  val := ORD(b);
  c := c MOD 4;
  pos := x MOD 4;
  CASE pos OF
    0: val := val MOD 40H + c * 40H
  | 1: val := val DIV 40H * 40H + c * 10H + val MOD 10H
  | 2: val := val DIV 10H * 10H + c * 4 + val MOD 4
  | 3: val := val DIV 4 * 4 + c
  END;
  SYSTEM.PUT(bank, addr, SYSTEM.VAL(BYTE, val))
END SetPixel;

PROCEDURE GetPixel*(x, y: INTEGER): INTEGER;
BEGIN RETURN 0
END GetPixel;

PROCEDURE DrawLine*(x, y, w, h: INTEGER; c: INTEGER; lw: INTEGER);
BEGIN
END DrawLine;

PROCEDURE DrawRect*(x, y, w, h: INTEGER; c: INTEGER; lw: INTEGER);
BEGIN
END DrawRect;

PROCEDURE FillRect*(x, y, w, h: INTEGER; c: INTEGER);
BEGIN
END FillRect;

PROCEDURE DrawRoundRect*(x, y, w, h: INTEGER; c: INTEGER; lw: INTEGER; r: INTEGER);
BEGIN
END DrawRoundRect;

PROCEDURE FillRoundRect*(x, y, w, h: INTEGER; c: INTEGER; r: INTEGER);
BEGIN
END FillRoundRect;

PROCEDURE DrawCircle*(x, y, w, h: INTEGER; c: INTEGER; lw: INTEGER);
BEGIN
END DrawCircle;

PROCEDURE FillCircle*(x, y, w, h: INTEGER; c: INTEGER);
BEGIN
END FillCircle;

PROCEDURE Move*(x, y, w, h: INTEGER; dx, dy: INTEGER);
BEGIN
END Move;

PROCEDURE Blt*(sPage: BYTE; sBuffer: INTEGER; sx, sy, sw, sh: INTEGER; dx, dy: INTEGER);
BEGIN
END Blt;

PROCEDURE ModeBlt*(sPage: BYTE; sBuffer: INTEGER; sx, sy, sw, sh: INTEGER; dx, dy: INTEGER; mode: INTEGER);
BEGIN
END ModeBlt;

END Graphics.
