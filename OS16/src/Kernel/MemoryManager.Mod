MODULE MemoryManager;
(* OS16 coarse block allocator — the sole authority for the managed memory zone.
   Hands out non-overlapping, owned blocks (CODE/DATA/STACK/DP/HEAP/BUFFER); a
   fixed-range reservation (AllocFixed) claims a specific address range for
   memory-mapped things like the video framebuffer or device registers, done
   very early at boot. Metadata is a fixed static table (bank 0), so the
   MemoryManager runs before any heap exists. See doc/OS16_MemoryManagement.md.

   Addresses are 24-bit (LONGINT). This module only TRACKS ranges; clients read
   and write the memory they are given. *)

  IMPORT Out;

  CONST
    MaxBlocks* = 128;
    (* block kinds *)
    Free* = 0; Code* = 1; Data* = 2; Stack* = 3;
    DP* = 4; Heap* = 5; Buffer* = 6; Device* = 7;
    Sys* = -1;   (* owner id for system/kernel-owned blocks *)

  TYPE Addr* = LONGINT;

  VAR
    (* One ordered (by base) segment table covering [ramBase, ramTop)
       contiguously; every byte belongs to exactly one segment, free or used.
       Adjacent Free segments are coalesced on release. *)
    base:  ARRAY MaxBlocks OF Addr;
    size:  ARRAY MaxBlocks OF Addr;
    kind:  ARRAY MaxBlocks OF INTEGER;
    owner: ARRAY MaxBlocks OF INTEGER;
    nseg:  INTEGER;
    ramBase, ramTop: Addr;

  PROCEDURE insert(i: INTEGER; b, s: Addr; k, o: INTEGER);
    VAR j: INTEGER;
  BEGIN
    IF nseg < MaxBlocks THEN
      j := nseg;
      WHILE j > i DO
        base[j] := base[j-1]; size[j] := size[j-1];
        kind[j] := kind[j-1]; owner[j] := owner[j-1]; DEC(j)
      END;
      base[i] := b; size[i] := s; kind[i] := k; owner[i] := o; INC(nseg)
    END
  END insert;

  PROCEDURE remove(i: INTEGER);
    VAR j: INTEGER;
  BEGIN
    j := i;
    WHILE j < nseg-1 DO
      base[j] := base[j+1]; size[j] := size[j+1];
      kind[j] := kind[j+1]; owner[j] := owner[j+1]; INC(j)
    END;
    DEC(nseg)
  END remove;

  (* Carve [a, a+sz) as (k, own) out of free segment i, leaving any leading and
     trailing remainder as Free. Precondition: base[i] <= a, a+sz <= end(i). *)
  PROCEDURE carve(i: INTEGER; a, sz: Addr; k, own: INTEGER);
    VAR segEnd: Addr;
  BEGIN
    segEnd := base[i] + size[i];
    IF a = base[i] THEN
      size[i] := sz; kind[i] := k; owner[i] := own;
      IF a + sz < segEnd THEN insert(i+1, a+sz, segEnd-(a+sz), Free, Sys) END
    ELSE
      size[i] := a - base[i];               (* leading remainder stays Free *)
      insert(i+1, a, sz, k, own);
      IF a + sz < segEnd THEN insert(i+2, a+sz, segEnd-(a+sz), Free, Sys) END
    END
  END carve;

  PROCEDURE Init*(rb, rt: Addr);
  BEGIN
    ramBase := rb; ramTop := rt;
    nseg := 1; base[0] := rb; size[0] := rt - rb; kind[0] := Free; owner[0] := Sys
  END Init;

  (* Round a up to a multiple of al. al is a power of two — a page (100H), a
     bank (10000H), or 1 — so we align with a constant MOD (a cheap AND mask)
     and never need a runtime 32-bit divide. *)
  PROCEDURE alignUp(a, al: Addr): Addr;
  BEGIN
    IF al = 10000H THEN a := a + 0FFFFH; a := a - (a MOD 10000H)
    ELSIF al = 100H THEN a := a + 0FFH; a := a - (a MOD 100H)
    END;
    RETURN a
  END alignUp;

  (* Allocate sz bytes of kind k for owner own, base aligned to al bytes.
     Returns the base address, or 0 if no free segment is large enough. *)
  PROCEDURE Alloc*(k: INTEGER; sz, al: Addr; own: INTEGER): Addr;
    VAR i: INTEGER; a, pad, res: Addr;
  BEGIN
    res := 0; i := 0;
    WHILE (i < nseg) & (res = 0) DO
      IF kind[i] = Free THEN
        a := alignUp(base[i], al); pad := a - base[i];
        IF pad + sz <= size[i] THEN carve(i, a, sz, k, own); res := a END
      END;
      INC(i)
    END;
    RETURN res
  END Alloc;

  (* Reserve the SPECIFIC range [b, b+sz) — e.g. the video framebuffer or a
     device-register window. TRUE if the whole range lay inside one free
     segment (now claimed), else FALSE (overlap / not free). *)
  PROCEDURE AllocFixed*(b, sz: Addr; k, own: INTEGER): BOOLEAN;
    VAR i: INTEGER; ok: BOOLEAN;
  BEGIN
    ok := FALSE; i := 0;
    WHILE (i < nseg) & ~ok DO
      IF (kind[i] = Free) & (base[i] <= b) & (b + sz <= base[i] + size[i]) THEN
        carve(i, b, sz, k, own); ok := TRUE
      END;
      INC(i)
    END;
    RETURN ok
  END AllocFixed;

  PROCEDURE coalesce;
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE i < nseg-1 DO
      IF (kind[i] = Free) & (kind[i+1] = Free) THEN
        size[i] := size[i] + size[i+1]; remove(i+1)
      ELSE INC(i)
      END
    END
  END coalesce;

  PROCEDURE Release*(addr: Addr);   (* free a block by its base address *)
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < nseg) & (base[i] # addr) DO INC(i) END;
    IF (i < nseg) & (kind[i] # Free) THEN
      kind[i] := Free; owner[i] := Sys; coalesce
    END
  END Release;

  (* Reclaim every block belonging to one owner (process exit). *)
  PROCEDURE FreeOwner*(own: INTEGER);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE i < nseg DO
      IF (kind[i] # Free) & (owner[i] = own) THEN kind[i] := Free; owner[i] := Sys END;
      INC(i)
    END;
    coalesce
  END FreeOwner;

  PROCEDURE Stat*(VAR used, freeBytes, largestFree: Addr);
    VAR i: INTEGER;
  BEGIN
    used := 0; freeBytes := 0; largestFree := 0;
    i := 0;
    WHILE i < nseg DO
      IF kind[i] = Free THEN
        freeBytes := freeBytes + size[i];
        IF size[i] > largestFree THEN largestFree := size[i] END
      ELSE used := used + size[i]
      END;
      INC(i)
    END
  END Stat;

  (* print a 24-bit address as bank:offset (Out.Hex/Int are 16-bit) *)
  PROCEDURE PrAddr*(a: Addr);
    VAR bank, hi, lo: INTEGER;
  BEGIN
    bank := a DIV 10000H; hi := a DIV 100H MOD 100H; lo := a MOD 100H;
    Out.Int(bank, 1); Out.Char(":"); Out.Hex(hi); Out.Hex(lo)
  END PrAddr;

  PROCEDURE Dump*;
    VAR i: INTEGER;
  BEGIN
    Out.String("MM:"); Out.Int(nseg, 1); Out.String(" segs"); Out.Ln;
    i := 0;
    WHILE i < nseg DO
      Out.String("  "); PrAddr(base[i]); Out.String(" +"); PrAddr(size[i]);
      Out.String(" k"); Out.Int(kind[i], 1); Out.String(" o"); Out.Int(owner[i], 1); Out.Ln;
      INC(i)
    END
  END Dump;

BEGIN
  nseg := 0; ramBase := 0; ramTop := 0
END MemoryManager.
