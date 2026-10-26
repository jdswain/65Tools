# em16 in Oberon

em16, the emulator of the 65C816, the Rockwell R65C02 and the L28's
R65C19 that the 65Tools test their programs on, ported from C++
(em16-c, now in git's history only) to Oberon, and of the Tang Nano 20K SoC of
`../../Verilog65C816/fpga` (`-fpga`, below). It builds `../bin/em16`, which the oc test
suites, `as/test816` and Business BASIC use.

    make            ../bin/em16
    make test       the disk controllers, DMA and the banked direct page

`-t` traces every instruction to standard error: where, the opcode, the
registers and the cycles so far. `-tfrom addr skip count` traces only
from the skip+1th time the instruction at addr (`0xFF00`, say) is reached,
for count instructions: one interrupt or a few, not a whole boot
(`../../OS16/tools/irqprof.py` profiles such a trace).

Oberon programs run on OS16, which boots on `-fpga` from a floppy as on
the board: em16 has no loader of its own for Oberon modules any more, nor
a heap for NEW. The tests of `../oc` and `../as/test816` and OS16's own
build a boot floppy with OS16's kernel image and the program
(`../../OS16/tools/mkfloppy.py`, `../../OS16/doc/OS16_MemoryManagement.md`).

The Oberon sources are compiled by the LLVM Oberon compiler of the oc
repository (`../../../oc/bin/oc`, or `make OC=...`), as `as` is.

## Licence

em16 is based on emu816, Copyright (C) 2016 Andrew John Jacobs, made
available under the Creative Commons Attribution-NonCommercial-ShareAlike
4.0 International licence (http://creativecommons.org/licenses/by-nc-sa/4.0/).
This port is a derivative of it and under the same licence.

## Modules

    Em16      command line, running, -fbdump, the statistics
    EmLoad    ELF loading and the run time traps (but on -fpga, where
              BRK goes through the vectors)
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
    EmSCC     the emulated Z85C30 SCC of rtl/scc_85c30.v
    EmADB     the ADB host, with a keyboard and a mouse
    EmBlit    the blitter
    EmHarte   -harte: the Harte single-step tests on EmCore

    and on both the default machine and the SoC:

    Em82077   the carrier's 82077AA floppy controller, two drives
    EmSCSI    the carrier's 53C80 SCSI controller and a disk at ID 0

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
em16-c's `emu816.cpp` (tools/gendispatch.py, both now in git's history).

## The same behaviour

The port kept what em16 did, and what its users read: every message
of the ELF loader, `cout`'s sticky `hex` (once `cout << hex` had been
written, later numbers on `cout`, such as the count in "Executed",
came out in hex), the trace format, the BRK traps, and the places where
em16 differs from the chip: TCD sets no flags, `JMP a` takes the
program bank from the data bank and `JMP (a)` sets it to 0, `PEI` pushes the word the
pointer points to, `TXS` with 8 bit index registers puts the stack in
page `sp_page`, `(d,S),Y` writes a line to standard output, `RTI` in
emulation mode does not force bits 4 and 5, a JMP to 0 in bank 0 stops.
These could be corrected now in both versions.

One addition: the default machine has the carrier board's disk
controllers at the SoC's addresses, the 82077AA at $0800 and the 53C80
at $0830; em16-c has the WD1793 at $0800, which `-wd1793` gives instead
(below), and RAM at $0830. The 82077AA's time there is the processor's
cycles, three of the SoC's to each (as if at 8.4 MHz). The L28 keeps its
WD1793 at $0640. Removed since: the loading of .816 modules (with -I,
the manifest at $0D00, the module table at $0E00), the heap behind
BRK #10, and the comparison with em16-c (test/compare.sh,
tools/cputest.py, tools/gendispatch.py and em16-c itself, in git's
history): OS16 loads modules, and its heap
is NEW's.

Left out, because nothing reached them: the S28 loader (`load` in
`main.cpp`, never called), the R6501 (constructed, but no address of
the memory map led to it), and the ST7586S and UC1608 LCDs (no longer
built).

Differences: the trace and standard error are written a line at a time
rather than piece by piece (the order is the same; it is many times
faster); `WDM 2` reads a character if one is waiting instead of blocking
on `cin`; the memory starts zeroed; the string table of an ELF file may
have 1 MB, its symbol table 200000 symbols.

## The SoC (-fpga)

    em16 -fpga [-bootrom rom.bin] [-font font.hex] [-video] [-fbdump ppm]
               [-disk0 img] [-disk1 img] [-wd1793] [-scsi img]
               [-adbkey code] [file ...]

`-fpga` emulates the SoC of `../../Verilog65C816/fpga` as its RTL
describes it (`rtl/soc.v` and the modules below it, and `fpga/README.md`)
rather than em16's default machine:

