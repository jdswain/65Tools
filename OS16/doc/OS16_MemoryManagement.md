# OS16 Memory Management

**Authoritative memory map + MemoryManager / HeapManager design.**
Supersedes the address assumptions in `OS16/docs/OS16_Memory_Layout.md` where
they conflict (that doc predates the extended 816 and assumes bank 1 = video /
all stacks in bank 0). This is the design of record going forward.

## 0. Why this exists

Every memory region in OS16 must have exactly one owner and one documented
address range. The recent MakeImage bug was caused by two components both
claiming the same bytes: the module loader wrote a module's data at `varAddr`
while the emulator's ad-hoc heap started at the *same* address, so linking a
module clobbered the open file's `FileDesc` (which lived on that heap). The fix
is not another magic constant — it is a single component, the **MemoryManager**,
that owns the whole address space and hands out non-overlapping blocks. Nothing
writes to memory it was not given.

Two rules:
1. **The MemoryManager is the sole authority for RAM ≥ the dynamic base.** No
   other module picks an address. Fixed low-bank-0 structures (below) are the
   only hardcoded addresses, and they are listed here once.
2. **Every allocation is owned.** A block records its owner (a process id, or
   `SYSTEM`). Freeing a process frees all its blocks.

## 1. Hardware assumptions (extended 816)

- 24-bit address space, up to 16 MB (256 banks × 64 KB). Target: **≥ 1 MB**
  (SDRAM on the FPGA gives 32 MB; usable range is the 24-bit 16 MB).
- **Extended 816: the stack pointer and direct-page register are 24-bit** — S
  and D may point into *any* bank, not just bank 0. This is the pivotal change
  from the old design: per-process stacks and direct pages no longer have to be
  crammed into bank 0, so they can be full-size and there can be many of them.
- Pointers are 4 bytes: `[offset_lo, offset_hi, bank, $00]` (pad byte 0).
- Reset/IRQ/NMI vectors are fixed at `$00:FFE4–$FFFF` and must be RAM after ROM
  switch-out. Device registers are memory-mapped low in bank 0 (e.g. FDC `$0640`).

## 2. The memory map

The address space is divided into a small **reserved** low region (fixed
addresses, never handed out) and a large **managed** region (everything the
MemoryManager allocates from).

```
$00:0000 ┌──────────────────────────────────────────┐  RESERVED — bank 0 system zone
         │ $0000–$00FF  kernel direct page (D=0)     │  (fixed; not MemoryManager-managed)
         │ $0100–$03FF  kernel/boot stack            │
         │ $0400–$05FF  device registers (FDC, …)    │  hardware-mapped
         │ $0600–$0CFF  kernel tables:               │
         │                process table, port table, │
         │                free bitmaps, MM metadata   │
         │ $0D00–$0FFF  boot manifest (from MakeImage)│
         │ $1000–$FFDF  reserved / kernel static      │  (kernel globals, ISR stubs)
         │ $FFE4–$FFFF  CPU vectors                   │
$01:0000 ├──────────────────────────────────────────┤  RESERVED — video framebuffer
         │              (only if a display is fitted; │   otherwise this bank is MANAGED)
         │               window server owns it)       │
$02:0000 ├──────────────────────────────────────────┤  MANAGED ZONE (MemoryManager)
         │                                            │   coarse blocks, bank- or page-
         │   MemoryManager block pool                 │   aligned, one owner each:
         │     process CODE segments                  │     CODE  (executable, JSL-reached)
         │     process DATA segments (module globals) │     DATA  (module SB base)
         │     process STACK blocks   (extended-816)  │     STACK (S points here)
         │     process DP blocks      (extended-816)  │     DP    (D points here)
         │     HEAP blocks            → HeapManager   │     HEAP  (sub-allocated)
         │     shared static buffers  (FS cache, …)   │     BUFFER
         │                                            │
$NN:FFFF └──────────────────────────────────────────┘  top of installed RAM
```

Notes:
- **Bank 0 stays small and fixed.** Because stacks and DPs escape to the managed
  zone (extended 816), bank 0 no longer holds 32 stacks — it holds only the
  kernel's own DP/stack, device registers, kernel tables, the boot manifest, and
  the vectors. This is where the old "cram 32×1 KB stacks into `$1800–$97FF`"
  design is retired.
- **The video framebuffer is owned by the DisplayManager, not by MemoryManager
  or the Graphics code.** When a display is fitted, the DisplayManager (a future
  module — does not exist yet) reserves the framebuffer at boot via
  `MemoryManager.AllocFixed` (kind BUFFER or DEVICE, owner = the display device)
  and hands drawing code a handle to it. Graphics/UIGraphics render *into* that
  buffer but never allocate it. With no display fitted (the current disk-boot
  path) that bank is just an ordinary managed region. So MemoryManager reserves
  nothing for video itself; it only records the AllocFixed the DisplayManager
  requests. This keeps "one owner per region" intact: no module hardcodes a
  framebuffer address.
- **The managed zone is granular per block owner**, so a process's code, data,
  stack, DP, and heap are independent MemoryManager blocks and are all reclaimed
  when the process exits.

## 3. MemoryManager

Coarse block allocator over the managed zone. It is the only code that decides
addresses there. Blocks are aligned (default: 256-byte pages; STACK/DP/CODE may
request bank alignment).

### Block model

```
BlockKind = CODE | DATA | STACK | DP | HEAP | BUFFER
Block = RECORD
  base   : ADDR24     (* 24-bit start address *)
  size   : INTEGER    (* bytes *)
  kind   : BlockKind
  owner  : INTEGER    (* process id, or Sys *)
  next   : Block      (* free/used list link *)
END
```

