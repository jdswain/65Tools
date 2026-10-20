MODULE Files; (* The Oberon file interface: Files, Riders and a directory
   of names, on a file system on a block device (model: FileSystem).

   A FileSystem is the type a file system's module extends (FatFS),
   overriding its methods. One is in use at a time, the mounted one, which
   Old, New and the directory procedures work on; a file goes on working
   on the one it came from. Riders are kept here: a file system reads and
   writes a file a byte at a time, at a position.

   Init and Format work on a device with the file system installed (FatFS
   installs itself when it is loaded). *)

  IMPORT BlockDriver;

  CONST
    attrDirectory* = 10H;   (* a directory entry's attribute: a directory *)

  TYPE
    FileName* = ARRAY 128 OF CHAR;

    FileSystem* = POINTER TO FileSystemDesc;

    File* = POINTER TO FileDesc;
    FileDesc* = RECORD
      fs*: FileSystem   (* the file system it is on *)
    END;

    Rider* = RECORD
      eof*: BOOLEAN;    (* a Read was past the end *)
      res*: INTEGER;    (* ReadBytes: how many were not read; Write: -1 failed *)
      file: File;
      pos: INTEGER
    END;

    FileSystemDesc* = RECORD
      dev*: BlockDriver.BlockDriver   (* the device it lives on *)
    END;

    (* the file system of a device, not yet mounted *)
    Maker* = PROCEDURE (d: BlockDriver.BlockDriver): FileSystem;

  VAR
    mounted: FileSystem;   (* NIL: none *)
    maker: Maker;          (* the installed file system; NIL: none *)

  (* --- What a file system overrides --- *)

  (* Write an empty file system to the device. *)
  PROCEDURE (fs: FileSystem) Format*(): BOOLEAN;
  BEGIN RETURN FALSE
  END Format;

  (* Read the device's file system: TRUE if there is one. *)
  PROCEDURE (fs: FileSystem) Mount*(): BOOLEAN;
  BEGIN RETURN FALSE
  END Mount;

  (* Write back what is held in memory. *)
  PROCEDURE (fs: FileSystem) Sync*(): BOOLEAN;
  BEGIN RETURN TRUE
  END Sync;

  PROCEDURE (fs: FileSystem) Old*(name: ARRAY OF CHAR): File;
  BEGIN RETURN NIL
  END Old;

  PROCEDURE (fs: FileSystem) New*(name: ARRAY OF CHAR): File;
  BEGIN RETURN NIL
  END New;

  PROCEDURE (fs: FileSystem) Register*(f: File);
  END Register;

  PROCEDURE (fs: FileSystem) Close*(f: File);
  END Close;

  PROCEDURE (fs: FileSystem) Delete*(name: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN res := -1
  END Delete;

  PROCEDURE (fs: FileSystem) Rename*(old, new: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN res := -1
  END Rename;

  PROCEDURE (fs: FileSystem) Length*(f: File): INTEGER;
  BEGIN RETURN 0
  END Length;

  PROCEDURE (fs: FileSystem) Date*(f: File): INTEGER;
  BEGIN RETURN 0
  END Date;

  PROCEDURE (fs: FileSystem) CreateDir*(path: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN res := -1
  END CreateDir;

  PROCEDURE (fs: FileSystem) RemoveDir*(path: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN res := -1
  END RemoveDir;

  (* byte pos of f into x: FALSE at or past the end, or failed *)
  PROCEDURE (fs: FileSystem) ReadByte*(f: File; pos: INTEGER; VAR x: BYTE): BOOLEAN;
  BEGIN RETURN FALSE
  END ReadByte;

  (* x at byte pos of f, pos at most its length (which it then grows) *)
  PROCEDURE (fs: FileSystem) WriteByte*(f: File; pos: INTEGER; x: BYTE): BOOLEAN;
  BEGIN RETURN FALSE
  END WriteByte;

  (* --- File systems --- *)

  (* The file system Init and Format make for a device. *)
  PROCEDURE Install*(m: Maker);
  BEGIN maker := m
  END Install;

  (* fs, if it mounts, as the one in use: TRUE if it did *)
  PROCEDURE Mount*(fs: FileSystem): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN
    ok := (fs # NIL) & fs.Mount();
    IF ok THEN mounted := fs END
  RETURN ok
  END Mount;

  (* The file system on d, if it has one, in use; NIL: none in use. *)
  PROCEDURE Init*(d: BlockDriver.BlockDriver);
    VAR ok: BOOLEAN;
  BEGIN
    mounted := NIL;
    IF (d # NIL) & (maker # NIL) THEN ok := Mount(maker(d)) END
  END Init;

  (* An empty file system written to d. *)
  PROCEDURE Format*(d: BlockDriver.BlockDriver);
    VAR fs: FileSystem; ok: BOOLEAN;
  BEGIN
    IF (d # NIL) & (maker # NIL) THEN fs := maker(d); ok := fs.Format() END
  END Format;

  (* --- Files --- *)

  PROCEDURE Old*(name: ARRAY OF CHAR): File;
    VAR f: File;
  BEGIN
    IF mounted # NIL THEN f := mounted.Old(name) ELSE f := NIL END
  RETURN f
  END Old;

  PROCEDURE New*(name: ARRAY OF CHAR): File;
    VAR f: File;
  BEGIN
    IF mounted # NIL THEN f := mounted.New(name) ELSE f := NIL END
  RETURN f
  END New;

  PROCEDURE Register*(f: File);
  BEGIN IF f # NIL THEN f.fs.Register(f) END
  END Register;

  PROCEDURE Close*(f: File);
  BEGIN IF f # NIL THEN f.fs.Close(f) END
  END Close;

  PROCEDURE Delete*(name: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN
    IF mounted # NIL THEN mounted.Delete(name, res) ELSE res := -1 END
  END Delete;

  PROCEDURE Rename*(old, new: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN
    IF mounted # NIL THEN mounted.Rename(old, new, res) ELSE res := -1 END
  END Rename;

  PROCEDURE Length*(f: File): INTEGER;
    VAR n: INTEGER;
  BEGIN
    IF f # NIL THEN n := f.fs.Length(f) ELSE n := 0 END
  RETURN n
  END Length;

  PROCEDURE Date*(f: File): INTEGER;
    VAR n: INTEGER;
  BEGIN
    IF f # NIL THEN n := f.fs.Date(f) ELSE n := 0 END
  RETURN n
  END Date;

  (* --- Directories --- *)

  PROCEDURE CreateDir*(path: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN
    IF mounted # NIL THEN mounted.CreateDir(path, res) ELSE res := -1 END
  END CreateDir;

  PROCEDURE RemoveDir*(path: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN
    IF mounted # NIL THEN mounted.RemoveDir(path, res) ELSE res := -1 END
  END RemoveDir;

  (* --- Riders --- *)

  PROCEDURE Set*(VAR r: Rider; f: File; pos: INTEGER);
  BEGIN
    r.file := f; r.eof := FALSE; r.res := 0;
    IF pos < 0 THEN r.pos := 0
    ELSIF (f # NIL) & (pos > Length(f)) THEN r.pos := Length(f)
    ELSE r.pos := pos
    END
  END Set;

  PROCEDURE Pos*(VAR r: Rider): INTEGER;
  BEGIN RETURN r.pos
  END Pos;

  PROCEDURE Base*(VAR r: Rider): File;
  BEGIN RETURN r.file
  END Base;

  PROCEDURE Read*(VAR r: Rider; VAR x: BYTE);
  BEGIN
    IF (r.file # NIL) & r.file.fs.ReadByte(r.file, r.pos, x) THEN INC(r.pos)
    ELSE x := 0; r.eof := TRUE
    END
  END Read;

  PROCEDURE ReadInt*(VAR r: Rider; VAR x: INTEGER);
    VAR lo, hi: BYTE;
  BEGIN
    Read(r, lo); Read(r, hi);
    x := ORA(lo, ASL(hi, 8))
  END ReadInt;

  PROCEDURE ReadString*(VAR r: Rider; VAR x: ARRAY OF CHAR);
    VAR i: INTEGER; b: BYTE;
  BEGIN
    i := 0;
    REPEAT
      Read(r, b);
      IF i < LEN(x) - 1 THEN x[i] := CHR(b); INC(i) END
    UNTIL (b = 0) OR r.eof;
    x[i] := 0X
  END ReadString;

  PROCEDURE ReadBytes*(VAR r: Rider; VAR x: ARRAY OF BYTE; n: INTEGER);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < n) & ~r.eof DO Read(r, x[i]); INC(i) END;
    r.res := n - i
  END ReadBytes;

  PROCEDURE Write*(VAR r: Rider; x: BYTE);
  BEGIN
    IF r.file # NIL THEN
      IF r.file.fs.WriteByte(r.file, r.pos, x) THEN INC(r.pos) ELSE r.res := -1 END
    END
  END Write;

  PROCEDURE WriteInt*(VAR r: Rider; x: INTEGER);
  BEGIN
    Write(r, AND(x, 0FFH));
    Write(r, AND(LSR(x, 8), 0FFH))
  END WriteInt;

  PROCEDURE WriteString*(VAR r: Rider; x: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(x)) & (x[i] # 0X) DO Write(r, ORD(x[i])); INC(i) END;
    Write(r, 0)
  END WriteString;

  PROCEDURE WriteBytes*(VAR r: Rider; VAR x: ARRAY OF BYTE; n: INTEGER);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE i < n DO Write(r, x[i]); INC(i) END
  END WriteBytes;

BEGIN
  mounted := NIL; maker := NIL
END Files.
