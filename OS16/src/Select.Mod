MODULE Select; (* A choice of one item from a list that pops up; value is the
   item chosen (model: Select, a Control). Not yet written  *)

  IMPORT Control;

  TYPE
    Select* = POINTER TO SelectDesc;
    SelectDesc* = RECORD (Control.ControlDesc) END;

END Select.
