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
#include "R6501.h"

#include "Video.h"

// The mem816 class defines a set of standard methods for defining and accessing
// the emulated memory area.

class mem816 :
  public wdc816
{
public:
  // Define the memory areas and sizes
  static void setMemory (Addr memMask, Addr ramSize, const Byte *pROM);
  static void setMemory (Addr memMask, Addr ramSize, Byte *pRAM, const Byte *pROM);

  // Fetch a byte from memory
  INLINE static Byte getByte(Addr ea)
  {
	//if ((ea >= 0xC000) && (ea <= 0xC004))
	//  return uart.getByte(ea);

	 if ((ea >= 0x0000) && (ea <= 0x0FF))
	   return r6501.getByte(ea);

	//if ((ea >= 0x9000) && (ea <= 0xA000))
	//	return video.getByte(ea - 0x9000);
		
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
	// std::cout << "Set byte at " << ea << std::endl;
	//if ((ea >= 0xC000) && (ea <= 0xC004))
	//  uart.setByte(ea, data);
	 if ((ea >= 0x0000) && (ea <= 0x00FF))
	  r6501.setByte(ea, data);

	//if ((ea >= 0x9000) && (ea <= 0xA000))
	//  return video.setByte(ea - 0x9000, data);
			
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
  
  protected:
  mem816();
  ~mem816();

private:
  static Addr memMask;		// The address mask pattern
  static Addr ramSize;		// The amount of RAM

  static Byte *pRAM;		// Base of RAM memory array
  static const Byte *pROM;      // Base of ROM memory array
  static R6501 r6501;
  static UART uart;
  static Video video;
};
#endif