- the processor is `EmCore`, a translation of `cpu_65c816.v` state by
  state: its bus cycles, its idle cycles and its departures from the
  WDC chip are those of the core on the board, not EmCPU's. It passes
  the Harte tests as the core does (`em16 -harte dir [names]`: the
  same 5,080,011 pass, and the same MVN/MVP files fail). It has the
  core's banked direct page and stack too (`WDM #$B1` on, `WDM #$B0`
  off; docs/BankedDP.md in the Verilog repository), which
  `test/banked.sh` checks with the core's own test, banked.s;
- the map: 8 MB of SDRAM through the cache, the I/O block at
  $0200-$0FFF (palette, ADB, system control, external bus, video
  control, blitter, DMA; the external bus is eight slots of 16
  registers mirrored every 128 bytes, the floppy controller in slot 0,
  and the SCC answers at $0820-$082F in place of slot 2), the boot
  ROM until system control bit 0 is cleared: 8, 16 or 32K at $E000,
  $C000 or $8000, the smallest that holds the `-bootrom` image, which
  ends at $FFFF (as the Verilog repository's Makefile sizes it);
- the serial port, channel A of the SCC, on standard input and output;
- the SCC's baud-rate generators and their zero-count interrupt, as
  `rtl/scc_85c30.v` has them: OS16's clock tick, on channel B;
- the display: 640 x 480 in 16 colours at $70_0000, or 80 x 30 text
  (video control bit 0) drawn with the board's font, read at start from
  the Verilog repository's `fpga/rom/font_st8x16.hex` (or `-font`). The
  font comes from EmuTOS and is GPL v2, so it is read, not copied here;
- the blitter (`rtl/blitter.v`) as its test bench's reference model
  defines it, its 8x8 patterns included, its writes dropping the cache
  lines they touch;
- the ADB host with a keyboard and a mouse that the `-video` window
  feeds; `-adbkey code` (e.g. `0x2e`, M) holds a key down from power on,
  for a boot ROM that looks for one;
- the disk controllers of the carrier board that `docs/Hardware.md`
  describes, at the addresses it gives: an 82077AA at $0800 (slot 0)
  and the SCSI half of the Z85C80, a 53C80, at $0830 (slot 3), with
  their interrupts on the card `IRQ#` that bit 0 of $0340 reads (and the
  CPU's IRQ), and bit 0 of $0340 resetting them; below;
- the DMA engine (`rtl/dma.v`, `EmDMA.Mod`; docs/DMA.md in the Verilog
  repository), two channels at $0400 and $0410 between the memory and
  the 53C80 and the 82077AA; the chips' /DACK slots, 4 and 1 ($0840,
  $0810), reach them by pseudo-DMA;
- the tick timer (`rtl/timer.v`, `EmTimer.Mod`) at $0450, a period of
  RELOAD cycles and a 32-bit count of ticks, and the interrupt status
  and mask at $0440 and $0441, through which the timer, the two DMA
  channels, the cards' `IRQ#` and the SCC reach the CPU's IRQ;
- with `-wd1793`, the WD1793 card that OS16's old boot loader was
  written for at $0800 instead of the 82077AA, as before;
- a program ends with STP or a fetch from 00:0000.

Time is counted in the SoC's 25.2 MHz cycles, and each bus cycle of the
core takes what the board would take:

- boot ROM and I/O block 2 cycles, the external bus 14 (its Intel
  cycle on the 8.4 MHz timing, as the CPU sees it);
- a DMA byte 17 cycles; the engine's SDRAM traffic and its hold on the
  external bus are not counted against the CPU;
- SDRAM as the cache's state machine: a byte of the held word 1 cycle,
  another hit 3, a miss 18; a store is posted in 3 and holds the port
  for 10, so a store or a miss after it may wait;
- the display's line fetches (about 210 cycles of each 800 cycle line in
  graphics, 105 in text) and refresh (6 of every 190) take the port
  first, phased as on the board after the SDRAM's initialisation;
- the SCC 2340 cycles a character (115200 baud), each way;
  an SCC access 3 cycles;
- the blitter busy for a time fitted to the test bench's 409 timed blits
  (median error 6%); the pixels change when it finishes.

A test program's fetches, timed in the RTL simulation (`tb_soc`, the
SoC and pixel clocks equal as on the board), and in em16, stayed within
4 cycles over 3,000, across three waits for the display. Not modelled:
which SDRAM rows are open (a cycle or two on some misses), the
display's fetch arbitration beyond its fixed windows, and a typed
character arriving while one waits: on the board it overruns, here it
is held back, as if by flow control.

