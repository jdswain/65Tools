#include "LCD_UC1608.h"
#include "emu816.h"
#include "mem816.h"

#include <string.h>
#include <iostream>

#ifdef __APPLE__
#import <Cocoa/Cocoa.h>

// LCD pixel colors — classic LCD appearance
static const uint8_t LCD_ON_R  = 40,  LCD_ON_G  = 50,  LCD_ON_B  = 80;   // dark blue/black
static const uint8_t LCD_OFF_R = 190, LCD_OFF_G = 195, LCD_OFF_B = 190;  // light grey background
static const uint8_t LCD_GAP_R = 175, LCD_GAP_G = 180, LCD_GAP_B = 175;  // gap between pixels

static const int LCD_PIX = LCD_SCALE - 1;  // pixel block size (gap = 1)

// Border around LCD area (in LCD pixels, scaled by LCD_SCALE)
static const int LCD_BORDER = 2;

// ---------------------------------------------------------------------------
// LCDView — custom NSView that renders 1-bit UC1608 framebuffer at 4x scale
// ---------------------------------------------------------------------------

@interface LCDView : NSView {
  LCD_UC1608 *lcd;
  uint8_t *rgbaBuffer;
}
- (instancetype)initWithFrame:(NSRect)frame lcd:(LCD_UC1608 *)l;
- (void)refresh;
@end

@implementation LCDView

- (instancetype)initWithFrame:(NSRect)frame lcd:(LCD_UC1608 *)l {
  self = [super initWithFrame:frame];
  if (self) {
    lcd = l;
    rgbaBuffer = (uint8_t *)calloc(LCD_WIDTH * LCD_SCALE * LCD_HEIGHT * LCD_SCALE, 4);
  }
  return self;
}

- (void)dealloc {
  free(rgbaBuffer);
  [super dealloc];
}

- (void)refresh {
  if (lcd->dirty.exchange(false)) {
    [self setNeedsDisplay:YES];
  }
}

- (BOOL)acceptsFirstResponder {
  return YES;
}

