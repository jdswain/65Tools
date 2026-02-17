MODULE TestDelete;
  IMPORT Driver, FloppyDriver, Files, Out;

  VAR
    s: ARRAY 16 OF CHAR;

  PROCEDURE Run;
    VAR drv: Driver.BlockDriver;
        f, g: Files.File;
        r: Files.Rider;
        res: INTEGER;
        fname: ARRAY 16 OF CHAR;
  BEGIN
    FloppyDriver.Init(0, drv);
    Files.Format(drv);
    Files.Init(drv);

    (* Test pointer NIL comparison *)
    f := NIL;
    IF f = NIL THEN s := "f=NIL ok" ELSE s := "f=NIL BAD" END;
    Out.String(s); Out.Ln;

    fname := "TEST.TXT";
    f := Files.New(fname);
    Files.Set(r, f, 0);
    Files.Write(r, 72);
    Files.Register(f);
    Files.Close(f);
    s := "Reg OK"; Out.String(s); Out.Ln;

    fname := "TEST.TXT";
    Files.Delete(fname, res);
    s := "Del "; Out.String(s); Out.Int(res, 1); Out.Ln;

    (* Set f to something non-NIL first *)
    fname := "DUMMY.TXT";
    g := Files.New(fname);
    s := "g new ok"; Out.String(s); Out.Ln;

    (* Now call Old on deleted file - should return NIL *)
    fname := "TEST.TXT";
    f := Files.Old(fname);
    IF f = NIL THEN
      s := "Old=NIL"; Out.String(s); Out.Ln
    ELSE
      s := "Old!=NIL"; Out.String(s); Out.Ln
    END;

    (* Also test: set f to NIL manually then compare *)
    f := NIL;
    IF f = NIL THEN s := "ok2" ELSE s := "BAD2" END;
    Out.String(s); Out.Ln;

    s := "Done"; Out.String(s); Out.Ln
  END Run;

BEGIN
  Run
END TestDelete.
