MODULE Serial; (* A serial port, the SoC's 6551 ACIA (model: Serial, a
   CharacterDriver). Not yet written: Read and Write will poll the ACIA's
   status for a received character and an empty transmitter  *)

  IMPORT CharacterDriver;

  TYPE
    Serial* = POINTER TO SerialDesc;
    SerialDesc* = RECORD (CharacterDriver.CharacterDriverDesc) base*: INTEGER   (* the ACIA's registers *) END;

END Serial.
