#include "Video.h"
#include "emu816.h"

#include <string.h>
#include <iostream>

#ifdef __APPLE__
#import <Cocoa/Cocoa.h>

// 2-bit per pixel palette: black, dark gray, light gray, white
static const uint8_t palette[4][3] = {
  {0,   0,   0},     // 00 = black
  {85,  85,  85},    // 01 = dark gray
  {170, 170, 170},   // 10 = light gray
  {255, 255, 255}    // 11 = white
};

// ---------------------------------------------------------------------------
// VideoView — custom NSView that renders the 2bpp framebuffer at 2x scale
// ---------------------------------------------------------------------------

@interface VideoView : NSView {
  Video *video;
  uint8_t *rgbaBuffer;
  int videoWidth;
  int videoHeight;
}
- (instancetype)initWithFrame:(NSRect)frame video:(Video *)v;
- (void)refresh;
@end

@implementation VideoView

- (instancetype)initWithFrame:(NSRect)frame video:(Video *)v {
  self = [super initWithFrame:frame];
  if (self) {
    video = v;
    videoWidth = v->getWidth();
    videoHeight = v->getHeight();
    rgbaBuffer = (uint8_t *)calloc(videoWidth * videoHeight, 4);
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

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  uint8_t *mem = video->getMemory();
  int bpr = videoWidth / 4; // bytes per video row (160)

  // Convert 2bpp packed pixels to RGBA
  for (int y = 0; y < videoHeight; y++) {
    for (int x = 0; x < bpr; x++) {
      uint8_t byte = mem[y * bpr + x];
      for (int p = 0; p < 4; p++) {
        int ci = (byte >> (6 - p * 2)) & 0x03;
        int off = (y * videoWidth + x * 4 + p) * 4;
        rgbaBuffer[off + 0] = palette[ci][0]; // R
        rgbaBuffer[off + 1] = palette[ci][1]; // G
        rgbaBuffer[off + 2] = palette[ci][2]; // B
        rgbaBuffer[off + 3] = 255;            // A
      }
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
