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
    int slave_fd;
    char pty_name[128];
    struct termios tty;
    
    // Initialize termios structure for raw mode
    memset(&tty, 0, sizeof(tty));
    tty.c_cflag = CS8;
    
    // Create PTY pair
    int result = openpty(&pty_fd, &slave_fd, pty_name, &tty, nullptr);
    if (result < 0) {
        std::fprintf(stderr, "Failed to create PTY: %s\n", strerror(errno));
        return;
    }
    
    std::printf("Slave PTY: %s\n", pty_name);
    
    // Wait for user input (consider removing this in production)
    std::cout << "Press Enter to continue...";
    std::cin.ignore();
    
    // Configure master PTY for raw mode
    if (tcgetattr(pty_fd, &tty) < 0) {
        std::fprintf(stderr, "Failed to get PTY attributes: %s\n", strerror(errno));
        close(pty_fd);
        close(slave_fd);
        return;
    }
    
    cfmakeraw(&tty);
    
    if (tcsetattr(pty_fd, TCSANOW, &tty) < 0) {
        std::fprintf(stderr, "Failed to set PTY attributes: %s\n", strerror(errno));
        close(pty_fd);
        close(slave_fd);
        return;
    }
    
    // Close slave fd as we only need the master
    close(slave_fd);
    
    statusReg = 0x10;
}

void UART::status() {
    if (statusReg & 0x08) return;
    
    wdc816::Byte buf[1];
    fd_set read_fds;
    
    // Clear and set the file descriptor set for reading only
    FD_ZERO(&read_fds);
    FD_SET(pty_fd, &read_fds);
    
    // Set timeout to 100us
    struct timeval timeout;
    timeout.tv_sec = 0;
    timeout.tv_usec = 100;
    
    // Wait for input to become ready or until timeout
    int bytesReady = select(pty_fd + 1, &read_fds, nullptr, nullptr, &timeout);
    
    if (bytesReady > 0 && FD_ISSET(pty_fd, &read_fds)) {
        ssize_t bytes_read = read(pty_fd, buf, 1);
        if (bytes_read > 0) {
            statusReg |= 0x08;
            receiveDataReg = *buf;
            std::cout << "Byte: 0x" << std::hex << static_cast<unsigned int>(receiveDataReg) << std::endl;
        }
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
