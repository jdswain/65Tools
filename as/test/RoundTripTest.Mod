MODULE RoundTripTest;
  (* Imports the assembled module RoundTrip; see run_tests.sh. *)
  IMPORT Out, RoundTrip;
BEGIN
  Out.Int(RoundTrip.Twice(21), 0); Out.Ln;
  Out.Int(RoundTrip.AddTwo(40, 3), 0); Out.Ln
END RoundTripTest.