- (void)keyDown:(NSEvent *)event {
  // Use charactersIgnoringModifiers to get the base key, then
  // apply shift/ctrl ourselves to match what asciiToKey expects.
  NSString *raw = [event charactersIgnoringModifiers];
  if ([raw length] == 0) return;

  unichar base = [raw characterAtIndex:0];
  if (base >= 0xF700) return;  // skip function/arrow keys

  NSUInteger flags = [event modifierFlags];
  bool shift = (flags & NSEventModifierFlagShift) != 0;
  bool ctrl  = (flags & NSEventModifierFlagControl) != 0;

  unsigned char ch;

  if (ctrl && base >= 'a' && base <= 'z') {
    // Ctrl+letter: send control character 0x01..0x1A
    ch = base - 'a' + 1;
  } else if (base == '\r' || base == '\n') {
    ch = 0x0D;  // Return → CR
  } else if (base == 0x7F || base == 0x08) {
    ch = 0x7F;  // Delete/Backspace → DEL (EXPECT checks for $7F)
  } else if (base == 0x1B) {
    ch = 0x1B;  // Escape
  } else if (base == 0x09) {
    ch = 0x09;  // Tab
  } else if (shift) {
    // Use Cocoa's shifted character (e.g. Shift+1 = '!')
    NSString *chars = [event characters];
    if ([chars length] == 0) return;
    unichar sch = [chars characterAtIndex:0];
    if (sch >= 0x80) return;
    ch = (unsigned char)sch;
  } else {
    if (base >= 0x80) return;
    // Uppercase unshifted letters for Forth convention
    if (base >= 'a' && base <= 'z')
      ch = base - 'a' + 'A';
    else
      ch = (unsigned char)base;
  }

  mem816::getL28MCU().injectChar(ch);
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;

  int scaledW = LCD_WIDTH * LCD_SCALE;
  int scaledH = LCD_HEIGHT * LCD_SCALE;
  int stride = scaledW * 4;

  // Fill entire buffer with gap color
  for (int i = 0; i < scaledW * scaledH; i++) {
    rgbaBuffer[i * 4 + 0] = LCD_GAP_R;
    rgbaBuffer[i * 4 + 1] = LCD_GAP_G;
    rgbaBuffer[i * 4 + 2] = LCD_GAP_B;
    rgbaBuffer[i * 4 + 3] = 255;
  }

  if (!lcd->isEnabled()) {
    // Display disabled — fill pixel blocks with background color
    for (int row = 0; row < LCD_HEIGHT; row++)
      for (int col = 0; col < LCD_WIDTH; col++)
        for (int sy = 0; sy < LCD_PIX; sy++)
          for (int sx = 0; sx < LCD_PIX; sx++) {
            int off = ((row * LCD_SCALE + sy) * scaledW + col * LCD_SCALE + sx) * 4;
            rgbaBuffer[off + 0] = LCD_OFF_R;
            rgbaBuffer[off + 1] = LCD_OFF_G;
            rgbaBuffer[off + 2] = LCD_OFF_B;
          }
  } else {
    uint8_t *ram = lcd->getRAM();
    int startLine = lcd->getStartLine();
    bool inv = lcd->isInverse();
    bool allOn = lcd->isAllPixelsOn();
    bool my = lcd->isMirrorY();
    bool mx = lcd->isMirrorX();

    for (int row = 0; row < LCD_HEIGHT; row++) {
      int ramLine = my ? (LCD_HEIGHT - 1 - row + startLine) : (row + startLine);
      ramLine %= LCD_HEIGHT;  // wrap at LCD_HEIGHT lines
      int page = ramLine >> 3;
      int bit  = ramLine & 0x07;

      for (int col = 0; col < LCD_WIDTH; col++) {
        int ramCol = mx ? (LCD_WIDTH - 1 - col) : col;

        bool pixel;
        if (allOn) {
          pixel = true;
        } else {
          uint8_t byte = ram[page * LCD_COLS + ramCol];
          pixel = (byte >> bit) & 1;
        }
        if (inv) pixel = !pixel;

        uint8_t r = pixel ? LCD_ON_R : LCD_OFF_R;
        uint8_t g = pixel ? LCD_ON_G : LCD_OFF_G;
        uint8_t b = pixel ? LCD_ON_B : LCD_OFF_B;

        // Fill (LCD_PIX x LCD_PIX) block, leaving 1-pixel gap
        for (int sy = 0; sy < LCD_PIX; sy++)
          for (int sx = 0; sx < LCD_PIX; sx++) {
            int off = ((row * LCD_SCALE + sy) * scaledW + col * LCD_SCALE + sx) * 4;
            rgbaBuffer[off + 0] = r;
            rgbaBuffer[off + 1] = g;
            rgbaBuffer[off + 2] = b;
          }
      }
    }
  }

  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGContextRef bmpCtx = CGBitmapContextCreate(
    rgbaBuffer, scaledW, scaledH, 8, stride, cs,
    kCGImageAlphaNoneSkipLast);
  CGImageRef image = CGBitmapContextCreateImage(bmpCtx);

  CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];

  // Fill border area
  CGContextSetRGBFillColor(ctx,
    LCD_GAP_R / 255.0, LCD_GAP_G / 255.0, LCD_GAP_B / 255.0, 1.0);
  CGContextFillRect(ctx, self.bounds);

  // Draw LCD image inset by the border (already at full scale)
  int border = LCD_BORDER * LCD_SCALE;
  CGContextDrawImage(ctx,
    CGRectMake(border, border, scaledW, scaledH),
    image);

  CGImageRelease(image);
  CGContextRelease(bmpCtx);
  CGColorSpaceRelease(cs);
}

@end

// ---------------------------------------------------------------------------
// LCDDelegate — manages the NSWindow and refresh timer
// ---------------------------------------------------------------------------

