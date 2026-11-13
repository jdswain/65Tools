/* EmAndroid.c - em16 on Android: the FPGA SoC's 1024 x 768 framebuffer
   in a NativeActivity, booted from a SCSI disk with no floppy, keys and
   the mouse to the SoC's ADB, the network em16's own NAT. What
   mac/EmCocoa.m is on the Mac.

   android_main (the native_app_glue's thread) copies the boot ROM and the
   disk out of the APK into the app's files the first time, sets em16's
   arguments and starts Em16 on a thread of its own: its EmHost.RunVideo
   runs the CPU there (Em16.CpuThread) until the guest stops. This thread
   takes the input events and draws the framebuffer when the guest has
   changed it, letterboxed to the screen's shape.

   A physical keyboard's keys go to the guest as an ADB keyboard's codes.
   A mouse is captured (Em16Activity, View.requestPointerCapture) and its
   moves passed as an ADB mouse's, unaccelerated (the guest's
   InputManager accelerates); a mouse not captured, by the difference of
   its positions. A finger is a trackpad: moved, it moves the pointer; a
   tap is a click; held still, the button is held until it is lifted,
   and what it does meanwhile is a drag (a menu pulled down, a window
   moved). Standard output and error go to the log (tag em16). */

#include <android/log.h>
#include <android/native_window.h>
#include <android_native_app_glue.h>
#include <errno.h>
#include <math.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define LOG(...) __android_log_print(ANDROID_LOG_INFO, "em16", __VA_ARGS__)

enum { W = 1024, H = 768, TextBpr = 256 };

/* the Oberon side */
extern uint8_t EmVideo__mem[];
extern uint8_t EmVideo__pal[];
extern int EmVideo__dirty;
extern int EmVideo__text;
extern uint8_t EmVideo__font[];
extern int EmHost__adb;
extern int EmHost__pace;
void EmVIA__AdbKeyDown(int kc);
void EmVIA__AdbKeyUp(int kc);
void EmVIA__AdbMouseMove(int dx, int dy);
void EmVIA__AdbMouseButton(int pressed);
void EmADB__KeyDown(int kc);
void EmADB__KeyUp(int kc);
void EmADB__MouseMove(int dx, int dy);
void EmADB__MouseButton(int pressed);
void EmPower__Key(int down);
void EmCPU__Stop(void);
void Em16__CpuThread(void);
void Em16__init(void);
void oc_set_args(int argc, char **argv);

static volatile int cpuDone;   /* the guest stopped */
static volatile int stopDisplay;

/* ---- EmHost's display, for Em16.Main ---- */

void EmHost__RunVideo(void) { EmHost__pace = 1; Em16__CpuThread(); cpuDone = 1; }
void EmHost__RunLCD(void) { Em16__CpuThread(); cpuDone = 1; }
void EmHost__StopDisplay(void) { stopDisplay = 1; }

/* ---- the guest's keys and mouse ---- */

static void keyDown(int kc) {
    if (kc == 0x6F && EmHost__adb) { EmPower__Key(1); EmADB__KeyDown(0x7F); return; }   /* F12: the power key */
    if (EmHost__adb) EmADB__KeyDown(kc); else EmVIA__AdbKeyDown(kc);
}
static void keyUp(int kc) {
    if (kc == 0x6F && EmHost__adb) { EmPower__Key(0); EmADB__KeyUp(0x7F); return; }
    if (EmHost__adb) EmADB__KeyUp(kc); else EmVIA__AdbKeyUp(kc);
}
static void mouseMove(int dx, int dy) { if (EmHost__adb) EmADB__MouseMove(dx, dy); else EmVIA__AdbMouseMove(dx, dy); }
static void mouseButton(int p) { if (EmHost__adb) EmADB__MouseButton(p); else EmVIA__AdbMouseButton(p); }

/* An Android key code as an ADB keyboard's (an extended one's, for the
   right-hand modifiers); -1 none */
