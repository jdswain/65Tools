MODULE DiskTest; (* The SCSI disk path: SCSIManager on the 53C80, the
   SCSIDisk at ID 0, its GPT partitions as DiskPartitions, and FatFS
   formatted on partition 1, through Files: files written, read back
   after Files.Init mounts it again, one deleted. Then partition 2, big
   enough to need clusters of 16 sectors: formatted, a file across
   clusters written and read back.
   Run on em16 with -scsi of tools/mkgpt.py's image (Makefile: test-disk). *)
  IMPORT SCSIManager, SCSIDisk, DiskPartition, Files, FatFS, Out;

  VAR
    bus: SCSIManager.SCSIManager; disk: SCSIDisk.SCSIDisk;
    parts: ARRAY 4 OF DiskPartition.DiskPartition;
    fs: Files.FileSystem; f: Files.File; r: Files.Rider;
    n, i, t, x, ok, res: INTEGER; b: BYTE;
    buf: ARRAY 512 OF BYTE; s: ARRAY 32 OF CHAR;

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

BEGIN
  bus := SCSIManager.New();
  Out.String("bus "); Out.String(bus.name); Out.String(", types");
  FOR t := 0 TO SCSIManager.MaxTargets - 1 DO Out.Char(" "); Out.Int(bus.types[t], 0) END; Out.Ln;
  disk := SCSIDisk.New(bus, 0);
  IF SCSIDisk.New(bus, 1) = NIL THEN Out.String("none at ID 1") ELSE Out.String("one at ID 1?") END; Out.Ln;
  IF disk = NIL THEN Out.String("no disk at ID 0"); Out.Ln
  ELSE
    Out.String("disk "); Out.String(disk.name); Out.String(", "); Num(disk.Blocks()); Out.String(" blocks"); Out.Ln;
    n := DiskPartition.Scan(disk, parts);
    Out.String("partitions "); Out.Int(n, 0); Out.Ln;
    FOR i := 0 TO n - 1 DO
      Out.String(parts[i].name); Out.String(" from "); Num(parts[i].first);
      Out.String(", "); Num(parts[i].Blocks()); Out.String(" blocks, "); Out.String(parts[i].label); Out.Ln
    END;
    IF n > 0 THEN
      Out.String("past the end "); Out.Int(parts[0].ReadBlock(parts[0].Blocks(), buf), 0); Out.Ln;
      fs := FatFS.ForDevice(parts[0]);
      IF fs.Format() & Files.Mount(fs) THEN Out.String("formatted, mounted") ELSE Out.String("mount failed") END; Out.Ln;
      f := Files.New("KEEP.TXT"); Files.Set(r, f, 0);
      Files.WriteString(r, "on a partition"); Files.WriteInt(r, 4321);
      Files.Register(f); Files.Close(f);
      f := Files.New("HELLO.TXT"); Files.Set(r, f, 0);
      i := 0; WHILE i < 3000 DO Files.Write(r, i MOD 251); INC(i) END;
      Files.Register(f); Files.Close(f);
      IF fs.Sync() THEN Out.String("synced") END; Out.Ln;
      Files.Init(parts[0]);
      f := Files.Old("KEEP.TXT");
      IF f = NIL THEN Out.String("KEEP.TXT not found")
      ELSE Files.Set(r, f, 0); Files.ReadString(r, s); Files.ReadInt(r, x); Out.String(s); Out.Char(" "); Out.Int(x, 0)
      END; Out.Ln;
      f := Files.Old("HELLO.TXT");
      IF f = NIL THEN Out.String("HELLO.TXT not found")
      ELSE
        Out.String("length "); Out.Int(Files.Length(f), 0);
        Files.Set(r, f, 0); ok := 0; i := 0;
        WHILE i < 3000 DO Files.Read(r, b); IF b = i MOD 251 THEN INC(ok) END; INC(i) END;
        Out.String(", bytes ok "); Out.Int(ok, 0)
      END; Out.Ln;
      Files.Delete("HELLO.TXT", res); Out.String("delete "); Out.Int(res, 0); Out.Ln;
      IF Files.Old("HELLO.TXT") = NIL THEN Out.String("gone") ELSE Out.String("still there") END; Out.Ln
    END;
    IF n > 1 THEN
      fs := FatFS.ForDevice(parts[1]);
      IF fs.Format() & Files.Mount(fs) THEN Out.String("partition 2 formatted, mounted") ELSE Out.String("partition 2 mount failed") END; Out.Ln;
      f := Files.New("DATA.BIN"); Files.Set(r, f, 0);
      i := 0; WHILE i < 20000 DO Files.Write(r, i MOD 253); INC(i) END;
      Files.Register(f); Files.Close(f);
      Files.Init(parts[1]);
      f := Files.Old("DATA.BIN");
      IF f = NIL THEN Out.String("DATA.BIN not found")
      ELSE
        Out.String("length "); Out.Int(Files.Length(f), 0);
        Files.Set(r, f, 0); ok := 0; i := 0;
        WHILE i < 20000 DO Files.Read(r, b); IF b = i MOD 253 THEN INC(ok) END; INC(i) END;
        Out.String(", bytes ok "); Out.Int(ok, 0)
      END; Out.Ln
    END
  END;
  Out.String("done"); Out.Ln
END DiskTest.