@interface LCDDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate> {
  LCD_UC1608 *lcd;
}
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, strong) LCDView *lcdView;
- (instancetype)initWithLCD:(LCD_UC1608 *)l;
@end

@implementation LCDDelegate

- (instancetype)initWithLCD:(LCD_UC1608 *)l {
  self = [super init];
  if (self) {
    lcd = l;
  }
  return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  (void)notification;

  int winW = (LCD_WIDTH + LCD_BORDER * 2) * LCD_SCALE;
  int winH = (LCD_HEIGHT + LCD_BORDER * 2) * LCD_SCALE;

  NSRect frame = NSMakeRect(100, 100, winW, winH);
  self.window = [[NSWindow alloc]
    initWithContentRect:frame
    styleMask:(NSWindowStyleMaskTitled |
               NSWindowStyleMaskClosable |
               NSWindowStyleMaskMiniaturizable)
    backing:NSBackingStoreBuffered
    defer:NO];
  [self.window setTitle:@"L28 LCD Display"];
  [self.window setDelegate:self];

  self.lcdView = [[LCDView alloc]
    initWithFrame:NSMakeRect(0, 0, winW, winH)
    lcd:lcd];
  [self.window setContentView:self.lcdView];
  [self.window makeKeyAndOrderFront:nil];

  // Refresh display at ~60 fps
  self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
    target:self
    selector:@selector(timerFired:)
    userInfo:nil
    repeats:YES];
}

- (void)timerFired:(NSTimer *)timer {
  (void)timer;
  [self.lcdView refresh];
}

