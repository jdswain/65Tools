#ifndef L28_MCU_H
#define L28_MCU_H

#include "wdc816.h"
#include <atomic>
#include <cstring>

/*

L28 (R65C19) USART — register layout at base $0038:

Offset  Register  Read                     Write
------  --------  -----------------------  -------------------------
0 ($38) SIB/SOB   Receive data, clear BF   Transmit data
1 ($39) SIR       Interrupt register       Interrupt enable
2 ($3A) SMR       Serial mode              Serial mode
3 ($3B) SLCR      Line control             Line control
4 ($3C) SSR       Status (read-only)       Write clears errors
5 ($3D) SFR       Serial form              Serial form
6 ($3E) SODL      —                        RXD divider latch
7 ($3F) SIDL      —                        TXD divider latch

Timer B registers at $0014-$0017 (used for baud rate generation):

Addr    Register  Description
------  --------  -----------
$0014   TBM       Timer B Mode (control/status)
$0015   TBLL      Timer B Lower Latch (write) / Lower Counter (read)
$0016   TBUL      Timer B Upper Latch (write)
$0017   TBUL      Timer B Upper Latch (read, clears TBM7 interrupt flag)

SSR (Status Register) bits:
  Bit 0: BF — Serial In Buffer Full (data available)
  Bit 1: OE — Overrun Error
  Bit 2: PE — Parity Error
  Bit 3: FE — Framing Error
  Bit 4: BI — Break Interrupt
  Bit 5: BE — Serial Out Buffer Empty (ready to transmit)
  Bit 6: UR — Serial Out Underrun

*/

struct SST39F010 {
    enum State { IDLE, CYCLE1, CYCLE2, BYTE_PROGRAM, ERASE_SETUP, ERASE_1, ERASE_2 };
    State state = IDLE;
    uint8_t data[128 * 1024];

    SST39F010() { memset(data, 0xFF, sizeof(data)); }

    void init(const uint8_t* src, uint32_t len) {
        uint32_t n = len < sizeof(data) ? len : sizeof(data);
        memcpy(data, src, n);
    }

    uint8_t read(uint32_t addr) const { return data[addr & 0x1FFFF]; }

    void write(uint32_t addr, uint8_t val) {
        addr &= 0x1FFFF;
        switch (state) {
        case IDLE:
            if (addr == 0x5555 && val == 0xAA) state = CYCLE1;
            break;
        case CYCLE1:
            state = (addr == 0x2AAA && val == 0x55) ? CYCLE2 : IDLE;
            break;
        case CYCLE2:
            if (addr == 0x5555) {
                if (val == 0xA0) state = BYTE_PROGRAM;
                else if (val == 0x80) state = ERASE_SETUP;
                else state = IDLE;
            } else state = IDLE;
            break;
        case BYTE_PROGRAM:
            data[addr] &= val;  // flash can only clear bits
            state = IDLE;
            break;
        case ERASE_SETUP:
            state = (addr == 0x5555 && val == 0xAA) ? ERASE_1 : IDLE;
            break;
        case ERASE_1:
            state = (addr == 0x2AAA && val == 0x55) ? ERASE_2 : IDLE;
            break;
        case ERASE_2:
            if (val == 0x30) {
                uint32_t base = addr & 0x1F000;
                memset(&data[base], 0xFF, 0x1000);  // 4K sector erase
            } else if (val == 0x10) {
                memset(data, 0xFF, sizeof(data));    // chip erase
            }
            state = IDLE;
            break;
        }
    }
};

class L28_MCU {
 public:
  L28_MCU();
  // USART registers ($0038-$003F)
  wdc816::Byte getByte(wdc816::Addr ea);
  void setByte(wdc816::Addr ea, wdc816::Byte data);

  // Timer B registers ($0014-$0017) — for baud rate generation
  wdc816::Byte getTimerBByte(wdc816::Addr offset);
  void setTimerBByte(wdc816::Addr offset, wdc816::Byte data);

  // Port registers ($0000-$000B)
  wdc816::Byte getPortByte(wdc816::Addr offset);
  void setPortByte(wdc816::Addr offset, wdc816::Byte data);

