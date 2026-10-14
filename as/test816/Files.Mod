MODULE Files;
  (* Files held in memory, for running the assembler under the emulator
     before it has a file system. Offers the part of the runtime's Files
     interface the assembler uses. *)

  CONST NameLen = 64; BlockSize = 256;

  TYPE
    Block = POINTER TO BlockDesc;
    BlockDesc = RECORD next: Block; d: ARRAY BlockSize OF BYTE END;

    File* = POINTER TO FileDesc;
    FileDesc* = RECORD
      name: ARRAY NameLen OF CHAR;
      len: LONGINT;
      first: Block;
      next: File
    END;

    Rider* = RECORD
      eof*: BOOLEAN;
      file: File;
      pos: LONGINT
    END;

  VAR root: File;   (* the registered files *)

  PROCEDURE Old*(name: ARRAY OF CHAR): File;
    VAR f: File;
  BEGIN f := root;
    WHILE (f # NIL) & (f.name # name) DO f := f.next END;
    RETURN f
  END Old;

  PROCEDURE New*(name: ARRAY OF CHAR): File;
    VAR f: File; i: INTEGER;
  BEGIN NEW(f); i := 0;
    WHILE (i < NameLen - 1) & (i < LEN(name)) & (name[i] # 0X) DO f.name[i] := name[i]; INC(i) END;
    f.name[i] := 0X; f.len := 0; f.first := NIL; f.next := NIL;
    RETURN f
  END New;

  (* Enter f in the directory, in place of a file of the same name. *)
  PROCEDURE Register*(f: File);
    VAR p: File;
  BEGIN
    IF (root # NIL) & (root.name = f.name) THEN root := root.next
    ELSE p := root;
      WHILE (p # NIL) & (p.next # NIL) DO
        IF p.next.name = f.name THEN p.next := p.next.next ELSE p := p.next END
      END
    END;
    f.next := root; root := f
  END Register;

  PROCEDURE Close*(f: File);
  BEGIN
  END Close;

  PROCEDURE Length*(f: File): LONGINT;
  BEGIN RETURN f.len
  END Length;

  PROCEDURE Set*(VAR r: Rider; f: File; pos: LONGINT);
  BEGIN r.file := f; r.pos := pos; r.eof := FALSE
  END Set;

  (* the block holding position pos of f, appended if f ends before it *)
  PROCEDURE Seek(f: File; pos: LONGINT): Block;
    VAR b: Block;
  BEGIN
    IF f.first = NIL THEN NEW(f.first); f.first.next := NIL END;
    b := f.first;
    WHILE pos >= BlockSize DO
      IF b.next = NIL THEN NEW(b.next); b.next.next := NIL END;
      b := b.next; pos := pos - BlockSize
    END;
    RETURN b
  END Seek;

  PROCEDURE ReadByte*(VAR r: Rider; VAR x: BYTE);
    VAR b: Block;
  BEGIN
    IF (r.file = NIL) OR (r.pos >= r.file.len) THEN r.eof := TRUE; x := 0
    ELSE b := Seek(r.file, r.pos); x := b.d[r.pos MOD BlockSize]; r.pos := r.pos + 1
    END
  END ReadByte;

  PROCEDURE WriteByte*(VAR r: Rider; x: BYTE);
    VAR b: Block;
  BEGIN
    IF r.file # NIL THEN
      b := Seek(r.file, r.pos); b.d[r.pos MOD BlockSize] := x; r.pos := r.pos + 1;
      IF r.pos > r.file.len THEN r.file.len := r.pos END
    END
  END WriteByte;

BEGIN root := NIL
END Files.
