(* This is a very basic module used for developing the compiler *)
(* JDS 2024 *)

MODULE Resources;

(*IMPORT SYSTEM;*)

CONST
	 PI = 3;
	 WELCOME_STR = "Welecome to Oberon";
	 WELCOME_ICON = [$00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $FF, $FF, $FF, $FF,
					 $FF, $FF, $FF, $FF,
					 $FF, $FF, $FF, $FF,
					 $FF, $FF, $FF, $FF,
					 $FF, $FF, $FF, $FF,
					 $FF, $FF, $FF, $FF,
					 $FF, $FF, $FF, $FF,
					 $FF, $FF, $FF, $FF,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00,
					 $00, $FF, $FF, $00];

VAR
	 a, b, c: INTEGER;

PROCEDURE Called(p1, p2, p3: INTEGER): INTEGER;
VAR
	 x, y, z: INTEGER;
BEGIN
	 x := p1 + p2;
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
	 b := Called(1, 2, 3);
	 PeekPoke
END Main;

END Test.

	 
