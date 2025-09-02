MODULE ArrayTestNoLoop;
IMPORT SYSTEM;

PROCEDURE PutByte(value: INTEGER);
CONST
  ACIA_DATA = 0C000H;
BEGIN
  SYSTEM.PUT(ACIA_DATA, value);
END PutByte;

VAR
  arr: ARRAY 3 OF INTEGER;

BEGIN
  arr[0] := 65;
  PutByte(arr[0]);
END ArrayTestNoLoop.