static int adbCode(int k) {
    static const signed char letters[26] = {   /* A .. Z */
        0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26, 0x28, 0x25, 0x2E,
        0x2D, 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11, 0x20, 0x09, 0x0D, 0x07, 0x10, 0x06 };
    static const signed char digits[10] = { 0x1D, 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19 };
    static const signed char fkeys[12] = { 0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F };
    if (k >= AKEYCODE_A && k <= AKEYCODE_Z) return letters[k - AKEYCODE_A];
    if (k >= AKEYCODE_0 && k <= AKEYCODE_9) return digits[k - AKEYCODE_0];
    if (k >= AKEYCODE_F1 && k <= AKEYCODE_F12) return fkeys[k - AKEYCODE_F1];
    switch (k) {
    case AKEYCODE_COMMA: return 0x2B;         case AKEYCODE_PERIOD: return 0x2F;
    case AKEYCODE_ALT_LEFT: return 0x3A;      case AKEYCODE_ALT_RIGHT: return 0x7C;
    case AKEYCODE_SHIFT_LEFT: return 0x38;    case AKEYCODE_SHIFT_RIGHT: return 0x7B;
    case AKEYCODE_CTRL_LEFT: return 0x36;     case AKEYCODE_CTRL_RIGHT: return 0x7D;
    case AKEYCODE_META_LEFT: return 0x37;     case AKEYCODE_META_RIGHT: return 0x37;
    case AKEYCODE_TAB: return 0x30;           case AKEYCODE_SPACE: return 0x31;
    case AKEYCODE_ENTER: return 0x24;         case AKEYCODE_NUMPAD_ENTER: return 0x4C;
    case AKEYCODE_DEL: return 0x33;           case AKEYCODE_FORWARD_DEL: return 0x75;
    case AKEYCODE_GRAVE: return 0x32;         case AKEYCODE_MINUS: return 0x1B;
    case AKEYCODE_EQUALS: return 0x18;        case AKEYCODE_LEFT_BRACKET: return 0x21;
    case AKEYCODE_RIGHT_BRACKET: return 0x1E; case AKEYCODE_BACKSLASH: return 0x2A;
    case AKEYCODE_SEMICOLON: return 0x29;     case AKEYCODE_APOSTROPHE: return 0x27;
    case AKEYCODE_SLASH: return 0x2C;         case AKEYCODE_ESCAPE: return 0x35;
    case AKEYCODE_CAPS_LOCK: return 0x39;     case AKEYCODE_INSERT: return 0x72;
    case AKEYCODE_MOVE_HOME: return 0x73;     case AKEYCODE_MOVE_END: return 0x77;
    case AKEYCODE_PAGE_UP: return 0x74;       case AKEYCODE_PAGE_DOWN: return 0x79;
    case AKEYCODE_DPAD_LEFT: return 0x3B;     case AKEYCODE_DPAD_RIGHT: return 0x3C;
    case AKEYCODE_DPAD_DOWN: return 0x3D;     case AKEYCODE_DPAD_UP: return 0x3E;
    default: return -1;
    }
}

/* ---- the screen ---- */

static ANativeWindow *window;
static int bufW, bufH, offX, offY;   /* the buffer, the screen's shape; the image in it */
static int winW, winH;
static int redraw;
static uint32_t rgbx[W * H];

/* the buffer the screen's shape, the image whole in it and centred */
static void geometry(void) {
    winW = ANativeWindow_getWidth(window); winH = ANativeWindow_getHeight(window);
    if (winW <= 0 || winH <= 0) return;
    if (winW * H > winH * W) { bufH = H; bufW = (int)((long)H * winW / winH); }
    else { bufW = W; bufH = (int)((long)W * winH / winW); }
    offX = (bufW - W) / 2; offY = (bufH - H) / 2;
    ANativeWindow_setBuffersGeometry(window, bufW, bufH, WINDOW_FORMAT_RGBX_8888);
    redraw = 1;
}

/* 4 bits a pixel, the left one in the low nibble, through the palette;
   or 128 x 48 cells of character and attribute, 8 x 16 */
static void render(void) {
    uint32_t pal[16];
    ANativeWindow_Buffer b;
    int x, y, i;
    for (i = 0; i < 16; i++) pal[i] = 0xFF000000u | (uint32_t)EmVideo__pal[i * 3] | (uint32_t)EmVideo__pal[i * 3 + 1] << 8 | (uint32_t)EmVideo__pal[i * 3 + 2] << 16;
    if (EmVideo__text) {
        for (y = 0; y < H; y++)
            for (x = 0; x < W; x++) {
                int cell = (y / 16) * TextBpr + (x / 8) * 2;
                int ch = EmVideo__mem[cell], at = EmVideo__mem[cell + 1];
                int on = (EmVideo__font[ch * 16 + y % 16] >> (7 - x % 8)) & 1;
                rgbx[y * W + x] = pal[on ? (at & 0x0F) : (at >> 4)];
            }
    } else {
        for (y = 0; y < H; y++)
            for (x = 0; x < W / 2; x++) {
                uint8_t v = EmVideo__mem[y * (W / 2) + x];
                rgbx[y * W + x * 2] = pal[v & 0x0F]; rgbx[y * W + x * 2 + 1] = pal[v >> 4];
            }
    }
    if (ANativeWindow_lock(window, &b, NULL) != 0) return;
    if (b.width == bufW && b.height == bufH) {
        uint32_t *p = b.bits;
        for (y = 0; y < bufH; y++) {
            uint32_t *row = p + (size_t)y * (size_t)b.stride;
            if (y < offY || y >= offY + H) { memset(row, 0, (size_t)bufW * 4); continue; }
            if (offX) { memset(row, 0, (size_t)offX * 4); memset(row + offX + W, 0, (size_t)(bufW - offX - W) * 4); }
            memcpy(row + offX, rgbx + (size_t)(y - offY) * W, W * 4);
        }
    }
    ANativeWindow_unlockAndPost(window);
}

