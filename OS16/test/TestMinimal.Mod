MODULE TestMinimal;
  IMPORT Driver, FloppyDriver, Files, Out;

  PROCEDURE Run;
    VAR
      drv: Driver.BlockDriver;
      f: Files.File;
      fname: ARRAY 16 OF CHAR;
  BEGIN
    Out.String("A"); Out.Ln;
    FloppyDriver.Init(0, drv);
    Out.String("B"); Out.Ln;
    Files.Format(drv);
    Out.String("C"); Out.Ln;
    Files.Init(drv);
    Out.String("D"); Out.Ln;
    fname := "TEST.TXT";
    f := Files.New(fname);
    IF f # NIL THEN Out.String("E") ELSE Out.String("F") END;
    Out.Ln
  END Run;

BEGIN
  Run
END TestMinimal.
