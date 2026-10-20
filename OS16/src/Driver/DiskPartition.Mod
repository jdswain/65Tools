MODULE DiskPartition; (* A partition of a disk (model: DiskPartition, a
   BlockDriver): count blocks of another BlockDriver, its disk (a
   SCSIDisk), from block first; block n of the partition is block
   first + n of the disk.

   Scan finds a disk's partitions in its GUID partition table (GPT): the
   header in block 1 ("EFI PART"; the backup in the last block if that
   one is bad), its CRC32 and that of the partition entries checked, and
   a DiskPartition for each entry in use, named for the disk and its
   number from 1 (SD0p1, ...). The entries' LBAs are taken to 32 bits,
   2 TB of 512 byte blocks. *)

  IMPORT Driver, BlockDriver;

  CONST
    BlockSize = BlockDriver.BlockSize;
    MaxEntries = 128;
    LabelLen* = 37;   (* a GPT name is 36 UTF-16 characters *)

  TYPE
    DiskPartition* = POINTER TO DiskPartitionDesc;
    DiskPartitionDesc* = RECORD (BlockDriver.BlockDriverDesc)
      disk*: BlockDriver.BlockDriver;   (* the disk it is on *)
      first*, count*: LONGINT;           (* its blocks on the disk *)
      type*: ARRAY 16 OF BYTE;           (* the partition type GUID, as stored *)
      label*: ARRAY LabelLen OF CHAR     (* its GPT name, the characters below 80H *)
    END;

  VAR
    buf: ARRAY BlockSize OF BYTE;
    (* CRC32, as two 16-bit halves: oc816's AND, EOR and LSR are 16-bit *)
    crcHi, crcLo: INTEGER;

  (* --- Block I/O --- *)

  PROCEDURE (p: DiskPartition) ReadBlock*(n: LONGINT; VAR buf: ARRAY OF BYTE): INTEGER OVERRIDE;
    VAR res: INTEGER;
  BEGIN
    IF (n < 0) OR (n >= p.count) THEN res := -BlockDriver.errRange
    ELSE res := p.disk.ReadBlock(p.first + n, buf)
    END
  RETURN res
  END ReadBlock;

  PROCEDURE (p: DiskPartition) WriteBlock*(n: LONGINT; VAR buf: ARRAY OF BYTE): INTEGER OVERRIDE;
    VAR res: INTEGER;
  BEGIN
    IF (n < 0) OR (n >= p.count) THEN res := -BlockDriver.errRange
    ELSE res := p.disk.WriteBlock(p.first + n, buf)
    END
  RETURN res
  END WriteBlock;

  PROCEDURE (p: DiskPartition) Blocks*(): LONGINT OVERRIDE;
  BEGIN RETURN p.count
  END Blocks;

  (* --- CRC32 (IEEE 802.3, reflected, as GPT has it) --- *)

  PROCEDURE CrcStart;
  BEGIN crcHi := -1; crcLo := -1
  END CrcStart;

  PROCEDURE CrcByte(b: INTEGER);
    VAR i: INTEGER; carry: BOOLEAN;
  BEGIN
    crcLo := EOR(crcLo, b);
    FOR i := 1 TO 8 DO
      carry := ODD(crcLo);
      crcLo := ORA(LSR(crcLo, 1), ASL(AND(crcHi, 1), 15));
      crcHi := LSR(crcHi, 1);
      IF carry THEN crcHi := EOR(crcHi, 0EDB8H); crcLo := EOR(crcLo, 8320H) END
    END
  END CrcByte;

  (* the CRC so far equals the 4 bytes at b[i] *)
  PROCEDURE CrcIs(VAR b: ARRAY OF BYTE; i: INTEGER): BOOLEAN;
    VAR hi, lo: INTEGER;
  BEGIN
    hi := EOR(crcHi, -1); lo := EOR(crcLo, -1);
    RETURN (AND(lo, 0FFH) = b[i]) & (AND(LSR(lo, 8), 0FFH) = b[i + 1])
      & (AND(hi, 0FFH) = b[i + 2]) & (AND(LSR(hi, 8), 0FFH) = b[i + 3])
  END CrcIs;

  (* --- The GPT --- *)

  PROCEDURE Long(VAR b: ARRAY OF BYTE; i: INTEGER): LONGINT;
    VAR v: LONGINT; k: INTEGER;
  BEGIN v := 0;
    FOR k := 3 TO 0 BY -1 DO v := v * 100H + b[i + k] END
  RETURN v
  END Long;

  (* a GPT header at block n of disk, CRC checked: its entries' block,
     number and size *)
  PROCEDURE Header(disk: BlockDriver.BlockDriver; n: LONGINT; VAR at: LONGINT; VAR num, size: INTEGER): BOOLEAN;
    VAR ok: BOOLEAN; i, len: INTEGER;
  BEGIN
    ok := (n > 0) & (disk.ReadBlock(n, buf) = 0)
      & (buf[0] = ORD("E")) & (buf[1] = ORD("F")) & (buf[2] = ORD("I")) & (buf[3] = ORD(" "))
      & (buf[4] = ORD("P")) & (buf[5] = ORD("A")) & (buf[6] = ORD("R")) & (buf[7] = ORD("T"));
    IF ok THEN
      len := buf[12] + buf[13] * 100H;                    (* header size, 92 *)
      ok := (len >= 92) & (len <= BlockSize);
      IF ok THEN
        CrcStart;
        FOR i := 0 TO len - 1 DO
          IF (i >= 16) & (i < 20) THEN CrcByte(0) ELSE CrcByte(buf[i]) END   (* its own CRC as 0 *)
        END;
        ok := CrcIs(buf, 16);
        at := Long(buf, 72); num := Long(buf, 80); size := Long(buf, 84);
        ok := ok & (size >= 128) & (size <= BlockSize) & (BlockSize MOD size = 0)
          & (num > 0) & (num <= MaxEntries)
      END
    END
  RETURN ok
  END Header;

  (* the entries' CRC equals the one in the header at block n *)
  PROCEDURE EntriesOK(disk: BlockDriver.BlockDriver; n, at: LONGINT; num, size: INTEGER): BOOLEAN;
    VAR ok: BOOLEAN; i, k, perBlock: INTEGER;
  BEGIN
    perBlock := BlockSize DIV size; CrcStart; ok := TRUE; i := 0;
    WHILE ok & (i < num) DO
      IF i MOD perBlock = 0 THEN ok := disk.ReadBlock(at + i DIV perBlock, buf) = 0 END;
      FOR k := 0 TO size - 1 DO CrcByte(buf[i MOD perBlock * size + k]) END;
      INC(i)
    END;
    ok := ok & (disk.ReadBlock(n, buf) = 0) & CrcIs(buf, 88)
  RETURN ok
  END EntriesOK;

  (* name and number from 1: SD0 and 2 make SD0p2 *)
  PROCEDURE Name(p: DiskPartition; num: INTEGER);
    VAR name: ARRAY Driver.NameLen OF CHAR; i: INTEGER;
  BEGIN
    i := 0;
    WHILE (p.disk.name[i] # 0X) & (i < Driver.NameLen - 5) DO name[i] := p.disk.name[i]; INC(i) END;
    name[i] := "p"; INC(i);
    IF num >= 100 THEN name[i] := CHR(ORD("0") + num DIV 100); INC(i) END;
    IF num >= 10 THEN name[i] := CHR(ORD("0") + num DIV 10 MOD 10); INC(i) END;
    name[i] := CHR(ORD("0") + num MOD 10); name[i + 1] := 0X;
    Driver.SetName(p, name)
  END Name;

  (* The partitions of disk, in the order of its partition table, into
     parts: how many, 0 if it has no valid GPT. *)
  PROCEDURE Scan*(disk: BlockDriver.BlockDriver; VAR parts: ARRAY OF DiskPartition): INTEGER;
    VAR n, at, first, last: LONGINT; num, size, perBlock, i, j, k, e, found: INTEGER;
      used: BOOLEAN; p: DiskPartition;
  BEGIN
    found := 0;
    n := 1;
    IF ~(Header(disk, n, at, num, size) & EntriesOK(disk, n, at, num, size)) THEN
      n := disk.Blocks() - 1;                             (* the backup *)
      IF ~(Header(disk, n, at, num, size) & EntriesOK(disk, n, at, num, size)) THEN n := 0 END
    END;
    IF n > 0 THEN
      perBlock := BlockSize DIV size; i := 0;
      WHILE (i < num) & (found < LEN(parts)) DO
        IF (i MOD perBlock = 0) & (disk.ReadBlock(at + i DIV perBlock, buf) # 0) THEN i := num
        ELSE
          e := i MOD perBlock * size;
          used := FALSE; FOR k := 0 TO 15 DO IF buf[e + k] # 0 THEN used := TRUE END END;
          first := Long(buf, e + 32); last := Long(buf, e + 40);
          IF used & (first > 0) & (last >= first) THEN
            NEW(p); p.disk := disk; p.first := first; p.count := last - first + 1;
            FOR k := 0 TO 15 DO p.type[k] := buf[e + k] END;
            j := 0; k := 0;
            WHILE (k < 36) & ((buf[e + 56 + 2 * k] # 0) OR (buf[e + 57 + 2 * k] # 0)) DO
              IF (buf[e + 57 + 2 * k] = 0) & (buf[e + 56 + 2 * k] < 80H) THEN
                p.label[j] := CHR(buf[e + 56 + 2 * k]); INC(j)
              END;
              INC(k)
            END;
            p.label[j] := 0X;
            Name(p, i + 1);
            parts[found] := p; INC(found)
          END;
          INC(i)
        END
      END
    END
  RETURN found
  END Scan;

END DiskPartition.
