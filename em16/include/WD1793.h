#ifndef WD1793_H
#define WD1793_H

#include "wdc816.h"
#include <cstdio>
#include <cstdint>

// WD1793 Floppy Disk Controller emulation
// I/O slot: $C010-$C01F (16 bytes)
//
// Register map:
//   $C010 (R) Status / (W) Command
//   $C011 (R/W) Track
//   $C012 (R/W) Sector
//   $C013 (R/W) Data
//   $C016 (R) Drive Status / (W) Drive Control
//
// Disk geometry: 720K (80 tracks, 2 sides, 9 sectors/track, 512 bytes/sector)

// Status register bits
#define WD_STAT_NOT_READY  0x80
#define WD_STAT_WRITE_PROT 0x40  // Type II write commands
#define WD_STAT_HEAD_LOAD  0x20  // Type I commands
#define WD_STAT_REC_TYPE   0x20  // Type II commands
#define WD_STAT_SEEK_ERR   0x10  // Type I commands
#define WD_STAT_RNF        0x10  // Type II commands (Record Not Found)
#define WD_STAT_CRC_ERR    0x08
#define WD_STAT_TRACK0     0x04  // Type I commands
#define WD_STAT_LOST_DATA  0x04  // Type II commands
#define WD_STAT_INDEX      0x02  // Type I commands
#define WD_STAT_DRQ        0x02  // Type II commands
#define WD_STAT_BUSY       0x01

// Simulated delay counts (status register reads before operation completes)
#define WD_DELAY_RESTORE   3   // Restore/Seek: Busy for N polls
#define WD_DELAY_SEEK      3
#define WD_DELAY_READ      2   // Read/Write: Busy (no DRQ) for N polls, then DRQ
#define WD_DELAY_WRITE     2

// Disk geometry constants
#define WD_TRACKS       80
#define WD_SIDES        2
#define WD_SECTORS      9   // sectors per track (1-based: 1-9)
#define WD_SECTOR_SIZE  512
#define WD_DISK_SIZE    (WD_TRACKS * WD_SIDES * WD_SECTORS * WD_SECTOR_SIZE)  // 737280

class WD1793 {
public:
  WD1793();
  wdc816::Byte getByte(wdc816::Addr ea);
  void setByte(wdc816::Addr ea, wdc816::Byte data);
  void reset();
  bool mountDisk(int drive, const char *filename);

private:
  // WD1793 registers
  uint8_t statusReg;
  uint8_t commandReg;
  uint8_t trackReg;
  uint8_t sectorReg;
  uint8_t dataReg;

  // Drive control/status
  uint8_t driveControl;    // last written to $C016
  int     selectedDrive;   // 0 or 1
  int     selectedSide;    // 0 or 1
  bool    motorOn;

  // Sector buffer for byte-at-a-time DRQ transfer
  uint8_t sectorBuf[WD_SECTOR_SIZE];
  int     bufPos;          // current position in sector buffer
  bool    writing;         // true during write sector command

  // Delay simulation: commands stay Busy until delayCounter reaches 0
  enum PendingOp { NONE, PENDING_RESTORE, PENDING_SEEK,
                   PENDING_READ, PENDING_WRITE };
  PendingOp pendingOp;
  int       delayCounter;  // decremented on each status register read

  // Disk images (2 drives)
  FILE   *diskImage[2];
  bool    diskMounted[2];

  // Internal methods
  void executeCommand(uint8_t cmd);
  void doRestore();
  void doSeek();
  void doReadSector();
  void doWriteSector();
  void doForceInterrupt();
  long sectorOffset();        // compute flat file offset from track/side/sector
  uint8_t driveStatusRead();  // build drive status register value
  void completePendingOp();   // finish deferred operation when delay expires
};

#endif
