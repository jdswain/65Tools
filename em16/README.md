# em16 in Oberon

em16, the emulator of the 65C816, the Rockwell R65C02 and the L28's
R65C19 that the 65Tools test their programs on, ported from C++
(`../em16-c`) to Oberon, and of the Tang Nano 20K SoC of
`../../Verilog65C816/fpga` (`-fpga`, below). It builds `../bin/em16`, which the oc test
suites, `as/test816` and Business BASIC use; the C++ version builds
`../bin/em16-c` and is kept to compare with.

    make            ../bin/em16
    make compare    run both on the same programs (test/compare.sh)

The Oberon sources are compiled by the LLVM Oberon compiler of the oc
repository (`../../../oc/bin/oc`, or `make OC=...`), as `as` is.

## Licence

em16 is based on emu816, Copyright (C) 2016 Andrew John Jacobs, made
available under the Creative Commons Attribution-NonCommercial-ShareAlike
4.0 International licence (http://creativecommons.org/licenses/by-nc-sa/4.0/).
This port is a derivative of it and under the same licence.

## Modules

    Em16      command line, running, -fbdump, the statistics
    EmLoad    ELF and .816 loading, relocation, imports, the boot
              manifest at $0D00, the heap and the run time traps
    EmCPU     the processor: registers, addressing modes, operations,
              the three opcode tables, the trace (-t)
    EmMem     the memory map of the three machines
    EmUART    6551 ACIA                 EmVIA    6522 VIA with ADB
    EmFDC     WD1793 floppy disks       EmL28    the L28's ports, USART,
    EmVideo   SoC framebuffer, palette           banks, flash, keyboard
    EmLCD     RA8889 LCD controller
    EmHost    the host: output, the terminal, the clock, disk images
    EmSym     symbols, and the addresses of the trace

    and for the SoC (-fpga):

    EmSoC     its memory map, I/O block, boot ROM, time
    EmCore    its processor, cpu_65c816.v state for state
    EmSDRAM   the 8 MB, the cache, the SDRAM port's time
    EmACIA    the 6551 of rtl/acia_6551.v
    EmADB     the ADB host, with a keyboard and a mouse
    EmBlit    the blitter
    EmHarte   -harte: the Harte single-step tests on EmCore

What Oberon cannot reach is in C: `EmHost_rt.c` (terminal modes,
non-blocking standard input, signals, the clock, the disk image files),
`EmFont.c` (the LCD's character ROM, as data) and `EmCocoa.m` (the two
display windows). The procedures of `EmHost` without a body are weak
stubs that these define, as `ASH_rt.c` does for `as`. In the other
direction the windows read the devices' exported variables
(`EmVideo.mem`, `EmLCD.fb`, ...) by their symbols and pass keys and
the mouse to exported procedures; `-video` and `-console` run the CPU
(`Em16.CpuThread`) on a second thread, as before.

The opcode tables at the end of `EmCPU.Mod` were generated from
`em16-c/src/emu816.cpp` by `tools/gendispatch.py`.

## The same behaviour

The port keeps what em16 did, and what its users read: every message
of the loaders, `cout`'s sticky `hex` (once `cout << hex` had been
written, later numbers on `cout`, such as the count in "Executed",
came out in hex), the trace format, the BRK traps, and the places where
em16 differs from the chip: TCD sets no flags, `JMP a` takes the
program bank from the data bank and `JMP (a)` sets it to 0, `PEI` pushes the word the
pointer points to, `TXS` with 8 bit index registers puts the stack in
page `sp_page`, `(d,S),Y` writes a line to standard output, `RTI` in
emulation mode does not force bits 4 and 5, a JMP to 0 in bank 0 stops.
These could be corrected now in both versions.

Left out, because nothing reached them: the S28 loader (`load` in
`main.cpp`, never called), the R6501 (constructed, but no address of
the memory map led to it), and the ST7586S and UC1608 LCDs (no longer
built).

Differences: the trace and standard error are written a line at a time
rather than piece by piece (the order is the same; it is many times
faster); `WDM 2` reads a character if one is waiting instead of blocking
on `cin`; the memory starts zeroed; the string table of an ELF file may
have 1 MB, its symbol table 200000 symbols, a .816 module 64K of type
descriptors.

