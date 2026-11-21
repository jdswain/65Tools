MODULE EmTMS9918; (* The Mini816's TMS9118 at $C020, which behaves as a
   TMS9918A with 16K of VRAM: its ports, registers and status, the four
   modes and the sprites, a line at a time, in its own time: its crystal
   of 10.738635 MHz, a pixel every two cycles, 342 pixels a line and 262
   lines a frame (59.92 a second).

   The board passes the time in the crystal's cycles (now). Line y of the
   display (0-191) is drawn, and its sprites looked at, as the beam
   leaves it; F is set as line 192 starts, and INT is F with R1's IE.
   Sprites: those on a line in the order of the attribute table to the
   first Y of $D0; the first four shown, the lower numbered in front,
   colour 0 transparent; a fifth sets 5S and its number, if 5S is clear
   (while it is, the low bits hold the number of the last sprite looked
   at); two of the four with a pixel in the same place of the display set
   C, whatever their colours. In text mode there are none; with BL clear
   the display is the backdrop and the sprites are not looked at.

   A frame is drawn into fb, a palette index a pixel, with its border:
   width x height, the display at left, top. It is published as line 192
   starts, dirty set, if SetRender asked: for the window (1, when it has
   taken the last) or for every frame (2, -fbdump's). VRAM may be
   accessed at any rate. The 4K mode (R1 bit 7 clear) and the
   undocumented mixtures of the modes are not there: M1 is text, else M2
   multicolour, else M3 Graphics II, else Graphics I. *)

  CONST
    width* = 288; height* = 240;          (* the frame, the border included *)
    left* = 16; top* = 24;                (* the display's place in it *)
    lineClks = 684; lines = 262;          (* a line in the crystal's cycles; a frame's lines *)

  VAR
    vram*: ARRAY 4000H OF BYTE;
    reg*: ARRAY 8 OF INTEGER;
    status*: INTEGER;
    addr, low, buffer: INTEGER;           (* the address, the setup's first byte, the read-ahead *)
    latched: BOOLEAN;                     (* the setup's first byte written *)
    line: INTEGER;                        (* the line the beam is on *)
    frameAt: LONGINT;                     (* the time the frame began *)
    fb*: ARRAY 69120 OF BYTE;             (* the last frame published, width x height *)
    work: ARRAY 69120 OF BYTE;            (* the frame being drawn *)
    row: ARRAY 256 OF INTEGER;            (* a line of the display, 0 the backdrop *)
    occupied, shown: ARRAY 256 OF BOOLEAN;  (* a sprite's pixel there; a colour *)
    pal*: ARRAY 48 OF BYTE;               (* the colours, R G B *)
    dirty*, frames*: INTEGER;
    render: INTEGER;
    drawing: BOOLEAN;                     (* this frame is drawn *)

  PROCEDURE SetRender*(how: INTEGER);
  BEGIN render := how; drawing := how # 0
  END SetRender;

  PROCEDURE Backdrop(): INTEGER;
  BEGIN RETURN AND(reg[7], 0FH)
  END Backdrop;

  (* --- a line --- *)

  (* 8 pixels of p, MSB first, fg or bg, from row[x] *)
  PROCEDURE Pixels(x, p, fg, bg: INTEGER);
    VAR k: INTEGER;
  BEGIN
    FOR k := 0 TO 7 DO
      IF p >= 80H THEN row[x + k] := fg ELSE row[x + k] := bg END;
      p := AND(p * 2, 0FFH)
    END
  END Pixels;

  PROCEDURE Background(y: INTEGER);
    VAR c, k, n, p, nt, pg, i, fg, bg: INTEGER;
  BEGIN nt := AND(reg[2], 0FH) * 400H; pg := AND(reg[4], 7) * 800H;
    IF ~ODD(reg[1] DIV 40H) THEN
      FOR c := 0 TO 255 DO row[c] := 0 END
    ELSIF ODD(reg[1] DIV 10H) THEN                          (* text, 40 x 24 of 6 x 8 *)
      fg := reg[7] DIV 10H; bg := Backdrop();
      FOR c := 0 TO 7 DO row[c] := 0; row[248 + c] := 0 END;
      FOR c := 0 TO 39 DO
        p := vram[pg + vram[nt + y DIV 8 * 40 + c] * 8 + y MOD 8];
        FOR k := 0 TO 5 DO
          IF p >= 80H THEN row[8 + c * 6 + k] := fg ELSE row[8 + c * 6 + k] := bg END;
          p := AND(p * 2, 0FFH)
        END
      END
    ELSIF ODD(reg[1] DIV 8) THEN                            (* multicolour, 64 x 48 blocks *)
      FOR c := 0 TO 31 DO
        p := vram[pg + vram[nt + y DIV 8 * 32 + c] * 8 + y DIV 8 MOD 4 * 2 + y MOD 8 DIV 4];
        FOR k := 0 TO 3 DO row[c * 8 + k] := p DIV 10H; row[c * 8 + 4 + k] := p MOD 10H END
      END
    ELSE
      FOR c := 0 TO 31 DO n := vram[nt + y DIV 8 * 32 + c];
        IF ODD(reg[0] DIV 2) THEN                           (* Graphics II: a table a third *)
          i := y DIV 64 * 800H + n * 8 + y MOD 8;
          p := vram[AND(reg[4], 4) * 800H + AND(i, AND(reg[4], 3) * 800H + 7FFH)];
          n := vram[AND(reg[3], 80H) * 40H + AND(i, AND(reg[3], 7FH) * 40H + 3FH)]
        ELSE p := vram[pg + n * 8 + y MOD 8]; n := vram[reg[3] * 40H + n DIV 8]
        END;
        Pixels(c * 8, p, n DIV 10H, n MOD 10H)
      END
    END
  END Background;

  (* sprite s's pixel at x of the display *)
  PROCEDURE Dot(x, colour: INTEGER);
  BEGIN
    IF (x >= 0) & (x < 256) THEN
      IF occupied[x] THEN status := ORA(status, 20H) END;
      occupied[x] := TRUE;
      IF (colour # 0) & ~shown[x] THEN row[x] := colour; shown[x] := TRUE END
    END
  END Dot;

  PROCEDURE Sprites(y: INTEGER);
    VAR sat, spg, size, mag, h, i, n, e, dy, x, name, colour, p, k: INTEGER;
      list: ARRAY 4 OF INTEGER; done: BOOLEAN;
  BEGIN sat := AND(reg[5], 7FH) * 80H; spg := AND(reg[6], 7) * 800H;
    IF ODD(reg[1] DIV 2) THEN size := 16 ELSE size := 8 END;
    mag := reg[1] MOD 2; h := size * (mag + 1);
    n := 0; i := 0; done := FALSE;
    WHILE ~done & (i < 32) DO
      IF vram[sat + i * 4] = 0D0H THEN done := TRUE
      ELSIF AND(y - vram[sat + i * 4] - 1, 0FFH) < h THEN
        IF n < 4 THEN list[n] := i; INC(n); INC(i)
        ELSE done := TRUE;
          IF ~ODD(status DIV 40H) THEN status := AND(status, 0A0H) + 40H + i END
        END
      ELSE INC(i)
      END
    END;
    IF i > 31 THEN i := 31 END;
    IF ~ODD(status DIV 40H) THEN status := AND(status, 0E0H) + i END;
    IF n > 0 THEN
      FOR x := 0 TO 255 DO occupied[x] := FALSE; shown[x] := FALSE END;
      FOR i := 0 TO n - 1 DO e := sat + list[i] * 4;
        dy := AND(y - vram[e] - 1, 0FFH) DIV (mag + 1);
        x := vram[e + 1]; name := vram[e + 2]; colour := vram[e + 3] MOD 10H;
        IF vram[e + 3] >= 80H THEN x := x - 32 END;      (* the early clock *)
        IF size = 16 THEN name := AND(name, 0FCH);
          p := vram[spg + name * 8 + dy] * 100H + vram[spg + name * 8 + 16 + dy]
        ELSE p := vram[spg + name * 8 + dy] * 100H
        END;
        FOR k := 0 TO size - 1 DO
          IF p >= 8000H THEN Dot(x + k * (mag + 1), colour); IF mag = 1 THEN Dot(x + k * 2 + 1, colour) END END;
          p := AND(p * 2, 0FFFFH)
        END
      END
    END
  END Sprites;

  (* the line y of the display, as the beam leaves it *)
  PROCEDURE Line(y: INTEGER);
    VAR x, bd, c, o: INTEGER;
  BEGIN
    IF drawing THEN Background(y) END;
    IF ODD(reg[1] DIV 40H) & ~ODD(reg[1] DIV 10H) THEN Sprites(y) END;
    IF drawing THEN bd := Backdrop(); o := (top + y) * width;
      FOR x := 0 TO left - 1 DO work[o + x] := bd; work[o + left + 256 + x] := bd END;
      o := o + left;
      FOR x := 0 TO 255 DO c := row[x]; IF c = 0 THEN c := bd END; work[o + x] := c END
    END
  END Line;

  (* the frame drawn: the borders above and below, then published *)
  PROCEDURE Publish;
    VAR i, bd: INTEGER;
  BEGIN
    IF drawing THEN bd := Backdrop();
      FOR i := 0 TO top * width - 1 DO work[i] := bd END;
      FOR i := (top + 192) * width TO height * width - 1 DO work[i] := bd END;
      FOR i := 0 TO width * height - 1 DO fb[i] := work[i] END;
      dirty := 1
    END;
    INC(frames)
  END Publish;

  (* the beam brought up to now *)
  PROCEDURE Update(now: LONGINT);
  BEGIN
    WHILE frameAt + (line + 1) * lineClks <= now DO
      IF line < 192 THEN Line(line) END;
      INC(line);
      IF line = 192 THEN status := ORA(status, 80H); Publish
      ELSIF line = lines THEN line := 0; frameAt := frameAt + lines * lineClks;
        drawing := (render = 2) OR (render = 1) & (dirty = 0)
      END
    END
  END Update;

  PROCEDURE Tick*(now: LONGINT);
  BEGIN Update(now)
  END Tick;

  (* INT, asserted (low) while F and IE *)
  PROCEDURE Int*(): BOOLEAN;
  BEGIN RETURN ODD(status DIV 80H) & ODD(reg[1] DIV 20H)
  END Int;

  (* MODE (reg 1) the status and the setup, 0 VRAM *)
  PROCEDURE Read*(mode: INTEGER; now: LONGINT): INTEGER;
    VAR v: INTEGER;
  BEGIN Update(now); latched := FALSE;
    IF ODD(mode) THEN v := status; status := AND(status, 1FH)
    ELSE v := buffer; buffer := vram[addr]; addr := (addr + 1) MOD 4000H
    END;
    RETURN v
  END Read;

  PROCEDURE Write*(mode, v: INTEGER; now: LONGINT);
  BEGIN Update(now); v := AND(v, 0FFH);
    IF ~ODD(mode) THEN latched := FALSE; vram[addr] := v; buffer := v; addr := (addr + 1) MOD 4000H
    ELSIF ~latched THEN latched := TRUE; low := v; addr := AND(addr, 3F00H) + v
    ELSE latched := FALSE; addr := AND(v, 3FH) * 100H + low;
      IF v >= 80H THEN reg[AND(v, 7)] := low
      ELSIF v < 40H THEN buffer := vram[addr]; addr := (addr + 1) MOD 4000H   (* a read's: ahead *)
      END
    END
  END Write;

  (* RESB: the registers and the status, not VRAM or the beam *)
  PROCEDURE Reset*;
    VAR i: INTEGER;
  BEGIN FOR i := 0 TO 7 DO reg[i] := 0 END;
    status := 0; addr := 0; low := 0; buffer := 0; latched := FALSE
  END Reset;

  (* the TMS9918A's colours, 0 (transparent) black *)
  PROCEDURE Colours;
    VAR i: INTEGER; c: ARRAY 16 OF INTEGER;
  BEGIN
    c[0] := 000000H; c[1] := 000000H; c[2] := 21C842H; c[3] := 5EDC78H;
    c[4] := 5455EDH; c[5] := 7D76FCH; c[6] := 0D4524DH; c[7] := 42EBF5H;
    c[8] := 0FC5554H; c[9] := 0FF7978H; c[10] := 0D4C154H; c[11] := 0E6CE80H;
    c[12] := 21B03BH; c[13] := 0C95BBAH; c[14] := 0CCCCCCH; c[15] := 0FFFFFFH;
    FOR i := 0 TO 15 DO
      pal[i * 3] := c[i] DIV 10000H; pal[i * 3 + 1] := c[i] DIV 100H MOD 100H; pal[i * 3 + 2] := c[i] MOD 100H
    END
  END Colours;

  PROCEDURE Init;
    VAR i: INTEGER;
  BEGIN
    FOR i := 0 TO LEN(vram) - 1 DO vram[i] := 0 END;
    FOR i := 0 TO LEN(fb) - 1 DO fb[i] := 0; work[i] := 0 END;
    Colours; Reset; line := 0; frameAt := 0; dirty := 0; frames := 0; render := 0; drawing := FALSE
  END Init;

BEGIN Init
END EmTMS9918.
