//==============================================================================
//                                          .ooooo.     .o      .ooo   
//                                         d88'   `8. o888    .88'     
//  .ooooo.  ooo. .oo.  .oo.   oooo  oooo  Y88..  .8'  888   d88'      
// d88' `88b `888P"Y88bP"Y88b  `888  `888   `88888b.   888  d888P"Ybo. 
// 888ooo888  888   888   888   888   888  .8'  ``88b  888  Y88[   ]88 
// 888    .o  888   888   888   888   888  `8.   .88P  888  `Y88   88P 
// `Y8bod8P' o888o o888o o888o  `V88V"V8P'  `boood8'  o888o  `88bod8'  
//                                                                    
// A Portable C++ WDC 65C816 Emulator  
//------------------------------------------------------------------------------
// Copyright (C),2016 Andrew John Jacobs
// All rights reserved.
//
// This work is made available under the terms of the Creative Commons
// Attribution-NonCommercial-ShareAlike 4.0 International license. Open the
// following URL to see the details.
//
// http://creativecommons.org/licenses/by-nc-sa/4.0/
//------------------------------------------------------------------------------

#ifndef MEM816_H
#define MEM816_H

#include "wdc816.h"
#include "UART_6551.h"
#include "L28_MCU.h"
#include "R6501.h"
#include "WD1793.h"
#include "VIA_6522.h"

#include "Video.h"
#include "LCD_ST7586S.h"

// The mem816 class defines a set of standard methods for defining and accessing
// the emulated memory area.

