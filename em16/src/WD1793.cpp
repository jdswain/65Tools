#include "WD1793.h"
#include <cstring>

WD1793::WD1793()
{
  reset();
  diskImage[0] = NULL;
  diskImage[1] = NULL;
  diskMounted[0] = false;
  diskMounted[1] = false;
}

void WD1793::reset()
{
  statusReg = 0;
  commandReg = 0;
  trackReg = 0;
  sectorReg = 1;
  dataReg = 0;
  driveControl = 0;
  selectedDrive = 0;
  selectedSide = 0;
  motorOn = false;
  bufPos = 0;
  writing = false;
  pendingOp = NONE;
  delayCounter = 0;
  memset(sectorBuf, 0, WD_SECTOR_SIZE);
}

bool WD1793::mountDisk(int drive, const char *filename)
{
  if (drive < 0 || drive > 1) return false;

  if (diskImage[drive]) {
    fclose(diskImage[drive]);
    diskImage[drive] = NULL;
    diskMounted[drive] = false;
  }

  FILE *f = fopen(filename, "r+b");
  if (!f) {
    // Try read-only
    f = fopen(filename, "rb");
    if (!f) {
      printf("WD1793: Cannot open disk image: %s\n", filename);
      return false;
    }
    printf("WD1793: Mounted disk %d (read-only): %s\n", drive, filename);
  } else {
    printf("WD1793: Mounted disk %d: %s\n", drive, filename);
  }

  diskImage[drive] = f;
  diskMounted[drive] = true;
  return true;
}

long WD1793::sectorOffset()
{
  // Flat offset: ((track * 2 + side) * 9 + (sector - 1)) * 512
  int track = trackReg;
  int side = selectedSide;
  int sector = sectorReg;

  if (track < 0 || track >= WD_TRACKS) return -1;
  if (side < 0 || side >= WD_SIDES) return -1;
  if (sector < 1 || sector > WD_SECTORS) return -1;

  return (long)((track * WD_SIDES + side) * WD_SECTORS + (sector - 1)) * WD_SECTOR_SIZE;
}

uint8_t WD1793::driveStatusRead()
{
  // Bit 7: /INTRQ (active low, so 0 = interrupt pending)
  // Bit 6: /(INTRQ+DRQ) (active low)
  // Bit 5: Motor on status (0=On, 1=Off)
  uint8_t val = 0;
  bool intrq = !(statusReg & WD_STAT_BUSY); // INTRQ when not busy (command complete)
  bool drq = (statusReg & WD_STAT_DRQ) != 0;

  if (!intrq) val |= 0x80;           // /INTRQ: high when no interrupt
  if (!(intrq || drq)) val |= 0x40;  // /(INTRQ+DRQ): high when neither
  if (!motorOn) val |= 0x20;         // Motor status: 1=Off

  return val;
}

wdc816::Byte WD1793::getByte(wdc816::Addr ea)
{
  int reg = ea & 0x0F;

  switch (reg) {
    case 0x00: // Status register
      // Advance delay simulation: each read of status ticks the counter
      if (pendingOp != NONE && delayCounter > 0) {
        delayCounter--;
        if (delayCounter == 0) {
          completePendingOp();
        }
      }
      return statusReg;

    case 0x01: // Track register
      return trackReg;

    case 0x02: // Sector register
      return sectorReg;

    case 0x03: // Data register
      if (!writing && (statusReg & WD_STAT_DRQ)) {
        // Reading sector data byte-by-byte
        dataReg = sectorBuf[bufPos++];
        if (bufPos >= WD_SECTOR_SIZE) {
          // Transfer complete
          statusReg &= ~(WD_STAT_DRQ | WD_STAT_BUSY);
        }
      }
      return dataReg;

    case 0x06: // Drive status
      return driveStatusRead();

    default:
      return 0;
  }
}

void WD1793::setByte(wdc816::Addr ea, wdc816::Byte data)
{
  int reg = ea & 0x0F;

  switch (reg) {
    case 0x00: // Command register
      commandReg = data;
      executeCommand(data);
      break;

    case 0x01: // Track register
      trackReg = data;
      break;

    case 0x02: // Sector register
      sectorReg = data;
      break;

    case 0x03: // Data register
      dataReg = data;
      if (writing && (statusReg & WD_STAT_DRQ)) {
        // Writing sector data byte-by-byte
        sectorBuf[bufPos++] = data;
        if (bufPos >= WD_SECTOR_SIZE) {
          // Flush buffer to disk image
          if (diskMounted[selectedDrive] && diskImage[selectedDrive]) {
            long offset = sectorOffset();
            if (offset >= 0) {
              fseek(diskImage[selectedDrive], offset, SEEK_SET);
              fwrite(sectorBuf, 1, WD_SECTOR_SIZE, diskImage[selectedDrive]);
              fflush(diskImage[selectedDrive]);
            }
          }
          statusReg &= ~(WD_STAT_DRQ | WD_STAT_BUSY);
          writing = false;
        }
      }
      break;

    case 0x06: // Drive control register
      driveControl = data;
      // Bit 0: Side select
      selectedSide = data & 0x01;
      // Bits 1-2: Drive select
      if (data & 0x02) selectedDrive = 0;
      if (data & 0x04) selectedDrive = 1;
      // Bit 5: Motor on
      motorOn = (data & 0x20) != 0;
      break;

    default:
      break;
  }
}

