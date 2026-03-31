#include "Video.h"
#include "emu816.h"

#include <string.h>
#include <iostream>

#ifdef __APPLE__
#import <Cocoa/Cocoa.h>

// 4-bit per pixel palette: standard VGA 16 colors
static const uint8_t palette[16][3] = {
  {  0,   0,   0},   //  0 = Black
  {  0,   0, 170},   //  1 = Dark Blue
  {  0, 170,   0},   //  2 = Dark Green
  {  0, 170, 170},   //  3 = Dark Cyan
  {170,   0,   0},   //  4 = Dark Red
  {170,   0, 170},   //  5 = Dark Magenta
  {170,  85,   0},   //  6 = Brown
  {170, 170, 170},   //  7 = Light Gray
  { 85,  85,  85},   //  8 = Dark Gray
  { 85,  85, 255},   //  9 = Light Blue
  { 85, 255,  85},   // 10 = Light Green
  { 85, 255, 255},   // 11 = Light Cyan
  {255,  85,  85},   // 12 = Light Red
  {255,  85, 255},   // 13 = Light Magenta
  {255, 255,  85},   // 14 = Yellow
  {255, 255, 255}    // 15 = White
};

// ---------------------------------------------------------------------------
// VideoView — custom NSView that renders the 4bpp framebuffer at 2x scale
// ---------------------------------------------------------------------------

@interface VideoView : NSView {
  Video *video;
  uint8_t *rgbaBuffer;
  int videoWidth;
  int videoHeight;
}
- (instancetype)initWithFrame:(NSRect)frame video:(Video *)v;
- (void)refresh;
- (BOOL)acceptsFirstResponder;
- (void)keyDown:(NSEvent *)event;
- (void)keyUp:(NSEvent *)event;
- (void)flagsChanged:(NSEvent *)event;
- (void)mouseDown:(NSEvent *)event;
- (void)mouseUp:(NSEvent *)event;
- (void)mouseMoved:(NSEvent *)event;
- (void)mouseDragged:(NSEvent *)event;
@end

@implementation VideoView

- (instancetype)initWithFrame:(NSRect)frame video:(Video *)v {
  self = [super initWithFrame:frame];
  if (self) {
    video = v;
    videoWidth = v->getWidth();
    videoHeight = v->getHeight();
    rgbaBuffer = (uint8_t *)calloc(videoWidth * videoHeight, 4);

    // Tracking area for mouseMoved events
    NSTrackingArea *ta = [[NSTrackingArea alloc]
      initWithRect:self.bounds
      options:(NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect)
      owner:self userInfo:nil];
    [self addTrackingArea:ta];
  }
  return self;
}

- (void)dealloc {
  free(rgbaBuffer);
  [super dealloc];
}

- (void)refresh {
  if (video->dirty.exchange(false)) {
    [self setNeedsDisplay:YES];
  }
}

- (BOOL)acceptsFirstResponder {
  return YES;
}

- (void)keyDown:(NSEvent *)event {
  mem816::getVIA().adbKeyDown([event keyCode]);
}

- (void)keyUp:(NSEvent *)event {
  mem816::getVIA().adbKeyUp([event keyCode]);
}

- (void)flagsChanged:(NSEvent *)event {
  // Track previous modifier state to detect press vs release
  static NSEventModifierFlags prevFlags = 0;
  NSEventModifierFlags flags = [event modifierFlags];
  uint8_t kc = [event keyCode];

  // If the modifier's flag bit is now set and wasn't before, it's a press
  // Common modifier keycodes: Shift=56/60, Control=59/62, Option=58/61, Command=55/54
  bool isPress = false;
  switch (kc) {
  case 56: case 60: // Shift
    isPress = (flags & NSEventModifierFlagShift) != 0;
    break;
  case 59: case 62: // Control
    isPress = (flags & NSEventModifierFlagControl) != 0;
    break;
  case 58: case 61: // Option
    isPress = (flags & NSEventModifierFlagOption) != 0;
    break;
  case 55: case 54: // Command
    isPress = (flags & NSEventModifierFlagCommand) != 0;
    break;
  case 57: // Caps Lock
    isPress = (flags & NSEventModifierFlagCapsLock) != 0;
    break;
  default:
    isPress = (flags & NSEventModifierFlagDeviceIndependentFlagsMask) >
              (prevFlags & NSEventModifierFlagDeviceIndependentFlagsMask);
    break;
  }

  if (isPress)
    mem816::getVIA().adbKeyDown(kc);
  else
    mem816::getVIA().adbKeyUp(kc);

  prevFlags = flags;
}

- (void)mouseDown:(NSEvent *)event {
  (void)event;
  mem816::getVIA().adbMouseButton(true);
}

- (void)mouseUp:(NSEvent *)event {
  (void)event;
  mem816::getVIA().adbMouseButton(false);
}

