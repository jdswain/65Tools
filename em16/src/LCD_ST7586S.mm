#include "LCD_ST7586S.h"
#include "emu816.h"
#include "mem816.h"

#include <string.h>
#include <iostream>
#include <algorithm>

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
// LCDView — custom NSView that renders ST7586S framebuffer at 3x scale
// ---------------------------------------------------------------------------

@interface LCDView : NSView {
  LCD_ST7586S *lcd;
  uint8_t *rgbaBuffer;
}
- (instancetype)initWithFrame:(NSRect)frame lcd:(LCD_ST7586S *)l;
- (void)refresh;
@end

@implementation LCDView

- (instancetype)initWithFrame:(NSRect)frame lcd:(LCD_ST7586S *)l {
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
  NSString *raw = [event charactersIgnoringModifiers];
  if ([raw length] == 0) return;

  unichar base = [raw characterAtIndex:0];
  if (base >= 0xF700) return;

  NSUInteger flags = [event modifierFlags];
  bool shift = (flags & NSEventModifierFlagShift) != 0;
  bool ctrl  = (flags & NSEventModifierFlagControl) != 0;

  unsigned char ch;

  if (ctrl && base >= 'a' && base <= 'z') {
    ch = base - 'a' + 1;
  } else if (base == '\r' || base == '\n') {
    ch = 0x0D;
  } else if (base == 0x7F || base == 0x08) {
    ch = 0x7F;
  } else if (base == 0x1B) {
    ch = 0x1B;
  } else if (base == 0x09) {
    ch = 0x09;
  } else if (shift) {
    NSString *chars = [event characters];
    if ([chars length] == 0) return;
    unichar sch = [chars characterAtIndex:0];
    if (sch >= 0x80) return;
    ch = (unsigned char)sch;
  } else {
    if (base >= 0x80) return;
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
    bool inv = lcd->isInverse();
    bool my = lcd->isMirrorY();
    bool mx = lcd->isMirrorX();
    int scrollSt = lcd->getScrollStart();
    int scrollTop = lcd->getScrollAreaTop();
    int scrollHt = lcd->getScrollAreaHeight();
    uint8_t contrast = lcd->getContrast();

    // Contrast-adjusted on-pixel color
    float factor = std::min(1.0f, std::max(0.2f, contrast / 50.0f));
    uint8_t onR = LCD_OFF_R + (int)((LCD_ON_R - (int)LCD_OFF_R) * factor);
    uint8_t onG = LCD_OFF_G + (int)((LCD_ON_G - (int)LCD_OFF_G) * factor);
    uint8_t onB = LCD_OFF_B + (int)((LCD_ON_B - (int)LCD_OFF_B) * factor);

    for (int row = 0; row < LCD_HEIGHT; row++) {
      // Apply scrolling
      int ramRow;
      if (scrollHt == 0) {
        ramRow = row;
      } else if (row < scrollTop) {
        ramRow = row;  // top fixed area
      } else if (row < scrollTop + scrollHt) {
        ramRow = scrollTop + ((row - scrollTop + scrollSt) % scrollHt);
      } else {
        ramRow = row;  // bottom fixed area
      }
      if (my) ramRow = LCD_HEIGHT - 1 - ramRow;

      for (int pixCol = 0; pixCol < LCD_WIDTH; pixCol++) {
        int effCol = mx ? (LCD_WIDTH - 1 - pixCol) : pixCol;
        int byteCol = effCol / 2 + LCD_COL_OFFSET;
        int pixPos = effCol & 1;

        uint8_t byte = ram[ramRow * LCD_RAM_COLS + byteCol];
        // ST7586S encoding: left pixel = bits[7:6], right pixel = bits[4:3]
        // 11 = on, 00 = off (in mono mode)
        bool pixel = (pixPos == 0) ? (byte & 0xC0) != 0 : (byte & 0x18) != 0;
        if (inv) pixel = !pixel;

        uint8_t r = pixel ? onR : LCD_OFF_R;
        uint8_t g = pixel ? onG : LCD_OFF_G;
        uint8_t b = pixel ? onB : LCD_OFF_B;

        for (int sy = 0; sy < LCD_PIX; sy++)
          for (int sx = 0; sx < LCD_PIX; sx++) {
            int off = ((row * LCD_SCALE + sy) * scaledW + pixCol * LCD_SCALE + sx) * 4;
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

  // Draw LCD image inset by the border
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
  LCD_ST7586S *lcd;
}
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, strong) LCDView *lcdView;
- (instancetype)initWithLCD:(LCD_ST7586S *)l;
@end

@implementation LCDDelegate

- (instancetype)initWithLCD:(LCD_ST7586S *)l {
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
// LCD_ST7586S class implementation
// ---------------------------------------------------------------------------

LCD_ST7586S::LCD_ST7586S()
  : displayEnabled(false), nativeDelegate(nullptr)
{
  reset();
}

void LCD_ST7586S::reset()
{
  memset(ram, 0, sizeof(ram));
  colStart = 0;
  colEnd = LCD_RAM_COLS - 1;
  rowStart = 0;
  rowEnd = LCD_RAM_ROWS - 1;
  curCol = 0;
  curRow = 0;
  scrollStart = 0;
  scrollAreaTop = 0;
  scrollAreaHeight = 0;
  displayEnable = false;
  inverse = false;
  idleMode = false;
  pixelFormat = 2;
  mirrorX = false;
  mirrorY = false;
  vopOffset = 0x28;  // default contrast
  vop = 0x0145;
  state = IDLE;
  currentCmd = 0;
  paramCount = 0;
  paramExpected = 0;
  readDummy = false;
}

wdc816::Byte LCD_ST7586S::getByte(wdc816::Addr offset)
{
  if (offset == 0) {
    // Status read: return 0 (not busy)
    return 0x00;
  } else {
    return readRAM();
  }
}

void LCD_ST7586S::setByte(wdc816::Addr offset, wdc816::Byte data)
{
  if (offset == 0) {
    // Command byte — interrupts any ongoing RAM write/read or param sequence
    executeCommand(data);
  } else {
    // Data byte
    if (state == PARAM) {
      processParam(data);
    } else if (state == RAM_WRITE) {
      writeRAM(data);
    }
    // If IDLE or RAM_READ, data writes are ignored
  }
}

void LCD_ST7586S::executeCommand(uint8_t cmd)
{
  // Any new command interrupts RAM_WRITE/RAM_READ/PARAM state
  state = IDLE;
  currentCmd = cmd;
  paramCount = 0;

  switch (cmd) {
  case 0x01:  // Software Reset
    reset();
    break;
  case 0x11:  // Sleep Out
    break;
  case 0x10:  // Sleep In
    break;
  case 0x20:  // Display Inversion OFF
    inverse = false;
    dirty.store(true, std::memory_order_relaxed);
    break;
  case 0x21:  // Display Inversion ON
    inverse = true;
    dirty.store(true, std::memory_order_relaxed);
    break;
  case 0x28:  // Display OFF
    displayEnable = false;
    dirty.store(true, std::memory_order_relaxed);
    break;
  case 0x29:  // Display ON
    displayEnable = true;
    dirty.store(true, std::memory_order_relaxed);
    break;
  case 0x38:  // Idle Mode OFF
    idleMode = false;
    break;
  case 0x39:  // Idle Mode ON (monochrome)
    idleMode = true;
    break;
  case 0x2A:  // Column Address Set — 4 params
    paramExpected = 4;
    state = PARAM;
    break;
  case 0x2B:  // Row Address Set — 4 params
    paramExpected = 4;
    state = PARAM;
    break;
  case 0x2C:  // Memory Write
    state = RAM_WRITE;
    curCol = colStart;
    curRow = rowStart;
    break;
  case 0x2E:  // Memory Read
    state = RAM_READ;
    curCol = colStart;
    curRow = rowStart;
    readDummy = true;
    break;
  case 0x33:  // Scroll Area Definition — 6 params
    paramExpected = 6;
    state = PARAM;
    break;
  case 0x36:  // Memory Access Control (MADCTL) — 1 param
    paramExpected = 1;
    state = PARAM;
    break;
  case 0x37:  // Vertical Scroll Start — 2 params
    paramExpected = 2;
    state = PARAM;
    break;
  case 0x3A:  // Interface Pixel Format — 1 param
    paramExpected = 1;
    state = PARAM;
    break;
  case 0xB0:  // Duty Setting — 1 param
    paramExpected = 1;
    state = PARAM;
    break;
  case 0xB5:  // N-Line Setting — 1 param
    paramExpected = 1;
    state = PARAM;
    break;
  case 0xC0:  // Vop Setting — 2 params
    paramExpected = 2;
    state = PARAM;
    break;
  case 0xC3:  // BIAS Setting — 1 param
    paramExpected = 1;
    state = PARAM;
    break;
  case 0xC4:  // Booster Setting — 1 param
    paramExpected = 1;
    state = PARAM;
    break;
  case 0xC7:  // Vop Offset — 1 param
    paramExpected = 1;
    state = PARAM;
    break;
  case 0xD0:  // Analog Circuit Setting — 1 param
    paramExpected = 1;
    state = PARAM;
    break;
  default:
    // Unknown command — stay IDLE
    break;
  }
}

void LCD_ST7586S::processParam(uint8_t data)
{
  if (paramCount < 8) {
    paramBuf[paramCount++] = data;
  }
  if (paramCount >= paramExpected) {
    finishCommand();
  }
}

void LCD_ST7586S::finishCommand()
{
  switch (currentCmd) {
  case 0x2A:  // Column Address Set
    colStart = ((uint16_t)paramBuf[0] << 8) | paramBuf[1];
    colEnd   = ((uint16_t)paramBuf[2] << 8) | paramBuf[3];
    break;
  case 0x2B:  // Row Address Set
    rowStart = ((uint16_t)paramBuf[0] << 8) | paramBuf[1];
    rowEnd   = ((uint16_t)paramBuf[2] << 8) | paramBuf[3];
    break;
  case 0x33:  // Scroll Area Definition: TFA(2) + VSA(2) + BFA(2)
    scrollAreaTop    = ((uint16_t)paramBuf[0] << 8) | paramBuf[1];
    scrollAreaHeight = ((uint16_t)paramBuf[2] << 8) | paramBuf[3];
    // BFA = paramBuf[4:5] — bottom fixed area (not stored separately)
    break;
  case 0x36:  // MADCTL
    mirrorY = (paramBuf[0] & 0x80) != 0;
    mirrorX = (paramBuf[0] & 0x40) != 0;
    dirty.store(true, std::memory_order_relaxed);
    break;
  case 0x37:  // Scroll Start
    scrollStart = ((uint16_t)paramBuf[0] << 8) | paramBuf[1];
    dirty.store(true, std::memory_order_relaxed);
    break;
  case 0x3A:  // Pixel Format
    pixelFormat = paramBuf[0];
    break;
  case 0xB0:  // Duty
    // paramBuf[0] = duty value (informational)
    break;
  case 0xB5:  // N-Line
    break;
  case 0xC0:  // Vop
    vop = ((uint16_t)paramBuf[1] << 8) | paramBuf[0];
    break;
  case 0xC3:  // BIAS
    break;
  case 0xC4:  // Booster
    break;
  case 0xC7:  // Vop Offset
    vopOffset = paramBuf[0];
    dirty.store(true, std::memory_order_relaxed);
    break;
  case 0xD0:  // Analog Circuit
    break;
  default:
    break;
  }
  state = IDLE;
}

void LCD_ST7586S::writeRAM(uint8_t data)
{
  if (curRow < LCD_RAM_ROWS && curCol < LCD_RAM_COLS) {
    ram[curRow * LCD_RAM_COLS + curCol] = data;
    dirty.store(true, std::memory_order_relaxed);
  }
  advanceWindowPos();
}

uint8_t LCD_ST7586S::readRAM()
{
  if (state != RAM_READ) return 0x00;

  if (readDummy) {
    readDummy = false;
    // Return dummy byte, don't advance
    if (curRow < LCD_RAM_ROWS && curCol < LCD_RAM_COLS)
      return ram[curRow * LCD_RAM_COLS + curCol];
    return 0x00;
  }

  uint8_t result = 0x00;
  if (curRow < LCD_RAM_ROWS && curCol < LCD_RAM_COLS)
    result = ram[curRow * LCD_RAM_COLS + curCol];
  advanceWindowPos();
  return result;
}

void LCD_ST7586S::advanceWindowPos()
{
  curCol++;
  if (curCol > colEnd) {
    curCol = colStart;
    curRow++;
    if (curRow > rowEnd) {
      curRow = rowStart;  // wrap
    }
  }
}

void LCD_ST7586S::enableDisplay()
{
  displayEnabled = true;
}

void LCD_ST7586S::stopDisplay()
{
#ifdef __APPLE__
  if (displayEnabled) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [NSApp terminate:nil];
    });
  }
#endif
}

void LCD_ST7586S::runCocoa()
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
