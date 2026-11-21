/* EmCocoa.m - the display windows of em16: the 1024 x 768 framebuffer of
   the FPGA SoC (-video), the L28's 800 x 480 RA8889 LCD (-console) and
   the Mini816's TMS9118 (-mini816 -video), its keyboard and joystick.

   The Cocoa event loop runs on the main thread and the CPU, Em16.CpuThread,
   on a second one, as in the C++ em16 (Video.mm, LCD_RA8889.mm), whose
   window code this is. The devices are in Oberon; their state is read
   here through the symbols of their exported variables, and keys and the
   mouse are passed to them through exported procedures. Built without
   ARC. */

#import <Cocoa/Cocoa.h>
#import <GameController/GameController.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <math.h>
#include <unistd.h>

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
void EmPower__Key(int down);
void EmADB__KeyUp(int kc);
void EmADB__MouseMove(int dx, int dy);
void EmADB__MouseButton(int pressed);
void EmCPU__Stop(void);
void Em16__CpuThread(void);
extern uint8_t EmTMS9918__fb[];
extern uint8_t EmTMS9918__pal[];
extern int EmTMS9918__dirty;
extern int EmMini816__joyArrows;
void EmMini816__Key(int col, int row, int down);
void EmMini816__Stop(void);
int EmMini816__CardIn(void);
void em16_press(int b);   /* EmHost_rt.c: the Mini816's buttons */

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
/* F12 is the power key: the SoC's power block's line (EmPower), and ADB's
   power key code, $7F, as the keyboard reports it */
static void key_down(int kc) { if (kc == 0x6F && EmHost__adb) { EmPower__Key(1); EmADB__KeyDown(0x7F); return; } kc = adb_code(kc); if (EmHost__adb) EmADB__KeyDown(kc); else EmVIA__AdbKeyDown(kc); }
static void key_up(int kc) { if (kc == 0x6F && EmHost__adb) { EmPower__Key(0); EmADB__KeyUp(0x7F); return; } kc = adb_code(kc); if (EmHost__adb) EmADB__KeyUp(kc); else EmVIA__AdbKeyUp(kc); }
static void mouse_move(int dx, int dy) { if (EmHost__adb) EmADB__MouseMove(dx, dy); else EmVIA__AdbMouseMove(dx, dy); }
static void mouse_button(int p) { if (EmHost__adb) EmADB__MouseButton(p); else EmVIA__AdbMouseButton(p); }

enum { videoWidth = 1024, videoHeight = 768, videoScale = 1, videoTextBpr = 256, lcdWidth = 800, lcdHeight = 480,
       vdpWidth = 288, vdpHeight = 240, vdpScale = 3 };

