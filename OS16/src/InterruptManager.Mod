MODULE InterruptManager;
  IMPORT SYSTEM;

  CONST
    MaxHandlers = 8;
    IRQVector = 0FFEEH;
    Trampoline = 0FF00H;
    T1CL = 0C024H;  (* VIA Timer 1 counter low — read clears T1 IFR *)

  TYPE
    Handler* = PROCEDURE;

  VAR
    handlers: ARRAY MaxHandlers OF Handler;
    count: INTEGER;
    dispatchProc: Handler;  (* holds full addr+bank of Dispatch *)

  PROCEDURE Register*(h: Handler);
  BEGIN
    IF count < MaxHandlers THEN
      handlers[count] := h;
      INC(count)
    END
  END Register;

  (* Normal exported procedure — called from trampoline via JSL *)
  PROCEDURE Dispatch*;
    VAR i: INTEGER; b: BYTE;
  BEGIN
    (* Acknowledge T1 interrupt by reading T1C-L *)
    SYSTEM.GET(0, T1CL, b);
    (* Call all registered handlers *)
    i := 0;
    WHILE i < count DO
      handlers[i];
      INC(i)
    END
  END Dispatch;

  PROCEDURE Init*;
    VAR b: BYTE; base, i: INTEGER;
  BEGIN
    count := 0;
    dispatchProc := Dispatch;  (* capture full 4-byte addr+bank *)
    base := SYSTEM.ADR(dispatchProc);  (* address of proc var in data area *)

    (* Write trampoline at $FF00:
       REP #$30; PHA; PHX; PHY; JSL Dispatch; PLY; PLX; PLA; RTI *)
    i := 0;
    b := 0C2H; SYSTEM.PUT(0, Trampoline + i, b); INC(i);  (* REP *)
    b := 030H; SYSTEM.PUT(0, Trampoline + i, b); INC(i);  (* #$30 *)
    b := 048H; SYSTEM.PUT(0, Trampoline + i, b); INC(i);  (* PHA *)
    b := 0DAH; SYSTEM.PUT(0, Trampoline + i, b); INC(i);  (* PHX *)
    b := 05AH; SYSTEM.PUT(0, Trampoline + i, b); INC(i);  (* PHY *)
    b := 022H; SYSTEM.PUT(0, Trampoline + i, b); INC(i);  (* JSL *)
    (* Copy 3 address bytes from dispatchProc variable *)
    SYSTEM.GET(0, base, b);     SYSTEM.PUT(0, Trampoline + i, b); INC(i);  (* addr lo *)
    SYSTEM.GET(0, base + 1, b); SYSTEM.PUT(0, Trampoline + i, b); INC(i);  (* addr hi *)
    SYSTEM.GET(0, base + 2, b); SYSTEM.PUT(0, Trampoline + i, b); INC(i);  (* bank *)
    b := 07AH; SYSTEM.PUT(0, Trampoline + i, b); INC(i);  (* PLY *)
    b := 0FAH; SYSTEM.PUT(0, Trampoline + i, b); INC(i);  (* PLX *)
    b := 068H; SYSTEM.PUT(0, Trampoline + i, b); INC(i);  (* PLA *)
    b := 040H; SYSTEM.PUT(0, Trampoline + i, b);           (* RTI *)

    (* Set native IRQ vector to point to trampoline *)
    b := 0; SYSTEM.PUT(0, IRQVector, b);         (* $00 = low byte of $FF00 *)
    b := 0FFH; SYSTEM.PUT(0, IRQVector + 1, b)   (* $FF = high byte of $FF00 *)
  END Init;

BEGIN
  count := 0
END InterruptManager.