### API (sketch)

```
PROCEDURE Init(ramBase, ramTop: ADDR24);          (* the managed zone bounds *)
PROCEDURE Reserve(base: ADDR24; size: INTEGER);   (* carve out video / device banks *)
PROCEDURE Alloc(kind: BlockKind; size, align: INTEGER; owner: INTEGER): Block;  (* NIL on OOM *)
PROCEDURE Free(b: Block);
PROCEDURE FreeOwner(owner: INTEGER);              (* free every block of a process *)
PROCEDURE Stat(VAR used, free, largest: INTEGER); (* diagnostics *)
```

- Implementation: a free-list over the managed zone (first-fit + coalescing on
  free), with a small fixed table of `Block` records in the kernel-tables area
  (bank 0). No self-referential heap — the MemoryManager's own metadata is a
  fixed static array, so it can run before any heap exists.
- **This fixes the loader/heap collision structurally:** the module loader asks
  `Alloc(CODE, …)` and `Alloc(DATA, …)`; the heap is `Alloc(HEAP, …)`. Two
  distinct blocks can never overlap, so writing a linked module can never touch
  the heap or an open file's buffer.

## 4. HeapManager

Fine-grained allocator that operates **inside a single MemoryManager HEAP
block**. This is the target of Oberon `NEW`. There can be more than one heap
(e.g. a per-process heap and a shared system heap) — each is its own HEAP block.

```
Heap = RECORD blk: Block; ... free list ... END
PROCEDURE Create(size: INTEGER; owner: INTEGER): Heap;   (* MemoryManager.Alloc(HEAP,…) *)
PROCEDURE Alloc(h: Heap; size: INTEGER; typeDesc: ADDR24): ADDR24;   (* NEW *)
PROCEDURE Free(h: Heap; p: ADDR24);
PROCEDURE Collect(h: Heap);                              (* mark/sweep, later *)
```

- 12-byte block header per allocation `{size:4, typeDesc:4, flags:2, pad:2}` —
  as in the old doc §6.1; `typeDesc = 0` means opaque (raw buffer, not scanned).
- First-fit + split now; the mark/sweep GC (roots = process stacks + module
  globals, traversal via type descriptors — the backend already emits the
  pointer maps / tag headers) is a later drop-in that operates on the same
  header. If the active HEAP block is exhausted, HeapManager asks the
  MemoryManager to grow it or allocate another HEAP block.

## 5. Multiple processes (designed in now)

A process owns a set of MemoryManager blocks so we never have to re-layout for
concurrency later:

```
Process = RECORD
  id        : INTEGER
  code      : Block       (* CODE  — its linked module code *)
  data      : Block       (* DATA  — its module globals; SB base *)
  stack     : Block       (* STACK — S points into this (extended 816) *)
  dp        : Block       (* DP    — D points into this (extended 816) *)
  heap      : Heap        (* its NEW arena; may share the system heap *)
  ... TCB fields (saved S, D, DBR, state, priority, ports) ...
END
```

- **Create**: `MemoryManager.Alloc` a code block (loader links into it), a data
  block, a stack block, a DP block; `HeapManager.Create` (or attach the shared
  heap); build the TCB with `S`/`D` pointing at the stack/DP blocks (24-bit, so
  they can be anywhere). **Exit**: `MemoryManager.FreeOwner(id)` reclaims all of
  it in one call.
- Because S and D are 24-bit (extended 816), stacks can be large (the compiler's
  deep recursion is no longer boxed into 1 KB) and each process is fully
  isolated in its own blocks — no shared bank-0 stack region.
- The kernel itself is "process 0 / SYSTEM": its stack/DP are the fixed bank-0
  reserved regions; its static tables are `Reserve`d, not `Alloc`ed.

## 6. Migration from the current code

The current `Modules`/`MakeImage`/em16 use a flat model (code in bank 1 from
`$0000`, data in bank 0 from `$1000`, ad-hoc heap at the next free var address).
Steps to land this design without a big-bang rewrite:

1. **MemoryManager + HeapManager modules** (kernel static tables; no heap
   needed to bootstrap them).
2. **Route `NEW`/Files' `FileDesc` allocation through HeapManager** on a HEAP
   block — this alone fixes the MakeImage multi-module collision, because the
   heap is a reserved block that the loader's DATA/CODE writes cannot reach.
3. **Route the loader** (`Modules.SetLinkAddr` today) through
   `MemoryManager.Alloc(CODE/DATA,…)` so linked/loaded modules get owned blocks
   instead of a hand-picked `$8000`.
4. **Boot**: MakeImage's kernel image reserves the bank-0 fixed zone and the
   video bank (if any) and initialises the MemoryManager over the rest; the
   boot manifest tells it what is already resident.
5. Later: per-process blocks + the scheduler; the GC in HeapManager.

## 7. Open decisions

- **Alignment/granularity**: 256-byte pages vs bank-aligned for CODE/STACK.
  Bank-aligned CODE makes intra-module JSR (small model) always reachable; page
  alignment packs tighter. Proposed: bank-align CODE and STACK, page-align the
  rest.
- **One shared heap vs per-process heaps**: start with one shared system heap
  (simpler, and Files/kernel allocations are shared); give the compiler its own
  heap later if isolation/GC pauses matter.
- **Where the kernel tables + MemoryManager metadata live**: fixed in bank 0
  `$0600–$0CFF` per §2; size the block table for the max process count.
- **Reconcile the two OS16 trees** (`OS16/` design docs vs `65Tools/OS16/`
  code): this doc lives with the code and is authoritative for addresses.
