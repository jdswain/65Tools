MODULE BootManager;
(* The boot loader (model: BootManager), run from the boot ROM: reads
   PAYLOAD.816 from the root directory of the FAT12 floppy in drive 0 of
   the carrier's 82077AA, loads it and runs it, reporting on the serial
   port, channel A of the SoC's Z85C30 SCC. IMPORT SYSTEM only, fixed
   buffers (no NEW); the relocation is done by makerom.py. AND/LSR/ASL/ORA
   are oc816 builtins (no import).

   The 82077AA is worked by polling, as em16 -fpga emulates it: out of
   reset, SPECIFY non-DMA, CONFIGURE implied seek, RECALIBRATE, then READ
   DATA a sector at a time. The density is found by trying the data rates
   in turn (720K, 1.44M, 2.88M); the BPB's geometry is not trusted, as
   hdiutil's 720K images give 32 sectors a track there. *)
  IMPORT SYSTEM;

  CONST
    (* the Z85C30 SCC, channel A *)
    sccCtl  = 0822H;                (* RR0 bit 2: transmit buffer empty *)
    sccData = 0823H;

    (* the 82077AA, card 0 of the external bus *)
    fdDOR  = 0802H;                 (* motors 7-4, DMA gate 3, /RESET 2, select 1-0 *)
    fdMSR  = 0804H;                 (* R: RQM 7, DIO 6, non-DMA 5, busy 4 *)
    fdFIFO = 0805H;
    fdCCR  = 0807H;                 (* W: data rate *)
    rqm = 80H; dio = 40H; ndma = 20H;

    drive = 0;
    dorOn = 1CH;                    (* motor A, DMA gate, out of reset, drive 0 *)

    SecSize   = 512;
    MaxWait   = 30000;              (* 816 INTEGER is 16-bit signed (max 32767) *)
    MaxFATSec = 9;                  (* FAT12 on a 1.44M disk *)

    (* BPB field offsets *)
    bpbBPS = 11; bpbSPC = 13; bpbRES = 14; bpbNFAT = 16;
    bpbROOT = 17; bpbTOT = 19; bpbFPF = 22;

    (* directory-entry field offsets *)
    deATTR = 11; deCLUSTER = 26; deSIZE = 28; DirEntSize = 32;
    attrLFN = 0FH; attrVolume = 08H; attrDir = 10H;

  VAR
    secBuf: ARRAY SecSize OF BYTE;
    fat: ARRAY MaxFATSec * SecSize OF BYTE;
    spt: INTEGER;                   (* sectors a track, for the data rate found *)
    st: ARRAY 8 OF INTEGER;         (* the last result phase *)
    fatStart, rootStart, rootSecs, dataStart, spc, rootEnts, fatSecs, maxClu: INTEGER;
    isFAT12: BOOLEAN;
    clu, size: INTEGER;
    target: ARRAY 12 OF CHAR;
    (* payload byte-stream over the cluster chain *)
    streamClu, streamSecOfs, streamPos: INTEGER; streamLoaded: BOOLEAN;

  (* ---- register access ---- *)

  PROCEDURE PutReg(reg, val: INTEGER);
    VAR b: BYTE;
  BEGIN b := val; SYSTEM.PUT(0, reg, b) END PutReg;

  PROCEDURE GetReg(reg: INTEGER): INTEGER;
    VAR b: BYTE; v: INTEGER;
  BEGIN SYSTEM.GET(0, reg, b); v := b RETURN v END GetReg;

  (* ---- serial output ---- *)

  PROCEDURE Wr(ch: CHAR);
  BEGIN
    WHILE AND(GetReg(sccCtl), 4) = 0 DO END;
    PutReg(sccData, ORD(ch))
  END Wr;

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

  PROCEDURE InitSerial;
    VAR v: INTEGER;
  BEGIN
    v := GetReg(sccCtl);            (* the register pointer back to 0 *)
    PutReg(sccCtl, 5); PutReg(sccCtl, 68H)   (* WR5: transmit on, 8 bits *)
  END InitSerial;

  (* ---- the 82077AA ---- *)

  (* until MSR AND mask = val, a bounded while *)
  PROCEDURE WaitMSR(mask, val: INTEGER): BOOLEAN;
    VAR n, m: INTEGER; ok: BOOLEAN;
  BEGIN m := 0; ok := AND(GetReg(fdMSR), mask) = val;
    WHILE ~ok & (m < 100) DO
      n := 0;
      WHILE ~ok & (n < MaxWait) DO ok := AND(GetReg(fdMSR), mask) = val; INC(n) END;
      INC(m)
    END
  RETURN ok
  END WaitMSR;

  (* a command or parameter byte *)
  PROCEDURE Cmd(v: INTEGER): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN ok := WaitMSR(rqm + dio, rqm);
    IF ok THEN PutReg(fdFIFO, v) END
  RETURN ok
  END Cmd;

  (* the result phase into st: how many bytes *)
  PROCEDURE Result(): INTEGER;
    VAR n: INTEGER;
  BEGIN n := 0;
    IF WaitMSR(rqm, rqm) THEN
      WHILE (n < LEN(st)) & (AND(GetReg(fdMSR), rqm + dio + 10H) = rqm + dio + 10H) DO
        st[n] := GetReg(fdFIFO); INC(n)
      END
    END
  RETURN n
  END Result;

  (* SENSE INTERRUPT STATUS: TRUE if an interrupt was pending *)
  PROCEDURE SenseInt(): BOOLEAN;
  BEGIN RETURN Cmd(8) & (Result() = 2)
  END SenseInt;

  PROCEDURE InitFDC(): BOOLEAN;
    VAR i, n: INTEGER; ok, done: BOOLEAN;
  BEGIN
    PutReg(fdDOR, 0); PutReg(fdDOR, dorOn);
    i := 0; WHILE i < 4 DO done := SenseInt(); INC(i) END;   (* the reset's ready changes *)
    ok := Cmd(3) & Cmd(0DFH) & Cmd(3);                      (* SPECIFY: 3 ms steps, non-DMA *)
    ok := ok & Cmd(13H) & Cmd(0) & Cmd(50H) & Cmd(0);       (* CONFIGURE: implied seek, no polling *)
    ok := ok & Cmd(7) & Cmd(drive);                         (* RECALIBRATE *)
    n := 0; done := FALSE;
    WHILE ok & ~done & (n < MaxWait) DO done := SenseInt(); INC(n) END
  RETURN ok & done
  END InitFDC;

  (* ---- read one 512-byte sector (linear LBA) into buf ---- *)

  PROCEDURE ReadSector(lba: INTEGER; VAR buf: ARRAY OF BYTE): BOOLEAN;
    VAR c, h, r, i, msr: INTEGER; ok: BOOLEAN;
  BEGIN
    c := lba DIV (2 * spt); h := lba DIV spt MOD 2; r := lba MOD spt + 1;
    ok := Cmd(46H) & Cmd(h * 4 + drive) & Cmd(c) & Cmd(h) & Cmd(r)
      & Cmd(2) & Cmd(r) & Cmd(1BH) & Cmd(0FFH);           (* READ DATA, MFM, one sector *)
    i := 0;
    WHILE ok & WaitMSR(rqm, rqm) & (AND(GetReg(fdMSR), ndma) # 0) DO
      msr := GetReg(fdFIFO);
      IF i < SecSize THEN buf[i] := msr END;
      INC(i)
    END;
    (* polled, no terminal count: a sector read ends "end of cylinder" *)
    ok := ok & (Result() = 7) & (i = SecSize) & (st[2] = 0)
      & ((AND(st[0], 0C0H) = 0) OR (AND(st[0], 0C0H) = 40H) & (st[1] = 80H))
  RETURN ok
  END ReadSector;

  (* the density of the disk: sector 0 read at 250, 500, then 1000 kbit/s *)
  PROCEDURE FindDensity(): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN
    PutReg(fdCCR, 2); spt := 9; ok := ReadSector(0, secBuf);
    IF ~ok THEN PutReg(fdCCR, 0); spt := 18; ok := ReadSector(0, secBuf) END;
    IF ~ok THEN PutReg(fdCCR, 3); spt := 36; ok := ReadSector(0, secBuf) END
  RETURN ok
  END FindDensity;

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
  InitSerial;
  Str("OS16 boot"); Ln;
  target := "PAYLOAD 816";                 (* 8.3: "PAYLOAD.816" *)
  IF ~InitFDC() THEN Str("no floppy controller"); Ln
  ELSIF ~FindDensity() THEN Str("no disk"); Ln
  ELSIF ReadBPB() THEN
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
END BootManager.
