MODULE EmSoC; (* The Tang Nano 20K SoC of ../../Verilog65C816/fpga: its
   memory map, its devices and its time, around EmCore.

   $00_0000-$7F_FFFF  SDRAM, 8 MB, through the cache (EmSDRAM); except
     $00_0200-$00_0FFF  the I/O block, a device per 64 byte slot:
       $0200 unclaimed: $FF       $0300 system control: bit 0 boot ROM
       $0240 palette, write only  $0340 external bus control
       $0280 ADB host (EmADB)     $0380 video control: bit 0 text
       $02C0 SD card: $FF         $03C0 blitter (EmBlit)
       $0400 the DMA engine (EmDMA), mirrored at $0420
       $0440-$07FF unclaimed: $FF
       $0800-$0FFF the external bus: 8 slots of 16 registers, mirrored
                   every 128 bytes, as the carrier's 74HCT138 decodes them:
                   slot 0 the 82077AA floppy controller (Em82077), or with
                   -wd1793 the WD1793 card (EmFDC); slot 1 the 82077AA's
                   /DACK; slot 3 the SCSI half of its Z85C80 (EmSCSI);
                   slot 4 the 53C80's /DACK; 5-7 empty: $FF. A CPU access
                   to a /DACK slot is pseudo-DMA, a byte without TC.
         $0820-$082F the emulated Z85C30 SCC (EmSCC), the serial port,
                   which answers in place of slot 2 and takes 3 cycles
     $00_E000-$00_FFFF  the 8K boot ROM while system control bit 0 is set;
                   writes there always go to the SDRAM
   $80_0000-$FF_FFFF  unmapped: $FF

   Time is the SoC's 25.2 MHz clock. Each bus cycle of the core takes the
   cycles soc.v gives it: the boot ROM, the I/O block and unmapped
   addresses 2, the SDRAM what the cache takes, the external bus 14 (its
   Intel cycle on the 8.4 MHz timing, as the CPU sees it). The devices are
   given the time as it passes. The IRQ line is the SCC's ORed with the
   cards' IRQ# (the 82077AA's INT and the 53C80's IRQ), which bit 0 of
   $0340 reads, and with the DMA engine's; setting bit 0 of $0340 resets
   the cards' chips (RES#). *)

  IMPORT EmHost, EmCore, EmSDRAM, EmSCC, EmADB, EmBlit, EmFDC, Em82077, EmSCSI, EmDMA, EmVideo;

  CONST
    extCost = 14;             (* an external bus cycle *)

  VAR
    now*: LONGINT;            (* cycles since reset *)
    rom: ARRAY 2000H OF BYTE;
    romEn, cardReset: BOOLEAN;
    wd1793*: BOOLEAN;         (* card 0 is the WD1793 card, not the 82077AA *)
    nextTick: LONGINT;

  PROCEDURE UseWD1793*;
  BEGIN wd1793 := TRUE; EmDMA.NoFloppy
  END UseWD1793;

  PROCEDURE LoadROM*(VAR src: ARRAY OF BYTE; n: INTEGER);
    VAR i: INTEGER;
  BEGIN FOR i := 0 TO 1FFFH DO IF i < n THEN rom[i] := src[i] ELSE rom[i] := 0FFH END END
  END LoadROM;

  (* The devices that act on their own: every 64 cycles is often enough. *)
  PROCEDURE Pass(c: INTEGER);
  BEGIN now := now + c;
    IF now >= nextTick THEN
      EmSCC.Tick(now); EmADB.Tick(now); EmBlit.Tick(now); EmDMA.Tick(now); Em82077.Tick(now);
      nextTick := now + 64
    END
  END Pass;

  PROCEDURE IO(a: INTEGER): BOOLEAN;
  BEGIN RETURN (a >= 200H) & (a <= 0FFFH)
  END IO;

  (* the cards' IRQ# *)
  PROCEDURE CardIrq(): BOOLEAN;
  BEGIN RETURN ~wd1793 & Em82077.Irq() OR EmSCSI.Irq()
  END CardIrq;

  PROCEDURE ResetCards;
  BEGIN IF wd1793 THEN EmFDC.Reset ELSE Em82077.Reset END; EmSCSI.ResetChip
  END ResetCards;

  PROCEDURE CardRead(a: INTEGER): INTEGER;
    VAR slot, r: INTEGER;
  BEGIN slot := AND(a DIV 16, 7); r := 0FFH;
    IF slot = 0 THEN
      IF wd1793 THEN r := EmFDC.GetByte(a) ELSIF AND(a, 8) = 0 THEN r := Em82077.Read(a, now) END
    ELSIF (slot = 1) & ~wd1793 THEN r := Em82077.DackRead(FALSE, now)
    ELSIF (slot = 3) & (AND(a, 8) = 0) THEN r := EmSCSI.Read(a)
    ELSIF slot = 4 THEN r := EmSCSI.DackRead(FALSE)
    END;
    RETURN r
  END CardRead;

  PROCEDURE CardWrite(a, v: INTEGER);
    VAR slot: INTEGER;
  BEGIN slot := AND(a DIV 16, 7);
    IF slot = 0 THEN
      IF wd1793 THEN EmFDC.SetByte(a, v) ELSIF AND(a, 8) = 0 THEN Em82077.Write(a, v, now) END
    ELSIF (slot = 1) & ~wd1793 THEN Em82077.DackWrite(v, FALSE, now)
    ELSIF (slot = 3) & (AND(a, 8) = 0) THEN EmSCSI.Write(a, v)
    ELSIF slot = 4 THEN EmSCSI.DackWrite(v, FALSE)
    END
  END CardWrite;

  (* the emulated SCC: slot 2 of the external bus, and its mirrors *)
  PROCEDURE SCC(a: INTEGER): BOOLEAN;
  BEGIN RETURN (a >= 800H) & (AND(a DIV 16, 7) = 2)
  END SCC;

  PROCEDURE IORead(a: INTEGER): INTEGER;
    VAR r, slot: INTEGER;
  BEGIN
    IF SCC(a) THEN Pass(3); r := EmSCC.Read(a, now)
    ELSIF a >= 800H THEN
      Pass(extCost); r := CardRead(a)
    ELSE Pass(2); slot := a DIV 40H;
      IF slot = 10 THEN r := EmADB.Read(a, now)
      ELSIF slot = 16 THEN r := EmDMA.Read(a, now)
      ELSIF slot = 12 THEN IF romEn THEN r := 1 ELSE r := 0 END
      ELSIF slot = 13 THEN IF CardIrq() THEN r := 1 ELSE r := 0 END
      ELSIF slot = 14 THEN r := EmVideo.text
      ELSIF slot = 15 THEN r := EmBlit.Read(a, now)
      ELSE r := 0FFH                                  (* palette, SD card, unclaimed *)
      END
    END;
    RETURN r
  END IORead;

  PROCEDURE IOWrite(a, v: INTEGER);
    VAR slot: INTEGER;
  BEGIN
    IF SCC(a) THEN Pass(3); EmSCC.Write(a, v, now)
    ELSIF a >= 800H THEN
      Pass(extCost); CardWrite(a, v)
    ELSE Pass(2); slot := a DIV 40H;
      IF slot = 9 THEN
        IF AND(a, 3) # 3 THEN EmVideo.SetPalette(AND(a DIV 4, 0FH), AND(a, 3), v) END
      ELSIF slot = 10 THEN EmADB.Write(a, v, now)
      ELSIF slot = 12 THEN romEn := ODD(v)
      ELSIF slot = 13 THEN
        IF ODD(v) & ~cardReset THEN ResetCards END;
        cardReset := ODD(v)
      ELSIF slot = 14 THEN EmVideo.SetText(ODD(v))
      ELSIF slot = 15 THEN EmBlit.Write(a, v, now)
      ELSIF slot = 16 THEN EmDMA.Write(a, v, now)
      END
    END
  END IOWrite;

  (* --- the core's bus --- *)

  PROCEDURE Read*(a: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF a >= EmSDRAM.size THEN Pass(2); r := 0FFH
    ELSIF IO(a) THEN r := IORead(a)
    ELSIF romEn & (a >= 0E000H) & (a <= 0FFFFH) THEN Pass(2); r := rom[a - 0E000H]
    ELSE Pass(EmSDRAM.ReadCost(a, now)); r := EmSDRAM.Peek(a)
    END;
    RETURN r
  END Read;

  PROCEDURE Write*(a, v: INTEGER);
  BEGIN
    IF a >= EmSDRAM.size THEN Pass(2)
    ELSIF IO(a) THEN IOWrite(a, v)
    ELSE Pass(EmSDRAM.WriteCost(a, now)); EmSDRAM.Poke(a, v)
    END
  END Write;

  (* an internal cycle *)
  PROCEDURE Idle*;
  BEGIN Pass(1)
  END Idle;

  PROCEDURE Irq*(): BOOLEAN;
  BEGIN RETURN EmSCC.Irq() OR CardIrq() OR EmDMA.Irq()
  END Irq;

  (* --- without taking time, for loading and the trace --- *)

  PROCEDURE Peek*(a: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF IO(a) THEN r := 0FFH
    ELSIF romEn & (a >= 0E000H) & (a <= 0FFFFH) THEN r := rom[a - 0E000H]
    ELSE r := EmSDRAM.Peek(a)
    END;
    RETURN r
  END Peek;

  PROCEDURE Poke*(a, v: INTEGER);
  BEGIN IF ~IO(a) THEN EmSDRAM.Poke(a, v) END
  END Poke;

  (* --- running --- *)

  PROCEDURE Reset*;
  BEGIN now := 0; nextTick := 0; romEn := TRUE; cardReset := FALSE;
    EmSDRAM.Reset; EmBlit.Reset; EmADB.Reset; EmSCC.Reset; EmVideo.SetText(FALSE);
    ResetCards; EmSCSI.Reset; EmDMA.Reset;
    EmCore.SetBus(Read, Peek, Write, Idle, Irq);
    EmCore.Reset
  END Reset;

  (* Until the core stops: STP, or a fetch from 00:0000. *)
  PROCEDURE Run*;
  BEGIN
    WHILE ~EmCore.stopped DO EmCore.Step(now) END;
    EmHost.DrainAll
  END Run;

BEGIN romEn := TRUE; now := 0; wd1793 := FALSE
END EmSoC.
