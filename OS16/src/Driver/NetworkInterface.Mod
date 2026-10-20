MODULE NetworkInterface; (* A network interface (model: NetworkInterface, a Driver).
   Not yet written: it will send and receive frames  *)

  IMPORT Driver;

  TYPE
    NetworkInterface* = POINTER TO NetworkInterfaceDesc;
    NetworkInterfaceDesc* = RECORD (Driver.DriverDesc) END;

END NetworkInterface.
