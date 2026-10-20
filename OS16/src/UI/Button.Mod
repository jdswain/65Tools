MODULE Button; (* A push button with a title (model: Button, a Control). Not yet
   written  *)

  IMPORT Control;

  TYPE
    Button* = POINTER TO ButtonDesc;
    ButtonDesc* = RECORD (Control.ControlDesc) title*: ARRAY 32 OF CHAR END;

END Button.