- (void)windowWillClose:(NSNotification *)notification {
  (void)notification;
  [self.refreshTimer invalidate];
  self.refreshTimer = nil;
  emu816::stop();
  [NSApp terminate:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
  (void)sender;
  return YES;
}

@end

#endif // __APPLE__

// ---------------------------------------------------------------------------
// LCD_UC1608 class implementation
// ---------------------------------------------------------------------------

LCD_UC1608::LCD_UC1608()
  : displayEnabled(false), nativeDelegate(nullptr)
{
  reset();
}

void LCD_UC1608::reset()
{
  memset(ram, 0, sizeof(ram));
  pageAddr = 0;
  colAddr = 0;
  returnCol = 0;
  startLine = 0;
  fixedLines = 0;
  gain = 0;
  potentiometer = 0;
  biasRatio = 0;
  powerControl = 0;
  muxRate = 0;
  tempComp = 0;
  addrControl = 0;
  displayEnable = false;
  allPixelsOn = false;
  inverse = false;
  mirrorX = false;
  mirrorY = false;
  msbFirst = false;
  awaitingSecondByte = false;
  firstCmdByte = 0;
  readLatch = 0;
  readPrimed = false;
}

wdc816::Byte LCD_UC1608::getByte(wdc816::Addr offset)
{
  if (offset == 0)
    return readStatus();
  else
    return readData();
}

void LCD_UC1608::setByte(wdc816::Addr offset, wdc816::Byte data)
{
  if (offset == 0)
    executeCommand(data);
  else
    writeData(data);
}

uint8_t LCD_UC1608::readStatus()
{
  // Status byte: BZ MX DE RS WA GN1 GN0 1
  uint8_t status = 0x01;  // bit 0 always 1
  status |= (gain & 0x03) << 1;       // GN[1:0] bits 1-2
  bool wrapAround = (addrControl & 0x01);
  if (wrapAround) status |= 0x08;     // WA bit 3
  // RS (reset) = 0 (not in reset)     // bit 4
  if (displayEnable) status |= 0x20;  // DE bit 5
  if (mirrorX) status |= 0x40;        // MX bit 6
  // BZ (busy) = 0                     // bit 7
  return status;
}

void LCD_UC1608::executeCommand(uint8_t cmd)
{
  // Handle second byte of double-byte commands
  if (awaitingSecondByte) {
    awaitingSecondByte = false;
    if (firstCmdByte == 0x81) {
      // Set Gain + PM: GN[1:0] = bits 7-6, PM[5:0] = bits 5-0
      gain = (cmd >> 6) & 0x03;
      potentiometer = cmd & 0x3F;
    } else if (firstCmdByte == 0xF0) {
      // Extended Set Start Line: SL = cmd (0-159)
      startLine = cmd;
    } else if (firstCmdByte == 0xF1) {
      // Extended Set Page Address: PA = cmd (0-19)
      pageAddr = cmd;
      readPrimed = false;
    }
    return;
  }

  uint8_t hi4 = (cmd >> 4) & 0x0F;
  uint8_t lo4 = cmd & 0x0F;

  switch (hi4) {
  case 0x0:
    // 0000 xxxx — Set Column Address LSB
    colAddr = (colAddr & 0xF0) | lo4;
    readPrimed = false;
    break;

  case 0x1:
    // 0001 xxxx — Set Column Address MSB
    colAddr = (colAddr & 0x0F) | (lo4 << 4);
    readPrimed = false;
    break;

  case 0x2:
    if (cmd & 0x08) {
      // 0010 1xxx — Set Power Control: PC[2:0]
      powerControl = cmd & 0x07;
    } else {
      // 0010 0xxx — Set MR + TC: MR = bit 2, TC[1:0] = bits 1-0
      muxRate = (cmd >> 2) & 0x01;
      tempComp = cmd & 0x03;
    }
    break;

  case 0x4:
  case 0x5:
  case 0x6:
  case 0x7:
    // 01xx xxxx — Set Start Line: SL[5:0] (original UC1608, 0-63)
    startLine = cmd & 0x3F;
    break;

  case 0x8:
    if (cmd == 0x81) {
      // Set Gain + PM (double-byte)
      awaitingSecondByte = true;
      firstCmdByte = cmd;
    } else if ((cmd & 0xFE) == 0x84) {
      // 1000 010x — Set All Pixels ON: DC[1]
      allPixelsOn = cmd & 0x01;
      dirty.store(true, std::memory_order_relaxed);
    } else if ((cmd & 0xFE) == 0x8A) {
      // 1000 101x — Set RAM Address Control: AC bit
      // This sets AC[0] (wrap-around enable)
      if (cmd & 0x01)
        addrControl |= 0x01;
      else
        addrControl &= ~0x01;
    }
    break;

  case 0x9:
    // 1001 xxxx — Set Fixed Lines: FL[3:0]
    fixedLines = lo4;
    break;

  case 0xA:
    if ((cmd & 0xFE) == 0xA4) {
      // 1010 010x — Set All Pixels ON: DC[1]
      allPixelsOn = cmd & 0x01;
      dirty.store(true, std::memory_order_relaxed);
    } else if ((cmd & 0xFE) == 0xA6) {
      // 1010 011x — Set Inverse: DC[0]
      inverse = cmd & 0x01;
      dirty.store(true, std::memory_order_relaxed);
    } else if ((cmd & 0xFE) == 0xAE) {
      // 1010 111x — Set Display Enable: DC[2]
      displayEnable = cmd & 0x01;
      dirty.store(true, std::memory_order_relaxed);
    }
    break;

  case 0xB:
    // 1011 xxxx — Set Page Address: PA[4:0] (extended to 5 bits for 20 pages)
    pageAddr = cmd & 0x1F;
    readPrimed = false;
    break;

  case 0xC:
    // 1100 xxxx — Set LCD Mapping: MY, MX, 0, MSF
    mirrorY  = (cmd >> 3) & 0x01;
    mirrorX  = (cmd >> 2) & 0x01;
    msbFirst = cmd & 0x01;
    dirty.store(true, std::memory_order_relaxed);
    break;

  case 0xD:
    // Reserved — ignore
    break;

  case 0xE:
    if (cmd == 0xE2) {
      // System Reset
      reset();
    } else if (cmd == 0xE3) {
      // NOP
    } else if ((cmd & 0xFC) == 0xE8) {
      // 1110 10xx — Set Bias Ratio: BR[1:0]
      biasRatio = cmd & 0x03;
    } else if (cmd == 0xEE) {
      // Reset Cursor Mode: AC[3]=0, CA=CR
      addrControl &= ~0x08;
      colAddr = returnCol;
      readPrimed = false;
    } else if (cmd == 0xEF) {
      // Set Cursor Mode: AC[3]=1, CR=CA
      addrControl |= 0x08;
      returnCol = colAddr;
    }
    break;

  case 0xF:
    if (cmd == 0xF0) {
      // $F0 — Extended Set Start Line (double-byte): next byte = SL[7:0]
      awaitingSecondByte = true;
      firstCmdByte = 0xF0;
    } else if (cmd == 0xF1) {
      // $F1 — Extended Set Page Address (double-byte): next byte = PA[7:0]
      awaitingSecondByte = true;
      firstCmdByte = 0xF1;
    }
    break;

  default:
    break;
  }
}

void LCD_UC1608::writeData(uint8_t data)
{
  if (pageAddr < LCD_PAGES && colAddr < LCD_COLS) {
    ram[pageAddr * LCD_COLS + colAddr] = data;
    dirty.store(true, std::memory_order_relaxed);
  }
  advanceAddress();
  readPrimed = false;
}

uint8_t LCD_UC1608::readData()
{
  if (!readPrimed) {
    // First read after address change is a dummy — load the latch
    if (pageAddr < LCD_PAGES && colAddr < LCD_COLS)
      readLatch = ram[pageAddr * LCD_COLS + colAddr];
    readPrimed = true;
    advanceAddress();
    return readLatch;  // returns stale data
  }

  uint8_t result = readLatch;
  if (pageAddr < LCD_PAGES && colAddr < LCD_COLS)
    readLatch = ram[pageAddr * LCD_COLS + colAddr];
  advanceAddress();
  return result;
}

void LCD_UC1608::advanceAddress()
{
  bool wrapAround = (addrControl & 0x01);
  bool pageDecrement = (addrControl & 0x04);

  colAddr++;
  if (colAddr >= LCD_COLS) {
    if (wrapAround) {
      colAddr = 0;
      if (pageDecrement) {
        pageAddr = (pageAddr == 0) ? LCD_PAGES - 1 : pageAddr - 1;
      } else {
        pageAddr = (pageAddr + 1 >= LCD_PAGES) ? 0 : pageAddr + 1;
      }
    } else {
      colAddr = LCD_COLS - 1;  // clamp at max
    }
  }
}

void LCD_UC1608::enableDisplay()
{
  displayEnabled = true;
}

void LCD_UC1608::stopDisplay()
{
#ifdef __APPLE__
  if (displayEnabled) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [NSApp terminate:nil];
    });
  }
#endif
}

void LCD_UC1608::runCocoa()
{
#ifdef __APPLE__
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    LCDDelegate *delegate = [[LCDDelegate alloc] initWithLCD:this];
    [NSApp setDelegate:delegate];
    nativeDelegate = (__bridge void *)delegate;

    // Create a minimal menu bar (Quit via Cmd-Q)
    NSMenu *menuBar = [[NSMenu alloc] init];
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    [menuBar addItem:appMenuItem];
    NSMenu *appMenu = [[NSMenu alloc] init];
    NSMenuItem *quitItem = [[NSMenuItem alloc]
      initWithTitle:@"Quit"
      action:@selector(terminate:)
      keyEquivalent:@"q"];
    [appMenu addItem:quitItem];
    [appMenuItem setSubmenu:appMenu];
    [NSApp setMainMenu:menuBar];

    [NSApp activateIgnoringOtherApps:YES];
    [NSApp run]; // Blocks until terminated
  }
#else
  std::cerr << "Cocoa display not available on this platform" << std::endl;
#endif
}