enum { modeVideo, modeLCD, modeMini };

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
   or in text mode 128 x 48 cells of character and attribute, 8 x 16 */
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    int bpr = videoWidth / 2;
    if (EmVideo__text) {
        for (int y = 0; y < videoHeight; y++)
            for (int x = 0; x < videoWidth; x++) {
                int cell = (y / 16) * videoTextBpr + (x / 8) * 2;
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

/* --- the Mini816 --- */

/* A macOS key code's place in the Mini816's matrix (docs/em16-profile.md
   section 6), column * 8 + row + 1; 0 none. Host keys by where they are,
   not what they type: Control (either) is the key left of A, Caps Lock
   its Caps, Command its Super, Option its Alt. */
static const unsigned char mini_keys[128] = {
#define K(c, r) ((c) * 8 + (r) + 1)
    [0x35] = K(0, 0), [0x1A] = K(1, 0), [0x13] = K(2, 0), [0x16] = K(3, 0),   /* Esc 7 2 6 */
    [0x15] = K(4, 0), [0x12] = K(5, 0), [0x14] = K(6, 0), [0x17] = K(7, 0),   /* 4 1 3 5 */
    [0x1C] = K(0, 1), [0x19] = K(1, 1), [0x1B] = K(2, 1), [0x1D] = K(3, 1),   /* 8 9 - 0 */
    [0x18] = K(4, 1), [0x33] = K(5, 1), [0x75] = K(5, 1), [0x32] = K(6, 1),   /* = Del (both) ` */
    [0x0A] = K(6, 1), [0x2A] = K(7, 1),                                       /* ISO's section: `, \ */
    [0x20] = K(0, 2), [0x22] = K(1, 2), [0x23] = K(2, 2), [0x21] = K(3, 2),   /* U I P [ */
    [0x1F] = K(4, 2), [0x10] = K(5, 2), [0x11] = K(6, 2), [0x1E] = K(7, 2),   /* O Y T ] */
    [0x30] = K(0, 3), [0x3B] = K(1, 3), [0x3E] = K(1, 3), [0x00] = K(2, 3),   /* Tab Control (both) A */
    [0x01] = K(3, 3), [0x0E] = K(4, 3), [0x0C] = K(5, 3), [0x0D] = K(6, 3),   /* S E Q W */
    [0x0F] = K(7, 3),                                                         /* R */
    [0x26] = K(0, 4), [0x28] = K(1, 4), [0x29] = K(2, 4), [0x02] = K(3, 4),   /* J K ; D */
    [0x25] = K(4, 4), [0x04] = K(5, 4), [0x05] = K(6, 4), [0x03] = K(7, 4),   /* L H G F */
    [0x2E] = K(0, 5), [0x2B] = K(1, 5), [0x2F] = K(2, 5), [0x2C] = K(3, 5),   /* M , . / */
    [0x27] = K(4, 5), [0x24] = K(5, 5), [0x4C] = K(5, 5), [0x3C] = K(6, 5),   /* ' Enter (both) RShift */
    [0x7E] = K(7, 5),                                                         /* Up */
    [0x39] = K(0, 6), [0x38] = K(1, 6), [0x06] = K(2, 6), [0x07] = K(3, 6),   /* Caps LShift Z X */
    [0x08] = K(4, 6), [0x2D] = K(5, 6), [0x0B] = K(6, 6), [0x09] = K(7, 6),   /* C N B V */
    [0x37] = K(0, 7), [0x31] = K(1, 7), [0x3D] = K(2, 7), [0x3A] = K(3, 7),   /* LSuper Space RAlt LAlt */
    [0x36] = K(4, 7), [0x7D] = K(5, 7), [0x7B] = K(6, 7), [0x7C] = K(7, 7),   /* RSuper Down Left Right */
#undef K
};

/* The joystick (column 15: 1 up, 2 down, 4 left, 8 right, 16 fire) from
   the keypad: 8 2 4 6, 7 9 1 3 the diagonals, 5 and 0 fire; with
   -joyarrows from the arrows, and right Option fire, too. */
static int mini_joy(int kc) {
    if (EmMini816__joyArrows)
        switch (kc) {
        case 0x7E: return 1; case 0x7D: return 2; case 0x7B: return 4; case 0x7C: return 8; case 0x3D: return 16;
        }
    switch (kc) {
    case 0x5B: return 1; case 0x54: return 2; case 0x56: return 4; case 0x58: return 8;
    case 0x59: return 5; case 0x5C: return 9; case 0x53: return 6; case 0x55: return 10;
    case 0x57: case 0x52: return 16;
    default: return 0;
    }
}

/* the matrix's keys held by the host's, a count each: two host keys on
   one place, and the keyboard and a game controller on the joystick's */
static unsigned char mini_held[16][8];

static void mini_press(int c, int r, int down) {
    if (down) { if (mini_held[c][r]++ == 0) EmMini816__Key(c, r, 1); }
    else if (mini_held[c][r] && --mini_held[c][r] == 0) EmMini816__Key(c, r, 0);
}

static void mini_joy_bits(int bits, int down) {
    for (int r = 0; r < 5; r++) if (bits & (1 << r)) mini_press(15, r, down);
}

/* a game controller's d-pad or left stick and its A or B: the joystick's */
static int pad_bits(void) {
    int b = 0;
    for (GCController *c in [GCController controllers]) {
        GCExtendedGamepad *g = [c extendedGamepad];
        if (!g) continue;
        if (g.dpad.up.pressed || g.leftThumbstick.yAxis.value > 0.5) b |= 1;
        if (g.dpad.down.pressed || g.leftThumbstick.yAxis.value < -0.5) b |= 2;
        if (g.dpad.left.pressed || g.leftThumbstick.xAxis.value < -0.5) b |= 4;
        if (g.dpad.right.pressed || g.leftThumbstick.xAxis.value > 0.5) b |= 8;
        if (g.buttonA.pressed || g.buttonB.pressed) b |= 16;
    }
    return b;
}

@interface MiniView : NSView {
    uint8_t *rgba;
    BOOL down[128];     /* the host's keys down */
    int pad;            /* the game controller's bits */
    int capsUp;         /* ticks until Caps is let go: a press at each turn of Caps Lock */
}
- (void)refresh;
- (void)releaseKeys;
@end

@implementation MiniView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) rgba = (uint8_t *)calloc(vdpWidth * vdpHeight, 4);
    return self;
}

