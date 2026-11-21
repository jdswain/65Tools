MODULE EmMini816; (* The Mini816 (../../../Hardware/Mini816, its
   docs/em16-profile.md): a W65C816S (EmW816) at 7.3728 MHz, 512K of RAM,
   512K of flash (EmFlash), the CPLD's decode, the W65C22 (Em65C22) and
   the Z85C30 (EmZ85C30), the TMS9118 (EmTMS9918), the keyboard, the
   joystick and the microSD card on the VIA (EmSD's card), and the
   TIM-Bus's slots.

   The CPLD latches bank bits 0-3 only, so the map repeats every 16 banks:

     $00:0000-$00:BFFF   RAM
     $00:C000-$00:CFFF   I/O: $C000 VIA, $C010 SCC (mirrored every 4),
                         $C020 VDP, $C080 + n * 16 slot n's DEVSEL,
                         $Cn00 its IOSEL, $C800 the slots' IOSTRB
     $00:D000-$00:FFFF   the top 12K of the flash, the boot window
     $01-$07             RAM
     $08-$0F             the flash

   with a 128K RAM's banks $02-$07 mirroring $00-$01 and a smaller
   flash mirrored. A cycle selects something only with VDA or VPA; an
   internal one (the emulation mode's dummy write too) selects nothing.
   Nothing driving the bus reads the open bus value ($FF).

   Time: an I/O cycle (VDA or VPA, $00:C000-$00:CFFF) is stretched to
   ioClks CPU clocks (8 until the CPLD fixes it), the others take one.
   now counts the CPU clocks, the time the SCC and the rest run by; phi2
   counts PHI2's cycles, a stretched one among them once, the VIA's.

   IRQ is the wired OR of the VIA's, the SCC's and the cards'; NMI and
   reset are buttons (EmHost.Buttons: SIGUSR1 and SIGUSR2). Reset resets
   the CPU, the VIA and the cards but not the SCC, which has no reset
   pin, or the SD card. STP ends the run; Run keeps to real time but
   with Turbo.

   The SD card's SPI is port B's, bit by bit: PB3 MOSI, PB4 SCK, PB5 CS
   (low selects), PB6 MISO, in mode 0: the card takes MOSI as SCK rises
   and puts its next bit on MISO as SCK falls, a byte's first as CS falls
   or as the last byte's eighth bit ends. MISO is pulled up, 1 with the
   card deselected or out. Its detect is CA1, low with a card in but with
   SetCardDetect(FALSE); a card is in if EmSD has one mounted.

   The VDP runs from its own crystal, in the time now is (the wall's),
   at $C020 (A0 its MODE, mirrored every 2); its INT is CB1, low while
   asserted. RESB resets it.

   The keyboard's columns are selected by PB0-PB2 and CA2 (bit 3), and
   the selected column's rows read on port A, 0 for a key down: columns
   0-7 the 64 keys, 15 the joystick (rows 0-4 up, down, left, right,
   fire), 8-14 nothing. Key presses them (the window, -key); a button
   also ejects or inserts the SD card (EmHost.Buttons' 4).

   The speaker (EmSound) is PB7 as port B drives it, and CB2 if it is
   started so; their changes are passed on at the wall's time (now, less
   the PHI2 cycles since the change), and the samples brought up to now
   as the run goes. *)

  IMPORT EmHost, EmW816, EmFlash, Em65C22, EmZ85C30, EmSD, EmTMS9918, EmSound;

  CONST
    pclk* = 7372800;              (* the SCC's PCLK, never stretched *)
    vdpXtal = 10738635;           (* the VDP's crystal *)

  TYPE
    (* a TIM-Bus card: an access to its slot's DEVSEL (sel 0), IOSEL (1) or
       the shared IOSTRB (2), at A7-A0; a read's byte, or -1 not driven *)
    Card* = PROCEDURE (sel, addr, data: INTEGER; write: BOOLEAN): INTEGER;
    CardLine* = PROCEDURE (): BOOLEAN;

  VAR
    ram: ARRAY 80000H OF BYTE;
    ramMask: INTEGER;
    ioClks*, openBus*: INTEGER;
    cpuHz*: LONGINT;
    now*, phi2*: LONGINT;
    turbo: BOOLEAN;
    cards: ARRAY 8 OF Card;
    cardIrq: ARRAY 8 OF CardLine;
    cardReset: ARRAY 8 OF PROCEDURE;
    nextButtons, nextPace, nextTick: LONGINT;
    (* the SD card: port B's pins as last driven, the bits of the byte
       shifted in, the byte, the card's byte going out, MISO *)
    sdPins, sdBits, sdIn, sdOut, miso: INTEGER;
    cdLow: BOOLEAN;               (* CA1 low with a card in *)
    matrix: ARRAY 16 OF INTEGER;  (* each column's keys down, a bit a row *)
    column: INTEGER;              (* the column selected *)
    cb1: INTEGER;                 (* CB1 as the VDP drives it *)
    joyArrows*: INTEGER;          (* 1: the window's arrows are the joystick's *)
    quit: BOOLEAN;                (* the window closed *)

  PROCEDURE SetRam*(size: INTEGER);
  BEGIN IF size = 20000H THEN ramMask := 1FFFFH ELSE ramMask := 7FFFFH END
  END SetRam;

  PROCEDURE SetIoClks*(n: INTEGER);
  BEGIN IF n >= 1 THEN ioClks := n END
  END SetIoClks;

  PROCEDURE SetOpenBus*(v: INTEGER);
  BEGIN openBus := AND(v, 0FFH)
  END SetOpenBus;

  PROCEDURE SetCpuClock*(hz: LONGINT);
  BEGIN IF hz > 0 THEN cpuHz := hz END
  END SetCpuClock;

  PROCEDURE Turbo*;
  BEGIN turbo := TRUE
  END Turbo;

  (* the level of CA1 that means a card is in: low (TRUE) or high *)
  PROCEDURE SetCardDetect*(low: BOOLEAN);
  BEGIN cdLow := low
  END SetCardDetect;

  (* slot n's card, its IRQ line and its reset (NIL: none) *)
  PROCEDURE SetCard*(n: INTEGER; c: Card; irq: CardLine; reset: PROCEDURE);
  BEGIN cards[n] := c; cardIrq[n] := irq; cardReset[n] := reset
  END SetCard;

  PROCEDURE JoyArrows*;
  BEGIN joyArrows := 1
  END JoyArrows;

  (* key (column c, row r) down or up (1, 0) *)
  PROCEDURE Key*(c, r, down: INTEGER);
  BEGIN
    IF ((c >= 0) & (c < 8) OR (c = 15)) & (r >= 0) & (r < 8) THEN
      IF down # 0 THEN matrix[c] := ORA(matrix[c], ASL(1, r)) ELSE matrix[c] := AND(matrix[c], 0FFH - ASL(1, r)) END
    END
  END Key;

  (* 1 a card in the slot, 0 out, -1 none given (-sd) *)
  PROCEDURE CardIn*(): INTEGER;
    VAR v: INTEGER;
  BEGIN IF ~EmSD.loaded THEN v := -1 ELSIF EmSD.mounted THEN v := 1 ELSE v := 0 END; RETURN v
  END CardIn;

  (* the run ended from outside: the window closed *)
  PROCEDURE Stop*;
  BEGIN quit := TRUE
  END Stop;

  (* the time in the VDP's crystal's cycles *)
  PROCEDURE Vclk(): LONGINT;
  BEGIN RETURN now DIV cpuHz * vdpXtal + now MOD cpuHz * vdpXtal DIV cpuHz
  END Vclk;

  (* CB1 from the VDP's INT *)
  PROCEDURE VdpLine;
    VAR v: INTEGER;
  BEGIN IF EmTMS9918.Int() THEN v := 0 ELSE v := 1 END;
    IF v # cb1 THEN cb1 := v; Em65C22.SetCB1(v, phi2) END
  END VdpLine;

  (* the time in PCLK cycles *)
  PROCEDURE Pclk(): LONGINT;
    VAR t: LONGINT;
  BEGIN IF cpuHz = pclk THEN t := now ELSE t := now * pclk DIV cpuHz END; RETURN t
  END Pclk;

  PROCEDURE CardAccess(n, sel, a, d: INTEGER; write: BOOLEAN): INTEGER;
    VAR v: INTEGER;
  BEGIN v := -1;
    IF cards[n] # NIL THEN v := cards[n](sel, AND(a, 0FFH), d, write) END;
    IF v < 0 THEN v := openBus END;
    RETURN v
  END CardAccess;

  (* the IOSTRB space is every card's *)
  PROCEDURE Strobe(a, d: INTEGER; write: BOOLEAN): INTEGER;
    VAR n, v, r: INTEGER;
  BEGIN r := -1;
    FOR n := 0 TO 7 DO
      IF cards[n] # NIL THEN v := cards[n](2, AND(a, 0FFH), d, write); IF v >= 0 THEN r := v END END
    END;
    IF r < 0 THEN r := openBus END;
    RETURN r
  END Strobe;

  PROCEDURE IO(a, d: INTEGER; write: BOOLEAN): INTEGER;
    VAR v: INTEGER;
  BEGIN v := openBus;
    IF a < 0C010H THEN
      IF write THEN Em65C22.Write(a, d, phi2) ELSE v := Em65C22.Read(a, phi2) END
    ELSIF a < 0C020H THEN
      IF write THEN EmZ85C30.Write(a, d, Pclk()) ELSE v := EmZ85C30.Read(a, Pclk()) END
    ELSIF a < 0C030H THEN
      IF write THEN EmTMS9918.Write(a, d, Vclk()) ELSE v := EmTMS9918.Read(a, Vclk()) END;
      VdpLine
    ELSIF a < 0C080H THEN                           (* IO_SP3, none *)
    ELSIF a < 0C100H THEN v := CardAccess(AND((a - 0C080H) DIV 16, 7), 0, a, d, write)
    ELSIF a < 0C800H THEN v := CardAccess(AND(a DIV 100H, 7), 1, a, d, write)
    ELSE v := Strobe(a, d, write)
    END;
    RETURN v
  END IO;

  (* A bus cycle of the CPU *)
  PROCEDURE Bus(a, kind, d: INTEGER): INTEGER;
    VAR bank, off, v: INTEGER; write: BOOLEAN;
  BEGIN v := openBus; INC(phi2);
    IF AND(kind, EmW816.vda + EmW816.vpa) = 0 THEN INC(now)
    ELSE bank := AND(a DIV 10000H, 0FH); off := AND(a, 0FFFFH); write := ODD(kind DIV EmW816.wr);
      IF bank = 0 THEN
        IF off < 0C000H THEN INC(now);
          IF write THEN ram[off] := d ELSE v := ram[off] END
        ELSIF off < 0D000H THEN now := now + ioClks; v := IO(off, d, write)
        ELSE INC(now); off := EmFlash.size - 3000H + off - 0D000H;
          IF write THEN EmFlash.Write(off, d) ELSE v := EmFlash.Read(off) END
        END
      ELSIF bank < 8 THEN INC(now); off := AND(bank * 10000H + off, ramMask);
        IF write THEN ram[off] := d ELSE v := ram[off] END
      ELSE INC(now); off := (bank - 8) * 10000H + off;
        IF write THEN EmFlash.Write(off, d) ELSE v := EmFlash.Read(off) END
      END
    END;
    RETURN v
  END Bus;

  (* --- the VIA's pins --- *)

  (* port A: the selected column's rows *)
  PROCEDURE PinsA(): INTEGER;
  BEGIN RETURN 0FFH - matrix[column]
  END PinsA;

  (* port B: MISO, the rest pulled up *)
  PROCEDURE PinsB(): INTEGER;
  BEGIN RETURN 0BFH + miso * 40H
  END PinsB;

  (* port B's outputs, CA2 or CB2 changed (at t, PHI2's): the keyboard's
     column, the speaker, the SD card's SPI *)
  PROCEDURE Lines(pb, ca2, cb2: INTEGER; t: LONGINT);
    VAR was: INTEGER;
  BEGIN column := pb MOD 8 + ca2 * 8;
    IF EmSound.on THEN EmSound.Set(0, pb DIV 80H, now - (phi2 - t)); EmSound.Set(1, cb2, now - (phi2 - t)) END;
    was := sdPins; sdPins := pb;
    IF ODD(pb DIV 20H) THEN                          (* CS high *)
      IF ~ODD(was DIV 20H) THEN EmSD.Select(FALSE) END;
      miso := 1
    ELSIF ODD(was DIV 20H) THEN                      (* CS falling *)
      EmSD.Select(TRUE); sdBits := 0; sdIn := 0; sdOut := EmSD.Send(); miso := sdOut DIV 80H
    ELSIF ODD(pb DIV 10H) & ~ODD(was DIV 10H) THEN   (* SCK rising *)
      sdIn := sdIn * 2 + pb DIV 8 MOD 2; INC(sdBits);
      IF sdBits = 8 THEN EmSD.Receive(sdIn) END
    ELSIF ~ODD(pb DIV 10H) & ODD(was DIV 10H) THEN   (* SCK falling *)
      IF sdBits = 8 THEN sdBits := 0; sdIn := 0; sdOut := EmSD.Send() END;
      miso := LSR(sdOut, 7 - sdBits) MOD 2
    END
  END Lines;

  (* CA1, the card's detect *)
  PROCEDURE CardDetect(): INTEGER;
    VAR v: INTEGER;
  BEGIN IF EmSD.mounted = cdLow THEN v := 0 ELSE v := 1 END; RETURN v
  END CardDetect;

  (* IRQB, the devices brought up to now first *)
  PROCEDURE Irq(): BOOLEAN;
    VAR n: INTEGER; r: BOOLEAN;
  BEGIN EmTMS9918.Tick(Vclk()); VdpLine; Em65C22.Tick(phi2); EmZ85C30.Tick(Pclk());
    r := Em65C22.Irq() OR EmZ85C30.Irq();
    FOR n := 0 TO 7 DO IF (cardIrq[n] # NIL) & cardIrq[n]() THEN r := TRUE END END;
    RETURN r
  END Irq;

  (* RESB: all but the SCC *)
  PROCEDURE Reset*;
    VAR n: INTEGER;
  BEGIN Em65C22.SetCA1(CardDetect(), phi2); Em65C22.Reset; EmTMS9918.Reset; VdpLine;
    FOR n := 0 TO 7 DO IF cardReset[n] # NIL THEN cardReset[n] END END;
    EmW816.SetBus(Bus, Irq); EmW816.Reset
  END Reset;

  (* the buttons, a few hundred times a second *)
  PROCEDURE Buttons;
    VAR b: INTEGER;
  BEGIN b := EmHost.Buttons();
    IF ODD(b) THEN EmW816.Nmi END;
    IF ODD(b DIV 2) THEN Reset END;
    IF ODD(b DIV 4) & EmSD.loaded THEN
      IF EmSD.mounted THEN EmSD.Eject ELSE EmSD.Insert END;
      Em65C22.SetCA1(CardDetect(), phi2)
    END;
    nextButtons := now + cpuHz DIV 200
  END Buttons;

  PROCEDURE Run*;
  BEGIN nextButtons := now; nextPace := now; nextTick := now;
    WHILE ~EmW816.stopped & ~quit DO EmW816.Step;
      IF now >= nextTick THEN
        EmTMS9918.Tick(Vclk()); VdpLine; Em65C22.Tick(phi2); EmZ85C30.Tick(Pclk()); nextTick := now + 64;
        IF EmSound.on THEN EmSound.Advance(now) END
      END;
      IF now >= nextButtons THEN Buttons END;
      IF ~turbo & (now >= nextPace) THEN EmHost.Pace(now, cpuHz); nextPace := now + cpuHz DIV 1000 END
    END;
    IF EmSound.on THEN EmSound.Advance(now); EmSound.Finish END;
    EmHost.DrainAll
  END Run;

  (* the RAM's contents at power on: what the chip held, here 0 *)
  PROCEDURE Init;
    VAR i: INTEGER;
  BEGIN
    FOR i := 0 TO LEN(ram) - 1 DO ram[i] := 0 END;
    FOR i := 0 TO 7 DO cards[i] := NIL; cardIrq[i] := NIL; cardReset[i] := NIL END;
    ramMask := 7FFFFH; ioClks := 8; openBus := 0FFH; cpuHz := pclk; now := 0; phi2 := 0; turbo := FALSE;
    sdPins := 0FFH; sdBits := 0; sdIn := 0; sdOut := 0FFH; miso := 1; cdLow := TRUE;
    FOR i := 0 TO 15 DO matrix[i] := 0 END;
    column := 15; cb1 := 1; joyArrows := 0; quit := FALSE;
    Em65C22.SetPins(PinsA, PinsB, Lines)
  END Init;

BEGIN Init
END EmMini816.
