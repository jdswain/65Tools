# MakeImage & Real Boot Plan

**Goal:** replace the emulator's C bootstrap with a real Oberon boot chain.

Today `em16` *fakes* the boot: it parses the initial `.816` modules, relocates
them, and writes a module manifest at `$0D00` that `Modules.Mod` reads. We want:

1. **MakeImage** — an Oberon tool (runs on the host) that statically links a set
   of `.816` modules into a **kernel image** with a baked-in module manifest.
2. **A small boot ROM** — reads `/System/Kernel` from the floppy and jumps to its
   entry point. No relocation at boot: the kernel image is already linked.
3. **em16 becomes a straight emulator** — CPU + RAM + WD1793 + video, booting
   from the reset vector. The C `.816` loader and manifest writer are removed.

The runtime module loader (`Modules.Mod`, loads apps from FAT12 at runtime) stays
— MakeImage is *only* for building the kernel, "everything needed to load further
modules." The two are complementary and share the same relocation logic.

> **Why now:** writing a linker in Oberon that runs on the host needs a mature
> toolchain (a self-hosted compiler, `Files`, a stable `.816` format, and — for
> headroom — the new LARGE model so no build tool is boxed into one bank). That
> only came together recently.

---

## What already exists (reuse, don't rewrite)

| Asset | State |
|---|---|
| `em16/WD1793.cpp` | Working FDC — mount/read/write sectors to a disk image |
| `OS16/src/FloppyDriver.Mod` | Working block driver over the WD1793 |
| `OS16/src/Files.Mod` | Working FAT12 (read/write, subdirs, flush) |
| `OS16/src/Modules.Mod` | Working runtime `.816` loader + relocation engine |
| em16 `apply_relocation` (C) | Reference for the exact reloc semantics |

`Modules.ApplyReloc` already handles every relocation kind we need — JSR (intra),
JSL (import vs intra by bank byte), LDA #imm (var base), PER (imported proc var),
plus bank relocs and TD fixups. MakeImage does the **same fixups offline**,
writing into an image buffer instead of live banks.

---

## MakeImage design

### Reuse via a shared object-file core

Factor the `.816` parse + relocation out of `Modules.Mod` into a shared module —
call it `ObjFile.Mod` — with the *memory target abstracted* so the same code
serves both the runtime loader (writes live banks via `SYSTEM.PUT`) and MakeImage
(writes an image buffer in a file/array):

```
ObjFile.Mod  — parse a .816 header + sections; a Reloc engine parameterised by
               Get/Put procedures (or a small target record) so the "memory" is
               either live banks (Modules) or an image buffer (MakeImage).
Modules.Mod  — runtime loader: target = live banks, then SYSTEM.EXEC.
MakeImage.Mod— host linker:    target = image buffer, then write image + manifest.
```

If a full refactor is too disruptive at first, MakeImage may start by copying the
parse/reloc from `Modules.Mod` and we consolidate into `ObjFile.Mod` once both
work. Prefer the shared module — it keeps the two loaders from drifting.

### Inputs / outputs

- **Input:** a manifest — modules in link order, a base code address, a base var
  address, and the entry (`Module.proc`). Read from a text file (via `Files`).
- **Output:** a **kernel image** file:
  ```
  Header:   magic 'OS16', version, imageSize, loadAddr, varAddr, entry, count, checksum
  Manifest: per module { name, bank, codeBase, varBase, exportCount, export[] }
            + next-free code/var addresses  (the same shape Modules.ReadManifest
            already parses at $0D00 — so nothing on the runtime side changes)
  Code:     linked, at final addresses (no runtime relocation)
  Data:     TD + vars + strings
  ```
- Assign each module a code base + var base (as `Modules.Load` does with
  `loadAddr`/`varAddr`), resolve cross-module refs, apply all relocations, write
  the linked bytes, then append the manifest and header + checksum.

### Where it runs

MakeImage runs on the **host**, built with `oc-self` (LLVM backend) — it only
reads `.816` files and writes an image file through `Files`. No target hardware
needed.

---

## Boot process (target shape)

