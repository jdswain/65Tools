MODULE L10_SystemAdr;
  IMPORT SYSTEM, Out;
  VAR x: INTEGER;
      addr: INTEGER;
BEGIN
  x := 42;
  addr := SYSTEM.ADR(x);
  (* Verify ADR returns a non-zero address *)
  IF addr # 0 THEN
    Out.Int(1, 1); Out.Ln()
  ELSE
    Out.Int(0, 1); Out.Ln()
  END;

  (* Write through address using GET/PUT *)
  SYSTEM.PUT(addr, 99);
  Out.Int(x, 1); Out.Ln()
END L10_SystemAdr.
