# OS16 Module Linking — Kernel-as-API vs Shared Modules

**Decision note.** Companion to `MakeImage_Boot_Plan.md` (which assumed a
*self-contained* pre-linked kernel image). This note covers the dimension that
plan does not: how **apps** link against the kernel, whether modules are
**shared** (loaded once), and how the system **bootstraps**.

**Decision (2026-08-27): pure dynamic loading, no fixed kernel image.** Every
module is relocated at load, the Wirth one-by-one way; nothing bakes a RAM
address, so there is no base-address-stability problem to solve (an earlier
draft agonised over a fixed base layer + reserved `base.map` — that is retired,
see §4). Bootstrap is a **two-stage boot** with the loader in ROM (§5). The only
self-contained, fixed-address artifact left is the ROM itself, and ROM addresses
are fixed by construction — so `MakeImage` shrinks to "build the ROM image."

The prompt for this note: `MakeImage` linking failed with `res=-2` "Failed to
load dep: Out". That is not a mere bug — it is the self-contained-snapshot model
colliding with module sharing. Understanding why settled the architecture toward
pure dynamic loading.

---

## 0. TL;DR

- The **Wirth shared-linking model already works at runtime.** The loader keeps
  one module table and resolves imports **by name at load time**; with the
  normal `linkBase = 0`, an app's imports bind to already-resident kernel
  modules, and a module imported by two apps is **loaded once**. No `KFile`/`File`
  split or frozen ABI is required to get sharing.
- We do **not** have to choose "kernel API" *vs* "shared modules." Keep one flat
  module namespace; "the kernel" = the modules resident at boot; "the API" =
  their exported procedures, resolved by name, version-checked by the existing
  per-module `key`.
- **Everything is relocated at load** (decided). No fixed base layer, no
  pre-linked kernel image, no `base.map`. `linkBase = 0` at runtime always, so
  imports bind to whatever is resident and modules load once. `SetLinkBase`'s
  raise-the-base mode is now used **only** to build the ROM image (§5).
- Bootstrap is solved by a **two-stage boot** (§5): a ROM-resident BootLoader
  (full relocating loader + read-only FAT12 + read-only floppy) brings the loader
  closure resident, then loads and jumps to Kernel.

---

## 1. What the loader actually does today

`Modules.Mod` keeps **one** global table (`names/banks/baseAddrs/varAddrs/
exports/entries`, `count`). Imports are resolved **by name**:

```
Find(name) -> module index      (linear scan of the table from linkBase..count)
LoadEx:  IF Find(nm) >= 0 THEN (* already resident: reuse *) ELSE load from disk END
```

After placing a module, the loader patches each **JSL import fixup** with the
resident target module's *real* export address (seen in traces as
`JSL import fixup … -> Out $01:0117`). So:

- **Linking is done by the loader, by name, at load time** — exactly the robust,
  non-fragile mechanism we wanted. Apps are not hand-linked against fixed kernel
  offsets; they carry symbolic imports the loader binds.
- With `linkBase = 0` (normal runtime), `Find` sees every resident module, so
  **imports bind to resident modules and sharing is automatic** — a second app
  importing `Out` finds it and reuses it. *This already happens.*

**Conclusion:** the shared model is not a rewrite; it is the current runtime
behaviour. What blocks it in one place is MakeImage's deliberate opt-out.

---

## 2. Why `linkBase` exists (and the `res=-2`)

`SetLinkBase(firstMod)` raises `Find`'s lower bound so a link session **cannot
see** the modules already resident when MakeImage started. Purpose: build a
**self-contained** kernel image — the linked kernel re-links *fresh copies* of
its modules rather than referencing the build tool's resident `Out`/`Driver`
(whose addresses are the build tool's and won't exist at boot).

The `res=-2` falls straight out of this: MakeImage **itself imports**
`Driver, FloppyDriver, Files, Modules, Out`, so those are resident. Linking a
kernel/app that also imports `Out` cannot `Find` it (excluded by `linkBase`),
so it force-loads a *fresh* `Out` from disk — and that second-copy path is what
fails. The collision is structural, not incidental.

Two honest ways out, matching the two architectures:

| | Self-contained image | Link-against-resident base |
|---|---|---|
| `linkBase` for this build | **raised** (fresh copies) | **0** (reuse resident) |
| Image contains | full dependency closure | only the *new* modules |
| Correct when | built against an **empty** resident set | base is resident at **stable** addresses at build *and* boot |
| Modules shared | no (each image its own copies) | **yes — loaded once** |
| Fixes `res=-2` by | building with deps *not* already resident, or supporting a 2nd image-local copy | letting `Find` see the base |

Both are legitimate; they serve different build targets (§3).

---

## 3. Two build targets, one loader

Stop treating "linking" as one mode. There are two:

1. **ROM image build** (the *only* self-contained, fixed-address target):
   BootLoader (§5) — a full relocating loader + read-only file layer, linked once
   into ROM. Because it is ROM, its addresses are fixed by construction; there is
   no RAM address map to keep stable. This is the sole remaining use of
   `SetLinkBase(raise)` / `MakeImage`.

2. **Everything else — runtime dynamic load** (`Modules.Load`, `linkBase = 0`):
   kernel modules and apps alike are relocated at load and bind imports to
   whatever is resident. Modules load once and are shared. No self-containment,
   no baked RAM addresses. This is the Wirth shared model, and the runtime loader
   already does it.

So the answer to "kernel API vs modules-as-kernel-interface" is: **modules are
the interface, resolved by name at load, and that is not fragile because the
loader — not the app — does the binding.** Versioning is the per-module `key`
(symbol-file hash) the loader already reads; an app importing a changed kernel
module can be **rejected on key mismatch** — stronger than a hand-maintained ABI,
and free.

