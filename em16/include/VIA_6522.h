#ifndef VIA_6522_H
#define VIA_6522_H

#include "wdc816.h"
#include "ADB_Controller.h"

// 6522 VIA (Versatile Interface Adapter) emulation
// I/O slot: $C020-$C02F (16 bytes)
//
// Register map:
//   $0  IRB/ORB     Port B
//   $1  IRA/ORA     Port A (handshake)
//   $2  DDRB        Data Direction B
//   $3  DDRA        Data Direction A
//   $4  T1C-L       Timer 1 Counter/Latch Low
//   $5  T1C-H       Timer 1 Counter High
//   $6  T1L-L       Timer 1 Latch Low
//   $7  T1L-H       Timer 1 Latch High
//   $8  T2C-L       Timer 2 Counter/Latch Low
//   $9  T2C-H       Timer 2 Counter High
//   $A  SR          Shift Register
//   $B  ACR         Auxiliary Control Register
//   $C  PCR         Peripheral Control Register
//   $D  IFR         Interrupt Flag Register
//   $E  IER         Interrupt Enable Register
//   $F  IRA/ORA     Port A (no handshake)
//
// ADB microcontroller connected via Port A (data) and Port B (control):
//   Port B bit 0 (output): Command strobe — rising edge sends ORA as command
//   Port B bit 1 (input):  Data available — ADB has response bytes
//   Port B bit 4 (input):  SRQ — device has pending service request

class VIA_6522 {
public:
  VIA_6522();
  wdc816::Byte getByte(wdc816::Addr ea);
  void setByte(wdc816::Addr ea, wdc816::Byte data);
  void reset();
  void tick(unsigned int elapsed_cycles);
  bool irqPending() const;

  // ADB input convenience methods (called from Cocoa event handlers)
  void adbKeyDown(uint8_t adbKeyCode);
  void adbKeyUp(uint8_t adbKeyCode);
  void adbMouseMove(int dx, int dy);
  void adbMouseButton(bool pressed);

  ADB_Controller& getADB() { return adb; }

private:
  // Port registers
  wdc816::Byte ora, orb;      // Output registers A/B
  wdc816::Byte ddra, ddrb;    // Data direction A/B

  // Timer registers
  wdc816::Word t1_counter, t1_latch;
  wdc816::Word t2_counter;
  wdc816::Byte t2_latch_lo;

  // Shift register and control
  wdc816::Byte sr;             // Shift register
  wdc816::Byte acr;            // Auxiliary control register
  wdc816::Byte pcr;            // Peripheral control register
  wdc816::Byte ifr;            // Interrupt flag register
  wdc816::Byte ier;            // Interrupt enable register

  // Timer 1 running state (set when T1C-H is written)
  bool t1_running;

  // ADB microcontroller
  ADB_Controller adb;

  // Update IFR bit 7 based on enabled interrupts
  void updateIRQ();
  void signalSRQ();
};

#endif
