# as — 65xx assembler in Oberon

An assembler for the MOS 6502, WDC 65C02 and 65C816, and the Rockwell
R65C02, R6501Q and C19. It is a port to Oberon of the C assembler in
`../as-c` (with the parts of `../shared` it used), restructured after the
Oberon compiler it is built with.

## Building

    make            # -> ../bin/as
    make test       # regression tests in test/
    make test816    # the assembler compiled with oc816, run under em16
    make OC=/path/to/oc/bin/oc

It is compiled by the LLVM Oberon compiler of the `oc` repository
(`../../../oc/bin/oc`) and linked with that compiler's POSIX runtime
(`Files`, `Out`, `Env`). The compiler writes its artifacts beside the
source, so the sources are copied to `obj/` and compiled there.

## Usage

    as [options] -o outfile infile ...

The extension of the output file selects the format: none = ELF
executable, `.o` ELF object, `.bin` binary, `.hex` Intel hex, `.s19`
`.s28` `.s37` S-records, `.tim` MOS paper tape, `.816` Oberon module plus
its `.smb` symbol file. A listing is written beside the first source file
(`name.lst`). The exit status is 1 if there was an error; no output file is
written then.

    -I dir        search dir for include files and symbol files
    -D sym[=val]  define a symbol
    -legacy       write .816/.smb in the layouts of the C Oberon compiler
    -v            report the passes

## Modules

| Module | Role | From |
|--------|------|------|
| `AS`  | command line, control | `as.c` |
| `ASP` | parser: source to operations | `parser.c` |
| `ASI` | interpreter: runs the operations in several passes | `interp.c`, `as.c` |
| `ASG` | code generator: sections, addressing modes, instruction formats | `codegen.c`, `elf_file.c` |
| `ASC` | processor tables: mnemonics, modes, encodings (as text rows) | `gen_*.c`, `cpu.c` |
| `ASB` | base: values, symbol table, symbol file import | `value.c`, `as.c` |
| `ASS` | scanner, source files | `scanner.c`, `buffered_file.c` |
| `ASL` | listing | `interp.c`, `as.c` |
| `ASO` | output formats | `elf_file.c` |
| `ASH` | host interface: console, exit status, path names | — |

The names follow the compiler's ORS/ORB/ORG/ORP. As there, the scanner
delivers symbols through `Get` and reports errors through `Mark`, the
symbol table has a universe of predefined names below the program's scope,
and symbol files are read the way `ORB.Import` reads them.

The syntax accepted is given in EBNF at the head of `ASP.Mod`.

## How it works

The parser does not generate code. It translates the source into
operations for a stack machine (push a value, apply an operator, define a
label, emit an instruction). `ASI` runs that program repeatedly; a forward
reference takes the value of the previous pass, and passes repeat until no
label moves. A final pass then reports errors and writes the listing.

## Differences from the C assembler

Output for sources both accept is byte-identical, except as listed.

Formats, brought in line with the current compiler and loaders:

- `.smb` files are written in symbol file version 6 (`ORB.Mod` of `oc816`);
  both version 1 and 6 are read. `-legacy` writes version 1.
- `.816` files are written in layout version 2 (with the method table
  fixup section the OS16 loader expects), carry the key of the symbol file
  rather than a hash of the name, and list only parameterless procedures
  as commands.
- In `.smb` files value parameters have class `Var` and `VAR` parameters
  class `Par`; the C version wrote `Const` and `Var`.
- ELF: `e_shstrndx` is 1 (em16 reads it), section offsets are set in
  object files, bss sections have a size, and an executable has one
  program header per run of code, so a section with several `org`s loads
  at all of them. Paper tape gets the same per-run addresses.
- Intel hex and S-records are implemented (they were empty stubs).

Language:

- `//` and `/* */` comments, which the test sources use.
- `end` ends the source only on a line of its own; elsewhere it is a name
  (`operators.s` has a label `end`).
- Names after a `.` may be spelled like a keyword (`Out.Char`, `.loop`).
- `dpage` is honoured: an address in the page it points to is assembled
  direct (`816.s` expects this).
- `(addr)` and `[addr]` become direct page forms when they fit;
  previously `ora ($10)` and `lda [$10]` were rejected on the 65C816.
- `.l` selects long addressing for a plain address; `.b`/`.w` select the
  size of an immediate.
- Macros work: parameters and labels are local to each call.
- `if`/`else if`/`else` nest correctly, also inside a branch not taken.
- `{ }` is a block with local symbols.
- Added: `+= -= *= /= %= &= |= <<= >>=`, `&&`, `||`, `~`, unary minus on a
  factor, `\xhh` in strings, `align`, `long`, `float`, real numbers,
  `errorif cond, text`, string concatenation with `+`.
- `fill n` without a value fills with zeros; `fill.w`/`fill.l` fill words
  and longs.

Errors that used to pass silently:

- undefined symbols, duplicate labels, redefinition of a `let` constant,
  malformed operands, unknown characters, division by zero, an unknown
  `cpu`, branches out of range (reported once, with the right line).
- An instruction with an addressing mode it lacks is always reported
  (`lda` used to be dropped silently).

Encoding fixes:

- `stx dp,Y` and `stz dp,X` are two bytes, not three.
- A branch to address 0 is no longer dropped.
- BRA/BRL promotion tests the real offset (it was off by one).
- `mvn`/`mvp` accept bank numbers as well as addresses.
- `<` in expressions compared with `<=`; a leading minus negated the
  whole sum instead of the first term.

## On the 65C816

`make test816` compiles the same sources with `oc816`, loads them into
em16 and has the emulated assembler assemble `test816/sample.s`; its
output file and listing must equal the host's. The run uses a small
runtime in `test816/`: files held in memory, arguments set by a module,
`Out` on the ACIA, and `Stack.s`, which moves the stack out of em16's
floppy controller window before anything else runs.

The sources keep to what both compilers accept: plain Oberon-07 with
`LONGINT`, no methods, no array constants. Addresses and values are
`LONGINT` (`INTEGER` is 16 bits there) and bytes are extracted with `DIV`
and `MOD`. Source text is not kept in memory for the listing but re-read
from the file. Some of the code is shaped by what `oc816` cannot do yet:

- `ASSERT` traps when its condition holds, so there is none.
- Two conditions cannot be compared with `=` or `#`.
- Procedure variables take exported procedures only (`ASP.Expression`,
  `ASP.Statement`).
- A call cannot have more parameters than fit the register stack
  (`ASL.Text` and `ASL.Line` are two calls for that reason).
- The loaders accept fewer than 1024 relocations a module, and every
  call is one; the processor tables in `ASC` are therefore text.

What a port to OS16 still needs: its `Files` has `Read`/`Write` on bytes
instead of `ReadByte`/`WriteByte` and positions are 16 bit, and `Env` and
`ASH.Exit` need equivalents. Under em16 the heap is what is left of bank
0, which is enough for a source of a few dozen lines; anything real needs
the OS16 heap manager.

Limits of the LLVM compiler that also shaped the code: constant
expressions are not folded in declarations, `CASE` needs a simple
variable, procedures take at most 8 parameters, and an exported record
must not have a field of a private recursive pointer type (`oc816` shares
that last one).
