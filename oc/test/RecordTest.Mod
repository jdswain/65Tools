(* String assignment to obj.name *)
MODULE RecordTest;
   IMPORT SYSTEM;

   TYPE
	  Object = POINTER TO ObjDesc;

      ObjDesc = RECORD
		 class, exno: BYTE;
		 expo, rdo: BOOLEAN;   (*exported / read-only*)
		 lev: INTEGER;
		 name: ARRAY 12 OF CHAR;
		 val: INTEGER
      END ;

   VAR
      a, b: INTEGER;
	  obj: ObjDesc;
	  pobj: Object;
	  
   PROCEDURE PutChar(value: CHAR);
	  CONST
		 ACIA_DATA = 0C000H;
   BEGIN
      SYSTEM.PUT(ACIA_DATA, value);
   END PutChar;

BEGIN
   pobj := ^obj;
   pobj->lev := 11;
   pobj->name[0] := "T";
   IF pobj.lev = 10 THEN
	  PutChar('P');
   ELSE
	  PutChar('F');
   END;
   PutChar(pobj.name[0]);
END RecordTest.