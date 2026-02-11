MODULE L4_TypeDesc;
  IMPORT Out, SYSTEM;
  TYPE Node = RECORD val: INTEGER; next: POINTER TO Node END;
  VAR first: INTEGER;
      tdBase, w: INTEGER;
BEGIN
  tdBase := SYSTEM.ADR(first) - 24;
  SYSTEM.GET(tdBase, w);      Out.Int(w, 1); Out.Ln;
  SYSTEM.GET(tdBase + 4, w);  Out.Int(w, 1); Out.Ln;
  SYSTEM.GET(tdBase + 16, w); Out.Int(w, 1); Out.Ln;
  SYSTEM.GET(tdBase + 20, w); Out.Int(w, 1); Out.Ln
END L4_TypeDesc.
