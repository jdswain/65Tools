MODULE Em16; (* em16, an emulator of the 65C816 and its relatives, for
   testing programs of the assembler and the Oberon compiler: the
   command line and the running.

   em16 [-t] [-cpu l28|rockwell|wdc|816] [-fpga] [-c832] [-sysclk hz] [-cpuclk hz] [-turbo] [-smc] [-nodisplay] [-bootrom rom.bin]
        [-dp addr] [-sp addr] [-video] [-fbdump ppm] [-prof file cycles] [-test-pattern]
        [-console] [-disk0 file] [-disk1 file] [-wd1793]
        [-scsi file] [-scsitiming] [-sd file] [-net vmnet|vmnet-host|vmnet-bridged:IF|udp:LPORT:RPORT[:HOST]] [-mac aa:bb:cc:dd:ee:ff]
        [-rtc file] [-rtctime YYYYMMDDhhmmss] [-nortc] [-adbkey code] [-adbmouse dx dy] file ...
   em16 -mini816 [-t] [-flash file] [-rom file] [-flashsize 128K|256K|512K] [-ramsize 128K|512K]
        [-noflashwrite] [-iostretch n] [-openbus v] [-cpuclk hz] [-turbo]
        [-scca console|pty|tcp:PORT|none] [-sccb console|pty|tcp:PORT|none]
        [-sd file] [-sdcd low|high] [-video] [-joyarrows] [-key col,row] [-fbdump ppm]

   On the default machine and under -fpga the floppy disks are the
   82077AA's, or the WD1793's with -wd1793, and -scsi puts a disk at ID 0
   on the SCSI bus (-scsitiming, under -fpga, gives it the time a drive
   of about 1990 takes: EmSCSI); -sd puts a card in the microSD slot, an SDHC card of
   the file's raw blocks. The L28's are its WD1793's. Under -fpga the
   rev B's real-time clock (EmRTC) runs from the host's time in UTC, or
   from -rtctime's; -rtc keeps it in a file (a new module, its oscillator
   off, if the file is not there yet); -nortc leaves it out, as on a rev
   A board (the last of the three wins). Under -fpga, -adbkey
   holds an ADB key code down from power on (the keyboard reports it at
   the first Talk), as a key held while the board starts, and -adbmouse
   moves the mouse dx right and dy down from power on, reported at the
   mouse's Talks (a test of a program's own pointer). -cpuclk runs the
   core on a clock of its own below the system clock (8M or 16M, a real
   65C816's), the memory and devices keeping theirs; -turbo runs flat out
   even with a window, never in step with the host's time.

   -mini816 is the Mini816 (EmMini816) instead, kept to real time but
   with -turbo: -flash is the file that holds its flash (made at the first
   write if it is not there, read-only if the file is), -rom an image put
   at the top of the flash (a boot ROM, its vectors at $FFE0-$FFFF), the
   sizes the smaller chips, -noflashwrite the FLASH_WRITE jumper off,
   -iostretch an I/O cycle's CPU clocks (8), -openbus what nothing driving
   the bus reads ($FF), -cpuclk the CPU's clock (7.3728M; the SCC's PCLK
   stays), -scca and -sccb the SCC's channels' hosts (A the console, B
   none), -sd the microSD card's image and -sdcd the level of its detect
   with the card in (low). -video opens the VDP's window, whose keys are
   the keyboard's, the keypad and a game controller the joystick (with
   -joyarrows the arrows and right Option too); -key holds a key of the
   matrix down from power on; -fbdump writes the VDP's last frame.
   SIGUSR1 presses its NMI button, SIGUSR2 its reset.

   A file is an ELF executable. Oberon modules are not loaded by em16:
   OS16 boots on -fpga, from a floppy, as on the board, and loads them.
   Ported from the C++ em16 (em16-c). Its parts:

     EmCPU    the processor          EmMem   the memory map
     EmLoad   ELF loading, traps     EmHost  the host (C side: EmHost_rt.c)
     EmUART EmVIA EmFDC EmL28 EmVideo EmLCD  the devices *)

  IMPORT Env, Files, EmHost, EmMem, EmCPU, EmLoad, EmFDC, Em82077, EmSCSI, EmSD, EmEth, EmRTC, EmADB, EmL28, EmVideo, EmLCD, EmCore, EmSDRAM, EmSoC, EmHarte,
    EmW816, EmFlash, EmZ85C30, EmMini816, EmTMS9918;

  VAR
    trace, videoEnabled, testPattern, consoleMode, wantFpga, wantL28, wantMini, bad: BOOLEAN;
    sysclk: INTEGER;          (* -sysclk: the SoC's clock, 0 its default *)
    customDp, customSp, entry: INTEGER;
    adbKeys: ARRAY 8 OF INTEGER; nAdbKeys: INTEGER;   (* -adbkey: held down at reset *)
    adbDx, adbDy: INTEGER;                            (* -adbmouse: moved at reset *)
    fbdump, bootrom, font, profArg: EmLoad.Path;

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

  (* A frequency: hz (40500000), or MHz or kHz with M or k (8M, 14.318M,
     500k), Hz after them allowed; 0 if s is not one. *)
  PROCEDURE Hertz(s: ARRAY OF CHAR): INTEGER;
    VAR i, v, scale, div: INTEGER; point: BOOLEAN;
  BEGIN i := 0; v := 0; div := 1; scale := 1; point := FALSE;
    WHILE (i < LEN(s)) & ((s[i] >= "0") & (s[i] <= "9") OR (s[i] = ".") & ~point) DO
      IF s[i] = "." THEN point := TRUE
      ELSE v := v * 10 + ORD(s[i]) - ORD("0"); IF point THEN div := div * 10 END
      END;
      INC(i)
    END;
    IF i < LEN(s) THEN
      IF (s[i] = "M") OR (s[i] = "m") THEN scale := 1000000; INC(i)
      ELSIF (s[i] = "k") OR (s[i] = "K") THEN scale := 1000; INC(i)
      END
    END;
    IF (i + 1 < LEN(s)) & ((s[i] = "H") OR (s[i] = "h")) & (s[i + 1] = "z") THEN INC(i, 2) END;
    IF (i < LEN(s)) & (s[i] # 0X) OR (div > scale) THEN v := 0 ELSE v := v * (scale DIV div) END;
    RETURN v
  END Hertz;


  PROCEDURE Cycles(): LONGINT;
  BEGIN RETURN EmCPU.cycles
  END Cycles;

  PROCEDURE Options(VAR index: INTEGER);
    VAR arg, val: EmLoad.Path; n, k, tskip: INTEGER; done: BOOLEAN;
  BEGIN n := Env.ArgCount(); done := FALSE;
    WHILE ~done & ~bad & (index < n) DO
      Env.Arg(index, arg);
      IF arg[0] # "-" THEN done := TRUE
      ELSIF Equal(arg, "-t") THEN trace := TRUE; INC(index)
      ELSIF Equal(arg, "-tfrom") & (index + 3 < n) THEN
        Env.Arg(index + 1, val); k := Number(val); Env.Arg(index + 2, val); tskip := Number(val);
        Env.Arg(index + 3, val); EmCore.TraceFrom(k, tskip, Number(val)); INC(index, 4)
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
      ELSIF Equal(arg, "-prof") & (index + 2 < n) THEN Env.Arg(index + 1, val); Env.Arg(index + 2, profArg);
        IF ~EmSoC.Profile(val, Number(profArg)) THEN ErrStr("Cannot write "); ErrStr(val); EmHost.Ln(EmHost.err); bad := TRUE END;
        INC(index, 3)
      ELSIF Equal(arg, "-fbdump") & (index + 1 < n) THEN Env.Arg(index + 1, fbdump); INC(index, 2)
      ELSIF Equal(arg, "-fpga") THEN INC(index)
      ELSIF Equal(arg, "-smc") THEN EmCore.SetSMC(TRUE); INC(index)
      ELSIF Equal(arg, "-c832") THEN EmCore.SetC832(TRUE); INC(index)
      ELSIF Equal(arg, "-nodisplay") THEN EmSDRAM.NoDisplay; INC(index)
      ELSIF Equal(arg, "-sysclk") & (index + 1 < n) THEN INC(index, 2)
      ELSIF Equal(arg, "-turbo") THEN EmSoC.Turbo; INC(index)
      ELSIF Equal(arg, "-cpuclk") & (index + 1 < n) THEN Env.Arg(index + 1, val); k := Hertz(val);
        IF (k <= 0) OR (k > EmHost.hz) THEN
          ErrStr("-cpuclk: hz, at most the system clock's (8M, 16M), not "); ErrStr(val); EmHost.Ln(EmHost.err); bad := TRUE
        ELSE EmSoC.SetCpuClock(k)
        END;
        INC(index, 2)
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
      ELSIF Equal(arg, "-scsitiming") THEN
        IF wantFpga THEN EmSCSI.SetTiming ELSE ErrStr("-scsitiming: only with -fpga"); EmHost.Ln(EmHost.err); bad := TRUE END;
        INC(index)
      ELSIF Equal(arg, "-sd") & (index + 1 < n) THEN Env.Arg(index + 1, val);
        IF EmSD.Mount(val) THEN END; INC(index, 2)
      ELSIF Equal(arg, "-net") & (index + 1 < n) THEN Env.Arg(index + 1, val);
        IF ~EmEth.Open(val) THEN bad := TRUE END; INC(index, 2)
      ELSIF Equal(arg, "-mac") & (index + 1 < n) THEN Env.Arg(index + 1, val);
        IF ~EmEth.SetMac(val) THEN ErrStr("-mac: aa:bb:cc:dd:ee:ff, not "); ErrStr(val); EmHost.Ln(EmHost.err); bad := TRUE END;
        INC(index, 2)
      ELSIF Equal(arg, "-nortc") THEN EmRTC.Absent; INC(index)
      ELSIF Equal(arg, "-rtc") & (index + 1 < n) THEN Env.Arg(index + 1, val); EmRTC.Load(val); INC(index, 2)
      ELSIF Equal(arg, "-rtctime") & (index + 1 < n) THEN Env.Arg(index + 1, val);
        IF ~EmRTC.SetTime(val) THEN ErrStr("-rtctime: YYYYMMDDhhmmss, not "); ErrStr(val); EmHost.Ln(EmHost.err); bad := TRUE END;
        INC(index, 2)
      ELSIF Equal(arg, "-console") THEN consoleMode := TRUE; INC(index)
      ELSIF Equal(arg, "-adbkey") & (index + 1 < n) THEN Env.Arg(index + 1, val);
        IF nAdbKeys < LEN(adbKeys) THEN adbKeys[nAdbKeys] := Number(val); INC(nAdbKeys) END; INC(index, 2)
      ELSIF Equal(arg, "-adbmouse") & (index + 2 < n) THEN
        Env.Arg(index + 1, val); adbDx := Number(val); Env.Arg(index + 2, val); adbDy := Number(val); INC(index, 3)
      ELSIF Equal(arg, "-?") THEN
        ErrStr("Usage: em16 [-t] [-tfrom addr skip count] [-cpu l28|rockwell|wdc|816] [-fpga] [-c832] [-sysclk hz] [-cpuclk hz] [-turbo] [-smc] [-nodisplay] [-bootrom rom.bin] [-font hex] [-dp addr] [-sp addr] [-video] [-fbdump ppm] [-prof file cycles] [-test-pattern] [-console] [-disk0 file] [-disk1 file] [-wd1793] [-scsi file] [-scsitiming] [-sd file] [-adbkey code] [-adbmouse dx dy] file ...");
        EmHost.Ln(EmHost.err); bad := TRUE
      ELSE ErrStr("Invalid: option '"); ErrStr(arg); ErrStr("'"); EmHost.Ln(EmHost.err); bad := TRUE
      END
    END
  END Options;

  (* The program; on the CPU thread when there is a window. *)
  PROCEDURE CpuThread*;
  BEGIN
    IF wantMini THEN EmMini816.Run
    ELSIF EmMem.fpga THEN EmSoC.Run
    ELSIF entry # 0 THEN
      EmHost.Str(EmHost.out, "Initialising at "); EmHost.CoutHex(entry); EmHost.Ln(EmHost.out); EmHost.Flush;
      EmCPU.JumpLong(entry)
    ELSE EmCPU.Run
    END;
    EmHost.DrainAll
  END CpuThread;

  PROCEDURE BootROM;
    VAR f: Files.File; r: Files.Rider; rom: ARRAY 8000H OF BYTE; b: BYTE; n, i: INTEGER;
  BEGIN f := Files.Old(bootrom);
    IF f = NIL THEN ErrStr("Cannot open boot ROM: "); ErrStr(bootrom); EmHost.Ln(EmHost.err); bad := TRUE
    ELSIF (Files.Length(f) = 0) OR (Files.Length(f) > 8000H) THEN
      ErrStr("Boot ROM must be 1 to 32768 bytes: "); ErrStr(bootrom); EmHost.Ln(EmHost.err); bad := TRUE
    ELSE
      n := Files.Length(f);
      Files.Set(r, f, 0);
      FOR i := 0 TO n - 1 DO Files.ReadByte(r, b); rom[i] := b END;
      EmMem.LoadBootROM(rom, n);
      EmHost.Str(EmHost.out, "Boot ROM loaded ("); EmHost.Cout(n); EmHost.Str(EmHost.out, " bytes), reset vector -> $");
      EmHost.CoutHex(rom[n - 4] + rom[n - 3] * 256); EmHost.Ln(EmHost.out)
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
      head := "1024 768"; head[8] := 0AX; head[9] := "2"; head[10] := "5"; head[11] := "5"; head[12] := 0AX; head[13] := 0X;
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

  (* em16 -bench file [-c832]: a test image of the Verilog repository on EmCore *)
  PROCEDURE Bench;
    VAR file, arg: EmLoad.Path;
  BEGIN Env.Arg(2, file);
    IF Env.ArgCount() > 3 THEN Env.Arg(3, arg); IF Equal(arg, "-c832") THEN EmCore.SetC832(TRUE) END END;
    EmHarte.Bench(file); EmHost.DrainAll
  END Bench;

  (* em16 -harte dir [opcode.mode ...]: EmCore against the SingleStepTests *)
  PROCEDURE Harte;
    VAR dir: EmLoad.Path; names: EmHarte.Names; i, n: INTEGER;
  BEGIN Env.Arg(2, dir); n := 0;
    FOR i := 3 TO Env.ArgCount() - 1 DO IF n < 64 THEN Env.Arg(i, names[n]); INC(n) END END;
    EmHarte.Run(dir, names, n); EmHost.DrainAll
  END Harte;

  (* em16 -harte816 dir [-show n] [opcode.mode ...]: EmW816, the chip,
     against the SingleStepTests, cycle by cycle; n failures shown in full
     a file (default 1) *)
  PROCEDURE Harte816;
    VAR dir, arg: EmLoad.Path; names: EmHarte.Names; i, n, show: INTEGER;
  BEGIN Env.Arg(2, dir); n := 0; show := 1; i := 3;
    WHILE i < Env.ArgCount() DO Env.Arg(i, arg);
      IF Equal(arg, "-show") & (i + 1 < Env.ArgCount()) THEN INC(i); Env.Arg(i, arg); show := Number(arg)
      ELSIF n < 64 THEN Env.Arg(i, names[n]); INC(n)
      END;
      INC(i)
    END;
    EmHarte.Run816(dir, names, n, show); EmHost.DrainAll
  END Harte816;

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

  (* A size: 128K, 256K, 512K, or bytes *)
  PROCEDURE Size(s: ARRAY OF CHAR): INTEGER;
    VAR v: INTEGER;
  BEGIN
    IF Equal(s, "128K") OR Equal(s, "128k") THEN v := 20000H
    ELSIF Equal(s, "256K") OR Equal(s, "256k") THEN v := 40000H
    ELSIF Equal(s, "512K") OR Equal(s, "512k") THEN v := 80000H
    ELSE v := Number(s)
    END;
    RETURN v
  END Size;

  (* the SCC's channel c (A or B) on h: console, pty, tcp:PORT or none *)
  PROCEDURE SccHost(c: INTEGER; h: ARRAY OF CHAR);
    VAR name: EmLoad.Path;
  BEGIN
    IF Equal(h, "console") THEN EmZ85C30.SetHost(c, EmZ85C30.console, 0)
    ELSIF Equal(h, "none") THEN EmZ85C30.SetHost(c, EmZ85C30.none, 0)
    ELSIF EmHost.PortOpen(c, h) # 0 THEN EmZ85C30.SetHost(c, EmZ85C30.port, c);
      EmHost.PortName(c, name);
      IF c = EmZ85C30.A THEN ErrStr("SCC channel A: ") ELSE ErrStr("SCC channel B: ") END;
      ErrStr(name); EmHost.Ln(EmHost.err); EmHost.Drain(EmHost.err)
    ELSE ErrStr("-scca, -sccb: console, pty, tcp:PORT or none, not "); ErrStr(h); EmHost.Ln(EmHost.err); bad := TRUE
    END
  END SccHost;

  (* -key col,row: the key held down, FALSE if s is not two numbers *)
  PROCEDURE HoldKey(s: ARRAY OF CHAR): BOOLEAN;
    VAR i, j, c, r: INTEGER; ok: BOOLEAN;
  BEGIN i := 0; c := 0; r := 0;
    WHILE (i < 3) & (s[i] >= "0") & (s[i] <= "9") DO c := c * 10 + ORD(s[i]) - ORD("0"); INC(i) END;
    ok := (i > 0) & (s[i] = ",");
    IF ok THEN INC(i); j := i;
      WHILE (i < j + 3) & (s[i] >= "0") & (s[i] <= "9") DO r := r * 10 + ORD(s[i]) - ORD("0"); INC(i) END;
      ok := (i > j) & (s[i] = 0X) & ((c < 8) OR (c = 15)) & (r < 8)
    END;
    IF ok THEN EmMini816.Key(c, r, 1) END;
    RETURN ok
  END HoldKey;

  (* -fbdump: the VDP's last frame as a PPM file, through its palette *)
  PROCEDURE VdpDump(name: ARRAY OF CHAR);
    VAR f: Files.File; r: Files.Rider; i, c: INTEGER; head: ARRAY 32 OF CHAR;
  BEGIN f := Files.New(name);
    IF f # NIL THEN Files.Set(r, f, 0);
      head := "P6 288 240 255"; head[2] := 0AX; head[10] := 0AX; head[14] := 0AX; head[15] := 0X;
      i := 0; WHILE head[i] # 0X DO Files.WriteByte(r, ORD(head[i])); INC(i) END;
      FOR i := 0 TO EmTMS9918.width * EmTMS9918.height - 1 DO c := EmTMS9918.fb[i];
        Files.WriteByte(r, EmTMS9918.pal[c * 3]); Files.WriteByte(r, EmTMS9918.pal[c * 3 + 1]);
        Files.WriteByte(r, EmTMS9918.pal[c * 3 + 2])
      END;
      Files.Register(f)
    ELSE ErrStr("Cannot write "); ErrStr(name); EmHost.Ln(EmHost.err)
    END
  END VdpDump;

  (* em16 -mini816 ... (this module's head) *)
  PROCEDURE Mini;
    VAR i, n, k, flashSize, ramSize: INTEGER; arg, val, flash, rom, dump: EmLoad.Path; noWrite, video: BOOLEAN;
  BEGIN n := Env.ArgCount(); i := 1; flash[0] := 0X; rom[0] := 0X; dump[0] := 0X; noWrite := FALSE; video := FALSE;
    flashSize := 80000H; ramSize := 80000H;
    WHILE ~bad & (i < n) DO Env.Arg(i, arg);
      IF (i + 1 < n) & (Equal(arg, "-flash") OR Equal(arg, "-rom") OR Equal(arg, "-flashsize")
          OR Equal(arg, "-ramsize") OR Equal(arg, "-iostretch") OR Equal(arg, "-openbus")
          OR Equal(arg, "-cpuclk") OR Equal(arg, "-scca") OR Equal(arg, "-sccb")
          OR Equal(arg, "-sd") OR Equal(arg, "-sdcd") OR Equal(arg, "-key") OR Equal(arg, "-fbdump")) THEN
        INC(i); Env.Arg(i, val);
        IF Equal(arg, "-flash") THEN flash := val
        ELSIF Equal(arg, "-rom") THEN rom := val
        ELSIF Equal(arg, "-flashsize") THEN flashSize := Size(val);
          IF (flashSize # 20000H) & (flashSize # 40000H) & (flashSize # 80000H) THEN
            ErrStr("-flashsize: 128K, 256K or 512K, not "); ErrStr(val); EmHost.Ln(EmHost.err); bad := TRUE
          END
        ELSIF Equal(arg, "-ramsize") THEN ramSize := Size(val);
          IF (ramSize # 20000H) & (ramSize # 80000H) THEN
            ErrStr("-ramsize: 128K or 512K, not "); ErrStr(val); EmHost.Ln(EmHost.err); bad := TRUE
          END
        ELSIF Equal(arg, "-iostretch") THEN k := Number(val);
          IF k < 1 THEN ErrStr("-iostretch: CPU clocks, 1 or more"); EmHost.Ln(EmHost.err); bad := TRUE
          ELSE EmMini816.SetIoClks(k)
          END
        ELSIF Equal(arg, "-openbus") THEN EmMini816.SetOpenBus(Number(val))
        ELSIF Equal(arg, "-cpuclk") THEN k := Hertz(val);
          IF k <= 0 THEN ErrStr("-cpuclk: hz (7.3728M), not "); ErrStr(val); EmHost.Ln(EmHost.err); bad := TRUE
          ELSE EmMini816.SetCpuClock(k)
          END
        ELSIF Equal(arg, "-scca") THEN SccHost(EmZ85C30.A, val)
        ELSIF Equal(arg, "-sccb") THEN SccHost(EmZ85C30.B, val)
        ELSIF Equal(arg, "-sd") THEN bad := ~EmSD.Mount(val)
        ELSIF Equal(arg, "-fbdump") THEN dump := val
        ELSIF Equal(arg, "-key") THEN
          IF ~HoldKey(val) THEN ErrStr("-key: col,row (0-7 or 15, 0-7), not "); ErrStr(val); EmHost.Ln(EmHost.err); bad := TRUE END
        ELSIF Equal(val, "low") OR Equal(val, "high") THEN EmMini816.SetCardDetect(Equal(val, "low"))
        ELSE ErrStr("-sdcd: low or high, not "); ErrStr(val); EmHost.Ln(EmHost.err); bad := TRUE
        END
      ELSIF Equal(arg, "-mini816") THEN
      ELSIF Equal(arg, "-noflashwrite") THEN noWrite := TRUE
      ELSIF Equal(arg, "-turbo") THEN EmMini816.Turbo
      ELSIF Equal(arg, "-video") THEN video := TRUE
      ELSIF Equal(arg, "-joyarrows") THEN EmMini816.JoyArrows
      ELSIF Equal(arg, "-t") THEN EmW816.SetTrace(TRUE)
      ELSE ErrStr("Invalid with -mini816: option '"); ErrStr(arg); ErrStr("'"); EmHost.Ln(EmHost.err); bad := TRUE
      END;
      INC(i)
    END;
    IF ~bad THEN
      EmMini816.SetRam(ramSize); EmFlash.SetSize(flashSize); EmFlash.Protect(noWrite);
      IF (flash[0] # 0X) & ~EmFlash.Open(flash) THEN
        ErrStr("Cannot open the flash: "); ErrStr(flash); EmHost.Ln(EmHost.err); bad := TRUE
      END;
      IF (rom[0] # 0X) & ~EmFlash.LoadTop(rom) THEN
        ErrStr("Cannot load the ROM (at most the flash's size): "); ErrStr(rom); EmHost.Ln(EmHost.err); bad := TRUE
      END
    END;
    IF bad THEN EmHost.Exit(1) END;
    EmHost.ClockStart; EmMini816.Reset;
    IF video THEN EmTMS9918.SetRender(1); EmHost.RunMini       (* until the window closes *)
    ELSE IF dump[0] # 0X THEN EmTMS9918.SetRender(2) END; CpuThread
    END;
    IF dump[0] # 0X THEN VdpDump(dump) END;
    IF EmHost.coutHex THEN EmHost.Report(EmMini816.now, 1) ELSE EmHost.Report(EmMini816.now, 0) END
  END Mini;

  PROCEDURE Main;
    VAR index, n, i, v: INTEGER; arg: EmLoad.Path; cycles: LONGINT;
  BEGIN
    IF Env.ArgCount() > 2 THEN Env.Arg(1, arg);
      IF Equal(arg, "-harte") THEN Harte; EmHost.Exit(0)
      ELSIF Equal(arg, "-harte816") THEN Harte816; EmHost.Exit(0)
      ELSIF Equal(arg, "-bench") THEN Bench; EmHost.Exit(0)
      END
    END;
    trace := FALSE; videoEnabled := FALSE; testPattern := FALSE; consoleMode := FALSE; bad := FALSE;
    customDp := -1; customSp := -1; entry := 0; nAdbKeys := 0; adbDx := 0; adbDy := 0; fbdump[0] := 0X; bootrom[0] := 0X; font[0] := 0X;
    n := Env.ArgCount();
    (* -fpga first, so that the memory has its size before files are loaded *)
    (* and -wd1793 and -cpu l28, so that floppies go to the right controller *)
    wantFpga := FALSE; wantL28 := FALSE; wantMini := FALSE; sysclk := 0;
    FOR i := 1 TO n - 1 DO Env.Arg(i, arg);
      IF Equal(arg, "-mini816") THEN wantMini := TRUE
      ELSIF Equal(arg, "-fpga") THEN wantFpga := TRUE ELSIF Equal(arg, "-wd1793") THEN EmSoC.UseWD1793
      ELSIF Equal(arg, "-sysclk") & (i + 1 < n) THEN Env.Arg(i + 1, arg); sysclk := Hertz(arg)
      ELSIF Equal(arg, "-cpu") & (i + 1 < n) THEN Env.Arg(i + 1, arg);
        wantL28 := Equal(arg, "l28") OR Equal(arg, "L28") OR Equal(arg, "c19") OR Equal(arg, "C19")
      END
    END;
    IF wantMini THEN Mini; EmHost.Exit(0) END;
    EmMem.SetClock(Cycles);
    IF wantFpga THEN EmHost.SetClock(40500000) END;              (* the board's clock (top_tang20k.v) *)
    IF sysclk > 0 THEN EmHost.SetClock(sysclk) END;
    IF wantFpga THEN EmMem.EnableFPGA; EmMem.SetMemory(7FFFFFH, 800000H)
    ELSE EmMem.SetMemory(0FFFFFH, 100000H)
    END;
    index := 1; Options(index);
    IF ~bad THEN
      IF index < n THEN
        WHILE index < n DO
          Env.Arg(index, arg); entry := EmLoad.LoadELF(arg);
          INC(index)
        END
      ELSIF (bootrom[0] = 0X) & ~wantFpga THEN
        ErrStr("No ELF files specified"); EmHost.Ln(EmHost.err); bad := TRUE
      END
    END;
    IF ~bad THEN
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
      IF EmMem.fpga THEN EmCore.SetTrace(trace); EmSoC.Reset; LoadFont; EmHost.SetADB(1);
        FOR i := 0 TO nAdbKeys - 1 DO EmADB.KeyDown(adbKeys[i]) END;   (* keys held at power on *)
        IF (adbDx # 0) OR (adbDy # 0) THEN EmADB.MouseMove(adbDx, adbDy) END
      END;
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
      EmLoad.InitTraps;
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
      IF EmMem.fpga & (EmCore.smcHits > 0) THEN
        EmHost.Int(EmHost.err, EmCore.smcHits); ErrStr(" stores to queued code"); EmHost.Ln(EmHost.err)
      END;
      IF EmMem.fpga THEN cycles := EmSoC.now ELSE cycles := EmCPU.cycles END;
      IF EmHost.coutHex THEN EmHost.Report(cycles, 1) ELSE EmHost.Report(cycles, 0) END
    ELSE EmHost.Exit(1)
    END
  END Main;

BEGIN Main
END Em16.
