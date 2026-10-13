IMPORT "Console"

(* A simple boot monitor, intended to be loaded into ROM. *)
	   
MODULE AsmTest;

PROCEDURE Cold;
BEGIN
	ASM BEGIN
		  CLD
	END
    Warm;
END

PROCEDURE Warm;
VAR
	  buffer: ARRAY 80 OF CHAR;
BEGIN
	  Console.PrintLn("MiniMon V 1.0");
	  Console.ReadLn(buffer);
	  Interp(buffer);
END


PROCEDURE Interp(buffer: POINTER TO ARRAY 80 of CHAR);
BEGIN
END
	 
	
END AsmTest.
