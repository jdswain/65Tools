#ifndef VIDEO_H
#define VIDEO_H

#include "wdc816.h"
#include <string.h>
#include <atomic>

// Video display parameters — FPGA framebuffer layout:
//   base $70_0000, 640x480, 4bpp, 320-byte stride (2 px/byte), 150 KB.
//   Low nibble = left (even-x) pixel; high nibble = right (odd-x) pixel.
#define VIDEO_WIDTH      640
#define VIDEO_HEIGHT     480
#define VIDEO_BPP        4
#define VIDEO_SCALE      2
#define VIDEO_BPR        (VIDEO_WIDTH * VIDEO_BPP / 8)  // 320 bytes per row
#define VIDEO_MEM_SIZE   (VIDEO_BPR * VIDEO_HEIGHT)      // 153600 bytes (150 KB)
#define VIDEO_BASE_ADDR  0x700000

class Video {
public:
  Video();
  ~Video();
  wdc816::Byte getByte(wdc816::Addr ea);
  void setByte(wdc816::Addr ea, wdc816::Byte data);
  void reset();
  void run();

  // Cocoa display support
  void enableDisplay();
  bool isDisplayEnabled() const { return displayEnabled; }
  void runCocoa();     // Create window and run NSApp event loop (blocks)
  void stopDisplay();  // Signal display to close

  uint8_t *getMemory() { return mem; }

  // Programmable 16-entry palette (FPGA writes it at $0240). c: 0=R,1=G,2=B.
  void setPaletteByte(int n, int c, uint8_t v) {
    if (n >= 0 && n < 16 && c >= 0 && c < 3) pal[n][c] = v;
  }
  const uint8_t *getPalette() const { return &pal[0][0]; }
  int getWidth() const { return _w; }
  int getHeight() const { return _h; }

  std::atomic<bool> dirty{false};

private:
  uint8_t *mem;   // heap-allocated framebuffer (VIDEO_MEM_SIZE bytes)
  uint8_t pal[16][3];   // programmable palette (RGB per entry)
  int _w;
  int _h;
  bool displayEnabled;
  void *nativeDelegate;  // Opaque pointer to Cocoa delegate
};

#endif
