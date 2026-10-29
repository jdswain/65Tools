MODULE EmSD; (* The SoC's microSD slot in SPI mode, rtl/sd_spi.v, with an
   SDHC card whose blocks are an image file (-sd card.img), raw blocks
   from 0.

   Registers at $02C0, mirrored through the slot:
     +0 DATA     write: send the byte. read: the byte last received
     +1 NEXT     read: the byte last received, and send $FF for the next
     +2 STATUS   read: bit 7 busy, bit 0 select
        CONTROL  write: bit 0 select (1 drives the card's CS low)
     +3 DIVIDER  SCLK = clock / (2 * (DIVIDER + 1)); 31 at reset
   An exchange takes 16 * (DIVIDER + 1) + 1 cycles. An access to DATA or
   NEXT while one runs waits for it to end (Wait), as the board holds the
   CPU; a write to DATA or a read of NEXT then starts the next. Without a
   card, or with it deselected, a byte comes back $FF.

   The card is sim/sd_card_model.v of the Verilog repository, a byte at a
   time: it answers a command after one $FF (NCR), a read's data token
   after one more. CMD0 (its CRC must be $95), CMD8 (CRC $87, R7 echoed),
   CMD9 (a version 2 CSD of the image's size), CMD10, CMD12 (R1b, ending
   CMD18), CMD13, CMD16 (512 only), CMD17, CMD18, CMD24, CMD25 (tokens $FC,
   and $FD to stop), CMD55 and ACMD41 (idle for the first, ready on the
   second), CMD58 (OCR: powered up once ready, CCS set). Others are illegal
   commands; other CRCs are not checked. Deselecting it abandons what it
   was sending. *)

  IMPORT EmHost;

  CONST
    image = 3;                        (* EmHost's disk number *)
    blockSize = 512;
    qSize = 2048;
    pRead = 1; pSend = 2; pNext = 3;  (* an access that waits *)

  VAR
    mounted, readOnly: BOOLEAN;
    blocks: INTEGER;
    (* the controller *)
    rx, div, sel: INTEGER;
    busyUntil: LONGINT;
    (* the card *)
    q: ARRAY qSize OF INTEGER; qh, qt: INTEGER;
    cmd: ARRAY 6 OF INTEGER; ncmd: INTEGER;
    idle, app, rdMulti, wrMulti: BOOLEAN;
    acmd41s, rdBlk, wrState, wrBlk, wrN: INTEGER;
    buf: ARRAY blockSize OF BYTE;

  PROCEDURE Mount*(name: ARRAY OF CHAR): BOOLEAN;
    VAR k, size: INTEGER;
  BEGIN mounted := FALSE;
    k := EmHost.DiskOpen(image, name); size := EmHost.DiskSize(image);
    IF k = 0 THEN EmHost.Str(EmHost.out, "SD: Cannot open card image: "); EmHost.Str(EmHost.out, name)
    ELSIF size < blockSize THEN EmHost.Str(EmHost.out, "SD: Card image too small: "); EmHost.Str(EmHost.out, name)
    ELSE mounted := TRUE; readOnly := k = 2; blocks := size DIV blockSize;
      EmHost.Str(EmHost.out, "SD: Card in the slot ("); EmHost.Int(EmHost.out, blocks);
      EmHost.Str(EmHost.out, " blocks");
      IF readOnly THEN EmHost.Str(EmHost.out, ", read-only") END;
      EmHost.Str(EmHost.out, "): "); EmHost.Str(EmHost.out, name)
    END;
    EmHost.Ln(EmHost.out);
    RETURN mounted
  END Mount;

  (* --- the card --- *)

  PROCEDURE Push(b: INTEGER);
  BEGIN q[qt] := AND(b, 0FFH); qt := (qt + 1) MOD qSize
  END Push;

  PROCEDURE R1(flags: INTEGER);
  BEGIN Push(0FFH); IF idle THEN Push(ORA(flags, 1)) ELSE Push(flags) END
  END R1;

  (* CRC16-CCITT of buf, as a read sends it *)
  PROCEDURE Crc16(): INTEGER;
    VAR n, b, c: INTEGER;
  BEGIN c := 0;
    FOR n := 0 TO blockSize - 1 DO
      c := EOR(c, ASL(buf[n], 8));
      FOR b := 0 TO 7 DO
        IF ODD(c DIV 8000H) THEN c := EOR(AND(ASL(c, 1), 0FFFFH), 1021H)
        ELSE c := AND(ASL(c, 1), 0FFFFH)
        END
      END
    END;
    RETURN c
  END Crc16;

  PROCEDURE PushBlock(blk: INTEGER);
    VAR n, k, c: INTEGER;
  BEGIN
    FOR n := 0 TO blockSize - 1 DO buf[n] := 0 END;
    k := EmHost.DiskRead(image, blk * blockSize, buf);
    Push(0FFH); Push(0FEH);                (* NAC, the start block token *)
    FOR n := 0 TO blockSize - 1 DO Push(buf[n]) END;
    c := Crc16(); Push(c DIV 100H); Push(c)
  END PushBlock;

  PROCEDURE Command;
    VAR c, arg, n: INTEGER;
  BEGIN c := AND(cmd[0], 3FH);
    arg := ((cmd[1] * 100H + cmd[2]) * 100H + cmd[3]) * 100H + cmd[4];
    IF app & (c = 41) THEN app := FALSE; INC(acmd41s);
      IF acmd41s >= 2 THEN idle := FALSE END;
      R1(0)
    ELSE app := FALSE;
      CASE c OF
        0: IF cmd[5] # 95H THEN R1(8) ELSE idle := TRUE; acmd41s := 0; rdMulti := FALSE; R1(0) END
      | 8: IF cmd[5] # 87H THEN R1(8) ELSE R1(0); Push(0); Push(0); Push(cmd[3]); Push(cmd[4]) END
      | 9: R1(0); Push(0FFH); Push(0FEH);    (* CSD version 2: C_SIZE = blocks / 1024 - 1 *)
          Push(40H); Push(0EH); Push(0); Push(32H); Push(5BH); Push(59H); Push(0);
          n := blocks DIV 1024 - 1; IF n < 0 THEN n := 0 END;
          Push(AND(n DIV 10000H, 3FH)); Push(n DIV 100H); Push(n);
          Push(7FH); Push(80H); Push(0AH); Push(40H); Push(0); Push(1);
          Push(0); Push(0)
      | 10: R1(0); Push(0FFH); Push(0FEH);
          FOR n := 0 TO 15 DO Push(41H + n) END; Push(0); Push(0)
      | 12: qt := qh; rdMulti := FALSE;
          Push(0FFH); R1(0); Push(0); Push(0FFH)
      | 13: R1(0); Push(0)
      | 16: IF arg = blockSize THEN R1(0) ELSE R1(40H) END
      | 17: IF (arg < 0) OR (arg >= blocks) THEN R1(40H) ELSE R1(0); PushBlock(arg) END
      | 18: IF (arg < 0) OR (arg >= blocks) THEN R1(40H) ELSE R1(0); rdMulti := TRUE; rdBlk := arg END
      | 24, 25: IF (arg < 0) OR (arg >= blocks) THEN R1(40H)
          ELSE R1(0); wrState := 1; wrBlk := arg; wrMulti := c = 25
          END
      | 55: app := TRUE; R1(0)
      | 58: R1(0); IF idle THEN Push(40H) ELSE Push(0C0H) END; Push(0FFH); Push(80H); Push(0)
      ELSE R1(4)
      END
    END
  END Command;

  (* A byte from the host *)
  PROCEDURE Take(b: INTEGER);
  BEGIN
    IF wrState = 1 THEN
      IF (b = 0FEH) OR wrMulti & (b = 0FCH) THEN wrState := 2; wrN := 0
      ELSIF wrMulti & (b = 0FDH) THEN wrState := 0;      (* stop tran: a byte, busy, done *)
        Push(0FFH); Push(0); Push(0); Push(0FFH)
      END
    ELSIF wrState = 2 THEN
      IF wrN < blockSize THEN buf[wrN] := b END;
      INC(wrN);
      IF wrN = blockSize + 2 THEN                      (* the data and its CRC *)
        IF ~readOnly THEN EmHost.DiskWrite(image, wrBlk * blockSize, buf) END;
        Push(05H); Push(0); Push(0); Push(0); Push(0FFH);   (* accepted, busy *)
        IF wrMulti & (wrBlk + 1 < blocks) THEN INC(wrBlk); wrState := 1 ELSE wrState := 0 END
      END
    ELSIF ncmd > 0 THEN cmd[ncmd] := b; INC(ncmd);
      IF ncmd = 6 THEN ncmd := 0; Command END
    ELSIF b DIV 40H = 1 THEN cmd[0] := b; ncmd := 1
    END
  END Take;

  (* One byte each way *)
  PROCEDURE Exchange(b: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN r := 0FFH;
    IF mounted & (sel # 0) THEN
      IF qh # qt THEN r := q[qh]; qh := (qh + 1) MOD qSize END;
      Take(b);
      IF (qh = qt) & rdMulti THEN PushBlock(rdBlk); rdBlk := (rdBlk + 1) MOD blocks END
    END;
    RETURN r
  END Exchange;

  PROCEDURE Deselect;
  BEGIN qh := 0; qt := 0; ncmd := 0; rdMulti := FALSE;
    IF wrState = 2 THEN wrState := 0 END
  END Deselect;

  (* --- the controller --- *)

  PROCEDURE Start(b: INTEGER; now: LONGINT);
  BEGIN rx := Exchange(b); busyUntil := now + 16 * (div + 1) + 1
  END Start;

  (* The cycles an access to reg waits at now: DATA and NEXT wait for an
     exchange to end. *)
  PROCEDURE Wait*(reg: INTEGER; now: LONGINT): INTEGER;
    VAR w: INTEGER;
  BEGIN w := 0;
    IF (AND(reg, 2) = 0) & (now < busyUntil) THEN w := busyUntil - now END;
    RETURN w
  END Wait;

  PROCEDURE Read*(reg: INTEGER; now: LONGINT): INTEGER;
    VAR r: INTEGER;
  BEGIN reg := AND(reg, 3); r := rx;
    IF reg = 1 THEN Start(0FFH, now)
    ELSIF reg = 2 THEN r := sel; IF now < busyUntil THEN r := r + 80H END
    ELSIF reg = 3 THEN r := div
    END;
    RETURN r
  END Read;

  PROCEDURE Write*(reg, v: INTEGER; now: LONGINT);
  BEGIN reg := AND(reg, 3); v := AND(v, 0FFH);
    IF reg = 0 THEN Start(v, now)
    ELSIF reg = 2 THEN
      IF ODD(v) THEN sel := 1 ELSE IF sel # 0 THEN Deselect END; sel := 0 END
    ELSIF reg = 3 THEN div := v
    END
  END Write;

  PROCEDURE Reset*;
  BEGIN rx := 0FFH; div := 31; sel := 0; busyUntil := 0; Deselect;
    idle := TRUE; app := FALSE; acmd41s := 0; wrState := 0; wrMulti := FALSE
  END Reset;

BEGIN mounted := FALSE; Reset
END EmSD.
