MODULE EmMem; (* The memory and the devices in it, for the three machines
   em16 emulates.

   The default machine has 1 MB of RAM, repeated through the 16 MB, with
   a 6551 at $C000, a 6522 at $C020 (0: none), the floppy controller at
   $0800 and the 640 x 480 framebuffer at $70_0000.

   The L28 (the R65C19) has its ports and USART in page zero, the LCD at
   $0600, the floppy controller at $0640, and the bank select registers
   map each 8K window of the address space to ES0 RAM or a flash chip.

   The Tang Nano 20K SoC (-fpga) is EmSoC, with its own processor
   (EmCore); here are only the accesses of the loaders and the trace,
   which take no time and leave the devices alone. *)

  IMPORT EmHost, EmUART, EmVIA, EmFDC, EmL28, EmVideo, EmLCD, EmSoC;

  CONST
    maxRam = 800000H;

  VAR
    ram*: ARRAY maxRam OF BYTE;
    memMask, ramSize*: INTEGER;
    uartBase, fdcBase, viaBase: INTEGER;
    l28*, flashInitialized, fpga*: BOOLEAN;

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
    ELSIF (ea >= fdcBase) & (ea <= fdcBase + 0FH) THEN r := EmFDC.GetByte(ea)
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
    ELSIF (ea >= fdcBase) & (ea <= fdcBase + 0FH) THEN EmFDC.SetByte(ea, data)
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
  l28 := FALSE; flashInitialized := FALSE; fpga := FALSE
END EmMem.
