MODULE TestTool;
   IMPORT SYSTEM;
	  
   CONST
	  ACIA_DATA = 0C000H;
	  
   TYPE
	  String = ARRAY 250 OF CHAR;
	  
   VAR
	  str: String;
	  
   PROCEDURE NewLine*;
   BEGIN
	  SYSTEM.PUT(ACIA_DATA, 0AX);
   END NewLine;
   
   PROCEDURE PutChar*(value: CHAR);
   BEGIN
	  SYSTEM.PUT(ACIA_DATA, value);
   END PutChar;

   PROCEDURE Println*(VAR str: ARRAY OF CHAR);
	  VAR
		 i: INTEGER;
   BEGIN
	  i := 0;
	  WHILE (str[i] # 0X) DO
		 PutChar(str[i]); i := i + 1
	  END;
   END Println;
   
BEGIN
   str := "Test Tool Begin";
   Println(str); NewLine();
END TestTool.
