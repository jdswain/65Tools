MODULE FillDiag;
  IMPORT UIGraphics, Out;
VAR x, y, c, found: INTEGER;
BEGIN
  UIGraphics.FillRect(0, 0, 640, 480, 1);
  found := 0;
  (* Scan rows 0-20, right side pixels *)
  FOR y := 0 TO 20 DO
    FOR x := 370 TO 639 DO
      c := UIGraphics.GetPixel(x, y);
      IF c # 1 THEN
        Out.Int(y, 4); Out.Int(x, 5); Out.Int(c, 3); Out.Ln;
        found := found + 1;
        IF found > 20 THEN
          Out.Int(99, 0); Out.Ln;
          ASSERT(FALSE)
        END
      END
    END
  END;
  (* Also check row 409 *)
  FOR x := 370 TO 639 DO
    c := UIGraphics.GetPixel(x, 409);
    IF c # 1 THEN
      Out.Int(409, 4); Out.Int(x, 5); Out.Int(c, 3); Out.Ln;
      found := found + 1;
      IF found > 20 THEN
        Out.Int(99, 0); Out.Ln;
        ASSERT(FALSE)
      END
    END
  END;
  Out.Int(found, 0); Out.Ln;
  Out.Int(99, 0); Out.Ln
END FillDiag.
