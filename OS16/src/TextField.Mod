MODULE TextField; (* A line of text the user edits (model: TextField, a Control).
   Not yet written  *)

  IMPORT Control;

  TYPE
    TextField* = POINTER TO TextFieldDesc;
    TextFieldDesc* = RECORD (Control.ControlDesc) text*: ARRAY 128 OF CHAR END;

END TextField.
