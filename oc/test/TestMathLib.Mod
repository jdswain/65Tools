MODULE TestMathLib;
  IMPORT MathLib, Out;
BEGIN
  Out.Int(MathLib.Twice(21), 0); Out.Ln;
  Out.Int(MathLib.AddTwo(10, 32), 0); Out.Ln
END TestMathLib.
