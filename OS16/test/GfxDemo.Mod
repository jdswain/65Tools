MODULE GfxDemo;
(* B4 payload: a self-contained (IMPORT SYSTEM only) graphics demo that draws
   the GraphicsWindow mockup directly to the FPGA framebuffer. Boot relocates it
   with MakePayload, loads it off the floppy, and SYSTEM.EXECs it.

   Framebuffer: $70_0000, 640x480, 4bpp, stride 320 bytes, low nibble = left
   pixel. Palette (write-only) at $0240, 16 x {r,g,b,-}. General LONGINT multiply
   is deferred in the backend, so row addresses are built incrementally (+stride)
   rather than y*320. Colours are our own palette indices; we program the entries
   we use so it also works on real hardware (em16 defaults to VGA). *)
  IMPORT SYSTEM;

  CONST
    SccCtl  = 0822H;                (* the Z85C30 SCC, channel A *)
    SccData = 0823H;
    Palette = 0240H;
    FBBase  = 700000H;              (* LONGINT framebuffer base *)
    Stride  = 320;
    ScreenW = 640; ScreenH = 480; MenuH = 14;
    (* palette indices *)
    Black = 0; White = 1; LiteGray = 2; DarkGray = 3;

  PROCEDURE Wr(ch: CHAR);                (* the SCC, channel A: wait for room *)
    VAR b: BYTE;
  BEGIN
    REPEAT SYSTEM.GET(0, SccCtl, b) UNTIL ODD(b DIV 4);
    b := ORD(ch); SYSTEM.PUT(0, SccData, b)
  END Wr;

  (* ---- 24-bit memory access (bank:offset split, both powers of two) ---- *)

  PROCEDURE PutB(a: LONGINT; val: INTEGER);
    VAR b: BYTE;
  BEGIN b := val; SYSTEM.PUT(a DIV 10000H, a MOD 10000H, b) END PutB;

  PROCEDURE GetB(a: LONGINT): INTEGER;
    VAR b: BYTE; v: INTEGER;
  BEGIN SYSTEM.GET(a DIV 10000H, a MOD 10000H, b); v := b RETURN v END GetB;

  PROCEDURE SetPalette(i, r, g, b: INTEGER);
    VAR base: INTEGER; v: BYTE;
  BEGIN base := Palette + i * 4;
    v := r; SYSTEM.PUT(0, base, v);
    v := g; SYSTEM.PUT(0, base + 1, v);
    v := b; SYSTEM.PUT(0, base + 2, v)
  END SetPalette;

  (* rowAddr = FBBase + y*Stride, built by repeated add (no multiply) *)
  PROCEDURE RowAddr(y: INTEGER): LONGINT;
    VAR a: LONGINT; i: INTEGER;
  BEGIN a := FBBase; i := 0;
    WHILE i < y DO a := a + Stride; INC(i) END
  RETURN a
  END RowAddr;

  (* one pixel via read-modify-write of its nibble (low nibble = even x) *)
  PROCEDURE SetPix(rowAddr: LONGINT; x, c: INTEGER);
    VAR a: LONGINT; b: INTEGER;
  BEGIN a := rowAddr + x DIV 2; b := GetB(a);
    IF x MOD 2 = 0 THEN b := ORA(AND(b, 0F0H), c)
    ELSE b := ORA(AND(b, 0FH), ASL(c, 4))
    END;
    PutB(a, b)
  END SetPix;

  PROCEDURE FillRect(x, y, w, h, c: INTEGER);
    VAR rowAddr: LONGINT; row, px, xend, cc: INTEGER;
  BEGIN
    cc := ORA(c, ASL(c, 4));            (* both nibbles = c *)
    rowAddr := RowAddr(y); row := 0;
    WHILE row < h DO
      px := x; xend := x + w;
      WHILE px < xend DO
        IF (px MOD 2 = 0) & (px + 1 < xend) THEN
          PutB(rowAddr + px DIV 2, cc); px := px + 2   (* full byte = 2 px *)
        ELSE
          SetPix(rowAddr, px, c); INC(px)
        END
      END;
      rowAddr := rowAddr + Stride; INC(row)
    END
  END FillRect;

  PROCEDURE HLine(x, y, len, c: INTEGER); BEGIN FillRect(x, y, len, 1, c) END HLine;
  PROCEDURE VLine(x, y, len, c: INTEGER); BEGIN FillRect(x, y, 1, len, c) END VLine;

  PROCEDURE Draw;
    VAR x, y, w, h: INTEGER;
  BEGIN
    (* desktop fills everything above the menu bar *)
    Wr("0"); FillRect(0, 0, 64, 64, DarkGray); Wr("1");

    (* menu bar: black rule, dark-gray rule, light-gray bar to bottom edge *)
    HLine(0, ScreenH - MenuH,     ScreenW, Black);
    HLine(0, ScreenH - MenuH + 1, ScreenW, DarkGray);
    FillRect(0, ScreenH - MenuH + 2, ScreenW, MenuH - 2, LiteGray); Wr("2");

    (* window filling the screen (20px margins, clear of the menu bar) *)
    x := 20; y := 20; w := ScreenW - 40; h := ScreenH - MenuH - y - 20;

    (* black outer frame *)
    HLine(x, y, w, Black); HLine(x, y + h, w, Black);
    VLine(x, y, h, Black); VLine(x + w, y, h + 1, Black);

    (* window body + title bar (bottom), light gray, with a white top-left bevel *)
    FillRect(x + 1, y + 1, w - 1, h - 15, LiteGray);
    HLine(x + 1, y + h - 14, w - 1, Black);
    FillRect(x + 2, y + h - 12, w - 3, 11, LiteGray);
    VLine(x + 1, y + 1, h - 15, White);
    HLine(x + 1, y + 1, w - 1, White); Wr("3")
  END Draw;

BEGIN
  SetPalette(Black,    0,   0,   0);
  SetPalette(White,    255, 255, 255);
  SetPalette(LiteGray, 192, 192, 192);
  SetPalette(DarkGray, 96,  96,  96);
  Draw
END GfxDemo.
