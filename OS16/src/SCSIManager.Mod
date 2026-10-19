MODULE SCSIManager; (* The SCSI bus (model: SCSIManager, a BusDriver), and
   the hard disks on it, which it owns (the model's composition). Not yet
   written: Reset will scan the bus for targets and make a HardDisk for
   each. *)

  IMPORT BusDriver, HardDisk;

  CONST MaxTargets* = 7;

  TYPE
    SCSIManager* = POINTER TO SCSIManagerDesc;
    SCSIManagerDesc* = RECORD (BusDriver.BusDriverDesc)
      disks*: ARRAY MaxTargets OF HardDisk.HardDisk   (* NIL: no disk at that target *)
    END;

END SCSIManager.
