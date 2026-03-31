#include "UART_6551.h"

#include <sys/select.h>
#include <sys/time.h>
#include <sys/types.h>
#include <fcntl.h>
#include <unistd.h>
#include <cstdio>
#include <cstdlib>
#include <termios.h>
#include <cerrno>
#include <signal.h>

struct termios saved_tty;
bool tty_raw = false;

static void sigint_handler(int) {
    // Restore terminal before exiting
    if (tty_raw) {
        tcsetattr(STDIN_FILENO, TCSANOW, &saved_tty);
    }
    std::fprintf(stderr, "\n[em16] Caught SIGINT\n");
    _exit(130);
}

void restore_terminal() {
    if (tty_raw) {
        tcsetattr(STDIN_FILENO, TCSANOW, &saved_tty);
        tty_raw = false;
    }
}

UART::UART() {
    signal(SIGPIPE, SIG_IGN);
    signal(SIGINT, sigint_handler);

    if (!isatty(STDIN_FILENO)) {
        // Piped mode: output via stdout, no input
        use_stdout = true;
        interactive = false;
    } else {
        // Interactive mode: stdin/stdout in raw mode (deferred)
        use_stdout = false;
        interactive = true;
    }
    statusReg = 0x10;
}

// Switch stdin to raw mode on first UART I/O, so that
// earlier diagnostic messages (printf/cout) display normally.
void UART::enterRawMode()
{
    if (tty_raw) return;

    tcgetattr(STDIN_FILENO, &saved_tty);
    tty_raw = true;
    atexit(restore_terminal);

    struct termios raw = saved_tty;
    cfmakeraw(&raw);
    raw.c_lflag |= ISIG;   // Keep Ctrl+C = SIGINT
    tcsetattr(STDIN_FILENO, TCSANOW, &raw);

    // Non-blocking so polling doesn't stall the emulated CPU
    fcntl(STDIN_FILENO, F_SETFL, fcntl(STDIN_FILENO, F_GETFL) | O_NONBLOCK);
}

void UART::reset()
{
    statusReg = 0x10;
}

void UART::status() {
    if (statusReg & 0x08) return;  // already have unread data

    if (interactive) enterRawMode();

    unsigned char buf;
    ssize_t n = read(STDIN_FILENO, &buf, 1);
    if (n == 1) {
        statusReg |= 0x08;
        receiveDataReg = buf;
        std::fprintf(stderr, "[UART] recv $%02X '%c'\n", buf, (buf >= 0x20 && buf < 0x7f) ? buf : '.');
    }
}

void UART::send(wdc816::Byte data) {
    if (interactive) enterRawMode();
    putchar(data);
    fflush(stdout);
}

wdc816::Byte UART::getByte(wdc816::Addr ea)
{
  switch (ea & 0x03) {
  case 0x00: // Data
    status();
    statusReg &= ~0x08;
    return receiveDataReg;
  case 0x01: // Status
    status();
    return statusReg;
  case 0x02: // Command
    return commandReg;
  case 0x03: // Control
    return controlReg;
  }
  return 0;
}

void UART::setByte(wdc816::Addr ea, wdc816::Byte data)
{
  switch (ea & 0x03) {
  case 0x00: // Data
    send(data);
    statusReg |= 0x10;
    break;
  case 0x01: // Programmed Reset
    reset();
    break;
  case 0x02: // Command
    commandReg = data;
    break;
  case 0x03: // Control
    controlReg = data;
    break;
  }
}