---

## 4. Base address stability — retired (not a problem)

An earlier draft treated "the base bakes addresses into apps" as needing a fixed
reserved `base.map`. **Because every module is now relocated at load, nothing
bakes a RAM address, so there is nothing to stabilise.** The whole question
dissolves. Kept here only so the reasoning isn't rediscovered: the fixed-`base.map`
option is *not* being pursued; pure dynamic loading is simpler and is what the
loader already does at `linkBase = 0`.

---

## 5. Bootstrap: two-stage boot, loader in ROM

The chicken-and-egg — to load modules from a FAT12 disk you need `Modules`,
`Files`, `FloppyDriver`, but those are themselves modules on the disk — is solved
by a two-stage boot rather than a fixed resident kernel.

```
reset ─► ROM stub (asm): native mode, set SP/DP/DBR
      ─► BootLoader (Oberon, in ROM):
           banner
           read-only WD1793 + read-only FAT12  ──┐  (BootLoader's private,
           full relocating loader (ObjFile core) ─┘   ROM-only subset)
           load + relocate the loader closure from /Library/Modules:
             {Driver, FloppyDriver, HeapManager, Files, Out, Modules}
             (+ MemoryManager)  in dependency order
           build the $0D00 module manifest describing what it just loaded
           load Kernel (via the now-resident real loader)
           JML Kernel.entry     ── frees BootLoader's scratch RAM
      ─► Kernel (boot coordinator): adopts the $0D00 manifest, brings up
           MemoryManager/display/drivers, then the shell; further apps load
           dynamically via the resident real Modules.
```

Key points, and the non-obvious ones:

- **"Subset" = the file layer, not the loader.** BootLoader must resolve imports
  and apply *full* relocation across the boot closure, so its loader/relocator is
  the real one (the `ObjFile.Mod` core from `MakeImage_Boot_Plan.md`). What is a
  subset is only the **file access**: read-only FAT12 (find file, follow cluster
  chain, read — no write / free-cluster alloc / mkdir) and read-only WD1793.
  Shared source with the runtime `Files`/`FloppyDriver`, so no logic drift.

- **No permanent duplicate code.** The read-only file layer lives *only* in ROM,
  costing zero RAM. (Contrast the rejected "fat `Modules`" option, which bakes a
  read-only floppy/FAT permanently into resident `Modules` and still needs a ROM
  reader to load `Modules` in the first place — strictly worse.)

- **The `$0D00` manifest is the handoff contract, and it already exists.** `em16`
  fakes it today; `Modules.ReadManifest` already parses it at init. BootLoader
  builds it for real. So "write BootLoader" and "de-fake em16" (Phase 4 of the
  boot plan) are the same work.

- **The ROM also passes a hardware-info block to the kernel.** Alongside the
  module manifest, BootLoader hands Kernel a fixed-layout **BootInfo** record
  describing the machine it discovered: total RAM size and bank count (→
  MemoryManager's managed-zone extent), video configuration (framebuffer
  base/bank, width/height/depth, or "none" → DisplayManager), boot device, and
  CPU variant (base 816 vs extended 816 with 24-bit S/DP). Kernel reads BootInfo
  *before* bringing up MemoryManager and the display, so nothing hard-codes RAM
  size or video geometry. This lives next to the `$0D00` manifest (a second fixed
  low-bank-0 structure — assign it an address in `OS16_MemoryManagement.md`); its
  layout is versioned so the ROM and Kernel can evolve independently. Discovery
  itself is the ROM's job (probe RAM, read the video controller); Kernel just
  consumes the record.

- **Boot allocation before MemoryManager exists.** The loader assigns code/var
  addresses with a linear bump allocator (as `loadAddr`/`varAddr` do now). Once
  MemoryManager is resident, register the already-used ranges with it so it never
  re-hands them out; then all further allocation goes through MM.

- **Memory reclaim.** BootLoader-in-ROM has no RAM *code* footprint; its only RAM
  is scratch (sector buffer, FAT window, bss, boot stack). After `JML Kernel`,
  MemoryManager marks that scratch free.

- **ROM vs disk for stage 1 (minor, deferrable).** BootLoader-in-ROM is the
  chosen default (simplest, no stage-1 disk seek). If ROM-reflash friction
  becomes a problem, a tiny ROM stub could instead read a BootLoader image from a
  fixed disk location — the classic BIOS→bootsector split. Not needed to start.

---

## 6. Concrete next steps (when we proceed)

1. **Extract `ObjFile.Mod`** — the `.816` parse + relocation + import-resolution
   core — shared by BootLoader and runtime `Modules` (Phase 2 of the boot plan).
2. **Read-only file/floppy subset** for BootLoader (find-file + cluster-walk +
   sector-read only), sharing source with `Files`/`FloppyDriver`.
3. **BootLoader** = ObjFile + RO-file + RO-floppy: loads the boot closure, builds
   the `$0D00` manifest, loads and jumps to `Kernel`. This *is* de-faking em16.
4. **`Kernel.Mod`** boot coordinator: adopt the manifest, bring up MemoryManager
   (registering the boot bump-allocator's used ranges), display, drivers, shell.
5. **Key-mismatch rejection** on load (verify the loader compares the import `key`
   against the resident module's; add if missing) — the "not fragile" guarantee.

`MakeImage` is reduced to building the ROM image (the one self-contained target).

---

## 7. Status

Architecture **decided** (2026-08-27): pure dynamic loading + two-stage boot with
the loader in ROM; base-address-stability retired; `MakeImage` → ROM builder
only. No open decisions block prototyping — start at §6.1 (`ObjFile.Mod`).
