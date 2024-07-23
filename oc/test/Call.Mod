(* This is a very basic module used for developing the compiler *)
(* JDS 2024 *)

MODULE Call;

IMPORT SYSTEM;

CONST
	 VID_BASE = $9000;

VAR
	 a, b, c: INTEGER;
	 f: BOOLEAN;

PROCEDURE Called(p1, p2, p3: INTEGER): INTEGER;
VAR
	 x, y, z: INTEGER;
BEGIN
	 x := p1 * ABS(p2);
	 a := x + 100;
	 RETURN x
END Called;

PROCEDURE PeekPoke();
VAR
	 i: INTEGER;
BEGIN
(*	 SYSTEM.PUT(i, 0)*)
END PeekPoke;

PROCEDURE Main*();
BEGIN
	 f := false;
	 
	 a := 1;
	 b := 127;

	 (* Graphics *)
	 SYSTEM.PUT(VID_BASE, %01010101);
	 SYSTEM.PUT(VID_BASE+2, $ff)
			   
 (*	 IF (a # 45) & (a # 46) THEN b := Called(27, -a, 3) END *)
END Main;

END Call.

	 
