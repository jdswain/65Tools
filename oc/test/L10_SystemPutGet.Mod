MODULE L10_SystemPutGet;
  IMPORT SYSTEM, Out;
  VAR x, y: INTEGER;
      addr: INTEGER;
BEGIN
  addr := 2000H;
  SYSTEM.PUT(addr, 1234);
  SYSTEM.GET(addr, y);
  Out.Int(y, 1); Out.Ln();

  addr := 2002H;
  SYSTEM.PUT(addr, -99);
  SYSTEM.GET(addr, y);
  Out.Int(y, 1); Out.Ln();

  (* PUT then GET at same address with variable *)
  x := 5678;
  addr := 2004H;
  SYSTEM.PUT(addr, x);
  SYSTEM.GET(addr, y);
  Out.Int(y, 1); Out.Ln()
END L10_SystemPutGet.