### Disks

On the default machine and under -fpga. Both controllers can be
polled, and under -fpga moved by DMA too (the default machine has no
engine). The comments at the top of `Em82077.Mod`, `EmSCSI.Mod` and
`EmDMA.Mod` list what they do and leave out.

- **Floppy**, `-disk0` and `-disk1`: 720K, 1.44M or 2.88M images, the
  sectors in the order track, side, sector. The 82077AA is in PC/AT
  mode. Set ND with SPECIFY for polled transfers (RQM while the FIFO
  has a byte, or room); without it the transfer is DMA, DRQ while the
  DOR's DMA gate is on. Either way a read's bytes arrive at the data
  rate, and one not taken before the 16-byte FIFO fills is an overrun
  (ST0 $40, ST1 $10). The data rate (CCR or
  DSR) must suit the disk, 500K for 1.44M and 250K for 720K. A
  transfer ends after the sector EOT names with ST0 $40, ST1 $80, as on
  a PC without TC, or normally (ST0 $00) when TC comes with a byte.
  Seeks take the step rate SPECIFY sets.
- **SCSI**, `-scsi`: one disk at ID 0, as large as its image, in 512
  byte blocks from block 0. The 53C80's registers are those of the 5380;
  the disk answers arbitration, selection with or without ATN, and the
  common commands of a SCSI-2 disk (INQUIRY, TEST UNIT READY, REQUEST
  SENSE, READ CAPACITY, READ and WRITE 6 and 10, MODE SENSE, ...), with
  UNIT ATTENTION after power on and a bus reset. DMA mode (mode bit 1,
  then a write to register 5, send, or 7, initiator receive) asks for
  each byte with DRQ while the phase matches; EOP sets End of DMA, and
  the target changing phase first interrupts.

`tools/mkdisk.sh` makes FAT images with the Mac's `hdiutil`, and opens
them in the Finder to copy files in and out, as the floppy images were:

    tools/mkdisk.sh create hd.img 5m file ...    a 5 MB FAT16 disk for -scsi
    tools/mkdisk.sh create fd.img 1440k file ... a 1.44M FAT12 floppy for -disk0
    tools/mkdisk.sh mount hd.img                 /Volumes/EM16
    tools/mkdisk.sh unmount hd.img               before em16 uses it again

The volume starts at block 0, with no partition map. The floppies' boot
sectors give their real geometry, which hdiutil does not write.

`test/disks.sh` runs a boot ROM, `test/disks.s`, that drives both by
polling (reset and SENSE INTERRUPT STATUS, SPECIFY, RECALIBRATE, SEEK,
READ and WRITE DATA, a wrong data rate, a wrong cylinder, READ ID;
arbitration, selection, IDENTIFY, the SCSI commands above, a check
condition and its sense, a selection nobody answers, a bus reset) and
compares what it prints with `test/disks.expected`. `test/dma.sh` does
the same by DMA, `test/dma.s` against `test/dma.expected`: floppy reads
and writes with TC, a read the engine never serves (an overrun), a
read by pseudo-DMA; SCSI reads and writes, a read shorter than the
count asked for (the phase changes, and COUNT says how much is left),
and a read by pseudo-DMA.

`fpga/rom`'s `blttest`, `fbtest`, `texttest` and `adbtest` behave as on
the board (`as -o X.mem`, the image made a binary for `-bootrom`;
their closing `bra halt` replaced by STP to end the run).

## Speed

The compiler does not optimise; the Makefile compiles the LLVM it
leaves beside each object again with `clang -O2`, which makes em16 three
times faster and about as fast as the C++ version (OS16's boot loader,
1.1 million cycles: 8.3 ms against 7.7 ms). Tracing is faster than
before, as above.

## Testing

`make test` runs `test/disks.sh`, a boot ROM (`test/disks.s`) that drives
both disk controllers by polling and compares what it prints with
`test/disks.expected`, `test/dma.sh`, the same by DMA, and `test/banked.sh`, the banked direct page and
stack of the board's 65C816. `test/pattern.sh` draws with the blitter's
patterns (`test/pattern.s`): odd left and right edges, copy, OR, XOR and
BIC, fill set as well, a transparent colour, and a PATTERN write while
busy; a model in the script, from the definition, checks every pixel. The
same ROM prints the same on the RTL's SoC simulation. The oc816 golden suite (`../oc`, make
test_self), `as/test816`, OS16's tests and Business BASIC's run on em16
-fpga.

The port found two faults of the Oberon compiler: two procedures of
the same name in one module are accepted, and a call from another
module can then reach the wrong one; and a string literal of more than
255 characters was cut short without a word (fixed: the limit is now
1023, and a longer one is an error).
