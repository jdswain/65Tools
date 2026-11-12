MODULE EmSoC; (* The Tang Nano 20K SoC of ../../Verilog65C816/fpga: its
   memory map, its devices and its time, around EmCore.

   $00_0000-$7F_FFFF  SDRAM, 8 MB, through the cache (EmSDRAM); except
     $00_0200-$00_0FFF  the I/O block, a device per 64 byte slot:
       $0200 unclaimed: $FF       $0300 system control: bit 0 boot ROM
       $0240 palette, write only  $0340 external bus control
       $0280 ADB host (EmADB)     $0380 video control: bit 0 text,
                                  bit 7 (read) 1024 x 768
       $02C0 microSD slot (EmSD)  $03C0 blitter (EmBlit)
       $0400 the DMA engine (EmDMA): channels 0, 1 and 2 (the ENC424J600)
       $0440 interrupt status (read): 0 the timer, 1 DMA channel 0,
             2 DMA channel 1, 3 the cards' IRQ#, 4 the SCC (emulated in
             the FPGA; the real one will be on the cards' IRQ#), 5 the
             power key (EmPower, with its IE), 6 DMA channel 2; $0441 the
             mask, 1 = the source reaches the IRQ, $FF at reset; the
             rest of $0440-$044F reads 0
       $0450 the tick timer (EmTimer); $0440-$045F repeats at $0460
       $0480 soft power and the power LED (EmPower), mirrored to $04BF
       $04C0-$07FF unclaimed: $FF
       $0800-$0FFF the external bus: 8 slots of 16 registers, mirrored
                   every 128 bytes, as the carrier's 74HCT138 decodes them:
                   slot 0 the 82077AA floppy controller (Em82077), or with
                   -wd1793 the WD1793 card (EmFDC); slot 1 the 82077AA's
                   /DACK; slot 3 the SCSI half of its Z85C80 (EmSCSI);
                   slot 4 the 53C80's /DACK; slot 5 the ENC424J600
                   Ethernet controller (EmEth); 6 empty: $FF; 7 the
                   rev B's DS12C887 real-time clock (EmRTC), or with
                   -nortc nothing: the data lines have no pull-ups, so a
                   read gets what the bus last held (bus). A CPU access
                   to a /DACK slot is pseudo-DMA, a byte without TC.
         $0820-$082F the emulated Z85C30 SCC (EmSCC), the serial port,
                   which answers in place of slot 2 in 2 cycles (3
                   straight after another access to it)
     $00_E000-$00_FFFF  the boot ROM while system control bit 0 is set,
                   or from $C000 or $8000 for an image over 8 or 16K
                   (LoadROM); writes there always go to the SDRAM
   $80_0000-$FF_FFFF  unmapped: $FF

   Time is the SoC's system clock, EmHost.hz: the board's 40.5 MHz, or
   -sysclk's (25.2 MHz for soc.v's simulation). The core runs clock by
   clock (EmCore), and each of its bus cycles takes the cycles soc.v gives
   it: the boot ROM, the I/O block and unmapped addresses 2, the SDRAM
   what the cache takes (EmSDRAM), the emulated SCC 2 (3 straight after
   another access to it), the external bus 3T + H + 4, T and H the
   bridge's bus clock and edge gap in system clocks (21 at 40.5 MHz, 14
   at 25.2: its Intel cycle on the 8.4 MHz timing, as the CPU sees it);
   an access to the SD slot's DATA or NEXT also waits for an exchange
   running to end. A fill of the core's instruction queue (Fetch) takes
   a word of the boot ROM in 2 cycles and of the SDRAM as the cache does,
   and a byte of anything else. The devices are
   given the time as it passes. The IRQ line is the sources of $0440
   that $0441 lets through: the timer, the DMA engine's channels, the
   cards' IRQ# (the 82077AA's INT, the 53C80's IRQ, the ENC424J600's
   /INT and the DS12C887's /IRQ), which bit 0 of
   $0340 also reads, and the SCC; setting bit 0 of $0340 resets the
   cards' chips (RES#).

   With -cpuclk (SetCpuClock) the core runs on a clock of its own, slower
   than the system clock, as if a clock enable at that rate drove it: a
   state without a bus cycle takes a clock of the core's, and a bus cycle
   ends at the first edge of the core's clock once the memory or device
   is ready, at least one after it began. The memory, the devices and the
   display keep the system clock. The core then counts its own clocks
   (Clock), and a fill's ready is in them. Not the board's: its core runs
   on the system clock. *)

  IMPORT Files, EmHost, EmCore, EmSDRAM, EmSCC, EmADB, EmBlit, EmSD, EmFDC, Em82077, EmSCSI, EmEth, EmPower, EmRTC, EmDMA, EmTimer, EmVideo;

  CONST
    Polls = 200;              (* ADB transactions in a second: the guest reads its input (OS16 400, the boot ROM 100) *)

  VAR
    extCost: INTEGER;         (* an external bus cycle: 3T + H + 4 of rtl/external_bus.v *)
    bus: INTEGER;             (* the card bus's data lines: the last byte driven on them *)
    Hz: LONGINT;              (* the clock, EmHost.hz *)
    now*: LONGINT;            (* cycles since reset *)
    profEvery, nextProf: LONGINT;   (* -prof: a sample each profEvery cycles *)
    profFile: Files.File; prof: Files.Rider;
    rom: ARRAY 8000H OF BYTE;
    romBase: INTEGER;         (* where the boot ROM starts: $E000, $C000 or $8000 *)
    romEn, cardReset: BOOLEAN;
    imask: INTEGER;           (* $0441 *)
    wd1793*: BOOLEAN;         (* card 0 is the WD1793 card, not the 82077AA *)
    nextTick: LONGINT;
    nextPace: LONGINT;
    turbo: BOOLEAN;           (* -turbo: never kept to real time *)
    rested: BOOLEAN;          (* the guest reads its input: real time *)
    cpuHz: LONGINT;           (* -cpuclk: the core's clock, 0 the system clock *)
    slow: BOOLEAN;            (* the core on a clock of its own, slower than Hz *)
    cn: LONGINT;              (* with slow, the core's clocks since reset *)
    edge: LONGINT;            (* the system clock's cycle of the core's clock cn *)
    frac, stepQ, stepR: LONGINT;   (* edge's fraction of a cycle, in 1/cpuHz; Hz DIV and MOD cpuHz *)
    ms: INTEGER;              (* milliseconds of this second *)
    talks0: LONGINT;          (* EmADB.talks at its start *)
    sccEnd: LONGINT;          (* the cycle after the SCC's last access *)
    irq, irqDue: BOOLEAN;     (* the IRQ line; to be worked out again *)

  PROCEDURE UseWD1793*;
  BEGIN wd1793 := TRUE; EmDMA.NoFloppy
  END UseWD1793;

  (* -turbo: flat out always, even with a window and the guest at rest *)
  PROCEDURE Turbo*;
  BEGIN turbo := TRUE
  END Turbo;

  (* -cpuclk: the core's clock, at most the system clock's (Reset sets it up) *)
  PROCEDURE SetCpuClock*(hz: LONGINT);
  BEGIN cpuHz := hz
  END SetCpuClock;

  (* The boot ROM is sized to its image, as the Verilog repository's
     tools/romimage.py sizes it: the smallest of 8, 16 or 32K that holds the
     n bytes, at the top of bank 0, the image at its top (the image ends at
     $FFFF), $FF below it. n is at most 32K. *)
  PROCEDURE LoadROM*(VAR src: ARRAY OF BYTE; n: INTEGER);
    VAR i, size: INTEGER;
  BEGIN size := 2000H; WHILE (size < n) & (size < 8000H) DO size := size * 2 END;
    romBase := 10000H - size;
    FOR i := 0 TO size - 1 DO
      IF i < size - n THEN rom[i] := 0FFH ELSE rom[i] := src[i - (size - n)] END
    END
  END LoadROM;

  (* The devices that act on their own: every 64 cycles is often enough. *)
  PROCEDURE Pass(c: INTEGER);
  BEGIN now := now + c;
    IF now >= nextTick THEN
      EmSCC.Tick(now); EmADB.Tick(now); EmBlit.Tick(now); EmDMA.Tick(now); EmTimer.Tick(now); Em82077.Tick(now); EmEth.Tick(now); EmPower.Tick(now); EmRTC.Tick(now); EmSCSI.Tick(now);
      nextTick := now + 64; irqDue := TRUE
    END
  END Pass;

  (* --- the core's clock, with slow --- *)

  (* The next edge of the core's clock: Hz / cpuHz cycles on, the fraction
     carried. *)
  PROCEDURE NextEdge;
  BEGIN INC(cn); edge := edge + stepQ; frac := frac + stepR;
    IF frac >= cpuHz THEN frac := frac - cpuHz; INC(edge) END
  END NextEdge;

  (* The end of a bus cycle that began at the core's clock edge: the first
     edge at or after now, the memory's ready, and at least the next. *)
  PROCEDURE Align;
  BEGIN
    REPEAT NextEdge UNTIL edge >= now;
    IF edge > now THEN Pass(edge - now) END
  END Align;

  (* The core's clocks from edge until the system clock's cycle t:
     the clocks a fill whose memory is ready at t takes, at least 1. *)
  PROCEDURE ClocksTo(t: LONGINT): INTEGER;
    VAR e, f: LONGINT; k: INTEGER;
  BEGIN e := edge; f := frac; k := 0;
    REPEAT INC(k); e := e + stepQ; f := f + stepR;
      IF f >= cpuHz THEN f := f - cpuHz; INC(e) END
    UNTIL e >= t;
    RETURN k
  END ClocksTo;

  PROCEDURE IO(a: INTEGER): BOOLEAN;
  BEGIN RETURN (a >= 200H) & (a <= 0FFFH)
  END IO;

  (* the cards' IRQ# *)
  PROCEDURE CardIrq(): BOOLEAN;
  BEGIN RETURN ~wd1793 & Em82077.Irq() OR EmSCSI.Irq() OR EmEth.Irq() OR EmRTC.Irq()
  END CardIrq;

  PROCEDURE ResetCards;
  BEGIN IF wd1793 THEN EmFDC.Reset ELSE Em82077.Reset END; EmSCSI.ResetChip
  END ResetCards;

  PROCEDURE CardRead(a: INTEGER): INTEGER;
    VAR slot, r: INTEGER;
  BEGIN slot := AND(a DIV 16, 7); r := 0FFH;
    IF (slot = 7) & ~EmRTC.present THEN r := bus END;
    IF slot = 0 THEN
      IF wd1793 THEN r := EmFDC.GetByte(a) ELSIF AND(a, 8) = 0 THEN r := Em82077.Read(a, now) END
    ELSIF (slot = 1) & ~wd1793 THEN r := Em82077.DackRead(FALSE, now)
    ELSIF (slot = 3) & (AND(a, 8) = 0) THEN EmSCSI.Tick(now); r := EmSCSI.Read(a)
    ELSIF slot = 4 THEN EmSCSI.Tick(now); r := EmSCSI.DackRead(FALSE)
    ELSIF slot = 5 THEN r := EmEth.Read(a, now)
    ELSIF (slot = 7) & EmRTC.present THEN r := EmRTC.Read(a, now)
    END;
    bus := r;
    RETURN r
  END CardRead;

  PROCEDURE CardWrite(a, v: INTEGER);
    VAR slot: INTEGER;
  BEGIN slot := AND(a DIV 16, 7); bus := AND(v, 0FFH);
    IF slot = 0 THEN
      IF wd1793 THEN EmFDC.SetByte(a, v) ELSIF AND(a, 8) = 0 THEN Em82077.Write(a, v, now) END
    ELSIF (slot = 1) & ~wd1793 THEN Em82077.DackWrite(v, FALSE, now)
    ELSIF (slot = 3) & (AND(a, 8) = 0) THEN EmSCSI.Tick(now); EmSCSI.Write(a, v)
    ELSIF slot = 4 THEN EmSCSI.Tick(now); EmSCSI.DackWrite(v, FALSE)
    ELSIF slot = 5 THEN EmEth.Write(a, v, now)
    ELSIF slot = 7 THEN EmRTC.Write(a, v, now)
    END
  END CardWrite;

  (* $0440: which sources are asking for the IRQ, before the mask *)
  PROCEDURE IStat(): INTEGER;
    VAR v: INTEGER;
  BEGIN v := 0;
    IF EmTimer.Irq() THEN v := v + 1 END;
    IF EmDMA.IrqCh(0) THEN v := v + 2 END;
    IF EmDMA.IrqCh(1) THEN v := v + 4 END;
    IF EmDMA.IrqCh(2) THEN v := v + 40H END;
    IF CardIrq() THEN v := v + 8 END;
    IF EmSCC.Irq() THEN v := v + 10H END;
    IF EmPower.Irq() THEN v := v + 20H END;
    RETURN v
  END IStat;

  PROCEDURE IntRead(a: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN r := 0;
    IF AND(a, 10H) # 0 THEN r := EmTimer.Read(a, now)
    ELSIF AND(a, 0FH) = 0 THEN r := IStat()
    ELSIF AND(a, 0FH) = 1 THEN r := imask
    END;
    RETURN r
  END IntRead;

  (* the emulated SCC: slot 2 of the external bus, and its mirrors *)
  PROCEDURE SCC(a: INTEGER): BOOLEAN;
  BEGIN RETURN (a >= 800H) & (AND(a DIV 16, 7) = 2)
  END SCC;

  (* The emulated SCC answers in 2 cycles, and is not ready again until
     a cycle after: an access straight after another takes 3. *)
  PROCEDURE SCCCycles(): INTEGER;
    VAR c: INTEGER;
  BEGIN IF now = sccEnd THEN c := 3 ELSE c := 2 END; sccEnd := now + c; RETURN c
  END SCCCycles;

  PROCEDURE IORead(a: INTEGER): INTEGER;
    VAR r, slot: INTEGER;
  BEGIN
    IF SCC(a) THEN slot := SCCCycles(); r := EmSCC.Read(a, now + slot); Pass(slot)
    ELSIF a >= 800H THEN
      IF cardReset THEN Pass(2); r := 0FFH                  (* RES#: the bridge ends the access at once *)
      ELSE Pass(extCost); r := CardRead(a)
      END
    ELSE Pass(2); slot := a DIV 40H;
      IF slot = 10 THEN r := EmADB.Read(a, now)
      ELSIF slot = 11 THEN Pass(EmSD.Wait(a, now)); r := EmSD.Read(a, now)
      ELSIF slot = 16 THEN r := EmDMA.Read(a, now)
      ELSIF slot = 17 THEN r := IntRead(a)
      ELSIF slot = 18 THEN r := EmPower.Read(a, now)
      ELSIF slot = 12 THEN IF romEn THEN r := 1 ELSE r := 0 END
      ELSIF slot = 13 THEN IF CardIrq() THEN r := 1 ELSE r := 0 END
      ELSIF slot = 14 THEN r := EmVideo.text + 80H   (* 1024 x 768 *)
      ELSIF slot = 15 THEN r := EmBlit.Read(a, now)
      ELSE r := 0FFH                                  (* palette, unclaimed *)
      END
    END;
    RETURN r
  END IORead;

  PROCEDURE IOWrite(a, v: INTEGER);
    VAR slot: INTEGER;
  BEGIN
    IF SCC(a) THEN slot := SCCCycles(); EmSCC.Write(a, v, now + slot); Pass(slot)
    ELSIF a >= 800H THEN
      IF cardReset THEN Pass(2) ELSE Pass(extCost); CardWrite(a, v) END
    ELSE Pass(2); slot := a DIV 40H;
      IF slot = 9 THEN
        IF AND(a, 3) # 3 THEN EmVideo.SetPalette(AND(a DIV 4, 0FH), AND(a, 3), v) END
      ELSIF slot = 10 THEN EmADB.Write(a, v, now)
      ELSIF slot = 11 THEN Pass(EmSD.Wait(a, now)); EmSD.Write(a, v, now)
      ELSIF slot = 12 THEN romEn := ODD(v)
      ELSIF slot = 13 THEN
        IF ODD(v) & ~cardReset THEN ResetCards END;
        cardReset := ODD(v)
      ELSIF slot = 14 THEN IF AND(a, 3FH) = 0 THEN EmVideo.SetText(ODD(v)) END   (* $0380 only *)
      ELSIF slot = 15 THEN EmBlit.Write(a, v, now)
      ELSIF slot = 16 THEN EmDMA.Write(a, v, now)
      ELSIF slot = 18 THEN EmPower.Write(a, v, now)
      ELSIF slot = 17 THEN
        IF AND(a, 10H) # 0 THEN EmTimer.Write(a, v, now)
        ELSIF AND(a, 0FH) = 1 THEN imask := AND(v, 0FFH)
        END
      END
    END
  END IOWrite;

  (* --- the core's bus --- *)

  PROCEDURE Read*(a: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF a >= EmSDRAM.size THEN Pass(2); r := 0FFH
    ELSIF IO(a) THEN r := IORead(a); irqDue := TRUE
    ELSIF romEn & (a >= romBase) & (a <= 0FFFFH) THEN Pass(2); r := rom[a - romBase]
    ELSE Pass(EmSDRAM.ReadCost(a, now)); r := EmSDRAM.Peek(a)
    END;
    IF slow THEN Align END;
    RETURN r
  END Read;

  PROCEDURE Write*(a, v: INTEGER);
  BEGIN
    IF a >= EmSDRAM.size THEN Pass(2)
    ELSIF IO(a) THEN IOWrite(a, v); irqDue := TRUE
    ELSE Pass(EmSDRAM.WriteCost(a, now)); EmSDRAM.Poke(a, v)
    END;
    IF slow THEN Align END
  END Write;

  (* A fill of the core's instruction queue, its bus cycle from cycle at:
     the word of the SDRAM or the boot ROM (from a to its end), a byte of
     anything else ($FF: a fill of the I/O block, which no code runs from,
     reads nothing), and the cycles to its ready. With slow, at and the
     cycles are the core's clocks; the fill starts now, at edge. *)
  PROCEDURE Fetch*(a: INTEGER; at: LONGINT; VAR w: ARRAY OF INTEGER; VAR n: INTEGER): INTEGER;
    VAR c, i: INTEGER;
  BEGIN
    IF slow THEN at := now END;
    IF (a >= EmSDRAM.size) OR IO(a) THEN n := 1; w[0] := 0FFH;
      c := 2; IF IO(a) & SCC(a) & (at = sccEnd) THEN c := 3 ELSIF IO(a) & (a >= 800H) & ~cardReset THEN c := extCost END
    ELSE n := 4 - a MOD 4;
      IF romEn & (a >= romBase) & (a <= 0FFFFH) THEN c := 2;
        FOR i := 0 TO n - 1 DO w[i] := rom[a + i - romBase] END
      ELSE c := EmSDRAM.FetchCost(a, at);
        FOR i := 0 TO n - 1 DO w[i] := EmSDRAM.Peek(a + i) END
      END
    END;
    IF slow THEN c := ClocksTo(at + c) END;
    RETURN c
  END Fetch;

  (* cycles of the core without a bus cycle of its own: its clocks *)
  PROCEDURE Wait*(c: INTEGER);
  BEGIN
    IF slow THEN
      WHILE c > 0 DO NextEdge; DEC(c) END;
      Pass(edge - now)
    ELSE Pass(c)
    END
  END Wait;

  (* the core's time: the system clock's cycles, or with slow its own clocks *)
  PROCEDURE Clock*(): LONGINT;
    VAR t: LONGINT;
  BEGIN IF slow THEN t := cn ELSE t := now END;
    RETURN t
  END Clock;

  (* The IRQ line: the sources change as the devices are given the time
     and as they are accessed, so it is worked out again only then. *)
  PROCEDURE Irq*(): BOOLEAN;
  BEGIN
    IF irqDue THEN irq := AND(IStat(), imask) # 0; irqDue := FALSE END;
    RETURN irq
  END Irq;

  (* --- without taking time, for loading and the trace --- *)

  PROCEDURE Peek*(a: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF IO(a) THEN r := 0FFH
    ELSIF romEn & (a >= romBase) & (a <= 0FFFFH) THEN r := rom[a - romBase]
    ELSE r := EmSDRAM.Peek(a)
    END;
    RETURN r
  END Peek;

  PROCEDURE Poke*(a, v: INTEGER);
  BEGIN IF ~IO(a) THEN EmSDRAM.Poke(a, v) END
  END Poke;

  (* --- running --- *)

  PROCEDURE Reset*;
  BEGIN now := 0; nextTick := 0; sccEnd := -1; bus := 0FFH; irq := FALSE; irqDue := TRUE; romEn := TRUE; cardReset := FALSE; Hz := EmHost.hz;
    slow := (cpuHz > 0) & (cpuHz < Hz); cn := 0; edge := 0; frac := 0;
    IF slow THEN stepQ := Hz DIV cpuHz; stepR := Hz MOD cpuHz END;
    extCost := 3 * ((Hz + 8399999) DIV 8400000) + (Hz + 25199999) DIV 25200000 + 4;
    EmSDRAM.Reset; EmBlit.Reset; EmSD.Reset; EmADB.Reset; EmSCC.Reset; EmVideo.SetText(FALSE);
    ResetCards; EmSCSI.Reset; EmEth.Reset; EmPower.SetClock(Hz); EmPower.Reset; EmRTC.Reset; EmDMA.Reset; EmTimer.Reset; imask := 0FFH;
    EmCore.SetBus(Read, Write, Fetch, Wait, Clock, Irq);
    EmCore.Reset
  END Reset;

  (* Until the core stops: STP, or a fetch from 00:0000. Flat out; but
     with a window (EmHost.pace), once the guest reads its keyboard and
     mouse (Polls ADB transactions in a second, as OS16's InputManager
     makes and a boot does not), at the board's speed from then on, each millisecond of the
     clock in step with the host's, so that its times (a key's repeat, a
     double click) are the person's, busy or not. With -turbo (Turbo),
     flat out all the time. *)
  PROCEDURE Word(v: INTEGER);
  BEGIN Files.WriteByte(prof, v MOD 100H); Files.WriteByte(prof, v DIV 100H MOD 100H);
    Files.WriteByte(prof, v DIV 10000H MOD 100H); Files.WriteByte(prof, v DIV 1000000H MOD 100H)
  END Word;

  (* -prof name every: each every cycles, the core's PC (PBR:PC) and the
     time (in thousands of cycles) to name, as two little-endian words *)
  PROCEDURE Profile*(name: ARRAY OF CHAR; every: INTEGER): BOOLEAN;
  BEGIN profFile := Files.New(name);
    IF (profFile # NIL) & (every > 0) THEN Files.Set(prof, profFile, 0); profEvery := every; nextProf := 0 END
  RETURN profFile # NIL
  END Profile;

  PROCEDURE Run*;
  BEGIN
    nextPace := now; rested := FALSE; ms := 0; talks0 := EmADB.talks;
    WHILE ~EmCore.stopped & ~EmPower.off DO EmCore.Step(now);
      IF (profEvery > 0) & (now >= nextProf) THEN
        Word(EmCore.PBR * 10000H + EmCore.PC); Word(now DIV 1000); nextProf := now + profEvery
      END;
      IF (EmHost.pace # 0) & ~turbo & (now >= nextPace) THEN
        IF rested THEN EmHost.Pace(now, Hz)
        ELSE
          INC(ms);
          IF ms = 1000 THEN rested := EmADB.talks - talks0 >= Polls; ms := 0; talks0 := EmADB.talks END
        END;
        nextPace := now + Hz DIV 1000
      END
    END;
    IF profEvery > 0 THEN Files.Register(profFile); profEvery := 0 END;
    EmHost.DrainAll
  END Run;

BEGIN profEvery := 0; romEn := TRUE; romBase := 0E000H; now := 0; wd1793 := FALSE; turbo := FALSE; cpuHz := 0; slow := FALSE
END EmSoC.
