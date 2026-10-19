MODULE HardDisk; (* A hard disk on the SCSI bus (model: HardDisk, a BlockDriver).
   Not yet written: the SCSIManager that owns it will give it its target
   and pass its blocks  *)

  IMPORT BlockDriver;

  TYPE
    HardDisk* = POINTER TO HardDiskDesc;
    HardDiskDesc* = RECORD (BlockDriver.BlockDriverDesc) target*: INTEGER END;

END HardDisk.
