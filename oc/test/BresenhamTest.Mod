MODULE BresenhamTest;
  IMPORT SYSTEM;

  CONST
    ACIA_DATA = 0C000H;
    

 PROCEDURE PutChar(value: CHAR);
 BEGIN
    SYSTEM.PUT(ACIA_DATA, value);
 END PutChar;
 
 PROCEDURE PutHex(value: INTEGER);
    VAR
	   neg: BOOLEAN;
	   digit: INTEGER;
 BEGIN
	neg := value < 0;
	IF neg THEN
	   value := AND(value, 07FFFh);
	   PutChar('-');
	END;
	digit := LSR(value, 4);
    IF digit < 10 THEN
       PutChar(CHR(digit + ORD('0')))
    ELSE
       PutChar(CHR(digit - 10 + ORD('A')))
    END;
    digit := AND(value, 0FFh);
    IF digit < 10 THEN
       PutChar(CHR(digit + ORD('0')))
    ELSE
       PutChar(CHR(digit - 10 + ORD('A')))
    END
  END PutHex;
  
  PROCEDURE NewLine();
  BEGIN
    SYSTEM.PUT(ACIA_DATA, 0AX);
  END NewLine;

  PROCEDURE SetPixel(x, y: INTEGER);
  BEGIN
    (* Implementation left blank for user to fill in *)
    (* For testing, we'll just output the coordinates *)
     PutChar('(');
     PutHex(x);
     PutChar(',');
     PutHex(y);
     PutChar(')');
     PutChar(' ');
  END SetPixel;

  PROCEDURE DrawLine(x0, y0, x1, y1: INTEGER);
    VAR
      dx, dy, sx, sy, err, e2: INTEGER;
      done: BOOLEAN;
  BEGIN
    dx := x1 - x0;
    IF dx < 0 THEN dx := -dx END;
    
    dy := y1 - y0;
    IF dy < 0 THEN dy := -dy END;
    
    IF x0 < x1 THEN sx := 1 ELSE sx := -1 END;
    IF y0 < y1 THEN sy := 1 ELSE sy := -1 END;
    
    err := dx - dy;
    done := FALSE;
    
    WHILE ~done DO
      SetPixel(x0, y0);
      
      IF (x0 = x1) & (y0 = y1) THEN
        done := TRUE
      ELSE
        e2 := 2 * err;
        
        IF e2 > -dy THEN
          err := err - dy;
          x0 := x0 + sx
        END;
        
        IF e2 < dx THEN
          err := err + dx;
          y0 := y0 + sy
        END
      END
    END
  END DrawLine;

BEGIN
  PutChar('B'); PutChar('r'); PutChar('e'); PutChar('s'); PutChar('e'); PutChar('n'); PutChar('h'); PutChar('a'); PutChar('m'); PutChar(' '); 
  PutChar('L'); PutChar('i'); PutChar('n'); PutChar('e'); PutChar(':'); NewLine();
  
  (* Draw a line from (5,3) to (12,8) *)
  DrawLine(5, 3, 12, 8);
  NewLine();
  
  (* Draw a line from (0,0) to (7,4) *)
  DrawLine(0, 0, 7, 4);
  NewLine();
  
  (* Draw a steep line from (2,1) to (4,9) *)
  DrawLine(2, 1, 4, 9);
  NewLine();
END BresenhamTest.