- (void)mouseMoved:(NSEvent *)event {
  int dx = (int)[event deltaX];
  int dy = (int)[event deltaY];
  if (dx != 0 || dy != 0)
    mem816::getVIA().adbMouseMove(dx, dy);
}

- (void)mouseDragged:(NSEvent *)event {
  int dx = (int)[event deltaX];
  int dy = (int)[event deltaY];
  if (dx != 0 || dy != 0)
    mem816::getVIA().adbMouseMove(dx, dy);
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  uint8_t *mem = video->getMemory();
  int bpr = videoWidth / 2; // bytes per video row (320)

  // Convert 4bpp packed pixels to RGBA
  for (int y = 0; y < videoHeight; y++) {
    for (int x = 0; x < bpr; x++) {
      uint8_t byte = mem[y * bpr + x];
      // High nibble = left pixel (even x), low nibble = right pixel (odd x)
      int ci0 = (byte >> 4) & 0x0F;
      int ci1 = byte & 0x0F;
      int off0 = (y * videoWidth + x * 2) * 4;
      int off1 = off0 + 4;
      rgbaBuffer[off0 + 0] = palette[ci0][0]; // R
      rgbaBuffer[off0 + 1] = palette[ci0][1]; // G
      rgbaBuffer[off0 + 2] = palette[ci0][2]; // B
      rgbaBuffer[off0 + 3] = 255;             // A
      rgbaBuffer[off1 + 0] = palette[ci1][0]; // R
      rgbaBuffer[off1 + 1] = palette[ci1][1]; // G
      rgbaBuffer[off1 + 2] = palette[ci1][2]; // B
      rgbaBuffer[off1 + 3] = 255;             // A
    }
  }

  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGContextRef bmpCtx = CGBitmapContextCreate(
    rgbaBuffer, videoWidth, videoHeight, 8, videoWidth * 4, cs,
    kCGImageAlphaNoneSkipLast);
  CGImageRef image = CGBitmapContextCreateImage(bmpCtx);

  // Draw into the view, flipping so row 0 is at the top
  CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
  CGContextSaveGState(ctx);
  CGContextTranslateCTM(ctx, 0, self.bounds.size.height);
  CGContextScaleCTM(ctx, 1.0, -1.0);
  CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
  CGContextDrawImage(ctx,
    CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height),
    image);
  CGContextRestoreGState(ctx);

  CGImageRelease(image);
  CGContextRelease(bmpCtx);
  CGColorSpaceRelease(cs);
}

@end

// ---------------------------------------------------------------------------
// EmulatorDelegate — manages the NSWindow and refresh timer
// ---------------------------------------------------------------------------

@interface EmulatorDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate> {
  Video *video;
}
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, strong) VideoView *videoView;
- (instancetype)initWithVideo:(Video *)v;
@end

@implementation EmulatorDelegate

- (instancetype)initWithVideo:(Video *)v {
  self = [super init];
  if (self) {
    video = v;
  }
  return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  (void)notification;

  int winW = VIDEO_WIDTH * VIDEO_SCALE;
  int winH = VIDEO_HEIGHT * VIDEO_SCALE;

  NSRect frame = NSMakeRect(100, 100, winW, winH);
  self.window = [[NSWindow alloc]
    initWithContentRect:frame
    styleMask:(NSWindowStyleMaskTitled |
               NSWindowStyleMaskClosable |
               NSWindowStyleMaskMiniaturizable)
    backing:NSBackingStoreBuffered
    defer:NO];
  [self.window setTitle:@"PC16 Display"];
  [self.window setDelegate:self];

  self.videoView = [[VideoView alloc]
    initWithFrame:NSMakeRect(0, 0, winW, winH)
    video:video];
  [self.window setContentView:self.videoView];
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
  [self.videoView refresh];
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
// Video class implementation
// ---------------------------------------------------------------------------

Video::Video()
  : _w(VIDEO_WIDTH), _h(VIDEO_HEIGHT), displayEnabled(false), nativeDelegate(nullptr)
{
  memset(mem, 0, sizeof(mem));
}

Video::~Video()
{
}

void Video::reset()
{
}

wdc816::Byte Video::getByte(wdc816::Addr ea)
{
  if (ea < VIDEO_MEM_SIZE)
    return mem[ea];
  return 0;
}

void Video::setByte(wdc816::Addr ea, wdc816::Byte data)
{
  if (ea < VIDEO_MEM_SIZE) {
    mem[ea] = data;
    dirty.store(true, std::memory_order_relaxed);
  }
}

void Video::run()
{
  // Simple step loop — used by both headless and Cocoa modes
  while (!emu816::isStopped()) {
    emu816::step();
  }
}

void Video::enableDisplay()
{
  displayEnabled = true;
}

void Video::stopDisplay()
{
#ifdef __APPLE__
  if (displayEnabled) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [NSApp terminate:nil];
    });
  }
#endif
}

void Video::runCocoa()
{
#ifdef __APPLE__
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    EmulatorDelegate *delegate = [[EmulatorDelegate alloc] initWithVideo:this];
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
