MODULE EmZ85C30; (* A Z85C30 SCC, the Mini816's: two asynchronous
   channels, each on a host connection (the console, a pty or a TCP
   socket, or none), at the rates their baud-rate generators set from PCLK
   (the board passes the time in PCLK cycles, now).

   Registers: 0 B control, 1 B data, 2 A control, 3 A data (A1 = A/~B,
   A0 = D/~C). Each control port has the register pointer: with it at 0 a
   write is WR0, which sets it (bits 2-0, 8 more with "point high", bits
   5-3 = 001); the next access goes to that register and puts it back to
   0. WR2 and WR9 are shared. RR2 of channel B is the vector with the
   status of the highest interrupt pending (WR9 bit 4: in bits 6-4, else
   3-1; none: 011), RR3 of channel A the pending bits.

   A character takes its frame (a start bit, 5 to 8 bits, parity, 1, 1.5
   or 2 stop bits: WR3, WR4, WR5) at the rate of its clock, the baud-rate
   generator (WR11's Rx and Tx clocks the BRG, WR14 bit 0 on and bit 1
   PCLK): 2 * (time constant + 2) * the clock mode (WR4: x1, x16, x32,
   x64) PCLK cycles a bit. RTxC and TRxC carry no clock on the board, so
   a channel clocked by them does not run. The BRG's zero counts, a time
   constant + 2 cycles apart, raise the ext/status interrupt with WR15
   bit 1.

   Receiving: a 3-byte FIFO, from the host no faster than a frame and
   only with room (the host holds the rest back, as with flow control: no
   overrun); the Rx interrupt on the first character (WR1 bits 4-3 = 01,
   again after WR0 command 4) or on each (10). Transmitting: the buffer and
   the shift register, a character to the host at its frame's end; the Tx
   interrupt (WR1 bit 1) as the buffer empties, until data is written or
   WR0 command 5. CTS is asserted while a host is connected, and with
   auto enables (WR3 bit 5) the transmitter waits for it; DCD always (the
   board ties it). MIE is WR9 bit 3; there is no interrupt acknowledge
   (the board ties /INTACK high), so no IUS.

   Reset: WR9 bits 7-6, 01 channel B, 10 channel A, 11 the chip, and power
   on (Init). The board does not reset it with the CPU. *)

  IMPORT EmHost;

  CONST
    A* = 1; B* = 0;
    none* = 0; console* = 1; port* = 2;     (* a channel's host *)

  VAR
    wr: ARRAY 2, 16 OF INTEGER;
    ptr: ARRAY 2 OF INTEGER;
    wr2, wr9: INTEGER;
    fifo: ARRAY 2, 3 OF INTEGER;
    count, rxByte: ARRAY 2 OF INTEGER;
    rxDue, rxFree: ARRAY 2 OF LONGINT;       (* the character coming in by, the receiver free from *)
    rxFirst, rxIP: ARRAY 2 OF BOOLEAN;        (* the first character's interrupt armed, pending *)
    txBuf, txShift: ARRAY 2 OF INTEGER;
    txFull: ARRAY 2 OF BOOLEAN;
    txAt, txDue, txFree: ARRAY 2 OF LONGINT;  (* the buffer written, the shift register out by, free from *)
    txIP, extIP: ARRAY 2 OF BOOLEAN;
    zero: ARRAY 2 OF LONGINT;                 (* the BRG's next zero count *)
    cts: ARRAY 2 OF INTEGER;
    host, hostPort: ARRAY 2 OF INTEGER;
    nextPoll, nextCts: ARRAY 2 OF LONGINT;
    interactive: BOOLEAN;
    never: LONGINT;

  (* --- the host --- *)

  (* channel c on the console, on EmHost's port n, or on none *)
  PROCEDURE SetHost*(c, kind, n: INTEGER);
  BEGIN host[c] := kind; hostPort[c] := n
  END SetHost;

  PROCEDURE HostRead(c: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN r := -1;
    IF host[c] = console THEN IF interactive THEN EmHost.RawMode END; r := EmHost.ReadIn()
    ELSIF host[c] = port THEN r := EmHost.PortRead(hostPort[c])
    END;
    RETURN r
  END HostRead;

  PROCEDURE HostWrite(c, b: INTEGER);
  BEGIN
    IF host[c] = console THEN
      IF interactive THEN EmHost.RawMode END; EmHost.Drain(EmHost.out); EmHost.PutChar(b)
    ELSIF host[c] = port THEN EmHost.PortWrite(hostPort[c], b)
    END
  END HostWrite;

  PROCEDURE HostCts(c: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN
    IF host[c] = console THEN r := 1 ELSIF host[c] = port THEN r := EmHost.PortConnected(hostPort[c]) ELSE r := 0 END;
    RETURN r
  END HostCts;

  (* --- the clocks and frames --- *)

  PROCEDURE BrgOn(c: INTEGER): BOOLEAN;
  BEGIN RETURN AND(wr[c, 14], 3) = 3
  END BrgOn;

  PROCEDURE Tc(c: INTEGER): LONGINT;
    VAR t: LONGINT;
  BEGIN t := wr[c, 13]; RETURN t * 256 + wr[c, 12] + 2
  END Tc;

  (* a bit's time, or 0 when the clock (rx: the receiver's) is not the
     running BRG *)
  PROCEDURE BitTime(c: INTEGER; rx: BOOLEAN): LONGINT;
    VAR src, m: INTEGER; t: LONGINT;
  BEGIN
    IF rx THEN src := AND(wr[c, 11] DIV 32, 3) ELSE src := AND(wr[c, 11] DIV 8, 3) END;
    IF (src = 2) & BrgOn(c) THEN
      m := AND(wr[c, 4] DIV 64, 3);
      IF m = 0 THEN m := 1 ELSIF m = 1 THEN m := 16 ELSIF m = 2 THEN m := 32 ELSE m := 64 END;
      t := 2 * Tc(c) * m
    ELSE t := 0
    END;
    RETURN t
  END BitTime;

  (* the bits a character: WR3 bits 7-6 receiving, WR5 bits 6-5 sending *)
  PROCEDURE Bits(c: INTEGER; rx: BOOLEAN): INTEGER;
    VAR k: INTEGER;
  BEGIN
    IF rx THEN k := AND(wr[c, 3] DIV 64, 3) ELSE k := AND(wr[c, 5] DIV 32, 3) END;
    IF k = 0 THEN k := 5 ELSIF k = 1 THEN k := 7 ELSIF k = 2 THEN k := 6 ELSE k := 8 END;
    RETURN k
  END Bits;

  PROCEDURE Frame(c: INTEGER; rx: BOOLEAN): LONGINT;
    VAR half, s: INTEGER;
  BEGIN
    half := 2 * (1 + Bits(c, rx) + wr[c, 4] MOD 2);
    s := AND(wr[c, 4] DIV 4, 3); IF s <= 1 THEN half := half + 2 ELSE half := half + s END;
    RETURN BitTime(c, rx) * half DIV 2
  END Frame;

  PROCEDURE Mask(c: INTEGER; rx: BOOLEAN): INTEGER;
  BEGIN RETURN ASL(1, Bits(c, rx)) - 1
  END Mask;

  (* --- receiving and sending, up to now --- *)

  PROCEDURE RxMode(c: INTEGER): INTEGER;
  BEGIN RETURN AND(wr[c, 1] DIV 8, 3)
  END RxMode;

  PROCEDURE Rx(c: INTEGER; now: LONGINT);
    VAR b: INTEGER; t: LONGINT;
  BEGIN
    IF rxDue[c] <= now THEN
      fifo[c, count[c]] := rxByte[c]; INC(count[c]);
      IF (RxMode(c) = 1) & rxFirst[c] THEN rxIP[c] := TRUE; rxFirst[c] := FALSE END;
      rxFree[c] := rxDue[c]; rxDue[c] := never
    END;
    IF (rxDue[c] = never) & (count[c] < 3) & ODD(wr[c, 3]) & (BitTime(c, TRUE) > 0) & (now >= nextPoll[c]) THEN
      b := HostRead(c);
      IF b >= 0 THEN
        rxByte[c] := AND(b, Mask(c, TRUE)); t := rxFree[c]; IF now > t THEN t := now END;
        rxDue[c] := t + Frame(c, TRUE)
      ELSE nextPoll[c] := now + 500 + Frame(c, TRUE)
      END
    END
  END Rx;

  PROCEDURE TxOn(c: INTEGER): BOOLEAN;
  BEGIN RETURN ODD(wr[c, 5] DIV 8) & (BitTime(c, FALSE) > 0) & (~ODD(wr[c, 3] DIV 32) OR (cts[c] = 1))
  END TxOn;

  PROCEDURE Tx(c: INTEGER; now: LONGINT);
    VAR t: LONGINT; again: BOOLEAN;
  BEGIN
    REPEAT again := FALSE;
      IF txDue[c] <= now THEN
        HostWrite(c, AND(txShift[c], Mask(c, FALSE))); txFree[c] := txDue[c]; txDue[c] := never
      END;
      IF (txDue[c] = never) & txFull[c] & TxOn(c) THEN
        t := txAt[c]; IF txFree[c] > t THEN t := txFree[c] END;
        IF t <= now THEN
          txShift[c] := txBuf[c]; txFull[c] := FALSE; txDue[c] := t + Frame(c, FALSE);
          IF ODD(wr[c, 1] DIV 2) THEN txIP[c] := TRUE END;
          again := TRUE
        END
      END
    UNTIL ~again
  END Tx;

  (* the BRG's zero counts up to now *)
  PROCEDURE Count(c: INTEGER; now: LONGINT);
  BEGIN
    WHILE BrgOn(c) & (now >= zero[c]) DO
      IF ODD(wr[c, 15] DIV 2) & ODD(wr[c, 1]) THEN extIP[c] := TRUE END;
      zero[c] := zero[c] + Tc(c)
    END
  END Count;

  PROCEDURE Cts(c: INTEGER; now: LONGINT);
    VAR v: INTEGER;
  BEGIN
    IF now >= nextCts[c] THEN v := HostCts(c);
      IF v # cts[c] THEN cts[c] := v; IF ODD(wr[c, 15] DIV 32) & ODD(wr[c, 1]) THEN extIP[c] := TRUE END END;
      nextCts[c] := now + 10000
    END
  END Cts;

  PROCEDURE Tick*(now: LONGINT);
    VAR c: INTEGER;
  BEGIN
    FOR c := 0 TO 1 DO Cts(c, now); Tx(c, now); Rx(c, now); Count(c, now) END
  END Tick;

  (* --- interrupts --- *)

  PROCEDURE RxPending(c: INTEGER): BOOLEAN;
  BEGIN RETURN rxIP[c] OR (RxMode(c) = 2) & (count[c] > 0)
  END RxPending;

  PROCEDURE Irq*(): BOOLEAN;
  BEGIN RETURN ODD(wr9 DIV 8) & (RxPending(A) OR txIP[A] OR extIP[A] OR RxPending(B) OR txIP[B] OR extIP[B])
  END Irq;

  (* the status of the highest interrupt pending *)
  PROCEDURE Status(): INTEGER;
    VAR v: INTEGER;
  BEGIN
    IF RxPending(A) THEN v := 6 ELSIF txIP[A] THEN v := 4 ELSIF extIP[A] THEN v := 5
    ELSIF RxPending(B) THEN v := 2 ELSIF txIP[B] THEN v := 0 ELSIF extIP[B] THEN v := 1 ELSE v := 3
    END;
    RETURN v
  END Status;

  (* --- the registers --- *)

  PROCEDURE Pop(c: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN r := fifo[c, 0];
    IF count[c] > 0 THEN fifo[c, 0] := fifo[c, 1]; fifo[c, 1] := fifo[c, 2]; DEC(count[c]) END;
    IF RxMode(c) = 1 THEN rxIP[c] := FALSE END;
    RETURN r
  END Pop;

  PROCEDURE RR(c, n: INTEGER): INTEGER;
    VAR r, v: INTEGER;
  BEGIN
    CASE n OF
      0, 4: r := 48H + cts[c] * 20H;                (* Tx underrun/EOM, DCD *)
        IF ~txFull[c] THEN r := r + 4 END;
        IF count[c] > 0 THEN r := r + 1 END
    | 1, 5: r := 6;                                 (* residue code 011 *)
        IF ~txFull[c] & (txDue[c] = never) THEN r := r + 1 END
    | 2, 6: IF c = A THEN r := wr2
        ELSE v := Status();
          IF ODD(wr9 DIV 16) THEN                   (* status high: bits 4-6, reversed *)
            r := AND(wr2, 8FH) + (v MOD 2) * 40H + (v DIV 2 MOD 2) * 20H + (v DIV 4) * 10H
          ELSE r := AND(wr2, 0F1H) + v * 2
          END
        END
    | 3, 7: r := 0;
        IF c = A THEN
          IF RxPending(A) THEN r := r + 20H END;
          IF txIP[A] THEN r := r + 10H END;
          IF extIP[A] THEN r := r + 8 END;
          IF RxPending(B) THEN r := r + 4 END;
          IF txIP[B] THEN r := r + 2 END;
          IF extIP[B] THEN r := r + 1 END
        END
    | 8: r := Pop(c)
    | 9, 13: r := wr[c, 13]
    | 10, 14: r := 0
    | 12: r := wr[c, 12]
    | 11, 15: r := AND(wr[c, 15], 0FAH)
    END;
    RETURN r
  END RR;

  PROCEDURE Read*(reg: INTEGER; now: LONGINT): INTEGER;
    VAR c, r: INTEGER;
  BEGIN Tick(now); reg := AND(reg, 3); c := reg DIV 2;
    IF ODD(reg) THEN r := Pop(c) ELSE r := RR(c, ptr[c]); ptr[c] := 0 END;
    RETURN r
  END Read;

  PROCEDURE ResetChannel(c: INTEGER);
    VAR i: INTEGER;
  BEGIN
    FOR i := 0 TO 15 DO wr[c, i] := 0 END;
    wr[c, 4] := 4; wr[c, 11] := 8; wr[c, 15] := 0F8H;
    ptr[c] := 0; count[c] := 0; rxDue[c] := never; rxFirst[c] := FALSE; rxIP[c] := FALSE;
    txFull[c] := FALSE; txDue[c] := never; txIP[c] := FALSE; extIP[c] := FALSE
  END ResetChannel;

  PROCEDURE TxData(c, v: INTEGER; now: LONGINT);
  BEGIN txBuf[c] := v; txFull[c] := TRUE; txAt[c] := now; txIP[c] := FALSE; Tx(c, now)
  END TxData;

  PROCEDURE Write*(reg, v: INTEGER; now: LONGINT);
    VAR c, n, cmd: INTEGER; on: BOOLEAN;
  BEGIN Tick(now); reg := AND(reg, 3); c := reg DIV 2; v := AND(v, 0FFH);
    IF ODD(reg) THEN TxData(c, v, now)
    ELSIF ptr[c] = 0 THEN                           (* WR0 *)
      cmd := AND(v DIV 8, 7); n := AND(v, 7);
      IF cmd = 1 THEN n := n + 8 END;
      ptr[c] := n; wr[c, 0] := v;
      IF cmd = 2 THEN extIP[c] := FALSE
      ELSIF cmd = 4 THEN rxFirst[c] := TRUE
      ELSIF cmd = 5 THEN txIP[c] := FALSE
      END
    ELSE n := ptr[c]; ptr[c] := 0;
      IF n = 2 THEN wr2 := v
      ELSIF n = 8 THEN TxData(c, v, now)
      ELSIF n = 9 THEN cmd := v DIV 64;
        IF cmd = 1 THEN ResetChannel(B) ELSIF cmd = 2 THEN ResetChannel(A)
        ELSIF cmd = 3 THEN ResetChannel(A); ResetChannel(B)
        END;
        IF cmd = 3 THEN wr9 := 0 ELSE wr9 := AND(v, 3FH) END
      ELSE
        IF (n = 1) & (AND(v DIV 8, 3) = 1) & (RxMode(c) # 1) THEN rxFirst[c] := TRUE END;
        on := BrgOn(c); wr[c, n] := v;
        IF (n = 14) & ~on & BrgOn(c) THEN zero[c] := now + Tc(c) END
      END
    END;
    IF ~ODD(wr[c, 1] DIV 2) THEN txIP[c] := FALSE END;
    IF ~ODD(wr[c, 1]) THEN extIP[c] := FALSE END;
    IF (RxMode(c) = 0) OR (RxMode(c) = 3) THEN rxIP[c] := FALSE END;
    Tx(c, now)
  END Write;

  (* power on: the chip reset *)
  PROCEDURE Init*;
    VAR c: INTEGER;
  BEGIN
    FOR c := 0 TO 1 DO
      ResetChannel(c); rxFree[c] := 0; txFree[c] := 0; txAt[c] := 0; zero[c] := 0;
      cts[c] := 0; nextPoll[c] := 0; nextCts[c] := 0
    END;
    wr2 := 0; wr9 := 0
  END Init;

BEGIN never := 1000000; never := never * never * 1000000;
  host[A] := console; host[B] := none; hostPort[A] := 0; hostPort[B] := 1;
  interactive := EmHost.IsTTY() # 0; IF ~interactive THEN EmHost.NonBlock END; Init
END EmZ85C30.
