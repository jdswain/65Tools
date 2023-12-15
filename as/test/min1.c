/*
min1.c
 
This is the first development test file.

With this file we can develop these features:

1) global variables of type char
2) void function with no parameters
3) assignment statement

 */

//volatile int v; // C++ style comment
// __attribute__ ((dp)) int r0;

char q;
char jason;
int david;
unsigned long swain;

void space()
{
}

void alloc()
{
  return 2;
}

void main()
{
  short b;
  char x;
  // x = 2;
  // q = 10 + 2;
  // Not implemented yet: q = 10;
  if (1) 
    space();
  else
    alloc();

  main();
  return 7 * 2;
}

/* 

** V1 **

* Done
return statement
return literal
literal expression
local variable
function definition
function call
calculate literal expressions at compile time
address is not set in symbol table

* Bugs
address is not set in JSR

* ToDo
assign literal to variable. Local. Global.
assign a variable to a variable. Local. Global.
assign function return to variable. Local. Global. Register.
complete mathematical expressions for basic types. 
if statement
-- loc resolution
looping statements
complete datatypes
locations - func_set_loc
function parameters
pointers
arrays

* Linker
link multiple files
set org and relocate
symtab for each section

* Optimisations
Remove unreachable code
Common subexpression elimination
STZ when storing 0 (replaces LDA #00; STA $0000)
Use registers for locals, avoid stack frame

* Emulator
use MAME to execute code
write a loader that loads an executable

* Goal 1
Simple C compiler with char, short, int data types
No struct, array etc.
Single file.
No preprocessor

char *ptr = (char *)0xC012;
char c = *ptr;   -- MOV c, *ptr
*ptr = 0x00;     -- MOV *ptr, 0x00

LDX #$C012
LDA $0,X
STZ $C012

Optimisations
-------------

*/
