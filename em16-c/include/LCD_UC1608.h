#ifndef LCD_UC1608_H
#define LCD_UC1608_H

#include "wdc816.h"
#include <atomic>

#define LCD_WIDTH      240
#define LCD_HEIGHT     160     // visible rows (240x160 panel)
#define LCD_PAGES      20      // 160 rows / 8 bits per page
#define LCD_COLS       240
#define LCD_RAM_SIZE   (LCD_PAGES * LCD_COLS)  // 4800 bytes
#define LCD_SCALE      3
#define LCD_BASE_ADDR  0x0600

class LCD_UC1608 {
public:
  LCD_UC1608();

  // Host interface: offset 0 = command/status, offset 1 = data
  wdc816::Byte getByte(wdc816::Addr offset);
  void setByte(wdc816::Addr offset, wdc816::Byte data);

  void reset();

  // Cocoa display
  void enableDisplay();
  bool isDisplayEnabled() const { return displayEnabled; }
  void runCocoa();       // create window, run event loop (blocks)
  void stopDisplay();

  uint8_t *getRAM() { return ram; }
  std::atomic<bool> dirty{false};

  // Display state accessors for rendering
  int getStartLine() const { return startLine; }
  int getFixedLines() const { return fixedLines; }
  bool isInverse() const { return inverse; }
  bool isAllPixelsOn() const { return allPixelsOn; }
  bool isEnabled() const { return displayEnable; }
  bool isMirrorY() const { return mirrorY; }
  bool isMirrorX() const { return mirrorX; }
  bool isMSBFirst() const { return msbFirst; }

private:
  uint8_t ram[LCD_RAM_SIZE];   // display data RAM

  // Address registers
  uint8_t pageAddr;            // PA: 0-19
  uint8_t colAddr;             // CA: 0-239
  uint8_t returnCol;           // CR: saved CA for cursor mode

  // Control registers
  uint8_t startLine;           // SL: 0-159
  uint8_t fixedLines;          // FL: 0-15
  uint8_t gain;                // GN: 0-3
  uint8_t potentiometer;       // PM: 0-63
  uint8_t biasRatio;           // BR: 0-3
  uint8_t powerControl;        // PC: 0-7
  uint8_t muxRate;             // MR: 0=96, 1=128
  uint8_t tempComp;            // TC: 0-3
  uint8_t addrControl;         // AC: bits [3:0]

  // Display control
  bool displayEnable;          // DC[2]
  bool allPixelsOn;            // DC[1]
  bool inverse;                // DC[0]
  bool mirrorX;                // LC[2] -- column mirror
  bool mirrorY;                // LC[3] -- row mirror
  bool msbFirst;               // LC[0] -- MSB first data order

  // Command state
  bool awaitingSecondByte;     // for double-byte commands
  uint8_t firstCmdByte;        // saved first byte of double-byte cmd

  // Read pipeline
  uint8_t readLatch;           // pipeline latch for RAM reads
  bool readPrimed;             // false = next read is dummy

  bool displayEnabled;         // Cocoa window enabled
  void *nativeDelegate;

  void executeCommand(uint8_t cmd);
  void writeData(uint8_t data);
  uint8_t readData();
  uint8_t readStatus();
  void advanceAddress();       // auto-increment CA (and PA if WA)
};

#endif
