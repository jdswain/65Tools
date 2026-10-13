MODULE App;

PROCEDURE takeSomeSpace(i: INTEGER);
	 VAR
		  a: INTEGER;
BEGIN
	 a := 7;
	 a := a + i;
END takeSomeSpace;

PROCEDURE anotherOne();
	 VAR
		  x: INTEGER;
BEGIN
	 takeSomeSpace(x);
END anotherOne;
	 
PROCEDURE main(): INTEGER;
VAR
	  x: INTEGER;
	  i: INTEGER;
	  j: INTEGER;
BEGIN
	 PUT($C000, 'H');
	 PUT($C000, 'e');
	 PUT($C000, 'l');
	 PUT($C000, 'l');
	 PUT($C000, 'o');
	 PUT($C000, '!');
	 PUT($C000, '\r');
	 PUT($C000, '\n');
	 x := 11 + 2;
	 i := 2000; 
	 j := i + 10 - x + 7; (* Result is 2004, which is $7d4 *)
	 takeSomeSpace(x);
	 anotherOne();
	 RETURN j
END main;

(* Closure style...

TYPE
	 sortClosure: PROCEDURE(^Object left, ^Object right): Int;

PROCEDURE closure;
BEGIN
	 map.sort [(left, right)
			   BEGIN
					return left < right;
			   END
			  ];
END
*)	 

(* This is a very simple function *)
(* 
The code generated should be: 

1. Function stack frame setup including correct size

test:  tsa
       sec
       adc #$02
       tas

2. Assign constant to variable

       lda #$000a
	   sta 0,s

3. Function stack cleanup and return

       tsa
       clc
       adc #$02
       tas

       rts

 *)

(*
PROCEDURE ret(): BOOLEAN;
VAR
	 a: INTEGER;
BEGIN
	 a := 0;
	 test();
	 IF 0 THEN a := 4 END;
	 RETURN (a+2)
END ret;
 *)

END App.
