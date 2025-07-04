#include "R6501.h"

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
#include <poll.h>

/*
R6501::xR6501()
{
  char nmbuf[128];
  struct termios tty;
  tty.c_iflag = (tcflag_t) 0;
  tty.c_lflag = (tcflag_t) 0;
  tty.c_cflag = CS8;
  tty.c_oflag = (tcflag_t) 0;

  auto e = openpty(&pty_fd, &slave_fd, nmbuf, &tty, nullptr);
  if(0 > e) {
    std::printf("Error: %s\n", strerror(errno));
    return;
  } else {
	std::printf("PTY FD: %d\n", pty_fd);
  }

  // fcntl(pty_fd, F_SETFL, O_NONBLOCK);
  
  std::printf("Slave PTY: %s\n", nmbuf);
  char c;
  std::cin.get(c);
}
*/
R6501::~R6501()
{
}

void R6501::reset()
{
  //7 XMTR under-run
  //6 XMTR data reg empty
  //5 End of transmission
  //4 Wake-up
  //3 Frame error
  //2 Parity error
  //1 RCVR over-run
  //0 RCVR data reg full
  statusReg = 0x40;
}

R6501::R6501()
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

void R6501::status() {
  // if (statusReg & 0x08) return;
    
    wdc816::Byte buf[1];
    fd_set read_fds;
    
    // Clear and set the file descriptor set for reading only
    FD_ZERO(&read_fds);
    FD_SET(pty_fd, &read_fds);
    
    // Set timeout to 100us
    struct timeval timeout;
    timeout.tv_sec = 0;
    timeout.tv_usec = 100;
    
	statusReg = 0x40;

  // Wait for input to become ready or until timeout
    int bytesReady = select(pty_fd + 1, &read_fds, nullptr, nullptr, &timeout);
    
    if (bytesReady > 0 && FD_ISSET(pty_fd, &read_fds)) {
        ssize_t bytes_read = read(pty_fd, buf, 1);
        if (bytes_read > 0) {
            statusReg |= 0x01;
            receiveDataReg = *buf;
            std::cout << "Byte: 0x" << std::hex << static_cast<unsigned int>(receiveDataReg) << std::endl;
        }
    }
}
/*
void R6501::status() {
  // if (statusReg & 0x08) return;

  wdc816::Byte buf[1];

  int ready;
  nfds_t nfds;
  ssize_t s;
  struct pollfd *pfds;

  nfds = 1;
  pfds = (pollfd*)calloc(nfds, sizeof(struct pollfd));
  pfds[0].fd = 3; //pty_fd;
  pfds[0].events = POLLIN;
  
  statusReg = 0x40;
  ready = poll(pfds, nfds, 10);

  printf("Status\n");

  if (pfds[0].revents & POLLIN) {
	s = read(pfds[0].fd, buf, 1);
	printf("Read %d bytes\n", s);
	if (s == 1) {
	  statusReg |= 0x01;
	  receiveDataReg = *buf;
	  printf("Recv $%02x from %d\n", receiveDataReg, pty_fd);
	} 
  }
  
  /*
  fd_set fds; 
  FD_ZERO(&fds);
  FD_SET(pty_fd, &fds);
  struct timeval t = {0, 10};
  int bytesAvailable = select(pty_fd + 1, &fds, NULL, NULL, &t);
  if (bytesAvailable && (read(pty_fd, buf, 1) != 0)) {
	statusReg |= 0x01;
	receiveDataReg = *buf;
	//	std::cout << "Byte '" << std::hex << receiveDataReg << "'" << std::endl;
  } else {
	statusReg = 0x40;
  }
  * /
}
*/
void R6501::send(wdc816::Byte data) {
  printf("Send $%02x to %d\n", data, pty_fd);
  // std::cout << "send '" << std::hex << data << "'" << std::endl;
  int bytes = write(3, &data, 1);
  if (bytes != 1) {
    fprintf(stderr, "Couldn't write to serial port");
  }
}
  
wdc816::Byte R6501::getByte(wdc816::Addr ea)
{
  // std::cout << "R6501: " << ea << std::endl; 
  switch (ea & 0xff) {
  case 0x00: // PortA
	return ram[ea];
  case 0x01: // PortB
	return ram[ea];
  case 0x02: // PortC
	return ram[ea];
  case 0x03: // PortD
	return ram[ea];
  case 0x04: // PortE - R6500/12
	return 0;
  case 0x05: // PortF - R6500/12
	return 0;
  case 0x06: // PortG - R6500/12
	return 0;
	// 0x07-0x0f User RAM
  case 0x10:
	return 0xff;
  case 0x11: // IFR
	return 0;
  case 0x12: // IER
	return 0;
  case 0x13: // --
	return 0xff;
  case 0x14: // MCR
	return 0;
  case 0x15: // SCR
    return commandReg;
  case 0x16: // SSR
    status();
    return statusReg;
  case 0x17: // SRDR
    status(); 
    statusReg &= ~0x01; // Clear bit 0 RCVR full flag
    return receiveDataReg;
	// Counter A
	// Counter B
  default:
	return ram[ea & 0xff];
  }
}

void R6501::setByte(wdc816::Addr ea, wdc816::Byte data)
{
  // std::cout << "R6501: " << ea << ":=" << data << std::endl; 
  switch (ea & 0xff) {
  case 0x12: // IER
	break;
  case 0x14: // MCR
	break;
  case 0x15: // SCCR
	// 1100 0100 = Transmit, Receive enabled, async, 7-bits, no parity
    controlReg = data;
	if (data == 0xc4) { reset(); }
	break;
  case 0x16: // SSR
    status();
    // statusReg &= ~0x08;
	// Counter A
	// Counter B
	break;
  case 0x17: // Data
    send(data);
    // statusReg |= 0x10;
    break;
  case 0x02: // Command
  case 0x03: // Control
    break;
  default:
	ram[ea & 0xff] = data;
  }
}
