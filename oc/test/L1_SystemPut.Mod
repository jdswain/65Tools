MODULE L1_SystemPut;
  IMPORT SYSTEM, Out;
  CONST ACIA = 0C000H;
BEGIN
  SYSTEM.PUT(0, ACIA, ORD("H"));
  SYSTEM.PUT(0, ACIA, ORD("i"));
  SYSTEM.PUT(0, ACIA, 0AH);
  Out.Char("."); Out.Ln()
END L1_SystemPut.
