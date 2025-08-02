MODULE PutTest;
IMPORT SYSTEM;

PROCEDURE Main;
CONST		  
    ACIA_BASE = 0C000H;
    ACIA_DATA = ACIA_BASE+0;
    ACIA_RESET = ACIA_BASE+1;
VAR
    h, e, l, o, zero: BYTE;
BEGIN
    h := 48H;
    e := 45H; 
    l := 4CH;
    o := 4FH;
    zero := 0;
    
    SYSTEM.PUT(ACIA_DATA, h);     (* PUT($C000, 'H') *)
    SYSTEM.PUT(ACIA_DATA, e);     (* PUT($C000, 'E') *)
    SYSTEM.PUT(ACIA_DATA, l);     (* PUT($C000, 'L') *)
    SYSTEM.PUT(ACIA_DATA, l);     (* PUT($C000, 'L') *)
    SYSTEM.PUT(ACIA_DATA, o);     (* PUT($C000, 'O') *)
    SYSTEM.PUT(ACIA_RESET, zero); (* PUT($C001, 0) - pause the simulator *)
END Main;

BEGIN
    Main
END PutTest.
