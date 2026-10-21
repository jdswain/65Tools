# OC - Oberon Compiler for 65C816

An Oberon-07 compiler targeting the WDC 65C816 processor. Based on Niklaus Wirth's
original Oberon RISC compiler, translated to C and retargeted for the 65C816
architecture.

The compiler implements the full Oberon-07 language: integers, reals (software
floating point), booleans, characters, bytes, arrays, records, pointers, sets,
procedures, and a module system with separate compilation.

## Building

Requires GCC (or any C99 compiler) and make.

```bash
make
```

This produces:

- `bin/oc` - the Oberon compiler
- `bin/disasm` - disassembler for `.816` object files

## Usage

```bash
# Compile a module
bin/oc test/Hello.Mod

# Compile a library module (generates .smb symbol file for importers)
bin/oc test/Out.Mod /s

# Disassemble the output
bin/disasm test/Hello.816
```

The compiler reads a `.Mod` source file and produces a `.816` object file and
a `.smb` symbol file in the same directory as the source.

## Emulator

The test suite requires the `em16` 65C816 emulator, expected at `../bin/em16`
relative to this directory. To build it:

```bash
cd ../em16
make
```

em16 is written in Oberon and needs the LLVM Oberon compiler (`../../../oc`).

Compiled modules run on OS16 (`../../OS16`), booted under `em16 -fpga`
from a floppy that holds OS16's kernel, the program and the modules it
imports, and RUN.TXT naming it (`../../OS16/tools/mkfloppy.py`): em16 has
no loader of its own for them. `test/run_self_tests.sh` does this for each
test. The `-t` flag of em16 enables an instruction trace for debugging.

## Tests

The test suite is organized into levels (L0-L18), each covering a set of
language features. See `test/TEST_PLAN.md` for the full breakdown.

```bash
# Run all tests: this compiler's compilation tests, then oc816's goldens
make test

# Run just this compiler's compilation tests
make test_compile

# Run oc816's goldens on OS16 (build OS16 first: cd ../../OS16 && make);
# give levels to run only those
make test_self
bash test/run_self_tests.sh L4 L9
```

This C compiler's own programs no longer run: its NEW is `BRK #10`, which
em16 answered from a heap of its own, and that heap and em16's module
loader are gone; NEW is OS16's HeapManager's.

## Project Structure

```
oc/
  src/           Source files
    ORS.c          Scanner (lexical analysis)
    ORP.c          Parser (syntax and semantic analysis)
    ORG.c          Code generator (65C816 target)
    ORB.c          Symbol table and type system
    codegen.c      Machine code emission
    cpu.c          65C816 instruction encoding
    gen_816.c      65C816-specific code patterns
    Files.c        File I/O abstraction
    Texts.c        Text/logging support
    disasm.c       Disassembler
  include/       Header files
  test/          Oberon test modules and expected output
  oberon/        Original Oberon source (reference)
```

## License

Copyright (C) 2024-2026 Jason Swain

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

See [LICENSE](LICENSE) for the full text.
