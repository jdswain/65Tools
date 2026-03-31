# Building em16

## Prerequisites

- macOS: Xcode command-line tools (`xcode-select --install`)
- Linux: `g++`, `libsdl2-dev`, `libutil-dev`
- The shared library `../shared/obj/lib65.a` must be built first

## Building the shared library

    cd ../shared
    BUILD_BASE=.. make release

## Building em16

From the `em16/` directory:

    BUILD_BASE=.. make release

This produces `../bin/em16`.

Other targets:

    BUILD_BASE=.. make debug      # debug build -> ../bin/em16d
    BUILD_BASE=.. make build      # both debug and release
    BUILD_BASE=.. make clean      # remove obj/ and binaries

## How BUILD_BASE works

The build system lives in `../build/` (relative to em16). `BUILD_BASE` must
point to the 65Tools root directory. From em16 that is `..`.

The build system auto-detects the platform via `uname` and includes the
matching config file:

    build/config/Darwin    # macOS: clang/clang++, Cocoa framework
    build/config/Linux     # Linux: gcc/g++, SDL2, -lutil

## Platform differences

- **macOS**: Video uses Cocoa (`src/Video.mm`, Objective-C++). Linked with
  `-framework Cocoa`.
- **Linux**: Video uses SDL2 (`src/Video.cpp`). Linked with `-lutil` and
  SDL2 libraries.

## Build system files

    build/config/Darwin      # macOS tool and flag definitions
    build/config/Linux       # Linux tool and flag definitions
    build/rules/global       # Requires BUILD_BASE, detects OS, sets paths
    build/rules/compile      # Pattern rules for .c, .cpp, .mm files
    build/rules/exec         # Linking rules, build/clean/run targets

## Source files

    src/emu816.cpp           # CPU emulator core
    src/wdc816.cpp           # WDC 65C816 base
    src/mem816.cpp           # Memory mapping
    src/UART_6551.cpp        # 6551 UART (stdin/stdout, raw terminal mode)
    src/R6501.cpp            # R6501 on-chip UART
    src/WD1793.cpp           # WD1793 floppy disk controller
    src/VIA_6522.cpp         # 6522 VIA
    src/ADB_Controller.cpp   # ADB keyboard controller
    src/Video.mm             # Cocoa video display (macOS)
    src/memory.cpp           # Memory/ROM loading
    src/main.cpp             # Entry point, argument parsing

## Rebuilding after source changes

Only modified files are recompiled. To force a full rebuild:

    BUILD_BASE=.. make clean && BUILD_BASE=.. make release
