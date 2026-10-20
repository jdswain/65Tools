MODULE DiskTest2; (* FatFS beyond 16-bit sector numbers: partition 2 of
   DiskTest's disk, FAT16, mounted again after tools/mkgpt.py --fill has
   given its clusters up to volume sector 40000 to FILLER.BIN. DATA.BIN,
   which DiskTest wrote, read back; FAR.BIN, which must go beyond the
   filler, written, read back after Files.Init mounts it again
   (Makefile: test-disk). *)
  IMPORT SCSIManager, SCSIDisk, DiskPartition, Files, FatFS, Out;   (* FatFS: installed for Files.Init *)

  VAR
    disk: SCSIDisk.SCSIDisk;
    parts: ARRAY 4 OF DiskPartition.DiskPartition;
    f: Files.File; r: Files.Rider;
    n, i, ok: INTEGER; b: BYTE;

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
    Files.Init(parts[1]);
    Check("FAR.BIN", 253)
  ELSE Out.String("no partition 2"); Out.Ln
  END;
  Out.String("done"); Out.Ln
END DiskTest2.
