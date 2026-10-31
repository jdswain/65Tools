/* EmCocoa.m - the display windows of em16: the 640 x 480 framebuffer of
   the FPGA SoC (-video) and the L28's 800 x 480 RA8889 LCD (-console).

   The Cocoa event loop runs on the main thread and the CPU, Em16.CpuThread,
   on a second one, as in the C++ em16 (Video.mm, LCD_RA8889.mm), whose
   window code this is. The devices are in Oberon; their state is read
   here through the symbols of their exported variables, and keys and the
   mouse are passed to them through exported procedures. Built without
   ARC. */

#import <Cocoa/Cocoa.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <math.h>

/* the Oberon side */
extern uint8_t EmVideo__mem[];
extern uint8_t EmVideo__pal[];
extern int EmVideo__dirty;
extern int EmVideo__text;
extern uint8_t EmVideo__font[];
extern int EmHost__adb;
extern int EmHost__pace;
extern uint8_t EmLCD__fb[];
extern int EmLCD__dirty, EmLCD__pwmDuty, EmLCD__cursorVisible, EmLCD__cursorBlink;
extern int EmLCD__blinkRate, EmLCD__textCursorX, EmLCD__textCursorY, EmLCD__fontW, EmLCD__fontH;
void EmVIA__AdbKeyDown(int kc);
void EmVIA__AdbKeyUp(int kc);
void EmVIA__AdbMouseMove(int dx, int dy);
void EmVIA__AdbMouseButton(int pressed);
void EmL28__InjectChar(int ch);
void EmADB__KeyDown(int kc);
void EmADB__KeyUp(int kc);
void EmADB__MouseMove(int dx, int dy);
void EmADB__MouseButton(int pressed);
void EmCPU__Stop(void);
void Em16__CpuThread(void);

/* A macOS key code as an ADB keyboard sends it. macOS's virtual key
   codes are ADB's but for these: Control, the arrows, and the right-hand
   modifiers (an extended ADB keyboard's; ADB has one Command, $37). */
static int adb_code(int kc) {
    switch (kc) {
    case 0x3B: return 0x36;   /* Control */
    case 0x3E: return 0x7D;   /* right Control */
    case 0x3C: return 0x7B;   /* right Shift */
    case 0x3D: return 0x7C;   /* right Option */
    case 0x36: return 0x37;   /* right Command: Command */
    case 0x7B: return 0x3B;   /* Left */
    case 0x7C: return 0x3C;   /* Right */
    case 0x7D: return 0x3D;   /* Down */
    case 0x7E: return 0x3E;   /* Up */
    default: return kc;
    }
}

/* keys and the mouse go to the VIA's ADB, or with -fpga to the SoC's,
   in ADB's key codes */
static void key_down(int kc) { kc = adb_code(kc); if (EmHost__adb) EmADB__KeyDown(kc); else EmVIA__AdbKeyDown(kc); }
static void key_up(int kc) { kc = adb_code(kc); if (EmHost__adb) EmADB__KeyUp(kc); else EmVIA__AdbKeyUp(kc); }
static void mouse_move(int dx, int dy) { if (EmHost__adb) EmADB__MouseMove(dx, dy); else EmVIA__AdbMouseMove(dx, dy); }
static void mouse_button(int p) { if (EmHost__adb) EmADB__MouseButton(p); else EmVIA__AdbMouseButton(p); }

enum { videoWidth = 640, videoHeight = 480, videoScale = 2, lcdWidth = 800, lcdHeight = 480 };

static volatile int cpu_done;   /* the CPU thread has returned: the guest stopped */

static void *cpu_main(void *arg) {
    (void)arg;
    Em16__CpuThread();
    cpu_done = 1;
    return NULL;
}

static void start_cpu(void) {
    pthread_t t;
    pthread_create(&t, NULL, cpu_main, NULL);
    pthread_detach(t);
}

/* An RGBA buffer drawn into the view, row 0 at the top (a bitmap context's
   first row is its image's top, and the view is not flipped), its pixels
   not smoothed when scaled. */
static void draw_rgba(NSView *view, uint8_t *rgba, int w, int h, NSRect dest) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef bmp = CGBitmapContextCreate(rgba, w, h, 8, w * 4, cs, (CGBitmapInfo)kCGImageAlphaNoneSkipLast);
    CGImageRef image = CGBitmapContextCreateImage(bmp);
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    CGContextSaveGState(ctx);
    CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
    CGContextDrawImage(ctx, dest, image);
    CGContextRestoreGState(ctx);
    CGImageRelease(image);
    CGContextRelease(bmp);
    CGColorSpaceRelease(cs);
}

