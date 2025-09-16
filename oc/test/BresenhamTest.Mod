MODULE BresenhamTest;
   IMPORT SYSTEM;
	  
   CONST
      ACIA_DATA = 0C000H;
      SCREEN_BUFFER = 08000H;
	  SCREEN_WIDTH_BYTES = 320 DIV 8;
	  
   PROCEDURE PutChar(value: CHAR);
   BEGIN
      SYSTEM.PUT(ACIA_DATA, value);
   END PutChar;
   
   PROCEDURE PutDigit(d: INTEGER);
   BEGIN
	  d := AND(d, 0FH);
      IF d < 10 THEN
		 PutChar(CHR(d + ORD('0')))
      ELSE
		 PutChar(CHR(d - 10 + ORD('A')))
      END;
   END PutDigit;
 
 (* FOR now we just print the hex value, it IS up TO the use TO interpret this as negative *)
   PROCEDURE PutHex(value: INTEGER);
      VAR
		 d0, d1, d2, d3: INTEGER;
   BEGIN
	  d0 := value;
	  d1 := LSR(value, 4);
	  d2 := LSR(value, 4);
	  d3 := LSR(value, 4);
	  PutDigit(d3);
	  PutDigit(d2);
	  PutDigit(d1);
	  PutDigit(d0);
   END PutHex;
   
   PROCEDURE NewLine();
   BEGIN
      SYSTEM.PUT(ACIA_DATA, 0AX);
   END NewLine;
   
   PROCEDURE SetPixel(x, y: INTEGER);
	  VAR
		 addr: INTEGER;
		 data, n: BYTE;
   BEGIN
      (* For testing, we'll just output the coordinates * )
      PutChar('(');
      PutHex(x);
      PutChar(',');
      PutHex(y);
      PutChar(')');
      PutChar(' ');
	  NewLine();
      *)
	  
	  addr := y * SCREEN_WIDTH_BYTES;
	  addr := addr + x DIV 8;

	  n := {x MOD 8};
	  data := SYSTEM.GET(addr);
	  data := data + n;
	  SYSTEM.PUT(addr, value);

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
			done := TRUE;
			PutChar('D'); PutChar('O'); PutChar('N'); PutChar('E'); NewLine();
		 ELSE
			e2 := 2 * err;
			
			IF e2 > -dy THEN
			   err := err - dy;
			   x0 := x0 + sx
			END;
			
			IF e2 < dx THEN
			   err := err + dx;
			   y0 := y0 + sy
			END;
			
		 END
		 
      END;
   END DrawLine;
   
BEGIN
   PutChar('B'); PutChar('r'); PutChar('e'); PutChar('s'); PutChar('e'); PutChar('n'); PutChar('h'); PutChar('a'); PutChar('m'); PutChar(' '); 
   PutChar('L'); PutChar('i'); PutChar('n'); PutChar('e'); PutChar(':'); NewLine();

   (* Draw a line from (5,3) to (12,8) *)
   DrawLine(12, 8, 5, 3);
   NewLine();

   (* Draw a line from (0,0) to (7,4) *)
   DrawLine(0, 0, 7, 4);
   NewLine();
  
   (* Draw a steep line from (2,1) to (4,9) *)
   DrawLine(2, 1, 4, 9);
   NewLine();

END BresenhamTest.