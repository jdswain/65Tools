#include "L28_MCU.h"

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

// Raw terminal state is shared with UART_6551 — declared extern here.
// Only one serial device will actually be active per run.
extern struct termios saved_tty;
extern bool tty_raw;

extern void restore_terminal();

L28_MCU::L28_MCU() {
    if (!isatty(STDIN_FILENO)) {
        use_stdout = true;
        interactive = false;
    } else {
        use_stdout = false;
        interactive = true;
    }
    statusReg = 0x20;  // BE set (tx buffer empty/ready)
}

void L28_MCU::enterRawMode()
{
    if (tty_raw) return;

    tcgetattr(STDIN_FILENO, &saved_tty);
    tty_raw = true;
    atexit(restore_terminal);

    struct termios raw = saved_tty;
    cfmakeraw(&raw);
    raw.c_lflag |= ISIG;   // Keep Ctrl+C = SIGINT
    tcsetattr(STDIN_FILENO, TCSANOW, &raw);

    fcntl(STDIN_FILENO, F_SETFL, fcntl(STDIN_FILENO, F_GETFL) | O_NONBLOCK);
}

void L28_MCU::status() {
    if (statusReg & 0x01) return;  // already have unread data (BF set)
    if (consoleMode) return;       // stdin consumed by pollKeyboard() in console mode

    if (interactive) enterRawMode();

    unsigned char buf;
    ssize_t n = read(STDIN_FILENO, &buf, 1);
    if (n == 1) {
        statusReg |= 0x01;         // BF = data available
        receiveDataReg = buf;
    }
}

void L28_MCU::send(wdc816::Byte data) {
    if (interactive) enterRawMode();
    putchar(data);
    fflush(stdout);
}

wdc816::Byte L28_MCU::getByte(wdc816::Addr ea)
{
    switch (ea & 0x07) {
    case 0x00: // SIB — receive data, clear BF
        status();
        statusReg &= ~0x01;
        return receiveDataReg;
    case 0x01: // SIR
        return sirReg;
    case 0x02: // SMR
        return smrReg;
    case 0x03: // SLCR
        return slcrReg;
    case 0x04: // SSR — status
        status();
        return statusReg;
    case 0x05: // SFR
        return sfrReg;
    case 0x06: // SODL (write-only, return 0)
        return 0;
    case 0x07: // SIDL (write-only, return 0)
        return 0;
    }
    return 0;
}

void L28_MCU::setByte(wdc816::Addr ea, wdc816::Byte data)
{
    switch (ea & 0x07) {
    case 0x00: // SOB — transmit data
        send(data);
        statusReg |= 0x20;     // BE = buffer empty (ready for next)
        break;
    case 0x01: // SIR — interrupt enable
        sirReg = data;
        break;
    case 0x02: // SMR — serial mode
        smrReg = data;
        break;
    case 0x03: // SLCR — line control
        slcrReg = data;
        break;
    case 0x04: // SSR — write clears error bits (also clears SIR7)
        statusReg &= ~(data & 0x1E); // clear OE, PE, FE, BI if written
        sirReg &= 0x7F;              // clear SIR7 (Serial In Status Int Flag)
        break;
    case 0x05: // SFR — serial form
        sfrReg = data;
        break;
    case 0x06: // SODL — divider latch
        sodlReg = data;
        break;
    case 0x07: // SIDL — divider latch
        sidlReg = data;
        break;
    }
}

// Timer B registers: offset 0=TBM($14), 1=TBLL($15), 2=TBUL($16), 3=TBUL($17)
wdc816::Byte L28_MCU::getTimerBByte(wdc816::Addr offset)
{
    switch (offset) {
    case 0x00: // TBM — Timer B Mode
        return tbmReg;
    case 0x01: // TBLL — Timer B Lower Counter (read)
        return tbllReg;
    case 0x02: // TBUL — Timer B Upper Latch (read)
        return tbulReg;
    case 0x03: // TBUL — read also clears TBM7 (interrupt flag)
        tbmReg &= 0x7F;
        return tbulReg;
    }
    return 0;
}

void L28_MCU::setTimerBByte(wdc816::Addr offset, wdc816::Byte data)
{
    switch (offset) {
    case 0x00: // TBM — Timer B Mode
        tbmReg = (tbmReg & 0x80) | (data & 0x67); // bit 7 is read-only flag
        break;
    case 0x01: // TBLL — Timer B Lower Latch
        tbllReg = data;
        break;
    case 0x02: // TBUL — Timer B Upper Latch (write loads counter)
        tbulReg = data;
        break;
    case 0x03: // TBUL — write also clears TBM7
        tbulReg = data;
        tbmReg &= 0x7F;
        break;
    }
}

//==============================================================================
// Port Registers ($0000-$000B)
//------------------------------------------------------------------------------

