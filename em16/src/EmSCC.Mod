MODULE EmSCC; (* The SoC's emulated Z85C30 SCC, rtl/scc_85c30.v, with
   channel A on standard input and output and the same timing as EmACIA:
   2340 cycles a character at 25.2 MHz (115200 baud).

   Registers at $0820-$082F, mirrored every 4 bytes: 0 B control, 1 B data,
   2 A control, 3 A data. Each channel's control port has the SCC's
   register pointer: with the pointer at 0 a write is WR0, which sets it
   (bits 2-0, plus 8 for "point high", bits 5-3 = 001); any other access
   uses the register it names and puts it back to 0. WR2 and WR9 are
   shared.

   What the RTL does, this does: RR0 bit 0 receive character available,
   bit 2 transmit buffer empty, DCD and CTS always asserted; RR1 bit 5
   overrun (WR0 command 6 clears it) and bit 0 all sent; a three-byte
   receive FIFO, filled only while WR3 bit 0 is set; transmit only while
   WR5 bit 3 is set; the receive interrupt (WR1 bits 4-3 = 01 or 10), the
   transmit interrupt (WR1 bit 1, cleared by writing data or WR0 command
   5), MIE (WR9 bit 3), RR3, RR2 from channel B with the status in it (WR9
   bits 0 and 4), and the resets in WR9 bits 7-6. Channel B has no pins.

   As in EmACIA, a character typed reaches the FIFO no sooner than a
   character time after the one before, and only if there is room: the
   host holds it back rather than overrunning. *)

  IMPORT EmHost;

  CONST charTime = 2340; A = 1; B = 0;

  VAR
    ptr, wr1, wr3, wr5, wr12, wr13, wr15: ARRAY 2 OF INTEGER;
    txIP: ARRAY 2 OF BOOLEAN;
    wr2, wr9: INTEGER;
    fifo: ARRAY 3 OF INTEGER;
    count: INTEGER;
    overrun, txFull, interactive: BOOLEAN;
    txBuf: INTEGER;
    txFree, rxNext, nextPoll: LONGINT;

  PROCEDURE ResetChannel(c: INTEGER);
  BEGIN ptr[c] := 0; wr1[c] := 0; wr3[c] := AND(wr3[c], 0FEH); wr5[c] := AND(wr5[c], 61H);
    wr15[c] := 0F8H; txIP[c] := FALSE;
    IF c = A THEN count := 0; overrun := FALSE; txFull := FALSE END
  END ResetChannel;

  PROCEDURE Reset*;
    VAR c: INTEGER;
  BEGIN
    FOR c := 0 TO 1 DO
      ptr[c] := 0; wr1[c] := 0; wr3[c] := 0; wr5[c] := 0; wr12[c] := 0; wr13[c] := 0;
      wr15[c] := 0F8H; txIP[c] := FALSE
    END;
    wr2 := 0; wr9 := 0; count := 0; overrun := FALSE; txFull := FALSE; txBuf := 0;
    txFree := 0; rxNext := 0; nextPoll := 0
  END Reset;

  (* The transmitter: the buffer goes to the shift register once the
     previous character has gone. *)
  PROCEDURE Send(now: LONGINT);
  BEGIN
    IF txFull & (now >= txFree) & ODD(wr5[A] DIV 8) THEN
      IF interactive THEN EmHost.RawMode END;
      EmHost.Drain(EmHost.out); EmHost.PutChar(txBuf);
      txFull := FALSE; txFree := now + 1 + charTime;
      IF ODD(wr1[A] DIV 2) THEN txIP[A] := TRUE END
    END
  END Send;

  (* Take a character from standard input if the FIFO can. *)
  PROCEDURE Poll(now: LONGINT);
    VAR b: INTEGER;
  BEGIN Send(now);
    IF (count < 3) & ODD(wr3[A]) & (now >= rxNext) THEN
      IF interactive THEN EmHost.RawMode END;
      b := EmHost.ReadIn();
      IF b >= 0 THEN
        fifo[count] := b; INC(count); rxNext := now + charTime;
        EmHost.Str(EmHost.err, "[UART] recv $"); EmHost.Hex(EmHost.err, b, 2); EmHost.Str(EmHost.err, " '");
        IF (b >= 20H) & (b < 7FH) THEN EmHost.Ch(EmHost.err, CHR(b)) ELSE EmHost.Ch(EmHost.err, ".") END;
        EmHost.Ch(EmHost.err, "'"); EmHost.Ln(EmHost.err)
      END
    END;
    nextPoll := now + charTime
  END Poll;

  (* Called as time passes, for a program that waits for the IRQ. *)
  PROCEDURE Tick*(now: LONGINT);
  BEGIN Send(now); IF now >= nextPoll THEN Poll(now) END
  END Tick;

  PROCEDURE RxIP(): BOOLEAN;
    VAR m: INTEGER;
  BEGIN m := AND(wr1[A] DIV 8, 3); RETURN ((m = 1) OR (m = 2)) & (count > 0)
  END RxIP;

  PROCEDURE Irq*(): BOOLEAN;
  BEGIN RETURN ODD(wr9 DIV 8) & (RxIP() OR txIP[A] OR txIP[B])
  END Irq;

  PROCEDURE Pop(): INTEGER;
    VAR r: INTEGER;
  BEGIN r := fifo[0];
    IF count > 0 THEN fifo[0] := fifo[1]; fifo[1] := fifo[2]; DEC(count) END;
    RETURN r
  END Pop;

  PROCEDURE RR(c, n: INTEGER; now: LONGINT): INTEGER;
    VAR r, v: INTEGER;
  BEGIN
    IF (n = 0) OR (n = 4) THEN
      r := 68H;                                   (* Tx underrun, CTS, DCD *)
      IF (c = B) OR ~txFull THEN r := ORA(r, 4) END;
      IF (c = A) & (count > 0) THEN r := ORA(r, 1) END
    ELSIF (n = 1) OR (n = 5) THEN
      r := 6;                                     (* residue code 011 *)
      IF c = B THEN r := 7
      ELSE
        IF overrun THEN r := ORA(r, 20H) END;
        IF ~txFull & (now >= txFree) THEN r := ORA(r, 1) END
      END
    ELSIF (n = 2) OR (n = 6) THEN
      IF (c = A) OR ~ODD(wr9) THEN r := wr2
      ELSE
        IF RxIP() THEN v := 6 ELSIF txIP[A] THEN v := 4 ELSIF txIP[B] THEN v := 0 ELSE v := 3 END;
        IF ODD(wr9 DIV 16) THEN               (* status high: V4-V6, reversed *)
          r := AND(wr2, 8FH) + (v MOD 2) * 40H + (v DIV 2 MOD 2) * 20H + (v DIV 4) * 10H
        ELSE r := AND(wr2, 0F1H) + v * 2
        END
      END
    ELSIF (n = 3) OR (n = 7) THEN
      r := 0;
      IF c = A THEN
        IF RxIP() THEN r := ORA(r, 20H) END;
        IF txIP[A] THEN r := ORA(r, 10H) END;
        IF txIP[B] THEN r := ORA(r, 2) END
      END
    ELSIF n = 8 THEN IF c = A THEN r := Pop() ELSE r := 0 END
    ELSIF (n = 9) OR (n = 13) THEN r := wr13[c]
    ELSIF (n = 10) OR (n = 14) THEN r := 0
    ELSIF n = 12 THEN r := wr12[c]
    ELSE r := AND(wr15[c], 0FAH)
    END;
    RETURN r
  END RR;

  PROCEDURE Read*(reg: INTEGER; now: LONGINT): INTEGER;
    VAR c, r: INTEGER;
  BEGIN reg := AND(reg, 3); c := reg DIV 2; Poll(now);
    IF ODD(reg) THEN IF c = A THEN r := Pop() ELSE r := 0 END
    ELSE r := RR(c, ptr[c], now); ptr[c] := 0
    END;
    RETURN r
  END Read;

  PROCEDURE TxData(c, data: INTEGER; now: LONGINT);
  BEGIN
    IF c = A THEN txBuf := data; txFull := TRUE; txIP[A] := FALSE; Send(now)
    ELSIF ODD(wr1[B] DIV 2) THEN txIP[B] := TRUE
    END
  END TxData;

  PROCEDURE Write*(reg, data: INTEGER; now: LONGINT);
    VAR c, n, cmd: INTEGER;
  BEGIN reg := AND(reg, 3); c := reg DIV 2; Send(now);
    IF ODD(reg) THEN TxData(c, data, now)
    ELSIF ptr[c] = 0 THEN                         (* WR0 *)
      cmd := AND(data DIV 8, 7); n := AND(data, 7);
      IF cmd = 1 THEN n := n + 8 END;
      ptr[c] := n;
      IF cmd = 5 THEN txIP[c] := FALSE
      ELSIF (cmd = 6) & (c = A) THEN overrun := FALSE
      END
    ELSE n := ptr[c]; ptr[c] := 0;
      IF n = 1 THEN wr1[c] := data
      ELSIF n = 2 THEN wr2 := data
      ELSIF n = 3 THEN wr3[c] := data
      ELSIF n = 5 THEN wr5[c] := data
      ELSIF n = 8 THEN TxData(c, data, now)
      ELSIF n = 9 THEN
        cmd := data DIV 40H;
        IF cmd = 1 THEN ResetChannel(B)
        ELSIF cmd = 2 THEN ResetChannel(A)
        ELSIF cmd = 3 THEN ResetChannel(A); ResetChannel(B)
        END;
        IF cmd = 3 THEN wr9 := 0 ELSE wr9 := AND(data, 3FH) END
      ELSIF n = 12 THEN wr12[c] := data
      ELSIF n = 13 THEN wr13[c] := data
      ELSIF n = 15 THEN wr15[c] := data
      END                                         (* WR4, WR6, WR7, WR10, WR11, WR14: no effect *)
    END;
    IF ~ODD(wr1[A] DIV 2) THEN txIP[A] := FALSE END;
    IF ~ODD(wr1[B] DIV 2) THEN txIP[B] := FALSE END
  END Write;

BEGIN Reset; interactive := EmHost.IsTTY() # 0;
  IF ~interactive THEN EmHost.NonBlock END
END EmSCC.