## The SoC (-fpga)

    em16 -fpga [-bootrom rom.bin] [-font font.hex] [-video] [-fbdump ppm] [file ...]

`-fpga` emulates the SoC of `../../Verilog65C816/fpga` as its RTL
describes it (`rtl/soc.v` and the modules below it, and `fpga/README.md`)
rather than em16's default machine:

- the processor is `EmCore`, a translation of `cpu_65c816.v` state by
  state: its bus cycles, its idle cycles and its departures from the
  WDC chip are those of the core on the board, not EmCPU's. It passes
  the Harte tests as the core does (`em16 -harte dir [names]`: the
  same 5,080,011 pass, and the same MVN/MVP files fail);
- the map: 8 MB of SDRAM through the cache, the I/O block at
  $0200-$0FFF (ACIA, palette, ADB, system control, external bus, video
  control, blitter; the floppy controller is card 0 of the external
  bus), the 8K boot ROM at $E000 until system control bit 0 is cleared;
- the display: 640 x 480 in 16 colours at $70_0000, or 80 x 30 text
  (video control bit 0) drawn with the board's font, read at start from
  the Verilog repository's `fpga/rom/font_st8x16.hex` (or `-font`). The
  font comes from EmuTOS and is GPL v2, so it is read, not copied here;
- the blitter (`rtl/blitter.v`) as its test bench's reference model
  defines it, its writes dropping the cache lines they touch;
- the ADB host with a keyboard and a mouse that the `-video` window
  feeds;
- a program ends with STP or a fetch from 00:0000.

Time is counted in the SoC's 25.2 MHz cycles, and each bus cycle of the
core takes what the board would take:

- boot ROM and I/O block 2 cycles, the external bus a cycle of its
  1 MHz PHI0 after waiting for its falling edge;
- SDRAM as the cache's state machine: a byte of the held word 1 cycle,
  another hit 3, a miss 18; a store is posted in 3 and holds the port
  for 10, so a store or a miss after it may wait;
- the display's line fetches (about 210 cycles of each 800 cycle line in
  graphics, 105 in text) and refresh (6 of every 190) take the port
  first, phased as on the board after the SDRAM's initialisation;
- the ACIA 2340 cycles a character (115200 baud), each way;
- the blitter busy for a time fitted to the test bench's 409 timed blits
  (median error 6%); the pixels change when it finishes.

A test program's fetches, timed in the RTL simulation (`tb_soc`, the
SoC and pixel clocks equal as on the board), and in em16, stayed within
4 cycles over 3,000, across three waits for the display. Not modelled:
which SDRAM rows are open (a cycle or two on some misses), the
display's fetch arbitration beyond its fixed windows, and a typed
character arriving while one waits: on the board it overruns, here it
is held back, as if by flow control.

`fpga/rom`'s `blttest`, `fbtest`, `texttest` and `adbtest` behave as on
the board (`as -o X.mem`, the image made an 8K binary for `-bootrom`;
their closing `bra halt` replaced by STP to end the run).

## Speed

The compiler does not optimise; the Makefile compiles the LLVM it
leaves beside each object again with `clang -O2`, which makes em16 three
times faster and about as fast as the C++ version (OS16's boot loader,
1.1 million cycles: 8.3 ms against 7.7 ms). Tracing is faster than
before, as above.

## Testing

`test/compare.sh` runs both versions and compares standard output
(without the timing lines), standard error, the traces and the files
they write:

- `tools/cputest.py` writes programs that execute every opcode of the
  65C816 in its five register width modes, of the R65C02 and of the
  R65C19, with varied registers, flags (decimal included), memory and
  direct page; their `-t` traces are compared, three seeds each;
- every compiled test program in `../oc/test`;
- OS16's boot loader reading a floppy image: trace and the image after;
- a boot ROM drawing into the framebuffer, with `-fbdump`;
- Business BASIC on the SoC (the output, not the time);
- the L28's USART, LCD and banked memory, the VIA's timer interrupts
  and ADB.

314 comparisons, all the same. The oc816 golden suite (146 pass,
2 skipped), `as/test816` and Business BASIC's tests pass with it.

The port found two faults of the Oberon compiler: two procedures of
the same name in one module are accepted, and a call from another
module can then reach the wrong one; and a long string literal is cut
short without a word (EmCore's mnemonics are assigned 64 at a time).
