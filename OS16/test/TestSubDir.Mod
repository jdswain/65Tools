MODULE TestSubDir;
  IMPORT Driver, FloppyDriver, Files, Out;

  VAR
    pass, fail, sp, done: ARRAY 8 OF CHAR;

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
      f: Files.File;
      r: Files.Rider;
      b: BYTE;
      i, n, res, len: INTEGER;
      ok: BOOLEAN;
      fname: ARRAY 32 OF CHAR;
  BEGIN
    (* Initialize floppy driver *)
    FloppyDriver.Init(0, drv);

    (* Test 1: Format and Init *)
    Out.Int(1, 1); Out.String(sp);
    Files.Format(drv);
    Files.Init(drv);
    Out.String(pass); Out.Ln;

    (* Test 2: CreateDir "SUB" in root *)
    Out.Int(2, 1); Out.String(sp);
    fname := "SUB";
    Files.CreateDir(fname, res);
    PrintResult(res = 0);

    (* Test 3: Create file in subdirectory *)
    Out.Int(3, 1); Out.String(sp);
    fname := "SUB/hello.txt";
    f := Files.New(fname);
    PrintResult(f # NIL);

    (* Test 4: Write "Hello" to SUB/hello.txt *)
    Out.Int(4, 1); Out.String(sp);
    Files.Set(r, f, 0);
    Files.Write(r, ORD("H"));
    Files.Write(r, ORD("e"));
    Files.Write(r, ORD("l"));
    Files.Write(r, ORD("l"));
    Files.Write(r, ORD("o"));
    Files.Register(f);
    Files.Close(f);
    Out.String(pass); Out.Ln;

    (* Test 5: Reopen SUB/hello.txt with Old *)
    Out.Int(5, 1); Out.String(sp);
    fname := "SUB/hello.txt";
    f := Files.Old(fname);
    PrintResult(f # NIL);

    (* Test 6: Verify length = 5 *)
    Out.Int(6, 1); Out.String(sp);
    len := Files.Length(f);
    PrintResult(len = 5);

    (* Test 7: Read back and verify content *)
    Out.Int(7, 1); Out.String(sp);
    Files.Set(r, f, 0);
    ok := TRUE;
    Files.Read(r, b); IF b # ORD("H") THEN ok := FALSE END;
    Files.Read(r, b); IF b # ORD("e") THEN ok := FALSE END;
    Files.Read(r, b); IF b # ORD("l") THEN ok := FALSE END;
    Files.Read(r, b); IF b # ORD("l") THEN ok := FALSE END;
    Files.Read(r, b); IF b # ORD("o") THEN ok := FALSE END;
    PrintResult(ok);

    (* Test 8: Delete file from subdirectory *)
    Out.Int(8, 1); Out.String(sp);
    fname := "SUB/hello.txt";
    Files.Delete(fname, res);
    PrintResult(res = 0);

    (* Test 9: Verify file is gone *)
    Out.Int(9, 1); Out.String(sp);
    fname := "SUB/hello.txt";
    f := Files.Old(fname);
    PrintResult(f = NIL);

    (* Test 10: RemoveDir "SUB" *)
    Out.Int(10, 1); Out.String(sp);
    fname := "SUB";
    Files.RemoveDir(fname, res);
    PrintResult(res = 0);

    (* Test 11: CreateDir nested "A" then "A/B" *)
    Out.Int(11, 1); Out.String(sp);
    fname := "A";
    Files.CreateDir(fname, res);
    ok := (res = 0);
    fname := "A/B";
    Files.CreateDir(fname, res);
    IF res # 0 THEN ok := FALSE END;
    PrintResult(ok);

    (* Test 12: Create file in nested subdir A/B *)
    Out.Int(12, 1); Out.String(sp);
    fname := "A/B/test.txt";
    f := Files.New(fname);
    Files.Set(r, f, 0);
    i := 0;
    WHILE i < 100 DO
      Files.Write(r, i MOD 256);
      INC(i)
    END;
    Files.Register(f);
    Files.Close(f);
    Out.String(pass); Out.Ln;

    (* Test 13: Reopen and verify nested file *)
    Out.Int(13, 1); Out.String(sp);
    fname := "A/B/test.txt";
    f := Files.Old(fname);
    ok := (f # NIL);
    IF ok THEN
      len := Files.Length(f);
      IF len # 100 THEN ok := FALSE END;
      Files.Set(r, f, 0);
      i := 0;
      WHILE (i < 100) & ok DO
        Files.Read(r, b);
        IF b # (i MOD 256) THEN ok := FALSE END;
        INC(i)
      END
    END;
    PrintResult(ok);

    (* Test 14: RemoveDir on non-empty dir fails *)
    Out.Int(14, 1); Out.String(sp);
    fname := "A/B";
    Files.RemoveDir(fname, res);
    PrintResult(res # 0);

    (* Test 15: Delete file, then remove nested dirs *)
    Out.Int(15, 1); Out.String(sp);
    fname := "A/B/test.txt";
    Files.Delete(fname, res);
    ok := (res = 0);
    fname := "A/B";
    Files.RemoveDir(fname, res);
    IF res # 0 THEN ok := FALSE END;
    fname := "A";
    Files.RemoveDir(fname, res);
    IF res # 0 THEN ok := FALSE END;
    PrintResult(ok);

    (* Test 16: Root file still works after subdir ops *)
    Out.Int(16, 1); Out.String(sp);
    fname := "ROOT.TXT";
    f := Files.New(fname);
    Files.Set(r, f, 0);
    Files.Write(r, ORD("R"));
    Files.Register(f);
    Files.Close(f);
    fname := "ROOT.TXT";
    f := Files.Old(fname);
    ok := (f # NIL);
    IF ok THEN
      Files.Set(r, f, 0);
      Files.Read(r, b);
      IF b # ORD("R") THEN ok := FALSE END
    END;
    PrintResult(ok);

    (* Test 17: Duplicate CreateDir fails *)
    Out.Int(17, 1); Out.String(sp);
    fname := "DUP";
    Files.CreateDir(fname, res);
    ok := (res = 0);
    fname := "DUP";
    Files.CreateDir(fname, res);
    IF res = 0 THEN ok := FALSE END;
    (* Clean up *)
    fname := "DUP";
    Files.RemoveDir(fname, res);
    PrintResult(ok);

    Out.String(done); Out.Ln
  END Run;

BEGIN
  pass := " PASS";
  fail := " FAIL";
  sp := " ";
  done := "Done";
  Run
END TestSubDir.
