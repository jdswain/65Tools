MODULE Em16; (* em16, an emulator of the 65C816 and its relatives, for
   testing programs of the assembler and the Oberon compiler: the
   command line and the running.

   em16 [-t] [-cpu l28|rockwell|wdc|816] [-fpga] [-bootrom rom.bin]
        [-dp addr] [-sp addr] [-video] [-fbdump ppm] [-test-pattern]
        [-console] [-I dir] [-disk0 file] [-disk1 file] [-wd1793]
        [-scsi file] file ...

   On the default machine and under -fpga the floppy disks are the
   82077AA's, or the WD1793's with -wd1793, and -scsi puts a disk at ID 0
   on the SCSI bus; the L28's are its WD1793's.

   A file with no extension, or one other than .816, is an ELF
   executable; a .816 file an Oberon module. Ported from the C++ em16
   (em16-c), whose behaviour and messages it keeps. Its parts:

     EmCPU    the processor          EmMem   the memory map
     EmLoad   ELF and .816 loading   EmHost  the host (C side: EmHost_rt.c)
     EmUART EmVIA EmFDC EmL28 EmVideo EmLCD  the devices *)

  IMPORT Env, Files, EmHost, EmMem, EmCPU, EmLoad, EmFDC, Em82077, EmSCSI, EmL28, EmVideo, EmLCD, EmCore, EmSoC, EmHarte;

  VAR
    trace, videoEnabled, testPattern, consoleMode, wantFpga, wantL28, bad: BOOLEAN;
    customDp, customSp, entry: INTEGER;
    fbdump, bootrom, font: EmLoad.Path;

  PROCEDURE ErrStr(s: ARRAY OF CHAR);
  BEGIN EmHost.Str(EmHost.err, s)
  END ErrStr;

  PROCEDURE Equal(a, b: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE (i < LEN(a)) & (i < LEN(b)) & (a[i] # 0X) & (a[i] = b[i]) DO INC(i) END;
    RETURN ((i = LEN(a)) OR (a[i] = 0X)) & ((i = LEN(b)) OR (b[i] = 0X))
  END Equal;

  (* strtol(s, NULL, 0): 0x hex, a leading 0 octal, else decimal. *)
  PROCEDURE Number(s: ARRAY OF CHAR): INTEGER;
    VAR i, v, base, d: INTEGER; neg, done: BOOLEAN;
  BEGIN i := 0; v := 0; neg := FALSE; done := FALSE;
    IF s[0] = "-" THEN neg := TRUE; i := 1 ELSIF s[0] = "+" THEN i := 1 END;
    IF (s[i] = "0") & ((s[i+1] = "x") OR (s[i+1] = "X")) THEN base := 16; i := i + 2
    ELSIF s[i] = "0" THEN base := 8
    ELSE base := 10
    END;
    WHILE ~done & (i < LEN(s)) DO
      IF (s[i] >= "0") & (s[i] <= "9") THEN d := ORD(s[i]) - ORD("0")
      ELSIF (s[i] >= "a") & (s[i] <= "f") THEN d := ORD(s[i]) - ORD("a") + 10
      ELSIF (s[i] >= "A") & (s[i] <= "F") THEN d := ORD(s[i]) - ORD("A") + 10
      ELSE d := 99
      END;
      IF d < base THEN v := v * base + d; INC(i) ELSE done := TRUE END
    END;
    IF neg THEN v := -v END;
    RETURN v
  END Number;

  (* The position of the last "." in s, -1 if none. *)
  PROCEDURE Suffix(s: ARRAY OF CHAR): INTEGER;
    VAR i, r: INTEGER;
  BEGIN i := 0; r := -1;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO IF s[i] = "." THEN r := i END; INC(i) END;
    RETURN r
  END Suffix;

  PROCEDURE Cycles(): LONGINT;
  BEGIN RETURN EmCPU.cycles
  END Cycles;

  PROCEDURE Options(VAR index: INTEGER);
    VAR arg, val: EmLoad.Path; n, k: INTEGER; done: BOOLEAN;
  BEGIN n := Env.ArgCount(); done := FALSE;
    WHILE ~done & ~bad & (index < n) DO
      Env.Arg(index, arg);
      IF arg[0] # "-" THEN done := TRUE
      ELSIF Equal(arg, "-t") THEN trace := TRUE; INC(index)
      ELSIF Equal(arg, "-dp") & (index + 1 < n) THEN Env.Arg(index + 1, val); customDp := Number(val); INC(index, 2)
      ELSIF Equal(arg, "-sp") & (index + 1 < n) THEN Env.Arg(index + 1, val); customSp := Number(val); INC(index, 2)
      ELSIF Equal(arg, "-cpu") & (index + 1 < n) THEN Env.Arg(index + 1, val);
        IF Equal(val, "l28") OR Equal(val, "L28") OR Equal(val, "c19") OR Equal(val, "C19") THEN
          EmCPU.SetCpuType(EmCPU.l28); EmMem.EnableL28; EmMem.SetUartBase(1FFFFFH); EmMem.SetFdcBase(640H);
          EmHost.Str(EmHost.out, "CPU type: L28 (R65C19)"); EmHost.Ln(EmHost.out)
        ELSIF Equal(val, "rockwell") OR Equal(val, "r02") THEN
          EmCPU.SetCpuType(EmCPU.rockwell); EmHost.Str(EmHost.out, "CPU type: Rockwell R65C02"); EmHost.Ln(EmHost.out)
        ELSIF Equal(val, "wdc") OR Equal(val, "816") THEN
          EmCPU.SetCpuType(EmCPU.wdc); EmHost.Str(EmHost.out, "CPU type: WDC 65C816"); EmHost.Ln(EmHost.out)
        ELSE ErrStr("Unknown CPU type: "); ErrStr(val); EmHost.Ln(EmHost.err); bad := TRUE
        END;
        INC(index, 2)
      ELSIF Equal(arg, "-video") THEN videoEnabled := TRUE; INC(index)
      ELSIF Equal(arg, "-test-pattern") THEN testPattern := TRUE; INC(index)
      ELSIF Equal(arg, "-fbdump") & (index + 1 < n) THEN Env.Arg(index + 1, fbdump); INC(index, 2)
      ELSIF Equal(arg, "-fpga") THEN INC(index)
      ELSIF Equal(arg, "-bootrom") & (index + 1 < n) THEN Env.Arg(index + 1, bootrom); INC(index, 2)
      ELSIF Equal(arg, "-font") & (index + 1 < n) THEN Env.Arg(index + 1, font); INC(index, 2)
      ELSIF (Equal(arg, "-disk0") OR Equal(arg, "-disk1")) & (index + 1 < n) THEN Env.Arg(index + 1, val);
        k := ORD(arg[5]) - ORD("0");
        IF ~EmSoC.wd1793 & ~EmMem.l28 & ~wantL28 THEN IF Em82077.Mount(k, val) THEN END
        ELSIF EmFDC.Mount(k, val) THEN
        END;
        INC(index, 2)
      ELSIF Equal(arg, "-wd1793") THEN INC(index)
      ELSIF Equal(arg, "-scsi") & (index + 1 < n) THEN Env.Arg(index + 1, val);
        IF EmSCSI.Mount(val) THEN END; INC(index, 2)
      ELSIF Equal(arg, "-I") & (index + 1 < n) THEN Env.Arg(index + 1, val); EmLoad.AddPath(val); INC(index, 2)
      ELSIF (arg[1] = "I") & (arg[2] # 0X) THEN
        k := 0; WHILE arg[k + 2] # 0X DO val[k] := arg[k + 2]; INC(k) END; val[k] := 0X;
        EmLoad.AddPath(val); INC(index)
      ELSIF Equal(arg, "-console") THEN consoleMode := TRUE; INC(index)
      ELSIF Equal(arg, "-?") THEN
        ErrStr("Usage: em16 [-t] [-cpu l28|rockwell|wdc|816] [-fpga] [-bootrom rom.bin] [-font hex] [-dp addr] [-sp addr] [-video] [-fbdump ppm] [-test-pattern] [-console] [-I dir] [-disk0 file] [-disk1 file] [-wd1793] [-scsi file] file ...");
        EmHost.Ln(EmHost.err); bad := TRUE
      ELSE ErrStr("Invalid: option '"); ErrStr(arg); ErrStr("'"); EmHost.Ln(EmHost.err); bad := TRUE
      END
    END
  END Options;

  (* The modules' initialisations, or the program; on the CPU thread when
     there is a window. *)
  PROCEDURE CpuThread*;
    VAR i: INTEGER;
  BEGIN
    IF EmMem.fpga THEN EmSoC.Run
    ELSIF EmLoad.nofEntries > 0 THEN
      FOR i := 0 TO EmLoad.nofEntries - 1 DO
        IF EmLoad.entries[i] # 0 THEN
          EmHost.Str(EmHost.out, "Initialising at "); EmHost.CoutHex(EmLoad.entries[i]); EmHost.Ln(EmHost.out);
          EmHost.Flush;
          EmCPU.JumpLong(EmLoad.entries[i])
        END
      END
    ELSIF entry # 0 THEN
      EmHost.Str(EmHost.out, "Initialising at "); EmHost.CoutHex(entry); EmHost.Ln(EmHost.out); EmHost.Flush;
      EmCPU.JumpLong(entry)
    ELSE EmCPU.Run
    END;
    EmHost.DrainAll
  END CpuThread;

  PROCEDURE BootROM;
    VAR f: Files.File; r: Files.Rider; rom: ARRAY 2000H OF BYTE; b: BYTE; n, i: INTEGER;
  BEGIN f := Files.Old(bootrom);
    IF f = NIL THEN ErrStr("Cannot open boot ROM: "); ErrStr(bootrom); EmHost.Ln(EmHost.err); bad := TRUE
    ELSE
      FOR i := 0 TO 1FFFH DO rom[i] := 0 END;
      n := Files.Length(f); IF n > 2000H THEN n := 2000H END;
      Files.Set(r, f, 0);
      FOR i := 0 TO n - 1 DO Files.ReadByte(r, b); rom[i] := b END;
      EmMem.LoadBootROM(rom, n);
      EmHost.Str(EmHost.out, "Boot ROM loaded ("); EmHost.Cout(n); EmHost.Str(EmHost.out, " bytes), reset vector -> $");
      EmHost.CoutHex(rom[1FFCH] + rom[1FFDH] * 256); EmHost.Ln(EmHost.out)
    END
  END BootROM;

  (* The framebuffer as a PPM file, through the palette. *)
  PROCEDURE FBDump;
    VAR f: Files.File; r: Files.Rider; x, y, b, c, i: INTEGER;
      head: ARRAY 32 OF CHAR;
  BEGIN f := Files.New(fbdump);
    IF f # NIL THEN
      Files.Set(r, f, 0);
      head := "P6"; head[2] := 0AX; head[3] := 0X;
      i := 0; WHILE head[i] # 0X DO Files.WriteByte(r, ORD(head[i])); INC(i) END;
      head := "640 480"; head[7] := 0AX; head[8] := "2"; head[9] := "5"; head[10] := "5"; head[11] := 0AX; head[12] := 0X;
      i := 0; WHILE head[i] # 0X DO Files.WriteByte(r, ORD(head[i])); INC(i) END;
      FOR y := 0 TO EmVideo.height - 1 DO
        FOR x := 0 TO EmVideo.width - 1 DO
          c := EmVideo.Pixel(x, y);
          Files.WriteByte(r, EmVideo.pal[c * 3]); Files.WriteByte(r, EmVideo.pal[c * 3 + 1]);
          Files.WriteByte(r, EmVideo.pal[c * 3 + 2])
        END
      END;
      Files.Register(f);
      EmHost.Str(EmHost.out, "Framebuffer dumped to "); EmHost.Str(EmHost.out, fbdump); EmHost.Ln(EmHost.out)
    END
  END FBDump;

  (* em16 -harte dir [opcode.mode ...]: EmCore against the SingleStepTests *)
  PROCEDURE Harte;
    VAR dir: EmLoad.Path; names: EmHarte.Names; i, n: INTEGER;
  BEGIN Env.Arg(2, dir); n := 0;
    FOR i := 3 TO Env.ArgCount() - 1 DO IF n < 64 THEN Env.Arg(i, names[n]); INC(n) END END;
    EmHarte.Run(dir, names, n); EmHost.DrainAll
  END Harte;

  (* The SoC's text mode font: -font, or the Verilog repository's beside
     the 65Tools that bin/em16 is in. *)
  PROCEDURE LoadFont;
    VAR i, k: INTEGER; path: EmLoad.Path; rest: ARRAY 64 OF CHAR;
  BEGIN
    IF font[0] = 0X THEN
      EmHost.ExePath(path); i := 0; k := -1;
      WHILE path[i] # 0X DO IF path[i] = "/" THEN k := i END; INC(i) END;
      path[k + 1] := 0X;
      rest := "../../Verilog65C816/fpga/rom/font_st8x16.hex";
      i := k + 1; k := 0;
      WHILE rest[k] # 0X DO path[i] := rest[k]; INC(i); INC(k) END; path[i] := 0X;
      font := path
    END;
    IF ~EmVideo.LoadFont(font) THEN
      ErrStr("No text mode font: "); ErrStr(font); EmHost.Ln(EmHost.err)
    END
  END LoadFont;

  PROCEDURE Main;
    VAR index, n, i, suffix, v: INTEGER; arg: EmLoad.Path; cycles: LONGINT;
  BEGIN
    IF Env.ArgCount() > 2 THEN Env.Arg(1, arg);
      IF Equal(arg, "-harte") THEN Harte; EmHost.Exit(0) END
    END;
    trace := FALSE; videoEnabled := FALSE; testPattern := FALSE; consoleMode := FALSE; bad := FALSE;
    customDp := -1; customSp := -1; entry := 0; fbdump[0] := 0X; bootrom[0] := 0X; font[0] := 0X;
    n := Env.ArgCount();
    (* -fpga first, so that the memory has its size before files are loaded *)
    (* and -wd1793 and -cpu l28, so that floppies go to the right controller *)
    wantFpga := FALSE; wantL28 := FALSE;
    FOR i := 1 TO n - 1 DO Env.Arg(i, arg);
      IF Equal(arg, "-fpga") THEN wantFpga := TRUE ELSIF Equal(arg, "-wd1793") THEN EmSoC.UseWD1793
      ELSIF Equal(arg, "-cpu") & (i + 1 < n) THEN Env.Arg(i + 1, arg);
        wantL28 := Equal(arg, "l28") OR Equal(arg, "L28") OR Equal(arg, "c19") OR Equal(arg, "C19")
      END
    END;
    EmMem.SetClock(Cycles);
    IF wantFpga THEN EmMem.EnableFPGA; EmMem.SetMemory(7FFFFFH, 800000H)
    ELSE EmMem.SetMemory(0FFFFFH, 100000H)
    END;
    index := 1; Options(index);
    IF ~bad THEN
      EmLoad.ClearEntries;
      IF index < n THEN
        WHILE index < n DO
          Env.Arg(index, arg); suffix := Suffix(arg);
          IF (suffix >= 0) & (arg[suffix+1] = "8") & (arg[suffix+2] = "1") & (arg[suffix+3] = "6") & (arg[suffix+4] = 0X) THEN
            entry := EmLoad.LoadMod(arg); EmLoad.AddEntry(entry)
          ELSE entry := EmLoad.LoadELF(arg)
          END;
          INC(index)
        END
      ELSIF (bootrom[0] = 0X) & ~wantFpga THEN
        ErrStr("No ELF files specified"); EmHost.Ln(EmHost.err); bad := TRUE
      END
    END;
    IF ~bad THEN
      IF ~wantFpga THEN EmLoad.WriteManifest END;
      IF consoleMode THEN
        EmL28.EnableKeyboard; EmL28.SetConsoleMode(TRUE); EmL28.SetCocoaInput(TRUE); EmLCD.EnableDisplay;
        EmHost.Str(EmHost.out, "Console mode: keyboard input via LCD window, LCD enabled"); EmHost.Ln(EmHost.out)
      END;
      EmHost.ClockStart;
      IF customSp >= 0 THEN EmCPU.SetStackPage(customSp) END;
      EmMem.InitFlash;
      IF bootrom[0] # 0X THEN BootROM END
    END;
    IF ~bad THEN
      IF EmMem.fpga THEN EmCore.SetTrace(trace); EmSoC.Reset; LoadFont; EmHost.SetADB(1) END;
      EmCPU.Reset(trace);
      IF ~EmMem.fpga & (EmCPU.cpuType # EmCPU.l28) THEN
        EmCPU.SetNativeMode;
        (* the stack grows down from below the disk controllers at $0800 *)
        IF customSp >= 0 THEN EmCPU.SetSP(customSp) ELSE EmCPU.SetSP(7FFH) END
      END;
      IF customDp >= 0 THEN
        EmCPU.SetDP(customDp);
        EmHost.Str(EmHost.out, "DP set to $"); EmHost.Hex(EmHost.out, customDp, 4); EmHost.Ln(EmHost.out)
      END;
      EmLoad.InitHeap;
      EmHost.Flush;
      IF EmLCD.displayEnabled THEN EmHost.RunLCD
      ELSIF videoEnabled THEN
        IF testPattern THEN
          FOR i := 0 TO EmVideo.height - 1 DO
            IF i < EmVideo.height DIV 4 THEN v := 0FFH
            ELSIF i < EmVideo.height DIV 2 THEN v := 0AAH
            ELSIF i < 3 * EmVideo.height DIV 4 THEN v := 55H
            ELSE v := 0
            END;
            EmVideo.FillRow(i, v)
          END
        END;
        EmHost.RunVideo
      ELSE CpuThread
      END;
      IF fbdump[0] # 0X THEN FBDump END;
      IF EmMem.fpga THEN cycles := EmSoC.now ELSE cycles := EmCPU.cycles END;
      IF EmHost.coutHex THEN EmHost.Report(cycles, 1) ELSE EmHost.Report(cycles, 0) END
    ELSE EmHost.Exit(1)
    END
  END Main;

BEGIN Main
END Em16.