- (void)dealloc {
    free(rgba);
    [super dealloc];
}

- (void)hostKey:(int)kc down:(BOOL)d {
    int j;
    if (kc < 0 || kc > 127 || down[kc] == d) return;
    down[kc] = d;
    if ((j = mini_joy(kc)) != 0) mini_joy_bits(j, d);
    else if (mini_keys[kc]) mini_press((mini_keys[kc] - 1) / 8, (mini_keys[kc] - 1) % 8, d);
}

- (void)releaseKeys {
    for (int kc = 0; kc < 128; kc++) if (down[kc]) [self hostKey:kc down:NO];
    if (capsUp) { capsUp = 0; mini_press(0, 6, 0); }
}

/* 60 times a second: the frame, Caps let go, the game controller */
- (void)refresh {
    int p;
    if (EmTMS9918__dirty) { [self setNeedsDisplay:YES]; }
    if (capsUp && --capsUp == 0) mini_press(0, 6, 0);
    p = pad_bits();
    if (p != pad) { mini_joy_bits(p & ~pad, 1); mini_joy_bits(pad & ~p, 0); pad = p; }
}

- (BOOL)acceptsFirstResponder { return YES; }

- (void)keyDown:(NSEvent *)event { if (![event isARepeat]) [self hostKey:[event keyCode] down:YES]; }
- (void)keyUp:(NSEvent *)event { [self hostKey:[event keyCode] down:NO]; }

/* the modifiers, each key by its own flag; Caps Lock locks on the Mac,
   so each turn of it is a press of Caps, held a tenth of a second */
- (void)flagsChanged:(NSEvent *)event {
    NSEventModifierFlags flags = [event modifierFlags];
    int kc = [event keyCode];
    switch (kc) {
    case 56: case 60: [self hostKey:kc down:(flags & NSEventModifierFlagShift) != 0]; break;
    case 59: case 62: [self hostKey:kc down:(flags & NSEventModifierFlagControl) != 0]; break;
    case 58: case 61: [self hostKey:kc down:(flags & NSEventModifierFlagOption) != 0]; break;
    case 55: case 54: [self hostKey:kc down:(flags & NSEventModifierFlagCommand) != 0]; break;
    case 57: if (!capsUp) { mini_press(0, 6, 1); capsUp = 6; } break;
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    EmTMS9918__dirty = 0;
    for (int i = 0; i < vdpWidth * vdpHeight; i++) {
        int c = EmTMS9918__fb[i] & 15;
        rgba[i * 4] = EmTMS9918__pal[c * 3]; rgba[i * 4 + 1] = EmTMS9918__pal[c * 3 + 1];
        rgba[i * 4 + 2] = EmTMS9918__pal[c * 3 + 2]; rgba[i * 4 + 3] = 255;
    }
    draw_rgba(self, rgba, vdpWidth, vdpHeight, CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height));
}

@end

/* --- the application --- */

@interface EmDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate> {
    int mode;
    NSWindow *window;
    NSTimer *timer;
    NSView *view;
}
- (instancetype)initForMode:(int)m;
@end

@implementation EmDelegate

