MODULE CharacterDriver; (* A device read and written a character at a
   time (model: CharacterDriver, a Driver). Serial extends it. *)

  IMPORT Driver;

  TYPE
    CharacterDriver* = POINTER TO CharacterDriverDesc;
    CharacterDriverDesc* = RECORD (Driver.DriverDesc) END;

  (* the next character, or -1 if none is waiting *)
  PROCEDURE (d: CharacterDriver) Read*(): INTEGER;
  BEGIN RETURN -1
  END Read;

  (* 0, or a negative error *)
  PROCEDURE (d: CharacterDriver) Write*(ch: CHAR): INTEGER;
  BEGIN RETURN -1
  END Write;

END CharacterDriver.
