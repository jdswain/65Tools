MODULE StringTest;
   IMPORT SYSTEM;

   CONST
	  ACIA_DATA = 0C000H;
	  
   TYPE
	  String = ARRAY 255 OF CHAR;
	  
   VAR
	  str: String;
	  x: INTEGER;
	  
   PROCEDURE NewLine();
   BEGIN
	  SYSTEM.PUT(ACIA_DATA, 0AX);
   END NewLine;
   
   PROCEDURE PutChar(value: CHAR);
   BEGIN
	  SYSTEM.PUT(ACIA_DATA, value);
   END PutChar;

   (* VAR open ARRAY doesn't work *)
   PROCEDURE Println(VAR str: ARRAY OF CHAR);
	  VAR
		 i: INTEGER;
   BEGIN
	  i := 0;
   x := LEN(str);
   IF x = 255 THEN
	  PutChar('T');
   ELSE
	  PutChar('F');
   END;
	  (* To Fix: str[200] := 44X; *)
	  (* Output string character by character *)
	  WHILE (str[i] # 0X) DO
		 PutChar(str[i]); i := i + 1
	  END;
   END Println;
   
BEGIN
   str := "String Test";
   Println(str); NewLine();
END StringTest.
