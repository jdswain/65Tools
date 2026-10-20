MODULE FileDialog; (* A dialog to choose a file to open or a name to save under
   (model: FileDialog, a Dialog). Not yet written  *)

  IMPORT Dialog;

  TYPE
    FileDialog* = POINTER TO FileDialogDesc;
    FileDialogDesc* = RECORD (Dialog.DialogDesc) name*: ARRAY 128 OF CHAR END;

END FileDialog.
