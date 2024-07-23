#ifndef R6501_H
#define R6501_H

#include "wdc816.h"

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

/*

R6501 emulation

*/

class R6501 {
 public:
  R6501();
  ~R6501();
  wdc816::Byte getByte(wdc816::Addr ea);
  void setByte(wdc816::Addr ea, wdc816::Byte data);
  void reset();
 private:
  wdc816::Byte receiveDataReg = 0x00;
  wdc816::Byte transmitDataReg = 0x00;
  wdc816::Byte statusReg = 0x10;
  wdc816::Byte commandReg = 0x02;
  wdc816::Byte controlReg = 0x00;
  wdc816::Byte ram[255];
  
  int pty_fd, slave_fd;
  struct termios tty;

  void status();
  void send(wdc816::Byte data);

};

#endif
