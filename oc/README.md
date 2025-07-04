# Oberon Compiler Components in C

A C implementation of key Oberon-07 compiler components, translated from Niklaus Wirth's original Pascal/Oberon implementation.

## Components

1. **ORS (Scanner)** - Lexical analysis module
2. **ORB (Symbol Table)** - Symbol table management and type system
3. **ORP (Parser)** - Syntax analysis and semantic checking

## Project Structure

```
oberon-compiler/
├── include/        # Header files
│   ├── ORS.h      # Scanner interface
│   ├── ORB.h      # Symbol table interface
│   └── ORP.h      # Parser interface
├── src/           # Source files
│   ├── ORS.c      # Scanner implementation
│   ├── ORB.c      # Symbol table implementation
│   ├── ORP.c      # Parser implementation
│   ├── test_scanner.c  # Scanner test program
│   ├── test_orb.c      # Symbol table test program
│   └── test_orp.c      # Parser test program
├── obj/           # Object files (generated)
├── bin/           # Binary files (generated)
├── Makefile       # Build configuration
└── README.md      # This file
```

## Building

```bash
# Build all components
make

# Run all tests
make test

# Run individual tests
make test_scanner
make test_orb
make test_orp

# Clean build files
make clean

# Install (optional)
sudo make install
```

## Usage

### Scanner (ORS)

```bash
# Scan an Oberon source file
./bin/test_scanner input.Mod
```

### Symbol Table (ORB)

```bash
# Run symbol table tests
./bin/test_orb
```

### Parser (ORP)

```bash
# Parse and check an Oberon module
./bin/test_orp source.Mod [/s]

# Options:
#   /s  Force creation of new symbol file
```

## API Overview

### ORS Scanner API

```c
// Initialize keyword table (call once at startup)
void InitKeywords(void);

// Initialize scanner with file and starting position
void Init(FILE *file, long pos);

// Get next token
void Get(int *sym);

// Access token data
extern int32_t ival;      // Integer value
extern double rval;       // Real value
extern Ident id;          // Identifier string
extern char str[];        // String literal
extern int32_t slen;      // String length
```

### ORB Symbol Table API

```c
// Initialize symbol table
void ORB_Initialize(void);
void ORB_Init(void);

// Object management
void NewObj(ObjectPtr *obj, const char *id, int class);
ObjectPtr thisObj(void);
ObjectPtr thisimport(ObjectPtr mod);
ObjectPtr thisfield(TypePtr rec);

// Scope management
void OpenScope(void);
void CloseScope(void);

// Import/Export
void Import(char *modid, char *modid1);
void Export(const char *modid, bool *newSF, int32_t *key);
```

### ORP Parser API

```c
// Initialize parser
void ORP_Init(void);

// Compile a module
void Compile(const char *filename, bool forceNewSF);

// Main parsing function (called by Compile)
void Module(void);
```

## Status

Currently implemented:
- ✅ Complete scanner with all Oberon tokens
- ✅ Symbol table with import/export
- ✅ Parser with type checking and semantic analysis
- ⚠️  Code generator interface (stubs only)

The parser includes stub functions for the code generator (ORG module). To create a complete compiler, you would need to implement the ORG module for your target architecture.

## Example Oberon Module

```oberon
MODULE Example;
  CONST
    MaxSize = 100;
  
  TYPE
    Vector = ARRAY MaxSize OF REAL;
  
  VAR
    v: Vector;
    sum: REAL;
  
  PROCEDURE ComputeSum(VAR a: Vector; n: INTEGER): REAL;
    VAR i: INTEGER; s: REAL;
  BEGIN
    s := 0.0;
    FOR i := 0 TO n-1 DO
      s := s + a[i]
    END;
    RETURN s
  END ComputeSum;
  
BEGIN
  sum := ComputeSum(v, MaxSize)
END Example.
```

## Token Types

All lexical symbols are defined in `include/ORS.h` with the `_sym` suffix:
- `ident_sym` - Identifier
- `int_sym` - Integer literal
- `real_sym` - Real number literal
- `string_sym` - String literal
- `char_sym` - Character literal
- Keywords: `if_sym`, `while_sym`, `module_sym`, etc.
- Operators: `plus_sym`, `minus_sym`, `times_sym`, etc.
- Delimiters: `lparen_sym`, `rparen_sym`, `semicolon_sym`, etc.

## Example

```c
#include <stdio.h>
#include "ORS.h"

int main() {
    FILE *f = fopen("example.Mod", "r");
    int sym;
    
    InitKeywords();
    Init(f, 0);
    
    do {
        Get(&sym);
        printf("Token: %s\n", GetSymbolName(sym));
        
        if (sym == ident_sym) {
            printf("  Identifier: %s\n", id);
        } else if (sym == int_sym) {
            printf("  Integer: %d\n", ival);
        }
    } while (sym != eot_sym);
    
    fclose(f);
    return 0;
}
```

## Original Source

Based on the Oberon-07 scanner by Niklaus Wirth (1993/2017).
Translated to C while preserving the original structure and behavior.