```
reset ─► ROM stub (asm): native mode, set SP/DP/DBR
       ─► Boot.Init (Oberon in ROM):
            banner to screen
            FloppyDriver + minimal FAT12 read
            open  /System/Kernel   (the MakeImage output)
            read image into RAM at loadAddr, verify magic + checksum
            JML  entry
       ─► Kernel runs; Modules.Mod loads further apps from FAT12 at runtime
```

Because the kernel image is pre-linked by MakeImage, the ROM does **no
relocation** — it reads the file and jumps. The ROM's module set is small:
a stub + `Boot` + `FloppyDriver` + a read-only FAT12 lookup + image load. MakeImage
builds the ROM too (a `--rom` variant), so the ROM is itself Oberon.

`/System/Kernel` is the agreed path (cf. `Startup.md`'s `/OSLibrary/Modules/`).

---

## De-faking em16

- Add a **boot mode**: load the kernel/ROM image at its base, set the reset
  vector to its entry, run. No `.816` parsing, no `$0D00` manifest write.
- **Keep the current `.816`-loading mode behind a flag** during the transition so
  the existing golden suite (`run_self_tests.sh`) keeps working until the boot
  path is proven.
- Once boot works end-to-end, delete the C loader + manifest writer; em16 is then
  just CPU + RAM + WD1793 + video + reset-vector boot.

---

## Extended 816 — stack & DP escape bank 0

Our target is the **extended 816**: the stack pointer and direct page can be
24-bit, so **stack and DP need not live in bank 0**. This matters here:

- **Bigger / multiple stacks:** task stacks (and the compiler's deep recursion)
  can live in high RAM instead of being crammed into bank 0's 64 KB.
- **≥1 MB RAM:** the memory manager can hand out heap and stacks across banks;
  pointers are already 4-byte (addr+bank).
- Pairs with the **long-SB** direction (module globals via a 24-bit static base —
  the `Plan.md` "escape bank 0" item) to give a full *data-in-any-bank* model.

MakeImage should therefore let the manifest specify stack/DP placement (bank +
offset). Minimal boot can stay in bank 0; we move stacks/globals to high banks as
the memory manager and the long-SB codegen land. This is the *data-side* companion
to the LARGE (code-side) memory model already implemented.

---

## Some OS code predates recent compiler work

`Files.Mod`, `FloppyDriver.Mod`, `Modules.Mod` etc. were written against an older
oc816 and use 16-bit (`INTEGER`) addresses / `CodeBank = 1` (single bank). Before
building on them: **recompile the OS module set with the current oc816 and fix
what breaks** (changed `SYSTEM` signatures, sizing, etc.). This is Phase 1 — it
de-risks everything and tells us how much updating is really needed.

---

## Phases

1. **Audit & rebuild.** Compile the existing OS modules (`Out`, `FloppyDriver`,
   `Files`, `Modules`, tests) with the current oc816; fix breakage; confirm the
   FAT12 tests still pass on em16 (current fake-load mode). *Deliverable: a green
   baseline on today's compiler.*
2. **Shared `ObjFile.Mod`.** Extract the `.816` parse + relocation engine from
   `Modules.Mod`, memory-target abstracted. `Modules.Mod` re-expressed on top of
   it (behaviour unchanged, tests still pass).
3. **MakeImage.Mod.** Host linker producing a kernel image + baked manifest.
   *Deliverable: an image of `{Out, Hello}` that boots under em16's new mode with
   zero C-side loading and prints.*
4. **em16 boot mode + de-fake.** Boot-image/reset-vector mode; gate then remove
   the C loader/manifest.
5. **Boot ROM.** Oberon ROM that reads `/System/Kernel` from FAT12 and jumps.
   *Deliverable: full cold boot from a floppy image.*

Later tracks (separate): memory manager + GC, Console (then Windows / Controls /
Menu Bar), long-SB *data-in-any-bank* codegen, and self-hosting.

**Start:** Phase 1 (audit & rebuild) — immediately actionable and it tells us the
true state of the pre-existing code before we build MakeImage on it.
