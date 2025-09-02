MODULE SetOperationsTest;
   IMPORT SYSTEM;

   VAR
      s1, s2, s3: SET;
      i: INTEGER;
    
   PROCEDURE PutChar(value: CHAR);
	  CONST
		 ACIA_DATA = 0C000H;
   BEGIN
      SYSTEM.PUT(ACIA_DATA, value);
   END PutChar;

   PROCEDURE PutString(str: ARRAY OF CHAR);
      VAR i: INTEGER;
   BEGIN
      i := 0;
      WHILE (i < LEN(str)) & (str[i] # 0X) DO
         PutChar(str[i]);
         INC(i)
      END
   END PutString;

   PROCEDURE TestSetOp(name: ARRAY OF CHAR; result: BOOLEAN);
   BEGIN
      PutString(name);
      IF result THEN 
         PutChar('T')
      ELSE
         PutChar('F')
      END;
      PutChar(' ')
   END TestSetOp;

BEGIN
   (* Test SET literal creation *)
   s1 := {1, 3, 5, 7};         (* Set with elements 1, 3, 5, 7 *)
   s2 := {0, 2, 4, 6, 8};      (* Set with elements 0, 2, 4, 6, 8 *)
   s3 := {};                   (* Empty set *)

   PutString("SET Operations Test:");
   PutChar(0AX); (* newline *)

   (* Test set membership (IN operator) *)
   TestSetOp("1IN{1,3,5}:", 1 IN s1);           (* Should be TRUE *)
   TestSetOp("2IN{1,3,5}:", 2 IN s1);           (* Should be FALSE *)
   TestSetOp("0IN{}:", 0 IN s3);                (* Should be FALSE *)
   PutChar(0AX);

   (* Test set union (+) *)
   s3 := s1 + s2;  (* Union of s1 and s2 *)
   TestSetOp("Union1:", 1 IN s3);               (* Should be TRUE *)
   TestSetOp("Union2:", 2 IN s3);               (* Should be TRUE *)
   TestSetOp("Union9:", 9 IN s3);               (* Should be FALSE *)
   PutChar(0AX);

   (* Test set intersection (*) *)
   s1 := {1, 2, 3, 4, 5};
   s2 := {3, 4, 5, 6, 7};
   s3 := s1 * s2;  (* Intersection *)
   TestSetOp("Inter3:", 3 IN s3);               (* Should be TRUE *)
   TestSetOp("Inter1:", 1 IN s3);               (* Should be FALSE *)
   TestSetOp("Inter7:", 7 IN s3);               (* Should be FALSE *)
   PutChar(0AX);

   (* Test set difference (-) *)
   s1 := {1, 2, 3, 4, 5};
   s2 := {3, 4, 5};
   s3 := s1 - s2;  (* Difference: elements in s1 but not in s2 *)
   TestSetOp("Diff1:", 1 IN s3);                (* Should be TRUE *)
   TestSetOp("Diff3:", 3 IN s3);                (* Should be FALSE *)
   TestSetOp("Diff2:", 2 IN s3);                (* Should be TRUE *)
   PutChar(0AX);

   (* Test symmetric difference (/) *)
   s1 := {1, 2, 3, 4};
   s2 := {3, 4, 5, 6};
   s3 := s1 / s2;  (* Symmetric difference: elements in s1 or s2 but not both *)
   TestSetOp("SymDiff1:", 1 IN s3);             (* Should be TRUE *)
   TestSetOp("SymDiff3:", 3 IN s3);             (* Should be FALSE *)
   TestSetOp("SymDiff5:", 5 IN s3);             (* Should be TRUE *)
   PutChar(0AX);

   (* Test set equality and inclusion *)
   s1 := {1, 2, 3};
   s2 := {1, 2, 3};
   s3 := {1, 2};
   TestSetOp("Equal:", s1 = s2);                (* Should be TRUE *)
   TestSetOp("NotEqual:", s1 = s3);             (* Should be FALSE *)
   TestSetOp("Subset:", s3 <= s1);              (* Should be TRUE *)
   TestSetOp("NotSubset:", s1 <= s3);           (* Should be FALSE *)
   PutChar(0AX);

   (* Test INCL and EXCL procedures *)
   s1 := {1, 3, 5};
   INCL(s1, 7);    (* Include 7 in the set *)
   EXCL(s1, 3);    (* Exclude 3 from the set *)
   TestSetOp("INCL7:", 7 IN s1);                (* Should be TRUE *)
   TestSetOp("EXCL3:", 3 IN s1);                (* Should be FALSE *)
   TestSetOp("Keep1:", 1 IN s1);                (* Should be TRUE *)
   PutChar(0AX);

   (* Test range sets *)
   s1 := {5..10};   (* Set with elements 5, 6, 7, 8, 9, 10 *)
   TestSetOp("Range5:", 5 IN s1);               (* Should be TRUE *)
   TestSetOp("Range8:", 8 IN s1);               (* Should be TRUE *)
   TestSetOp("Range4:", 4 IN s1);               (* Should be FALSE *)
   TestSetOp("Range11:", 11 IN s1);             (* Should be FALSE *)
   PutChar(0AX);

   PutString("SET test complete");
   PutChar(0AX)
END SetOperationsTest.