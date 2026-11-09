# em16 in Oberon

em16, the emulator of the 65C816, the Rockwell R65C02 and the L28's
R65C19 that the 65Tools test their programs on, ported from C++
(em16-c, now in git's history only) to Oberon, and of the Tang Nano 20K SoC of
`../../Verilog65C816/fpga` (`-fpga`, below). It builds `../bin/em16`, which the oc test
suites, `as/test816` and Business BASIC use.

    make            ../bin/em16
    make test       the disk controllers, DMA and the banked direct page

`-t` traces every instruction to standard error: where, the opcode, the
registers and the cycles so far (under `-fpga`, the opcode the core's
instruction queue holds and the cycle it is taken in). `-tfrom addr skip
count` traces only from the skip+1th time the instruction at addr
(`0xFF00`, say) is reached, for count instructions: one interrupt or a
few, not a whole boot (`../../OS16/tools/irqprof.py` profiles such a
trace).

`-prof file cycles` (with `-fpga`) writes a sample to file each so many
cycles: the core's PC (PBR:PC) and the time in thousands of cycles, two
little-endian words; `../../OS16/tools/uiprof.py` names the samples by
procedure, from the modules' bases the guest prints and the maps `oc816
-m` and `as` write (OS16's `make prof-ui`).

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
    EmCore    its processor, cpu_65c816.v state for state, cycle for cycle
    EmSDRAM   the 8 MB, the cache, the SDRAM port's time
    EmSCC     the emulated Z85C30 SCC of rtl/scc_85c30.v
    EmADB     the ADB host, with a keyboard and a mouse
    EmBlit    the blitter
    EmHarte   -harte: the Harte single-step tests on EmCore

    and on both the default machine and the SoC:

    Em82077   the carrier's 82077AA floppy controller, two drives
    EmSCSI    the carrier's 53C80 SCSI controller and a disk at ID 0

    and on the SoC's carrier:

    EmEth     the ENC424J600 Ethernet controller, on -net's network
    EmRTC     the rev B's DS12C887 real-time clock (-rtc, -rtctime)

What Oberon cannot reach is in C: `EmNet_rt.c` (the network: vmnet
and UDP), `EmHost_rt.c` (terminal modes,
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

    em16 -fpga [-sysclk hz] [-smc] [-nodisplay] [-bootrom rom.bin] [-font font.hex] [-video] [-fbdump ppm] [-prof file cycles]
               [-disk0 img] [-disk1 img] [-wd1793] [-scsi img] [-sd img]
               [-net vmnet|vmnet-host|vmnet-bridged:IF|udp:LPORT:RPORT[:HOST]]
               [-mac aa:bb:cc:dd:ee:ff] [-rtc file] [-rtctime YYYYMMDDhhmmss] [-nortc]
               [-adbkey code] [-adbmouse dx dy] [file ...]

`-fpga` emulates the SoC of `../../Verilog65C816/fpga` as its RTL
describes it (`rtl/soc.v` and the modules below it, and `fpga/README.md`)
rather than em16's default machine:

- the processor is `EmCore`, a translation of `cpu_65c816.v` state by
  state and cycle by cycle: its 8-byte instruction queue, the opcode
  taken from it in a cycle and all the operand bytes in the next, a
  read's and an implied opcode's execute in the next opcode's cycle, a
  push's setup cycle, its bus cycles, its idle cycles and its departures
  from the WDC chip are those of the core on the board, not EmCPU's. It
  passes the Harte tests as the core does (`em16 -harte dir [names]`:
  with the vectors of 2026-10-31, 5,079,989 pass, file for file as
  `tb_harte` has it, MVN/MVP's counts included, and the same files
  fail: the block moves, one SBC and JSR (a,X) at $0100 in emulation
  mode). It has the
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
  defines it, its 8x8 patterns and 1-bit expansion included, its writes dropping the cache
  lines they touch;
- the ADB host with a keyboard and a mouse that the `-video` window
  feeds. A click in the window captures the mouse, as a virtual
  machine's does (the click is not the guest's): the host's arrow is
  hidden and held in the window, and the mouse's moves, the device's
  own before macOS's acceleration (the guest accelerates, as for an
  ADB mouse), go to the guest, a move beyond the 7 bits of a Talk in
  the next. Control-Command lets the mouse go, as does the window going
  behind another, closing, or the guest stopping; the title says which;
- with `-video`, real time once the guest reads its keyboard and
  mouse: em16 runs some 1.8 times the board's speed (70 million of its
  cycles a second), flat out through a boot; when the guest makes 200 ADB transactions in a second (OS16's
  InputManager makes 400, the boot ROM 100), each millisecond of the
  clock is kept in step with the host's from then on, so a key's repeat
  and a double click take the person's time. Without `-video` it is all
  flat out; `-adbkey code` (e.g. `0x2e`, M) holds a key down from
  power on, for a boot ROM that looks for one, and `-adbmouse dx dy`
  moves the mouse from power on (OS16's UITest checks its pointer with
  it);
- the disk controllers of the carrier board that `docs/Hardware.md`
  describes, at the addresses it gives: an 82077AA at $0800 (slot 0)
  and the SCSI half of the Z85C80, a 53C80, at $0830 (slot 3), with
  their interrupts on the card `IRQ#` that bit 0 of $0340 reads (and the
  CPU's IRQ), and bit 0 of $0340 resetting them; below;
- the DMA engine (`rtl/dma.v`, `EmDMA.Mod`; docs/DMA.md in the Verilog
  repository), three channels at $0400, $0410 and $0420 between the
  memory and the 53C80, the 82077AA and the ENC424J600; the first two
  chips' /DACK slots, 4 and 1 ($0840, $0810), reach them by pseudo-DMA;
  channel 2 runs unpaced on the Ethernet chip's data port ($0851), at the
  window software latched, with DONE on ISTAT bit 6;
- the tick timer (`rtl/timer.v`, `EmTimer.Mod`) at $0450, a period of
  RELOAD counts of 25.2 MHz at any system clock (a phase accumulator, as
  the RTL's) and a 32-bit count of ticks, and the interrupt status
  and mask at $0440 and $0441, through which the timer, the two DMA
  channels, the cards' `IRQ#`, the SCC and the power key reach the CPU's
  IRQ;
- soft power and the power LED (`rtl/power.v`, `EmPower.Mod`) at $0480:
  STATUS (the key, PRESSED, the off burst), CONTROL (the LED, BLINK, IE,
  which puts PRESSED on ISTAT bit 5) and OFF ($A5 turns the supply off:
  em16 ends 50 ms later with "the supply turned off"). F12 in the window
  is the power key, which the keyboard also sends over ADB ($7F); held 4
  seconds it turns the supply off;
- the 65-16 rev B's real-time clock, a DS12C887 (`EmRTC.Mod`), on the
  external bus's select 7: `$0870` written sets the register's index,
  `$0871` reads and writes the register, as the PC AT's ports 70h and
  71h; its /IRQ is one of the cards' IRQ#. The time, the alarms, UIP,
  SET, BCD or binary, 12 or 24 hours, the century byte at 32h, the
  periodic, alarm and update interrupts and the NV RAM, as the datasheet
  has them; a reset clears the enables and the flags. Its seconds are the
  SoC's (so they agree with the tick timer, paced or not), from the
  host's time in UTC at start-up, binary and 24-hour, as OS16 keeps it;
  `-rtctime YYYYMMDDhhmmss` starts it at that time instead (a test's);
  `-rtc file` keeps the chip in file, written after each register
  write, its time carried on by the host's while em16 was not running;
  a file not there yet is a new module, its oscillator off; `-nortc`
  leaves the chip out, as on a rev A board or an empty socket: a read
  there gets the last byte the card bus held, as the data lines have no
  pull-ups (OS16's tests boot so, for files without dates); the last of
  the three wins;
- with `-wd1793`, the WD1793 card that OS16's old boot loader was
  written for at $0800 instead of the 82077AA, as before;
- a program ends with STP or a fetch from 00:0000.

Time is counted in the SoC's system clock, the board's 40.5 MHz
(`top_tang20k.v`), or `-sysclk hz`'s (25.2 MHz is the RTL simulation's,
`tb_soc`'s default). The devices take their times from it as the RTL
does from `SYS_HZ`: the external bus, the DMA byte, the SCC's character,
ADB's microsecond, the SD divider's reset value, the SDRAM's
initialisation and refresh, the display's line, the tick timer's counts.
The core runs a clock at a time, as the RTL's does (Verilog65C816
0fab85c, f0dd5e8, afc158f): its instruction queue fills in the cycles it
is off the bus, a state that uses the bus waits for a fill in flight,
and each bus cycle takes what the board would take:

- boot ROM and I/O block 2 cycles (a queue fill from the 32-bit boot
  ROM brings its word in 2), the external bus 3T + H + 4, T and H the
  bridge's bus clock and edge gap in system clocks (21 at 40.5 MHz, 14
  at 25.2: its Intel cycle on the 8.4 MHz timing, as the CPU sees it);
  while bit 0 of $0340 holds the cards in reset, 2, reading $FF;
- the emulated SCC 2 cycles, 3 straight after another access to it; its
  transmitter's buffer and shift register as `scc_85c30.v`'s, ten bit
  times a character (115200 baud), each way;
- a DMA byte 3T + H + 5 + DRQ_HOLD cycles (25 at 40.5 MHz, 17 at 25.2);
  the engine's SDRAM traffic and its hold on the external bus are not
  counted against the CPU;
- SDRAM as the cache's state machine (`cache.v`, f0dd5e8) and the
  controller's (`sdram_burst.v`): a data read in the held word 1 cycle,
  a hit 2, a miss once the write buffer is empty, its burst 3 cycles
  before the answer (16 with the port free and the row open); a queue
  fill is a read that leaves the held word alone; a store goes into the
  4-word write buffer in 2 cycles (merging into the newest word not yet
  sent), into a full one once the oldest has left, and the buffer drains
  a word a write transaction whenever the port is free; the blitter and
  the DMA engine start once it is empty, as `wr_busy` holds them;
- the controller's sharing as `sdram_burst.v` and `video.v` (7725fee)
  have it: a refresh every FREQ / 133 kHz + 1 cycles (305 at 40.5 MHz)
  first, then the display's bursts, 32 of four words for each of the 768
  lines shown (16 in text mode), at the start of the line before (840
  cycles a line at 40.5 MHz), each followed by a cycle in which a waiting
  access of the cache goes first, then the cache; a burst 10 cycles, a
  write 7, 2 more with the bank's row closed and 3 with another row open
  (which rows are open is followed); phased from the core's start, once
  the controller has initialised (FREQ / 5000 + 36 cycles), as `tb_soc`
  measures them; `-nodisplay` leaves the display out, as `soc.v` with
  `USE_VIDEO = 0`;
- the blitter busy for a time fitted to the test bench's 409 timed blits
  (median error 6%); the pixels change when it finishes.

`fpga/rom/bench.s` of the Verilog repository, its kernels' cycles as its
tick timer counts them, in `tb_soc` and in em16 (the SCC at the board's
DIVISOR in both, `-Ptb_soc.DIVISOR=219` or `352`); every instruction is
taken in the same cycle in both, all through the run:

| Clock, display | sieve | sum | copy | walk |
|---|---|---|---|---|
| 25.2 MHz, none | 90,635 | 29,672 | 6,470 | 49,038 |
| 40.5 MHz, none | 56,395 | 18,432 | 4,031 | 30,493 |
| 40.5 MHz, 1024 x 768 graphics | 57,028 | 20,182 | 4,236 | 32,940 |

(The em16 before the queue gave 109,511, 40,650, 9,526 and 65,266 for the
last.) Not modelled: the blitter's and the DMA engine's bursts on the
controller's port 2, which outrank the cache's (a CPU access during a
blit waits longer on the board); the CPU waiting for the external bus
while a DMA cycle has it; a queue fill of I/O, which reads nothing here;
and a typed character arriving while one waits: on the board it
overruns, here it is held back, as if by flow control.

As on the board, a store does not change bytes already in the core's
queue (at most the 8 after the storing instruction): code written by
stores runs as written only after a taken branch, jump, call, return or
interrupt, or 8 bytes or more past the store (the core's README). `-smc`
(and `-t`) reports each store into the queued bytes, "store to queued
code at bb:aaaa, PC bb:aaaa" (the store's address and its instruction's),
and their number at the end.

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
- **SD card**, `-sd`: an SDHC card in the microSD slot (`rtl/sd_spi.v`,
  `$02C0`), its blocks the image's from block 0. The controller is the
  RTL's, an access to DATA or NEXT waiting for the exchange running, which
  takes 16 * (DIVIDER + 1) + 1 cycles; the card is the Verilog
  repository's `sim/sd_card_model.v`: CMD0 and CMD8 with their CRCs, CMD9
  (the image's size), CMD10, CMD12, CMD13, CMD16, CMD17, CMD18, CMD24,
  CMD25, CMD55 and ACMD41, CMD58. Without `-sd` the slot reads `$FF`.

### Ethernet

The carrier's ENC424J600 (Microchip DS39935C) is on the external bus's
select 5, at `$0850`, in its 8-bit parallel mode 5 as the carrier wires it
(the Verilog repository's `docs/Hardware.md`, Ethernet): `+0` and `+2`
written set the address latch to 7E00h or 7F00h plus the byte, `+1` and
`+3` read and write at it. Its `/INT` is one of the cards' IRQ#, bit 3 of
`$0440`. The SoC's DMA channel 2 moves a frame between it and memory
without the CPU (latch the window, then start the channel). The comment at
the top of `EmEth.Mod` lists what it does and leaves out; in short, a driver written for the chip runs on it: the SFRs
with their Bit Set and Clear aliases, the SRAM windows and their wraps,
transmission with padding and the CRC, the receive ring with its status
vectors and the filters (unicast, not-me, multicast, broadcast, hash,
magic packet), the DMA's copy and checksum, the interrupts, the resets and
the PHY through MII, a 100 Mb/s full duplex link. The factory address is
00:04:A3:16:E5:00, or `-mac`'s.

`-net` is the cable. Without it the link stays down; with it the link
comes up 5 ms after a reset. macOS has no TAP device, so the frames go to
one of these:

- `-net vmnet`: Apple's vmnet.framework in shared mode, as QEMU's
  `vmnet-shared`. The guest is on a private network, 192.168.64.0/24, the
  Mac its gateway, with DHCP, DNS and NAT to the Mac's own network. It
  needs root: `sudo em16 -fpga ... -net vmnet` (or the com.apple.vm.networking
  entitlement, which Apple gives only to virtualisation products).
  `-net vmnet-host` is host-only (the Mac and other guests, no NAT), and
  `-net vmnet-bridged:en0` puts the guest on en0's own network as a machine
  of its own.
- `-net udp:LPORT:RPORT[:HOST]`: each frame a UDP datagram, received on
  LPORT and sent to HOST (127.0.0.1) port RPORT, as QEMU's `-netdev dgram`.
  It needs no privileges: two em16s are joined by giving each the other's
  ports, and a program can be the other end, as `test/eth.sh`'s is.

The frames go out and come in without their CRC; the chip adds it on the
way in, where the guest sees it.

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
same ROM prints the same on the RTL's SoC simulation. `test/expand.sh` does
the same for colour expansion (`test/expand.s`): 1-bit glyphs of widths 4 to
16, odd and even destinations, glyph rows going up the screen, a negative
source stride, background and transparent, OR and XOR, and fill winning; it
too matches the RTL. `test/sd.sh` drives the SD card (`test/sd.s`): the
card's start-up, the CSD, block reads with NEXT, a block written and read
back, CMD18 with CMD12 and CMD25; a model in the script checks what it
prints and the image file afterwards, and the RTL's SoC simulation with
its card model prints the same. `test/eth.sh` drives the ENC424J600
(`test/eth.s`) with a peer in Python at the other end of `-net udp`: the
interface check and ETHRST, the MAC address, the link and the PHY through
MII, a frame sent (the peer checks its padding), three received of which
the filters let two in (their next pointers, status vectors and text, the
IRQ), the hash table, the chip's DMA checksum and copy, and the SoC's
DMA channel 2 into the chip's buffer and back. `test/rtc.sh` drives the
real-time clock (`test/rtc.s`) at `-rtctime` 2026-11-09 23:59:58: the
registers, the index port, the RAM through a mirror, two updates over
midnight with UIP seen, the update interrupt and register C, BCD with
SET to 2100-01-01 (the century carried), 12-hour mode, the periodic
flag; then `-rtc` with no file (a new module, started) and again (kept).
The oc816 golden suite (`../oc`, make
test_self), `as/test816`, OS16's tests and Business BASIC's run on em16
-fpga.

The port found two faults of the Oberon compiler: two procedures of
the same name in one module are accepted, and a call from another
module can then reach the wrong one; and a string literal of more than
255 characters was cut short without a word (fixed: the limit is now
1023, and a longer one is an error).
