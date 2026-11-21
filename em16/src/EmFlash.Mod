MODULE EmFlash; (* An SST39SF040 (512K), 020A (256K) or 010A (128K): the
   Mini816's flash, with SST's software commands.

   Addresses are the chip's (the board masks them to its size). A
   command's cycles are recognised by A14-A0 alone, as on the chip:

     byte program   5555/AA 2AAA/55 5555/A0 addr/data     the byte ANDed in
     sector erase   5555/AA 2AAA/55 5555/80 5555/AA 2AAA/55 sector/30   4K
     chip erase     5555/AA 2AAA/55 5555/80 5555/AA 2AAA/55 5555/10
     ID entry       5555/AA 2AAA/55 5555/90    then A0 = 0 reads $BF, 1 the device
     ID exit        any/F0, or 5555/AA 2AAA/55 5555/F0

   and any other write starts the sequence again. An operation is
   complete at once, so data# polling and the toggle bit read as done.
   With Protect (the FLASH_WRITE jumper off: /WE held high) the chip
   sees no write at all.

   Open reads an image file, which then holds the chip: each byte
   programmed and each erase is written through to it, as the disk images
   are (EmHost's disk 4). A missing file starts erased and is made by the
   first write. *)

  IMPORT Files, EmHost;

  CONST
    max = 80000H;
    disk = 4;               (* EmHost's disk image for the file *)

  VAR
    mem*: ARRAY max OF BYTE;
    size*: INTEGER;
    state, idCode: INTEGER;
    id, protect, backed: BOOLEAN;
    name: ARRAY 1024 OF CHAR;

  PROCEDURE SetSize*(n: INTEGER);
  BEGIN size := n;
    IF n = 20000H THEN idCode := 0B5H ELSIF n = 40000H THEN idCode := 0B6H ELSE size := max; idCode := 0B7H END
  END SetSize;

  PROCEDURE Protect*(on: BOOLEAN);
  BEGIN protect := on
  END Protect;

  PROCEDURE Read*(a: INTEGER): INTEGER;
    VAR v: INTEGER;
  BEGIN a := AND(a, size - 1);
    IF id THEN IF ODD(a) THEN v := idCode ELSE v := 0BFH END ELSE v := mem[a] END;
    RETURN v
  END Read;

  (* the file's bytes from a, n of them (1, or 4K at a time), as the chip
     now holds them *)
  PROCEDURE Store(a, n: INTEGER);
    VAR buf: ARRAY 1000H OF BYTE; one: ARRAY 1 OF BYTE; i: INTEGER; f: Files.File; r: Files.Rider;
  BEGIN
    IF name[0] # 0X THEN
      IF ~backed THEN                               (* the file made, from the chip *)
        f := Files.New(name); Files.Set(r, f, 0);
        FOR i := 0 TO size - 1 DO Files.WriteByte(r, mem[i]) END;
        Files.Register(f); Files.Close(f); backed := EmHost.DiskOpen(disk, name) = 1
      ELSIF n = 1 THEN one[0] := mem[a]; EmHost.DiskWrite(disk, a, one)
      ELSE
        WHILE n > 0 DO
          FOR i := 0 TO 0FFFH DO buf[i] := mem[a + i] END;
          EmHost.DiskWrite(disk, a, buf); a := a + 1000H; n := n - 1000H
        END
      END
    END
  END Store;

  PROCEDURE Erase(a, n: INTEGER);
    VAR i: INTEGER;
  BEGIN FOR i := a TO a + n - 1 DO mem[i] := 0FFH END; Store(a, n)
  END Erase;

  PROCEDURE Write*(a, v: INTEGER);
    VAR c: INTEGER;
  BEGIN
    IF ~protect THEN
      a := AND(a, size - 1); c := AND(a, 7FFFH); v := AND(v, 0FFH);
      IF state = 3 THEN                             (* the byte to program *)
        mem[a] := AND(mem[a], v); Store(a, 1); state := 0
      ELSIF (state = 0) & (c = 5555H) & (v = 0AAH) THEN state := 1
      ELSIF (state = 1) & (c = 2AAAH) & (v = 55H) THEN state := 2
      ELSIF (state = 2) & (c = 5555H) & (v = 0A0H) & ~id THEN state := 3
      ELSIF (state = 2) & (c = 5555H) & (v = 80H) & ~id THEN state := 4
      ELSIF (state = 2) & (c = 5555H) & (v = 90H) THEN id := TRUE; state := 0
      ELSIF (state = 2) & (c = 5555H) & (v = 0F0H) THEN id := FALSE; state := 0
      ELSIF (state = 4) & (c = 5555H) & (v = 0AAH) THEN state := 5
      ELSIF (state = 5) & (c = 2AAAH) & (v = 55H) THEN state := 6
      ELSIF (state = 6) & (v = 30H) THEN Erase(AND(a, -1000H), 1000H); state := 0
      ELSIF (state = 6) & (c = 5555H) & (v = 10H) THEN Erase(0, size); state := 0
      ELSIF v = 0F0H THEN id := FALSE; state := 0
      ELSE state := 0
      END
    END
  END Write;

  (* the chip's contents from the file f, if there is one; FALSE if it
     cannot be read *)
  PROCEDURE Open*(f: ARRAY OF CHAR): BOOLEAN;
    VAR i, n, rc: INTEGER; buf: ARRAY 1000H OF BYTE; ok: BOOLEAN;
  BEGIN ok := TRUE; i := 0;
    WHILE (i < LEN(f) - 1) & (i < LEN(name) - 1) & (f[i] # 0X) DO name[i] := f[i]; INC(i) END; name[i] := 0X;
    IF EmHost.FileExists(name) # 0 THEN
      rc := EmHost.DiskOpen(disk, name);
      IF rc = 0 THEN ok := FALSE
      ELSE backed := rc = 1;
        IF rc = 2 THEN name[0] := 0X END;           (* read-only: the changes are not kept *)
        n := 0;
        WHILE n < size DO
          rc := EmHost.DiskRead(disk, n, buf);
          FOR i := 0 TO 0FFFH DO IF i >= rc THEN buf[i] := 0FFH END; mem[n + i] := buf[i] END;
          n := n + 1000H
        END
      END
    END;
    RETURN ok
  END Open;

  (* an image into the top of the chip, as a boot ROM is placed; FALSE if
     it cannot be read or does not fit *)
  PROCEDURE LoadTop*(f: ARRAY OF CHAR): BOOLEAN;
    VAR file: Files.File; r: Files.Rider; n, i: INTEGER; b: BYTE; ok: BOOLEAN;
  BEGIN file := Files.Old(f); ok := file # NIL;
    IF ok THEN n := Files.Length(file); ok := n <= size;
      IF ok THEN Files.Set(r, file, 0);
        FOR i := size - n TO size - 1 DO Files.ReadByte(r, b); mem[i] := b END
      END
    END;
    RETURN ok
  END LoadTop;

  PROCEDURE Reset*;
  BEGIN state := 0; id := FALSE
  END Reset;

  PROCEDURE Init;
    VAR i: INTEGER;
  BEGIN FOR i := 0 TO max - 1 DO mem[i] := 0FFH END;
    SetSize(max); protect := FALSE; backed := FALSE; name[0] := 0X; Reset
  END Init;

BEGIN Init
END EmFlash.