- (instancetype)initForMode:(int)m {
    self = [super init];
    if (self) mode = m;
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    int w, h;
    (void)notification;
    if (mode == modeLCD) { w = lcdWidth; h = lcdHeight; }
    else if (mode == modeMini) { w = vdpWidth * vdpScale; h = vdpHeight * vdpScale; }
    else { w = videoWidth * videoScale; h = videoHeight * videoScale; }
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, w, h)
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
        backing:NSBackingStoreBuffered defer:NO];
    [window setTitle:(mode == modeLCD ? @"L28 TFT Display (RA8889)" : mode == modeMini ? @"Mini816" : @"PC16 Display")];
    [window setDelegate:self];
    if (mode == modeLCD) view = [[LCDView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
    else if (mode == modeMini) view = [[MiniView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
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

/* the window put behind another, or closed: the mouse let go, the
   Mini816's keys let go (their key ups go elsewhere) */
- (void)windowDidResignKey:(NSNotification *)notification {
    (void)notification;
    if (mode == modeVideo) [(VideoView *)view releaseMouse];
    if (mode == modeMini) [(MiniView *)view releaseKeys];
}

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    if (mode == modeVideo) [(VideoView *)view releaseMouse];
    [timer invalidate];
    timer = nil;
    if (mode == modeMini) {   /* the run ended, and with it the WAV file (EmSound.Finish) */
        EmMini816__Stop();
        for (int i = 0; i < 200 && !cpu_done; i++) usleep(5000);
    } else EmCPU__Stop();
    [NSApp terminate:nil];
}

/* the Mini816's Machine menu: its buttons, and the SD card */
- (void)nmiButton:(id)sender { (void)sender; em16_press(1); }
- (void)resetButton:(id)sender { (void)sender; em16_press(2); }
- (void)sdCard:(id)sender { (void)sender; em16_press(4); }

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if ([item action] == @selector(sdCard:)) {
        int in = EmMini816__CardIn();
        [item setTitle:(in == 1 ? @"Eject SD Card" : @"Insert SD Card")];
        return in >= 0;
    }
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

@end

static void run_cocoa(int mode) {
    @autoreleasepool {
        NSMenu *bar, *appMenu;
        NSMenuItem *appItem, *quit;
        EmDelegate *d;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        d = [[EmDelegate alloc] initForMode:mode];
        [NSApp setDelegate:d];
        bar = [[NSMenu alloc] init];
        appItem = [[NSMenuItem alloc] init];
        [bar addItem:appItem];
        appMenu = [[NSMenu alloc] init];
        quit = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
        [appMenu addItem:quit];
        [appItem setSubmenu:appMenu];
        if (mode == modeMini) {   /* no key equivalents: Command is the keyboard's Super */
            NSMenuItem *machineItem = [[NSMenuItem alloc] init];
            NSMenu *machine = [[NSMenu alloc] initWithTitle:@"Machine"];
            [[machine addItemWithTitle:@"NMI Button" action:@selector(nmiButton:) keyEquivalent:@""] setTarget:d];
            [[machine addItemWithTitle:@"Reset Button" action:@selector(resetButton:) keyEquivalent:@""] setTarget:d];
            [machine addItem:[NSMenuItem separatorItem]];
            [[machine addItemWithTitle:@"Eject SD Card" action:@selector(sdCard:) keyEquivalent:@""] setTarget:d];
            [machineItem setSubmenu:machine];
            [bar addItem:machineItem];
        }
        [NSApp setMainMenu:bar];
        [NSApp activateIgnoringOtherApps:YES];
        [NSApp run];
    }
}

/* the framebuffer's window: the SoC in real time once at rest (EmSoC.Run) */
void EmHost__RunVideo(void) { EmHost__pace = 1; start_cpu(); run_cocoa(modeVideo); }
void EmHost__RunLCD(void) { start_cpu(); run_cocoa(modeLCD); }
/* the Mini816's VDP: the board keeps to real time itself (EmMini816.Run) */
void EmHost__RunMini(void) { start_cpu(); run_cocoa(modeMini); }

void EmHost__StopDisplay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
}
