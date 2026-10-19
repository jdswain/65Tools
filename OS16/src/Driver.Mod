MODULE Driver; (* The base of every device driver (model: Driver).

   A driver has a name and two control calls, Get and Set, that take a
   key defined by the driver (an error code, a track, a baud rate, ...).
   CharacterDriver, BlockDriver, BusDriver and NetworkInterface extend
   it. *)

  CONST NameLen* = 16;

  TYPE
    Driver* = POINTER TO DriverDesc;
    DriverDesc* = RECORD
      name*: ARRAY NameLen OF CHAR
    END;

  (* the value of a control parameter; -1 for a key the driver lacks *)
  PROCEDURE (d: Driver) Get*(key: INTEGER; VAR val: INTEGER);
  BEGIN val := -1
  END Get;

  PROCEDURE (d: Driver) Set*(key, val: INTEGER);
  BEGIN
  END Set;

  PROCEDURE SetName*(d: Driver; name: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE (i < LEN(name)) & (i < NameLen - 1) & (name[i] # 0X) DO d.name[i] := name[i]; INC(i) END;
    d.name[i] := 0X
  END SetName;

END Driver.
