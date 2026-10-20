MODULE ListView; (* A list of items to choose from; value is the item chosen
   (model: ListView, a Control). Not yet written  *)

  IMPORT Control;

  TYPE
    ListView* = POINTER TO ListViewDesc;
    ListViewDesc* = RECORD (Control.ControlDesc) END;

END ListView.
