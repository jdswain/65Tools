MODULE TestMinimal;
  IMPORT Driver, FloppyDriver, Out;

  VAR
    drv: Driver.BlockDriver;
    buf: ARRAY 512 OF BYTE;
    i, res: INTEGER;
    a, b: ARRAY 4 OF CHAR;

  PROCEDURE DoWrite(d: Driver.BlockDriver);
    VAR r: INTEGER;
  BEGIN
    Out.String(a); Out.Ln;
    r := d.write(d, 0, buf);
    Out.Int(r, 1); Out.Ln;
    Out.String(b); Out.Ln
  END DoWrite;

BEGIN
  a := "X"; b := "Y";
  FloppyDriver.Init(0, drv);
  i := 0;
  WHILE i < 512 DO buf[i] := 0; INC(i) END;

  DoWrite(drv);
  Out.String(a); Out.Ln
END TestMinimal.
