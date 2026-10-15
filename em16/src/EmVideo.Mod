MODULE EmVideo; (* The framebuffer of the FPGA SoC: 640 x 480 pixels of 4
   bits at $70_0000, 320 bytes a row, the left pixel of a pair in the low
   nibble; and its 16 entry palette, which the SoC has at $0240.

   In text mode (the SoC's video control register, $0380 bit 0) the same
   memory holds 80 x 30 cells of a character and an attribute, ink in the
   low nibble and paper in the high one, drawn 8 x 16 in the SoC's font:
   the Atari ST system font of EmuTOS (GPL v2), read at run time from the
   Verilog repository's rom/font_st8x16.hex rather than copied in.

   mem, pal, text, font and dirty are read by the window (EmCocoa.m)
   from its own thread. *)

  IMPORT Files;

  CONST
    width* = 640; height* = 480;
    bpr* = 320;                 (* bytes per row *)
    size* = 153600;             (* bytes of framebuffer *)
    base* = 700000H;

  VAR
    mem*: ARRAY size OF BYTE;
    pal*: ARRAY 48 OF BYTE;     (* red, green, blue of each colour *)
    dirty*: INTEGER;            (* written since the window last looked *)
    text*: INTEGER;             (* 1: 80 x 30 text *)
    font*: ARRAY 4096 OF BYTE;  (* 16 bytes a glyph, bit 7 leftmost *)
    fontLoaded*: BOOLEAN;

  PROCEDURE GetByte*(ea: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF (ea >= 0) & (ea < size) THEN r := mem[ea] ELSE r := 0 END;
    RETURN r
  END GetByte;

  PROCEDURE SetByte*(ea, data: INTEGER);
  BEGIN
    IF (ea >= 0) & (ea < size) THEN mem[ea] := data; dirty := 1 END
  END SetByte;

  (* Fill a row with one byte, for -test-pattern. *)
  PROCEDURE FillRow*(row, v: INTEGER);
    VAR i: INTEGER;
  BEGIN FOR i := row * bpr TO row * bpr + bpr - 1 DO mem[i] := v END; dirty := 1
  END FillRow;

  (* Colour n, component c (0 red, 1 green, 2 blue). *)
  PROCEDURE SetPalette*(n, c, v: INTEGER);
  BEGIN
    IF (n >= 0) & (n < 16) & (c >= 0) & (c < 3) THEN pal[n * 3 + c] := v END
  END SetPalette;

  PROCEDURE SetText*(on: BOOLEAN);
  BEGIN IF on THEN text := 1 ELSE text := 0 END; dirty := 1
  END SetText;

  (* The font: 4096 lines of two hex digits. *)
  PROCEDURE LoadFont*(name: ARRAY OF CHAR): BOOLEAN;
    VAR f: Files.File; r: Files.Rider; b: BYTE; c, v, n, i: INTEGER;
  BEGIN f := Files.Old(name); i := 0;
    IF f # NIL THEN
      Files.Set(r, f, 0); v := 0; n := 0;
      Files.ReadByte(r, b);
      WHILE ~r.eof & (i < 4096) DO c := b;
        IF (c >= ORD("0")) & (c <= ORD("9")) THEN v := v * 16 + c - ORD("0"); INC(n)
        ELSIF (c >= ORD("A")) & (c <= ORD("F")) THEN v := v * 16 + c - ORD("A") + 10; INC(n)
        ELSIF (c >= ORD("a")) & (c <= ORD("f")) THEN v := v * 16 + c - ORD("a") + 10; INC(n)
        ELSIF n > 0 THEN font[i] := v MOD 256; INC(i); v := 0; n := 0
        END;
        Files.ReadByte(r, b)
      END;
      IF n > 0 THEN font[i] := v MOD 256; INC(i) END
    END;
    fontLoaded := i = 4096;
    RETURN fontLoaded
  END LoadFont;

  (* The palette index of pixel (x, y), in either mode. *)
  PROCEDURE Pixel*(x, y: INTEGER): INTEGER;
    VAR b, c, a, r: INTEGER;
  BEGIN
    IF text = 0 THEN b := mem[y * bpr + x DIV 2];
      IF ODD(x) THEN r := b DIV 16 ELSE r := b MOD 16 END
    ELSE
      c := mem[(y DIV 16) * 160 + (x DIV 8) * 2]; a := mem[(y DIV 16) * 160 + (x DIV 8) * 2 + 1];
      IF ODD(LSR(font[c * 16 + y MOD 16], 7 - x MOD 8)) THEN r := a MOD 16 ELSE r := a DIV 16 END
    END;
    RETURN r
  END Pixel;

  PROCEDURE Colour(n, r, g, b: INTEGER);
  BEGIN pal[n * 3] := r; pal[n * 3 + 1] := g; pal[n * 3 + 2] := b
  END Colour;

BEGIN dirty := 0; text := 0; fontLoaded := FALSE;
  (* The standard VGA colours, so that a program that does not load the
     palette still shows colour. (On the FPGA it is undefined at reset.) *)
  Colour(0, 0, 0, 0);       Colour(1, 0, 0, 170);    Colour(2, 0, 170, 0);
  Colour(3, 0, 170, 170);   Colour(4, 170, 0, 0);    Colour(5, 170, 0, 170);
  Colour(6, 170, 85, 0);    Colour(7, 170, 170, 170); Colour(8, 85, 85, 85);
  Colour(9, 85, 85, 255);   Colour(10, 85, 255, 85); Colour(11, 85, 255, 255);
  Colour(12, 255, 85, 85);  Colour(13, 255, 85, 255); Colour(14, 255, 255, 85);
  Colour(15, 255, 255, 255)
END EmVideo.
