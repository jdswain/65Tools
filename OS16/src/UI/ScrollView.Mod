MODULE ScrollView; (* A view onto a larger one, with scroll bars (model: ScrollView,
   a View). Not yet written  *)

  IMPORT View;

  TYPE
    ScrollView* = POINTER TO ScrollViewDesc;
    ScrollViewDesc* = RECORD (View.ViewDesc) content*: View.View END;

END ScrollView.
