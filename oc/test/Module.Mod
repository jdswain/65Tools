(* This is a very basic module used for developing the compiler *)
(* JDS 2014 *)

MODULE Test;

VAR
	 a, b, c: INTEGER;

PROCEDURE Command*();
BEGIN
	 a := 1;
	 c := a + 100 - 20;
	 return c   
END Command;

END Test.
