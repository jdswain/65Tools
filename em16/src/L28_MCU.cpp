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
    case 0x00: return portA;
    case 0x01: return portB;
    case 0x02: // Port C — keyboard column read
        if (keyboardEnabled) {
            wdc816::Byte result = 0;
            for (int row = 0; row < 8; row++) {
                if (portD & (1 << row))
                    result |= keyMatrix[row];
            }
            return result;
        }
        return portC;
    case 0x03: return portD;
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
            // Bit 6 written as 0: clear PA0 edge flag
            eirReg &= ~0x40;
            pa0_irq_pending = false;
            releaseAllKeys();
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

void L28_MCU::pressKey(int row, int col)
{
    if (row >= 0 && row < 8 && col >= 0 && col < 8)
        keyMatrix[row] |= (1 << col);
}

void L28_MCU::releaseKey(int row, int col)
{
    if (row >= 0 && row < 8 && col >= 0 && col < 8)
        keyMatrix[row] &= ~(1 << col);
}

void L28_MCU::releaseAllKeys()
{
    for (int i = 0; i < 8; i++)
        keyMatrix[i] = 0;
}

bool L28_MCU::irq0Pending() const
{
    return pa0_irq_pending && (eirReg & 0x01);  // bit 0 = PA0 edge detect enable
}

// Reverse lookup: ASCII → {row, col, shift, ctrl}
struct KeyEntry {
    int8_t row;
    int8_t col;
    bool shift;
    bool ctrl;
};

static const KeyEntry INVALID_KEY = {-1, -1, false, false};

static KeyEntry asciiToKey(unsigned char ch)
{
    // Control characters
    if (ch == 0x0D) return {3, 4, false, false};  // CR
    if (ch == 0x08) return {1, 4, false, false};  // BS
    if (ch == 0x09) return {1, 5, false, false};  // TAB
    if (ch == 0x1B) return {6, 5, false, false};  // ESC
    if (ch == 0x7F) return {6, 6, false, false};  // DEL
    if (ch == 0x20) return {6, 4, false, false};  // SPACE
    if (ch == 0x0A) return {3, 4, false, false};  // LF → CR

    // Control chars (Ctrl+A..Z = 0x01..0x1A)
    if (ch >= 0x01 && ch <= 0x1A) {
        // Map to the letter's position + ctrl flag
        // A=0x01 → row 3 col 5, B=0x02 → row 5 col 4, etc.
        return asciiToKey(ch + 0x40);  // get letter position
        // Actually need to return with ctrl flag — do it properly:
    }

    // Uppercase letters (unshifted = uppercase in Forth convention)
    if (ch >= 'A' && ch <= 'Z') {
        // Layout:  Q W E R T Y U I  (row 2)
        //          O P [ ] CR A S D  (row 3, A at col 5)
        //          F G H J K L ; '  (row 4)
        //          Z X C V B N M ,  (row 5)
        static const KeyEntry letters[26] = {
            {3, 5, false, false},  // A
            {5, 4, false, false},  // B
            {5, 2, false, false},  // C
            {3, 7, false, false},  // D
            {2, 2, false, false},  // E
            {4, 0, false, false},  // F
            {4, 1, false, false},  // G
            {4, 2, false, false},  // H
            {2, 7, false, false},  // I
            {4, 3, false, false},  // J
            {4, 4, false, false},  // K
            {4, 5, false, false},  // L
            {5, 6, false, false},  // M
            {5, 5, false, false},  // N
            {3, 0, false, false},  // O
            {3, 1, false, false},  // P
            {2, 0, false, false},  // Q
            {2, 3, false, false},  // R
            {3, 6, false, false},  // S
            {2, 4, false, false},  // T
            {2, 6, false, false},  // U
            {5, 3, false, false},  // V
            {2, 1, false, false},  // W
            {5, 1, false, false},  // X
            {2, 5, false, false},  // Y
            {5, 0, false, false},  // Z
        };
        return letters[ch - 'A'];
    }

    // Lowercase letters (shifted = lowercase in Forth convention)
    if (ch >= 'a' && ch <= 'z') {
        KeyEntry e = asciiToKey(ch - 0x20);  // get uppercase position
        e.shift = true;
        return e;
    }

    // Digits
    if (ch >= '1' && ch <= '8') return {0, (int8_t)(ch - '1'), false, false};
    if (ch == '9') return {1, 0, false, false};
    if (ch == '0') return {1, 1, false, false};

    // Unshifted punctuation
    switch (ch) {
    case '-':  return {1, 2, false, false};
    case '=':  return {1, 3, false, false};
    case '.':  return {1, 6, false, false};
    case '/':  return {1, 7, false, false};
    case '[':  return {3, 2, false, false};
    case ']':  return {3, 3, false, false};
    case ';':  return {4, 6, false, false};
    case '\'': return {4, 7, false, false};
    case ',':  return {5, 7, false, false};
    case '`':  return {6, 2, false, false};
    case '\\': return {6, 3, false, false};
    }

    // Shifted symbols
    switch (ch) {
    case '!':  return {0, 0, true, false};
    case '@':  return {0, 1, true, false};
    case '#':  return {0, 2, true, false};
    case '$':  return {0, 3, true, false};
    case '%':  return {0, 4, true, false};
    case '^':  return {0, 5, true, false};
    case '&':  return {0, 6, true, false};
    case '*':  return {0, 7, true, false};
    case '(':  return {1, 0, true, false};
    case ')':  return {1, 1, true, false};
    case '_':  return {1, 2, true, false};
    case '+':  return {1, 3, true, false};
    case '>':  return {1, 6, true, false};
    case '?':  return {1, 7, true, false};
    case '{':  return {3, 2, true, false};
    case '}':  return {3, 3, true, false};
    case ':':  return {4, 6, true, false};
    case '"':  return {4, 7, true, false};
    case '<':  return {5, 7, true, false};
    case '~':  return {6, 2, true, false};
    case '|':  return {6, 3, true, false};
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
    if (pa0_irq_pending) return;  // don't stack up keys

    unsigned char buf;

    if (cocoaInput) {
        // Read from ring buffer (fed by Cocoa keyDown events)
        int r = keyBufRead.load(std::memory_order_relaxed);
        if (r == keyBufWrite.load(std::memory_order_acquire)) return;
        buf = keyBuf[r];
        keyBufRead.store((r + 1) % KEY_BUF_SIZE, std::memory_order_release);
    } else {
        // Read from stdin
        if (interactive) enterRawMode();
        else fcntl(STDIN_FILENO, F_SETFL, fcntl(STDIN_FILENO, F_GETFL) | O_NONBLOCK);

        ssize_t n = read(STDIN_FILENO, &buf, 1);
        if (n != 1) return;
    }

    // Handle Ctrl+A..Z (0x01..0x1A) specially
    if (buf >= 0x01 && buf <= 0x1A) {
        KeyEntry e = asciiToKey(buf + 0x40);  // get letter position
        if (e.row < 0) return;
        pressKey(e.row, e.col);
        pressKey(6, 1);  // CTRL
        pa0_irq_pending = true;
        eirReg |= 0x40;  // set PA0 edge flag (bit 6)
        return;
    }

    KeyEntry e = asciiToKey(buf);
    if (e.row < 0) return;

    pressKey(e.row, e.col);
    if (e.shift) pressKey(6, 0);  // SHIFT
    if (e.ctrl)  pressKey(6, 1);  // CTRL

    pa0_irq_pending = true;
    eirReg |= 0x40;  // set PA0 edge flag (bit 6)
}
