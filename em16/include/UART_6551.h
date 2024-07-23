#ifndef UART6551_H
#define UART6551_H

#include "wdc816.h"

/*

6551 type UART

Control Register:

7 - Stop Bits, 0 = 1 Stop Bit, 1 = 2 Stop Bits (differnt for 8 and 5 bits)
6,5 - Word Length, 00 = 8, 01 = 7, 10 = 6, 11 = 5
4 - Receiver Clock Source, 0 = External Clock, 1 = Baud Rate Generator
3,2,1,0 - Baud rate generator, 0000 = External, 1111 = 19200
Hardware Reset: 00000000, Program Reset: --------

Command Register:

7,6,5 - Parity
4 - Normal/Echo, 0 = Normal
3,2 - Transmitter controls
1 - Receiver interrupt enable
0 - Data Terminal Ready
Hardware Reset: 00000010, Program Reset ---00010

Status Register:

7 - Interrupt
6 - Data Set Ready
5 - Data Carrier Detect
4 - Transmitter Data Register Empty, 1=Empty
3 - Receiver Data Register Full, 1=Full
2 - Overrun
1 - Framing Error
0 - Parity Error
Hardware Reset: 0 --10000, Program Reset -----0--

*/

class UART {
 public:
  wdc816::Byte getByte(wdc816::Addr ea);
  void setByte(wdc816::Addr ea, wdc816::Byte data);
  void reset();
 private:
  wdc816::Byte receiveDataReg = 0x00;
  wdc816::Byte transmitDataReg = 0x00;
  wdc816::Byte statusReg = 0x10;
  wdc816::Byte commandReg = 0x02;
  wdc816::Byte controlReg = 0x00;
  
  int pty_fd;
  
  void status();
  void send(wdc816::Byte data);

};

#endif
