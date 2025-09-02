This project is written in C.
There is a Makefile for building.
The file structure is:
include/ - .h header files.
src/ - .c source files.
test/ - Oberon test cases.
Use bin/oc to compile oberon code. The resulting object file ends in .816 and is in the same directory as the source, normally test/
Use two spaces for indenting in C code.
This project is an oberon compiler for the 65C816 processor.
The files are:
ORS.c - scanner
ORP.c - parser
ORG.c - code generator
ORB.c - base, data structures
There is also cpu.c, codegen.c, and gen_816.c for generating code.
Each oberon module compiles to a file with .816 extension.
There is a disassembler for the 816 files, it is in bin/disasm.
The disassembler does not implement all 65C816 instructions yet, quite often we need to add instructions.
The emulator is in ../bin/em16. You need the command echo "" | ../bin/em16 test/module.816
The emulator has a -t trace option, this outputs an instruction trace.
The compiler is based on an oberon version, this is in oberon/. Often it is useful to refer to the source in there to see what needs to be implemented.