/* --- the framebuffer --- */

@interface VideoView : NSView {
    uint8_t *rgba;
    BOOL captured;      /* the mouse is the guest's: the host's arrow hidden and held */
    double fx, fy;      /* the moves' fractions of a pixel, still to send */
}
- (void)refresh;
- (void)releaseMouse;
@end

@implementation VideoView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        rgba = (uint8_t *)calloc(videoWidth * videoHeight, 4);
        NSTrackingArea *ta = [[NSTrackingArea alloc] initWithRect:self.bounds
            options:(NSTrackingMouseMoved | NSTrackingActiveAlways | NSTrackingInVisibleRect)
            owner:self userInfo:nil];
        [self addTrackingArea:ta];
    }
    return self;
}

- (void)dealloc {
    free(rgba);
    [super dealloc];
}

/* The window's title: how to capture the mouse, or to let it go */
- (void)title {
    [[self window] setTitle:(captured ? @"PC16 Display - Control-Command releases the mouse"
                                      : @"PC16 Display - click to capture the mouse")];
}

/* The mouse captured, as a virtual machine's window takes it: the host's
   arrow hidden and held at the middle of the view (the pointer and the
   mouse dissociated), so that it cannot leave the window while the
   guest's pointer moves; the mouse's moves all the guest's. */
- (void)captureMouse {
    NSRect r;
    CGFloat top;
    if (captured || cpu_done) return;
    r = [[self window] convertRectToScreen:[self convertRect:self.bounds toView:nil]];
    top = [[[NSScreen screens] objectAtIndex:0] frame].size.height;   /* CG's y is down from the main screen's top */
    CGWarpMouseCursorPosition(CGPointMake(NSMidX(r), top - NSMidY(r)));
    CGAssociateMouseAndMouseCursorPosition(false);
    [NSCursor hide];
    captured = YES; fx = 0; fy = 0;
    [self title];
}

- (void)releaseMouse {
    if (!captured) return;
    CGAssociateMouseAndMouseCursorPosition(true);
    [NSCursor unhide];
    captured = NO;
    [self title];
}

- (void)refresh {
    if (EmVideo__dirty) { EmVideo__dirty = 0; [self setNeedsDisplay:YES]; }
    if (cpu_done) [self releaseMouse];   /* the guest stopped: nothing reads the mouse */
}

- (void)viewDidMoveToWindow { [self title]; }

- (BOOL)acceptsFirstResponder { return YES; }

/* the click that brings the window forward captures the mouse too */
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }

/* a key held: one down, as an ADB keyboard sends; macOS's repeats ignored */
- (void)keyDown:(NSEvent *)event { if (![event isARepeat]) key_down([event keyCode]); }
- (void)keyUp:(NSEvent *)event { key_up([event keyCode]); }

/* The modifier keys, to the guest; Control and Command held together
   let the mouse go. */
- (void)flagsChanged:(NSEvent *)event {
    static NSEventModifierFlags prev = 0;
    NSEventModifierFlags flags = [event modifierFlags];
    int kc = [event keyCode];
    BOOL press;
    switch (kc) {
    case 56: case 60: press = (flags & NSEventModifierFlagShift) != 0; break;
    case 59: case 62: press = (flags & NSEventModifierFlagControl) != 0; break;
    case 58: case 61: press = (flags & NSEventModifierFlagOption) != 0; break;
    case 55: case 54: press = (flags & NSEventModifierFlagCommand) != 0; break;
    case 57: press = (flags & NSEventModifierFlagCapsLock) != 0; break;
    default:
        press = (flags & NSEventModifierFlagDeviceIndependentFlagsMask) >
                (prev & NSEventModifierFlagDeviceIndependentFlagsMask);
    }
    if (press) key_down(kc); else key_up(kc);
    prev = flags;
    if ((flags & NSEventModifierFlagControl) && (flags & NSEventModifierFlagCommand)) [self releaseMouse];
}

/* A click captures the mouse, and is not the guest's; then the button
   is the guest's. */
- (void)mouseDown:(NSEvent *)event {
    (void)event;
    if (captured) mouse_button(1); else [self captureMouse];
}
- (void)mouseUp:(NSEvent *)event { (void)event; if (captured) mouse_button(0); }

