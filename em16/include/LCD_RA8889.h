#ifndef LCD_RA8889_H
#define LCD_RA8889_H

#include "wdc816.h"
#include <atomic>
#include <cstdint>

#define LCD_WIDTH       800
#define LCD_HEIGHT      480
#define LCD_BPP         2       // 16-bit RGB565
#define LCD_FB_SIZE     (LCD_WIDTH * LCD_HEIGHT * LCD_BPP)  // 768,000 bytes
#define LCD_BASE_ADDR   0x0600

// Font sizes (internal CGROM)
#define FONT_8x16   0
#define FONT_12x24  1
#define FONT_16x32  2

class LCD_RA8889 {
public:
  LCD_RA8889();
  ~LCD_RA8889();

  // Host interface: offset 0 = register addr/status, offset 1 = register data
  wdc816::Byte getByte(wdc816::Addr offset);
  void setByte(wdc816::Addr offset, wdc816::Byte data);

  void reset();
  void enableDisplay();
  bool isDisplayEnabled() const { return displayEnabled; }
  void runCocoa();
  void stopDisplay();

  std::atomic<bool> dirty{false};

  // Accessors for Cocoa rendering
  uint8_t *getFramebuffer() { return framebuffer; }
  uint16_t getCanvasWidth() const { return canvasWidth; }
  uint16_t getCanvasHeight() const { return canvasHeight; }
  uint16_t getMainWinX() const { return mainWinX; }
  uint16_t getMainWinY() const { return mainWinY; }
  uint8_t getPWMDuty() const { return pwmDuty; }
  bool isCursorVisible() const { return cursorVisible; }
  bool isCursorBlink() const { return cursorBlink; }
  uint16_t getTextCursorX() const { return textCursorX; }
  uint16_t getTextCursorY() const { return textCursorY; }
  int getFontW() const { return fontW; }
  int getFontH() const { return fontH; }
  uint8_t getBlinkRate() const { return blinkRate; }

private:
  uint8_t *framebuffer;          // 768KB RGB565 framebuffer
  uint8_t regs[256];             // register file
  uint8_t selectedReg;           // currently selected register address

  // Display state
  bool displayEnable;
  uint16_t canvasWidth, canvasHeight;
  uint32_t canvasAddr;           // base address in framebuffer
  uint16_t activeWinX, activeWinY, activeWinW, activeWinH;
  uint16_t mainWinX, mainWinY;   // scroll offset

  // Text engine
  uint16_t textCursorX, textCursorY;
  bool textMode;                  // ICR bit 2
  int fontSizeIdx;                // 0=8x16, 1=12x24, 2=16x32
  int fontW, fontH;               // current char pixel dimensions
  int hScale, vScale;             // text scaling (1-4x)
  uint8_t fgR, fgG, fgB;
  uint8_t bgR, bgG, bgB;
  bool textTransparent;
  bool cursorVisible, cursorBlink;
  uint8_t blinkRate;
  uint8_t charLineGap, charSpacing;

  // Drawing engine
  bool drawBusy;
  uint16_t drawX0, drawY0, drawX1, drawY1;

  // BTE engine
  bool bteBusy;
  // BTE source/dest/size registers
  uint16_t bteSrcX, bteSrcY;
  uint16_t bteDstX, bteDstY;
  uint16_t bteWidth, bteHeight;

  // PWM
  uint8_t pwmDuty;

  // Cocoa
  bool displayEnabled;
  void *nativeDelegate;

  // Internal methods
  void writeRegister(uint8_t reg, uint8_t value);
  uint8_t readRegister(uint8_t reg);
  void renderCharacter(uint8_t ch);
  void advanceTextCursor();
  void executeDrawing();
  void executeBTE();
  void bteBlockCopy(uint16_t sx, uint16_t sy, uint16_t dx, uint16_t dy,
                    uint16_t w, uint16_t h);
  void bteSolidFill(uint16_t x, uint16_t y, uint16_t w, uint16_t h,
                    uint8_t r, uint8_t g, uint8_t b);
  void drawLine(int x0, int y0, int x1, int y1);
  void drawRect(int x0, int y0, int x1, int y1, bool fill);
  void setPixel(int x, int y, uint8_t r, uint8_t g, uint8_t b);
  uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b);
  void updateFontSize();

  // Built-in 8x16 font data (VGA/CP437 bitmap font)
  static const uint8_t cgrom_8x16[256 * 16];
};

#endif
