MODULE Switch; (* An on/off control; value is 0 or 1 (model: Switch, a
   Control). Not yet written  *)

  IMPORT Control;

  TYPE
    Switch* = POINTER TO SwitchDesc;
    SwitchDesc* = RECORD (Control.ControlDesc) END;

END Switch.
