# FPGA Boot Plan — Tang Nano 20K 65C816 SoC

## REPLAN (2026-08-28): boot off the floppy

The floppy card can be wired in ~2 hours, which is far less rework than a full
self-contained assembly demo ROM — and it's the real architecture. Revised
approach, keeping the boot logic in **Oberon** (Wirth's no-assembly goal; the
only machine code is a ~43-byte stub baked into the tool):

- **`MakeROM`** (`OS16/tools/makerom.py`) — relocates a single dependency-free
  `.816` (imports `SYSTEM` only) into an 8/16 KB boot ROM: code → ROM base,
  vars → RAM base, a reset stub (native mode + stack, copy the string/TD data
  image ROM→RAM, zero BSS, `REP #$30`, `JML` entry), and the `$FFFA-$FFFF`
  vectors. Reuses the `.816` reloc semantics (JSR/JSL intra, var-base LDA, bank).
- **`Boot.Mod`** (`OS16/boot/Boot.Mod`) — pure Oberon, `IMPORT SYSTEM` only,
  fixed static buffers (no `NEW`). Talks to the WD1773 at `$0800` directly;
  reads a file **from the FAT12 root directory** (boot-sector geometry + root
  scan + cluster chain; no subdirs — decided), loads it to RAM, `JML`s it.
  Serial (`$0200`) for status.
- **Payload relocation stays offline** — the fuller `MakeImage` pre-links the
  payload closure to a RAM address; `Boot` just copies bytes + jumps.

**Decisions:** root-directory FAT12 (not fixed-sector, not subdirs); first
payload = **serial "hello", then the graphics window demo**.

### Status
- **B0 done** — em16 `-fpga` models the board; WD1793 already decodes at `$0800`
  (register = `ea & 0x0F`); `-disk0` mounts an image. Serial `$0200` → stdout,
  framebuffer/palette verified.
- **B1 done** — `MakeROM` + `Boot.Mod` (serial hello) → boots in
  `em16 -fpga -bootrom boot.rom`, prints `OS16 boot`. Validates the whole
  chain: Oberon → `.816` → relocated ROM → runs on the FPGA model.
