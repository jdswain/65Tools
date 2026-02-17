MODULE TestFilesDebug;
  IMPORT Driver, FloppyDriver, Files, Out;

  VAR
    s: ARRAY 16 OF CHAR;

  PROCEDURE Run;
    VAR drv: Driver.BlockDriver;
        f: Files.File;
        r: Files.Rider;
        b: BYTE;
        len, res: INTEGER;
        fname: ARRAY 16 OF CHAR;
  BEGIN
    FloppyDriver.Init(0, drv);
    Files.Format(drv);
    Files.Init(drv);
    s := "Init OK"; Out.String(s); Out.Ln;

    fname := "TEST.TXT";
    f := Files.New(fname);
    IF f = NIL THEN s := "New=NIL"; Out.String(s); Out.Ln
    ELSE
      s := "New OK"; Out.String(s); Out.Ln;
      Files.Set(r, f, 0);
      Files.Write(r, 72);
      len := Files.Length(f);
      s := "len="; Out.String(s); Out.Int(len, 1); Out.Ln;
      s := "Reg.."; Out.String(s); Out.Ln;
      Files.Register(f);
      s := "Cls.."; Out.String(s); Out.Ln;
      Files.Close(f);
      s := "Done"; Out.String(s); Out.Ln
    END
  END Run;

BEGIN
  Run
END TestFilesDebug.
