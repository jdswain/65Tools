/* EmHost_rt.c - the C side of EmHost.Mod.

   Each function here overrides the weak stub of the same name in
   EmHost.Mod. Oberon passes an INTEGER as int, a LONGINT as int64_t, an
   open array as pointer and length, a VAR parameter as a pointer.

   This is the terminal handling of em16's UART_6551.cpp and L28_MCU.cpp,
   its disk image files (WD1793.cpp) and the clock and statistics of
   main.cpp, kept in C because Oberon has no access to them. */

#include <errno.h>
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
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

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

/* The Mini816's buttons: SIGUSR1 presses NMI, SIGUSR2 reset; the
   window's menu those and 4, the SD card in or out (em16_press) */
static volatile sig_atomic_t buttons;

void em16_press(int b) { buttons |= b; }

static void sigusr1_handler(int sig) { (void)sig; buttons |= 1; }
static void sigusr2_handler(int sig) { (void)sig; buttons |= 2; }

void EmHost__Init(void) {
    signal(SIGPIPE, SIG_IGN);
    signal(SIGINT, sigint_handler);
    signal(SIGUSR1, sigusr1_handler);
    signal(SIGUSR2, sigusr2_handler);
}

int EmHost__Buttons(void) {
    int b = buttons;
    buttons = 0;
    return b;
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
    s[0] = 0;
#ifdef __APPLE__
    uint32_t size = sizeof(raw);
    if (_NSGetExecutablePath(raw, &size) != 0) return;
#else
    ssize_t n = readlink("/proc/self/exe", raw, sizeof(raw) - 1);
    if (n < 0) return;
    raw[n] = 0;
#endif
    if (realpath(raw, real)) {
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

int64_t EmHost__UnixTime(void) {
    return (int64_t)time(NULL);
}

void EmHost__ClockStart(void) {
    clock_gettime(CLOCK_MONOTONIC, &start);
}

/* Real time: cycles at hz a second against the clock since the first
   call, a sleep while they are ahead. A host that falls behind by more
   than 0.1 s starts again from now, rather than hurrying the guest. */
void EmHost__Pace(int64_t cycles, int64_t hz) {
    static int on;
    static int64_t c0;
    static struct timespec t0;
    struct timespec now;
    double ahead;
    clock_gettime(CLOCK_MONOTONIC, &now);
    if (!on) { on = 1; c0 = cycles; t0 = now; return; }
    ahead = (double)(cycles - c0) / (double)hz
          - ((now.tv_sec - t0.tv_sec) + (now.tv_nsec - t0.tv_nsec) / 1000000000.0);
    if (ahead > 0.001) usleep((useconds_t)(ahead * 1000000.0));
    else if (ahead < -0.1) { c0 = cycles; t0 = now; }
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

/* 0 and 1 the floppy drives, 2 the SCSI disk, 3 the SD card, 4 the
   Mini816's flash (EmFlash) */
#define NDISK 5
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

/* --- serial ports: the Mini816's SCC channels (EmZ85C30) --- */

/* "pty": a pseudo-terminal, its slave kept open (raw) so that the master
   reads no EIO before a terminal opens it; "tcp:PORT": a socket on
   127.0.0.1 that one client at a time connects to. Both non-blocking. */
#define NPORT 2
static int port_fd[NPORT] = {-1, -1}, port_listen[NPORT] = {-1, -1}, port_slave[NPORT] = {-1, -1};
static char port_name[NPORT][256];

int EmHost__PortOpen(int n, const char *spec, int len) {
    char s[256];
    if (n < 0 || n >= NPORT) return 0;
    cname(spec, len, s, sizeof(s));
    if (strcmp(s, "pty") == 0) {
        struct termios t;
        char *name;
        int m = posix_openpt(O_RDWR | O_NOCTTY);
        if (m < 0 || grantpt(m) != 0 || unlockpt(m) != 0 || !(name = ptsname(m))) return 0;
        snprintf(port_name[n], sizeof(port_name[n]), "%s", name);
        port_slave[n] = open(name, O_RDWR | O_NOCTTY);
        if (port_slave[n] >= 0 && tcgetattr(port_slave[n], &t) == 0) {
            cfmakeraw(&t);
            tcsetattr(port_slave[n], TCSANOW, &t);
        }
        fcntl(m, F_SETFL, fcntl(m, F_GETFL) | O_NONBLOCK);
        port_fd[n] = m;
        return 1;
    }
    if (strncmp(s, "tcp:", 4) == 0) {
        struct sockaddr_in a;
        int one = 1, fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0) return 0;
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
        memset(&a, 0, sizeof(a));
        a.sin_family = AF_INET;
        a.sin_port = htons((unsigned short)atoi(s + 4));
        a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        if (bind(fd, (struct sockaddr *)&a, sizeof(a)) != 0 || listen(fd, 1) != 0) { close(fd); return 0; }
        fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
        port_listen[n] = fd;
        snprintf(port_name[n], sizeof(port_name[n]), "127.0.0.1:%d", atoi(s + 4));
        return 1;
    }
    return 0;
}

static void port_accept(int n) {
    if (port_listen[n] >= 0 && port_fd[n] < 0) {
        int one = 1, c = accept(port_listen[n], NULL, NULL);
        if (c >= 0) {
            fcntl(c, F_SETFL, fcntl(c, F_GETFL) | O_NONBLOCK);
            setsockopt(c, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
            port_fd[n] = c;
        }
    }
}

/* a client gone: wait for the next */
static void port_lost(int n) {
    if (port_listen[n] >= 0 && port_fd[n] >= 0) { close(port_fd[n]); port_fd[n] = -1; }
}

int EmHost__PortRead(int n) {
    unsigned char b;
    ssize_t r;
    if (n < 0 || n >= NPORT) return -1;
    port_accept(n);
    if (port_fd[n] < 0) return -1;
    r = read(port_fd[n], &b, 1);
    if (r == 1) return b;
    if (r == 0 || (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)) port_lost(n);
    return -1;
}

void EmHost__PortWrite(int n, int ch) {
    unsigned char b = (unsigned char)ch;
    if (n < 0 || n >= NPORT) return;
    port_accept(n);
    if (port_fd[n] >= 0 && write(port_fd[n], &b, 1) < 0 && errno != EAGAIN && errno != EWOULDBLOCK)
        port_lost(n);
}

int EmHost__PortConnected(int n) {
    if (n < 0 || n >= NPORT) return 0;
    port_accept(n);
    return port_fd[n] >= 0;
}

void EmHost__PortName(int n, char *s, int len) {
    if (len <= 0) return;
    s[0] = 0;
    if (n >= 0 && n < NPORT) { strncpy(s, port_name[n], (size_t)len - 1); s[len - 1] = 0; }
}
