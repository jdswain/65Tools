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
x ! instead of ~ crashes the compiler.
x BresenhamTest now works,. Debugged many issues.
x StringParam?
x VAR array params don't set length correctly on stack.
x Adjust local calls for exported procs
x Import
x Copy (string?)
x CopyString test
x Exported procedures and JSL

**Bugs**
In StringTest the last PutChar doesn't SEP when loading the value

**Current**
1. Set - in, is, upto
2. StringRelation
3. Some load operations
4. DeRef Var and Par
5. Singleton
6. StoreStruct
7. VarParam two cases
8. Some call stuff
9. PACK/UNPACK
10. Abs/Odd/Floor
11. Pointers
12. Type CASE/TypeTest
13. NEW
14. Interrupt Procedures

**Memory and Environment**
Relocate module code fixorgP
Relocate module data fixorgD
Fixups for type descriptors fixorgT
Load time module linking
- Module PROCEDURES
- Module Data
What is static base for, do we need it?


**Later**
- mul, div, mod
Real, Float()
LONGINT (INTEGER is fine for most things, but LONGINT may be useful)
Add checks for branch out of range. Compile error.
Numeric CASE.
Change Trap to end in OsExit() call.
Enums
Consider adding newline as a command seperator so ; are not needed.
Return of exit code

**Optimisation**
Maybe optimise out reads to registers, do reads directly from globals or locals?
Maybe optimise by looking back at the code to avoid duplicated effort?
The LE case in emitBranch is less efficient than it could be due to the need to only have one fixup, this could use the fixup chain.

**Status**


