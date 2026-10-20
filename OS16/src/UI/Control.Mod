MODULE Control; (* A view the user works: it can be enabled or not and
   holds a value (model: Control, a View). Button, TextView, TextField,
   Switch, Select and ListView extend it. Not yet written beyond its
   state. *)

  IMPORT View;

  TYPE
    Control* = POINTER TO ControlDesc;
    ControlDesc* = RECORD (View.ViewDesc)
      enabled*: BOOLEAN;
      value*: INTEGER
    END;

END Control.
