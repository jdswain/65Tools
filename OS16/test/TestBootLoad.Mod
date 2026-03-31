MODULE TestBootLoad;
  IMPORT Driver, FloppyDriver, Files, Out, Modules;

  PROCEDURE Run;
    VAR
      drv: Driver.BlockDriver;
      res: INTEGER;
  BEGIN
    FloppyDriver.Init(0, drv);
    Files.Init(drv);
    Out.String("Disk initialized"); Out.Ln;

    Modules.Load("Hello", res);
    IF res = 0 THEN
      Out.String("PASS"); Out.Ln
    ELSE
      Out.String("FAIL res="); Out.Int(res, 1); Out.Ln
    END
  END Run;

BEGIN
  Run
END TestBootLoad.
