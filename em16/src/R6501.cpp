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

R6501::R6501()
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

  if (pfds[0].revents & POLLIN) {
	s = read(pfds[0].fd, buf, 1);
	if (s == 1) {
	  statusReg |= 0x01;
	  receiveDataReg = *buf;
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
  */
}

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
