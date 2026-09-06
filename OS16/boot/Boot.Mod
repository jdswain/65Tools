MODULE Boot;
(* Minimal dependency-free floppy boot (B2): read a named file from the FAT12
   root directory of the WD1773 floppy at the FPGA ext-bus card window $0800 and
   serial-dump it. IMPORT SYSTEM only, fixed buffers (no NEW). Geometry + reloc
   handled by MakeROM; this runs from the boot ROM. AND/LSR/ASL/ORA are oc816
   builtins (no import). *)
  IMPORT SYSTEM;

  CONST
    Serial = 0200H;                 (* 6551 ACIA data register *)

    (* WD1773 registers (base $0800; register = ea & 0x0F) *)
    fdSTATUS = 0800H;               (* R: status  W: command *)
    fdCMD    = 0800H;
    fdTRACK  = 0801H;
    fdSECTOR = 0802H;
    fdDATA   = 0803H;
    fdCTRL   = 0806H;               (* W: drive control  R: drive status *)

    cmdRestore = 0;
    cmdSeek    = 10H;
    cmdRead    = 80H;

    ctlMotor = 20H;                 (* motor on *)
    ctlDrive0 = 2;                  (* drive-select 0 *)

    stBusy = 1;                     (* status bit 0 *)
    stDRQ  = 2;                     (* status bit 1 *)

    SecSize   = 512;
    SecPerTrk = 9;                  (* 720K 3.5" DD *)
    Sides     = 2;
    SecPerCyl = 18;                 (* SecPerTrk * Sides *)
    MaxRetry  = 30000;              (* 816 INTEGER is 16-bit signed (max 32767) *)
    MaxFATSec = 8;                  (* 720K FAT12 = up to ~5 sectors; headroom *)

    (* BPB field offsets *)
    bpbBPS = 11; bpbSPC = 13; bpbRES = 14; bpbNFAT = 16;
    bpbROOT = 17; bpbTOT = 19; bpbFPF = 22;

    (* directory-entry field offsets *)
    deATTR = 11; deCLUSTER = 26; deSIZE = 28; DirEntSize = 32;
    attrLFN = 0FH; attrVolume = 08H; attrDir = 10H;

  VAR
    secBuf: ARRAY SecSize OF BYTE;
    fat: ARRAY MaxFATSec * SecSize OF BYTE;
    curTrack: INTEGER;
    fatStart, rootStart, rootSecs, dataStart, spc, rootEnts, fatSecs, maxClu: INTEGER;
    isFAT12: BOOLEAN;
    clu, size: INTEGER;
    target: ARRAY 12 OF CHAR;
    (* payload byte-stream over the cluster chain *)
    streamClu, streamSecOfs, streamPos: INTEGER; streamLoaded: BOOLEAN;

  (* ---- serial output ---- *)

  PROCEDURE Wr(ch: CHAR);
  BEGIN SYSTEM.PUT(0, Serial, ORD(ch)) END Wr;

  PROCEDURE Str(s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO Wr(s[i]); INC(i) END
  END Str;

  PROCEDURE Ln; BEGIN Wr(0DX); Wr(0AX) END Ln;

  PROCEDURE Hex1(v: INTEGER);
  BEGIN v := AND(v, 0FH);
    IF v < 10 THEN Wr(CHR(ORD("0") + v)) ELSE Wr(CHR(ORD("A") + v - 10)) END
  END Hex1;

  PROCEDURE Hex2(v: INTEGER); BEGIN Hex1(LSR(v, 4)); Hex1(v) END Hex2;
  PROCEDURE Hex4(v: INTEGER); BEGIN Hex2(LSR(v, 8)); Hex2(v) END Hex4;

  (* ---- FDC register access ---- *)

  PROCEDURE PutReg(reg, val: INTEGER);
    VAR b: BYTE;
  BEGIN b := val; SYSTEM.PUT(0, reg, b) END PutReg;

  PROCEDURE GetReg(reg: INTEGER): INTEGER;
    VAR b: BYTE; v: INTEGER;
  BEGIN SYSTEM.GET(0, reg, b); v := b RETURN v END GetReg;

  PROCEDURE WaitNotBusy(): BOOLEAN;
    VAR n: INTEGER; done: BOOLEAN;
  BEGIN n := 0; done := FALSE;
    REPEAT
      IF AND(GetReg(fdSTATUS), stBusy) = 0 THEN done := TRUE END;
      INC(n)
    UNTIL done OR (n >= MaxRetry)
  RETURN done
  END WaitNotBusy;

  PROCEDURE WaitDRQ(): BOOLEAN;
    VAR n, s: INTEGER; ok, stop: BOOLEAN;
  BEGIN n := 0; ok := FALSE; stop := FALSE;
    REPEAT
      s := GetReg(fdSTATUS);
      IF AND(s, stDRQ) # 0 THEN ok := TRUE; stop := TRUE
      ELSIF AND(s, stBusy) = 0 THEN stop := TRUE   (* busy cleared, no DRQ = error *)
      END;
      INC(n)
    UNTIL stop OR (n >= MaxRetry)
  RETURN ok
  END WaitDRQ;

  (* ---- read one 512-byte sector (linear LBA) into buf ---- *)

  PROCEDURE ReadSector(lba: INTEGER; VAR buf: ARRAY OF BYTE): BOOLEAN;
    VAR track, side, sector, i: INTEGER; ok: BOOLEAN;
  BEGIN
    track  := lba DIV SecPerCyl;
    side   := (lba DIV SecPerTrk) MOD Sides;
    sector := lba MOD SecPerTrk + 1;

    PutReg(fdCTRL, ctlMotor + ctlDrive0 + side);

    ok := TRUE;
    IF track # curTrack THEN
      IF track = 0 THEN PutReg(fdCMD, cmdRestore)
      ELSE PutReg(fdDATA, track); PutReg(fdCMD, cmdSeek)
      END;
      ok := WaitNotBusy();
      IF ok THEN curTrack := track END
    END;

    IF ok THEN
      PutReg(fdSECTOR, sector);
      PutReg(fdCMD, cmdRead);
      ok := WaitDRQ();
      IF ok THEN
        i := 0;
        WHILE i < SecSize DO buf[i] := GetReg(fdDATA); INC(i) END;
        ok := WaitNotBusy()
      END
    END
  RETURN ok
  END ReadSector;

  (* ---- FAT12 geometry + lookup ---- *)

  PROCEDURE GetWord(VAR buf: ARRAY OF BYTE; ofs: INTEGER): INTEGER;
  BEGIN RETURN ORA(buf[ofs], ASL(buf[ofs + 1], 8)) END GetWord;

  PROCEDURE ReadBPB(): BOOLEAN;
    VAR nfat, root, tot, fpf, dataSecs, totClusters: INTEGER; ok: BOOLEAN;
  BEGIN ok := FALSE;
    IF ReadSector(0, secBuf) THEN
      IF GetWord(secBuf, bpbBPS) = SecSize THEN
        spc       := secBuf[bpbSPC];
        fatStart  := GetWord(secBuf, bpbRES);
        nfat      := secBuf[bpbNFAT];
        root      := GetWord(secBuf, bpbROOT);
        tot       := GetWord(secBuf, bpbTOT);
        fpf       := GetWord(secBuf, bpbFPF);
        fatSecs   := fpf;
        rootStart := fatStart + nfat * fpf;
        rootSecs  := (root * DirEntSize + SecSize - 1) DIV SecSize;
        dataStart := rootStart + rootSecs;
        rootEnts  := root;
        dataSecs  := tot - dataStart;
        totClusters := dataSecs DIV spc;
        maxClu    := totClusters + 1;
        isFAT12   := totClusters < 4085;
        ok := (fatSecs <= MaxFATSec) & isFAT12
      END
    END
  RETURN ok
  END ReadBPB;

  PROCEDURE LoadFAT(): BOOLEAN;
    VAR i, j, base: INTEGER; ok: BOOLEAN;
  BEGIN ok := TRUE; i := 0;
    WHILE (i < fatSecs) & ok DO
      ok := ReadSector(fatStart + i, secBuf);
      IF ok THEN
        base := i * SecSize; j := 0;
        WHILE j < SecSize DO fat[base + j] := secBuf[j]; INC(j) END
      END;
      INC(i)
    END
  RETURN ok
  END LoadFAT;

  PROCEDURE GetFAT(cluster: INTEGER): INTEGER;
    VAR ofs, val: INTEGER;
  BEGIN
    ofs := cluster + cluster DIV 2;               (* cluster * 1.5 *)
    val := ORA(fat[ofs], ASL(fat[ofs + 1], 8));
    IF ODD(cluster) THEN val := LSR(val, 4) ELSE val := AND(val, 0FFFH) END
  RETURN val
  END GetFAT;

  PROCEDURE ClusterToSector(c: INTEGER): INTEGER;
  BEGIN RETURN dataStart + (c - 2) * spc END ClusterToSector;

  (* match secBuf[base..base+10] against the 11-char 8.3 target *)
  PROCEDURE NameMatch(base: INTEGER): BOOLEAN;
    VAR i: INTEGER; ok: BOOLEAN;
  BEGIN i := 0; ok := TRUE;
    WHILE (i < 11) & ok DO
      IF secBuf[base + i] # ORD(target[i]) THEN ok := FALSE END;
      INC(i)
    END
  RETURN ok
  END NameMatch;

  (* scan the root directory for target; on hit set clu/size, return TRUE *)
  PROCEDURE FindFile(): BOOLEAN;
    VAR s, e, base, attr, first: INTEGER; found, atEnd: BOOLEAN;
  BEGIN found := FALSE; atEnd := FALSE; s := 0;
    WHILE (s < rootSecs) & ~found & ~atEnd DO
      IF ReadSector(rootStart + s, secBuf) THEN
        e := 0;
        WHILE (e < SecSize DIV DirEntSize) & ~found & ~atEnd DO
          base := e * DirEntSize;
          first := secBuf[base];
          IF first = 0 THEN atEnd := TRUE                 (* end of directory *)
          ELSIF first = 0E5H THEN                          (* deleted, skip *)
          ELSE
            attr := secBuf[base + deATTR];
            IF (attr # attrLFN) & (AND(attr, attrVolume + attrDir) = 0)
                & NameMatch(base) THEN
              clu  := GetWord(secBuf, base + deCLUSTER);
              size := GetWord(secBuf, base + deSIZE);      (* low 16 bits *)
              found := TRUE
            END
          END;
          INC(e)
        END
      ELSE atEnd := TRUE
      END;
      INC(s)
    END
  RETURN found
  END FindFile;

  (* follow the cluster chain, serial-dump up to DumpMax raw bytes *)
  (* ---- byte stream over the file's cluster chain ---- *)

  PROCEDURE InitStream(firstClu: INTEGER);
  BEGIN streamClu := firstClu; streamSecOfs := 0; streamPos := 0; streamLoaded := FALSE
  END InitStream;

  PROCEDURE NextByte(): INTEGER;
    VAR b: INTEGER;
  BEGIN
    IF ~streamLoaded OR (streamPos >= SecSize) THEN
      IF streamLoaded THEN
        INC(streamSecOfs);
        IF streamSecOfs >= spc THEN
          streamClu := GetFAT(streamClu); streamSecOfs := 0
        END
      END;
      IF ~ReadSector(ClusterToSector(streamClu) + streamSecOfs, secBuf) THEN
        (* leave secBuf as-is; caller sizes reads by header, not EOF *)
      END;
      streamPos := 0; streamLoaded := TRUE
    END;
    b := secBuf[streamPos]; INC(streamPos)
  RETURN b
  END NextByte;

  PROCEDURE NextWord(): INTEGER;
    VAR lo: INTEGER;
  BEGIN lo := NextByte() RETURN ORA(lo, ASL(NextByte(), 8)) END NextWord;

  (* ---- B3: load a relocated payload (MakePayload container) + EXEC it ----
     Header: codeBase codeLen varBase varSize dataLen entry (6x 16-bit LE),
     then code[codeLen], then data[dataLen]. All bank 0. *)
  PROCEDURE LoadPayload(firstClu: INTEGER);
    VAR codeBase, codeLen, varBase, varSize, dataLen, entry, i: INTEGER; bb: BYTE;
  BEGIN
    InitStream(firstClu);
    codeBase := NextWord(); codeLen := NextWord();
    varBase  := NextWord(); varSize := NextWord();
    dataLen  := NextWord(); entry   := NextWord();
    Str("load code="); Hex4(codeBase); Str("+"); Hex4(codeLen);
    Str(" var="); Hex4(varBase); Str("+"); Hex4(varSize);
    Str(" entry="); Hex4(entry); Ln;

    i := 0;                                        (* code -> codeBase *)
    WHILE i < codeLen DO bb := NextByte(); SYSTEM.PUT(0, codeBase + i, bb); INC(i) END;
    i := 0;                                        (* data image -> varBase+varSize *)
    WHILE i < dataLen DO bb := NextByte(); SYSTEM.PUT(0, varBase + varSize + i, bb); INC(i) END;
    bb := 0;                                       (* zero the BSS *)
    i := 0;
    WHILE i < varSize DO SYSTEM.PUT(0, varBase + i, bb); INC(i) END;

    Str("exec"); Ln;
    SYSTEM.EXEC(entry, 0);                          (* runs the payload, returns *)
    Str("returned"); Ln
  END LoadPayload;

BEGIN
  curTrack := -1;
  Str("OS16 boot"); Ln;
  target := "PAYLOAD 816";                 (* 8.3: "PAYLOAD.816" *)
  IF ReadBPB() THEN
    IF LoadFAT() THEN
      IF FindFile() THEN
        Str("found clu="); Hex4(clu); Str(" size="); Hex4(size); Ln;
        LoadPayload(clu)
      ELSE Str("not found"); Ln
      END
    ELSE Str("FAT read fail"); Ln
    END
  ELSE Str("BPB fail"); Ln
  END
END Boot.
