MODULE EmACIA; (* The SoC's serial port, rtl/acia_6551.v, on standard input
   and output, with its timing: 234 cycles a bit at 25.2 MHz (115200
   baud), ten bits a character.

   Registers (mirrored every 4 bytes): 0 data, 1 status (writing it is a
   programmed reset), 2 command, 3 control. Status: bit 7 IRQ, 4
   transmitter empty, 3 receiver full, 2 overrun. The IRQ is asserted
   while a character waits and command bit 1 is 0.

   A character sent takes 2340 cycles, during which the transmitter is
   not empty. A character typed reaches the receiver no sooner than 2340
   cycles after the one before, and only once that one has been read: on
   the board a character arriving while one waits is lost (overrun);
   here the host holds it back, as a terminal with flow control would. *)

  IMPORT EmHost;

  CONST charTime = 2340;

  VAR
    command, control, rxData: INTEGER;
    rxFull, overrun, interactive: BOOLEAN;
    txFree, rxNext, nextPoll: LONGINT;

  PROCEDURE Reset*;
  BEGIN command := 0; control := 0; rxData := 0; rxFull := FALSE; overrun := FALSE;
    txFree := 0; rxNext := 0; nextPoll := 0
  END Reset;

  (* Take a character from standard input if the receiver can. *)
  PROCEDURE Poll(now: LONGINT);
    VAR b: INTEGER;
  BEGIN
    IF ~rxFull & (now >= rxNext) THEN
      IF interactive THEN EmHost.RawMode END;
      b := EmHost.ReadIn();
      IF b >= 0 THEN
        rxData := b; rxFull := TRUE; rxNext := now + charTime;
        EmHost.Str(EmHost.err, "[UART] recv $"); EmHost.Hex(EmHost.err, b, 2); EmHost.Str(EmHost.err, " '");
        IF (b >= 20H) & (b < 7FH) THEN EmHost.Ch(EmHost.err, CHR(b)) ELSE EmHost.Ch(EmHost.err, ".") END;
        EmHost.Ch(EmHost.err, "'"); EmHost.Ln(EmHost.err)
      END
    END;
    nextPoll := now + charTime
  END Poll;

  (* Called as time passes, for a program that waits for the IRQ. *)
  PROCEDURE Tick*(now: LONGINT);
  BEGIN IF now >= nextPoll THEN Poll(now) END
  END Tick;

  PROCEDURE Irq*(): BOOLEAN;
  BEGIN RETURN rxFull & ~ODD(command DIV 2)
  END Irq;

  PROCEDURE Read*(reg: INTEGER; now: LONGINT): INTEGER;
    VAR r: INTEGER;
  BEGIN reg := AND(reg, 3);
    IF reg = 0 THEN Poll(now); r := rxData; rxFull := FALSE; overrun := FALSE
    ELSIF reg = 1 THEN Poll(now); r := 0;
      IF Irq() THEN r := ORA(r, 80H) END;
      IF now >= txFree THEN r := ORA(r, 10H) END;
      IF rxFull THEN r := ORA(r, 8) END;
      IF overrun THEN r := ORA(r, 4) END
    ELSIF reg = 2 THEN r := command
    ELSE r := control
    END;
    RETURN r
  END Read;

  PROCEDURE Write*(reg, data: INTEGER; now: LONGINT);
  BEGIN reg := AND(reg, 3);
    IF reg = 0 THEN
      IF now >= txFree THEN            (* a character while one is going is lost *)
        IF interactive THEN EmHost.RawMode END;
        EmHost.Drain(EmHost.out); EmHost.PutChar(data);
        txFree := now + 1 + charTime
      END
    ELSIF reg = 1 THEN command := 0; overrun := FALSE
    ELSIF reg = 2 THEN command := data
    ELSE control := data
    END
  END Write;

BEGIN Reset; interactive := EmHost.IsTTY() # 0;
  IF ~interactive THEN EmHost.NonBlock END
END EmACIA.