/* While captured, the mouse's moves: the event's deltas, the device's
   own (macOS's acceleration not in them; the guest's InputManager
   accelerates, as for an ADB mouse), a point to a pixel, the fractions
   carried over. */
- (void)mouseMoved:(NSEvent *)event {
    int dx, dy;
    if (!captured) return;
    fx += [event deltaX]; fy += [event deltaY];
    dx = (int)fx; dy = (int)fy;
    fx -= dx; fy -= dy;
    if (dx || dy) mouse_move(dx, dy);
}

- (void)mouseDragged:(NSEvent *)event { [self mouseMoved:event]; }

/* 4 bits a pixel, the left one in the low nibble, through the palette;
   or in text mode 80 x 30 cells of character and attribute, 8 x 16 */
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    int bpr = videoWidth / 2;
    if (EmVideo__text) {
        for (int y = 0; y < videoHeight; y++)
            for (int x = 0; x < videoWidth; x++) {
                int cell = (y / 16) * 160 + (x / 8) * 2;
                int ch = EmVideo__mem[cell], at = EmVideo__mem[cell + 1];
                int on = (EmVideo__font[ch * 16 + y % 16] >> (7 - x % 8)) & 1;
                int c = on ? (at & 0x0F) : (at >> 4);
                uint8_t *p = rgba + (y * videoWidth + x) * 4;
                p[0] = EmVideo__pal[c * 3]; p[1] = EmVideo__pal[c * 3 + 1]; p[2] = EmVideo__pal[c * 3 + 2]; p[3] = 255;
            }
    } else
    for (int y = 0; y < videoHeight; y++)
        for (int x = 0; x < bpr; x++) {
            uint8_t b = EmVideo__mem[y * bpr + x];
            int c0 = b & 0x0F, c1 = (b >> 4) & 0x0F;
            uint8_t *p = rgba + (y * videoWidth + x * 2) * 4;
            p[0] = EmVideo__pal[c0 * 3]; p[1] = EmVideo__pal[c0 * 3 + 1]; p[2] = EmVideo__pal[c0 * 3 + 2]; p[3] = 255;
            p[4] = EmVideo__pal[c1 * 3]; p[5] = EmVideo__pal[c1 * 3 + 1]; p[6] = EmVideo__pal[c1 * 3 + 2]; p[7] = 255;
        }
    draw_rgba(self, rgba, videoWidth, videoHeight,
              CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height));
}

@end

/* --- the LCD --- */

@interface LCDView : NSView {
    uint8_t *rgba;
    int blinkCounter;
    BOOL blinkState;
}
- (void)refresh;
@end

@implementation LCDView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        rgba = (uint8_t *)calloc(lcdWidth * lcdHeight, 4);
        blinkCounter = 0; blinkState = YES;
    }
    return self;
}

- (void)dealloc {
    free(rgba);
    [super dealloc];
}

- (void)refresh {
    int rate;
    if (EmLCD__dirty) { EmLCD__dirty = 0; [self setNeedsDisplay:YES]; }
    blinkCounter++;
    rate = EmLCD__blinkRate ? EmLCD__blinkRate : 30;
    if (blinkCounter >= rate) {
        blinkCounter = 0;
        blinkState = !blinkState;
        if (EmLCD__cursorVisible && EmLCD__cursorBlink) [self setNeedsDisplay:YES];
    }
}

- (BOOL)acceptsFirstResponder { return YES; }

/* Keys go to the L28's keyboard matrix as ASCII. */
- (void)keyDown:(NSEvent *)event {
    NSString *raw = [event charactersIgnoringModifiers];
    unichar base;
    NSUInteger flags;
    unsigned char ch;
    if ([raw length] == 0) return;
    base = [raw characterAtIndex:0];
    if (base >= 0xF700) return;
    flags = [event modifierFlags];
    if ((flags & NSEventModifierFlagControl) && base >= 'a' && base <= 'z') ch = base - 'a' + 1;
    else if (base == '\r' || base == '\n') ch = 0x0D;
    else if (base == 0x7F || base == 0x08) ch = 0x08;
    else if (base == 0x1B) ch = 0x1B;
    else if (base == 0x09) ch = 0x09;
    else if (flags & NSEventModifierFlagShift) {
        NSString *chars = [event characters];
        unichar sch;
        if ([chars length] == 0) return;
        sch = [chars characterAtIndex:0];
        if (sch >= 0x80) return;
        ch = (unsigned char)sch;
    } else {
        if (base >= 0x80) return;
        ch = (unsigned char)base;
    }
    EmL28__InjectChar(ch);
}

