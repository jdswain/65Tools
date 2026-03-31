MODULE ADBManager;
  IMPORT SYSTEM, EventManager, InterruptManager;

  CONST
    (* VIA 6522 register addresses *)
    PORTB = 0C020H;  (* Port B: strobe and status *)
    PORTA = 0C021H;  (* Port A: ADB data bus *)
    DDRB = 0C022H;  (* Data direction B *)
    DDRA = 0C023H;  (* Data direction A *)
    IER  = 0C02EH;  (* Interrupt enable register *)
    ACR  = 0C02BH;  (* Auxiliary control register *)
    T1LL = 0C024H;  (* Timer 1 latch low / counter low *)
    T1CH = 0C025H;  (* Timer 1 counter high *)

    (* ADB command bytes: addr(4) | cmd(2) | reg(2) *)
    KbdTalk0   = 02CH;  (* Keyboard addr=2, Talk=11, Reg0=00 *)
    MouseTalk0 = 03CH;  (* Mouse addr=3, Talk=11, Reg0=00 *)
    ADBReset   = 000H;  (* SendReset: bits 3-0 all zero *)

    (* ADB modifier keycodes *)
    kcLeftShift    = 038H;
    kcRightShift   = 03CH;
    kcLeftControl  = 03BH;
    kcRightControl = 03EH;
    kcLeftOption   = 03AH;
    kcRightOption  = 03DH;
    kcLeftCommand  = 037H;
    kcRightCommand = 036H;
    kcCapsLock     = 039H;

    (* ADB keycode to ASCII lookup tables (128 entries each)
       Index = ADB keycode, Value = ASCII code (0 = no mapping)
       ADB keycodes match macOS virtual keycodes *)
    KeyTable = ARRAY OF INTEGER {
      (* $00-$0F: a,s,d,f,h,g,z,x, c,v,§,b,q,w,e,r *)
       97,115,100,102,104,103,122,120,  99,118,  0, 98,113,119,101,114,
      (* $10-$1F: y,t,1,2,3,4,6,5, =,9,7,-,8,0,],o *)
      121,116, 49, 50, 51, 52, 54, 53,  61, 57, 55, 45, 56, 48, 93,111,
      (* $20-$2F: u,[,i,p,CR,l,j,', k,;,\,,,/,n,m,. *)
      117, 91,105,112, 13,108,106, 39, 107, 59, 92, 44, 47,110,109, 46,
      (* $30-$3F: Tab,Space,`,BS, (undef),Esc, modifiers... *)
        9, 32, 96,  8,   0, 27,  0,  0,   0,  0,  0,  0,  0,  0,  0,  0,
      (* $40-$4F: (undef),KP.,undef,KP*, undef,KP+,undef,Clear,
                   (undef),(undef),(undef),KP/, KPEnter,undef,KP-,undef *)
        0, 46,  0, 42,   0, 43,  0,  0,   0,  0,  0, 47,  13,  0, 45,  0,
      (* $50-$5F: undef,KP=,KP0,KP1, KP2,KP3,KP4,KP5,
                  KP6,KP7,undef,KP8, KP9,undef,undef,undef *)
        0, 61, 48, 49,  50, 51, 52, 53,  54, 55,  0, 56,  57,  0,  0,  0,
      (* $60-$6F: F5,F6,F7,F3, F8,F9,undef,F11, undef,F13,F16,F14,
                  undef,F10,undef,F12 *)
        0,  0,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0,
      (* $70-$7F: undef,F15,Ins,Home, PgUp,FwdDel,F4,End,
                  F2,PgDn,F1,Left, Right,Down,Up,undef *)
        0,  0,  0,  0,   0,127,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0
    };

    ShiftTable = ARRAY OF INTEGER {
      (* $00-$0F: A,S,D,F,H,G,Z,X, C,V,§,B,Q,W,E,R *)
       65, 83, 68, 70, 72, 71, 90, 88,  67, 86,  0, 66, 81, 87, 69, 82,
      (* $10-$1F: Y,T,!,@,#,$,^,%, +,(,&,_,*,),},O *)
       89, 84, 33, 64, 35, 36, 94, 37,  43, 40, 38, 95, 42, 41,125, 79,
      (* $20-$2F: U,{,I,P,CR,L,J,", K,:,|,<,?,N,M,> *)
       85,123, 73, 80, 13, 76, 74, 34,  75, 58,124, 60, 63, 78, 77, 62,
      (* $30-$3F: Tab,Space,~,BS, (undef),Esc, modifiers... *)
        9, 32,126,  8,   0, 27,  0,  0,   0,  0,  0,  0,  0,  0,  0,  0,
      (* $40-$4F: same as unshifted for keypad/special *)
        0, 46,  0, 42,   0, 43,  0,  0,   0,  0,  0, 47,  13,  0, 45,  0,
      (* $50-$5F *)
        0, 61, 48, 49,  50, 51, 52, 53,  54, 55,  0, 56,  57,  0,  0,  0,
      (* $60-$6F: function keys, no ASCII *)
        0,  0,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0,
      (* $70-$7F *)
        0,  0,  0,  0,   0,127,  0,  0,   0,  0,  0,  0,   0,  0,  0,  0
    };

  VAR
    mods: INTEGER;      (* current modifier state *)
    prevButton: INTEGER; (* previous mouse button state *)

  (* --- Low-level VIA access --- *)

  PROCEDURE PutReg(reg, val: INTEGER);
    VAR b: BYTE;
  BEGIN b := val; SYSTEM.PUT(0, reg, b)
  END PutReg;

  PROCEDURE GetReg(reg: INTEGER; VAR val: INTEGER);
    VAR b: BYTE;
  BEGIN SYSTEM.GET(0, reg, b); val := b
  END GetReg;

  PROCEDURE SendCommand(cmd: INTEGER);
  BEGIN
    PutReg(PORTA, cmd);
    PutReg(PORTB, 1);    (* strobe high *)
    PutReg(PORTB, 0)     (* strobe low *)
  END SendCommand;

  (* --- Modifier tracking --- *)

  PROCEDURE UpdateModifiers(keycode: INTEGER; down: BOOLEAN);
    VAR bit: INTEGER;
  BEGIN
    bit := 0;
    IF (keycode = kcLeftShift) OR (keycode = kcRightShift) THEN
      bit := EventManager.ModShift
    ELSIF (keycode = kcLeftControl) OR (keycode = kcRightControl) THEN
      bit := EventManager.ModControl
    ELSIF (keycode = kcLeftOption) OR (keycode = kcRightOption) THEN
      bit := EventManager.ModOption
    ELSIF (keycode = kcLeftCommand) OR (keycode = kcRightCommand) THEN
      bit := EventManager.ModCommand
    ELSIF keycode = kcCapsLock THEN
      IF down THEN
        mods := EOR(mods, EventManager.ModCapsLock)
      END;
      bit := 0  (* handled; skip below *)
    END;
    IF bit # 0 THEN
      IF down THEN
        mods := ORA(mods, bit)
      ELSE
        mods := AND(mods, EOR(bit, -1))  (* clear bit: AND with NOT *)
      END
    END
  END UpdateModifiers;

  (* --- Keycode to ASCII conversion --- *)

  PROCEDURE KeycodeToASCII(keycode: INTEGER): INTEGER;
    VAR ch: INTEGER; shifted: BOOLEAN;
  BEGIN
    ch := 0;
    IF (keycode >= 0) & (keycode < 128) THEN
      shifted := AND(mods, EventManager.ModShift) # 0;
      IF ~shifted & (AND(mods, EventManager.ModCapsLock) # 0) THEN
        (* CapsLock on, no shift: uppercase letters only *)
        ch := KeyTable[keycode];
        IF (ch >= 97) & (ch <= 122) THEN shifted := TRUE END
      END;
      IF shifted THEN ch := ShiftTable[keycode]
      ELSE ch := KeyTable[keycode]
      END;
      (* Control key: map A-Z/a-z to control codes 1-26 *)
      IF AND(mods, EventManager.ModControl) # 0 THEN
        IF (ch >= 65) & (ch <= 90) THEN ch := ch - 64
        ELSIF (ch >= 97) & (ch <= 122) THEN ch := ch - 96
        END
      END
    END
  RETURN ch
  END KeycodeToASCII;

  (* --- Event processing helpers --- *)

  PROCEDURE ProcessKey(raw: INTEGER);
    VAR keycode, ascii: INTEGER; down: BOOLEAN;
      e: EventManager.Event;
  BEGIN
    IF raw # 0FFH THEN
      keycode := AND(raw, 07FH);
      down := AND(raw, 080H) = 0;
      UpdateModifiers(keycode, down);
      ascii := KeycodeToASCII(keycode);
      e.keycode := keycode;
      e.modifiers := mods;
      e.ch := ascii;
      e.dx := 0; e.dy := 0; e.button := 0;
      IF down THEN e.kind := EventManager.EvKeyDown
      ELSE e.kind := EventManager.EvKeyUp
      END;
      EventManager.PostEvent(e)
    END
  END ProcessKey;

  PROCEDURE ProcessMouse(hi, lo: INTEGER);
    VAR btn, dx, dy: INTEGER;
      e: EventManager.Event;
  BEGIN
    (* hi: [button:1|dy:7], lo: [1:1|dx:7] *)
    IF AND(hi, 080H) = 0 THEN btn := 1 ELSE btn := 0 END;
    dy := AND(hi, 07FH);
    IF dy >= 64 THEN dy := dy - 128 END;  (* sign extend 7-bit *)
    dx := AND(lo, 07FH);
    IF dx >= 64 THEN dx := dx - 128 END;

    (* Button state change *)
    IF btn # prevButton THEN
      e.keycode := 0; e.ch := 0;
      e.modifiers := mods;
      e.dx := 0; e.dy := 0;
      e.button := btn;
      IF btn = 1 THEN e.kind := EventManager.EvMouseDown
      ELSE e.kind := EventManager.EvMouseUp
      END;
      EventManager.PostEvent(e);
      prevButton := btn
    END;

    (* Movement *)
    IF (dx # 0) OR (dy # 0) THEN
      e.kind := EventManager.EvMouseMove;
      e.keycode := 0; e.ch := 0;
      e.modifiers := mods;
      e.dx := dx; e.dy := dy;
      e.button := btn;
      EventManager.PostEvent(e)
    END
  END ProcessMouse;

  (* --- Public interface --- *)

  PROCEDURE Poll*;
    VAR status, hi, lo: INTEGER;
  BEGIN
    (* Poll keyboard: TALK Register 0 to address 2 *)
    SendCommand(KbdTalk0);
    GetReg(PORTB, status);
    IF ODD(status DIV 2) THEN  (* bit 1: data available *)
      GetReg(PORTA, hi);
      GetReg(PORTB, status);
      IF ODD(status DIV 2) THEN GetReg(PORTA, lo)
      ELSE lo := 0FFH
      END;
      ProcessKey(hi);
      ProcessKey(lo)
    END;

    (* Poll mouse: TALK Register 0 to address 3 *)
    SendCommand(MouseTalk0);
    GetReg(PORTB, status);
    IF ODD(status DIV 2) THEN
      GetReg(PORTA, hi);
      GetReg(PORTB, status);
      IF ODD(status DIV 2) THEN GetReg(PORTA, lo)
      ELSE lo := 080H  (* default: no dx, reserved bit 7 set *)
      END;
      ProcessMouse(hi, lo)
    END
  END Poll;

  PROCEDURE Modifiers*(): INTEGER;
  BEGIN RETURN mods
  END Modifiers;

  PROCEDURE Init*;
    VAR b: BYTE; v: INTEGER;
  BEGIN
    (* Set up VIA data direction registers *)
    PutReg(DDRB, 001H);  (* bit 0 = output for command strobe *)
    PutReg(DDRA, 0FFH);  (* all outputs for command/data writes *)

    (* Send ADB Reset *)
    SendCommand(ADBReset);

    (* Enable CA1 interrupt in VIA for SRQ notification *)
    b := 082H; SYSTEM.PUT(0, IER, b);

    (* Configure Timer 1 for periodic interrupts (~20Hz at 1MHz) *)
    (* ACR bit 6 = 1: free-running mode *)
    GetReg(ACR, v);
    v := ORA(v, 040H);
    PutReg(ACR, v);
    (* Set T1 latch to 50000 ($C350) for ~20Hz *)
    PutReg(T1LL, 050H);  (* low byte *)
    PutReg(T1CH, 0C3H);  (* high byte — starts timer *)
    (* Enable T1 interrupt in VIA IER: bit 7=1 (set mode), bit 6=1 (T1) *)
    b := 0C0H; SYSTEM.PUT(0, IER, b);

    (* Register ADB poll as interrupt handler *)
    InterruptManager.Register(Poll);

    mods := 0;
    prevButton := 0
  END Init;

BEGIN
  mods := 0;
  prevButton := 0
END ADBManager.
