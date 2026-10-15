MODULE EmUART; (* The 6551 ACIA on standard input and output.

   Registers: 0 data, 1 status (writing it is a programmed reset),
   2 command, 3 control. Status bit 3: a character has arrived, bit 4:
   the transmitter is empty, which it always is.

   When standard input is a terminal it is put in raw mode on the first
   use of the port; when it is a pipe it is made non-blocking, so that a
   program polling for a key keeps running. *)

  IMPORT EmHost;

  VAR
    receiveData, status, command, control: INTEGER;
    interactive: BOOLEAN;

  PROCEDURE Reset*;
  BEGIN status := 10H
  END Reset;

  (* Look for a character, unless one is waiting to be read. *)
  PROCEDURE Poll;
    VAR b: INTEGER;
  BEGIN
    IF AND(status, 8) = 0 THEN
      IF interactive THEN EmHost.RawMode END;
      b := EmHost.ReadIn();
      IF b >= 0 THEN
        status := ORA(status, 8); receiveData := b;
        EmHost.Str(EmHost.err, "[UART] recv $"); EmHost.Hex(EmHost.err, b, 2);
        EmHost.Str(EmHost.err, " '");
        IF (b >= 20H) & (b < 7FH) THEN EmHost.Ch(EmHost.err, CHR(b))
        ELSE EmHost.Ch(EmHost.err, ".")
        END;
        EmHost.Ch(EmHost.err, "'"); EmHost.Ln(EmHost.err)
      END
    END
  END Poll;

  PROCEDURE Send(data: INTEGER);
  BEGIN
    IF interactive THEN EmHost.RawMode END;
    EmHost.Drain(EmHost.out); EmHost.PutChar(data)
  END Send;

  PROCEDURE GetByte*(ea: INTEGER): INTEGER;
    VAR r, reg: INTEGER;
  BEGIN reg := AND(ea, 3);
    IF reg = 0 THEN Poll; status := AND(status, 0FFH - 8); r := receiveData
    ELSIF reg = 1 THEN Poll; r := status
    ELSIF reg = 2 THEN r := command
    ELSE r := control
    END;
    RETURN r
  END GetByte;

  PROCEDURE SetByte*(ea, data: INTEGER);
    VAR reg: INTEGER;
  BEGIN reg := AND(ea, 3);
    IF reg = 0 THEN Send(data); status := ORA(status, 10H)
    ELSIF reg = 1 THEN Reset
    ELSIF reg = 2 THEN command := data
    ELSE control := data
    END
  END SetByte;

BEGIN
  receiveData := 0; command := 2; control := 0; status := 10H;
  EmHost.Init;
  IF EmHost.IsTTY() = 0 THEN interactive := FALSE; EmHost.NonBlock
  ELSE interactive := TRUE
  END
END EmUART.
