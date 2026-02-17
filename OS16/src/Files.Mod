MODULE Files;
  IMPORT Driver;

  CONST
    MaxNameLen = 32;
    SectorSize = 512;

    (* FAT16 geometry for 720K floppy *)
    FATStart = 1;        (* first FAT sector *)
    FATSectors = 3;      (* sectors per FAT copy *)
    FAT2Start = 4;       (* second FAT copy *)
    DirStart = 7;        (* root directory start sector *)
    DirSectors = 7;      (* root directory sectors *)
    DirEntries = 112;    (* root directory entry count *)
    DataStart = 14;      (* first data sector *)
    SecsPerCluster = 2;
    MaxCluster = 714;    (* last valid cluster number *)

    (* Directory entry offsets within 32-byte entry *)
    deNAME = 0;          (* 8 bytes *)
    deEXT = 8;           (* 3 bytes *)
    deATTR = 11;
    deCLUSTER = 26;      (* 2 bytes LE *)
    deSIZE = 28;         (* 4 bytes LE, we use low 2 *)
    DirEntrySize = 32;
    EntriesPerSector = 16; (* 512 / 32 *)

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
    fat: ARRAY 1536 OF BYTE;
    dirBuf: ARRAY 512 OF BYTE;
    initialized: BOOLEAN;
    fatDirty: BOOLEAN;

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
    WHILE (i < FATSectors) & ok DO
      res := ReadSector(FATStart + i, dirBuf);
      IF res # 0 THEN ok := FALSE
      ELSE CopyFATSector(i, dirBuf)
      END;
      INC(i)
    END
  RETURN ok
  END LoadFAT;

  PROCEDURE GetFAT*(cluster: INTEGER): INTEGER;
    VAR ofs, lo, hi: INTEGER;
  BEGIN
    ofs := cluster * 2;
    lo := fat[ofs];
    hi := fat[ofs + 1]
  RETURN ORA(lo, ASL(hi, 8))
  END GetFAT;

  PROCEDURE SetFAT(cluster, val: INTEGER);
    VAR ofs: INTEGER;
  BEGIN
    ofs := cluster * 2;
    fat[ofs] := AND(val, 0FFH);
    fat[ofs + 1] := AND(LSR(val, 8), 0FFH);
    fatDirty := TRUE
  END SetFAT;

  PROCEDURE SetFATEOC(cluster: INTEGER);
  BEGIN
    SetFAT(cluster, -1)  (* -1 = 0xFFFF in 16-bit *)
  END SetFATEOC;

  PROCEDURE FlushFAT*(): BOOLEAN;
    VAR i, j, base, res: INTEGER;
        ok: BOOLEAN;
  BEGIN
    ok := TRUE;
    IF fatDirty THEN
      i := 0;
      WHILE (i < FATSectors) & ok DO
        base := i * SectorSize;
        j := 0;
        WHILE j < SectorSize DO
          dirBuf[j] := fat[base + j];
          INC(j)
        END;
        res := WriteSector(FATStart + i, dirBuf);
        IF res # 0 THEN ok := FALSE END;
        IF ok THEN
          res := WriteSector(FAT2Start + i, dirBuf);
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
    WHILE (c <= MaxCluster) & ~found DO
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
    WHILE (start >= 2) & (start <= MaxCluster) DO
      next := GetFAT(start);
      SetFAT(start, FATFree);
      start := next
    END
  END FreeChain;

  PROCEDURE ClusterToSector(cluster: INTEGER): INTEGER;
  BEGIN
  RETURN DataStart + (cluster - 2) * SecsPerCluster
  END ClusterToSector;

  PROCEDURE FollowChain(start, hops: INTEGER): INTEGER;
    VAR c: INTEGER;
  BEGIN
    c := start;
    WHILE (hops > 0) & (c >= 2) & (c <= MaxCluster) DO
      c := GetFAT(c);
      DEC(hops)
    END
  RETURN c
  END FollowChain;

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

  (* ---- Directory operations ---- *)

  PROCEDURE ReadDirSector(idx: INTEGER): INTEGER;
  BEGIN
  RETURN ReadSector(DirStart + idx, dirBuf)
  END ReadDirSector;

  PROCEDURE WriteDirSector(idx: INTEGER): INTEGER;
  BEGIN
  RETURN WriteSector(DirStart + idx, dirBuf)
  END WriteDirSector;

  PROCEDURE FindFile(VAR name: ARRAY OF CHAR; VAR idx: INTEGER): BOOLEAN;
    VAR i, secIdx, entOfs, res: INTEGER;
        fatNm: ARRAY 12 OF CHAR;
        found, done: BOOLEAN;
        b: INTEGER;
  BEGIN
    ToFATName(name, fatNm);
    found := FALSE; done := FALSE;
    i := 0;
    WHILE (i < DirSectors) & ~done DO
      res := ReadDirSector(i);
      IF res = 0 THEN
        entOfs := 0;
        WHILE (entOfs < SectorSize) & ~done DO
          b := dirBuf[entOfs];
          IF b = DirEmpty THEN done := TRUE
          ELSIF b # DirDeleted THEN
            secIdx := 0;
            found := TRUE;
            WHILE (secIdx < 11) & found DO
              b := dirBuf[entOfs + secIdx];
              IF CHR(b) # fatNm[secIdx] THEN found := FALSE END;
              INC(secIdx)
            END;
            IF found THEN
              idx := i * EntriesPerSector + entOfs DIV DirEntrySize;
              done := TRUE
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
  END FindFile;

  PROCEDURE FindFreeEntry(VAR idx: INTEGER): BOOLEAN;
    VAR i, entOfs, res: INTEGER;
        found, done: BOOLEAN;
        b: INTEGER;
  BEGIN
    found := FALSE; done := FALSE;
    i := 0;
    WHILE (i < DirSectors) & ~done DO
      res := ReadDirSector(i);
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
  END FindFreeEntry;

  PROCEDURE ReadEntryCluster(idx: INTEGER): INTEGER;
    VAR sec, ofs, res: INTEGER;
  BEGIN
    sec := idx DIV EntriesPerSector;
    ofs := (idx MOD EntriesPerSector) * DirEntrySize;
    res := ReadDirSector(sec)
  RETURN GetWord(dirBuf, ofs + deCLUSTER)
  END ReadEntryCluster;

  PROCEDURE ReadEntrySize(idx: INTEGER): INTEGER;
    VAR sec, ofs, res: INTEGER;
  BEGIN
    sec := idx DIV EntriesPerSector;
    ofs := (idx MOD EntriesPerSector) * DirEntrySize;
    res := ReadDirSector(sec)
  RETURN GetWord(dirBuf, ofs + deSIZE)
  END ReadEntrySize;

  PROCEDURE WriteEntry(idx: INTEGER; VAR fatName: ARRAY OF CHAR;
                       cluster, size: INTEGER);
    VAR sec, ofs, j, res: INTEGER;
  BEGIN
    sec := idx DIV EntriesPerSector;
    ofs := (idx MOD EntriesPerSector) * DirEntrySize;
    res := ReadDirSector(sec);
    j := 0;
    WHILE j < DirEntrySize DO dirBuf[ofs + j] := 0; INC(j) END;
    j := 0;
    WHILE j < 11 DO
      dirBuf[ofs + deNAME + j] := ORD(fatName[j]);
      INC(j)
    END;
    dirBuf[ofs + deATTR] := 0;
    PutWord(dirBuf, ofs + deCLUSTER, cluster);
    PutWord(dirBuf, ofs + deSIZE, size);
    res := WriteDirSector(sec)
  END WriteEntry;

  PROCEDURE DeleteEntry(idx: INTEGER);
    VAR sec, ofs, res: INTEGER;
  BEGIN
    sec := idx DIV EntriesPerSector;
    ofs := (idx MOD EntriesPerSector) * DirEntrySize;
    res := ReadDirSector(sec);
    dirBuf[ofs] := DirDeleted;
    res := WriteDirSector(sec)
  END DeleteEntry;

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
      clusterByte := SectorSize * SecsPerCluster;
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
        WHILE (GetFAT(c) >= 2) & (GetFAT(c) <= MaxCluster) DO
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
    ok := LoadFAT();
    IF ok THEN
      fatDirty := FALSE;
      initialized := TRUE
    END
  RETURN ok
  END InitFS;

  (* --- File operations --- *)

  PROCEDURE Old*(name: ARRAY OF CHAR): File;
    VAR f: File;
        idx, i: INTEGER;
        nm: ARRAY 32 OF CHAR;
  BEGIN
    f := NIL;
    i := 0;
    WHILE (i < LEN(name)) & (i < 31) & (name[i] # 0X) DO
      nm[i] := name[i]; INC(i)
    END;
    nm[i] := 0X;
    IF (dev # NIL) & initialized THEN
      IF FindFile(nm, idx) THEN
        NEW(f);
        f.dirEntry := idx;
        f.startCluster := ReadEntryCluster(idx);
        f.len := ReadEntrySize(idx);
        ToFATName(nm, f.fatName);
        f.name[0] := 0X;
        CopyName(nm, f.name);
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
        i: INTEGER;
        nm: ARRAY 32 OF CHAR;
  BEGIN
    f := NIL;
    i := 0;
    WHILE (i < LEN(name)) & (i < 31) & (name[i] # 0X) DO
      nm[i] := name[i]; INC(i)
    END;
    nm[i] := 0X;
    IF (dev # NIL) & initialized THEN
      NEW(f);
      f.name[0] := 0X;
      CopyName(nm, f.name);
      ToFATName(nm, f.fatName);
      f.len := 0;
      f.startCluster := 0;
      f.dirEntry := -1;
      f.registered := FALSE;
      f.modified := FALSE;
      f.bufCluster := -1;
      f.bufSecOfs := 0;
      f.bufDirty := FALSE
    END
  RETURN f
  END New;

  PROCEDURE Register*(f: File);
    VAR idx: INTEGER;
        ok: BOOLEAN;
  BEGIN
    IF (f # NIL) & ~f.registered THEN
      ok := FlushFile(f);
      IF ok & FindFreeEntry(idx) THEN
        WriteEntry(idx, f.fatName, f.startCluster, f.len);
        ok := FlushFAT();
        f.dirEntry := idx;
        f.registered := TRUE;
        f.modified := FALSE
      END
    END
  END Register;

  PROCEDURE Close*(f: File);
    VAR ok: BOOLEAN;
  BEGIN
    IF f # NIL THEN
      ok := FlushFile(f);
      IF f.registered & f.modified THEN
        WriteEntry(f.dirEntry, f.fatName, f.startCluster, f.len);
        ok := FlushFAT();
        f.modified := FALSE
      END
    END
  END Close;

  PROCEDURE Delete*(name: ARRAY OF CHAR; VAR res: INTEGER);
    VAR idx, cluster, i: INTEGER;
        ok: BOOLEAN;
        nm: ARRAY 32 OF CHAR;
  BEGIN
    res := -1;
    i := 0;
    WHILE (i < LEN(name)) & (i < 31) & (name[i] # 0X) DO
      nm[i] := name[i]; INC(i)
    END;
    nm[i] := 0X;
    IF (dev # NIL) & initialized THEN
      IF FindFile(nm, idx) THEN
        cluster := ReadEntryCluster(idx);
        DeleteEntry(idx);
        IF cluster >= 2 THEN
          FreeChain(cluster);
          ok := FlushFAT()
        END;
        res := 0
      END
    END
  END Delete;

  PROCEDURE Rename*(old, new: ARRAY OF CHAR; VAR res: INTEGER);
    VAR idx, dummy, i: INTEGER;
        fatNm: ARRAY 12 OF CHAR;
        oldNm, newNm: ARRAY 32 OF CHAR;
  BEGIN
    res := -1;
    i := 0;
    WHILE (i < LEN(old)) & (i < 31) & (old[i] # 0X) DO
      oldNm[i] := old[i]; INC(i)
    END;
    oldNm[i] := 0X;
    i := 0;
    WHILE (i < LEN(new)) & (i < 31) & (new[i] # 0X) DO
      newNm[i] := new[i]; INC(i)
    END;
    newNm[i] := 0X;
    IF (dev # NIL) & initialized THEN
      IF FindFile(newNm, dummy) THEN
        res := -2
      ELSIF FindFile(oldNm, idx) THEN
        ToFATName(newNm, fatNm);
        WriteEntry(idx, fatNm, ReadEntryCluster(idx), ReadEntrySize(idx));
        res := 0
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
        clusterByte := SectorSize * SecsPerCluster;
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
      clusterByte := SectorSize * SecsPerCluster;
      needExtend := FALSE;
      ok := TRUE;
      IF r.file.startCluster < 2 THEN
        needExtend := TRUE
      ELSE
        SyncRider(r);
        IF (r.cluster < 2) OR (r.cluster > MaxCluster) THEN
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
          IF r.secOfs + 1 < SecsPerCluster THEN
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
    dirBuf[bpbSPC] := SecsPerCluster;
    PutWord(dirBuf, bpbRES, 1);
    dirBuf[bpbNFAT] := 2;
    PutWord(dirBuf, bpbROOT, DirEntries);
    PutWord(dirBuf, bpbTOT, 1440);
    dirBuf[bpbMEDIA] := 0F9H;
    PutWord(dirBuf, bpbFPF, FATSectors);
    PutWord(dirBuf, bpbSPT, 9);
    PutWord(dirBuf, bpbHEADS, 2);
    dirBuf[510] := 055H;
    dirBuf[511] := 0AAH;
    res := d.write(d, 0, dirBuf);

    (* Write FAT1 *)
    i := 0;
    WHILE i < SectorSize DO dirBuf[i] := 0; INC(i) END;
    dirBuf[0] := 0F9H; dirBuf[1] := 0FFH;
    dirBuf[2] := 0FFH; dirBuf[3] := 0FFH;
    res := d.write(d, FATStart, dirBuf);
    dirBuf[0] := 0; dirBuf[1] := 0; dirBuf[2] := 0; dirBuf[3] := 0;
    i := 1;
    WHILE i < FATSectors DO
      res := d.write(d, FATStart + i, dirBuf);
      INC(i)
    END;

    (* Write FAT2 *)
    dirBuf[0] := 0F9H; dirBuf[1] := 0FFH; dirBuf[2] := 0FFH; dirBuf[3] := 0FFH;
    res := d.write(d, FAT2Start, dirBuf);
    dirBuf[0] := 0; dirBuf[1] := 0; dirBuf[2] := 0; dirBuf[3] := 0;
    i := 1;
    WHILE i < FATSectors DO
      res := d.write(d, FAT2Start + i, dirBuf);
      INC(i)
    END;

    (* Zero root directory *)
    i := 0;
    WHILE i < DirSectors DO
      res := d.write(d, DirStart + i, dirBuf);
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