class mem816 :
  public wdc816
{
public:
  // Define the memory areas and sizes
  static void setMemory (Addr memMask, Addr ramSize, const Byte *pROM);
  static void setMemory (Addr memMask, Addr ramSize, Byte *pRAM, const Byte *pROM);

  // Configure UART base address (default $C000, L28 uses $0000)
  static void setUartBase(Addr base) { uartBase = base; }

  // Configure FDC base address (default $C010, L28 uses $E000)
  static void setFdcBase(Addr base) { fdcBase = base; }

  // Configure VIA base address (default $C020, 0 = disabled)
  static void setViaBase(Addr base) { viaBase = base; }

  // Enable L28 native USART at $0038-$003F
  static void enableL28MCU() { l28MCUEnabled = true; }

  // Fetch a byte from RAM/ROM without triggering I/O side effects (for trace display)
  INLINE static Byte peekByte(Addr ea)
  {
    if ((ea &= memMask) < ramSize)
      return (pRAM[ea]);
    return (pROM[ea - ramSize]);
  }

  static L28_MCU& getL28MCU() { return l28mcu; }

  // Initialize ES3 flash from loaded ROM image
  static void initFlash() {
    if (l28MCUEnabled && pRAM) {
      uint32_t len = ramSize < 131072 ? ramSize : 131072;
      l28mcu.initES3(pRAM, len);
      flashInitialized = true;
    }
  }

  // Fetch a byte from memory
  INLINE static Byte getByte(Addr ea)
  {
	if ((ea >= VIDEO_BASE_ADDR) && (ea < VIDEO_BASE_ADDR + VIDEO_MEM_SIZE))
	  return video.getByte(ea - VIDEO_BASE_ADDR);

	if (l28MCUEnabled && (ea <= 0x000B))
	  return l28mcu.getPortByte(ea);

	if (l28MCUEnabled && (ea >= 0x0014) && (ea <= 0x0017))
	  return l28mcu.getTimerBByte(ea - 0x0014);

	if (l28MCUEnabled && (ea >= 0x0018) && (ea <= 0x001F))
	  return l28mcu.getBSR(ea - 0x0018);

	if (l28MCUEnabled && (ea >= 0x0038) && (ea <= 0x003F))
	  return l28mcu.getByte(ea - 0x0038);

	if (l28MCUEnabled && (ea >= LCD_BASE_ADDR) && (ea <= LCD_BASE_ADDR + 1))
	  return lcd.getByte(ea - LCD_BASE_ADDR);

	if ((ea >= uartBase) && (ea <= uartBase + 0x0F))
	  return uart.getByte(ea - uartBase);

	if ((ea >= fdcBase) && (ea <= fdcBase + 0x0F))
	  return fdc.getByte(ea);

	if (viaBase && (ea >= viaBase) && (ea <= viaBase + 0x0F))
	  return via.getByte(ea);

	if (l28MCUEnabled && ea >= 0x0800) {
	  uint8_t bsr_val = l28mcu.getBSR(ea >> 13);
	  if (!(bsr_val & 0x10)) {  // ES0 active (bit 4 = 0)
	    uint32_t phys = ((bsr_val & 0x20) << 12)   // A17
	                  | ((bsr_val & 0x0F) << 13)   // A16:A13
	                  | (ea & 0x1FFF);              // offset
	    return l28mcu.readES0(phys);
	  } else if (flashInitialized && !(bsr_val & 0x40)) {  // ES2
	    uint32_t phys = ((bsr_val & 0x20) << 12)
	                  | ((bsr_val & 0x0F) << 13)
	                  | (ea & 0x1FFF);
	    return l28mcu.readES2(phys);
	  } else if (flashInitialized && !(bsr_val & 0x80)) {  // ES3
	    uint32_t phys = ((bsr_val & 0x20) << 12)
	                  | ((bsr_val & 0x0F) << 13)
	                  | (ea & 0x1FFF);
	    return l28mcu.readES3(phys);
	  }
	}

    if ((ea &= memMask) < ramSize)
      return (pRAM[ea]);

    return (pROM[ea - ramSize]);
  }

  // Fetch a word from memory
  INLINE static Word getWord(Addr ea)
  {
    return (join(getByte(ea + 0), getByte(ea + 1)));
  }

  // Fetch a long address from memory
  INLINE static Addr getAddr(Addr ea)
  {
    return (join(getByte(ea + 2), getWord(ea + 0)));
  }

  // Write a byte to memory
  INLINE static void setByte(Addr ea, Byte data)
  {
	if ((ea >= VIDEO_BASE_ADDR) && (ea < VIDEO_BASE_ADDR + VIDEO_MEM_SIZE)) {
	  video.setByte(ea - VIDEO_BASE_ADDR, data);
	  return;
	}

	if (l28MCUEnabled && (ea <= 0x000B)) {
	  l28mcu.setPortByte(ea, data);
	  return;
	}

	if (l28MCUEnabled && (ea >= 0x0014) && (ea <= 0x0017)) {
	  l28mcu.setTimerBByte(ea - 0x0014, data);
	  return;
	}

	if (l28MCUEnabled && (ea >= 0x0018) && (ea <= 0x001F)) {
	  l28mcu.setBSR(ea - 0x0018, data);
	  return;
	}

	if (l28MCUEnabled && (ea >= 0x0038) && (ea <= 0x003F)) {
	  l28mcu.setByte(ea - 0x0038, data);
	  return;
	}

	if (l28MCUEnabled && (ea >= LCD_BASE_ADDR) && (ea <= LCD_BASE_ADDR + 1)) {
	  lcd.setByte(ea - LCD_BASE_ADDR, data);
	  return;
	}

	if ((ea >= uartBase) && (ea <= uartBase + 0x0F)) {
	  uart.setByte(ea - uartBase, data);
	  return;
	}

	if ((ea >= fdcBase) && (ea <= fdcBase + 0x0F)) {
	  fdc.setByte(ea, data);
	  return;
	}

	if (viaBase && (ea >= viaBase) && (ea <= viaBase + 0x0F)) {
	  via.setByte(ea, data);
	  return;
	}

	if (l28MCUEnabled && ea >= 0x0800) {
	  uint8_t bsr_val = l28mcu.getBSR(ea >> 13);
	  if (!(bsr_val & 0x10)) {  // ES0 active (bit 4 = 0)
	    uint32_t phys = ((bsr_val & 0x20) << 12)   // A17
	                  | ((bsr_val & 0x0F) << 13)   // A16:A13
	                  | (ea & 0x1FFF);              // offset
	    l28mcu.writeES0(phys, data);
	    return;
	  } else if (flashInitialized && !(bsr_val & 0x40)) {  // ES2
	    uint32_t phys = ((bsr_val & 0x20) << 12)
	                  | ((bsr_val & 0x0F) << 13)
	                  | (ea & 0x1FFF);
	    l28mcu.writeES2(phys, data);
	    return;
	  } else if (flashInitialized && !(bsr_val & 0x80)) {  // ES3
	    uint32_t phys = ((bsr_val & 0x20) << 12)
	                  | ((bsr_val & 0x0F) << 13)
	                  | (ea & 0x1FFF);
	    l28mcu.writeES3(phys, data);
	    return;
	  }
	}

    if ((ea &= memMask) < ramSize)
      pRAM[ea] = data;
  }

  // Write a word to memory
  INLINE static void setWord(Addr ea, Word data)
  {
    setByte(ea + 0, lo(data));
    setByte(ea + 1, hi(data));
  }

  static void run()
  {
	video.run();
  }

  static Video& getVideo() { return video; }
  static LCD_ST7586S& getLCD() { return lcd; }
  static WD1793& getFDC() { return fdc; }
  static VIA_6522& getVIA() { return via; }

  protected:
  mem816();
  ~mem816();

private:
  static Addr memMask;		// The address mask pattern
  static Addr ramSize;		// The amount of RAM
  static Addr uartBase;		// UART base address ($C000 default, $0000 for L28)
  static Addr fdcBase;		// FDC base address ($C010 default, $0800 for L28)
  static Addr viaBase;		// VIA base address ($C020 default, 0 = disabled)
  static bool l28MCUEnabled;	// L28 MCU peripherals enabled
  static bool flashInitialized;	// ES2/ES3 flash intercepts active

  static Byte *pRAM;		// Base of RAM memory array
  static const Byte *pROM;      // Base of ROM memory array
  static R6501 r6501;
  static UART uart;
  static L28_MCU l28mcu;
  static Video video;
  static LCD_ST7586S lcd;
  static WD1793 fdc;
  static VIA_6522 via;
};
#endif
