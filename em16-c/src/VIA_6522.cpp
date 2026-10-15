#include "VIA_6522.h"
#include <cstring>

// IFR/IER bit masks
#define IFR_CA2   0x01
#define IFR_CA1   0x02
#define IFR_SR    0x04
#define IFR_CB2   0x08
#define IFR_CB1   0x10
#define IFR_T2    0x20
#define IFR_T1    0x40
#define IFR_IRQ   0x80

VIA_6522::VIA_6522()
{
  reset();
}

void VIA_6522::reset()
{
  ora = orb = 0;
  ddra = ddrb = 0;
  t1_counter = t1_latch = 0;
  t2_counter = 0;
  t2_latch_lo = 0;
  t1_running = false;
  sr = 0;
  acr = pcr = 0;
  ifr = ier = 0;
  adb.reset();
}

void VIA_6522::updateIRQ()
{
  if (ifr & ier & 0x7F)
    ifr |= IFR_IRQ;
  else
    ifr &= ~IFR_IRQ;
}

void VIA_6522::signalSRQ()
{
  ifr |= IFR_CA1;
  updateIRQ();
}

void VIA_6522::adbKeyDown(uint8_t kc)
{
  adb.keyDown(kc);
  signalSRQ();
}

void VIA_6522::adbKeyUp(uint8_t kc)
{
  adb.keyUp(kc);
  signalSRQ();
}

void VIA_6522::adbMouseMove(int dx, int dy)
{
  adb.mouseMove(dx, dy);
  signalSRQ();
}

void VIA_6522::adbMouseButton(bool pressed)
{
  adb.mouseButton(pressed);
  signalSRQ();
}

wdc816::Byte VIA_6522::getByte(wdc816::Addr ea)
{
  switch (ea & 0x0F) {
  case 0x0: {
    // IRB — Port B: mix output bits with ADB status inputs
    uint8_t inputs = 0;
    if (adb.hasResponse()) inputs |= 0x02;  // bit 1: data available
    if (adb.hasSRQ())      inputs |= 0x10;  // bit 4: SRQ
    return (orb & ddrb) | (inputs & ~ddrb);
  }

  case 0x1: // IRA — Port A (with handshake): read ADB response, clear CA1
    ifr &= ~IFR_CA1;
    updateIRQ();
    if (adb.hasResponse()) return adb.readResponse();
    return 0xFF;

  case 0x2: // DDRB
    return ddrb;

  case 0x3: // DDRA
    return ddra;

  case 0x4: // T1C-L — Timer 1 counter low (clears T1 interrupt)
    ifr &= ~IFR_T1;
    updateIRQ();
    return (wdc816::Byte)(t1_counter & 0xFF);

  case 0x5: // T1C-H — Timer 1 counter high
    return (wdc816::Byte)((t1_counter >> 8) & 0xFF);

  case 0x6: // T1L-L — Timer 1 latch low
    return (wdc816::Byte)(t1_latch & 0xFF);

  case 0x7: // T1L-H — Timer 1 latch high
    return (wdc816::Byte)((t1_latch >> 8) & 0xFF);

  case 0x8: // T2C-L — Timer 2 counter low (clears T2 interrupt)
    ifr &= ~IFR_T2;
    updateIRQ();
    return (wdc816::Byte)(t2_counter & 0xFF);

  case 0x9: // T2C-H — Timer 2 counter high
    return (wdc816::Byte)((t2_counter >> 8) & 0xFF);

  case 0xA: // SR — Shift register
    return sr;

  case 0xB: // ACR
    return acr;

  case 0xC: // PCR
    return pcr;

  case 0xD: // IFR
    return ifr;

  case 0xE: // IER — read returns enable bits with bit 7 always set
    return ier | 0x80;

  case 0xF: // IRA — Port A (no handshake): read ADB response, clear CA1
    ifr &= ~IFR_CA1;
    updateIRQ();
    if (adb.hasResponse()) return adb.readResponse();
    return 0xFF;
  }
  return 0;
}

void VIA_6522::setByte(wdc816::Addr ea, wdc816::Byte data)
{
  switch (ea & 0x0F) {
  case 0x0: {
    // ORB — Port B output: detect rising edge on bit 0 (command strobe)
    uint8_t old = orb;
    orb = data;
    if ((data & 0x01) && !(old & 0x01)) {
      adb.sendCommand(ora);
    }
    break;
  }

  case 0x1: // ORA — Port A output (with handshake)
    ora = data;
    break;

  case 0x2: // DDRB
    ddrb = data;
    break;

  case 0x3: // DDRA
    ddra = data;
    break;

  case 0x4: // T1L-L — Timer 1 latch low
    t1_latch = (t1_latch & 0xFF00) | data;
    break;

  case 0x5: // T1C-H — write loads counter from latch, clears T1 interrupt, starts timer
    t1_latch = (t1_latch & 0x00FF) | ((wdc816::Word)data << 8);
    t1_counter = t1_latch;
    ifr &= ~IFR_T1;
    t1_running = true;
    updateIRQ();
    break;

  case 0x6: // T1L-L — latch low only
    t1_latch = (t1_latch & 0xFF00) | data;
    break;

  case 0x7: // T1L-H — latch high only (clears T1 interrupt)
    t1_latch = (t1_latch & 0x00FF) | ((wdc816::Word)data << 8);
    ifr &= ~IFR_T1;
    updateIRQ();
    break;

  case 0x8: // T2L-L — Timer 2 latch low
    t2_latch_lo = data;
    break;

  case 0x9: // T2C-H — write loads counter, clears T2 interrupt
    t2_counter = ((wdc816::Word)data << 8) | t2_latch_lo;
    ifr &= ~IFR_T2;
    updateIRQ();
    break;

  case 0xA: // SR
    sr = data;
    break;

  case 0xB: // ACR
    acr = data;
    break;

  case 0xC: // PCR
    pcr = data;
    break;

  case 0xD: // IFR — writing 1 clears the corresponding bit
    ifr &= ~(data & 0x7F);
    updateIRQ();
    break;

  case 0xE: // IER — bit 7: 1=set bits, 0=clear bits
    if (data & 0x80)
      ier |= (data & 0x7F);
    else
      ier &= ~(data & 0x7F);
    updateIRQ();
    break;

  case 0xF: // ORA — Port A (no handshake)
    ora = data;
    break;
  }
}

void VIA_6522::tick(unsigned int elapsed_cycles)
{
  if (!t1_running) return;

  if (elapsed_cycles >= t1_counter) {
    // Timer 1 underflow — fire interrupt
    ifr |= IFR_T1;
    if (acr & 0x40) {
      // Free-running mode (ACR bit 6): reload from latch
      // Account for overshoot cycles
      unsigned int overshoot = elapsed_cycles - t1_counter;
      t1_counter = t1_latch - (overshoot % (t1_latch + 1));
    } else {
      // One-shot mode: stop timer
      t1_running = false;
      t1_counter = 0;
    }
    updateIRQ();
  } else {
    t1_counter -= elapsed_cycles;
  }
}

bool VIA_6522::irqPending() const
{
  return (ifr & ier & 0x7F) != 0;
}
