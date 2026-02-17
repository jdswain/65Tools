MODULE Driver;

TYPE
  CharDriver* = POINTER TO CharDriverDesc;
  CharDriverDesc* = RECORD
    name*: ARRAY 16 OF CHAR;
    read*: PROCEDURE(d: CharDriver): INTEGER;
    write*: PROCEDURE(d: CharDriver; c: CHAR): INTEGER;
    get*: PROCEDURE(d: CharDriver; key: INTEGER; VAR val: INTEGER);
    set*: PROCEDURE(d: CharDriver; key: INTEGER; val: INTEGER);
  END;

  BlockDriver* = POINTER TO BlockDriverDesc;
  BlockDriverDesc* = RECORD
    name*: ARRAY 16 OF CHAR;
    read*: PROCEDURE(d: BlockDriver; block: INTEGER; VAR buf: ARRAY OF BYTE): INTEGER;
    write*: PROCEDURE(d: BlockDriver; block: INTEGER; VAR buf: ARRAY OF BYTE): INTEGER;
    get*: PROCEDURE(d: BlockDriver; key: INTEGER; VAR val: INTEGER);
    set*: PROCEDURE(d: BlockDriver; key: INTEGER; val: INTEGER);
  END;

END Driver.
