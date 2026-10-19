MODULE TextView; (* Text shown in a view, over several lines (model: TextView, a
   Control). Not yet written  *)

  IMPORT Control;

  TYPE
    TextView* = POINTER TO TextViewDesc;
    TextViewDesc* = RECORD (Control.ControlDesc) END;

END TextView.
