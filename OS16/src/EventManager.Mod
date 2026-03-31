MODULE EventManager;
  CONST
    (* Event types *)
    EvNone*      = 0;
    EvKeyDown*   = 1;
    EvKeyUp*     = 2;
    EvMouseMove* = 3;
    EvMouseDown* = 4;
    EvMouseUp*   = 5;

    (* Modifier flags *)
    ModShift*    = 1;
    ModControl*  = 2;
    ModOption*   = 4;
    ModCommand*  = 8;
    ModCapsLock* = 16;

    QueueSize = 32;

  TYPE
    Event* = RECORD
      kind*: INTEGER;       (* event type: EvKeyDown, EvMouseMove, etc. *)
      keycode*: INTEGER;    (* ADB keycode (keyboard events) *)
      modifiers*: INTEGER;  (* modifier flags at time of event *)
      ch*: INTEGER;         (* ASCII code of key, 0 if none *)
      dx*: INTEGER;         (* mouse X delta (mouse events) *)
      dy*: INTEGER;         (* mouse Y delta (mouse events) *)
      button*: INTEGER      (* mouse button: 1=pressed, 0=released *)
    END;

  VAR
    queue: ARRAY QueueSize OF Event;
    head, tail: INTEGER;

  PROCEDURE PostEvent*(VAR e: Event);
    VAR next: INTEGER;
  BEGIN
    next := (tail + 1) MOD QueueSize;
    IF next # head THEN
      queue[tail] := e;
      tail := next
    END
  END PostEvent;

  PROCEDURE NextEvent*(VAR e: Event);
  BEGIN
    IF head # tail THEN
      e := queue[head];
      head := (head + 1) MOD QueueSize
    ELSE
      e.kind := EvNone
    END
  END NextEvent;

  PROCEDURE HasEvent*(): BOOLEAN;
  BEGIN RETURN head # tail
  END HasEvent;

BEGIN
  head := 0;
  tail := 0
END EventManager.