/* RGB565 through the backlight, and the cursor inverted */
- (void)drawRect:(NSRect)dirtyRect {
    float bright = EmLCD__pwmDuty / 255.0f;
    CGContextRef ctx;
    (void)dirtyRect;
    for (int row = 0; row < lcdHeight; row++)
        for (int col = 0; col < lcdWidth; col++) {
            int i = (row * lcdWidth + col) * 2;
            uint16_t c = EmLCD__fb[i] | (EmLCD__fb[i + 1] << 8);
            uint8_t *p = rgba + (row * lcdWidth + col) * 4;
            p[0] = (uint8_t)((((c >> 11) & 0x1F) << 3) * bright);
            p[1] = (uint8_t)((((c >> 5) & 0x3F) << 2) * bright);
            p[2] = (uint8_t)(((c & 0x1F) << 3) * bright);
            p[3] = 255;
        }
    if (EmLCD__cursorVisible && (!EmLCD__cursorBlink || blinkState)) {
        int cx = EmLCD__textCursorX, cy = EmLCD__textCursorY;
        for (int dy = 0; dy < EmLCD__fontH && cy + dy < lcdHeight; dy++)
            for (int dx = 0; dx < EmLCD__fontW && cx + dx < lcdWidth; dx++) {
                uint8_t *p = rgba + ((cy + dy) * lcdWidth + cx + dx) * 4;
                p[0] ^= 0xFF; p[1] ^= 0xFF; p[2] ^= 0xFF;
            }
    }
    ctx = [[NSGraphicsContext currentContext] CGContext];
    CGContextSetRGBFillColor(ctx, 0, 0, 0, 1.0);
    CGContextFillRect(ctx, self.bounds);
    draw_rgba(self, rgba, lcdWidth, lcdHeight, CGRectMake(0, 0, lcdWidth, lcdHeight));
}

@end

/* --- the application --- */

@interface EmDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate> {
    BOOL lcd;
    NSWindow *window;
    NSTimer *timer;
    NSView *view;
}
- (instancetype)initForLCD:(BOOL)l;
@end

@implementation EmDelegate

- (instancetype)initForLCD:(BOOL)l {
    self = [super init];
    if (self) lcd = l;
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    int w, h;
    (void)notification;
    if (lcd) { w = lcdWidth; h = lcdHeight; }
    else { w = videoWidth * videoScale; h = videoHeight * videoScale; }
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, w, h)
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
        backing:NSBackingStoreBuffered defer:NO];
    [window setTitle:(lcd ? @"L28 TFT Display (RA8889)" : @"PC16 Display")];
    [window setDelegate:self];
    if (lcd) view = [[LCDView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
    else view = [[VideoView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
    [window setContentView:view];
    [window makeKeyAndOrderFront:nil];
    timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0 target:self
        selector:@selector(timerFired:) userInfo:nil repeats:YES];
}

- (void)timerFired:(NSTimer *)t {
    (void)t;
    [(id)view refresh];
}

/* the window put behind another, or closed: the mouse let go */
- (void)windowDidResignKey:(NSNotification *)notification {
    (void)notification;
    if (!lcd) [(VideoView *)view releaseMouse];
}

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    if (!lcd) [(VideoView *)view releaseMouse];
    [timer invalidate];
    timer = nil;
    EmCPU__Stop();
    [NSApp terminate:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

@end

static void run_cocoa(BOOL lcd) {
    @autoreleasepool {
        NSMenu *bar, *appMenu;
        NSMenuItem *appItem, *quit;
        EmDelegate *d;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        d = [[EmDelegate alloc] initForLCD:lcd];
        [NSApp setDelegate:d];
        bar = [[NSMenu alloc] init];
        appItem = [[NSMenuItem alloc] init];
        [bar addItem:appItem];
        appMenu = [[NSMenu alloc] init];
        quit = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
        [appMenu addItem:quit];
        [appItem setSubmenu:appMenu];
        [NSApp setMainMenu:bar];
        [NSApp activateIgnoringOtherApps:YES];
        [NSApp run];
    }
}

/* the framebuffer's window: the SoC in real time once at rest (EmSoC.Run) */
void EmHost__RunVideo(void) { EmHost__pace = 1; start_cpu(); run_cocoa(NO); }
void EmHost__RunLCD(void) { start_cpu(); run_cocoa(YES); }

void EmHost__StopDisplay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
}