/* ---- input ---- */

static int lastButtons;
static float lastX, lastY, fx, fy;
static int haveLast;
static float downX, downY; static int64_t downAt; static int moved;
static int fingerDown, held;          /* a finger on the screen; held still long enough: the button down */
static int64_t releaseAt;             /* a tap's click: the button let go then (0 none) */

static int64_t nowMs(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000; }

/* screen pixels as the guest's */
static float scale(void) { return winW > 0 ? (float)bufW / (float)winW : 1.0f; }

static void move(float dx, float dy) {
    int ix, iy;
    fx += dx; fy += dy; ix = (int)fx; iy = (int)fy; fx -= (float)ix; fy -= (float)iy;
    if (ix || iy) mouseMove(ix, iy);
}

static int32_t onInput(struct android_app *app, AInputEvent *e) {
    (void)app;
    if (AInputEvent_getType(e) == AINPUT_EVENT_TYPE_KEY) {
        int k = AKeyEvent_getKeyCode(e), a = AKeyEvent_getAction(e), c = adbCode(k);
        if (k == AKEYCODE_BACK) return 1;   /* not to leave the machine by accident */
        if (c < 0) return 0;
        if (a == AKEY_EVENT_ACTION_DOWN && AKeyEvent_getRepeatCount(e) == 0) keyDown(c);
        else if (a == AKEY_EVENT_ACTION_UP) keyUp(c);
        return 1;
    }
    if (AInputEvent_getType(e) == AINPUT_EVENT_TYPE_MOTION) {
        int32_t src = AInputEvent_getSource(e), a = AMotionEvent_getAction(e) & AMOTION_EVENT_ACTION_MASK;
        float x = AMotionEvent_getX(e, 0), y = AMotionEvent_getY(e, 0);
        if ((src & AINPUT_SOURCE_MOUSE_RELATIVE) == AINPUT_SOURCE_MOUSE_RELATIVE || (src & AINPUT_SOURCE_MOUSE) == AINPUT_SOURCE_MOUSE) {
            int buttons = AMotionEvent_getButtonState(e) & AMOTION_EVENT_BUTTON_PRIMARY;
            if ((src & AINPUT_SOURCE_MOUSE_RELATIVE) == AINPUT_SOURCE_MOUSE_RELATIVE) {
                if (a == AMOTION_EVENT_ACTION_MOVE || a == AMOTION_EVENT_ACTION_HOVER_MOVE) move(x, y);   /* captured: deltas */
            } else {
                if (haveLast) move((x - lastX) * scale(), (y - lastY) * scale());
                lastX = x; lastY = y; haveLast = 1;
                if (a == AMOTION_EVENT_ACTION_HOVER_EXIT) haveLast = 0;
            }
            if (buttons != lastButtons) { mouseButton(buttons != 0); lastButtons = buttons; }
            return 1;
        }
        if ((src & AINPUT_SOURCE_TOUCHSCREEN) == AINPUT_SOURCE_TOUCHSCREEN) {
            if (a == AMOTION_EVENT_ACTION_DOWN) { lastX = downX = x; lastY = downY = y; downAt = nowMs(); moved = 0; fingerDown = 1; held = 0; }
            else if (a == AMOTION_EVENT_ACTION_MOVE) {
                if (fabsf(x - downX) > 12 || fabsf(y - downY) > 12) moved = 1;
                if (moved || held) move((x - lastX) * scale(), (y - lastY) * scale());
                lastX = x; lastY = y;
            } else if (a == AMOTION_EVENT_ACTION_UP || a == AMOTION_EVENT_ACTION_CANCEL) {
                fingerDown = 0;
                if (held) { mouseButton(0); held = 0; }
                else if (!moved && a == AMOTION_EVENT_ACTION_UP) { mouseButton(1); releaseAt = nowMs() + 120; }
            }
            return 1;
        }
    }
    return 0;
}