  // BSR registers ($0018-$001F)
  uint8_t getBSR(int index) const { return bsr[index & 7]; }
  void setBSR(int index, uint8_t data) { bsr[index & 7] = data; }

  // ES0 RAM (128K)
  uint8_t readES0(uint32_t addr) const { return es0Ram[addr & 0x1FFFF]; }
  void writeES0(uint32_t addr, uint8_t data) { es0Ram[addr & 0x1FFFF] = data; }

  // ES2 flash (128K SST39F010)
  uint8_t readES2(uint32_t addr) const { return es2Flash.read(addr); }
  void writeES2(uint32_t addr, uint8_t data) { es2Flash.write(addr, data); }

  // ES3 flash (128K SST39F010)
  uint8_t readES3(uint32_t addr) const { return es3Flash.read(addr); }
  void writeES3(uint32_t addr, uint8_t data) { es3Flash.write(addr, data); }
  void initES3(const uint8_t* src, uint32_t len) { es3Flash.init(src, len); }

  // Keyboard matrix emulation
  void pressKey(int row, int col);
  void releaseKey(int row, int col);
  void releaseAllKeys();
  bool irq0Pending() const;
  void pollKeyboard();
  void enableKeyboard() { keyboardEnabled = true; }
  void setConsoleMode(bool mode) { consoleMode = mode; }
  void setCocoaInput(bool mode) { cocoaInput = mode; }
  void injectChar(unsigned char ch);

 private:
  wdc816::Byte receiveDataReg = 0x00;
  wdc816::Byte statusReg = 0x20;     // BE set (tx ready), BF clear
  wdc816::Byte sirReg = 0x00;        // Interrupt enable
  wdc816::Byte smrReg = 0x00;        // Serial mode
  wdc816::Byte slcrReg = 0x00;       // Line control
  wdc816::Byte sfrReg = 0x00;        // Serial form
  wdc816::Byte sodlReg = 0x00;       // SOUT divider latch
  wdc816::Byte sidlReg = 0x00;       // SIN divider latch

  // Timer B registers
  wdc816::Byte tbmReg = 0x00;        // Timer B Mode
  wdc816::Byte tbllReg = 0x00;       // Timer B Lower Latch
  wdc816::Byte tbulReg = 0x00;       // Timer B Upper Latch

  // Port registers ($0000-$000B)
  wdc816::Byte portA = 0x00;
  wdc816::Byte portB = 0x00;         // address bus select (mostly used)
  wdc816::Byte portC = 0x00;         // keyboard column read (input)
  wdc816::Byte portD = 0x00;         // keyboard row drive (output)
  wdc816::Byte portADir = 0x00;
  wdc816::Byte portBSel = 0x00;
  wdc816::Byte portCDir = 0x00;
  wdc816::Byte portE = 0x00;
  wdc816::Byte portEDir = 0x00;
  wdc816::Byte eirReg = 0x00;        // External Interrupt Register
  wdc816::Byte cirReg = 0x00;        // Clear Interrupt Register

  // Keyboard matrix state
  wdc816::Byte keyMatrix[8] = {};    // one byte per row, bits = columns
  bool pa0_irq_pending = false;      // PA0 edge detect → IRQ0
  bool keyboardEnabled = false;
  bool consoleMode = false;
  bool cocoaInput = false;

  // SPSC ring buffer for Cocoa keyboard input (main thread → CPU thread)
  static const int KEY_BUF_SIZE = 32;
  uint8_t keyBuf[KEY_BUF_SIZE] = {};
  std::atomic<int> keyBufWrite{0};
  std::atomic<int> keyBufRead{0};

  // BSR registers — reset defaults map each 8K window to ES3 ROM
  uint8_t bsr[8] = {0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57};

  // ES0 RAM — 128K (16 pages of 8K)
  uint8_t es0Ram[128 * 1024] = {};

  // ES2/ES3 flash — 128K each (SST39F010)
  SST39F010 es2Flash;   // starts erased (all $FF)
  SST39F010 es3Flash;   // initialized from ROM image

  bool use_stdout = false;
  bool interactive = false;

  void status();
  void send(wdc816::Byte data);
  void enterRawMode();
};

#endif
