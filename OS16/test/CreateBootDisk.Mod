MODULE CreateBootDisk;
  IMPORT Driver, FloppyDriver, Files, Out;

  VAR
    pass, fail, sp: ARRAY 8 OF CHAR;

  PROCEDURE PrintResult(cond: BOOLEAN);
  BEGIN
    IF cond THEN Out.String(pass)
    ELSE Out.String(fail)
    END;
    Out.Ln
  END PrintResult;

  PROCEDURE Run;
    VAR
      drv: Driver.BlockDriver;
      res: INTEGER;
      ok: BOOLEAN;
      name: ARRAY 128 OF CHAR;
  BEGIN
    FloppyDriver.Init(0, drv);

    (* Test 1: Format disk *)
    Out.Int(1, 1); Out.String(sp);
    Files.Format(drv);
    Files.Init(drv);
    Out.String(pass); Out.Ln;

    (* Test 2: Create /Library *)
    Out.Int(2, 1); Out.String(sp);
    name := "Library";
    Files.CreateDir(name, res);
    PrintResult(res = 0);

    (* Test 3: Create /Library/Modules *)
    Out.Int(3, 1); Out.String(sp);
    name := "Library/Modules";
    Files.CreateDir(name, res);
    PrintResult(res = 0);

    (* Test 4: Create /Library/Fonts *)
    Out.Int(4, 1); Out.String(sp);
    name := "Library/Fonts";
    Files.CreateDir(name, res);
    PrintResult(res = 0);

    (* Test 5: Create /Documents *)
    Out.Int(5, 1); Out.String(sp);
    name := "Documents";
    Files.CreateDir(name, res);
    PrintResult(res = 0);

    (* Test 6: Create /Applications *)
    Out.Int(6, 1); Out.String(sp);
    name := "Applications";
    Files.CreateDir(name, res);
    PrintResult(res = 0);

    Out.String("Done"); Out.Ln
  END Run;

BEGIN
  pass := " PASS";
  fail := " FAIL";
  sp := " ";
  Run
END CreateBootDisk.
