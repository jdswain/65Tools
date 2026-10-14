MODULE AS; (* The 65xx assembler: command line and control.

   An assembler for the MOS 6502, the WDC 65C02 and 65C816, and the
   Rockwell R65C02, R6501Q and C19, ported to Oberon from the C program
   in as-c. Its parts follow the Oberon compiler:

     ASS  scanner
     ASP  parser; translates the source into operations of ASI
     ASI  interpreter; runs the operations in several passes
     ASG  code generator; sections, addressing modes, instruction formats
     ASC  processor tables
     ASB  base; values and symbol table, symbol file import
     ASL  listing
     ASO  output formats
     ASH  host interface

   The body of this module is the program. *)

  IMPORT Env, ASH, ASC, ASS, ASB, ASG, ASL, ASI, ASP, ASO;

  CONST maxFiles = 32; maxDefs = 32;

  VAR
    (* input files and definitions, as the numbers of their arguments;
       a definition written "-Dsym" shares its argument with the option *)
    files: ARRAY maxFiles OF INTEGER; nofFiles: INTEGER;
    defs: ARRAY maxDefs OF INTEGER; nofDefs: INTEGER;
    defShared: ARRAY maxDefs OF BOOLEAN;
    outName: ASH.Path;
    verbose, legacy, help, bad: BOOLEAN;

  PROCEDURE Help;
  BEGIN
    ASH.Str("as version 0.1.0 - 65xx assembler"); ASH.Ln;
    ASH.Str("Usage: as [options] -o outfile infile ..."); ASH.Ln;
    ASH.Str("  -o outfile   output file; its extension selects the format:"); ASH.Ln;
    ASH.Str("                 none ELF executable, .o ELF object, .bin binary,"); ASH.Ln;
    ASH.Str("                 .hex Intel hex, .s19 .s28 .s37 S-records, .tim paper tape,"); ASH.Ln;
    ASH.Str("                 .mem Verilog memory file ($readmemh),"); ASH.Ln;
    ASH.Str("                 .816 Oberon module with its .smb symbol file"); ASH.Ln;
    ASH.Str("  -I dir       add dir to the include and symbol file search path"); ASH.Ln;
    ASH.Str("  -D sym[=val] define symbol sym, as 1 if no value is given"); ASH.Ln;
    ASH.Str("  -legacy      write .816 and .smb files for the C Oberon compiler"); ASH.Ln;
    ASH.Str("  -v           report the passes"); ASH.Ln;
    ASH.Str("  -h           show this help"); ASH.Ln
  END Help;

  (* The value of option -x: the rest of the argument, or the next one. *)
  PROCEDURE Value(VAR arg: ARRAY OF CHAR; VAR i: INTEGER; VAR val: ARRAY OF CHAR);
    VAR j: INTEGER;
  BEGIN
    IF arg[2] # 0X THEN j := 2;
      WHILE arg[j] # 0X DO val[j-2] := arg[j]; INC(j) END;
      val[j-2] := 0X
    ELSIF i + 1 < Env.ArgCount() THEN INC(i); Env.Arg(i, val)
    ELSE val[0] := 0X; bad := TRUE;
      ASH.Str("Missing value for option "); ASH.Str(arg); ASH.Ln
    END
  END Value;

  PROCEDURE Arguments;
    VAR i: INTEGER; arg, val: ASH.Path;
  BEGIN i := 1;
    WHILE i < Env.ArgCount() DO
      Env.Arg(i, arg);
      IF (arg[0] # "-") OR (arg[1] = 0X) THEN
        IF nofFiles < maxFiles THEN files[nofFiles] := i; INC(nofFiles)
        ELSE ASH.Str("Too many input files"); ASH.Ln; bad := TRUE
        END
      ELSIF (arg = "-h") OR (arg = "--help") OR (arg = "-?") THEN help := TRUE
      ELSIF arg = "-v" THEN verbose := TRUE
      ELSIF arg = "-legacy" THEN legacy := TRUE
      ELSIF arg[1] = "o" THEN Value(arg, i, outName)
      ELSIF arg[1] = "I" THEN Value(arg, i, val);
        IF val[0] # 0X THEN ASS.AddPath(val) END
      ELSIF arg[1] = "D" THEN
        IF nofDefs < maxDefs THEN
          defShared[nofDefs] := arg[2] # 0X; Value(arg, i, val);
          defs[nofDefs] := i; INC(nofDefs)
        ELSE ASH.Str("Too many definitions"); ASH.Ln; bad := TRUE
        END
      ELSE ASH.Str("Unknown option "); ASH.Str(arg); ASH.Ln; bad := TRUE
      END;
      INC(i)
    END
  END Arguments;

  PROCEDURE Assemble;
    VAR format, i, j: INTEGER; listName, arg: ASH.Path;
  BEGIN
    format := ASO.Format(outName);
    IF outName[0] = 0X THEN ASH.Str("No output file; name one with -o"); ASH.Ln; bad := TRUE
    ELSIF format = ASO.Unsupported THEN
      ASH.Str("Cannot tell the output format from the name "); ASH.Str(outName); ASH.Ln; bad := TRUE
    ELSE
      ASS.Init; ASB.Init; ASG.Init; ASI.Init; ASP.Init(outName);
      ASG.SetDefaultCpu(ASO.DefaultCpu(format)); ASI.SetVerbose(verbose);
      FOR i := 0 TO nofDefs - 1 DO
        Env.Arg(defs[i], arg);
        IF defShared[i] THEN  (*drop the "-D"*)
          j := 0;
          REPEAT arg[j] := arg[j + 2]; INC(j) UNTIL arg[j - 1] = 0X
        END;
        ASP.Define(arg)
      END;
      FOR i := 0 TO nofFiles - 1 DO
        Env.Arg(files[i], arg);
        ASH.Str("Assembling "); ASH.Str(arg); ASH.Ln;
        ASP.Compile(arg)
      END;
      IF ASS.errcnt = 0 THEN
        Env.Arg(files[0], arg); ASH.SetExt(arg, ".lst", listName);
        ASI.Assemble(listName)
      END;
      IF ASS.errcnt = 0 THEN ASO.Write(outName, format, legacy) END;
      IF ASS.errcnt # 0 THEN
        ASH.Int(ASS.errcnt);
        IF ASS.errcnt = 1 THEN ASH.Str(" error") ELSE ASH.Str(" errors") END;
        ASH.Str(", no output written"); ASH.Ln
      END
    END
  END Assemble;

BEGIN
  nofFiles := 0; nofDefs := 0; outName[0] := 0X;
  verbose := FALSE; legacy := FALSE; help := FALSE; bad := FALSE;
  Arguments;
  IF help OR (Env.ArgCount() < 2) THEN Help; ASH.Exit(1)
  ELSIF bad THEN ASH.Exit(1)
  ELSIF nofFiles = 0 THEN ASH.Str("No input files"); ASH.Ln; ASH.Exit(1)
  ELSE Assemble;
    IF bad OR (ASS.errcnt # 0) THEN ASH.Exit(1) END
  END
END AS.
