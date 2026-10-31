MODULE EmMem; (* The memory and the devices in it, for the three machines
   em16 emulates.

   The default machine has 1 MB of RAM, repeated through the 16 MB, with
   a 6551 at $C000, a 6522 at $C020 (0: none), the carrier board's disk
   controllers at the SoC's addresses, the 82077AA floppy controller at
   $0800 (or with -wd1793 the WD1793) and the 53C80 SCSI controller at
   $0830, and the 1024 x 768 framebuffer at $70_0000. The 82077AA's time
   is the processor's cycles (clock), three of the SoC's 25.2 MHz to
   each, as if the processor ran at 8.4 MHz.

   The L28 (the R65C19) has its ports and USART in page zero, the LCD at
   $0600, the WD1793 floppy controller at $0640, and the bank select
   registers map each 8K window of the address space to ES0 RAM or a
   flash chip.

   The Tang Nano 20K SoC (-fpga) is EmSoC, with its own processor
   (EmCore); here are only the accesses of the loaders and the trace,
   which take no time and leave the devices alone. *)

  IMPORT EmHost, EmUART, EmVIA, EmFDC, Em82077, EmSCSI, EmL28, EmVideo, EmLCD, EmSoC;

  CONST
    maxRam = 800000H;
    scsiBase = 830H;
    socPerCycle = 3;   (* the SoC's cycles in one of the default machine's *)

  VAR
    ram*: ARRAY maxRam OF BYTE;
    memMask, ramSize*: INTEGER;
    uartBase, fdcBase, viaBase: INTEGER;
    l28*, flashInitialized, fpga*: BOOLEAN;
    clock: PROCEDURE (): LONGINT;   (* the processor's cycles, for the 82077AA *)

  PROCEDURE NoClock(): LONGINT;
  BEGIN RETURN 0
  END NoClock;

  PROCEDURE SetClock*(c: PROCEDURE (): LONGINT);
  BEGIN clock := c
  END SetClock;

  (* the 82077AA, not the WD1793, at fdcBase *)
  PROCEDURE Is82077(): BOOLEAN;
  BEGIN RETURN ~l28 & ~EmSoC.wd1793
  END Is82077;

  (* the 82077AA's time, after it has been given it *)
  PROCEDURE FdcNow(): LONGINT;
    VAR now: LONGINT;
  BEGIN now := clock() * socPerCycle; Em82077.Tick(now); RETURN now
  END FdcNow;

  PROCEDURE SetMemory*(mask, size: INTEGER);
  BEGIN memMask := mask; ramSize := size
  END SetMemory;

  PROCEDURE SetUartBase*(a: INTEGER);
  BEGIN uartBase := a
  END SetUartBase;

  PROCEDURE SetFdcBase*(a: INTEGER);
  BEGIN fdcBase := a
  END SetFdcBase;

  PROCEDURE SetViaBase*(a: INTEGER);
  BEGIN viaBase := a
  END SetViaBase;

  PROCEDURE EnableL28*;
  BEGIN l28 := TRUE
  END EnableL28;

  PROCEDURE EnableFPGA*;
  BEGIN fpga := TRUE
  END EnableFPGA;

  PROCEDURE LoadBootROM*(VAR src: ARRAY OF BYTE; len: INTEGER);
  BEGIN EmSoC.LoadROM(src, len)
  END LoadBootROM;

  (* ES3 flash starts as the ROM image loaded into RAM. *)
  PROCEDURE InitFlash*;
  BEGIN
    IF l28 THEN
      IF ramSize < 20000H THEN EmL28.InitES3(ram, ramSize) ELSE EmL28.InitES3(ram, 20000H) END;
      flashInitialized := TRUE
    END
  END InitFlash;

  (* --- the L28's banked windows --- *)

  PROCEDURE Phys(bsr, ea: INTEGER): INTEGER;
  BEGIN RETURN AND(bsr, 20H) * 1000H + AND(bsr, 0FH) * 2000H + AND(ea, 1FFFH)
  END Phys;

  (* --- access --- *)

  PROCEDURE GetByte*(ea: INTEGER): INTEGER;
    VAR r, b: INTEGER; done: BOOLEAN;
  BEGIN done := TRUE;
    IF fpga THEN r := EmSoC.Peek(ea)
    ELSIF (ea >= EmVideo.base) & (ea < EmVideo.base + EmVideo.size) THEN r := EmVideo.GetByte(ea - EmVideo.base)
    ELSIF l28 & (ea <= 0BH) THEN r := EmL28.GetPort(ea)
    ELSIF l28 & (ea >= 14H) & (ea <= 17H) THEN r := EmL28.GetTimerB(ea - 14H)
    ELSIF l28 & (ea >= 18H) & (ea <= 1FH) THEN r := EmL28.GetBSR(ea - 18H)
    ELSIF l28 & (ea >= 38H) & (ea <= 3FH) THEN r := EmL28.GetByte(ea - 38H)
    ELSIF l28 & (ea >= EmLCD.base) & (ea <= EmLCD.base + 1) THEN r := EmLCD.GetByte(ea - EmLCD.base)
    ELSIF (ea >= uartBase) & (ea <= uartBase + 0FH) THEN r := EmUART.GetByte(ea - uartBase)
    ELSIF (ea >= fdcBase) & (ea <= fdcBase + 0FH) THEN
      IF ~Is82077() THEN r := EmFDC.GetByte(ea) ELSIF AND(ea, 8) = 0 THEN r := Em82077.Read(ea, FdcNow()) ELSE r := 0FFH END
    ELSIF ~l28 & (ea >= scsiBase) & (ea <= scsiBase + 7) THEN r := EmSCSI.Read(ea)
    ELSIF (viaBase # 0) & (ea >= viaBase) & (ea <= viaBase + 0FH) THEN r := EmVIA.GetByte(ea)
    ELSE done := FALSE;
      IF l28 & (ea >= 800H) THEN b := EmL28.GetBSR(ea DIV 2000H); done := TRUE;
        IF AND(b, 10H) = 0 THEN r := EmL28.ReadES0(Phys(b, ea))
        ELSIF flashInitialized & (AND(b, 40H) = 0) THEN r := EmL28.ReadES2(Phys(b, ea))
        ELSIF flashInitialized & (AND(b, 80H) = 0) THEN r := EmL28.ReadES3(Phys(b, ea))
        ELSE done := FALSE
        END
      END;
      IF ~done THEN r := ram[AND(ea, memMask)] END
    END;
    RETURN r
  END GetByte;

  PROCEDURE GetWord*(ea: INTEGER): INTEGER;
  BEGIN RETURN GetByte(ea) + GetByte(ea + 1) * 256
  END GetWord;

  PROCEDURE GetAddr*(ea: INTEGER): INTEGER;
  BEGIN RETURN GetWord(ea) + GetByte(ea + 2) * 10000H
  END GetAddr;

  (* A byte as GetByte reads it, but leaving the 82077AA and the 53C80 as
     they are (a FIFO byte not taken, an interrupt not cleared): for the
     trace's top of the stack, which is $0800 when the stack is empty. *)
  PROCEDURE TraceByte*(ea: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF ~fpga & Is82077() & (ea >= fdcBase) & (ea <= fdcBase + 0FH) THEN
      IF AND(ea, 8) = 0 THEN r := Em82077.Peek(ea) ELSE r := 0FFH END
    ELSIF ~fpga & ~l28 & (ea >= scsiBase) & (ea <= scsiBase + 7) THEN r := EmSCSI.Peek(ea)
    ELSE r := GetByte(ea)
    END;
    RETURN r
  END TraceByte;

  (* A byte of RAM, without touching a device: for the trace. *)
  PROCEDURE Peek*(ea: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN IF fpga THEN r := EmSoC.Peek(ea) ELSE r := ram[AND(ea, memMask)] END; RETURN r
  END Peek;

  PROCEDURE SetByte*(ea, data: INTEGER);
    VAR b: INTEGER; done: BOOLEAN;
  BEGIN data := AND(data, 0FFH);
    IF fpga THEN EmSoC.Poke(ea, data)
    ELSIF (ea >= EmVideo.base) & (ea < EmVideo.base + EmVideo.size) THEN EmVideo.SetByte(ea - EmVideo.base, data)
    ELSIF l28 & (ea <= 0BH) THEN EmL28.SetPort(ea, data)
    ELSIF l28 & (ea >= 14H) & (ea <= 17H) THEN EmL28.SetTimerB(ea - 14H, data)
    ELSIF l28 & (ea >= 18H) & (ea <= 1FH) THEN EmL28.SetBSR(ea - 18H, data)
    ELSIF l28 & (ea >= 38H) & (ea <= 3FH) THEN EmL28.SetByte(ea - 38H, data)
    ELSIF l28 & (ea >= EmLCD.base) & (ea <= EmLCD.base + 1) THEN EmLCD.SetByte(ea - EmLCD.base, data)
    ELSIF (ea >= uartBase) & (ea <= uartBase + 0FH) THEN EmUART.SetByte(ea - uartBase, data)
    ELSIF (ea >= fdcBase) & (ea <= fdcBase + 0FH) THEN
      IF ~Is82077() THEN EmFDC.SetByte(ea, data) ELSIF AND(ea, 8) = 0 THEN Em82077.Write(ea, data, FdcNow()) END
    ELSIF ~l28 & (ea >= scsiBase) & (ea <= scsiBase + 7) THEN EmSCSI.Write(ea, data)
    ELSIF (viaBase # 0) & (ea >= viaBase) & (ea <= viaBase + 0FH) THEN EmVIA.SetByte(ea, data)
    ELSE done := FALSE;
      IF l28 & (ea >= 800H) THEN b := EmL28.GetBSR(ea DIV 2000H); done := TRUE;
        IF AND(b, 10H) = 0 THEN EmL28.WriteES0(Phys(b, ea), data)
        ELSIF flashInitialized & (AND(b, 40H) = 0) THEN EmL28.WriteES2(Phys(b, ea), data)
        ELSIF flashInitialized & (AND(b, 80H) = 0) THEN EmL28.WriteES3(Phys(b, ea), data)
        ELSE done := FALSE
        END
      END;
      IF ~done & (AND(ea, memMask) < ramSize) THEN ram[AND(ea, memMask)] := data END
    END
  END SetByte;

  PROCEDURE SetWord*(ea, data: INTEGER);
  BEGIN SetByte(ea, AND(data, 0FFH)); SetByte(ea + 1, AND(data DIV 256, 0FFH))
  END SetWord;

BEGIN
  memMask := 0FFFFFH; ramSize := 100000H;
  uartBase := 0C000H; fdcBase := 800H; viaBase := 0C020H;
  l28 := FALSE; flashInitialized := FALSE; fpga := FALSE; clock := NoClock
END EmMem.
