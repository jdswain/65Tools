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
xVar Params
 x Module level
 x Local level
  x Test for nested calls
x ORB constants

Signed INTEGER
mul, div, mod

* Complex Types

Pointer arrow period
Array
String
Set - in, is, upto
Record
Real
Type definition

* Memory

Exported procedures and JSL
 Adjust local calls for exported procs
 Adjust stack calculations, including local VAR offsets
Static Base (SB), use loader fixup chain
Loader fixup chain for module procedures

* Control flow

Type CASE

* Environment

Import
SProc's
Interrupt procedures

-- Tidy

--
Test framework, might require module linking

-- Later
LONGINT
Need to add checks for branch out of range.
Maybe optimise out reads to registers, do reads directly from globals or locals?
Maybe optimise by looking back at the code to avoid duplicated effort?
The LE case in emitBranch is less efficient than it could be due to the need to only have one fixup.
STARTED: REP and SEP management. Always Sep() when calling funcs. Use Rep() and Sep() in functions to only change when needed.
Numeric CASE.

-- Local var params
item->a = 3
r0 := nothing
loadAddr(item->a + our stack frame + 2)

3,s

tsa
sec
sbc #3
sta rn

phb
lda #00
pha
plb
lda (r0)
plb
sta rx

This should be working with local vars providing DBR is 00. 
