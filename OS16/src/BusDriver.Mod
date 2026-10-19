MODULE BusDriver; (* A bus with devices on it (model: BusDriver, a
   Driver): it resets the bus, finds what is attached and polls it.
   ADBManager and SCSIManager extend it. *)

  IMPORT Driver;

  TYPE
    BusDriver* = POINTER TO BusDriverDesc;
    BusDriverDesc* = RECORD (Driver.DriverDesc) END;

  (* Reset the bus and the devices on it. *)
  PROCEDURE (b: BusDriver) Reset*;
  BEGIN
  END Reset;

  (* Service the bus: collect what its devices have for the system. *)
  PROCEDURE (b: BusDriver) Poll*;
  BEGIN
  END Poll;

END BusDriver.
