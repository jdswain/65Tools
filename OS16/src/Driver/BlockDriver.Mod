MODULE BlockDriver; (* A device read and written in fixed blocks (model:
   BlockDriver, a Driver). Floppy, SCSIDisk and DiskPartition extend it;
   a file system (Files) is mounted on one.

   Blocks are numbered from 0 to Blocks() - 1, as LONGINT: a hard disk
   has more than the 32767 an INTEGER counts. *)

  IMPORT Driver;

  CONST
    BlockSize* = 512;
    (* errors, negated, of ReadBlock and WriteBlock; a driver may add its own *)
    errRange* = 1;      (* no such block *)
    errMedium* = 2;     (* no medium, or the device did not answer *)
    errIO* = 3;         (* the block was not read or written *)
    errProtected* = 4;  (* the medium is write protected *)

  TYPE
    BlockDriver* = POINTER TO BlockDriverDesc;
    BlockDriverDesc* = RECORD (Driver.DriverDesc) END;

  (* Read block n into buf: 0, or a negative error. *)
  PROCEDURE (d: BlockDriver) ReadBlock*(n: LONGINT; VAR buf: ARRAY OF BYTE): INTEGER;
  BEGIN RETURN -errMedium
  END ReadBlock;

  (* Write buf to block n: 0, or a negative error. *)
  PROCEDURE (d: BlockDriver) WriteBlock*(n: LONGINT; VAR buf: ARRAY OF BYTE): INTEGER;
  BEGIN RETURN -errMedium
  END WriteBlock;

  (* How many blocks it has: 0 if it does not know (no medium). *)
  PROCEDURE (d: BlockDriver) Blocks*(): LONGINT;
  BEGIN RETURN 0
  END Blocks;

END BlockDriver.
