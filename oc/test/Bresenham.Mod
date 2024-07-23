MODULE BresenhamLineAlgorithm;

(* Bresenham's Line Algorithm in Oberon *)

IMPORT SYSTEM;

PROCEDURE DrawLine(x0, y0, x1, y1: INTEGER);
  VAR dx, dy, sx, sy, err, e2: INTEGER;
      done: BOOLEAN;
BEGIN
  dx := ABS(x1 - x0);
  dy := ABS(y1 - y0);
  
  IF x0 < x1 THEN sx := 1 ELSE sx := -1 END;
  IF y0 < y1 THEN sy := 1 ELSE sy := -1 END;
  
  err := dx - dy;
  
  REPEAT
    Out.String("Pixel at ("); Out.Int(x0, 0); Out.String(", "); Out.Int(y0, 0); Out.String(")"); Out.Ln;
    
    IF (x0 = x1) & (y0 = y1) THEN
      done := TRUE;
    ELSE
      e2 := 2 * err;
      IF e2 > -dy THEN
        err := err - dy;
        x0 := x0 + sx;
      END;
      IF e2 < dx THEN
        err := err + dx;
        y0 := y0 + sy;
      END;
    END;
  UNTIL done;
  
END DrawLine;

BEGIN
  (* Example usage *)
  DrawLine(1, 1, 8, 4); (* Draws a line from (1, 1) to (8, 4) *)
END BresenhamLineAlgorithm.
