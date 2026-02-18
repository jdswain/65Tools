MODULE UIText;
  IMPORT UIGraphics, SYSTEM;

  PROCEDURE DrawChar*(T: ARRAY OF INTEGER; ch, x, y, color: INTEGER): INTEGER;
  BEGIN
    RETURN UIGraphics.DrawGlyph(SYSTEM.ADR(T), SYSTEM.BANK(T), ch, x, y, color)
  END DrawChar;

  PROCEDURE DrawString*(T: ARRAY OF INTEGER; s: ARRAY OF CHAR; x, y, color: INTEGER): INTEGER;
    VAR i, dx: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO
      dx := UIGraphics.DrawGlyph(SYSTEM.ADR(T), SYSTEM.BANK(T), ORD(s[i]), x, y, color);
      x := x + dx;
      i := i + 1
    END;
    RETURN x
  END DrawString;

  PROCEDURE StringWidth*(T: ARRAY OF INTEGER; raster: ARRAY OF BYTE; s: ARRAY OF CHAR): INTEGER;
    VAR i, w: INTEGER;
  BEGIN
    w := 0; i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO
      IF T[ORD(s[i])] # 0 THEN
        w := w + raster[T[ORD(s[i])]]
      END;
      i := i + 1
    END;
    RETURN w
  END StringWidth;

  PROCEDURE TextHeight*(raster: ARRAY OF BYTE): INTEGER;
    VAR h: INTEGER;
  BEGIN
    h := raster[0];
    RETURN h
  END TextHeight;

  PROCEDURE Ascent*(raster: ARRAY OF BYTE): INTEGER;
    VAR a: INTEGER;
  BEGIN
    a := raster[1];
    RETURN a
  END Ascent;

  PROCEDURE Descent*(raster: ARRAY OF BYTE): INTEGER;
    VAR d: INTEGER;
  BEGIN
    d := raster[2];
    IF d >= 80H THEN d := d - 100H END;
    RETURN d
  END Descent;

  PROCEDURE CharWidth*(T: ARRAY OF INTEGER; raster: ARRAY OF BYTE; ch: INTEGER): INTEGER;
    VAR w: INTEGER;
  BEGIN
    IF T[ch] # 0 THEN w := raster[T[ch]] ELSE w := 0 END;
    RETURN w
  END CharWidth;

END UIText.
