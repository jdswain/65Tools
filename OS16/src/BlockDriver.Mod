MODULE BlockDriver; (* A device read and written in fixed blocks (model:
   BlockDriver, a Driver). Floppy and HardDisk extend it; a FileSystem
   is mounted on one. *)

  IMPORT Driver;

  CONST BlockSize* = 512;

  TYPE
    BlockDriver* = POINTER TO BlockDriverDesc;
    BlockDriverDesc* = RECORD (Driver.DriverDesc) END;

  (* Read block n into buf: 0, or a negative error. *)
  PROCEDURE (d: BlockDriver) ReadBlock*(n: INTEGER; VAR buf: ARRAY OF BYTE): INTEGER;
  BEGIN RETURN -1
  END ReadBlock;

  (* Write buf to block n: 0, or a negative error. *)
  PROCEDURE (d: BlockDriver) WriteBlock*(n: INTEGER; VAR buf: ARRAY OF BYTE): INTEGER;
  BEGIN RETURN -1
  END WriteBlock;

END BlockDriver.
