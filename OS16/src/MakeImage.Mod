MODULE MakeImage;
(* OS16 kernel image builder — the first real console tool.

   Reuses the runtime module loader (ModuleLoader): link the kernel module set into
   memory WITHOUT running it (ModuleLoader.Link), then snapshot the linked code and
   data plus a module manifest into an image file (ModuleLoader.WriteImage) that a
   boot ROM can load verbatim and jump to — no relocation at boot.

   Input : a manifest file (one module name per line; the LAST is the kernel
           entry). The listed modules and their imports are found on the module
           search path (Library/Modules/).
   Output: a single linked image (default System/Kernel).

   Installed at System/bin/MakeImage.816. *)

  IMPORT BlockDriver, Floppy, FatFS, ModuleLoader, Out;

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
  PROCEDURE ReadName(VAR r: FatFS.Rider; VAR name: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER; b: BYTE; ch: CHAR; ok: BOOLEAN;
  BEGIN
    FatFS.Read(r, b); ch := CHR(b);
    WHILE ~r.eof & White(ch) DO FatFS.Read(r, b); ch := CHR(b) END;
    IF r.eof THEN name[0] := 0X; ok := FALSE
    ELSE
      i := 0;
      WHILE ~r.eof & ~White(ch) & (i < LEN(name) - 1) DO
        name[i] := ch; INC(i); FatFS.Read(r, b); ch := CHR(b)
      END;
      name[i] := 0X;
      ok := i > 0
    END;
    RETURN ok
  END ReadName;

  PROCEDURE Run;
    VAR f: FatFS.File; r: FatFS.Rider;
        name: ARRAY 32 OF CHAR;
        firstMod, varBase, res, nLinked: INTEGER;
        codeBase: LONGINT;                     (* 24-bit code base *)
        ok: BOOLEAN;
        drv: BlockDriver.BlockDriver;
  BEGIN
    Out.String("MakeImage: building kernel image"); Out.Ln;
    drv := Floppy.New(0);   (* mount the existing volume (NOT Format) *)
    FatFS.Init(drv);
    f := FatFS.Old(ManifestPath);
    IF f = NIL THEN
      Out.String("  manifest not found: "); Out.String(ManifestPath); Out.Ln
    ELSE
      FatFS.Set(r, f, 0);

      (* everything already resident (this tool + its own imports) stays put;
         the kernel is linked fresh above it and stays self-contained *)
      firstMod := ModuleLoader.Count();
      codeBase := ModuleLoader.CodeTop();
      varBase  := LinkVarBase;
      ModuleLoader.SetLinkBase(firstMod);
      ModuleLoader.SetLinkAddr(codeBase, varBase);

      nLinked := 0; ok := TRUE;
      WHILE ReadName(r, name) DO
        Out.String("  link "); Out.String(name); Out.Ln;
        ModuleLoader.Link(name, res);
        IF res # 0 THEN
          Out.String("    FAILED res="); Out.Int(res, 1); Out.Ln; ok := FALSE
        END;
        INC(nLinked)
      END;
      FatFS.Close(f);

      IF ok & (nLinked > 0) THEN
        Out.String("Writing "); Out.String(OutputPath); Out.Ln;
        ModuleLoader.WriteImage(OutputPath, firstMod, codeBase, varBase, res);
        IF res = 0 THEN
          Out.String("OK: "); Out.Int(ModuleLoader.Count() - firstMod, 1);
          Out.String(" modules, code="); Out.Int(ModuleLoader.CodeTop() - codeBase, 1);
          Out.String("B data="); Out.Int(ModuleLoader.VarTop() - varBase, 1);
          Out.String("B"); Out.Ln
        ELSE
          Out.String("write failed res="); Out.Int(res, 1); Out.Ln
        END
      ELSE
        Out.String("nothing linked"); Out.Ln
      END;

      ModuleLoader.SetLinkBase(0)
    END
  END Run;

BEGIN
  Run
END MakeImage.
