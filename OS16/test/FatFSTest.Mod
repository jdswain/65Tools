MODULE FatFSTest; (* Format a floppy, write a file, read it back, delete it:
   Floppy and FatFS through the BlockDriver and FileSystem types.
   Run on em16 with a blank 720K image as -disk0 (see Makefile: test-fs). *)
  IMPORT BlockDriver, FileSystem, Floppy, FatFS, Out;
  VAR d: BlockDriver.BlockDriver; fs: FileSystem.FileSystem;
    f, g: FatFS.File; r: FatFS.Rider;
    i, x, res, ok: INTEGER; b: BYTE; s: ARRAY 32 OF CHAR;
BEGIN
  d := Floppy.New(0); Out.String("driver "); Out.String(d.name); Out.Ln;
  fs := FatFS.ForDevice(d);
  IF fs.Format() & fs.Mount() THEN Out.String("formatted, mounted") ELSE Out.String("mount failed") END; Out.Ln;
  f := FatFS.New("HELLO.TXT"); FatFS.Set(r, f, 0);
  FatFS.WriteString(r, "hello, os16"); FatFS.WriteInt(r, 1234);
  i := 0; WHILE i < 1500 DO FatFS.Write(r, i MOD 251); INC(i) END;
  FatFS.Register(f); FatFS.Close(f);
  IF fs.Sync() THEN Out.String("synced") END; Out.Ln;
  g := FatFS.Old("HELLO.TXT");
  IF g = NIL THEN Out.String("old failed"); Out.Ln ELSE
    Out.String("length "); Out.Int(FatFS.Length(g), 0); Out.Ln;
    FatFS.Set(r, g, 0); FatFS.ReadString(r, s); FatFS.ReadInt(r, x);
    Out.String(s); Out.Char(" "); Out.Int(x, 0); Out.Ln;
    ok := 0; i := 0; WHILE i < 1500 DO FatFS.Read(r, b); IF b = i MOD 251 THEN INC(ok) END; INC(i) END;
    Out.String("bytes ok "); Out.Int(ok, 0); Out.Ln
  END;
  FatFS.Delete("HELLO.TXT", res); Out.String("delete "); Out.Int(res, 0); Out.Ln;
  IF FatFS.Old("HELLO.TXT") = NIL THEN Out.String("gone") ELSE Out.String("still there") END; Out.Ln
END FatFSTest.
