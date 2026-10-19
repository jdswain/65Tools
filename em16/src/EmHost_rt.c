/* EmHost_rt.c - the C side of EmHost.Mod.

   Each function here overrides the weak stub of the same name in
   EmHost.Mod. Oberon passes an INTEGER as int, a LONGINT as int64_t, an
   open array as pointer and length, a VAR parameter as a pointer.

   This is the terminal handling of em16's UART_6551.cpp and L28_MCU.cpp,
   its disk image files (WD1793.cpp) and the clock and statistics of
   main.cpp, kept in C because Oberon has no access to them. */

#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>
#include <limits.h>
#include <mach-o/dyld.h>

void EmHost__DrainAll(void);

static struct termios saved_tty;
static int tty_raw = 0;

static void restore_terminal(void) {
    if (tty_raw) {
        tcsetattr(STDIN_FILENO, TCSANOW, &saved_tty);
        tty_raw = 0;
    }
}

static void sigint_handler(int sig) {
    (void)sig;
    if (tty_raw) tcsetattr(STDIN_FILENO, TCSANOW, &saved_tty);
    fprintf(stderr, "\n[em16] Caught SIGINT\n");
    _exit(130);
}

void EmHost__Init(void) {
    signal(SIGPIPE, SIG_IGN);
    signal(SIGINT, sigint_handler);
}

void EmHost__Write(int stream, const char *buf, int len, int n) {
    (void)len;
    fwrite(buf, 1, (size_t)n, stream ? stderr : stdout);
}

void EmHost__Flush(void) {
    fflush(stdout);
}

void EmHost__PutChar(int ch) {
    putchar(ch);
    fflush(stdout);
}

int EmHost__IsTTY(void) {
    return isatty(STDIN_FILENO) ? 1 : 0;
}

void EmHost__NonBlock(void) {
    fcntl(STDIN_FILENO, F_SETFL, fcntl(STDIN_FILENO, F_GETFL) | O_NONBLOCK);
}

/* Raw mode on the first use of the serial port, so that the messages
   before it are shown normally. Control-C still interrupts. */
void EmHost__RawMode(void) {
    struct termios raw;
    if (tty_raw) return;
    tcgetattr(STDIN_FILENO, &saved_tty);
    tty_raw = 1;
    atexit(restore_terminal);
    raw = saved_tty;
    cfmakeraw(&raw);
    raw.c_lflag |= ISIG;
    tcsetattr(STDIN_FILENO, TCSANOW, &raw);
    EmHost__NonBlock();
}

int EmHost__ReadIn(void) {
    unsigned char b;
    return read(STDIN_FILENO, &b, 1) == 1 ? b : -1;
}

void EmHost__Exit(int code) {
    EmHost__DrainAll();
    fflush(stdout);
    exit(code);
}

void EmHost__ExePath(char *s, int len) {
    char raw[PATH_MAX], real[PATH_MAX];
    uint32_t size = sizeof(raw);
    s[0] = 0;
    if (_NSGetExecutablePath(raw, &size) == 0 && realpath(raw, real)) {
        strncpy(s, real, (size_t)len - 1);
        s[len - 1] = 0;
    }
}

int EmHost__FileExists(const char *name, int len) {
    char path[1024];
    struct stat st;
    int n = 0;
    while (n < len && n < (int)sizeof(path) - 1 && name[n]) { path[n] = name[n]; n++; }
    path[n] = 0;
    return stat(path, &st) == 0 ? 1 : 0;
}

/* --- the clock and the closing statistics --- */

static struct timespec start;

void EmHost__ClockStart(void) {
    clock_gettime(CLOCK_MONOTONIC, &start);
}

/* As main.cpp wrote them with cout: the count in hex if cout << hex had
   been written before, the time and frequency with six digits. */
void EmHost__Report(int64_t cycles, int hex) {
    struct timespec end;
    double secs, speed;
    clock_gettime(CLOCK_MONOTONIC, &end);
    EmHost__DrainAll();
    secs = (end.tv_sec + end.tv_nsec / 1000000000.0)
         - (start.tv_sec + start.tv_nsec / 1000000000.0);
    speed = (double)cycles / secs;
    if (hex) printf("\nExecuted %llx in %g Secs", (unsigned long long)cycles, secs);
    else printf("\nExecuted %llu in %g Secs", (unsigned long long)cycles, secs);
    printf("\nOverall CPU Frequency = ");
    if (speed < 1000.0) printf("%g Hz", speed);
    else if ((speed /= 1000.0) < 1000.0) printf("%g KHz", speed);
    else printf("%g Mhz", speed / 1000.0);
    printf("\n");
    fflush(stdout);
}

/* --- disk images --- */

/* 0 and 1 the floppy drives, 2 the SCSI disk */
#define NDISK 3
static FILE *disk[NDISK];

static void cname(const char *name, int len, char *path, int size) {
    int n = 0;
    while (n < len && n < size - 1 && name[n]) { path[n] = name[n]; n++; }
    path[n] = 0;
}

int EmHost__DiskOpen(int drive, const char *name, int len) {
    char path[1024];
    FILE *f;
    int ro = 0;
    if (drive < 0 || drive >= NDISK) return 0;
    if (disk[drive]) { fclose(disk[drive]); disk[drive] = NULL; }
    cname(name, len, path, sizeof(path));
    f = fopen(path, "r+b");
    if (!f) { f = fopen(path, "rb"); ro = 1; }
    if (!f) return 0;
    disk[drive] = f;
    return ro ? 2 : 1;
}

int EmHost__DiskRead(int drive, int offset, uint8_t *buf, int len) {
    if (drive < 0 || drive >= NDISK || !disk[drive]) return 0;
    fseek(disk[drive], offset, SEEK_SET);
    return (int)fread(buf, 1, (size_t)len, disk[drive]);
}

void EmHost__DiskWrite(int drive, int offset, uint8_t *buf, int len) {
    if (drive < 0 || drive >= NDISK || !disk[drive]) return;
    fseek(disk[drive], offset, SEEK_SET);
    fwrite(buf, 1, (size_t)len, disk[drive]);
    fflush(disk[drive]);
}

int EmHost__DiskSize(int drive) {
    long n;
    if (drive < 0 || drive >= NDISK || !disk[drive]) return 0;
    fseek(disk[drive], 0, SEEK_END);
    n = ftell(disk[drive]);
    return n > 0x7FFFFFFF ? 0x7FFFFFFF : (int)n;
}
