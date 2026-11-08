MODULE EmEth; (* The carrier's ENC424J600 Ethernet controller (Microchip
   DS39935C) in its 8-bit parallel mode 5, on the external bus's select 5,
   with the network of -net (EmHost.NetOpen) on the other side of its
   cable.

   The carrier ties AD<14:9> high, so the bus reaches 7E00h-7FFFh: the
   SFRs at 7E00h-7E9Fh, their Bit Set aliases at +100h and Bit Clear at
   +180h. The 24K of SRAM is reached through the windows EGPDATA, ERXDATA
   and EUDADATA. The slot, $0850 (Hardware.md's Ethernet section):
     +0 write  the address latch's low byte, AD8 = 0 (7E00h-7EFFh)
     +2 write  the same, AD8 = 1 (7F00h-7FFFh)
     +1, +3    read or write the byte at the latched address; the latch
               holds, so a window is streamed without a new address
   A read of +0 or +2 strobes nothing: $FF. ext_a[3:2] are not connected.

   What it does: the SFRs with their reset values, mirrors, aliases and
   the MAC registers' low-byte-then-high write; the three windows and
   their wrap rules; transmission (ETXST, ETXLEN, TXRTS; TXMAC, PADCFG,
   TXCRCEN; ETXSTAT, ETXWIRE, TXIF) in the time the frame takes at 100
   Mb/s; reception into the ring from ERXST (the next packet pointer, the
   receive status vector, the frame and its CRC, PKTCNT, PKTDEC, the
   filters of ERXFCON: unicast, not-me, multicast, broadcast, the hash
   table, magic packet); the DMA's copy and checksum, at once; the
   interrupts (EIR, EIE, INTIE) onto the cards' IRQ#; ETHRST, TXRST and
   RXRST; MAC loopback; and the PHY through MIREGADR, MICMD, MIRD and
   MIWR, a 100 Mb/s full duplex link that comes up 5 ms after a reset
   when there is a network (-net), and stays down without one.

   Left out: half duplex, collisions and flow control (FCOP's single
   pause frames end at once, nothing is sent), the pattern match filter,
   the crypto engines (MODEXST and AESST end at once with their flags set,
   the results meaningless), the LEDs and CLKOUT, power saving, and the
   recovery times after a reset (25 us, the PHY's 256 us), which are not
   enforced. *)

  IMPORT EmHost;

  CONST
    Size = 6000H;               (* the SRAM *)
    Max = 1600;                 (* a frame's bytes, at most *)
    (* the SFRs, as offsets from 7E00h *)
    ETXST = 0; ETXLEN = 2; ERXST = 4; ERXTAIL = 6; ERXHEAD = 8; EDMAST = 0AH;
    EDMALEN = 0CH; EDMADST = 0EH; EDMACS = 10H; ETXSTAT = 12H; ETXWIRE = 14H;
    EUDAST = 16H; EUDAND = 18H; ESTAT = 1AH; EIR = 1CH; ECON1 = 1EH;
    EHT1 = 20H; ERXFCON = 34H; MACON1 = 40H; MACON2 = 42H; MAMXFL = 4AH;
    MICMD = 52H; MIREGADR = 54H; MAADR3 = 60H; MAADR2 = 62H; MAADR1 = 64H;
    MIWR = 66H; MIRD = 68H; MISTAT = 6AH; EPAUS = 6CH; ECON2 = 6EH;
    ERXWM = 70H; EIE = 72H; EIDLED = 74H;
    EGPDATA = 80H; ERXDATA = 82H; EUDADATA = 84H; EGPRDPT = 86H;
    EGPWRPT = 88H; ERXRDPT = 8AH; ERXWRPT = 8CH; EUDARDPT = 8EH; EUDAWRPT = 90H;
    (* EIR's bits *)
    PCFULIF = 1; RXABTIF = 2; TXABTIF = 4; TXIF = 8; DMAIF = 20H; PKTIF = 40H;
    LINKIF = 800H; AESIF = 1000H; MODEXIF = 4000H;

  VAR
    LinkTime, PollTime: LONGINT;    (* 5 ms from a reset to the link up; the network looked at each 250 us *)
    sram: ARRAY Size OF BYTE;
    reg: ARRAY 0A0H OF INTEGER;     (* the SFRs' bytes *)
    low: ARRAY 0A0H OF INTEGER;     (* a MAC register's low byte, until its high byte is written *)
    phy: ARRAY 32 OF INTEGER;
    mac*: ARRAY 6 OF INTEGER;       (* the factory address, 00:04:A3:... (-mac) *)
    latch: INTEGER;                 (* the address latch, 0-1FFh *)
    headH: INTEGER;                 (* ERXHEAD's high byte, latched by reading its low *)
    pktcnt: INTEGER;
    ignored: BOOLEAN;               (* a frame was dropped since the last one received *)
    net*: BOOLEAN;                  (* -net opened: the cable is in *)
    link: BOOLEAN; linkAt: LONGINT; (* the link, and when it comes up (-1 never) *)
    phane: INTEGER;                 (* PHANE's latched LPARCD *)
    txBusy: BOOLEAN; txAt: LONGINT; (* a transmission, and when it ends *)
    nextPoll: LONGINT;
    crcTab: ARRAY 256 OF INTEGER;
    f: ARRAY Max OF BYTE;           (* a frame, sent or received *)
    sent*, received*, dropped*: INTEGER;

  (* --- the registers --- *)

  PROCEDURE W(i: INTEGER): INTEGER;
  BEGIN RETURN reg[i] + reg[i + 1] * 100H
  END W;

  PROCEDURE SetW(i, v: INTEGER);
  BEGIN reg[i] := AND(v, 0FFH); reg[i + 1] := AND(LSR(v, 8), 0FFH)
  END SetW;

  (* EUDAST to ECON1 are at 16h-1Fh of each row of 32 *)
  PROCEDURE Canon(i: INTEGER): INTEGER;
  BEGIN IF (i < 80H) & (AND(i, 1FH) >= 16H) THEN i := AND(i, 1FH) END;
    RETURN i
  END Canon;

  PROCEDURE Mac(i: INTEGER): BOOLEAN;     (* a MAC or MII register: written low, then high *)
  BEGIN RETURN (i >= 40H) & (i < 6CH)
  END Mac;

  (* the register has Bit Set and Bit Clear aliases *)
  PROCEDURE Alias(i: INTEGER): BOOLEAN;
  BEGIN RETURN (i < 80H) & ~Mac(i) & ~((i >= 8) & (i < 0AH)) & ~((i >= 12H) & (i < 16H)) & ~((i >= 1AH) & (i < 1CH))
      & (i < 76H)
  END Alias;

  (* byte k of the MAC address: MAADR1L, MAADR1H, MAADR2L, ... *)
  PROCEDURE Adr(k: INTEGER): INTEGER;
  BEGIN RETURN MAADR1 - 2 * (k DIV 2) + k MOD 2
  END Adr;

  PROCEDURE Raise(bits: INTEGER);
  BEGIN SetW(EIR, ORA(W(EIR), bits))
  END Raise;

  (* --- the CRC --- *)

  PROCEDURE CRC(VAR b: ARRAY OF BYTE; n: INTEGER): INTEGER;   (* zlib's crc32 *)
    VAR c, i: INTEGER;
  BEGIN c := -1;
    FOR i := 0 TO n - 1 DO c := EOR(LSR(c, 8), crcTab[AND(EOR(c, b[i]), 0FFH)]) END;
    RETURN EOR(c, -1)
  END CRC;

  (* the hash table's bit for the destination at b: bits 28-23 of the CRC
     the chip computes, bit-serial and not reflected (DS39935C 10.9) *)
  PROCEDURE Hash(VAR b: ARRAY OF BYTE): INTEGER;
    VAR c, r, i: INTEGER;
  BEGIN c := EOR(CRC(b, 6), -1); r := 0;
    FOR i := 0 TO 31 DO r := ORA(ASL(r, 1), AND(c, 1)); c := LSR(c, 1) END;
    RETURN AND(LSR(r, 23), 3FH)
  END Hash;

  (* --- the SRAM's pointers --- *)

  PROCEDURE Ram(p: INTEGER): INTEGER;
    VAR v: INTEGER;
  BEGIN v := 0; IF p < Size THEN v := sram[p] END;
    RETURN v
  END Ram;

  PROCEDURE Poke(p, v: INTEGER);
  BEGIN IF p < Size THEN sram[p] := v END
  END Poke;

  PROCEDURE NextGP(p: INTEGER): INTEGER;
  BEGIN
    IF (p = W(ERXST) - 1) OR (p = Size - 1) THEN p := 0 ELSE p := AND(p + 1, 7FFFH) END;
    RETURN p
  END NextGP;

  PROCEDURE NextRX(p: INTEGER): INTEGER;
  BEGIN IF p = Size - 1 THEN p := W(ERXST) ELSE p := AND(p + 1, 7FFFH) END;
    RETURN p
  END NextRX;

  PROCEDURE NextUDA(p: INTEGER): INTEGER;
  BEGIN
    IF p = W(EUDAND) THEN p := W(EUDAST) ELSIF p = Size - 1 THEN p := 0 ELSE p := AND(p + 1, 7FFFH) END;
    RETURN p
  END NextUDA;

  PROCEDURE NextTX(p: INTEGER): INTEGER;          (* the transmitter's, and the DMA's after the UDA's *)
  BEGIN
    IF p = W(ERXST) - 1 THEN p := 0 ELSIF p = Size - 1 THEN p := W(ERXST) ELSE p := AND(p + 1, 7FFFH) END;
    RETURN p
  END NextTX;

  PROCEDURE NextDMA(p: INTEGER): INTEGER;
  BEGIN IF p = W(EUDAND) THEN p := W(EUDAST) ELSE p := NextTX(p) END;
    RETURN p
  END NextDMA;

  (* --- the PHY --- *)

  PROCEDURE PhyReset(now: LONGINT);
    VAR i: INTEGER;
  BEGIN
    FOR i := 0 TO 31 DO phy[i] := 0FFFFH END;
    phy[0] := 1000H; phy[2] := 0; phy[3] := 0; phy[4] := 01E1H; phy[5] := 0; phy[6] := 0;
    phy[10H] := 0; phy[11H] := 2; phy[12H] := 0; phy[1BH] := 000BH; phy[1FH] := 0040H;
    FOR i := 14H TO 17H DO phy[i] := 0 END; FOR i := 1CH TO 1EH DO phy[i] := 0 END;
    phy[1] := 7809H; phane := 0;
    IF link THEN link := FALSE; Raise(LINKIF) END;
    IF net THEN linkAt := now + LinkTime ELSE linkAt := -1 END
  END PhyReset;

  PROCEDURE LinkUp;
  BEGIN link := TRUE; linkAt := -1;
    phy[1] := 782DH; phy[5] := 45E1H; phy[1FH] := 0058H; phane := 2; Raise(LINKIF)
  END LinkUp;

  PROCEDURE PhyRead(r: INTEGER): INTEGER;
    VAR v: INTEGER;
  BEGIN r := AND(r, 1FH); v := phy[r];
    IF r = 6 THEN
      IF link THEN v := ORA(1, phane); phane := 0 ELSE v := 0 END
    END;
    RETURN v
  END PhyRead;

  PROCEDURE PhyWrite(r, v: INTEGER; now: LONGINT);
  BEGIN r := AND(r, 1FH);
    IF r = 0 THEN
      IF AND(v, 8000H) # 0 THEN PhyReset(now)                    (* PRST *)
      ELSE phy[0] := AND(v, 7D00H);
        IF AND(v, 200H) # 0 THEN                               (* RENEG *)
          IF link THEN link := FALSE; phy[1] := 7809H; phy[1FH] := 0040H; Raise(LINKIF) END;
          IF net THEN linkAt := now + LinkTime END
        END
      END
    ELSIF r = 4 THEN phy[4] := ORA(AND(v, 2DE0H), 1)
    ELSIF r = 11H THEN phy[11H] := ORA(AND(v, 2804H), AND(phy[11H], 2))
    END
  END PhyWrite;

  (* --- reset --- *)

  PROCEDURE SysReset(now: LONGINT);   (* power on, and ETHRST but for COCON *)
    VAR i: INTEGER;
  BEGIN
    FOR i := 0 TO 0A0H - 1 DO reg[i] := 0 END;
    SetW(ERXST, 5340H); SetW(ERXTAIL, 5FFEH); SetW(ERXHEAD, 5340H); SetW(EUDAND, 5FFFH);
    SetW(EIR, 0A00H); SetW(ERXFCON, 0059H); SetW(MACON1, 000DH); SetW(MACON2, 40B2H);
    SetW(44H, 0012H); SetW(46H, 0C12H); SetW(48H, 370FH); SetW(MAMXFL, 05EEH); SetW(MIREGADR, 0100H);
    FOR i := 0 TO 5 DO reg[Adr(i)] := mac[i] END;
    SetW(EPAUS, 1000H); SetW(ECON2, 0CB00H); SetW(ERXWM, 100FH); SetW(EIE, 8010H); SetW(EIDLED, 2622H);
    SetW(EGPRDPT, 05FAH); SetW(ERXRDPT, 05FAH); SetW(EUDARDPT, 05FAH);
    FOR i := 0 TO 0A0H - 1 DO low[i] := reg[i] END;
    pktcnt := 0; ignored := FALSE; txBusy := FALSE; headH := -1;
    PhyReset(now)
  END SysReset;

  (* --- receiving --- *)

  (* f's n bytes, a frame without its CRC: kept in the ring if the filters
     let it in and there is room *)
  PROCEDURE Deliver(n: INTEGER);
    VAR i, c, fcon, head, tail, size, free, need, next, p, typ: INTEGER;
        me, bcast, mcast, ok, hash, magic: BOOLEAN; rsv: ARRAY 6 OF INTEGER;
  BEGIN
    IF ODD(reg[ECON1]) & (AND(W(ECON2), 8000H) # 0) & (AND(reg[ECON2], 20H) = 0) & (n >= 14) THEN
      WHILE n < 60 DO f[n] := 0; INC(n) END;
      c := CRC(f, n);
      FOR i := 0 TO 3 DO f[n + i] := AND(LSR(c, 8 * i), 0FFH) END;
      INC(n, 4);
      me := TRUE; FOR i := 0 TO 5 DO IF f[i] # reg[Adr(i)] THEN me := FALSE END END;
      bcast := TRUE; FOR i := 0 TO 5 DO IF f[i] # 0FFH THEN bcast := FALSE END END;
      mcast := ODD(f[0]);
      typ := f[12] * 100H + f[13];
      hash := AND(LSR(W(EHT1 + 2 * (Hash(f) DIV 16)), Hash(f) MOD 16), 1) # 0;
      magic := FALSE;
      i := 0;
      WHILE ~magic & (i + 102 <= n) DO
        magic := TRUE; c := 0;
        WHILE magic & (c < 6) DO magic := f[i + c] = 0FFH; INC(c) END;
        WHILE magic & (c < 102) DO magic := f[i + c] = reg[Adr((c - 6) MOD 6)]; INC(c) END;
        INC(i)
      END;
      fcon := W(ERXFCON);
      ok := (AND(fcon, 8) # 0) & me OR (AND(fcon, 4) # 0) & ~mcast & ~me OR (AND(fcon, 2) # 0) & mcast
        OR ODD(fcon) & bcast OR (AND(fcon, 8000H) # 0) & hash OR (AND(fcon, 4000H) # 0) & magic;
      IF (typ = 8808H) & (AND(W(MACON1), 2) = 0) THEN ok := FALSE END;       (* a MAC control frame, but PASSALL *)
      IF ok THEN
        head := W(ERXHEAD); tail := W(ERXTAIL); size := Size - W(ERXST);
        free := tail - head; IF free < 0 THEN INC(free, size) END;
        need := 8 + n; IF ODD(need) THEN INC(need) END;
        IF (need <= free - 2) & (pktcnt < 0FFH) THEN
          next := head; FOR i := 1 TO need DO next := NextRX(next) END;
          rsv[0] := AND(n, 0FFH); rsv[1] := LSR(n, 8);
          rsv[2] := 80H; IF typ > 1500 THEN INC(rsv[2], 40H) END; IF ignored THEN INC(rsv[2], 1) END;
          rsv[3] := 0;
          IF bcast THEN INC(rsv[3], 2) ELSIF mcast THEN INC(rsv[3], 1) END;
          IF typ = 8808H THEN INC(rsv[3], 8) END; IF typ = 8100H THEN INC(rsv[3], 40H) END;
          rsv[4] := 0; IF me THEN INC(rsv[4], 10H) END; IF hash THEN INC(rsv[4], 2) END;
          IF ~mcast & ~me THEN INC(rsv[4], 1) END; IF magic THEN INC(rsv[4], 4) END;
          rsv[5] := 0;
          p := head; Poke(p, AND(next, 0FFH)); p := NextRX(p); Poke(p, LSR(next, 8)); p := NextRX(p);
          FOR i := 0 TO 5 DO Poke(p, rsv[i]); p := NextRX(p) END;
          FOR i := 0 TO n - 1 DO Poke(p, f[i]); p := NextRX(p) END;
          SetW(ERXHEAD, next); ignored := FALSE; INC(pktcnt); INC(received);
          IF pktcnt = 0FFH THEN Raise(PCFULIF) END
        ELSE ignored := TRUE; INC(dropped); Raise(RXABTIF)
        END
      END
    END
  END Deliver;

  (* --- transmitting --- *)

  PROCEDURE StartTx(now: LONGINT);
    VAR n, len, p, i, pad, c, macon2: INTEGER;
  BEGIN len := W(ETXLEN); p := W(ETXST); n := 0; macon2 := W(MACON2);
    i := 0;
    WHILE (i < len) & (n < Max - 4) DO
      IF (n = 6) & (AND(W(ECON2), 2000H) # 0) THEN                   (* TXMAC: the source *)
        WHILE n < 12 DO f[n] := reg[Adr(n - 6)]; INC(n) END
      END;
      f[n] := Ram(p); INC(n); p := NextTX(p); INC(i)
    END;
    IF (n = 6) & (AND(W(ECON2), 2000H) # 0) THEN WHILE n < 12 DO f[n] := reg[Adr(n - 6)]; INC(n) END END;
    pad := AND(LSR(macon2, 5), 7);
    IF ODD(pad) THEN                                               (* PADCFG: 60, or 64 *)
      c := 60;
      IF (pad = 3) OR (pad = 7) OR (pad = 5) & (n >= 14) & (f[12] = 81H) & (f[13] = 0) THEN c := 64 END;
      WHILE n < c DO f[n] := 0; INC(n) END
    END;
    SetW(ETXSTAT, 0);
    IF AND(macon2, 10H) # 0 THEN SetW(ETXWIRE, n + 4)               (* TXCRCEN: the CRC added *)
    ELSE SetW(ETXWIRE, n); IF n >= 4 THEN DEC(n, 4) END             (* the frame's own, not sent on *)
    END;
    IF link THEN
      IF AND(W(MACON1), 10H) # 0 THEN Deliver(n)                     (* LOOPBK *)
      ELSE EmHost.NetSend(f, n)
      END;
      INC(sent)
    END;
    txBusy := TRUE; txAt := now + (W(ETXWIRE) + 20) * EmHost.hz DIV 12500000   (* 80 ns a byte at 100 Mb/s *)
  END StartTx;

  PROCEDURE EndTx(bits: INTEGER);
  BEGIN txBusy := FALSE; reg[ECON1] := AND(reg[ECON1], 0FDH); Raise(bits)
  END EndTx;

  (* --- the DMA --- *)

  PROCEDURE DMA;
    VAR src, dst, len, i, sum, b, econ1: INTEGER; cs: BOOLEAN;
  BEGIN econ1 := reg[ECON1]; src := W(EDMAST); dst := W(EDMADST); len := W(EDMALEN);
    cs := AND(econ1, 4) = 0; sum := 0;
    IF AND(econ1, 8) # 0 THEN sum := EOR(W(EDMACS), 0FFFFH) END;
    FOR i := 0 TO len - 1 DO b := Ram(src);
      IF ODD(i) THEN sum := sum + b ELSE sum := sum + b * 100H END;
      IF AND(econ1, 10H) # 0 THEN Poke(dst, b); dst := NextDMA(dst) END;
      src := NextDMA(src)
    END;
    IF cs THEN
      WHILE sum > 0FFFFH DO sum := AND(sum, 0FFFFH) + LSR(sum, 16) END;
      SetW(EDMACS, EOR(sum, 0FFFFH))
    END;
    reg[ECON1] := AND(reg[ECON1], 0DFH); Raise(DMAIF)
  END DMA;

  (* --- the bus --- *)

  PROCEDURE Flags(): INTEGER;           (* EIR, PKTIF from PKTCNT *)
    VAR v: INTEGER;
  BEGIN v := AND(W(EIR), 0FFBFH); IF pktcnt # 0 THEN INC(v, PKTIF) END;
    RETURN v
  END Flags;

  PROCEDURE Status(): INTEGER;          (* ESTAT *)
    VAR v: INTEGER;
  BEGIN v := 5000H + pktcnt;              (* FCIDLE, CLKRDY *)
    IF link THEN INC(v, 500H) END;          (* PHYDPX, PHYLNK *)
    IF AND(AND(Flags(), W(EIE)), 786FH) # 0 THEN INC(v, 8000H) END;
    RETURN v
  END Status;

  PROCEDURE Irq*(): BOOLEAN;            (* /INT, low *)
    VAR e: INTEGER;
  BEGIN e := W(EIE);
    RETURN (AND(e, 8000H) # 0) & (AND(AND(Flags(), e), 786FH) # 0)
  END Irq;

  (* the base register's byte i (canonical), as it reads *)
  PROCEDURE Get(i: INTEGER): INTEGER;
    VAR v: INTEGER;
  BEGIN
    IF (i = ESTAT) OR (i = ESTAT + 1) THEN v := AND(LSR(Status(), 8 * (i - ESTAT)), 0FFH)
    ELSIF (i = EIR) OR (i = EIR + 1) THEN v := AND(LSR(Flags(), 8 * (i - EIR)), 0FFH)
    ELSIF (i = MIRD) OR (i = MIRD + 1) THEN
      IF ODD(reg[MICMD] DIV 2) THEN SetW(MIRD, PhyRead(reg[MIREGADR])) END;     (* MIISCAN *)
      v := reg[i]
    ELSIF i = MISTAT THEN v := 0; IF ODD(reg[MICMD] DIV 2) THEN v := 2 END
    ELSIF (i = EGPDATA + 1) OR (i = ERXDATA + 1) OR (i = EUDADATA + 1) OR (i >= 92H) THEN v := 0
    ELSE v := reg[i]
    END;
    RETURN v
  END Get;

  (* byte i (canonical) of a base register written v *)
  PROCEDURE Put(i, v: INTEGER; now: LONGINT);
    VAR old, x: INTEGER;
  BEGIN v := AND(v, 0FFH); old := reg[i];
    IF i < ERXHEAD THEN reg[i] := v;
      IF ODD(i) THEN reg[i] := AND(v, 7FH) END;
      IF i = ERXST THEN reg[i] := AND(v, 0FEH) END;
      IF (i = ERXST) OR (i = ERXST + 1) THEN SetW(ERXHEAD, W(ERXST)) END
    ELSIF (i >= EDMAST) & (i < ETXSTAT) THEN reg[i] := v;
      IF ODD(i) & (i < EDMACS) THEN reg[i] := AND(v, 7FH) END
    ELSIF i = EUDAST THEN reg[i] := AND(v, 0FEH)
    ELSIF i = EUDAND THEN reg[i] := ORA(v, 1)
    ELSIF (i = EUDAST + 1) OR (i = EUDAND + 1) THEN reg[i] := AND(v, 7FH)
    ELSIF i = EIR THEN reg[i] := ORA(AND(v, 2FH), AND(old, 50H))
    ELSIF i = EIR + 1 THEN reg[i] := ORA(AND(v, 0F8H), AND(old, 7))
    ELSIF i = ECON1 THEN
      IF ~ODD(old DIV 2) & ODD(v DIV 2) & (W(ETXLEN) < 8) THEN DEC(v, 2) END;
      IF AND(v, 0C0H) # 80H THEN v := AND(v, 3FH) END;                  (* FCOP 01 and 11 done at once *)
      reg[i] := v;
      IF ~ODD(old DIV 2) & ODD(v DIV 2) THEN StartTx(now)
      ELSIF ODD(old DIV 2) & ~ODD(v DIV 2) & txBusy THEN EndTx(TXIF + TXABTIF)
      END;
      IF (AND(old, 20H) = 0) & (AND(v, 20H) # 0) THEN DMA END
    ELSIF i = ECON1 + 1 THEN x := v;
      IF ODD(v) THEN                                                      (* PKTDEC *)
        IF pktcnt > 0 THEN DEC(pktcnt); SetW(EIR, AND(W(EIR), 0FFFEH)) END; DEC(x)
      END;
      IF AND(x, 8) # 0 THEN DEC(x, 8); Raise(AESIF) END;                  (* AESST, MODEXST: at once *)
      IF AND(x, 80H) # 0 THEN DEC(x, 80H); Raise(MODEXIF) END;
      reg[i] := x
    ELSIF i = ECON2 THEN
      IF AND(v, 10H) # 0 THEN x := reg[ECON2 + 1]; SysReset(now);         (* ETHRST, but for COCON *)
        reg[ECON2 + 1] := ORA(AND(reg[ECON2 + 1], 0F0H), AND(x, 0FH))
      ELSE reg[i] := v;
        IF AND(v, 40H) # 0 THEN reg[ECON1] := AND(reg[ECON1], 0FDH); txBusy := FALSE END;   (* TXRST *)
        IF AND(v, 20H) # 0 THEN reg[ECON1] := AND(reg[ECON1], 0FEH) END                     (* RXRST *)
      END
    ELSIF i = EIE THEN reg[i] := ORA(AND(v, 6FH), 10H)
    ELSIF i = EIE + 1 THEN reg[i] := AND(v, 0F8H)
    ELSIF i = EIDLED THEN                                                 (* DEVID, REVID: read only *)
    ELSIF Mac(i) THEN
      IF ~ODD(i) THEN low[i] := v
      ELSIF (i # MIRD + 1) & (i # MISTAT + 1) THEN reg[i - 1] := low[i - 1]; reg[i] := v;
        IF i = MICMD + 1 THEN
          reg[MICMD] := AND(reg[MICMD], 3); reg[MICMD + 1] := 0;
          IF ODD(reg[MICMD]) THEN SetW(MIRD, PhyRead(reg[MIREGADR])) END
        ELSIF i = MIWR + 1 THEN PhyWrite(reg[MIREGADR], W(MIWR), now)
        END
      END
    ELSIF i = EGPDATA THEN x := W(EGPWRPT); Poke(x, v); SetW(EGPWRPT, NextGP(x))
    ELSIF i = ERXDATA THEN x := W(ERXWRPT); Poke(x, v); SetW(ERXWRPT, NextRX(x))
    ELSIF i = EUDADATA THEN x := W(EUDAWRPT); Poke(x, v); SetW(EUDAWRPT, NextUDA(x))
    ELSIF (i >= EGPRDPT) & (i < 92H) THEN reg[i] := v; IF ODD(i) THEN reg[i] := AND(v, 7FH) END
    ELSIF ((i >= EHT1) & (i < 36H)) OR (i = EPAUS) OR (i = EPAUS + 1) OR (i = ECON2 + 1) OR (i = ERXWM) OR (i = ERXWM + 1) OR (i = EIDLED + 1) THEN
      reg[i] := v
    END
  END Put;

  (* a read of the byte at 7E00h + a *)
  PROCEDURE ReadAt(a: INTEGER): INTEGER;
    VAR i, v, p: INTEGER;
  BEGIN v := 0;
    IF a < 0A0H THEN i := Canon(a);
      IF i = EGPDATA THEN p := W(EGPRDPT); v := Ram(p); SetW(EGPRDPT, NextGP(p))
      ELSIF i = ERXDATA THEN p := W(ERXRDPT); v := Ram(p); SetW(ERXRDPT, NextRX(p))
      ELSIF i = EUDADATA THEN p := W(EUDARDPT); v := Ram(p); SetW(EUDARDPT, NextUDA(p))
      ELSIF i = ERXHEAD THEN v := reg[i]; headH := reg[i + 1]
      ELSIF i = ERXHEAD + 1 THEN
        IF headH >= 0 THEN v := headH; headH := -1 ELSE v := reg[i] END
      ELSE v := Get(i)
      END
    ELSIF a >= 100H THEN i := Canon(AND(a, 7FH)); v := Get(i)        (* an alias: the register's value *)
    END;
    RETURN v
  END ReadAt;

  PROCEDURE WriteAt(a, v: INTEGER; now: LONGINT);
    VAR i: INTEGER;
  BEGIN
    IF a < 0A0H THEN Put(Canon(a), v, now)
    ELSIF a >= 100H THEN i := Canon(AND(a, 7FH));
      IF Alias(i) THEN
        IF a < 180H THEN Put(i, ORA(reg[i], v), now)
        ELSE Put(i, AND(reg[i], EOR(v, 0FFH)), now)
        END
      END
    END
  END WriteAt;

  (* --- the slot --- *)

  PROCEDURE Tick*(now: LONGINT);
    VAR n: INTEGER;
  BEGIN
    IF txBusy & (now >= txAt) THEN EndTx(TXIF) END;
    IF (linkAt >= 0) & (now >= linkAt) THEN LinkUp END;
    IF net & (now >= nextPoll) THEN nextPoll := now + PollTime;
      n := EmHost.NetRecv(f);
      WHILE n > 0 DO IF link THEN Deliver(n) END; n := EmHost.NetRecv(f) END
    END
  END Tick;

  PROCEDURE Read*(a: INTEGER; now: LONGINT): INTEGER;
    VAR v: INTEGER;
  BEGIN Tick(now);
    IF ODD(a) THEN v := ReadAt(latch) ELSE v := 0FFH END;
    RETURN v
  END Read;

  PROCEDURE Write*(a, v: INTEGER; now: LONGINT);
  BEGIN Tick(now);
    IF ODD(a) THEN WriteAt(latch, v, now)
    ELSIF AND(a, 2) = 0 THEN latch := AND(v, 0FFH)
    ELSE latch := 100H + AND(v, 0FFH)
    END
  END Write;

  (* -net spec *)
  PROCEDURE Open*(spec: ARRAY OF CHAR): BOOLEAN;
  BEGIN net := EmHost.NetOpen(spec) # 0;
    IF net & ~link & (linkAt < 0) THEN linkAt := LinkTime END;
    RETURN net
  END Open;

  (* -mac aa:bb:cc:dd:ee:ff, the factory address *)
  PROCEDURE SetMac*(s: ARRAY OF CHAR): BOOLEAN;
    VAR i, k, d, v: INTEGER; ok: BOOLEAN; ch: CHAR;
  BEGIN i := 0; k := 0; ok := TRUE;
    WHILE ok & (k < 6) DO v := 0; d := 0;
      WHILE (i < LEN(s)) & (s[i] # 0X) & (s[i] # ":") & ok DO ch := s[i];
        IF (ch >= "0") & (ch <= "9") THEN v := v * 16 + ORD(ch) - ORD("0")
        ELSIF (ch >= "a") & (ch <= "f") THEN v := v * 16 + ORD(ch) - ORD("a") + 10
        ELSIF (ch >= "A") & (ch <= "F") THEN v := v * 16 + ORD(ch) - ORD("A") + 10
        ELSE ok := FALSE
        END;
        INC(d); INC(i)
      END;
      ok := ok & (d >= 1) & (d <= 2); mac[k] := v; INC(k);
      IF (k < 6) & ok THEN ok := (i < LEN(s)) & (s[i] = ":"); INC(i) END
    END;
    IF ok THEN FOR i := 0 TO 5 DO reg[Adr(i)] := mac[i]; low[Adr(i)] := mac[i] END END;
    RETURN ok
  END SetMac;

  (* power on: em16's start *)
  PROCEDURE Reset*;
  BEGIN LinkTime := EmHost.hz DIV 200; PollTime := EmHost.hz DIV 4000;
    link := FALSE; latch := 0; nextPoll := 0; SysReset(0)
  END Reset;

  PROCEDURE InitCRC;
    VAR i, j, c: INTEGER;
  BEGIN
    FOR i := 0 TO 255 DO c := i;
      FOR j := 0 TO 7 DO
        IF ODD(c) THEN c := EOR(LSR(c, 1), -306674912) ELSE c := LSR(c, 1) END   (* EDB88320h *)
      END;
      crcTab[i] := c
    END
  END InitCRC;

BEGIN InitCRC; mac[0] := 0; mac[1] := 4; mac[2] := 0A3H; mac[3] := 16H; mac[4] := 0E5H; mac[5] := 0;
  net := FALSE; link := FALSE; linkAt := -1; sent := 0; received := 0; dropped := 0; Reset
END EmEth.
