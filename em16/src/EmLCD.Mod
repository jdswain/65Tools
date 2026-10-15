MODULE EmLCD; (* The RA8889 LCD controller of the L28: 800 x 480 pixels of
   RGB565, reached through two bytes at $0600 (register select or
   status, register data).

   What the L28's Forth uses is emulated: the text engine with the
   built-in 8x16 font, scaled to 12x24 or 16x32 and magnified 1-4
   times; lines and rectangles; the block transfer engine's copy and
   solid fill; the main window offset, the cursor and the backlight.
   The window (EmCocoa.m) reads fb and the exported state from its own
   thread. *)

  IMPORT EmHost;

  CONST
    width* = 800; height* = 480;
    fbSize* = 768000;
    base* = 600H;
    font8x16 = 0; font12x24 = 1; font16x32 = 2;

  VAR
    fb*: ARRAY fbSize OF BYTE;
    dirty*: INTEGER;
    pwmDuty*, cursorVisible*, cursorBlink*, blinkRate*: INTEGER;
    textCursorX*, textCursorY*, fontW*, fontH*: INTEGER;
    displayEnabled*: BOOLEAN;     (* the window is wanted: em16 -console *)

    font: ARRAY 4096 OF BYTE;
    regs: ARRAY 256 OF INTEGER;
    selected: INTEGER;
    displayEnable, textMode, textTransparent: BOOLEAN;
    canvasWidth, canvasHeight: INTEGER;   (* the canvas address, $50-$53, is only stored *)
    activeWinX, activeWinY, activeWinW, activeWinH, mainWinX, mainWinY: INTEGER;
    fontSizeIdx, hScale, vScale: INTEGER;
    fgR, fgG, fgB, bgR, bgG, bgB: INTEGER;
    charLineGap, charSpacing: INTEGER;
    drawX0, drawY0, drawX1, drawY1: INTEGER;
    bteSrcX, bteSrcY, bteDstX, bteDstY, bteWidth, bteHeight: INTEGER;

  PROCEDURE Reset;
    VAR i: INTEGER;
  BEGIN
    FOR i := 0 TO fbSize - 1 DO fb[i] := 0 END;
    FOR i := 0 TO 255 DO regs[i] := 0 END;
    selected := 0; displayEnable := FALSE;
    canvasWidth := width; canvasHeight := height;
    activeWinX := 0; activeWinY := 0; activeWinW := width; activeWinH := height;
    mainWinX := 0; mainWinY := 0;
    textCursorX := 0; textCursorY := 0; textMode := FALSE;
    fontSizeIdx := font12x24; fontW := 12; fontH := 24; hScale := 1; vScale := 1;
    fgR := 255; fgG := 255; fgB := 255; bgR := 0; bgG := 0; bgB := 0;
    textTransparent := FALSE; cursorVisible := 0; cursorBlink := 0; blinkRate := 30;
    charLineGap := 0; charSpacing := 0;
    drawX0 := 0; drawY0 := 0; drawX1 := 0; drawY1 := 0;
    bteSrcX := 0; bteSrcY := 0; bteDstX := 0; bteDstY := 0; bteWidth := 0; bteHeight := 0;
    pwmDuty := 255
  END Reset;

  PROCEDURE Lo(VAR w: INTEGER; v: INTEGER);       (* low byte of a 16 bit register *)
  BEGIN w := ORA(AND(w, 0FF00H), v)
  END Lo;

  PROCEDURE Hi(VAR w: INTEGER; v: INTEGER);       (* high byte *)
  BEGIN w := ORA(AND(w, 0FFH), v * 256)
  END Hi;

  PROCEDURE RGB565(r, g, b: INTEGER): INTEGER;
  BEGIN RETURN (r DIV 8) * 2048 + (g DIV 4) * 32 + b DIV 8
  END RGB565;

  PROCEDURE SetPixel(x, y, r, g, b: INTEGER);
    VAR c, off: INTEGER;
  BEGIN
    IF (x >= 0) & (x < width) & (y >= 0) & (y < height) THEN
      c := RGB565(r, g, b); off := (y * width + x) * 2;
      fb[off] := AND(c, 0FFH); fb[off + 1] := c DIV 256
    END
  END SetPixel;

  PROCEDURE StrErr(s: ARRAY OF CHAR);
  BEGIN EmHost.Str(EmHost.err, s)
  END StrErr;

  PROCEDURE IntErr(x: INTEGER);
  BEGIN EmHost.Int(EmHost.err, x)
  END IntErr;

  PROCEDURE AdvanceCursor;
    VAR ew, eh: INTEGER;
  BEGIN ew := fontW * hScale; eh := fontH * vScale;
    textCursorX := AND(textCursorX + ew + charSpacing, 0FFFFH);
    IF textCursorX + ew > canvasWidth THEN
      textCursorX := 0; textCursorY := AND(textCursorY + eh + charLineGap, 0FFFFH)
    END;
    regs[63H] := AND(textCursorX, 0FFH); regs[64H] := textCursorX DIV 256;
    regs[65H] := AND(textCursorY, 0FFH); regs[66H] := textCursorY DIV 256
  END AdvanceCursor;

  PROCEDURE RenderChar(ch: INTEGER);
    VAR ew, eh, px, py, fx, fy, bx, by, sx, sy: INTEGER;
  BEGIN ew := fontW * hScale; eh := fontH * vScale;
    FOR py := 0 TO eh - 1 DO
      FOR px := 0 TO ew - 1 DO
        fx := px DIV hScale; fy := py DIV vScale;
        IF fontSizeIdx = font8x16 THEN bx := fx; by := fy
        ELSIF fontSizeIdx = font16x32 THEN bx := fx DIV 2; by := fy DIV 2
        ELSE bx := fx * 8 DIV 12; by := fy * 16 DIV 24
        END;
        IF bx >= 8 THEN bx := 7 END;
        IF by >= 16 THEN by := 15 END;
        sx := textCursorX + px; sy := textCursorY + py;
        IF (sx >= 0) & (sx < width) & (sy >= 0) & (sy < height) THEN
          IF ODD(LSR(font[ch * 16 + by], 7 - bx)) THEN SetPixel(sx, sy, fgR, fgG, fgB)
          ELSIF ~textTransparent THEN SetPixel(sx, sy, bgR, bgG, bgB)
          END
        END
      END
    END;
    AdvanceCursor; dirty := 1
  END RenderChar;

  PROCEDURE DrawLine(x0, y0, x1, y1: INTEGER);
    VAR dx, dy, sx, sy, e, e2: INTEGER; done: BOOLEAN;
  BEGIN dx := ABS(x1 - x0); dy := -ABS(y1 - y0);
    IF x0 < x1 THEN sx := 1 ELSE sx := -1 END;
    IF y0 < y1 THEN sy := 1 ELSE sy := -1 END;
    e := dx + dy; done := FALSE;
    REPEAT SetPixel(x0, y0, fgR, fgG, fgB);
      IF (x0 = x1) & (y0 = y1) THEN done := TRUE
      ELSE e2 := 2 * e;
        IF e2 >= dy THEN e := e + dy; x0 := x0 + sx END;
        IF e2 <= dx THEN e := e + dx; y0 := y0 + sy END
      END
    UNTIL done
  END DrawLine;

  PROCEDURE DrawRect(x0, y0, x1, y1: INTEGER; fill: BOOLEAN);
    VAR minX, maxX, minY, maxY, x, y: INTEGER;
  BEGIN
    IF x0 < x1 THEN minX := x0; maxX := x1 ELSE minX := x1; maxX := x0 END;
    IF y0 < y1 THEN minY := y0; maxY := y1 ELSE minY := y1; maxY := y0 END;
    IF fill THEN
      FOR y := minY TO maxY DO FOR x := minX TO maxX DO SetPixel(x, y, fgR, fgG, fgB) END END
    ELSE
      FOR x := minX TO maxX DO SetPixel(x, minY, fgR, fgG, fgB); SetPixel(x, maxY, fgR, fgG, fgB) END;
      FOR y := minY TO maxY DO SetPixel(minX, y, fgR, fgG, fgB); SetPixel(maxX, y, fgR, fgG, fgB) END
    END
  END DrawRect;

  PROCEDURE ExecuteDrawing;
    VAR shape: INTEGER;
  BEGIN shape := AND(regs[67H] DIV 8, 3);
    IF shape = 0 THEN DrawLine(drawX0, drawY0, drawX1, drawY1)
    ELSIF shape = 1 THEN DrawRect(drawX0, drawY0, drawX1, drawY1, AND(regs[67H], 20H) # 0)
    END;
    regs[67H] := AND(regs[67H], 7FH); dirty := 1
  END ExecuteDrawing;

  PROCEDURE CopyPixel(sx, sy, dx, dy: INTEGER);
    VAR s, d: INTEGER;
  BEGIN s := (sy * width + sx) * 2; d := (dy * width + dx) * 2;
    IF (s + 1 < fbSize) & (d + 1 < fbSize) THEN fb[d] := fb[s]; fb[d + 1] := fb[s + 1] END
  END CopyPixel;

  PROCEDURE BlockCopy(sx, sy, dx, dy, w, h: INTEGER);
    VAR row, col: INTEGER;
  BEGIN
    IF (dy < sy) OR (dy = sy) & (dx < sx) THEN
      FOR row := 0 TO h - 1 DO FOR col := 0 TO w - 1 DO
        CopyPixel(sx + col, sy + row, dx + col, dy + row) END END
    ELSE
      FOR row := h - 1 TO 0 BY -1 DO FOR col := w - 1 TO 0 BY -1 DO
        CopyPixel(sx + col, sy + row, dx + col, dy + row) END END
    END
  END BlockCopy;

  PROCEDURE SolidFill(x, y, w, h: INTEGER);
    VAR c, row, col, px, py, off: INTEGER;
  BEGIN c := RGB565(fgR, fgG, fgB);
    FOR row := 0 TO h - 1 DO
      FOR col := 0 TO w - 1 DO px := x + col; py := y + row;
        IF (px < width) & (py < height) THEN
          off := (py * width + px) * 2; fb[off] := AND(c, 0FFH); fb[off + 1] := c DIV 256
        END
      END
    END
  END SolidFill;

  PROCEDURE ExecuteBTE;
    VAR ctrl, op: INTEGER;
  BEGIN ctrl := regs[91H]; op := AND(ctrl DIV 2, 7);
    StrErr("[LCD] BTE op="); IntErr(op); StrErr(" ctrl1=0x"); EmHost.Hex(EmHost.err, ctrl, 2);
    StrErr(" dst=("); IntErr(bteDstX); StrErr(","); IntErr(bteDstY);
    StrErr(") src=("); IntErr(bteSrcX); StrErr(","); IntErr(bteSrcY);
    StrErr(") size="); IntErr(bteWidth); StrErr("x"); IntErr(bteHeight);
    StrErr(" fg=("); IntErr(fgR); StrErr(","); IntErr(fgG); StrErr(","); IntErr(fgB);
    StrErr(")"); EmHost.Ln(EmHost.err);
    IF op = 1 THEN BlockCopy(bteSrcX, bteSrcY, bteDstX, bteDstY, bteWidth, bteHeight)
    ELSIF op = 3 THEN SolidFill(bteDstX, bteDstY, bteWidth, bteHeight)
    ELSE StrErr("[LCD] BTE: unhandled op "); IntErr(op); EmHost.Ln(EmHost.err)
    END;
    regs[91H] := AND(regs[91H], 0FEH); dirty := 1
  END ExecuteBTE;

  PROCEDURE UpdateFontSize;
  BEGIN
    IF fontSizeIdx = font8x16 THEN fontW := 8; fontH := 16
    ELSIF fontSizeIdx = font16x32 THEN fontW := 16; fontH := 32
    ELSE fontW := 12; fontH := 24
    END
  END UpdateFontSize;

  PROCEDURE Colour(name: ARRAY OF CHAR; VAR c: INTEGER; v: INTEGER);
  BEGIN c := v; StrErr("[LCD] "); StrErr(name); StrErr("="); IntErr(v); EmHost.Ln(EmHost.err)
  END Colour;

  PROCEDURE WriteRegister(reg, v: INTEGER);
  BEGIN regs[reg] := v;
    CASE reg OF
      0: IF ODD(v) THEN Reset END
    | 1: displayEnable := v >= 80H; dirty := 1
    | 3: textMode := AND(v, 4) # 0
    | 4:
        IF textMode THEN
          StrErr("[LCD] renderChar '");
          IF (v >= 20H) & (v < 7FH) THEN EmHost.Ch(EmHost.err, CHR(v)) ELSE StrErr(".") END;
          StrErr("' (0x"); EmHost.Hex(EmHost.err, v, 2); StrErr(") at cursor (");
          IntErr(textCursorX); StrErr(","); IntErr(textCursorY); StrErr(") fg=(");
          IntErr(fgR); StrErr(","); IntErr(fgG); StrErr(","); IntErr(fgB); StrErr(") bg=(");
          IntErr(bgR); StrErr(","); IntErr(bgG); StrErr(","); IntErr(bgB); StrErr(")");
          EmHost.Ln(EmHost.err);
          RenderChar(v)
        END
    | 26H: Lo(mainWinX, v) | 27H: Hi(mainWinX, v)
    | 28H: Lo(mainWinY, v) | 29H: Hi(mainWinY, v)
    | 40H: cursorVisible := LSR(v, 6) MOD 2; cursorBlink := LSR(v, 5) MOD 2; dirty := 1
    | 44H: blinkRate := v
    | 54H: Lo(canvasWidth, v) | 55H: Hi(canvasWidth, v)
    | 56H: Lo(activeWinX, v) | 57H: Hi(activeWinX, v)
    | 58H: Lo(activeWinY, v) | 59H: Hi(activeWinY, v)
    | 5AH: Lo(activeWinW, v) | 5BH: Hi(activeWinW, v)
    | 5CH: Lo(activeWinH, v) | 5DH: Hi(activeWinH, v)
    | 63H: Lo(textCursorX, v) | 64H: Hi(textCursorX, v)
    | 65H: Lo(textCursorY, v) | 66H: Hi(textCursorY, v)
    | 67H: IF v >= 80H THEN ExecuteDrawing END
    | 68H: Lo(drawX0, v) | 69H: Hi(drawX0, v)
    | 6AH: Lo(drawY0, v) | 6BH: Hi(drawY0, v)
    | 6CH: Lo(drawX1, v) | 6DH: Hi(drawX1, v)
    | 6EH: Lo(drawY1, v) | 6FH: Hi(drawY1, v)
    | 87H: pwmDuty := v; dirty := 1
    | 91H: IF v # 0 THEN ExecuteBTE END
    | 98H: Lo(bteSrcX, v) | 99H: Hi(bteSrcX, v)
    | 9AH: Lo(bteSrcY, v) | 9BH: Hi(bteSrcY, v)
    | 0A2H: Lo(bteDstX, v) | 0A3H: Hi(bteDstX, v)
    | 0A4H: Lo(bteDstY, v) | 0A5H: Hi(bteDstY, v)
    | 0A6H: Lo(bteWidth, v) | 0A7H: Hi(bteWidth, v)
    | 0A8H: Lo(bteHeight, v) | 0A9H: Hi(bteHeight, v)
    | 0CCH: fontSizeIdx := AND(v DIV 16, 3); UpdateFontSize
    | 0CDH: textTransparent := ODD(v); hScale := AND(v DIV 4, 3) + 1; vScale := AND(v DIV 16, 3) + 1
    | 0D0H: charLineGap := v
    | 0D1H: charSpacing := v
    | 0D2H: Colour("FG R", fgR, v); dirty := 1
    | 0D3H: Colour("FG G", fgG, v); dirty := 1
    | 0D4H: Colour("FG B", fgB, v); dirty := 1
    | 0D5H: Colour("BG R", bgR, v)
    | 0D6H: Colour("BG G", bgG, v)
    | 0D7H: Colour("BG B", bgB, v)
    ELSE (* the panel timings and the rest are only stored *)
    END
  END WriteRegister;

  (* Offset 0: status (always ready) / register select; 1: data. *)
  PROCEDURE GetByte*(offset: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF offset = 0 THEN r := 80H ELSE r := regs[selected] END;
    RETURN r
  END GetByte;

  PROCEDURE SetByte*(offset, data: INTEGER);
  BEGIN
    IF offset = 0 THEN selected := data ELSE WriteRegister(selected, data) END
  END SetByte;

  PROCEDURE EnableDisplay*;
  BEGIN displayEnabled := TRUE
  END EnableDisplay;

BEGIN displayEnabled := FALSE; dirty := 0; EmHost.Font(font); Reset
END EmLCD.
