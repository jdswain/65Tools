MODULE EmL28; (* The peripherals of the L28, a Rockwell R65C19 machine.

   $0000-$000B   ports A-E, their directions, interrupt registers
   $0014-$0017   timer B (baud rate)
   $0018-$001F   bank select registers, one per 8K window
   $0038-$003F   the USART, on standard input and output
   ES0           128K of RAM
   ES2, ES3      two 128K SST39F010 flash chips; ES3 holds the ROM

   The keyboard is an 8 x 9 matrix: port C selects rows, port D (and
   PA1 for the modifier column) returns the keys. A character typed at
   the terminal, or in the LCD window (InjectChar), is held down in the
   matrix for 4096 instructions. *)

  IMPORT EmHost;

  CONST
    flashSize = 20000H;
    keyBufSize = 32;
    (* flash command states *)
    idle = 0; cycle1 = 1; cycle2 = 2; byteProgram = 3; eraseSetup = 4; erase1 = 5; erase2 = 6;

  TYPE
    Flash = RECORD
      state: INTEGER;
      data: ARRAY flashSize OF BYTE
    END;

  VAR
    receiveData, status, sir, smr, slcr, sfr, sodl, sidl: INTEGER;
    tbm, tbll, tbul: INTEGER;
    portA, portB, portC, portD, portADir, portBSel, portCDir, portE, portEDir: INTEGER;
    eir, cir: INTEGER;
    keyMatrix: ARRAY 8 OF INTEGER;
    keyMatrixPa1, keyPressTtl: INTEGER;
    keyboardEnabled, consoleMode, cocoaInput, interactive: BOOLEAN;
    keyBuf: ARRAY keyBufSize OF INTEGER;
    keyBufWrite, keyBufRead: INTEGER;
    bsr: ARRAY 8 OF INTEGER;
    es0: ARRAY flashSize OF BYTE;
    es2, es3: Flash;

  (* --- flash --- *)

  PROCEDURE FlashErase(VAR f: Flash; from, n: INTEGER);
    VAR i: INTEGER;
  BEGIN FOR i := from TO from + n - 1 DO f.data[i] := 0FFH END
  END FlashErase;

  PROCEDURE FlashWrite(VAR f: Flash; addr, val: INTEGER);
    VAR st: INTEGER;
  BEGIN addr := AND(addr, 1FFFFH); st := f.state;
    CASE st OF
      idle: IF (addr = 5555H) & (val = 0AAH) THEN f.state := cycle1 END
    | cycle1: IF (addr = 2AAAH) & (val = 55H) THEN f.state := cycle2 ELSE f.state := idle END
    | cycle2:
        IF addr = 5555H THEN
          IF val = 0A0H THEN f.state := byteProgram
          ELSIF val = 80H THEN f.state := eraseSetup
          ELSE f.state := idle
          END
        ELSE f.state := idle
        END
    | byteProgram: f.data[addr] := AND(f.data[addr], val); f.state := idle
    | eraseSetup: IF (addr = 5555H) & (val = 0AAH) THEN f.state := erase1 ELSE f.state := idle END
    | erase1: IF (addr = 2AAAH) & (val = 55H) THEN f.state := erase2 ELSE f.state := idle END
    | erase2:
        IF val = 30H THEN FlashErase(f, AND(addr, 1F000H), 1000H)
        ELSIF val = 10H THEN FlashErase(f, 0, flashSize)
        END;
        f.state := idle
    END
  END FlashWrite;

  PROCEDURE ReadES0*(addr: INTEGER): INTEGER;
  BEGIN RETURN es0[AND(addr, 1FFFFH)]
  END ReadES0;

  PROCEDURE WriteES0*(addr, val: INTEGER);
  BEGIN es0[AND(addr, 1FFFFH)] := val
  END WriteES0;

  PROCEDURE ReadES2*(addr: INTEGER): INTEGER;
  BEGIN RETURN es2.data[AND(addr, 1FFFFH)]
  END ReadES2;

  PROCEDURE WriteES2*(addr, val: INTEGER);
  BEGIN FlashWrite(es2, addr, val)
  END WriteES2;

  PROCEDURE ReadES3*(addr: INTEGER): INTEGER;
  BEGIN RETURN es3.data[AND(addr, 1FFFFH)]
  END ReadES3;

  PROCEDURE WriteES3*(addr, val: INTEGER);
  BEGIN FlashWrite(es3, addr, val)
  END WriteES3;

  (* ES3 starts as the ROM image, the first len bytes of mem. *)
  PROCEDURE InitES3*(VAR mem: ARRAY OF BYTE; len: INTEGER);
    VAR i: INTEGER;
  BEGIN
    IF len > flashSize THEN len := flashSize END;
    FOR i := 0 TO len - 1 DO es3.data[i] := mem[i] END
  END InitES3;

  PROCEDURE GetBSR*(i: INTEGER): INTEGER;
  BEGIN RETURN bsr[AND(i, 7)]
  END GetBSR;

  PROCEDURE SetBSR*(i, val: INTEGER);
  BEGIN bsr[AND(i, 7)] := val
  END SetBSR;

  (* --- the USART --- *)

  PROCEDURE Poll;
    VAR b: INTEGER;
  BEGIN
    IF (AND(status, 1) = 0) & ~consoleMode THEN
      IF interactive THEN EmHost.RawMode END;
      b := EmHost.ReadIn();
      IF b >= 0 THEN status := ORA(status, 1); receiveData := b END
    END
  END Poll;

  PROCEDURE Send(data: INTEGER);
  BEGIN
    IF interactive THEN EmHost.RawMode END;
    EmHost.Drain(EmHost.out); EmHost.PutChar(data)
  END Send;

  PROCEDURE GetByte*(ea: INTEGER): INTEGER;
    VAR r, reg: INTEGER;
  BEGIN reg := AND(ea, 7); r := 0;
    CASE reg OF
      0: Poll; status := AND(status, 0FEH); r := receiveData
    | 1: r := sir
    | 2: r := smr
    | 3: r := slcr
    | 4: Poll; r := status
    | 5: r := sfr
    | 6, 7: r := 0
    END;
    RETURN r
  END GetByte;

  PROCEDURE SetByte*(ea, data: INTEGER);
    VAR reg: INTEGER;
  BEGIN reg := AND(ea, 7);
    CASE reg OF
      0: Send(data); status := ORA(status, 20H)
    | 1: sir := data
    | 2: smr := data
    | 3: slcr := data
    | 4: status := AND(status, 0FFH - AND(data, 1EH)); sir := AND(sir, 7FH)
    | 5: sfr := data
    | 6: sodl := data
    | 7: sidl := data
    END
  END SetByte;

  (* --- timer B --- *)

  PROCEDURE GetTimerB*(offset: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN r := 0;
    IF offset = 0 THEN r := tbm
    ELSIF offset = 1 THEN r := tbll
    ELSIF offset = 2 THEN r := tbul
    ELSIF offset = 3 THEN tbm := AND(tbm, 7FH); r := tbul
    END;
    RETURN r
  END GetTimerB;

  PROCEDURE SetTimerB*(offset, data: INTEGER);
  BEGIN
    IF offset = 0 THEN tbm := ORA(AND(tbm, 80H), AND(data, 67H))
    ELSIF offset = 1 THEN tbll := data
    ELSIF offset = 2 THEN tbul := data
    ELSIF offset = 3 THEN tbul := data; tbm := AND(tbm, 7FH)
    END
  END SetTimerB;

  (* --- ports --- *)

  PROCEDURE GetPort*(offset: INTEGER): INTEGER;
    VAR r, sel: INTEGER;
  BEGIN r := 0;
    CASE offset OF
      0: r := AND(portA, 0FDH);
        IF keyboardEnabled & (AND(portC, keyMatrixPa1) # 0) THEN r := ORA(r, 2) END
    | 1: r := portB
    | 2: r := portC
    | 3:
        IF keyboardEnabled THEN
          FOR sel := 0 TO 7 DO
            IF ODD(LSR(portC, sel)) THEN r := ORA(r, keyMatrix[sel]) END
          END
        ELSE r := portD
        END
    | 4: r := portADir
    | 5: r := portBSel
    | 6: r := portCDir
    | 7: r := portE
    | 8: r := portEDir
    | 9: r := 0
    | 0AH: r := eir
    | 0BH: r := cir
    ELSE
    END;
    RETURN r
  END GetPort;

  PROCEDURE SetPort*(offset, data: INTEGER);
  BEGIN
    CASE offset OF
      0: portA := data
    | 1: portB := data
    | 2: portC := data
    | 3: portD := data
    | 4: portADir := data
    | 5: portBSel := data
    | 6: portCDir := data
    | 7: portE := data
    | 8: portEDir := data
    | 9:
    | 0AH: eir := data
    | 0BH:
        IF AND(data, 40H) = 0 THEN eir := AND(eir, 0BFH) END;
        IF AND(data, 20H) = 0 THEN eir := AND(eir, 0DFH) END;
        cir := data
    ELSE
    END
  END SetPort;

  (* --- the keyboard --- *)

  PROCEDURE PressKey(row, col: INTEGER);
  BEGIN
    IF (row >= 0) & (row < 8) THEN
      IF (col >= 0) & (col < 8) THEN keyMatrix[row] := ORA(keyMatrix[row], ASL(1, col))
      ELSIF col = 8 THEN keyMatrixPa1 := ORA(keyMatrixPa1, ASL(1, row))
      END
    END
  END PressKey;

  PROCEDURE ReleaseAllKeys;
    VAR i: INTEGER;
  BEGIN FOR i := 0 TO 7 DO keyMatrix[i] := 0 END; keyMatrixPa1 := 0
  END ReleaseAllKeys;

  PROCEDURE Irq0Pending*(): BOOLEAN;
  BEGIN RETURN FALSE    (* the keyboard is polled; there is no PA0 edge any more *)
  END Irq0Pending;

  (* Where an ASCII character is in the matrix: row and column, -1 if
     it is not there, and whether it needs shift or control. *)
  PROCEDURE Key(ch: INTEGER; VAR row, col: INTEGER; VAR shift, ctrl: BOOLEAN);
    VAR k: INTEGER;
  BEGIN shift := FALSE; ctrl := FALSE; row := -1; col := -1;
    IF (ch = 0DH) OR (ch = 0AH) THEN row := 5; col := 7
    ELSIF ch = 8 THEN row := 1; col := 5
    ELSIF ch = 9 THEN row := 6; col := 8
    ELSIF ch = 1BH THEN row := 7; col := 7
    ELSIF ch = 20H THEN row := 6; col := 7
    ELSIF (ch >= 1) & (ch <= 1AH) THEN Key(ch + 60H, row, col, shift, ctrl); ctrl := TRUE; shift := FALSE
    ELSIF (ch >= 41H) & (ch <= 5AH) THEN Key(ch + 20H, row, col, shift, ctrl); shift := TRUE
    ELSIF (ch >= 61H) & (ch <= 7AH) THEN
      k := ch - 61H;
      CASE k OF
        0: row := 6; col := 0        (* a *)
      | 1: row := 7; col := 2        (* b *)
      | 2: row := 7; col := 1        (* c *)
      | 3: row := 6; col := 1        (* d *)
      | 4: row := 4; col := 0        (* e *)
      | 5: row := 1; col := 1        (* f *)
      | 6: row := 6; col := 2        (* g *)
      | 7: row := 1; col := 2        (* h *)
      | 8: row := 5; col := 3        (* i *)
      | 9: row := 6; col := 3        (* j *)
      | 10: row := 1; col := 3       (* k *)
      | 11: row := 6; col := 4       (* l *)
      | 12: row := 7; col := 3       (* m *)
      | 13: row := 0; col := 2       (* n *)
      | 14: row := 4; col := 3       (* o *)
      | 15: row := 5; col := 4       (* p *)
      | 16: row := 6; col := 5       (* q *)
      | 17: row := 5; col := 1       (* r *)
      | 18: row := 1; col := 0       (* s *)
      | 19: row := 4; col := 1       (* t *)
      | 20: row := 4; col := 2       (* u *)
      | 21: row := 0; col := 1       (* v *)
      | 22: row := 5; col := 0       (* w *)
      | 23: row := 0; col := 0       (* x *)
      | 24: row := 5; col := 2       (* y *)
      | 25: row := 7; col := 0       (* z *)
      END
    ELSE
      CASE ch OF
        30H: row := 2; col := 0
      | 31H: row := 7; col := 5
      | 32H: row := 3; col := 3
      | 33H: row := 3; col := 2
      | 34H: row := 3; col := 1
      | 35H: row := 3; col := 0
      | 36H: row := 2; col := 4
      | 37H: row := 2; col := 3
      | 38H: row := 2; col := 2
      | 39H: row := 2; col := 1
      | 2CH: row := 0; col := 3
      | 2FH: row := 0; col := 4
      | 5CH: row := 0; col := 5                    (* \ *)
      | 3DH: row := 1; col := 4
      | 27H: row := 2; col := 5                    (* ' *)
      | 3BH: row := 3; col := 4
      | 60H: row := 3; col := 5                    (* ` *)
      | 2DH: row := 4; col := 4
      | 5BH: row := 4; col := 5
      | 5DH: row := 5; col := 5
      | 2EH: row := 7; col := 4
      | 3CH: row := 0; col := 3; shift := TRUE
      | 3FH: row := 0; col := 4; shift := TRUE
      | 7CH: row := 0; col := 5; shift := TRUE
      | 2BH: row := 1; col := 4; shift := TRUE
      | 22H: row := 2; col := 5; shift := TRUE     (* " *)
      | 3AH: row := 3; col := 4; shift := TRUE
      | 7EH: row := 3; col := 5; shift := TRUE
      | 5FH: row := 4; col := 4; shift := TRUE
      | 7BH: row := 4; col := 5; shift := TRUE
      | 7DH: row := 5; col := 5; shift := TRUE
      | 3EH: row := 7; col := 4; shift := TRUE
      | 29H: row := 2; col := 0; shift := TRUE
      | 28H: row := 2; col := 1; shift := TRUE
      | 2AH: row := 2; col := 2; shift := TRUE
      | 26H: row := 2; col := 3; shift := TRUE
      | 5EH: row := 2; col := 4; shift := TRUE
      | 25H: row := 3; col := 0; shift := TRUE
      | 24H: row := 3; col := 1; shift := TRUE
      | 23H: row := 3; col := 2; shift := TRUE
      | 40H: row := 3; col := 3; shift := TRUE
      | 21H: row := 7; col := 5; shift := TRUE
      ELSE
      END
    END
  END Key;

  (* A character typed in the LCD window; called from its thread. *)
  PROCEDURE InjectChar*(ch: INTEGER);
    VAR next: INTEGER;
  BEGIN next := (keyBufWrite + 1) MOD keyBufSize;
    IF next # keyBufRead THEN keyBuf[keyBufWrite] := ch; keyBufWrite := next END
  END InjectChar;

  (* After every instruction: release a key whose time is up, or take the
     next character and press its key. *)
  PROCEDURE PollKeyboard*;
    VAR b, row, col: INTEGER; shift, ctrl: BOOLEAN;
  BEGIN
    IF keyboardEnabled THEN
      IF keyPressTtl > 0 THEN DEC(keyPressTtl);
        IF keyPressTtl = 0 THEN ReleaseAllKeys END
      ELSE
        IF cocoaInput THEN
          IF keyBufRead = keyBufWrite THEN b := -1
          ELSE b := keyBuf[keyBufRead]; keyBufRead := (keyBufRead + 1) MOD keyBufSize
          END
        ELSE
          IF interactive THEN EmHost.RawMode ELSE EmHost.NonBlock END;
          b := EmHost.ReadIn()
        END;
        IF b >= 0 THEN Key(b, row, col, shift, ctrl);
          IF row >= 0 THEN
            PressKey(row, col);
            IF shift THEN PressKey(0, 8) END;
            IF ctrl THEN PressKey(1, 8) END;
            keyPressTtl := 4096
          END
        END
      END
    END
  END PollKeyboard;

  PROCEDURE EnableKeyboard*;
  BEGIN keyboardEnabled := TRUE
  END EnableKeyboard;

  PROCEDURE SetConsoleMode*(on: BOOLEAN);
  BEGIN consoleMode := on
  END SetConsoleMode;

  PROCEDURE SetCocoaInput*(on: BOOLEAN);
  BEGIN cocoaInput := on
  END SetCocoaInput;

  PROCEDURE Init;
    VAR i: INTEGER;
  BEGIN
    receiveData := 0; status := 20H; sir := 0; smr := 0; slcr := 0; sfr := 0; sodl := 0; sidl := 0;
    tbm := 0; tbll := 0; tbul := 0;
    portA := 0; portB := 0; portC := 0; portD := 0; portADir := 0; portBSel := 0;
    portCDir := 0; portE := 0; portEDir := 0; eir := 0; cir := 0;
    ReleaseAllKeys; keyPressTtl := 0;
    keyboardEnabled := FALSE; consoleMode := FALSE; cocoaInput := FALSE;
    keyBufWrite := 0; keyBufRead := 0;
    FOR i := 0 TO 7 DO bsr[i] := 50H + i END;
    es2.state := idle; es3.state := idle;
    FlashErase(es2, 0, flashSize); FlashErase(es3, 0, flashSize);
    interactive := EmHost.IsTTY() # 0
  END Init;

BEGIN Init
END EmL28.