void WD1793::executeCommand(uint8_t cmd)
{
  uint8_t cmdType = cmd & 0xF0;

  if (cmdType == 0x00) {
    doRestore();
  } else if (cmdType == 0x10) {
    doSeek();
  } else if ((cmd & 0xE0) == 0x80) {
    doReadSector();
  } else if ((cmd & 0xE0) == 0xA0) {
    doWriteSector();
  } else if ((cmd & 0xF0) == 0xD0) {
    doForceInterrupt();
  }
}

void WD1793::doRestore()
{
  if (!motorOn || !diskMounted[selectedDrive]) {
    statusReg = WD_STAT_NOT_READY;
    pendingOp = NONE;
    return;
  }
  // Start delayed restore: Busy, completion after N status reads
  statusReg = WD_STAT_BUSY;
  pendingOp = PENDING_RESTORE;
  delayCounter = WD_DELAY_RESTORE;
}

void WD1793::doSeek()
{
  if (!motorOn || !diskMounted[selectedDrive]) {
    statusReg = WD_STAT_NOT_READY;
    pendingOp = NONE;
    return;
  }
  // Start delayed seek: Busy, completion after N status reads
  statusReg = WD_STAT_BUSY;
  pendingOp = PENDING_SEEK;
  delayCounter = WD_DELAY_SEEK;
}

void WD1793::doReadSector()
{
  if (!motorOn) {
    statusReg = WD_STAT_NOT_READY;
    pendingOp = NONE;
    return;
  }
  if (!diskMounted[selectedDrive] || !diskImage[selectedDrive]) {
    statusReg = WD_STAT_NOT_READY;
    pendingOp = NONE;
    return;
  }
  long offset = sectorOffset();
  if (offset < 0) {
    statusReg = WD_STAT_RNF;
    pendingOp = NONE;
    return;
  }
  // Start delayed read: Busy only, DRQ asserted when delay expires
  statusReg = WD_STAT_BUSY;
  pendingOp = PENDING_READ;
  delayCounter = WD_DELAY_READ;
}

void WD1793::doWriteSector()
{
  if (!motorOn) {
    statusReg = WD_STAT_NOT_READY;
    pendingOp = NONE;
    return;
  }
  if (!diskMounted[selectedDrive] || !diskImage[selectedDrive]) {
    statusReg = WD_STAT_NOT_READY;
    pendingOp = NONE;
    return;
  }
  long offset = sectorOffset();
  if (offset < 0) {
    statusReg = WD_STAT_RNF;
    pendingOp = NONE;
    return;
  }
  // Start delayed write: Busy only, DRQ asserted when delay expires
  statusReg = WD_STAT_BUSY;
  pendingOp = PENDING_WRITE;
  delayCounter = WD_DELAY_WRITE;
}

void WD1793::doForceInterrupt()
{
  // Abort any in-progress or pending command
  pendingOp = NONE;
  delayCounter = 0;
  statusReg &= ~(WD_STAT_BUSY | WD_STAT_DRQ);
  writing = false;
  bufPos = 0;

  // Update Type I status bits
  if (trackReg == 0) statusReg |= WD_STAT_TRACK0;
  if (!motorOn || !diskMounted[selectedDrive]) {
    statusReg |= WD_STAT_NOT_READY;
  }
}

void WD1793::completePendingOp()
{
  switch (pendingOp) {
    case PENDING_RESTORE:
      trackReg = 0;
      statusReg = WD_STAT_TRACK0;  // Busy cleared, Track0 set
      break;

    case PENDING_SEEK:
      trackReg = dataReg;
      statusReg = 0;
      if (trackReg == 0) statusReg |= WD_STAT_TRACK0;
      break;

    case PENDING_READ: {
      // Now actually read sector data into buffer
      long offset = sectorOffset();
      if (offset >= 0) {
        fseek(diskImage[selectedDrive], offset, SEEK_SET);
        size_t nread = fread(sectorBuf, 1, WD_SECTOR_SIZE, diskImage[selectedDrive]);
        if (nread != WD_SECTOR_SIZE) {
          memset(sectorBuf + nread, 0, WD_SECTOR_SIZE - nread);
        }
      }
      bufPos = 0;
      writing = false;
      statusReg = WD_STAT_BUSY | WD_STAT_DRQ;  // DRQ: data ready to read
      break;
    }

    case PENDING_WRITE:
      bufPos = 0;
      writing = true;
      memset(sectorBuf, 0, WD_SECTOR_SIZE);
      statusReg = WD_STAT_BUSY | WD_STAT_DRQ;  // DRQ: ready to accept data
      break;

    default:
      break;
  }
  pendingOp = NONE;
}
