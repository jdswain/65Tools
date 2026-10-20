MODULE MakeImage;
(* OS16 kernel image builder — the first real console tool.

   Reuses the runtime module loader (ModuleManager): link the kernel module set into
   memory WITHOUT running it (ModuleManager.Link), then snapshot the linked code and
   data plus a module manifest into an image file (ModuleManager.WriteImage) that a
   boot ROM can load verbatim and jump to — no relocation at boot.

   Input : a manifest file (one module name per line; the LAST is the kernel
           entry). The listed modules and their imports are found on the module
           search path (Library/Modules/).
   Output: a single linked image (default System/Kernel).

   Installed at System/bin/MakeImage.816. *)

  IMPORT BlockDriver, Floppy, Files, FatFS, ModuleManager, Out;   (* FatFS: installs itself as the file system Files.Init mounts *)

  CONST
    ManifestPath = "System/Build.mf";
    OutputPath   = "System/Kernel";
    MaxMods      = 16;
    LinkVarBase  = 8000H;   (* link the kernel's data here — above the build-time
                               heap ($323D..$BFFF, where FatFS keeps its FileDescs) *)

  PROCEDURE White(ch: CHAR): BOOLEAN;
  BEGIN RETURN (ch = " ") OR (ch = 0DX) OR (ch = 0AX) OR (ch = 09X) OR (ch = 0X)
  END White;

  (* Read one whitespace-delimited token; FALSE at end of file. *)
  PROCEDURE ReadName(VAR r: Files.Rider; VAR name: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER; b: BYTE; ch: CHAR; ok: BOOLEAN;
  BEGIN
    Files.Read(r, b); ch := CHR(b);
    WHILE ~r.eof & White(ch) DO Files.Read(r, b); ch := CHR(b) END;
    IF r.eof THEN name[0] := 0X; ok := FALSE
    ELSE
      i := 0;
      WHILE ~r.eof & ~White(ch) & (i < LEN(name) - 1) DO
        name[i] := ch; INC(i); Files.Read(r, b); ch := CHR(b)
      END;
      name[i] := 0X;
      ok := i > 0
    END;
    RETURN ok
  END ReadName;

  PROCEDURE Run;
    VAR f: Files.File; r: Files.Rider;
        name: ARRAY 32 OF CHAR;
        firstMod, varBase, res, nLinked: INTEGER;
        codeBase: LONGINT;                     (* 24-bit code base *)
        ok: BOOLEAN;
        drv: BlockDriver.BlockDriver;
  BEGIN
    Out.String("MakeImage: building kernel image"); Out.Ln;
    drv := Floppy.New(0);   (* mount the existing volume (NOT Format) *)
    Files.Init(drv);
    f := Files.Old(ManifestPath);
    IF f = NIL THEN
      Out.String("  manifest not found: "); Out.String(ManifestPath); Out.Ln
    ELSE
      Files.Set(r, f, 0);

      (* everything already resident (this tool + its own imports) stays put;
         the kernel is linked fresh above it and stays self-contained *)
      firstMod := ModuleManager.Count();
      codeBase := ModuleManager.CodeTop();
      varBase  := LinkVarBase;
      ModuleManager.SetLinkBase(firstMod);
      ModuleManager.SetLinkAddr(codeBase, varBase);

      nLinked := 0; ok := TRUE;
      WHILE ReadName(r, name) DO
        Out.String("  link "); Out.String(name); Out.Ln;
        ModuleManager.Link(name, res);
        IF res # 0 THEN
          Out.String("    FAILED res="); Out.Int(res, 1); Out.Ln; ok := FALSE
        END;
        INC(nLinked)
      END;
      Files.Close(f);

      IF ok & (nLinked > 0) THEN
        Out.String("Writing "); Out.String(OutputPath); Out.Ln;
        ModuleManager.WriteImage(OutputPath, firstMod, codeBase, varBase, res);
        IF res = 0 THEN
          Out.String("OK: "); Out.Int(ModuleManager.Count() - firstMod, 1);
          Out.String(" modules, code="); Out.Int(ModuleManager.CodeTop() - codeBase, 1);
          Out.String("B data="); Out.Int(ModuleManager.VarTop() - varBase, 1);
          Out.String("B"); Out.Ln
        ELSE
          Out.String("write failed res="); Out.Int(res, 1); Out.Ln
        END
      ELSE
        Out.String("nothing linked"); Out.Ln
      END;

      ModuleManager.SetLinkBase(0)
    END
  END Run;

BEGIN
  Run
END MakeImage.
