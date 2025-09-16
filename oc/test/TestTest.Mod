MODULE TestTest;
   IMPORT TestTool;
	  
   VAR
	  str: ARRAY 64 OF CHAR;
   
BEGIN
   str := "TestTest Begin";
   TestTool.Println(str); TestTool.NewLine();
END TestTest.