wdc816::Byte L28_MCU::getPortByte(wdc816::Addr offset)
{
    switch (offset) {
    case 0x00: { // Port A — bit 1 = PA1 (matrix MRT8 modifier-column return)
        wdc816::Byte result = portA & ~0x02;
        if (keyboardEnabled && (portC & keyMatrixPa1))
            result |= 0x02;
        return result;
    }
    case 0x01: return portB;
    case 0x02: // Port C — now a select-output, just echo what ROM wrote
        return portC;
    case 0x03: // Port D — matrix returns MRT0..MRT7
        if (keyboardEnabled) {
            wdc816::Byte result = 0;
            for (int sel = 0; sel < 8; sel++) {
                if (portC & (1 << sel))
                    result |= keyMatrix[sel];
            }
            return result;
        }
        return portD;
    case 0x04: return portADir;
    case 0x05: return portBSel;
    case 0x06: return portCDir;
    case 0x07: return portE;
    case 0x08: return portEDir;  // MOR on read, PortE_Dir on write
    case 0x09: return 0;         // LPR
    case 0x0A: return eirReg;
    case 0x0B: return cirReg;
    }
    return 0;
}

void L28_MCU::setPortByte(wdc816::Addr offset, wdc816::Byte data)
{
    switch (offset) {
    case 0x00: portA = data; break;
    case 0x01: portB = data; break;
    case 0x02: portC = data; break;
    case 0x03: portD = data; break;
    case 0x04: portADir = data; break;
    case 0x05: portBSel = data; break;
    case 0x06: portCDir = data; break;
    case 0x07: portE = data; break;
    case 0x08: portEDir = data; break;
    case 0x09: break; // LPR
    case 0x0A: eirReg = data; break;
    case 0x0B: // CIR — clear interrupt register
        if (!(data & 0x40)) {
            // Bit 6 written as 0: clear PA0 edge flag (keyboard now polled,
            // no IRQ release of matrix bits — done by keyPressTtl instead)
            eirReg &= ~0x40;
        }
        if (!(data & 0x20)) {
            // Bit 5 written as 0: clear PD7 flag
            eirReg &= ~0x20;
        }
        cirReg = data;
        break;
    }
}

//==============================================================================
// Keyboard Matrix Emulation
//------------------------------------------------------------------------------

// row = which PC select drives this key's row (0..7)
// col = which return wire reads this key (0..7 = PD0..PD7, 8 = PA1)
void L28_MCU::pressKey(int row, int col)
{
    if (row < 0 || row >= 8) return;
    if (col >= 0 && col < 8)
        keyMatrix[row] |= (1 << col);
    else if (col == 8)
        keyMatrixPa1 |= (1 << row);
}

void L28_MCU::releaseKey(int row, int col)
{
    if (row < 0 || row >= 8) return;
    if (col >= 0 && col < 8)
        keyMatrix[row] &= ~(1 << col);
    else if (col == 8)
        keyMatrixPa1 &= ~(1 << row);
}

void L28_MCU::releaseAllKeys()
{
    for (int i = 0; i < 8; i++)
        keyMatrix[i] = 0;
    keyMatrixPa1 = 0;
}

bool L28_MCU::irq0Pending() const
{
    return pa0_irq_pending && (eirReg & 0x01);  // bit 0 = PA0 edge detect enable
}

// Reverse lookup: ASCII → {row, col, shift, ctrl}
// Matrix (post-swap): row = PC select bit (0..7), col = return wire
//   col 0..7 = PD0..PD7 (MRT0..MRT7)
//   col 8    = PA1      (MRT8 — modifier column)
struct KeyEntry {
    int8_t row;
    int8_t col;
    bool shift;
    bool ctrl;
};

static const KeyEntry INVALID_KEY = {-1, -1, false, false};

