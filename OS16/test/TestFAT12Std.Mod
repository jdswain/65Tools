MODULE TestFAT12Std;
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
      fname: ARRAY 16 OF CHAR;
  BEGIN
    (* Initialize floppy driver *)
    FloppyDriver.Init(0, drv);

    (* Test 1: Init on standard-formatted FAT12 disk (no Format) *)
    Out.Int(1, 1); Out.String(sp);
    Files.Init(drv);
    Out.String(pass); Out.Ln;

    (* Test 2: New file *)
    Out.Int(2, 1); Out.String(sp);
    fname := "TEST.TXT";
    f := Files.New(fname);
    PrintResult(f # NIL);

    (* Test 3: Write "Hello" *)
    Out.Int(3, 1); Out.String(sp);
    Files.Set(r, f, 0);
    Files.Write(r, ORD("H"));
    Files.Write(r, ORD("e"));
    Files.Write(r, ORD("l"));
    Files.Write(r, ORD("l"));
    Files.Write(r, ORD("o"));
    len := Files.Length(f);
    PrintResult(len = 5);

    (* Test 4: Register and close *)
    Out.Int(4, 1); Out.String(sp);
    Files.Register(f);
    Files.Close(f);
    Out.String(pass); Out.Ln;

    (* Test 5: Reopen with Old *)
    Out.Int(5, 1); Out.String(sp);
    fname := "TEST.TXT";
    f := Files.Old(fname);
    PrintResult(f # NIL);

    (* Test 6: Verify length *)
    Out.Int(6, 1); Out.String(sp);
    len := Files.Length(f);
    PrintResult(len = 5);

    (* Test 7: Read back content *)
    Out.Int(7, 1); Out.String(sp);
    Files.Set(r, f, 0);
    ok := TRUE;
    Files.Read(r, b); IF b # ORD("H") THEN ok := FALSE END;
    Files.Read(r, b); IF b # ORD("e") THEN ok := FALSE END;
    Files.Read(r, b); IF b # ORD("l") THEN ok := FALSE END;
    Files.Read(r, b); IF b # ORD("l") THEN ok := FALSE END;
    Files.Read(r, b); IF b # ORD("o") THEN ok := FALSE END;
    PrintResult(ok);

    (* Test 8: EOF after reading all bytes *)
    Out.Int(8, 1); Out.String(sp);
    Files.Read(r, b);
    PrintResult(r.eof);

    (* Test 9: Delete file *)
    Out.Int(9, 1); Out.String(sp);
    fname := "TEST.TXT";
    Files.Delete(fname, res);
    PrintResult(res = 0);

    (* Test 10: Old returns NIL after delete *)
    Out.Int(10, 1); Out.String(sp);
    fname := "TEST.TXT";
    f := Files.Old(fname);
    PrintResult(f = NIL);

    (* Test 11: Cross-cluster write *)
    Out.Int(11, 1); Out.String(sp);
    fname := "BIG.DAT";
    f := Files.New(fname);
    Files.Set(r, f, 0);
    i := 0;
    WHILE i < 2000 DO
      Files.Write(r, i MOD 256);
      INC(i)
    END;
    len := Files.Length(f);
    PrintResult(len = 2000);

    (* Test 12: Register big file *)
    Out.Int(12, 1); Out.String(sp);
    Files.Register(f);
    Files.Close(f);
    Out.String(pass); Out.Ln;

    (* Test 13: Reopen big file *)
    Out.Int(13, 1); Out.String(sp);
    fname := "BIG.DAT";
    f := Files.Old(fname);
    PrintResult(f # NIL);

    (* Test 14: Verify big file length *)
    Out.Int(14, 1); Out.String(sp);
    len := Files.Length(f);
    PrintResult(len = 2000);

    (* Test 15: Read back and verify big file *)
    Out.Int(15, 1); Out.String(sp);
    Files.Set(r, f, 0);
    ok := TRUE;
    i := 0;
    WHILE (i < 2000) & ok DO
      Files.Read(r, b);
      n := i MOD 256;
      IF b # n THEN ok := FALSE END;
      INC(i)
    END;
    PrintResult(ok);

    (* Test 16: WriteInt / ReadInt *)
    Out.Int(16, 1); Out.String(sp);
    fname := "INT.DAT";
    f := Files.New(fname);
    Files.Set(r, f, 0);
    Files.WriteInt(r, 12345);
    Files.WriteInt(r, -1);
    Files.Register(f);
    Files.Close(f);
    fname := "INT.DAT";
    f := Files.Old(fname);
    Files.Set(r, f, 0);
    Files.ReadInt(r, n);
    ok := (n = 12345);
    Files.ReadInt(r, n);
    IF n # -1 THEN ok := FALSE END;
    PrintResult(ok);

    Out.String(done); Out.Ln
  END Run;

BEGIN
  pass := " PASS";
  fail := " FAIL";
  sp := " ";
  done := "Done";
  Run
END TestFAT12Std.
