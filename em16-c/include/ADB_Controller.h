#ifndef ADB_CONTROLLER_H
#define ADB_CONTROLLER_H

#include <cstdint>
#include "wdc816.h"

// Apple Desktop Bus (ADB) microcontroller emulation
//
// Simplified ADB protocol with two devices:
//   Address 2: Keyboard (handler ID 2)
//   Address 3: Mouse (handler ID 3)
//
// Connected to VIA 6522 Port A (data bus) and Port B (control/status).
// CPU sends commands by writing a command byte to Port A and strobing
// Port B bit 0. Responses are read back from Port A; Port B bit 1
// indicates data available, bit 4 indicates SRQ (service request).
//
// ADB command byte format:
//   Bits 7-4: Device address
//   Bits 3-2: Command (00=Flush, 10=Listen, 11=Talk)
//   Bits 1-0: Register number
//   All bits 3-0 zero: SendReset

class ADB_Controller {
public:
  ADB_Controller();
  void reset();

  // Command interface (called by VIA on ORB strobe)
  void sendCommand(uint8_t cmd);

  // Response reading (called by VIA on IRA read)
  bool hasResponse() const;
  uint8_t readResponse();

  // SRQ status: true if any device has pending data
  bool hasSRQ() const;

  // Input injection from Cocoa event handlers
  void keyDown(uint8_t adbKeyCode);
  void keyUp(uint8_t adbKeyCode);
  void mouseMove(int dx, int dy);
  void mouseButton(bool pressed);

private:
  // Keyboard device (address 2)
  static const int KBD_BUF_SIZE = 32;
  struct {
    uint8_t address = 2;
    uint8_t handlerId = 2;
    uint8_t events[KBD_BUF_SIZE];  // bit7=up, bits6-0=keycode
    int head = 0, tail = 0;
    bool hasData() const { return head != tail; }
  } kbd;

  // Mouse device (address 3)
  struct {
    uint8_t address = 3;
    uint8_t handlerId = 3;
    int dx = 0, dy = 0;
    bool button = false;  // true = pressed
    bool moved = false;
  } mouse;

  // Response buffer (max 2 bytes per ADB response)
  uint8_t responseBuf[2];
  int responseLen = 0;
  int responsePos = 0;

  void processTalk(uint8_t addr, uint8_t reg);
  void processFlush(uint8_t addr);
};

#endif
