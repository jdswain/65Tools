MODULE HeapManager;
(* OS16 fine-grained allocator — the target of Oberon NEW. It sub-allocates
   inside a single MemoryManager HEAP block, so it never picks absolute
   addresses itself (MemoryManager owns those) and can never collide with
   code/data/other heaps. First-fit with splitting and lazy coalescing now;
   a mark/sweep GC is a later drop-in over the same block headers.

   Block header (12 bytes), 2-byte aligned, immediately before each payload:
     +0  size     (4)  total block size INCLUDING this header
     +4  flags    (2)  bit0 = in use
     +6  pad      (2)
     +8  typeDesc (4)  = payload-4, the [obj-4] type tag the 816 GC and
                        dynamic dispatch expect; 0 = free / opaque buffer
   See doc/OS16_MemoryManagement.md. *)

  IMPORT SYSTEM, MemoryManager, Out;

  CONST
    HdrSize*  = 12;
    MinBlock  = HdrSize + 4;   (* never leave a splinter smaller than this *)
    UsedBit   = 1;

    (* Default pre-kernel heap. A real boot ROM sizes the MemoryManager from
       detected RAM and Creates the system heap explicitly; until then Bootstrap
       lays a sensible default over the managed zone so any module that imports
       HeapManager (and thus routes NEW through it) just works. *)
    DfltRamBase  = 20000H;    (* managed zone starts at bank 2 *)
    DfltRamTop   = 100000H;   (* ... up to 1 MB (adjust when RAM is detected) *)
    DfltHeapSize = 80000H;    (* 512 KB system heap *)

  TYPE Addr* = MemoryManager.Addr;   (* 24-bit LONGINT *)

  VAR
    base, limit: Addr;   (* the active heap region [base, limit) *)

  (* --- 24-bit memory access via the 816 3-arg SYSTEM.GET/PUT (bank, ofs).
     One 2-byte word at a time, each split independently, so a 4-byte field
     that straddles a bank boundary still reads/writes correctly. Everything
     is 2-aligned, so a single word never straddles. --- *)

  PROCEDURE getW(p: Addr): Addr;   (* returns 0..0FFFFH (zero-extended) *)
    VAR bank, ofs, v: INTEGER; r: Addr;
  BEGIN
    bank := p DIV 10000H; ofs := p MOD 10000H;
    SYSTEM.GET(bank, ofs, v);
    r := v;                       (* INTEGER->LONGINT widen zero-extends *)
    RETURN r
  END getW;

  PROCEDURE putW(p, v: Addr);
    VAR bank, ofs, w: INTEGER;
  BEGIN
    bank := p DIV 10000H; ofs := p MOD 10000H; w := v;
    SYSTEM.PUT(bank, ofs, w)
  END putW;

  PROCEDURE getL(p: Addr): Addr;
  BEGIN RETURN getW(p) + getW(p + 2) * 10000H
  END getL;

  PROCEDURE putL(p, v: Addr);
  BEGIN putW(p, v MOD 10000H); putW(p + 2, v DIV 10000H)
  END putL;

  (* --- block header fields --- *)
  PROCEDURE blkSize(p: Addr): Addr;  RETURN getL(p)     END blkSize;
  PROCEDURE blkFlags(p: Addr): Addr; RETURN getW(p + 4) END blkFlags;
  PROCEDURE blkTD(p: Addr): Addr;    RETURN getL(p + 8) END blkTD;

  PROCEDURE setBlk(p, size, flags, td: Addr);
  BEGIN putL(p, size); putW(p + 4, flags); putW(p + 6, 0); putL(p + 8, td)
  END setBlk;

  PROCEDURE used(p: Addr): BOOLEAN;  RETURN blkFlags(p) MOD 2 = UsedBit END used;

  (* --- lifecycle --- *)

  (* Take a fresh HEAP block from the MemoryManager and lay one free block
     over it. Returns the block base, or 0 on out-of-memory. *)
  PROCEDURE Create*(size: Addr; owner: INTEGER): Addr;
    VAR b: Addr;
  BEGIN
    b := MemoryManager.Alloc(MemoryManager.Heap, size, 10000H, owner);
    IF b # 0 THEN base := b; limit := b + size; setBlk(b, size, 0, 0) END;
    RETURN b
  END Create;

  (* Lay the heap over an already-owned region (e.g. a static boot buffer). *)
  PROCEDURE Init*(regBase, size: Addr);
  BEGIN base := regBase; limit := regBase + size; setBlk(regBase, size, 0, 0)
  END Init;

  (* NEW: allocate 'size' payload bytes tagged with typeDesc (0 = raw buffer).
     Returns the payload address, or 0 if the heap is full. *)
  PROCEDURE Alloc*(size, typeDesc: Addr): Addr;
    VAR p, nx, bs, need, res: Addr;
  BEGIN
    need := HdrSize + (size + 1) DIV 2 * 2;   (* header + 2-aligned payload *)
    res := 0; p := base;
    WHILE (p < limit) & (res = 0) DO
      bs := blkSize(p);
      IF used(p) THEN p := p + bs
      ELSE
        (* greedily merge following free blocks so fragmentation heals *)
        nx := p + bs;
        WHILE (nx < limit) & ~used(nx) DO
          bs := bs + blkSize(nx); putL(p, bs); nx := p + bs
        END;
        IF bs >= need THEN
          IF bs - need >= MinBlock THEN
            setBlk(p + need, bs - need, 0, 0);   (* trailing remainder, free *)
            putL(p, need)
          END;
          putW(p + 4, UsedBit); putL(p + 8, typeDesc);
          res := p + HdrSize
        ELSE p := p + bs
        END
      END
    END;
    RETURN res
  END Alloc;

  (* Release a payload; the space is reclaimed lazily by the next Alloc. *)
  PROCEDURE Free*(payload: Addr);
    VAR p: Addr;
  BEGIN p := payload - HdrSize; putW(p + 4, 0); putL(p + 8, 0)
  END Free;

  PROCEDURE Stat*(VAR usedBytes, freeBytes, largestFree: Addr);
    VAR p, bs: Addr;
  BEGIN
    usedBytes := 0; freeBytes := 0; largestFree := 0; p := base;
    WHILE p < limit DO
      bs := blkSize(p);
      IF used(p) THEN usedBytes := usedBytes + bs
      ELSE
        freeBytes := freeBytes + bs;
        IF bs > largestFree THEN largestFree := bs END
      END;
      p := p + bs
    END
  END Stat;

  PROCEDURE Dump*;
    VAR p, bs: Addr;
  BEGIN
    Out.String("Heap "); MemoryManager.PrAddr(base);
    Out.String(".."); MemoryManager.PrAddr(limit); Out.Ln;
    p := base;
    WHILE p < limit DO
      bs := blkSize(p);
      Out.String("  "); MemoryManager.PrAddr(p); Out.String(" +");
      MemoryManager.PrAddr(bs);
      IF used(p) THEN Out.String(" USED td=") ELSE Out.String(" free   ") END;
      MemoryManager.PrAddr(blkTD(p)); Out.Ln;
      IF bs <= 0 THEN p := limit ELSE p := p + bs END   (* guard bad chains *)
    END
  END Dump;

  (* Set up MemoryManager over the default managed zone and create the default
     system heap. Idempotent; a kernel may instead call MemoryManager.Init +
     Create with real bounds before any allocation happens. *)
  PROCEDURE Bootstrap*;
    VAR b: Addr;
  BEGIN
    IF base = 0 THEN
      MemoryManager.Init(DfltRamBase, DfltRamTop);
      b := Create(DfltHeapSize, MemoryManager.Sys);
      IF b = 0 THEN Out.String("HeapManager: no memory for system heap"); Out.Ln END
    END
  END Bootstrap;

BEGIN
  base := 0; limit := 0;
  Bootstrap
END HeapManager.
