MODULE L1_SystemPut;
  IMPORT SYSTEM, Out;
  CONST ACIA = 0C000H;
BEGIN
  SYSTEM.PUT(ACIA, ORD("H"));
  SYSTEM.PUT(ACIA, ORD("i"));
  SYSTEM.PUT(ACIA, 0AH);
  Out.Char("."); Out.Ln()
END L1_SystemPut.
