x Value Params
x Function return
x Functions
x Save/Restore Regs
x SProcs Get Put
x Byte, Bool, Char
x Type casts via assignment
x Unary Operations
x Binary operators for byte types
x cond and if
x Relational operators
x FOR
x Get GT working
x Tidy up PutChar
x WHILE
x REPEAT
x Var Params
 x Module level
 x Local level
  x Test for nested calls
x ORB constants
x REP and SEP management. Always Sep() when calling funcs. Use Rep() and Sep() in functions to only change when needed.
x Global and Local Array
x Open Array Param
x Bounds checking is disabled in Open Arrays. Fix this.
x Test Bounds checking on open array
x String
x Find out what RegI is and implement or remove
x INC()
x String copy
x Sized array param - not supported
x Test INTEGER array
x Record
x Signed INTEGER
x Type alias
x Open Array LEN() doesn't work 
x Test functions in expressions, does the call handle registers correctly.
x Shift ASL, LSR, ROL
x Bitwise AND, EOR, ORA

**Current**
Set - in, is, upto
StringRelation
Some load operations
DeRef Var and Par
Singleton
StoreStruct
CopyString test
VarParam two cases
StringParam?
Some call stuff
PACK/UNPACK
Copy
Abs/Odd/Floor/Float
Return of exit code

**Complex Types**
Pointers
Type CASE/TypeTest

**Memory and Environment**
Exported procedures and JSL
 Adjust local calls for exported procs
 Adjust stack calculations, including local VAR offsets
Static Base (SB), use loader fixup chain
Loader fixup chain for module procedures
Import
NEW
Interrupt procedures

**Later**
- mul, div, mod
Real
LONGINT (INTEGER is fine for most things, but LONGINT may be useful)
Add checks for branch out of range. Compile error.
Numeric CASE.
Change Trap to end in OsExit() call.
Enums

**Optimisation**
Maybe optimise out reads to registers, do reads directly from globals or locals?
Maybe optimise by looking back at the code to avoid duplicated effort?
The LE case in emitBranch is less efficient than it could be due to the need to only have one fixup.

**Status**
VAR array params don't set length correctly on stack.
Implement Modules next, so we can create a Math Module for signed maths.

