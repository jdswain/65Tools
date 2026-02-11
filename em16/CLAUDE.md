# EM16 - 65C816 Emulator Project

## Overview
EM16 is a portable C++ emulator for the WDC 65C816 processor, used for testing compiled Oberon modules. The emulator includes comprehensive execution tracing capabilities and supports multiple file formats.

## Project Structure
- **Source**: `src/` directory contains C++ implementation files
- **Headers**: `include/` directory contains header files
- **Build**: Uses Makefile that depends on `BUILD_BASE` environment variable pointing to `..`
- **Target**: Builds to `../bin/em16`

## Build Requirements
- Environment variable `BUILD_BASE` must be set to `..`
- SDL2 development libraries (used for video/graphics)
- Standard C++ build tools (make, g++/clang++)
- Build command: `make` (from project directory)

## Usage
```bash
em16 [-t] ELF-file [additional-files...]
```

### Command Line Options
- `-t`: Enable execution trace output (very detailed processor state logging)
- `-?`: Show usage help

## Supported File Formats

### ELF Files
- Standard ELF format files from the assembler
- Supports multiple processor targets:
  - EM_816: 65C816 processor
  - EM_C02: 65C02 processor  
  - EM_02: 6502 processor
- Automatic processor configuration based on ELF machine type

### .816 Files (Oberon Modules)
- Simple loader for compiled Oberon modules
- Currently loads modules into bank 0
- **Planned Extensions** (from user context):
  - Make relocatable
  - Work outside bank 0
  - Link multiple modules

### Legacy S28 Files
- Motorola S-record format support (S1 and S2 records)

## Execution Trace (-t option)
When `-t` is specified, the emulator outputs detailed execution traces including:
- Program counter and current opcode
- Operand bytes (up to 3 bytes)
- Instruction mnemonic and effective address
- Complete processor state: registers (A, X, Y, SP, DP), processor flags
- Stack contents and direct page contents
- Symbol lookup for addresses (when debug info available)

**Usage Pattern**: Often redirect trace to file for investigation:
```bash
em16 -t program.elf > trace.txt
```

## Architecture Details
- **Memory**: 64KB RAM (no ROM)
- **Stack**: Page 0x0100 (typical 65xx configuration)
- **Processor**: Full 65C816 implementation with all addressing modes
- **Components**: UART (6551), Video, Memory management

## Key Source Files
- `src/main.cpp`: Entry point, file loaders, command line parsing
- `src/emu816.cpp`: Core 65C816 emulator implementation
- `src/wdc816.cpp`: WDC 65C816 specific processor logic
- `src/mem816.cpp`: Memory management system
- `include/emu816.h`: Main emulator interface and trace macros

## Module Loading (.816 files)
The `loadMod()` function in `src/main.cpp` handles Oberon module loading:
- Reads module name (null-terminated string)
- Loads module data into memory
- **Current Limitation**: Simple loader, not relocatable
- **Future Work**: Relocatable loading, bank switching, module linking

## Development Context
This emulator is part of a larger toolchain for Oberon development targeting 65C816:
- Related projects in sibling directories (`../oc/` for Oberon compiler)
- Used for testing compiled Oberon modules
- Part of a comprehensive 65xx development environment

## Testing Workflow
1. Compile Oberon modules using the compiler in `../oc/`
2. Load modules into em16 emulator
3. Use `-t` option to generate execution traces for debugging
4. Analyze trace output to verify correct compilation and execution

## Build System
- Uses shared build rules from `$(BUILD_BASE)/build/rules/`
- Links with libutil and SDL2
- Generates object files in `obj/` directory
- Final executable: `../bin/em16`