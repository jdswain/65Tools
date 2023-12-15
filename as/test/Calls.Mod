MODULE App;


PROCEDURE prInt(i: INTEGER);
	 VAR
		  a: INTEGER;
BEGIN
	 a := 48; (* ASCII 0 *)
	 a := a + i;
	 PUT($C000, a);
END prInt;

PROCEDURE main(): INTEGER;
VAR
	 x: INTEGER;
     y: BOOLEAN;
BEGIN
	 PUT($C000, 'X');

	 x := 1 + 2;
	 y := FALSE;
	 prInt(x);
	 prInt(7);

	 IF x > 8 THEN
		  x := 5;
	 END;
(*
	 IF x > 4 THEN
		  x := 5;
     END;
*)	 
	 RETURN x
END main;

END App.

(*
Process

calledProc(x+2)
[oberon_prepCall]
  if proc alloc reg for return
  rx := RH
  saveRegs
[parse_oberon_paramlist]
  r0 := x + 2
[oberon_call]
  saveRegs
  jump to calledProc
  restoreRegs -- to remove params
  restoreRegs rx -- to restore regs before call

PROCEDURE calledProc(i: INTEGER)
  03,S is i
  allocate var stack frame, 2 bytes
  01,S is a
  pop var stack frame, 2 bytes
  store return in 01,S -- this is the last register allocated before the call
  rts

Issues 
  param addresses are incorrect.
  return is stored, make sure it is allocated and used correctly.

a := 48
r0 := a -- load(a)
r1 = i -- load(i)
r0 = i + i -- addOp(r0, r1) -- incorrect
a := r0 -- store(a)

*)
