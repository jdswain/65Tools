#include "ADB_Controller.h"
#include <cstring>
#include <algorithm>

// ADB command field extraction
#define ADB_ADDR(cmd)  (((cmd) >> 4) & 0x0F)
#define ADB_CMD(cmd)   (((cmd) >> 2) & 0x03)
#define ADB_REG(cmd)   ((cmd) & 0x03)

// Command codes (bits 3-2)
#define ADB_CMD_FLUSH  0  // 00
#define ADB_CMD_LISTEN 2  // 10
#define ADB_CMD_TALK   3  // 11

ADB_Controller::ADB_Controller()
{
  reset();
}

void ADB_Controller::reset()
{
  kbd.head = kbd.tail = 0;
  kbd.address = 2;
  kbd.handlerId = 2;
  mouse.dx = mouse.dy = 0;
  mouse.button = false;
  mouse.moved = false;
  mouse.address = 3;
  mouse.handlerId = 3;
  responseLen = responsePos = 0;
}

void ADB_Controller::sendCommand(uint8_t cmd)
{
  // Clear any previous response
  responseLen = responsePos = 0;

  // SendReset: bits 3-0 all zero
  if ((cmd & 0x0F) == 0) {
    reset();
    return;
  }

  uint8_t addr = ADB_ADDR(cmd);
  uint8_t cmdCode = ADB_CMD(cmd);
  uint8_t reg = ADB_REG(cmd);

  switch (cmdCode) {
  case ADB_CMD_FLUSH:
    processFlush(addr);
    break;
  case ADB_CMD_TALK:
    processTalk(addr, reg);
    break;
  case ADB_CMD_LISTEN:
    // Listen not implemented yet (would receive data from CPU)
    break;
  default:
    break;
  }
}

void ADB_Controller::processTalk(uint8_t addr, uint8_t reg)
{
  if (addr == kbd.address) {
    if (reg == 0) {
      // Register 0: key event data
      // Format: [key1_status:1|keycode1:7] [key2_status:1|keycode2:7]
      if (kbd.hasData()) {
        responseBuf[0] = kbd.events[kbd.head];
        kbd.head = (kbd.head + 1) % KBD_BUF_SIZE;
        if (kbd.hasData()) {
          responseBuf[1] = kbd.events[kbd.head];
          kbd.head = (kbd.head + 1) % KBD_BUF_SIZE;
        } else {
          responseBuf[1] = 0xFF;  // No second key
        }
        responseLen = 2;
        responsePos = 0;
      }
    } else if (reg == 3) {
      // Register 3: device address + handler ID
      // [0:1|exc:1|srq:1|0:1|addr:4] [handler_id:8]
      uint8_t srqBit = kbd.hasData() ? 0x20 : 0x00;
      responseBuf[0] = srqBit | (kbd.address & 0x0F);
      responseBuf[1] = kbd.handlerId;
      responseLen = 2;
      responsePos = 0;
    }
  } else if (addr == mouse.address) {
    if (reg == 0) {
      // Register 0: mouse data
      // [button:1|dy:7] [1:1|dx:7]
      if (mouse.moved || mouse.button) {
        // Clamp deltas to 7-bit signed range (-64..+63)
        int dy = std::max(-64, std::min(63, mouse.dy));
        int dx = std::max(-64, std::min(63, mouse.dx));

        // Button: 0=pressed, 1=released (inverted)
        uint8_t btnBit = mouse.button ? 0x00 : 0x80;
        responseBuf[0] = btnBit | (dy & 0x7F);
        responseBuf[1] = 0x80 | (dx & 0x7F);  // Bit 7 always 1

        // Clear accumulated deltas
        mouse.dx = 0;
        mouse.dy = 0;
        mouse.moved = false;

        responseLen = 2;
        responsePos = 0;
      }
    } else if (reg == 3) {
      // Register 3: device address + handler ID
      uint8_t srqBit = (mouse.moved || mouse.button) ? 0x20 : 0x00;
      responseBuf[0] = srqBit | (mouse.address & 0x0F);
      responseBuf[1] = mouse.handlerId;
      responseLen = 2;
      responsePos = 0;
    }
  }
}

void ADB_Controller::processFlush(uint8_t addr)
{
  if (addr == kbd.address) {
    kbd.head = kbd.tail = 0;
  } else if (addr == mouse.address) {
    mouse.dx = mouse.dy = 0;
    mouse.moved = false;
  }
}

bool ADB_Controller::hasResponse() const
{
  return responsePos < responseLen;
}

uint8_t ADB_Controller::readResponse()
{
  if (responsePos < responseLen) {
    return responseBuf[responsePos++];
  }
  return 0xFF;
}

bool ADB_Controller::hasSRQ() const
{
  return kbd.hasData() || mouse.moved;
}

void ADB_Controller::keyDown(uint8_t adbKeyCode)
{
  // Key down: bit 7 = 0, bits 6-0 = keycode
  int next = (kbd.tail + 1) % KBD_BUF_SIZE;
  if (next != kbd.head) {
    kbd.events[kbd.tail] = adbKeyCode & 0x7F;
    kbd.tail = next;
  }
}

void ADB_Controller::keyUp(uint8_t adbKeyCode)
{
  // Key up: bit 7 = 1, bits 6-0 = keycode
  int next = (kbd.tail + 1) % KBD_BUF_SIZE;
  if (next != kbd.head) {
    kbd.events[kbd.tail] = 0x80 | (adbKeyCode & 0x7F);
    kbd.tail = next;
  }
}

void ADB_Controller::mouseMove(int dx, int dy)
{
  mouse.dx += dx;
  mouse.dy += dy;
  mouse.moved = true;
}

void ADB_Controller::mouseButton(bool pressed)
{
  mouse.button = pressed;
  mouse.moved = true;  // Trigger SRQ so CPU polls
}
