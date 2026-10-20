MODULE DiskTest2; (* FatFS beyond 16-bit sector numbers: partition 2 of
   DiskTest's disk, FAT16, mounted again after tools/mkgpt.py --fill has
   given its clusters up to volume sector 40000 to FILLER.BIN. DATA.BIN,
   which DiskTest wrote, read back; FAR.BIN, which must go beyond the
   filler, written, read back after Files.Init mounts it again. BIG.BIN,
   70000 bytes, past the 16-bit positions: written, read back and read
   at 66000 (Makefile: test-disk). *)
  IMPORT SCSIManager, SCSIDisk, DiskPartition, Files, FatFS, Out;   (* FatFS: installed for Files.Init *)

  VAR
    disk: SCSIDisk.SCSIDisk;
    parts: ARRAY 4 OF DiskPartition.DiskPartition;
    f: Files.File; r: Files.Rider;
    n, i, ok: INTEGER; b: BYTE; l, lok: LONGINT;

  PROCEDURE Num(l: LONGINT);   (* not negative *)
    VAR i: INTEGER;
  BEGIN
    IF l >= 10000 THEN
      Num(l DIV 10000); i := l MOD 10000;
      IF i < 1000 THEN Out.Char("0") END; IF i < 100 THEN Out.Char("0") END; IF i < 10 THEN Out.Char("0") END
    ELSE i := l
    END;
    Out.Int(i, 0)
  END Num;

  PROCEDURE Check(name: ARRAY OF CHAR; m: INTEGER);
  BEGIN
    f := Files.Old(name);
    Out.String(name);
    IF f = NIL THEN Out.String(" not found")
    ELSE
      Out.String(" length "); Out.Int(Files.Length(f), 0);
      Files.Set(r, f, 0); ok := 0; i := 0;
      WHILE i < Files.Length(f) DO Files.Read(r, b); IF b = i MOD m THEN INC(ok) END; INC(i) END;
      Out.String(", bytes ok "); Out.Int(ok, 0)
    END;
    Out.Ln
  END Check;

BEGIN
  disk := SCSIDisk.New(SCSIManager.New(), 0);
  IF disk # NIL THEN n := DiskPartition.Scan(disk, parts) ELSE n := 0 END;
  IF n > 1 THEN
    Files.Init(parts[1]);
    IF Files.Old("FILLER.BIN") # NIL THEN Out.String("partition 2 mounted, FILLER.BIN there") ELSE Out.String("no FILLER.BIN") END; Out.Ln;
    Check("DATA.BIN", 253);
    f := Files.New("FAR.BIN"); Files.Set(r, f, 0);
    i := 0; WHILE i < 20000 DO Files.Write(r, i MOD 253); INC(i) END;
    Files.Register(f); Files.Close(f);
    f := Files.New("BIG.BIN"); Files.Set(r, f, 0);
    l := 0; WHILE l < 70000 DO Files.Write(r, l MOD 251); l := l + 1 END;
    Out.String("BIG.BIN written to "); Num(Files.Pos(r)); Out.Ln;
    Files.Register(f); Files.Close(f);
    Files.Init(parts[1]);
    Check("FAR.BIN", 253);
    f := Files.Old("BIG.BIN");
    IF f = NIL THEN Out.String("BIG.BIN not found")
    ELSE
      Out.String("BIG.BIN length "); Num(Files.Length(f));
      Files.Set(r, f, 0); lok := 0; l := 0;
      WHILE l < Files.Length(f) DO Files.Read(r, b); IF b = l MOD 251 THEN lok := lok + 1 END; l := l + 1 END;
      Out.String(", bytes ok "); Num(lok);
      Files.Set(r, f, 66000); Files.Read(r, b);
      Out.String(", at "); Num(Files.Pos(r) - 1); Out.String(" "); Out.Int(b, 0);
      Files.Read(r, b); IF r.eof THEN Out.String(" eof?") END;
      Files.Set(r, f, 70000); Files.Read(r, b); IF r.eof THEN Out.String(", eof at the end") END
    END;
    Out.Ln
  ELSE Out.String("no partition 2"); Out.Ln
  END;
  Out.String("done"); Out.Ln
END DiskTest2.
