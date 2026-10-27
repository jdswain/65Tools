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
`.s28` `.s37` S-records, `.tim` MOS paper tape, `.mem` Verilog memory file,
`.816` Oberon module plus its `.smb` symbol file and a map (`name.map`:
each code label's offset in hex and its name, a line each, as `oc816 -m`
writes them, which OS16's `tools/uiprof.py` reads to name a profile's
samples). A listing is written beside the first source file
(`name.lst`). The exit status is 1 if there was an error; no output file is
written then.

    -I dir        search dir for include files and symbol files
    -D sym[=val]  define a symbol
    -legacy       write .816/.smb in the layouts of the C Oberon compiler
    -v            report the passes

### Oberon modules (.816)

The `text` section is the module's code and `bss` its variables, which the
loader allocates in bank 0 and zeroes (`data.w 0`, `fill n` reserve them).
A procedure is exported with `*` and declared to Oberon importers with
`.proc Name(INTEGER, VAR BYTE, ...): INTEGER`; `_init` is the module's body
(without one, an RTL appended to the code is). Parameters arrive in the
compiler's registers, R0 at `$02` upward, and a result goes back in R0
(`../oc/doc/DP.md`).

The types of a `.proc` are BYTE, BOOLEAN, CHAR, INTEGER, LONGINT, REAL,
SET, `ARRAY OF T` (open, for a parameter) and the types the module
declares with `.type`, which the symbol file describes as ORB does:

    .type Extended = ARRAY 5 OF INTEGER
    .type Decimal = RECORD
        sgn, exp: INTEGER
        sig: ARRAY 29 OF CHAR
    END
    .type Halt = PROCEDURE (INTEGER, INTEGER)
    .proc Num2Dec(DecForm, Extended, VAR Decimal)
    .proc SetHaltVector(Halt)

A record's fields are laid out as oc816 lays them out (one larger than a
byte at an even offset), separated by commas or lines; each record gets a
type descriptor after the variables, as ORG makes them, so that an
importer can pass its tag. An array or record value parameter is passed
by reference, as ORP passes it. A procedure type's formals are written as
a `.proc`'s; its value is 4 bytes, the address and the bank, in two
registers. A name exported with `*` whose value is a
number, not an address (`Inexact* = $10`), is a constant of the module,
INTEGER or, if it does not fit, LONGINT.

Addresses in a module are relocated by the loader (OS16's ModuleManager
and tools/mklink.py): a label in `text` or `bss` is relative to the
module's code or data, and stays so plus or minus a number; the difference
of two is a number. Such an address may be an absolute operand (`lda
count`, `lda table,x`, `jmp (jtab,x)`), a 16-bit immediate (`ldx #arr`),
a long operand (`lda.l table`, `jml label`; a variable's bank is 0), a
`data.w` or `data.l`, or the target of a branch, JSR, JSL or PER; never a
direct page or 8-bit operand, and `<`, `>`, `^` and other operators make
it a number the loader cannot relocate, which is an error where it is
emitted. A code address read as data needs the code's data bank (`phk`
`plb`) or a long operand. The relocation entries mark these in their high
word: $4000 a data word, $2000 a code word in its bank, $1000 a 24-bit
code address, each of the bytes at the entry's offset.

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
- `.mem` is new: a memory file for Verilog's `$readmemh`, one byte per
  value, from the lowest address of the program to the highest with `$FF`
  between the runs of code. It is read into an array that starts at 0
  (`reg [7:0] rom [0:8191]`), so the program's lowest address must be the
  base of the ROM; a comment on the first line gives the range. There are
  no `@address` lines: one counts from the start of the Verilog array, and
  Gowin's synthesis truncates it to the width of the data.

Language:

- A `section` directive inside an `if` block that is false no longer ends the
  skipping: the rest of the block is skipped, or assembled, in the new section
  as the condition says. The directive itself is not conditional, because the
  text of each section is collected when the source is read: what follows it
  belongs to the section it names, also after the block.
- `//` and `/* */` comments, which the test sources use.
- `end` ends the source only on a line of its own; elsewhere it is a name
  (`operators.s` has a label `end`).
- Names after a `.` may be spelled like a keyword (`Out.Char`, `.loop`).
- A label may be spelled like a mnemonic, a directive, `DIV` or `MOD` when
  `*` or `:` follows it (`Add*:`, `Long:`), so that an Oberon procedure can
  have such a name; it is referred to as `Module.Add` by an importer.
- `.type` and exported constants, for Oberon importers (above).
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
and `Out` on the ACIA.

The sources keep to what both compilers accept: plain Oberon-07 with
`LONGINT`, no methods, no array constants. Addresses and values are
`LONGINT` (`INTEGER` is 16 bits there) and bytes are extracted with `DIV`
and `MOD`. Source text is not kept in memory for the listing but re-read
from the file. Two things are shaped by the target:

- A call cannot have more parameters than fit the 15 words of the
  register stack (`ASL.Text` and `ASL.Line` are two calls for that
  reason).
- The processor tables in `ASC` are text, decoded at start-up; as
  procedure calls they needed 1603 relocations, more than loaders took.

Both need `oc816` and em16 as of October 2026: earlier ones lack
`LONGINT` arithmetic, working `ASSERT`, relations between conditions,
procedure variables for procedures that are not exported, and a stack
clear of the floppy controller.

What a port to OS16 still needs: its `Files` has `Read`/`Write` on bytes
instead of `ReadByte`/`WriteByte` and positions are 16 bit, and `Env` and
`ASH.Exit` need equivalents. Under em16 the heap is what is left of bank
0, which is enough for a source of a few dozen lines; anything real needs
the OS16 heap manager.

Limits of the LLVM compiler that also shaped the code: constant
expressions are not folded in declarations, `CASE` needs a simple
variable, and procedures take at most 8 parameters.
