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

65C816 Memory Layout and WordSize:
The 65C816 compiler follows the same logical structure as the original Oberon RISC compiler but must handle different memory layout requirements:

- WordSize = 2 bytes (size of INTEGER)
- In original Oberon: WordSize is the same for pointers and integers (4 bytes each)
- In 65C816: More complex due to bank addressing
  - INTEGER = 1 WordSize (2 bytes)
  - Pointer = 2 * WordSize (4 bytes total: 2 bytes for address + 2 bytes for bank)
  - Array length = 1 WordSize (2 bytes)

65C816 addressing is based on 6502 with 2-byte pointers, but adds a bank byte for 24-bit addressing. We maintain WordSize as the fundamental unit and express pointers as 2 * WordSize (one word for bank, one word for actual pointer).

Parameter layouts should follow original Oberon logic but use 65C816 sizes:
- Regular parameters: 1 WordSize
- VAR parameters (pointers): 2 * WordSize  
- Open arrays: 2 * WordSize (address + length)
- VAR open arrays: 3 * WordSize (pointer + length)
