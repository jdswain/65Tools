MODULE BranchBugTest;

PROCEDURE TestProc(condition: BOOLEAN): INTEGER;
BEGIN
    IF condition THEN
        RETURN 100
    ELSE
        RETURN 200
    END;
    RETURN 0  (* unreachable *)
END TestProc;

VAR result: INTEGER;

BEGIN
    result := TestProc(TRUE);
    result := TestProc(FALSE)
END BranchBugTest.