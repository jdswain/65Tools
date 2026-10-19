MODULE UIGraphics;
  PROCEDURE DrawGlyph*(fontAddr, fontBank, ch, x, y, color: INTEGER): INTEGER; BEGIN RETURN 0 END DrawGlyph;
  PROCEDURE DrawLine*(x1, y1, x2, y2, width, color: INTEGER); BEGIN END DrawLine;
  PROCEDURE FillRect*(x, y, w, h, color: INTEGER); BEGIN END FillRect;
  PROCEDURE GetPixel*(x, y: INTEGER): INTEGER; BEGIN RETURN 0 END GetPixel;
  PROCEDURE InitGraphics*; BEGIN END InitGraphics;
  PROCEDURE SetPixel*(x, y, c: INTEGER); BEGIN END SetPixel;
END UIGraphics.
