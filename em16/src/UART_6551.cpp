#include "UART_6551.h"

#include <sys/select.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <cstdio>
#include <pty.h>
#include <cerrno>
#include <string.h>
#include <iostream>

void UART::reset()
{
  int slave;
  char buf[128];
  struct termios tty;
  tty.c_iflag = (tcflag_t) 0;
  tty.c_lflag = (tcflag_t) 0;
  tty.c_cflag = CS8;
  tty.c_oflag = (tcflag_t) 0;

  auto e = openpty(&pty_fd, &slave, buf, &tty, nullptr);
  if(0 > e) {
    std::printf("Error: %s\n", strerror(errno));
    return;
  }

  std::printf("Slave PTY: %s\n", buf);
  char c;
  std::cin.get(c);
  statusReg = 0x10;
}

void UART::status() {
  if (statusReg & 0x08) return;
  
  wdc816::Byte buf[1];
    
  fd_set read_fds, write_fds, except_fds;
  FD_ZERO(&read_fds);
  FD_ZERO(&write_fds);
  FD_ZERO(&except_fds);
  FD_SET(pty_fd, &read_fds);
  
  // Set timeout to 100us
  struct timeval timeout;
  timeout.tv_sec = 0;
  timeout.tv_usec = 100;
  
  // Wait for input to become ready or until the time out
  int bytesReady = select(pty_fd + 1, &read_fds, &write_fds, &except_fds, &timeout);

  if ((bytesReady == 1) && (read(pty_fd, buf, 1) != 0)) {
      statusReg |= 0x08;
      receiveDataReg = *buf;
      std::cout << "Byte" << std::hex << receiveDataReg << std::endl;
  }
}

void UART::send(wdc816::Byte data) {
  std::cout << "char: " << data << std::endl;
  int bytes = write(pty_fd, &data, 1);
  if (bytes != 1) {
    fprintf(stderr, "Couldn't write to serial port");
  }
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
