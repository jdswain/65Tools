MODULE TestFloppy;
  IMPORT Driver, FloppyDriver, Out;

  VAR
    drv: Driver.BlockDriver;
    buf: ARRAY 512 OF BYTE;
    res, i, d: INTEGER;

BEGIN
  FloppyDriver.Init(0, drv);

  (* Test 1: Read block 0 — should have 0x55 at byte 0, zeros after *)
  res := drv.read(drv, 0, buf);
  Out.Int(res, 1); Out.Ln();

  d := buf[0]; Out.Int(d, 1); Out.Ln();  (* expect 85 = 0x55 *)
  d := buf[1]; Out.Int(d, 1); Out.Ln();  (* expect 0 *)

  (* Test 2: Write a pattern to block 1 *)
  i := 0;
  WHILE i < 512 DO
    buf[i] := i MOD 256;
    INC(i)
  END;
  res := drv.write(drv, 1, buf);
  Out.Int(res, 1); Out.Ln();

  (* Test 3: Read it back from block 1 *)
  i := 0;
  WHILE i < 512 DO buf[i] := 0FFH; INC(i) END;

  res := drv.read(drv, 1, buf);
  Out.Int(res, 1); Out.Ln();

  (* Print first 8 bytes: should be 0 1 2 3 4 5 6 7 *)
  i := 0;
  WHILE i < 8 DO
    d := buf[i]; Out.Int(d, 4);
    INC(i)
  END;
  Out.Ln();

  (* Test 4: Read block 9 — first block on side 1 *)
  res := drv.read(drv, 9, buf);
  Out.Int(res, 1); Out.Ln();

  (* Test 5: Read block 18 — first block on track 1 *)
  res := drv.read(drv, 18, buf);
  Out.Int(res, 1); Out.Ln()
END TestFloppy.
