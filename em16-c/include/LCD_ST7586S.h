#ifndef LCD_ST7586S_H
#define LCD_ST7586S_H

#include "wdc816.h"
#include <atomic>

#define LCD_WIDTH       240
#define LCD_HEIGHT      160
#define LCD_RAM_COLS    128     // byte columns (2 pixels each = 256 pixel cols)
#define LCD_RAM_ROWS    160
#define LCD_RAM_SIZE    (LCD_RAM_COLS * LCD_RAM_ROWS)  // 20,480
#define LCD_COL_OFFSET  4       // byte column offset (8 pixels / 2)
#define LCD_VIS_COLS    120     // visible byte columns (240 / 2)
#define LCD_SCALE       3
#define LCD_BASE_ADDR   0x0600

class LCD_ST7586S {
public:
  LCD_ST7586S();

  // Host interface: offset 0 = command/status, offset 1 = data
  wdc816::Byte getByte(wdc816::Addr offset);
  void setByte(wdc816::Addr offset, wdc816::Byte data);

  void reset();

  // Cocoa display
  void enableDisplay();
  bool isDisplayEnabled() const { return displayEnabled; }
  void runCocoa();
  void stopDisplay();

  uint8_t *getRAM() { return ram; }
  std::atomic<bool> dirty{false};

  // Display state for rendering
  bool isEnabled() const { return displayEnable; }
  bool isInverse() const { return inverse; }
  int getScrollStart() const { return scrollStart; }
  int getScrollAreaTop() const { return scrollAreaTop; }
  int getScrollAreaHeight() const { return scrollAreaHeight; }
  uint8_t getContrast() const { return vopOffset; }
  bool isMirrorX() const { return mirrorX; }
  bool isMirrorY() const { return mirrorY; }

private:
  uint8_t ram[LCD_RAM_SIZE];

  // Window registers
  uint16_t colStart, colEnd;
  uint16_t rowStart, rowEnd;
  uint16_t curCol, curRow;

  // Scroll
  uint16_t scrollStart;
  uint16_t scrollAreaTop;
  uint16_t scrollAreaHeight;

  // Display control
  bool displayEnable;
  bool inverse;
  bool idleMode;
  uint8_t pixelFormat;
  bool mirrorX, mirrorY;
  uint8_t vopOffset;
  uint16_t vop;

  // Command state machine
  enum State { IDLE, PARAM, RAM_WRITE, RAM_READ };
  State state;
  uint8_t currentCmd;
  uint8_t paramBuf[8];
  int paramCount;
  int paramExpected;
  bool readDummy;

  bool displayEnabled;         // Cocoa window
  void *nativeDelegate;

  void executeCommand(uint8_t cmd);
  void processParam(uint8_t data);
  void finishCommand();
  void writeRAM(uint8_t data);
  uint8_t readRAM();
  void advanceWindowPos();
};

#endif