static KeyEntry asciiToKey(unsigned char ch)
{
    // Specials (per keymatrix.md, post-swap layout)
    if (ch == 0x0D) return {5, 7, false, false};  // CR / ENTR
    if (ch == 0x0A) return {5, 7, false, false};  // LF → ENTR
    if (ch == 0x08) return {1, 5, false, false};  // BS
    if (ch == 0x09) return {6, 8, false, false};  // TAB (PA1 column)
    if (ch == 0x1B) return {7, 7, false, false};  // ESC
    if (ch == 0x20) return {6, 7, false, false};  // SPC

    // Ctrl+A..Z (0x01..0x1A): use lowercase letter pos + ctrl flag
    if (ch >= 0x01 && ch <= 0x1A) {
        KeyEntry e = asciiToKey(ch + 0x60);
        e.ctrl = true;
        e.shift = false;
        return e;
    }

    // Lowercase letters (unshifted = lowercase by Forth convention)
    if (ch >= 'a' && ch <= 'z') {
        static const KeyEntry letters[26] = {
            {6, 0, false, false},  // a
            {7, 2, false, false},  // b
            {7, 1, false, false},  // c
            {6, 1, false, false},  // d
            {4, 0, false, false},  // e
            {1, 1, false, false},  // f
            {6, 2, false, false},  // g
            {1, 2, false, false},  // h
            {5, 3, false, false},  // i
            {6, 3, false, false},  // j
            {1, 3, false, false},  // k
            {6, 4, false, false},  // l
            {7, 3, false, false},  // m
            {0, 2, false, false},  // n
            {4, 3, false, false},  // o
            {5, 4, false, false},  // p
            {6, 5, false, false},  // q
            {5, 1, false, false},  // r
            {1, 0, false, false},  // s
            {4, 1, false, false},  // t
            {4, 2, false, false},  // u
            {0, 1, false, false},  // v
            {5, 0, false, false},  // w
            {0, 0, false, false},  // x
            {5, 2, false, false},  // y
            {7, 0, false, false},  // z
        };
        return letters[ch - 'a'];
    }

    // Uppercase letters: shift + lowercase position
    if (ch >= 'A' && ch <= 'Z') {
        KeyEntry e = asciiToKey(ch + 0x20);
        e.shift = true;
        return e;
    }

    // Digits 0-9
    switch (ch) {
    case '0': return {2, 0, false, false};
    case '1': return {7, 5, false, false};
    case '2': return {3, 3, false, false};
    case '3': return {3, 2, false, false};
    case '4': return {3, 1, false, false};
    case '5': return {3, 0, false, false};
    case '6': return {2, 4, false, false};
    case '7': return {2, 3, false, false};
    case '8': return {2, 2, false, false};
    case '9': return {2, 1, false, false};
    }

    // Unshifted punctuation
    switch (ch) {
    case ',':  return {0, 3, false, false};
    case '/':  return {0, 4, false, false};
    case '\\': return {0, 5, false, false};
    case '=':  return {1, 4, false, false};
    case '\'': return {2, 5, false, false};
    case ';':  return {3, 4, false, false};
    case '`':  return {3, 5, false, false};
    case '-':  return {4, 4, false, false};
    case '[':  return {4, 5, false, false};
    case ']':  return {5, 5, false, false};
    case '.':  return {7, 4, false, false};
    }

    // Shifted symbols (per keymatrix.md)
    switch (ch) {
    case '<':  return {0, 3, true, false};   // , shifted
    case '?':  return {0, 4, true, false};   // / shifted
    case '|':  return {0, 5, true, false};   // \ shifted
    case '+':  return {1, 4, true, false};   // = shifted
    case '"':  return {2, 5, true, false};   // ' shifted
    case ':':  return {3, 4, true, false};   // ; shifted
    case '~':  return {3, 5, true, false};   // ` shifted
    case '_':  return {4, 4, true, false};   // - shifted
    case '{':  return {4, 5, true, false};   // [ shifted
    case '}':  return {5, 5, true, false};   // ] shifted
    case '>':  return {7, 4, true, false};   // . shifted
    case ')':  return {2, 0, true, false};   // 0 shifted
    case '(':  return {2, 1, true, false};   // 9 shifted
    case '*':  return {2, 2, true, false};   // 8 shifted
    case '&':  return {2, 3, true, false};   // 7 shifted
    case '^':  return {2, 4, true, false};   // 6 shifted
    case '%':  return {3, 0, true, false};   // 5 shifted
    case '$':  return {3, 1, true, false};   // 4 shifted
    case '#':  return {3, 2, true, false};   // 3 shifted
    case '@':  return {3, 3, true, false};   // 2 shifted
    case '!':  return {7, 5, true, false};   // 1 shifted (assumed)
    }

    return INVALID_KEY;
}

void L28_MCU::injectChar(unsigned char ch)
{
    int w = keyBufWrite.load(std::memory_order_relaxed);
    int next = (w + 1) % KEY_BUF_SIZE;
    if (next == keyBufRead.load(std::memory_order_acquire)) return; // full
    keyBuf[w] = ch;
    keyBufWrite.store(next, std::memory_order_release);
}

void L28_MCU::pollKeyboard()
{
    if (!keyboardEnabled) return;

    // Auto-release a previously-pressed key after the TTL window expires.
    // This gives the ROM scan loop enough cycles to observe the matrix bit
    // without needing host keyUp events.
    if (keyPressTtl > 0) {
        if (--keyPressTtl == 0) releaseAllKeys();
        return;
    }

    unsigned char buf;

    if (cocoaInput) {
        // Read from ring buffer (fed by Cocoa keyDown events)
        int r = keyBufRead.load(std::memory_order_relaxed);
        if (r == keyBufWrite.load(std::memory_order_acquire)) return;
        buf = keyBuf[r];
        keyBufRead.store((r + 1) % KEY_BUF_SIZE, std::memory_order_release);
    } else {
        if (interactive) enterRawMode();
        else fcntl(STDIN_FILENO, F_SETFL, fcntl(STDIN_FILENO, F_GETFL) | O_NONBLOCK);

        ssize_t n = read(STDIN_FILENO, &buf, 1);
        if (n != 1) return;
    }

    KeyEntry e = asciiToKey(buf);
    if (e.row < 0) return;

    pressKey(e.row, e.col);
    if (e.shift) pressKey(0, 8);  // SHFT lives at (MSB0, MRT8)
    if (e.ctrl)  pressKey(1, 8);  // CTRL lives at (MSB1, MRT8)

    keyPressTtl = 4096;  // ~4096 instructions of matrix-hold per keypress
}
