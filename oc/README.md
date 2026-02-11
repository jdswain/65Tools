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
make -f Makefile.macos    # macOS
make                      # Linux
```

To run a compiled module:

```bash
echo "" | ../bin/em16 test/Hello.816
```

For multi-module programs, list dependencies before the main module:

```bash
echo "" | ../bin/em16 test/Out.816 test/MyProgram.816
```

The `-t` flag enables an instruction trace for debugging.

## Tests

The test suite is organized into levels (L0-L12), each covering a set of
language features. See `test/TEST_PLAN.md` for the full breakdown.

```bash
# Run all tests (compilation + L0 emulator tests)
make test

# Run just compilation tests (no emulator needed)
make test_compile

# Run a specific level
make test_level0    # Legacy / integration tests
make test_level1    # Foundations (arithmetic, control flow, procedures)
make test_level2    # Arrays, strings, records
make test_level3    # Record operations
make test_level4    # Pointers and dynamic allocation
make test_level5    # SET type
make test_level6    # CASE statements
make test_level7    # Standard procedures (INC, DEC, ABS, ODD, LEN, etc.)
make test_level8    # REAL arithmetic
make test_level9    # Module system (imports, exports)
make test_level10   # SYSTEM module (PUT, GET, ADR, BIT, etc.)
make test_level11   # Edge cases and stress tests
make test_level12   # Negative tests (compiler error detection)
```

All levels except `test_compile` and `test_level12` require the emulator.

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