static void onCmd(struct android_app *app, int32_t cmd) {
    switch (cmd) {
    case APP_CMD_INIT_WINDOW: window = app->window; if (window) geometry(); break;
    case APP_CMD_WINDOW_RESIZED: case APP_CMD_CONFIG_CHANGED: if (window) geometry(); break;
    case APP_CMD_TERM_WINDOW: window = NULL; break;
    case APP_CMD_LOST_FOCUS: if (lastButtons) { mouseButton(0); lastButtons = 0; } haveLast = 0; break;
    default: break;
    }
}

/* a finger held still: the button down; a tap's click: let go */
static void touchTimers(void) {
    int64_t t = nowMs();
    if (fingerDown && !moved && !held && t - downAt > 400) { held = 1; mouseButton(1); }
    if (releaseAt && t >= releaseAt) { mouseButton(0); releaseAt = 0; }
}

/* ---- the files, the log and the CPU's thread ---- */

/* the APK's asset name copied to path; if keep, not if it is there already */
static int copyAsset(AAssetManager *am, const char *name, const char *path, int keep) {
    struct stat st;
    AAsset *a;
    FILE *f;
    char buf[65536], tmp[512];
    int n;
    if (keep && stat(path, &st) == 0 && st.st_size > 0) return 1;
    a = AAssetManager_open(am, name, AASSET_MODE_STREAMING);
    if (!a) { LOG("no asset %s", name); return 0; }
    snprintf(tmp, sizeof tmp, "%s.new", path);
    f = fopen(tmp, "wb");
    if (!f) { AAsset_close(a); return 0; }
    while ((n = AAsset_read(a, buf, sizeof buf)) > 0) fwrite(buf, 1, (size_t)n, f);
    fclose(f); AAsset_close(a);
    rename(tmp, path);
    LOG("%s copied to %s", name, path);
    return 1;
}

static int logPipe[2];
static void *logger(void *arg) {
    char line[512];
    FILE *f = fdopen(logPipe[0], "r");
    (void)arg;
    while (f && fgets(line, sizeof line, f)) __android_log_write(ANDROID_LOG_INFO, "em16", line);
    return NULL;
}

static char rom[512], disk[512], font[512];
static char *argv[] = { "em16", "-fpga", "-video", "-bootrom", rom, "-scsi", disk, "-net", "nat", "-font", font, NULL };
static int argc = 9;

static void *cpu(void *arg) {
    (void)arg;
    oc_set_args(argc, argv);
    Em16__init();   /* Em16.Main: the machine made, then RunVideo until the guest stops */
    cpuDone = 1;
    return NULL;
}

void android_main(struct android_app *app) {
    pthread_t t;
    int events;
    struct android_poll_source *source;
    const char *dir = app->activity->internalDataPath;
    setvbuf(stdout, NULL, _IOLBF, 0); setvbuf(stderr, NULL, _IONBF, 0);
    if (pipe(logPipe) == 0) { dup2(logPipe[1], 1); dup2(logPipe[1], 2); pthread_create(&t, NULL, logger, NULL); pthread_detach(t); }
    app->onAppCmd = onCmd;
    app->onInputEvent = onInput;
    mkdir(dir, 0700);
    snprintf(rom, sizeof rom, "%s/boot.rom", dir);
    snprintf(disk, sizeof disk, "%s/scsidisk.img", dir);
    snprintf(font, sizeof font, "%s/font_st8x16.hex", dir);
    if (copyAsset(app->activity->assetManager, "font_st8x16.hex", font, 0)) argc = 11;   /* the SoC's text mode's */
    if (!copyAsset(app->activity->assetManager, "boot.rom", rom, 0) ||
        !copyAsset(app->activity->assetManager, "scsidisk.img", disk, 1)) { ANativeActivity_finish(app->activity); return; }
    if (chdir(dir) != 0) LOG("chdir %s: %d", dir, errno);
    pthread_create(&t, NULL, cpu, NULL); pthread_detach(t);
    while (!app->destroyRequested) {
        while (ALooper_pollOnce(16, NULL, &events, (void **)&source) >= 0) {
            if (source) source->process(app, source);
            if (app->destroyRequested) break;
        }
        touchTimers();
        if (window && (EmVideo__dirty || redraw)) { EmVideo__dirty = 0; redraw = 0; render(); }
        if ((cpuDone || stopDisplay) && !app->destroyRequested) { ANativeActivity_finish(app->activity); cpuDone = stopDisplay = 0; }
    }
    /* the activity gone: the machine with it, so that the next start is a
       new process, Em16's modules initialised afresh (the disk's writes
       are the file's already) */
    EmCPU__Stop();
    exit(0);
}
