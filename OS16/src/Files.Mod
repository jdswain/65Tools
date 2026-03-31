MODULE Files;
  IMPORT Driver;

  CONST
    MaxNameLen = 128;
    SectorSize = 512;

    MaxFATSectors = 9;   (* supports up to 1.44MB floppy *)

    (* Directory entry offsets within 32-byte entry *)
    deNAME = 0;          (* 8 bytes *)
    deEXT = 8;           (* 3 bytes *)
    deATTR = 11;
    deCLUSTER = 26;      (* 2 bytes LE *)
    deSIZE = 28;         (* 4 bytes LE, we use low 2 *)
    DirEntrySize = 32;
    EntriesPerSector = 16; (* 512 / 32 *)

    (* Directory entry attribute *)
    attrDirectory* = 10H;

    (* VFAT Long Filename entry attribute *)
    attrLFN = 0FH;

    (* LFN entry offsets *)
    lfnSEQ = 0;          (* sequence number, bit 6 = last *)
    lfnNAME1 = 1;        (* chars 1-5 as UCS-2, 10 bytes *)
    lfnATTR = 11;        (* always 0x0F *)
    lfnTYPE = 12;        (* always 0x00 *)
    lfnCHKSUM = 13;      (* checksum of 8.3 name *)
    lfnNAME2 = 14;       (* chars 6-11 as UCS-2, 12 bytes *)
    lfnCLUSTER = 26;     (* always 0x0000 *)
    lfnNAME3 = 28;       (* chars 12-13 as UCS-2, 4 bytes *)
    lfnLAST = 40H;       (* bit 6: last LFN entry marker *)
    CharsPerLFN = 13;    (* characters per LFN entry *)

    (* Special directory entry markers *)
    DirEmpty = 0;
    DirDeleted = 0E5H;

    (* FAT special values *)
    FATFree = 0;

    (* BPB offsets *)
    bpbJMP = 0;
    bpbOEM = 3;
    bpbBPS = 11;         (* bytes per sector *)
    bpbSPC = 13;         (* sectors per cluster *)
    bpbRES = 14;         (* reserved sectors *)
    bpbNFAT = 16;        (* number of FATs *)
    bpbROOT = 17;        (* root dir entries *)
    bpbTOT = 19;         (* total sectors *)
    bpbMEDIA = 21;       (* media descriptor *)
    bpbFPF = 22;         (* FAT sectors per FAT *)
    bpbSPT = 24;         (* sectors per track *)
    bpbHEADS = 26;       (* number of heads *)

  TYPE
    FileName* = ARRAY MaxNameLen OF CHAR;

    File* = POINTER TO FileDesc;
    FileDesc = RECORD
      name: FileName;
      fatName: ARRAY 12 OF CHAR;
      len: INTEGER;
      startCluster: INTEGER;
      dirEntry: INTEGER;
      dirCluster: INTEGER;
      registered: BOOLEAN;
      modified: BOOLEAN;
      buf: ARRAY 512 OF BYTE;
      bufCluster: INTEGER;
      bufSecOfs: INTEGER;
      bufDirty: BOOLEAN
    END;

    Rider* = RECORD
      eof*: BOOLEAN;
      res*: INTEGER;
      file: File;
      pos: INTEGER;
      cluster: INTEGER;
      clusterIdx: INTEGER;
      secOfs: INTEGER
    END;

  VAR
    dev: Driver.BlockDriver;
    fat: ARRAY 4608 OF BYTE;   (* MaxFATSectors * SectorSize *)
    dirBuf: ARRAY 512 OF BYTE;
    initialized: BOOLEAN;
    fatDirty: BOOLEAN;
    fatStart, fatSectors, fat2Start: INTEGER;
    dirStart, dirSectors, dirEntries: INTEGER;
    dataStart, secsPerCluster, maxCluster: INTEGER;
    isFAT12: BOOLEAN;

  (* ---- Utility ---- *)

  PROCEDURE GetWord(VAR buf: ARRAY OF BYTE; ofs: INTEGER): INTEGER;
    VAR lo, hi: INTEGER;
  BEGIN
    lo := buf[ofs];
    hi := buf[ofs + 1]
  RETURN ORA(lo, ASL(hi, 8))
  END GetWord;

  PROCEDURE PutWord(VAR buf: ARRAY OF BYTE; ofs, val: INTEGER);
  BEGIN
    buf[ofs] := AND(val, 0FFH);
    buf[ofs + 1] := AND(LSR(val, 8), 0FFH)
  END PutWord;

  PROCEDURE CopyName(VAR src: ARRAY OF CHAR; VAR dst: FileName);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(src)) & (i < MaxNameLen - 1) & (src[i] # 0X) DO
      dst[i] := src[i]; INC(i)
    END;
    dst[i] := 0X
  END CopyName;

  (* ---- Low-level sector I/O ---- *)

  PROCEDURE ReadSector(sector: INTEGER; VAR buf: ARRAY OF BYTE): INTEGER;
  BEGIN
  RETURN dev.read(dev, sector, buf)
  END ReadSector;

  PROCEDURE WriteSector(sector: INTEGER; VAR buf: ARRAY OF BYTE): INTEGER;
  BEGIN
  RETURN dev.write(dev, sector, buf)
  END WriteSector;

  (* ---- BPB and geometry ---- *)

  PROCEDURE ReadBPB(): BOOLEAN;
    VAR res, bps, spc, nfat, root, tot, fpf, dataSecs, totalClusters: INTEGER;
        ok: BOOLEAN;
  BEGIN
    ok := FALSE;
    res := ReadSector(0, dirBuf);
    IF res = 0 THEN
      bps := GetWord(dirBuf, bpbBPS);
      IF bps = SectorSize THEN
        spc := dirBuf[bpbSPC];
        fatStart := GetWord(dirBuf, bpbRES);
        nfat := dirBuf[bpbNFAT];
        root := GetWord(dirBuf, bpbROOT);
        tot := GetWord(dirBuf, bpbTOT);
        fpf := GetWord(dirBuf, bpbFPF);
        fatSectors := fpf;
        fat2Start := fatStart + fpf;
        dirEntries := root;
        dirStart := fatStart + nfat * fpf;
        dirSectors := (root * DirEntrySize + SectorSize - 1) DIV SectorSize;
        dataStart := dirStart + dirSectors;
        secsPerCluster := spc;
        dataSecs := tot - dataStart;
        totalClusters := dataSecs DIV spc;
        maxCluster := totalClusters + 1;  (* clusters numbered 2..maxCluster *)
        isFAT12 := totalClusters < 4085;
        IF fatSectors <= MaxFATSectors THEN
          ok := TRUE
        END
      END
    END
  RETURN ok
  END ReadBPB;

  (* ---- FAT cache operations ---- *)

  PROCEDURE CopyFATSector(idx: INTEGER; VAR sec: ARRAY OF BYTE);
    VAR j, base: INTEGER;
  BEGIN
    base := idx * SectorSize;
    j := 0;
    WHILE j < SectorSize DO
      fat[base + j] := sec[j];
      INC(j)
    END
  END CopyFATSector;

  PROCEDURE LoadFAT(): BOOLEAN;
    VAR i, res: INTEGER;
        ok: BOOLEAN;
  BEGIN
    ok := TRUE; i := 0;
    WHILE (i < fatSectors) & ok DO
      res := ReadSector(fatStart + i, dirBuf);
      IF res # 0 THEN ok := FALSE
      ELSE CopyFATSector(i, dirBuf)
      END;
      INC(i)
    END
  RETURN ok
  END LoadFAT;

  PROCEDURE GetFAT*(cluster: INTEGER): INTEGER;
    VAR ofs, lo, hi, val: INTEGER;
  BEGIN
    IF isFAT12 THEN
      ofs := cluster + cluster DIV 2;  (* cluster * 1.5 *)
      lo := fat[ofs];
      hi := fat[ofs + 1];
      val := ORA(lo, ASL(hi, 8));
      IF ODD(cluster) THEN
        val := LSR(val, 4)
      ELSE
        val := AND(val, 0FFFH)
      END
    ELSE
      ofs := cluster * 2;
      lo := fat[ofs];
      hi := fat[ofs + 1];
      val := ORA(lo, ASL(hi, 8))
    END
  RETURN val
  END GetFAT;

  PROCEDURE SetFAT(cluster, val: INTEGER);
    VAR ofs, existing, lo, hi: INTEGER;
  BEGIN
    IF isFAT12 THEN
      ofs := cluster + cluster DIV 2;
      lo := fat[ofs];
      hi := fat[ofs + 1];
      existing := ORA(lo, ASL(hi, 8));
      IF ODD(cluster) THEN
        existing := ORA(AND(existing, 0FH), ASL(AND(val, 0FFFH), 4))
      ELSE
        existing := ORA(AND(existing, 0F000H), AND(val, 0FFFH))
      END;
      fat[ofs] := AND(existing, 0FFH);
      fat[ofs + 1] := AND(LSR(existing, 8), 0FFH)
    ELSE
      ofs := cluster * 2;
      fat[ofs] := AND(val, 0FFH);
      fat[ofs + 1] := AND(LSR(val, 8), 0FFH)
    END;
    fatDirty := TRUE
  END SetFAT;

  PROCEDURE SetFATEOC(cluster: INTEGER);
  BEGIN
    IF isFAT12 THEN
      SetFAT(cluster, 0FFFH)
    ELSE
      SetFAT(cluster, -1)  (* -1 = 0xFFFF in 16-bit *)
    END
  END SetFATEOC;

  PROCEDURE FlushFAT*(): BOOLEAN;
    VAR i, j, base, res: INTEGER;
        ok: BOOLEAN;
  BEGIN
    ok := TRUE;
    IF fatDirty THEN
      i := 0;
      WHILE (i < fatSectors) & ok DO
        base := i * SectorSize;
        j := 0;
        WHILE j < SectorSize DO
          dirBuf[j] := fat[base + j];
          INC(j)
        END;
        res := WriteSector(fatStart + i, dirBuf);
        IF res # 0 THEN ok := FALSE END;
        IF ok THEN
          res := WriteSector(fat2Start + i, dirBuf);
          IF res # 0 THEN ok := FALSE END
        END;
        INC(i)
      END;
      IF ok THEN fatDirty := FALSE END
    END
  RETURN ok
  END FlushFAT;

  PROCEDURE AllocCluster(): INTEGER;
    VAR c, v: INTEGER;
        found: BOOLEAN;
  BEGIN
    c := 2; found := FALSE;
    WHILE (c <= maxCluster) & ~found DO
      v := GetFAT(c);
      IF v = FATFree THEN found := TRUE
      ELSE INC(c)
      END
    END;
    IF ~found THEN c := -1 END
  RETURN c
  END AllocCluster;

  PROCEDURE FreeChain(start: INTEGER);
    VAR next: INTEGER;
  BEGIN
    WHILE (start >= 2) & (start <= maxCluster) DO
      next := GetFAT(start);
      SetFAT(start, FATFree);
      start := next
    END
  END FreeChain;

  PROCEDURE ClusterToSector(cluster: INTEGER): INTEGER;
  BEGIN
  RETURN dataStart + (cluster - 2) * secsPerCluster
  END ClusterToSector;

  PROCEDURE FollowChain(start, hops: INTEGER): INTEGER;
    VAR c: INTEGER;
  BEGIN
    c := start;
    WHILE (hops > 0) & (c >= 2) & (c <= maxCluster) DO
      c := GetFAT(c);
      DEC(hops)
    END
  RETURN c
  END FollowChain;

  (* ---- Generalized directory sector I/O ---- *)

  PROCEDURE ReadDirSectorAt(dirCluster, secIdx: INTEGER): INTEGER;
    VAR c, hops, secOfs, sec, res: INTEGER;
  BEGIN
    IF dirCluster < 0 THEN
      res := ReadSector(dirStart + secIdx, dirBuf)
    ELSE
      hops := secIdx DIV secsPerCluster;
      secOfs := secIdx MOD secsPerCluster;
      c := FollowChain(dirCluster, hops);
      IF (c >= 2) & (c <= maxCluster) THEN
        sec := ClusterToSector(c) + secOfs;
        res := ReadSector(sec, dirBuf)
      ELSE
        res := -1
      END
    END
  RETURN res
  END ReadDirSectorAt;

  PROCEDURE WriteDirSectorAt(dirCluster, secIdx: INTEGER): INTEGER;
    VAR c, hops, secOfs, sec, res: INTEGER;
  BEGIN
    IF dirCluster < 0 THEN
      res := WriteSector(dirStart + secIdx, dirBuf)
    ELSE
      hops := secIdx DIV secsPerCluster;
      secOfs := secIdx MOD secsPerCluster;
      c := FollowChain(dirCluster, hops);
      IF (c >= 2) & (c <= maxCluster) THEN
        sec := ClusterToSector(c) + secOfs;
        res := WriteSector(sec, dirBuf)
      ELSE
        res := -1
      END
    END
  RETURN res
  END WriteDirSectorAt;

  PROCEDURE DirSectorCount(dirCluster: INTEGER): INTEGER;
    VAR c, n: INTEGER;
  BEGIN
    IF dirCluster < 0 THEN
      n := dirSectors
    ELSE
      n := 0; c := dirCluster;
      WHILE (c >= 2) & (c <= maxCluster) DO
        n := n + secsPerCluster;
        c := GetFAT(c)
      END
    END
  RETURN n
  END DirSectorCount;

  (* ---- 8.3 name conversion ---- *)

  PROCEDURE UpCase(ch: CHAR): CHAR;
  BEGIN
    IF (ch >= "a") & (ch <= "z") THEN
      ch := CHR(ORD(ch) - 32)
    END
  RETURN ch
  END UpCase;

  PROCEDURE ToFATName(VAR src: ARRAY OF CHAR; VAR dst: ARRAY OF CHAR);
    VAR i, j, si: INTEGER;
  BEGIN
    i := 0;
    WHILE i < 11 DO dst[i] := " "; INC(i) END;
    dst[11] := 0X;
    si := 0; i := 0;
    WHILE (si < LEN(src)) & (src[si] # 0X) & (src[si] # ".") & (i < 8) DO
      dst[i] := UpCase(src[si]);
      INC(si); INC(i)
    END;
    WHILE (si < LEN(src)) & (src[si] # 0X) & (src[si] # ".") DO INC(si) END;
    IF (si < LEN(src)) & (src[si] = ".") THEN
      INC(si); j := 8;
      WHILE (si < LEN(src)) & (src[si] # 0X) & (j < 11) DO
        dst[j] := UpCase(src[si]);
        INC(si); INC(j)
      END
    END
  END ToFATName;

  PROCEDURE FromFATName(VAR src: ARRAY OF CHAR; VAR dst: ARRAY OF CHAR);
    VAR i, j: INTEGER;
  BEGIN
    j := 0;
    i := 0;
    WHILE (i < 8) & (src[i] # " ") DO
      dst[j] := src[i]; INC(i); INC(j)
    END;
    IF src[8] # " " THEN
      dst[j] := "."; INC(j);
      i := 8;
      WHILE (i < 11) & (src[i] # " ") DO
        dst[j] := src[i]; INC(i); INC(j)
      END
    END;
    dst[j] := 0X
  END FromFATName;

  (* ---- LFN support ---- *)

  PROCEDURE StrLength(VAR s: ARRAY OF CHAR): INTEGER;
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END
  RETURN i
  END StrLength;

  PROCEDURE LFNChecksum(VAR fatName: ARRAY OF CHAR): INTEGER;
    VAR i, sum: INTEGER;
  BEGIN
    sum := 0;
    i := 0;
    WHILE i < 11 DO
      (* Right-rotate 1 bit then add *)
      IF ODD(sum) THEN
        sum := LSR(sum, 1) + 80H
      ELSE
        sum := LSR(sum, 1)
      END;
      sum := AND(sum + ORD(fatName[i]), 0FFH);
      INC(i)
    END
  RETURN sum
  END LFNChecksum;

  PROCEDURE NeedsLFN(VAR name: ARRAY OF CHAR): BOOLEAN;
    VAR i, baseLen, extLen: INTEGER;
        hasDot, needsLfn: BOOLEAN;
        ch: CHAR;
  BEGIN
    needsLfn := FALSE;
    baseLen := 0; extLen := 0;
    hasDot := FALSE;
    i := 0;
    WHILE (i < LEN(name)) & (name[i] # 0X) DO
      ch := name[i];
      IF ch = "." THEN
        IF hasDot THEN needsLfn := TRUE END;  (* multiple dots *)
        hasDot := TRUE
      ELSIF hasDot THEN
        INC(extLen)
      ELSE
        INC(baseLen)
      END;
      (* Check for lowercase *)
      IF (ch >= "a") & (ch <= "z") THEN needsLfn := TRUE END;
      INC(i)
    END;
    IF ~hasDot THEN
      IF baseLen > 8 THEN needsLfn := TRUE END
    ELSE
      IF (baseLen > 8) OR (extLen > 3) THEN needsLfn := TRUE END
    END
  RETURN needsLfn
  END NeedsLFN;

  PROCEDURE WriteLFNEntry(dirCluster, entIdx, seq: INTEGER;
                          VAR name: ARRAY OF CHAR;
                          nameOfs, chksum: INTEGER; last: BOOLEAN);
    VAR sec, ofs, i, k, ch, nameLen, pos: INTEGER;
        res: INTEGER;
  BEGIN
    sec := entIdx DIV EntriesPerSector;
    ofs := (entIdx MOD EntriesPerSector) * DirEntrySize;
    res := ReadDirSectorAt(dirCluster, sec);
    (* Zero-fill the entry *)
    i := 0;
    WHILE i < DirEntrySize DO dirBuf[ofs + i] := 0; INC(i) END;
    (* Set sequence number *)
    IF last THEN
      dirBuf[ofs + lfnSEQ] := ORA(seq, lfnLAST)
    ELSE
      dirBuf[ofs + lfnSEQ] := seq
    END;
    dirBuf[ofs + lfnATTR] := attrLFN;
    dirBuf[ofs + lfnTYPE] := 0;
    dirBuf[ofs + lfnCHKSUM] := chksum;
    PutWord(dirBuf, ofs + lfnCLUSTER, 0);
    (* Fill name chars as UCS-2 (ASCII byte + 0x00) *)
    nameLen := StrLength(name);
    pos := nameOfs;
    (* NAME1: 5 chars at offset 1 *)
    k := 0;
    WHILE k < 5 DO
      IF pos < nameLen THEN
        ch := ORD(name[pos]); INC(pos)
      ELSIF pos = nameLen THEN
        ch := 0; INC(pos)  (* null terminator *)
      ELSE
        ch := 0FFH  (* padding *)
      END;
      dirBuf[ofs + lfnNAME1 + k * 2] := AND(ch, 0FFH);
      IF ch = 0FFH THEN
        dirBuf[ofs + lfnNAME1 + k * 2 + 1] := 0FFH
      ELSE
        dirBuf[ofs + lfnNAME1 + k * 2 + 1] := 0
      END;
      INC(k)
    END;
    (* NAME2: 6 chars at offset 14 *)
    k := 0;
    WHILE k < 6 DO
      IF pos < nameLen THEN
        ch := ORD(name[pos]); INC(pos)
      ELSIF pos = nameLen THEN
        ch := 0; INC(pos)
      ELSE
        ch := 0FFH
      END;
      dirBuf[ofs + lfnNAME2 + k * 2] := AND(ch, 0FFH);
      IF ch = 0FFH THEN
        dirBuf[ofs + lfnNAME2 + k * 2 + 1] := 0FFH
      ELSE
        dirBuf[ofs + lfnNAME2 + k * 2 + 1] := 0
      END;
      INC(k)
    END;
    (* NAME3: 2 chars at offset 28 *)
    k := 0;
    WHILE k < 2 DO
      IF pos < nameLen THEN
        ch := ORD(name[pos]); INC(pos)
      ELSIF pos = nameLen THEN
        ch := 0; INC(pos)
      ELSE
        ch := 0FFH
      END;
      dirBuf[ofs + lfnNAME3 + k * 2] := AND(ch, 0FFH);
      IF ch = 0FFH THEN
        dirBuf[ofs + lfnNAME3 + k * 2 + 1] := 0FFH
      ELSE
        dirBuf[ofs + lfnNAME3 + k * 2 + 1] := 0
      END;
      INC(k)
    END;
    res := WriteDirSectorAt(dirCluster, sec)
  END WriteLFNEntry;

  PROCEDURE WriteLFNEntries(dirCluster, startIdx, numLFN: INTEGER;
                            VAR longName, shortName: ARRAY OF CHAR);
    VAR i, seq, nameOfs, chksum: INTEGER;
  BEGIN
    chksum := LFNChecksum(shortName);
    (* Write LFN entries in reverse order: highest seq first *)
    i := 0;
    WHILE i < numLFN DO
      seq := numLFN - i;
      nameOfs := (seq - 1) * CharsPerLFN;
      WriteLFNEntry(dirCluster, startIdx + i, seq,
                    longName, nameOfs, chksum, i = 0)
      ;
      INC(i)
    END
  END WriteLFNEntries;

  PROCEDURE DeleteLFNEntries(dirCluster, shortIdx: INTEGER);
    VAR i, sec, ofs, res, b: INTEGER;
  BEGIN
    (* Walk backwards from shortIdx-1, deleting LFN entries *)
    i := shortIdx - 1;
    WHILE i >= 0 DO
      sec := i DIV EntriesPerSector;
      ofs := (i MOD EntriesPerSector) * DirEntrySize;
      res := ReadDirSectorAt(dirCluster, sec);
      b := dirBuf[ofs + deATTR];
      IF b = attrLFN THEN
        dirBuf[ofs] := DirDeleted;
        res := WriteDirSectorAt(dirCluster, sec);
        DEC(i)
      ELSE
        i := -1  (* stop — not an LFN entry *)
      END
    END
  END DeleteLFNEntries;

  (* ---- Directory operations ---- *)

  PROCEDURE ReadDirSector(idx: INTEGER): INTEGER;
  BEGIN
  RETURN ReadDirSectorAt(-1, idx)
  END ReadDirSector;

  PROCEDURE WriteDirSector(idx: INTEGER): INTEGER;
  BEGIN
  RETURN WriteDirSectorAt(-1, idx)
  END WriteDirSector;

  PROCEDURE FindFileIn(VAR name: ARRAY OF CHAR; dirCluster: INTEGER;
                       VAR idx: INTEGER): BOOLEAN;
    VAR i, nsec, secIdx, entOfs, res: INTEGER;
        fatNm: ARRAY 12 OF CHAR;
        longBuf: ARRAY MaxNameLen OF CHAR;
        found, done, lfnMatch, shortMatch: BOOLEAN;
        b, attr, seq, lpos, k, ch, nameLen: INTEGER;
        hasLFN: BOOLEAN;
  BEGIN
    ToFATName(name, fatNm);
    nameLen := StrLength(name);
    nsec := DirSectorCount(dirCluster);
    found := FALSE; done := FALSE;
    hasLFN := FALSE; lpos := 0;
    i := 0;
    WHILE i < MaxNameLen DO longBuf[i] := 0X; INC(i) END;
    i := 0;
    WHILE (i < nsec) & ~done DO
      res := ReadDirSectorAt(dirCluster, i);
      IF res = 0 THEN
        entOfs := 0;
        WHILE (entOfs < SectorSize) & ~done DO
          b := dirBuf[entOfs];
          IF b = DirEmpty THEN done := TRUE
          ELSIF b = DirDeleted THEN
            hasLFN := FALSE; lpos := 0
          ELSE
            attr := dirBuf[entOfs + deATTR];
            IF attr = attrLFN THEN
              (* Collect LFN chars *)
              seq := AND(b, 3FH);  (* mask off bit 6 *)
              IF AND(b, lfnLAST) # 0 THEN
                (* First LFN entry we see (highest seq) — reset *)
                hasLFN := TRUE;
                k := 0;
                WHILE k < MaxNameLen DO longBuf[k] := 0X; INC(k) END
              END;
              (* Place chars at (seq-1)*13 *)
              lpos := (seq - 1) * CharsPerLFN;
              (* NAME1: 5 chars *)
              k := 0;
              WHILE (k < 5) & (lpos + k < MaxNameLen - 1) DO
                ch := dirBuf[entOfs + lfnNAME1 + k * 2];
                IF (ch # 0FFH) & (ch # 0) THEN
                  longBuf[lpos + k] := CHR(ch)
                ELSIF ch = 0 THEN
                  longBuf[lpos + k] := 0X
                END;
                INC(k)
              END;
              (* NAME2: 6 chars *)
              k := 0;
              WHILE (k < 6) & (lpos + 5 + k < MaxNameLen - 1) DO
                ch := dirBuf[entOfs + lfnNAME2 + k * 2];
                IF (ch # 0FFH) & (ch # 0) THEN
                  longBuf[lpos + 5 + k] := CHR(ch)
                ELSIF ch = 0 THEN
                  longBuf[lpos + 5 + k] := 0X
                END;
                INC(k)
              END;
              (* NAME3: 2 chars *)
              k := 0;
              WHILE (k < 2) & (lpos + 11 + k < MaxNameLen - 1) DO
                ch := dirBuf[entOfs + lfnNAME3 + k * 2];
                IF (ch # 0FFH) & (ch # 0) THEN
                  longBuf[lpos + 11 + k] := CHR(ch)
                ELSIF ch = 0 THEN
                  longBuf[lpos + 11 + k] := 0X
                END;
                INC(k)
              END
            ELSE
              (* Non-LFN entry: check long name match, then 8.3 match *)
              lfnMatch := FALSE;
              IF hasLFN THEN
                (* Compare longBuf against name (case-sensitive) *)
                k := 0;
                lfnMatch := TRUE;
                WHILE (k < nameLen) & lfnMatch DO
                  IF longBuf[k] # name[k] THEN lfnMatch := FALSE END;
                  INC(k)
                END;
                IF lfnMatch & (longBuf[nameLen] # 0X) THEN
                  lfnMatch := FALSE
                END
              END;
              shortMatch := FALSE;
              IF ~lfnMatch THEN
                secIdx := 0;
                shortMatch := TRUE;
                WHILE (secIdx < 11) & shortMatch DO
                  b := dirBuf[entOfs + secIdx];
                  IF CHR(b) # fatNm[secIdx] THEN shortMatch := FALSE END;
                  INC(secIdx)
                END
              END;
              IF lfnMatch OR shortMatch THEN
                idx := i * EntriesPerSector + entOfs DIV DirEntrySize;
                found := TRUE; done := TRUE
              END;
              hasLFN := FALSE; lpos := 0
            END
          END;
          entOfs := entOfs + DirEntrySize
        END
      ELSE
        done := TRUE
      END;
      INC(i)
    END
  RETURN found
  END FindFileIn;

  PROCEDURE FindFile(VAR name: ARRAY OF CHAR; VAR idx: INTEGER): BOOLEAN;
  BEGIN
  RETURN FindFileIn(name, -1, idx)
  END FindFile;

  PROCEDURE FindFreeEntryIn(dirCluster: INTEGER; VAR idx: INTEGER): BOOLEAN;
    VAR i, nsec, entOfs, res: INTEGER;
        found, done: BOOLEAN;
        b: INTEGER;
  BEGIN
    nsec := DirSectorCount(dirCluster);
    found := FALSE; done := FALSE;
    i := 0;
    WHILE (i < nsec) & ~done DO
      res := ReadDirSectorAt(dirCluster, i);
      IF res = 0 THEN
        entOfs := 0;
        WHILE (entOfs < SectorSize) & ~done DO
          b := dirBuf[entOfs];
          IF (b = DirEmpty) OR (b = DirDeleted) THEN
            idx := i * EntriesPerSector + entOfs DIV DirEntrySize;
            found := TRUE; done := TRUE
          END;
          entOfs := entOfs + DirEntrySize
        END
      ELSE
        done := TRUE
      END;
      INC(i)
    END
  RETURN found
  END FindFreeEntryIn;

  PROCEDURE FindFreeEntry(VAR idx: INTEGER): BOOLEAN;
  BEGIN
  RETURN FindFreeEntryIn(-1, idx)
  END FindFreeEntry;

  PROCEDURE ReadEntryClusterIn(dirCluster, idx: INTEGER): INTEGER;
    VAR sec, ofs, res: INTEGER;
  BEGIN
    sec := idx DIV EntriesPerSector;
    ofs := (idx MOD EntriesPerSector) * DirEntrySize;
    res := ReadDirSectorAt(dirCluster, sec)
  RETURN GetWord(dirBuf, ofs + deCLUSTER)
  END ReadEntryClusterIn;

  PROCEDURE ReadEntryCluster(idx: INTEGER): INTEGER;
  BEGIN
  RETURN ReadEntryClusterIn(-1, idx)
  END ReadEntryCluster;

  PROCEDURE ReadEntrySizeIn(dirCluster, idx: INTEGER): INTEGER;
    VAR sec, ofs, res: INTEGER;
  BEGIN
    sec := idx DIV EntriesPerSector;
    ofs := (idx MOD EntriesPerSector) * DirEntrySize;
    res := ReadDirSectorAt(dirCluster, sec)
  RETURN GetWord(dirBuf, ofs + deSIZE)
  END ReadEntrySizeIn;

  PROCEDURE ReadEntrySize(idx: INTEGER): INTEGER;
  BEGIN
  RETURN ReadEntrySizeIn(-1, idx)
  END ReadEntrySize;

  PROCEDURE ReadEntryAttrIn(dirCluster, idx: INTEGER): INTEGER;
    VAR sec, ofs, res, a: INTEGER;
  BEGIN
    sec := idx DIV EntriesPerSector;
    ofs := (idx MOD EntriesPerSector) * DirEntrySize;
    res := ReadDirSectorAt(dirCluster, sec);
    a := dirBuf[ofs + deATTR]
  RETURN a
  END ReadEntryAttrIn;

  PROCEDURE WriteEntryIn(dirCluster, idx: INTEGER; VAR fatName: ARRAY OF CHAR;
                         cluster, size, attr: INTEGER);
    VAR sec, ofs, j, res: INTEGER;
  BEGIN
    sec := idx DIV EntriesPerSector;
    ofs := (idx MOD EntriesPerSector) * DirEntrySize;
    res := ReadDirSectorAt(dirCluster, sec);
    j := 0;
    WHILE j < DirEntrySize DO dirBuf[ofs + j] := 0; INC(j) END;
    j := 0;
    WHILE j < 11 DO
      dirBuf[ofs + deNAME + j] := ORD(fatName[j]);
      INC(j)
    END;
    dirBuf[ofs + deATTR] := attr;
    PutWord(dirBuf, ofs + deCLUSTER, cluster);
    PutWord(dirBuf, ofs + deSIZE, size);
    res := WriteDirSectorAt(dirCluster, sec)
  END WriteEntryIn;

  PROCEDURE WriteEntry(idx: INTEGER; VAR fatName: ARRAY OF CHAR;
                       cluster, size: INTEGER);
  BEGIN
    WriteEntryIn(-1, idx, fatName, cluster, size, 0)
  END WriteEntry;

  PROCEDURE DeleteEntryIn(dirCluster, idx: INTEGER);
    VAR sec, ofs, res: INTEGER;
  BEGIN
    (* Delete any preceding LFN entries *)
    DeleteLFNEntries(dirCluster, idx);
    (* Delete the 8.3 entry itself *)
    sec := idx DIV EntriesPerSector;
    ofs := (idx MOD EntriesPerSector) * DirEntrySize;
    res := ReadDirSectorAt(dirCluster, sec);
    dirBuf[ofs] := DirDeleted;
    res := WriteDirSectorAt(dirCluster, sec)
  END DeleteEntryIn;

  PROCEDURE DeleteEntry(idx: INTEGER);
  BEGIN
    DeleteEntryIn(-1, idx)
  END DeleteEntry;

  (* ---- Subdirectory support ---- *)

  PROCEDURE GrowDir(dirCluster: INTEGER): BOOLEAN;
    VAR c, newc, next: INTEGER;
        ok: BOOLEAN;
        i, j, res: INTEGER;
  BEGIN
    ok := FALSE;
    IF dirCluster >= 2 THEN
      newc := AllocCluster();
      IF newc >= 2 THEN
        SetFATEOC(newc);
        (* Find last cluster in chain *)
        c := dirCluster;
        next := GetFAT(c);
        WHILE (next >= 2) & (next <= maxCluster) DO
          c := next;
          next := GetFAT(c)
        END;
        SetFAT(c, newc);
        (* Zero-fill the new cluster *)
        i := 0;
        WHILE i < SectorSize DO dirBuf[i] := 0; INC(i) END;
        j := 0;
        WHILE j < secsPerCluster DO
          res := WriteSector(ClusterToSector(newc) + j, dirBuf);
          INC(j)
        END;
        ok := TRUE
      END
    END
  RETURN ok
  END GrowDir;

  PROCEDURE GenerateShortName(VAR longName: ARRAY OF CHAR;
                              dirCluster: INTEGER;
                              VAR shortName: ARRAY OF CHAR);
    VAR i, j, slen, tail, idx: INTEGER;
        ch: CHAR;
  BEGIN
    (* Initialize to spaces *)
    i := 0;
    WHILE i < 11 DO shortName[i] := " "; INC(i) END;
    shortName[11] := 0X;
    (* Copy up to 6 uppercase chars for base *)
    slen := StrLength(longName);
    i := 0; j := 0;
    WHILE (i < slen) & (j < 6) DO
      ch := longName[i];
      IF ch = "." THEN (* skip dots *)
      ELSIF ch = " " THEN (* skip spaces *)
      ELSIF (ch >= "a") & (ch <= "z") THEN
        shortName[j] := CHR(ORD(ch) - 32); INC(j)
      ELSE
        shortName[j] := ch; INC(j)
      END;
      INC(i)
    END;
    (* Pad with _ if base is very short *)
    IF j = 0 THEN shortName[0] := "_"; j := 1 END;
    (* Add ~1 suffix *)
    shortName[j] := "~";
    shortName[j + 1] := "1";
    (* Try ~1 through ~9, checking for collision *)
    tail := 1;
    WHILE (tail <= 9) & FindFileIn(shortName, dirCluster, idx) DO
      INC(tail);
      shortName[j + 1] := CHR(ORD("0") + tail)
    END
  END GenerateShortName;

  PROCEDURE FindContiguousFreeEntries(dirCluster, count: INTEGER;
                                      VAR startIdx: INTEGER): BOOLEAN;
    VAR i, nsec, entOfs, res, b: INTEGER;
        runStart, runLen, entIdx: INTEGER;
        found, done: BOOLEAN;
  BEGIN
    found := FALSE; done := FALSE;
    runStart := 0; runLen := 0;
    i := 0;
    nsec := DirSectorCount(dirCluster);
    WHILE (i < nsec) & ~done DO
      res := ReadDirSectorAt(dirCluster, i);
      IF res = 0 THEN
        entOfs := 0;
        WHILE (entOfs < SectorSize) & ~done DO
          b := dirBuf[entOfs];
          entIdx := i * EntriesPerSector + entOfs DIV DirEntrySize;
          IF (b = DirEmpty) OR (b = DirDeleted) THEN
            IF runLen = 0 THEN runStart := entIdx END;
            INC(runLen);
            IF runLen >= count THEN
              startIdx := runStart;
              found := TRUE; done := TRUE
            END
          ELSE
            runLen := 0
          END;
          entOfs := entOfs + DirEntrySize
        END
      ELSE
        done := TRUE
      END;
      INC(i)
    END;
    (* If not found in existing space, try growing *)
    IF ~found & (dirCluster >= 2) & GrowDir(dirCluster) THEN
      found := FindContiguousFreeEntries(dirCluster, count, startIdx)
    END
  RETURN found
  END FindContiguousFreeEntries;

  PROCEDURE SplitPath(VAR path: ARRAY OF CHAR; VAR dirCluster: INTEGER;
                      VAR baseName: ARRAY OF CHAR): BOOLEAN;
    VAR i, j, start, idx, attr: INTEGER;
        comp: ARRAY MaxNameLen OF CHAR;
        ok: BOOLEAN;
  BEGIN
    dirCluster := -1;
    ok := TRUE;
    i := 0;
    (* Find last slash to determine base name vs directory components *)
    j := -1;
    WHILE (i < LEN(path)) & (path[i] # 0X) DO
      IF path[i] = "/" THEN j := i END;
      INC(i)
    END;
    IF j < 0 THEN
      (* No slash — simple filename, root directory *)
      i := 0;
      WHILE (i < LEN(path)) & (i < LEN(baseName) - 1) & (path[i] # 0X) DO
        baseName[i] := path[i]; INC(i)
      END;
      baseName[i] := 0X
    ELSE
      (* Has slash(es) — parse directory components *)
      i := 0;
      WHILE (i < j) & ok DO
        (* Extract next component *)
        start := i;
        WHILE (i < j) & (path[i] # "/") DO INC(i) END;
        IF i > start THEN
          (* Copy component *)
          idx := 0;
          WHILE (start < i) & (idx < MaxNameLen - 1) DO
            comp[idx] := path[start];
            INC(start); INC(idx)
          END;
          comp[idx] := 0X;
          (* Look up in current directory *)
          IF FindFileIn(comp, dirCluster, idx) THEN
            attr := ReadEntryAttrIn(dirCluster, idx);
            IF AND(attr, attrDirectory) # 0 THEN
              dirCluster := ReadEntryClusterIn(dirCluster, idx)
            ELSE
              ok := FALSE  (* not a directory *)
            END
          ELSE
            ok := FALSE  (* component not found *)
          END
        END;
        IF (i < j) & (path[i] = "/") THEN INC(i) END
      END;
      (* Copy base name (after last slash) *)
      IF ok THEN
        i := j + 1;
        idx := 0;
        WHILE (i < LEN(path)) & (idx < LEN(baseName) - 1) & (path[i] # 0X) DO
          baseName[idx] := path[i];
          INC(i); INC(idx)
        END;
        baseName[idx] := 0X
      END
    END
  RETURN ok
  END SplitPath;

  PROCEDURE InitDirCluster(cluster, parentCluster: INTEGER);
    VAR dotNm: ARRAY 12 OF CHAR;
        i, j, res: INTEGER;
  BEGIN
    (* Zero-fill the cluster *)
    i := 0;
    WHILE i < SectorSize DO dirBuf[i] := 0; INC(i) END;
    j := 0;
    WHILE j < secsPerCluster DO
      res := WriteSector(ClusterToSector(cluster) + j, dirBuf);
      INC(j)
    END;
    (* Create "." entry — points to self *)
    i := 0;
    WHILE i < 11 DO dotNm[i] := " "; INC(i) END;
    dotNm[0] := "."; dotNm[11] := 0X;
    WriteEntryIn(cluster, 0, dotNm, cluster, 0, attrDirectory);
    (* Create ".." entry — points to parent (0 means root) *)
    dotNm[1] := ".";
    IF parentCluster < 0 THEN
      WriteEntryIn(cluster, 1, dotNm, 0, 0, attrDirectory)
    ELSE
      WriteEntryIn(cluster, 1, dotNm, parentCluster, 0, attrDirectory)
    END
  END InitDirCluster;

  PROCEDURE IsDirEmpty(dirCluster: INTEGER): BOOLEAN;
    VAR i, nsec, entOfs, res: INTEGER;
        empty: BOOLEAN;
        b, attr: INTEGER;
  BEGIN
    nsec := DirSectorCount(dirCluster);
    empty := TRUE;
    i := 0;
    WHILE (i < nsec) & empty DO
      res := ReadDirSectorAt(dirCluster, i);
      IF res = 0 THEN
        entOfs := 0;
        WHILE (entOfs < SectorSize) & empty DO
          b := dirBuf[entOfs];
          IF b = DirEmpty THEN
            (* No more entries *)
            i := nsec  (* break outer loop *)
          ELSIF b # DirDeleted THEN
            attr := dirBuf[entOfs + deATTR];
            IF attr = attrLFN THEN
              (* LFN entry — skip *)
            ELSIF (dirBuf[entOfs] = ORD(".")) & (dirBuf[entOfs + 1] = ORD(" ")) THEN
              (* "." entry — skip *)
            ELSIF (dirBuf[entOfs] = ORD(".")) & (dirBuf[entOfs + 1] = ORD("."))
                & (dirBuf[entOfs + 2] = ORD(" ")) THEN
              (* ".." entry — skip *)
            ELSE
              empty := FALSE
            END
          END;
          entOfs := entOfs + DirEntrySize
        END
      ELSE
        empty := FALSE
      END;
      INC(i)
    END
  RETURN empty
  END IsDirEmpty;

  (* ---- Buffer management ---- *)

  PROCEDURE FlushFile(f: File): BOOLEAN;
    VAR sec, res: INTEGER;
        ok: BOOLEAN;
  BEGIN
    ok := TRUE;
    IF f.bufDirty & (f.bufCluster >= 2) THEN
      sec := ClusterToSector(f.bufCluster) + f.bufSecOfs;
      res := WriteSector(sec, f.buf);
      IF res # 0 THEN ok := FALSE
      ELSE f.bufDirty := FALSE
      END
    END
  RETURN ok
  END FlushFile;

  PROCEDURE EnsureSector(f: File; cluster, secOfs: INTEGER): BOOLEAN;
    VAR sec, res: INTEGER;
        ok: BOOLEAN;
  BEGIN
    ok := TRUE;
    IF (cluster # f.bufCluster) OR (secOfs # f.bufSecOfs) THEN
      ok := FlushFile(f);
      IF ok & (cluster >= 2) THEN
        sec := ClusterToSector(cluster) + secOfs;
        res := ReadSector(sec, f.buf);
        IF res # 0 THEN ok := FALSE
        ELSE
          f.bufCluster := cluster;
          f.bufSecOfs := secOfs
        END
      END
    END
  RETURN ok
  END EnsureSector;

  (* ---- Rider position tracking ---- *)

  PROCEDURE SyncRider(VAR r: Rider);
    VAR bytePos, clusterByte, targetIdx, hops: INTEGER;
        c: INTEGER;
  BEGIN
    IF (r.file # NIL) & (r.pos >= 0) THEN
      bytePos := r.pos;
      clusterByte := SectorSize * secsPerCluster;
      targetIdx := bytePos DIV clusterByte;
      IF targetIdx < r.clusterIdx THEN
        r.cluster := r.file.startCluster;
        r.clusterIdx := 0
      END;
      hops := targetIdx - r.clusterIdx;
      IF hops > 0 THEN
        c := FollowChain(r.cluster, hops);
        r.cluster := c;
        r.clusterIdx := targetIdx
      END;
      r.secOfs := (bytePos - targetIdx * clusterByte) DIV SectorSize
    END
  END SyncRider;

  (* ---- Extend file by one cluster ---- *)

  PROCEDURE ExtendFile(f: File; VAR r: Rider): BOOLEAN;
    VAR newc, c, cnt: INTEGER;
        ok: BOOLEAN;
  BEGIN
    ok := FALSE;
    newc := AllocCluster();
    IF newc >= 2 THEN
      SetFATEOC(newc);
      IF f.startCluster < 2 THEN
        f.startCluster := newc;
        r.cluster := newc;
        r.clusterIdx := 0
      ELSE
        c := f.startCluster;
        cnt := 0;
        WHILE (GetFAT(c) >= 2) & (GetFAT(c) <= maxCluster) DO
          c := GetFAT(c);
          INC(cnt)
        END;
        SetFAT(c, newc);
        r.cluster := newc;
        r.clusterIdx := cnt + 1
      END;
      r.secOfs := 0;
      ok := TRUE
    END
  RETURN ok
  END ExtendFile;

  (* ---- Initialization ---- *)

  PROCEDURE InitFS(): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN
    ok := ReadBPB();
    IF ok THEN ok := LoadFAT() END;
    IF ok THEN
      fatDirty := FALSE;
      initialized := TRUE
    END
  RETURN ok
  END InitFS;

  (* --- File operations --- *)

  PROCEDURE Old*(name: ARRAY OF CHAR): File;
    VAR f: File;
        idx, i, dc: INTEGER;
        nm, bn: ARRAY MaxNameLen OF CHAR;
  BEGIN
    f := NIL;
    i := 0;
    WHILE (i < LEN(name)) & (i < MaxNameLen - 1) & (name[i] # 0X) DO
      nm[i] := name[i]; INC(i)
    END;
    nm[i] := 0X;
    IF (dev # NIL) & initialized THEN
      IF SplitPath(nm, dc, bn) & FindFileIn(bn, dc, idx) THEN
        NEW(f);
        f.dirEntry := idx;
        f.dirCluster := dc;
        f.startCluster := ReadEntryClusterIn(dc, idx);
        f.len := ReadEntrySizeIn(dc, idx);
        ToFATName(bn, f.fatName);
        f.name[0] := 0X;
        CopyName(bn, f.name);
        f.registered := TRUE;
        f.modified := FALSE;
        f.bufCluster := -1;
        f.bufSecOfs := 0;
        f.bufDirty := FALSE
      END
    END
  RETURN f
  END Old;

  PROCEDURE New*(name: ARRAY OF CHAR): File;
    VAR f: File;
        i, dc: INTEGER;
        nm, bn: ARRAY MaxNameLen OF CHAR;
  BEGIN
    f := NIL;
    i := 0;
    WHILE (i < LEN(name)) & (i < MaxNameLen - 1) & (name[i] # 0X) DO
      nm[i] := name[i]; INC(i)
    END;
    nm[i] := 0X;
    IF (dev # NIL) & initialized THEN
      IF SplitPath(nm, dc, bn) THEN
        NEW(f);
        f.name[0] := 0X;
        CopyName(bn, f.name);
        ToFATName(bn, f.fatName);
        f.len := 0;
        f.startCluster := 0;
        f.dirEntry := -1;
        f.dirCluster := dc;
        f.registered := FALSE;
        f.modified := FALSE;
        f.bufCluster := -1;
        f.bufSecOfs := 0;
        f.bufDirty := FALSE
      END
    END
  RETURN f
  END New;

  PROCEDURE Register*(f: File);
    VAR idx, numLFN, startIdx, nameLen: INTEGER;
        ok, useLFN: BOOLEAN;
        shortNm: ARRAY 12 OF CHAR;
  BEGIN
    IF (f # NIL) & ~f.registered THEN
      ok := FlushFile(f);
      IF ok THEN
        useLFN := NeedsLFN(f.name);
        IF useLFN THEN
          GenerateShortName(f.name, f.dirCluster, shortNm);
          nameLen := StrLength(f.name);
          numLFN := (nameLen + CharsPerLFN - 1) DIV CharsPerLFN;
          ok := FindContiguousFreeEntries(f.dirCluster, numLFN + 1, startIdx);
          IF ok THEN
            WriteLFNEntries(f.dirCluster, startIdx, numLFN, f.name, shortNm);
            idx := startIdx + numLFN;
            WriteEntryIn(f.dirCluster, idx, shortNm,
                         f.startCluster, f.len, 0);
            ok := FlushFAT();
            f.dirEntry := idx;
            f.registered := TRUE;
            f.modified := FALSE
          END
        ELSE
          IF FindFreeEntryIn(f.dirCluster, idx) THEN
            WriteEntryIn(f.dirCluster, idx, f.fatName,
                         f.startCluster, f.len, 0);
            ok := FlushFAT();
            f.dirEntry := idx;
            f.registered := TRUE;
            f.modified := FALSE
          ELSIF (f.dirCluster >= 2) & GrowDir(f.dirCluster) THEN
            IF FindFreeEntryIn(f.dirCluster, idx) THEN
              WriteEntryIn(f.dirCluster, idx, f.fatName,
                           f.startCluster, f.len, 0);
              ok := FlushFAT();
              f.dirEntry := idx;
              f.registered := TRUE;
              f.modified := FALSE
            END
          END
        END
      END
    END
  END Register;

  PROCEDURE Close*(f: File);
    VAR ok: BOOLEAN;
  BEGIN
    IF f # NIL THEN
      ok := FlushFile(f);
      IF f.registered & f.modified THEN
        WriteEntryIn(f.dirCluster, f.dirEntry, f.fatName,
                     f.startCluster, f.len, 0);
        ok := FlushFAT();
        f.modified := FALSE
      END
    END
  END Close;

  PROCEDURE Delete*(name: ARRAY OF CHAR; VAR res: INTEGER);
    VAR idx, cluster, attr, dc, i: INTEGER;
        ok: BOOLEAN;
        nm, bn: ARRAY MaxNameLen OF CHAR;
  BEGIN
    res := -1;
    i := 0;
    WHILE (i < LEN(name)) & (i < MaxNameLen - 1) & (name[i] # 0X) DO
      nm[i] := name[i]; INC(i)
    END;
    nm[i] := 0X;
    IF (dev # NIL) & initialized THEN
      IF SplitPath(nm, dc, bn) & FindFileIn(bn, dc, idx) THEN
        attr := ReadEntryAttrIn(dc, idx);
        IF AND(attr, attrDirectory) # 0 THEN
          res := -3  (* is a directory — use RemoveDir *)
        ELSE
          cluster := ReadEntryClusterIn(dc, idx);
          DeleteEntryIn(dc, idx);
          IF cluster >= 2 THEN
            FreeChain(cluster);
            ok := FlushFAT()
          END;
          res := 0
        END
      END
    END
  END Delete;

  PROCEDURE Rename*(old, new: ARRAY OF CHAR; VAR res: INTEGER);
    VAR idx, dummy, i, dc1, dc2: INTEGER;
        numLFN, startIdx, nameLen, cluster, size, attr: INTEGER;
        fatNm, shortNm: ARRAY 12 OF CHAR;
        oldNm, newNm, bn1, bn2: ARRAY MaxNameLen OF CHAR;
        ok, useLFN: BOOLEAN;
  BEGIN
    res := -1;
    i := 0;
    WHILE (i < LEN(old)) & (i < MaxNameLen - 1) & (old[i] # 0X) DO
      oldNm[i] := old[i]; INC(i)
    END;
    oldNm[i] := 0X;
    i := 0;
    WHILE (i < LEN(new)) & (i < MaxNameLen - 1) & (new[i] # 0X) DO
      newNm[i] := new[i]; INC(i)
    END;
    newNm[i] := 0X;
    IF (dev # NIL) & initialized THEN
      IF SplitPath(oldNm, dc1, bn1) & SplitPath(newNm, dc2, bn2) THEN
        IF dc1 # dc2 THEN
          res := -4  (* cross-directory rename not supported *)
        ELSIF FindFileIn(bn2, dc1, dummy) THEN
          res := -2  (* target already exists *)
        ELSIF FindFileIn(bn1, dc1, idx) THEN
          cluster := ReadEntryClusterIn(dc1, idx);
          size := ReadEntrySizeIn(dc1, idx);
          attr := ReadEntryAttrIn(dc1, idx);
          (* Delete old entry and LFN entries *)
          DeleteEntryIn(dc1, idx);
          (* Write new entry, possibly with LFN *)
          useLFN := NeedsLFN(bn2);
          IF useLFN THEN
            GenerateShortName(bn2, dc1, shortNm);
            nameLen := StrLength(bn2);
            numLFN := (nameLen + CharsPerLFN - 1) DIV CharsPerLFN;
            ok := FindContiguousFreeEntries(dc1, numLFN + 1, startIdx);
            IF ok THEN
              WriteLFNEntries(dc1, startIdx, numLFN, bn2, shortNm);
              WriteEntryIn(dc1, startIdx + numLFN, shortNm,
                           cluster, size, attr);
              res := 0
            END
          ELSE
            ToFATName(bn2, fatNm);
            ok := FindFreeEntryIn(dc1, dummy);
            IF ok THEN
              WriteEntryIn(dc1, dummy, fatNm, cluster, size, attr);
              res := 0
            END
          END
        END
      END
    END
  END Rename;

  PROCEDURE Length*(f: File): INTEGER;
    VAR n: INTEGER;
  BEGIN
    IF f # NIL THEN n := f.len ELSE n := 0 END
  RETURN n
  END Length;

  PROCEDURE Date*(f: File): INTEGER;
  BEGIN
  RETURN 0
  END Date;

  (* --- Directory operations --- *)

  PROCEDURE CreateDir*(path: ARRAY OF CHAR; VAR res: INTEGER);
    VAR dc, idx, cluster, i, numLFN, startIdx, nameLen: INTEGER;
        nm, bn: ARRAY MaxNameLen OF CHAR;
        fatNm, shortNm: ARRAY 12 OF CHAR;
        ok, useLFN: BOOLEAN;
  BEGIN
    res := -1;
    i := 0;
    WHILE (i < LEN(path)) & (i < MaxNameLen - 1) & (path[i] # 0X) DO
      nm[i] := path[i]; INC(i)
    END;
    nm[i] := 0X;
    IF (dev # NIL) & initialized THEN
      IF SplitPath(nm, dc, bn) THEN
        IF FindFileIn(bn, dc, idx) THEN
          res := -2  (* already exists *)
        ELSE
          cluster := AllocCluster();
          IF cluster >= 2 THEN
            SetFATEOC(cluster);
            InitDirCluster(cluster, dc);
            useLFN := NeedsLFN(bn);
            IF useLFN THEN
              GenerateShortName(bn, dc, shortNm);
              nameLen := StrLength(bn);
              numLFN := (nameLen + CharsPerLFN - 1) DIV CharsPerLFN;
              ok := FindContiguousFreeEntries(dc, numLFN + 1, startIdx);
              IF ok THEN
                WriteLFNEntries(dc, startIdx, numLFN, bn, shortNm);
                WriteEntryIn(dc, startIdx + numLFN, shortNm,
                             cluster, 0, attrDirectory);
                ok := FlushFAT();
                IF ok THEN res := 0 END
              ELSE
                SetFAT(cluster, FATFree);
                ok := FlushFAT()
              END
            ELSE
              ok := FindFreeEntryIn(dc, idx);
              IF ~ok & (dc >= 2) THEN
                ok := GrowDir(dc);
                IF ok THEN ok := FindFreeEntryIn(dc, idx) END
              END;
              IF ok THEN
                ToFATName(bn, fatNm);
                WriteEntryIn(dc, idx, fatNm, cluster, 0, attrDirectory);
                ok := FlushFAT();
                IF ok THEN res := 0 END
              ELSE
                SetFAT(cluster, FATFree);
                ok := FlushFAT()
              END
            END
          END
        END
      END
    END
  END CreateDir;

  PROCEDURE RemoveDir*(path: ARRAY OF CHAR; VAR res: INTEGER);
    VAR dc, idx, attr, cluster, i: INTEGER;
        nm, bn: ARRAY MaxNameLen OF CHAR;
        ok: BOOLEAN;
  BEGIN
    res := -1;
    i := 0;
    WHILE (i < LEN(path)) & (i < MaxNameLen - 1) & (path[i] # 0X) DO
      nm[i] := path[i]; INC(i)
    END;
    nm[i] := 0X;
    IF (dev # NIL) & initialized THEN
      IF SplitPath(nm, dc, bn) & FindFileIn(bn, dc, idx) THEN
        attr := ReadEntryAttrIn(dc, idx);
        IF AND(attr, attrDirectory) = 0 THEN
          res := -3  (* not a directory *)
        ELSE
          cluster := ReadEntryClusterIn(dc, idx);
          IF ~IsDirEmpty(cluster) THEN
            res := -4  (* directory not empty *)
          ELSE
            FreeChain(cluster);
            DeleteEntryIn(dc, idx);
            ok := FlushFAT();
            IF ok THEN res := 0 END
          END
        END
      END
    END
  END RemoveDir;

  (* --- Rider operations --- *)

  PROCEDURE Set*(VAR r: Rider; f: File; pos: INTEGER);
  BEGIN
    r.file := f; r.eof := FALSE; r.res := 0;
    IF pos < 0 THEN r.pos := 0
    ELSIF (f # NIL) & (pos > f.len) THEN r.pos := f.len
    ELSE r.pos := pos
    END;
    IF f # NIL THEN
      r.cluster := f.startCluster;
      r.clusterIdx := 0;
      r.secOfs := 0;
      SyncRider(r)
    ELSE
      r.cluster := 0;
      r.clusterIdx := 0;
      r.secOfs := 0
    END
  END Set;

  PROCEDURE Pos*(VAR r: Rider): INTEGER;
  BEGIN
  RETURN r.pos
  END Pos;

  PROCEDURE Base*(VAR r: Rider): File;
  BEGIN
  RETURN r.file
  END Base;

  (* --- Read operations --- *)

  PROCEDURE Read*(VAR r: Rider; VAR x: BYTE);
    VAR bufIdx: INTEGER;
        ok: BOOLEAN;
        clusterByte: INTEGER;
  BEGIN
    IF (r.file = NIL) OR (r.pos >= r.file.len) THEN
      x := 0; r.eof := TRUE
    ELSE
      SyncRider(r);
      ok := EnsureSector(r.file, r.cluster, r.secOfs);
      IF ok THEN
        clusterByte := SectorSize * secsPerCluster;
        bufIdx := r.pos - r.clusterIdx * clusterByte - r.secOfs * SectorSize;
        x := r.file.buf[bufIdx];
        INC(r.pos)
      ELSE
        x := 0; r.eof := TRUE
      END
    END
  END Read;

  PROCEDURE ReadInt*(VAR r: Rider; VAR x: INTEGER);
    VAR lo, hi: BYTE;
  BEGIN
    Read(r, lo);
    Read(r, hi);
    x := ORA(lo, ASL(hi, 8))
  END ReadInt;

  PROCEDURE ReadString*(VAR r: Rider; VAR x: ARRAY OF CHAR);
    VAR i: INTEGER;
        b: BYTE;
  BEGIN
    i := 0;
    REPEAT
      Read(r, b);
      IF i < LEN(x) - 1 THEN x[i] := CHR(b); INC(i) END
    UNTIL (b = 0) OR r.eof;
    x[i] := 0X
  END ReadString;

  PROCEDURE ReadBytes*(VAR r: Rider; VAR x: ARRAY OF BYTE; n: INTEGER);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < n) & ~r.eof DO
      Read(r, x[i]);
      INC(i)
    END;
    r.res := n - i
  END ReadBytes;

  (* --- Write operations --- *)

  PROCEDURE Write*(VAR r: Rider; x: BYTE);
    VAR bufIdx: INTEGER;
        ok: BOOLEAN;
        clusterByte: INTEGER;
        needExtend: BOOLEAN;
  BEGIN
    IF r.file # NIL THEN
      clusterByte := SectorSize * secsPerCluster;
      needExtend := FALSE;
      ok := TRUE;
      IF r.file.startCluster < 2 THEN
        needExtend := TRUE
      ELSE
        SyncRider(r);
        IF (r.cluster < 2) OR (r.cluster > maxCluster) THEN
          needExtend := TRUE
        END
      END;
      IF needExtend THEN
        ok := ExtendFile(r.file, r);
        IF ~ok THEN
          r.res := -1
        END
      END;
      IF ok THEN
        ok := EnsureSector(r.file, r.cluster, r.secOfs)
      END;
      IF ok THEN
        bufIdx := r.pos - r.clusterIdx * clusterByte - r.secOfs * SectorSize;
        IF bufIdx >= SectorSize THEN
          IF r.secOfs + 1 < secsPerCluster THEN
            r.secOfs := r.secOfs + 1
          ELSE
            ok := ExtendFile(r.file, r)
          END;
          IF ok THEN
            ok := EnsureSector(r.file, r.cluster, r.secOfs);
            bufIdx := r.pos - r.clusterIdx * clusterByte - r.secOfs * SectorSize
          END
        END
      END;
      IF ok THEN
        r.file.buf[bufIdx] := x;
        r.file.bufDirty := TRUE;
        INC(r.pos);
        IF r.pos > r.file.len THEN
          r.file.len := r.pos;
          r.file.modified := TRUE
        END
      ELSE
        r.res := -1
      END
    END
  END Write;

  PROCEDURE WriteInt*(VAR r: Rider; x: INTEGER);
  BEGIN
    Write(r, AND(x, 0FFH));
    Write(r, AND(LSR(x, 8), 0FFH))
  END WriteInt;

  PROCEDURE WriteString*(VAR r: Rider; x: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(x)) & (x[i] # 0X) DO
      Write(r, ORD(x[i]));
      INC(i)
    END;
    Write(r, 0)
  END WriteString;

  PROCEDURE WriteBytes*(VAR r: Rider; VAR x: ARRAY OF BYTE; n: INTEGER);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE i < n DO
      Write(r, x[i]);
      INC(i)
    END
  END WriteBytes;

  (* ---- Format ---- *)

  PROCEDURE Format*(d: Driver.BlockDriver);
    VAR i, res: INTEGER;
  BEGIN
    (* 720K FAT12: SPC=2, RES=1, NFAT=2, ROOT=112, TOT=1440, FPF=3 *)
    (* Layout: BPB(1) + FAT1(3) + FAT2(3) + RootDir(7) + Data(1426) *)
    i := 0;
    WHILE i < SectorSize DO dirBuf[i] := 0; INC(i) END;

    dirBuf[bpbJMP] := 0EBH;
    dirBuf[bpbJMP + 1] := 03CH;
    dirBuf[bpbJMP + 2] := 090H;
    dirBuf[bpbOEM] := ORD("O"); dirBuf[bpbOEM+1] := ORD("S");
    dirBuf[bpbOEM+2] := ORD("1"); dirBuf[bpbOEM+3] := ORD("6");
    dirBuf[bpbOEM+4] := 20H; dirBuf[bpbOEM+5] := 20H;
    dirBuf[bpbOEM+6] := 20H; dirBuf[bpbOEM+7] := 20H;
    PutWord(dirBuf, bpbBPS, 512);
    dirBuf[bpbSPC] := 2;
    PutWord(dirBuf, bpbRES, 1);
    dirBuf[bpbNFAT] := 2;
    PutWord(dirBuf, bpbROOT, 112);
    PutWord(dirBuf, bpbTOT, 1440);
    dirBuf[bpbMEDIA] := 0F9H;
    PutWord(dirBuf, bpbFPF, 3);
    PutWord(dirBuf, bpbSPT, 9);
    PutWord(dirBuf, bpbHEADS, 2);
    dirBuf[510] := 055H;
    dirBuf[511] := 0AAH;
    res := d.write(d, 0, dirBuf);

    (* Write FAT1 — FAT12: entries 0-1 = F9 FF FF (3 bytes) *)
    i := 0;
    WHILE i < SectorSize DO dirBuf[i] := 0; INC(i) END;
    dirBuf[0] := 0F9H; dirBuf[1] := 0FFH;
    dirBuf[2] := 0FFH;
    res := d.write(d, 1, dirBuf);
    dirBuf[0] := 0; dirBuf[1] := 0; dirBuf[2] := 0;
    i := 1;
    WHILE i < 3 DO
      res := d.write(d, 1 + i, dirBuf);
      INC(i)
    END;

    (* Write FAT2 *)
    dirBuf[0] := 0F9H; dirBuf[1] := 0FFH; dirBuf[2] := 0FFH;
    res := d.write(d, 4, dirBuf);
    dirBuf[0] := 0; dirBuf[1] := 0; dirBuf[2] := 0;
    i := 1;
    WHILE i < 3 DO
      res := d.write(d, 4 + i, dirBuf);
      INC(i)
    END;

    (* Zero root directory — 7 sectors starting at sector 7 *)
    i := 0;
    WHILE i < 7 DO
      res := d.write(d, 7 + i, dirBuf);
      INC(i)
    END
  END Format;

  (* --- Initialization --- *)

  PROCEDURE Init*(d: Driver.BlockDriver);
    VAR ok: BOOLEAN;
  BEGIN
    dev := d;
    initialized := FALSE;
    fatDirty := FALSE;
    IF dev # NIL THEN
      ok := InitFS()
    END
  END Init;

BEGIN
  dev := NIL;
  initialized := FALSE;
  fatDirty := FALSE
END Files.