- **B2 done (2026-08-29)** — `Boot.Mod` reads the floppy at `$0800` and dumps a
  named file. It talks to the WD1773 directly (motor-on + Restore/Seek +
  Read-Sector, DRQ-polled byte transfer, LBA→CHS with the same 9-sec/2-head
  mapping em16's `sectorOffset` uses), parses the FAT12 BPB, caches the FAT,
  scans the root directory for an 8.3 name (skips LFN/volume/dir/deleted),
  follows the cluster chain via `GetFAT`, and serial-dumps the content. Verified
  in `em16 -fpga -bootrom boot.rom -disk0 floppy.img`: finds `PAYLOAD.816` and
  dumps it byte-exact, incl. a 1501-byte 3-cluster file (chain-following clean).
  **Two gotchas hit:** (1) 816 `INTEGER` is 16-bit signed — a `MaxRetry=40000`
  poll cap wrapped negative so the wait loops ran once and "worked" only by
  luck; keep counters ≤32767. (2) `oc816 -s` writes the `.816` to the CWD, so
  compile `Boot.Mod` from inside `boot/` (or the ROM goes stale). hdiutil 720K
  images report SPT=32/HEADS=16 in the BPB, but that's irrelevant — em16 is a
  flat LBA image and Boot's 9/2 mapping matches em16's, so it round-trips.
- **Next: B3** load a payload to RAM + jump; **B4** payload = the window demo.

Build: `oc816 -s Boot.Mod` → `Boot.816`; `python3 OS16/tools/makerom.py
Boot.816 boot.rom` → `em16 -fpga -bootrom boot.rom -disk0 floppy.img`.

---

# Original plan (self-contained ROM, superseded by the floppy replan above)


Getting the machine to boot something real (framebuffer demo → shell → OS16),
staged against the hardware that exists now. Memory map of record:
`Verilog65C816/fpga/README.md`.

## Hardware status (2026-08)

| Piece | State |
|---|---|
| CPU + 8 MB SDRAM + block ROM/RAM | working (MiniMon boots from `$E000` block ROM over serial) |
| Serial (6551 ACIA @ `$0200`) | working — this is the console |
| Framebuffer (`$70_0000`, 640×480×4bpp) + palette (`$0240`) | wired |
| `$0300` ROM/RAM soft switch | wired |
| External bus (`$0800`, WD1773-style card) | connector exists; **no disk card built** |
| SD card (`$02C0`) | not implemented (reads `$FF`) |
| ADB keyboard/mouse (`$0280`) | **waiting on parts** |

Consequence: **no mass storage yet.** The runtime `.816` module loader
(`Modules.LoadEx`) has nothing to load *from*, so the first bootable targets must
be **fully self-contained in the boot ROM** — no loader, no disk.

## em16 now models this board (done)

`em16 -fpga` selects the FPGA memory map (8 MB SDRAM, I/O block at `$00_0200`,
serial at `$0200`, programmable palette at `$0240`, `$0300` soft switch,
switchable boot ROM at `$E000-$FFFF`, framebuffer at `$70_0000`). `-bootrom
rom.bin` loads an 8 KB ROM image; the CPU comes out of reset in **emulation
mode** and vectors from `$FFFC` in ROM, exactly like the hardware.

Validated: a 42-byte ROM (native-mode setup → program palette entry 1 → fill
`$70_0000` via `STA $700000,X` → `BRK #0` halt) renders correctly under
`em16 -fpga -bootrom fbtest.rom -fbdump out.ppm`. So the sim is a faithful
pre-flash test bed. (`-fbdump` snapshots the framebuffer headless; `-video`
opens the live window.)

Not yet modelled (deferred, matching the hardware): ADB, SD, and the external
floppy card just read/stub — fine until those exist.

## The boot ROM contract

An 8 KB image at `$E000-$FFFF`. On both hardware and em16:

1. Reset vector `$FFFC` → the ROM entry (emulation mode, `D=0`, stack in page 1).
2. `CLC; XCE` to native, set `SP`, set `DP`.
3. **Program the palette** — it is undefined at power-up. Write 16×`{r,g,b}` to
   `$0240 + n*4`. (em16 defaults it to VGA so sim demos show colour without
   this, but the hardware needs it — always program it.)
4. Optional: banner to serial `$0200`.
5. Optional but recommended: **shadow ROM→RAM** and drop the `$0300` switch, so
   `$E000-$FFFF` becomes patchable cached RAM (the README's shadow loop).
6. Run the payload.

## The payload: what boots, in order

### M1 — "Hello framebuffer" ROM  *(≈ done)*
The validated smoke-test ROM, fleshed out: program the full palette, clear the
screen, draw a test pattern. **Deliverable:** an image on the real panel.
Build path proven end-to-end in em16.

### M2 — Window demo as a ROM
Package the `GraphicsWindow` demo self-contained. `UIGraphics` is **already
assembly** (`UIGraphics.s`), so this is an assembly link, not a module load:

- `UIGraphics.s` (retargeted to `$70_0000`, low-nibble-left, 480-safe bank math)
  + the `Ohlfs9` glyph table as a data blob + a small `DrawString` + the window
  drawing sequence, assembled **absolute** at `$E000` (or shadowed to RAM).
- Estimated size: UIGraphics ~1.5 KB + font ~2 KB + window/string ~0.7 KB +
  palette/setup — comfortably inside 8 KB. No `Out`/serial needed for pixels.
- **Deliverable:** the Terminal window on the panel, from ROM, no disk.

### M3 — Serial monitor / shell
The FPGA already has MiniMon over `$0200`. Fold a small monitor into the ROM (or
keep MiniMon and add commands) so there's interactive control — peek/poke, run,
load-over-serial. This is the bridge that lets us push code before a disk exists:
**XMODEM-over-serial into SDRAM, then jump** — a stand-in for the disk loader.

### M4 — Real module loading  *(blocked on storage)*
When an SD (`$02C0`) or external floppy card (`$0800`, WD1773) is built:
bring up `FloppyDriver`/`Files`/`Modules` and boot OS16 via the two-stage loader
(`doc/OS16_ModuleLinking.md`, `doc/MakeImage_Boot_Plan.md`). The boot ROM shrinks
to a second-stage loader that pulls the kernel closure off storage. Until then,
serial-load (M3) covers development.

### M5 — ADB input  *(blocked on parts)*
Keyboard/mouse at `$0280` once the hardware lands; wire `ADBManager` to it.

## Toolchain gap to close (for M2)

Producing an absolute ROM binary from the assembly sources needs an
`assemble → locate → flat-binary + vectors → mk_verilog_rom` path:

- `as` emits ELF `.o` at `org=$E000`; the **`ln` linker is incomplete**, so for
  a single self-contained `.s` we can skip linking and **extract `.text` from the
  `.o`** into an 8 KB image (fill `$FF`, reset vector at offset `$1FFC`). A ~20-line
  script does this; `mk_verilog_rom` then makes the FPGA `.v`, and the same
  `.bin` runs under `em16 -fpga -bootrom`.
- If multiple `.s`/`.816` units must be combined, finishing `ln` (or a minimal
  absolute locator) becomes the real task — but M2 is designed to avoid it.

Note the **asd `.smb` is v1, oc816 is v6**: importing an assembly module from
Oberon needs the `UIGraphicsDef.Mod` v6 stub (compile against the stub, run
against the asd `.816`). Not on the ROM path, but the same drift to fix
eventually (bump asd to v6).

## Immediate next step

Do **M2**: write the `.text`-extraction script, assemble `UIGraphics.s` + a
window/font driver absolute at `$E000`, build the 8 KB ROM, verify in
`em16 -fpga -bootrom -video`, then `mk_verilog_rom` and flash. That puts the
window on real glass with everything the hardware has today.
