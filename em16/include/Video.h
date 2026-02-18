#ifndef VIDEO_H
#define VIDEO_H

#include "wdc816.h"
#include <string.h>
#include <atomic>

// Video display parameters
#define VIDEO_WIDTH      640
#define VIDEO_HEIGHT     400
#define VIDEO_BPP        4
#define VIDEO_SCALE      2
#define VIDEO_BPR        (VIDEO_WIDTH * VIDEO_BPP / 8)  // 160 bytes per row
#define VIDEO_MEM_SIZE   (VIDEO_BPR * VIDEO_HEIGHT)      // 76800 bytes
#define VIDEO_BASE_ADDR  0x020000

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
  int getWidth() const { return _w; }
  int getHeight() const { return _h; }

  std::atomic<bool> dirty{false};

private:
  uint8_t mem[VIDEO_MEM_SIZE];
  int _w;
  int _h;
  bool displayEnabled;
  void *nativeDelegate;  // Opaque pointer to Cocoa delegate
};

#endif
