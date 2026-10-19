MODULE Dialog; (* A window that asks the user something and waits for the
   answer (model: Dialog, a View). FileDialog extends it. Not yet
   written  *)

  IMPORT View;

  TYPE
    Dialog* = POINTER TO DialogDesc;
    DialogDesc* = RECORD (View.ViewDesc) END;

END Dialog.
