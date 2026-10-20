MODULE FatFSTest; (* Format a floppy, write a file, read it back, delete it:
   Floppy and FatFS through BlockDriver and Files, mounted as a FatFS made
   for the device, then again by Files.Init (the FatFS installed).
   Run on em16 with a blank 720K image as -disk0 (see Makefile: test-fs). *)
  IMPORT BlockDriver, Files, Floppy, FatFS, Out;
  VAR d: BlockDriver.BlockDriver; fs: Files.FileSystem;
    f, g: Files.File; r: Files.Rider;
    i, x, res, ok: INTEGER; b: BYTE; s: ARRAY 32 OF CHAR; bs: ARRAY 32 OF BYTE;
BEGIN
  d := Floppy.New(0); Out.String("driver "); Out.String(d.name); Out.Ln;
  fs := FatFS.ForDevice(d);
  IF fs.Format() & Files.Mount(fs) THEN Out.String("formatted, mounted") ELSE Out.String("mount failed") END; Out.Ln;
  f := Files.New("HELLO.TXT"); Files.Set(r, f, 0);
  Files.WriteString(r, "hello, os16"); Files.WriteInt(r, 1234);
  i := 0; WHILE i < 1500 DO Files.Write(r, i MOD 251); INC(i) END;
  Files.Register(f); Files.Close(f);
  IF fs.Sync() THEN Out.String("synced") END; Out.Ln;
  Files.Init(d);
  g := Files.Old("HELLO.TXT");
  IF g = NIL THEN Out.String("old failed"); Out.Ln ELSE
    Out.String("length "); Out.Int(Files.Length(g), 0); Out.Ln;
    Files.Set(r, g, 0); Files.ReadString(r, s); Files.ReadInt(r, x);
    Out.String(s); Out.Char(" "); Out.Int(x, 0); Out.Ln;
    ok := 0; i := 0; WHILE i < 1500 DO Files.Read(r, b); IF b = i MOD 251 THEN INC(ok) END; INC(i) END;
    Out.String("bytes ok "); Out.Int(ok, 0); Out.Ln;
    Files.Set(r, g, 1100); Files.Read(r, b); Out.String("at 1100 "); Out.Int(b, 0);
    Files.Set(r, g, 20); Files.Read(r, b); Out.String(", back at 20 "); Out.Int(b, 0);
    Out.String(", pos "); Out.Int(Files.Pos(r), 0);
    IF Files.Base(r) = g THEN Out.String(", base") END; Out.Ln;
    Files.Set(r, g, 1513); Files.Read(r, b); Files.Read(r, b);
    IF r.eof THEN Out.String("eof") END; Out.Ln;
    Files.Close(g)
  END;
  Files.CreateDir("SUB", res); Out.String("mkdir "); Out.Int(res, 0);
  f := Files.New("SUB/A Long File Name.TXT"); Files.Set(r, f, 0);
  i := 0; WHILE i < 26 DO bs[i] := ORD("a") + i; INC(i) END;
  Files.WriteBytes(r, bs, 26); Files.Register(f); Files.Close(f);
  Files.Rename("SUB/A Long File Name.TXT", "SUB/B.TXT", res); Out.String(", rename "); Out.Int(res, 0);
  g := Files.Old("SUB/B.TXT"); Files.Set(r, g, 0); Files.ReadBytes(r, bs, 30);
  i := 0; WHILE i < 26 DO s[i] := CHR(bs[i]); INC(i) END; s[26] := 0X;
  Out.String(", read "); Out.String(s); Out.String(" short "); Out.Int(r.res, 0); Out.Ln;
  Files.RemoveDir("SUB", res); Out.String("rmdir full "); Out.Int(res, 0);
  Files.Delete("SUB/B.TXT", res); Files.RemoveDir("SUB", res); Out.String(", emptied "); Out.Int(res, 0); Out.Ln;
  Files.Delete("HELLO.TXT", res); Out.String("delete "); Out.Int(res, 0); Out.Ln;
  IF Files.Old("HELLO.TXT") = NIL THEN Out.String("gone") ELSE Out.String("still there") END; Out.Ln
END FatFSTest.
