MODULE ASB; (* Base of the 65xx assembler: values and the symbol table.

   Port of as/src/value.c and of the symbol file reader of as/src/as.c,
   shaped after the Oberon compiler's ORB.

   A symbol is an Object holding a Value. Objects live in scopes: the
   universe of predefined names, the scope of the program, and a scope for
   every block and macro call the interpreter (ASI) enters. A label also
   is a scope: its local labels are its descendants, and so are the
   exports of an imported module. All of them are found with ThisIn, so
   "Label.local" and "Module.Export" are one and the same notation.

   Scopes persist from pass to pass. A value assigned in one pass is the
   estimate a forward reference sees in the next. *)

  IMPORT Files, ASH, ASS;

  CONST
    (* value forms *)
    Undef* = 0; Int* = 1; Real* = 2; Str* = 3;
    (* what an Int is relative to, in a .816 module: the loader adds the
       module's code or data address to it (Value.base) *)
    Abs* = 0; CodeBase* = 1; DataBase* = 2; Mixed* = 3;   (* Mixed: not relocatable *)
    Mod* = 4;        (* an imported module; only its exports have values *)

    Forever* = 7FFFH;  (* stamp of a predefined symbol: it is never redefined *)

    maxImports* = 32;
    maxPar* = 8;     (* parameters of a declared procedure *)
    maxScopes = 32;  (* nesting of blocks and macro calls *)
    HashSize = 251;

    (* symbol files: object classes and type forms of ORB *)
    Const = 1; Var = 2; Typ = 5; Meth = 9;
    IntF* = 4; RealF = 5; Pointer = 7; Proc* = 10; Array* = 12; Record* = 13; Intfc = 14;
    NoTyp* = 9;      (* type reference of a procedure without result *)
    maxRef = 64;

  TYPE
    String* = POINTER TO StringDesc;
    StringDesc* = RECORD
      len*: INTEGER;
      s*: ARRAY ASS.StrLen OF CHAR
    END;

    Value* = RECORD
      form*: INTEGER;
      i*: LONGINT;
      base*: INTEGER;      (* Abs, CodeBase, DataBase or Mixed *)
      r*: REAL;
      s*: String
    END;

    Object* = POINTER TO ObjDesc;
    ObjDesc* = RECORD
      name*: ASS.Ident;
      val*: Value;
      expo*: BOOLEAN;      (* marked for export with "*" *)
      rdo*: BOOLEAN;       (* defined with LET *)
      stamp*: INTEGER;     (* the pass that last defined it *)
      dsc*: Object;        (* local labels or module exports *)
      next: Object;        (* in its scope *)
      link*: Object        (* in the result of Sorted *)
    END;

    (* an imported module, for the import table of a .816 file *)
    Import* = RECORD
      name*: ASS.Ident;
      key*: LONGINT
    END;

    (* an Oberon type, for the symbol file: a predeclared one, LONGINT, an
       array (len < 0: open), a record or a procedure type, declared with
       ".type" or not *)
    Type* = POINTER TO TypeDesc;
    Field* = POINTER TO FieldDesc;
    Signature* = POINTER TO SigDesc;
    TypeDesc* = RECORD
      form*: INTEGER;      (* ORB's: IntF, RealF, ..., Array, Record *)
      ref*: INTEGER;       (* of a predeclared type, else 0 *)
      len*: INTEGER;       (* an array's *)
      size*: INTEGER;
      base*: Type;         (* an array's elements *)
      fields*: Field;      (* a record's, in order *)
      sig*: Signature;     (* a procedure type's parameters and result *)
      name*: ASS.Ident;    (* declared with ".type", else empty *)
      td*: INTEGER;        (* a record's descriptor: its offset in the data *)
      out*: INTEGER;       (* its reference in the symbol file being written *)
      next*: Type          (* in types *)
    END;
    FieldDesc* = RECORD
      name*: ASS.Ident;
      type*: Type;
      off*: INTEGER;
      next*: Field
    END;

    (* signature of an exported procedure, declared with ".proc" so that
       the symbol file tells Oberon importers how to call it, or of a
       procedure type *)
    SigDesc* = RECORD
      name*: ASS.Ident;
      nofpar*: INTEGER;
      partype*: ARRAY maxPar OF Type;
      parvar*: ARRAY maxPar OF BOOLEAN;
      restype*: Type;      (* NIL: none *)
      next: Signature
    END;

  VAR
    imports*: ARRAY maxImports OF Import;
    nofImports*: INTEGER;

    universe, topScope: Object;
    (* the program's scope holds every global symbol, so it is hashed;
       the other scopes are short lists *)
    hash: ARRAY HashSize OF Object;
    scopes: ARRAY maxScopes OF Object;   (* open scopes, innermost last *)
    nofScopes: INTEGER;
    sigs: Signature;
    types*: Type;                        (* declared with ".type", in order *)
    lastType: Type;
    predef: ARRAY 8 OF Type;             (* BYTE .. SET, LONGINT *)

    version: INTEGER;                    (* of the symbol file being read *)
    forms: ARRAY maxRef OF INTEGER;      (* form of each type read from it *)

  (* --- values --- *)

  PROCEDURE SetInt*(VAR v: Value; i: LONGINT);
  BEGIN v.form := Int; v.i := i; v.s := NIL; v.base := Abs
  END SetInt;

  PROCEDURE SetReal*(VAR v: Value; r: REAL);
  BEGIN v.form := Real; v.r := r; v.s := NIL; v.base := Abs
  END SetReal;

  PROCEDURE SetStr*(VAR v: Value; s: String);
  BEGIN v.form := Str; v.s := s; v.base := Abs
  END SetStr;

  (* A new string of the first len characters of s. *)
  PROCEDURE NewString*(s: ARRAY OF CHAR; len: INTEGER): String;
    VAR str: String; i: INTEGER;
  BEGIN NEW(str);
    IF len > ASS.StrLen - 1 THEN len := ASS.StrLen - 1 END;
    i := 0;
    WHILE i < len DO str.s[i] := s[i]; INC(i) END;
    str.s[len] := 0X; str.len := len;
    RETURN str
  END NewString;

  (* --- scopes --- *)

  PROCEDURE Hash(name: ARRAY OF CHAR): INTEGER;
    VAR i, h: INTEGER;
  BEGIN i := 0; h := 0;
    WHILE name[i] # 0X DO h := (h * 31 + ORD(name[i])) MOD HashSize; INC(i) END;
    RETURN h
  END Hash;

  (* The object called name in scope, NIL if there is none. *)
  PROCEDURE ThisIn*(scope: Object; name: ARRAY OF CHAR): Object;
    VAR obj: Object;
  BEGIN
    IF scope = topScope THEN obj := hash[Hash(name)] ELSE obj := scope.dsc END;
    WHILE (obj # NIL) & (obj.name # name) DO obj := obj.next END;
    RETURN obj
  END ThisIn;

  (* The object called name in scope, created if there is none. *)
  PROCEDURE NewIn*(scope: Object; name: ARRAY OF CHAR): Object;
    VAR obj: Object; h: INTEGER;
  BEGIN obj := ThisIn(scope, name);
    IF obj = NIL THEN
      NEW(obj); ASH.Copy(name, obj.name); obj.val.form := Undef; obj.val.base := Abs; obj.stamp := -1;
      IF scope = topScope THEN h := Hash(name); obj.next := hash[h]; hash[h] := obj
      ELSE obj.next := scope.dsc; scope.dsc := obj
      END
    END;
    RETURN obj
  END NewIn;

  (* The object called name that is visible here: the innermost of the
     open scopes that has one, then the universe. *)
  PROCEDURE This*(name: ARRAY OF CHAR): Object;
    VAR obj: Object; i: INTEGER;
  BEGIN obj := NIL; i := nofScopes;
    WHILE (obj = NIL) & (i > 0) DO DEC(i); obj := ThisIn(scopes[i], name) END;
    IF obj = NIL THEN obj := ThisIn(universe, name) END;
    RETURN obj
  END This;

  (* The object called name in the innermost open scope. *)
  PROCEDURE New*(name: ARRAY OF CHAR): Object;
  BEGIN RETURN NewIn(scopes[nofScopes - 1], name)
  END New;

  (* An anonymous object to serve as the scope of a block or macro call. *)
  PROCEDURE NewScope*(): Object;
    VAR obj: Object;
  BEGIN NEW(obj); obj.name[0] := 0X; obj.val.form := Undef; obj.val.base := Abs;
    RETURN obj
  END NewScope;

  PROCEDURE OpenScope*(scope: Object): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN ok := nofScopes < maxScopes;
    IF ok THEN scopes[nofScopes] := scope; INC(nofScopes) END;
    RETURN ok
  END OpenScope;

  PROCEDURE CloseScope*;
  BEGIN
    IF nofScopes > 1 THEN DEC(nofScopes); scopes[nofScopes] := NIL END
  END CloseScope;

  (* Close all scopes but the program's; done at the start of a pass. *)
  PROCEDURE ResetScopes*;
  BEGIN
    WHILE nofScopes > 1 DO CloseScope END
  END ResetScopes;

  PROCEDURE Top*(): Object;
  BEGIN RETURN topScope
  END Top;

  (* --- enumeration in alphabetical order --- *)

  PROCEDURE Merge(a, b: Object): Object;
    VAR head, tail, t: Object;
  BEGIN head := NIL; tail := NIL;
    WHILE (a # NIL) & (b # NIL) DO
      IF b.name < a.name THEN t := b; b := b.link ELSE t := a; a := a.link END;
      IF tail = NIL THEN head := t ELSE tail.link := t END;
      tail := t
    END;
    IF a = NIL THEN a := b END;
    IF tail = NIL THEN head := a ELSE tail.link := a END;
    RETURN head
  END Merge;

  (* merge sort of the n objects linked from list *)
  PROCEDURE Sort(list: Object; n: INTEGER): Object;
    VAR a, b, p: Object; i, h: INTEGER;
  BEGIN
    IF n > 1 THEN h := n DIV 2; p := list; i := 1;
      WHILE i < h DO p := p.link; INC(i) END;
      b := p.link; p.link := NIL;
      a := Sort(list, h); b := Sort(b, n - h);
      list := Merge(a, b)
    END;
    RETURN list
  END Sort;

  (* The objects of scope ordered by name and linked by their link
     fields; n is their number. *)
  PROCEDURE Sorted*(scope: Object; VAR n: INTEGER): Object;
    VAR list, obj: Object; h: INTEGER;
  BEGIN list := NIL; n := 0;
    IF scope = topScope THEN
      FOR h := 0 TO HashSize - 1 DO
        obj := hash[h];
        WHILE obj # NIL DO obj.link := list; list := obj; INC(n); obj := obj.next END
      END
    ELSE obj := scope.dsc;
      WHILE obj # NIL DO obj.link := list; list := obj; INC(n); obj := obj.next END
    END;
    RETURN Sort(list, n)
  END Sorted;

  (* --- procedure signatures --- *)

  PROCEDURE NewSignature*(name: ARRAY OF CHAR): Signature;
    VAR s: Signature;
  BEGIN NEW(s); ASH.Copy(name, s.name); s.nofpar := 0; s.restype := NIL;
    s.next := sigs; sigs := s;
    RETURN s
  END NewSignature;

  (* sig, a procedure type's, for the exported procedure name *)
  PROCEDURE AddSignature*(name: ARRAY OF CHAR; sig: Signature);
    VAR s: Signature; i: INTEGER;
  BEGIN s := NewSignature(name); s.nofpar := sig.nofpar; s.restype := sig.restype;
    FOR i := 0 TO sig.nofpar - 1 DO s.partype[i] := sig.partype[i]; s.parvar[i] := sig.parvar[i] END
  END AddSignature;

  PROCEDURE ThisSignature*(name: ARRAY OF CHAR): Signature;
    VAR s: Signature;
  BEGIN s := sigs;
    WHILE (s # NIL) & (s.name # name) DO s := s.next END;
    RETURN s
  END ThisSignature;

  (* --- types --- *)

  PROCEDURE NewType*(form, size: INTEGER): Type;
    VAR t: Type;
  BEGIN NEW(t); t.form := form; t.size := size; t.ref := 0; t.len := 0;
    t.base := NIL; t.fields := NIL; t.sig := NIL; t.name[0] := 0X; t.td := 0; t.out := 0; t.next := NIL;
    RETURN t
  END NewType;

  (* a procedure type, without parameters or result as yet *)
  PROCEDURE NewProcType*(): Type;
    VAR t: Type; s: Signature;
  BEGIN t := NewType(Proc, 4); NEW(s); s.name[0] := 0X; s.nofpar := 0; s.restype := NIL;
    s.next := NIL; t.sig := s;
    RETURN t
  END NewProcType;

  (* Enter t, made by NewType, as the type called name. *)
  PROCEDURE DeclareType*(t: Type; name: ARRAY OF CHAR);
  BEGIN ASH.Copy(name, t.name);
    IF lastType = NIL THEN types := t ELSE lastType.next := t END;
    lastType := t
  END DeclareType;

  (* Add a field of type ft to record t, laid out as ORP lays it out: a
     field larger than a byte at an even offset. *)
  PROCEDURE AddField*(t: Type; name: ARRAY OF CHAR; ft: Type);
    VAR f, g: Field;
  BEGIN NEW(f); ASH.Copy(name, f.name); f.type := ft; f.next := NIL;
    IF ft.size > 1 THEN t.size := (t.size + 1) DIV 2 * 2 END;
    f.off := t.size; t.size := t.size + ft.size;
    IF t.fields = NIL THEN t.fields := f
    ELSE g := t.fields;
      WHILE g.next # NIL DO g := g.next END;
      g.next := f
    END
  END AddField;

  (* The type called name: a basic Oberon type, LONGINT, or one declared
     with ".type"; NIL if there is none. The basic types carry the
     references ORB gives the predeclared types, so a symbol file can
     refer to them without describing them. *)
  PROCEDURE ThisType*(name: ARRAY OF CHAR): Type;
    VAR t: Type;
  BEGIN t := types;
    WHILE (t # NIL) & (t.name # name) DO t := t.next END;
    IF t = NIL THEN
      IF ASH.Same(name, "BYTE") THEN t := predef[1]
      ELSIF ASH.Same(name, "BOOLEAN") THEN t := predef[2]
      ELSIF ASH.Same(name, "CHAR") THEN t := predef[3]
      ELSIF ASH.Same(name, "INTEGER") THEN t := predef[4]
      ELSIF ASH.Same(name, "REAL") THEN t := predef[5]
      ELSIF ASH.Same(name, "SET") THEN t := predef[6]
      ELSIF ASH.Same(name, "LONGINT") THEN t := predef[7]
      END
    END;
    RETURN t
  END ThisType;

  PROCEDURE Predef(ref, form, size: INTEGER);
  BEGIN predef[ref] := NewType(form, size); predef[ref].ref := ref
  END Predef;

  (* --- symbol files --- *)

  PROCEDURE ReadByte(VAR R: Files.Rider; VAR x: INTEGER);
    VAR b: BYTE;
  BEGIN Files.ReadByte(R, b); x := b
  END ReadByte;

  PROCEDURE Read(VAR R: Files.Rider; VAR x: INTEGER);
    VAR b: BYTE;
  BEGIN Files.ReadByte(R, b);
    IF b < 128 THEN x := b ELSE x := b - 256 END
  END Read;

  PROCEDURE ReadLong(VAR R: Files.Rider; VAR x: LONGINT);
    VAR b0, b1, b2, b3: BYTE;
  BEGIN
    Files.ReadByte(R, b0); Files.ReadByte(R, b1); Files.ReadByte(R, b2); Files.ReadByte(R, b3);
    x := b3; x := ((x * 100H + b2) * 100H + b1) * 100H + b0
  END ReadLong;

  PROCEDURE ReadNum(VAR R: Files.Rider; VAR x: LONGINT);
    VAR b: BYTE; n, m: LONGINT;
  BEGIN n := 0; m := 1;
    Files.ReadByte(R, b);
    WHILE (b >= 128) & ~R.eof DO
      n := n + (b - 128) * m; m := m * 128;
      Files.ReadByte(R, b)
    END;
    n := n + b * m; m := m * 128;
    IF b >= 64 THEN n := n - m END;
    x := n
  END ReadNum;

  PROCEDURE ReadString(VAR R: Files.Rider; VAR s: ARRAY OF CHAR);
    VAR b: BYTE; i: INTEGER;
  BEGIN i := 0;
    Files.ReadByte(R, b);
    WHILE (b # 0) & ~R.eof DO
      IF i < LEN(s) - 1 THEN s[i] := CHR(b); INC(i) END;
      Files.ReadByte(R, b)
    END;
    s[i] := 0X
  END ReadString;

  (* Skip the description of a type and deliver its form. The assembler
     has no use for types, except that the form decides how the value of
     a constant is stored. Handles the layouts of version 1 (the C
     compiler) and version 6 (ORB.OutType). *)
  PROCEDURE SkipType(VAR R: Files.Rider; VAR form: INTEGER);
    VAR ref, class, k, f: INTEGER; n: LONGINT;
      name: ASS.Ident; mname: ARRAY 128 OF CHAR;
  BEGIN
    Read(R, ref);
    IF ref < 0 THEN
      IF -ref < maxRef THEN form := forms[-ref] ELSE form := 0 END
    ELSE
      Read(R, form);
      IF version >= 6 THEN
        IF form = IntF THEN ReadNum(R, n) END;
        IF form = Pointer THEN Read(R, k); SkipType(R, f)
        ELSIF form = Array THEN SkipType(R, f); ReadNum(R, n); ReadNum(R, n)
        ELSIF form = Record THEN
          SkipType(R, f);
          ReadNum(R, n); ReadNum(R, n); ReadNum(R, n); ReadNum(R, n);
          Read(R, class);
          WHILE (class # 0) & ~R.eof DO
            IF class = Meth THEN
              ReadString(R, name); Read(R, k); Read(R, k);
              ReadNum(R, n); ReadNum(R, n); ReadString(R, mname); SkipType(R, f)
            ELSE ReadString(R, name); SkipType(R, f); ReadNum(R, n)
            END;
            Read(R, class)
          END;
          Read(R, class);
          WHILE (class # 0) & ~R.eof DO SkipType(R, f); Read(R, class) END
        ELSIF form = Intfc THEN
          Read(R, class);
          WHILE (class # 0) & ~R.eof DO
            ReadString(R, name); ReadNum(R, n); SkipType(R, f); Read(R, class)
          END;
          Read(R, class);
          WHILE (class # 0) & ~R.eof DO SkipType(R, f); Read(R, class) END
        ELSIF form = Proc THEN
          Read(R, k); SkipType(R, f);
          Read(R, class);
          WHILE (class # 0) & ~R.eof DO Read(R, k); SkipType(R, f); Read(R, class) END
        END
      ELSE
        IF form = Pointer THEN SkipType(R, f)
        ELSIF form = Array THEN SkipType(R, f); ReadNum(R, n); ReadNum(R, n)
        ELSIF form = Record THEN
          SkipType(R, f);
          ReadNum(R, n); ReadNum(R, n); ReadNum(R, n);
          Read(R, class);
          WHILE (class # 0) & ~R.eof DO  (*a hidden field has no name and no type*)
            ReadString(R, name);
            IF name[0] # 0X THEN SkipType(R, f) END;
            ReadNum(R, n);
            Read(R, class)
          END
        ELSIF form = Proc THEN
          SkipType(R, f);
          Read(R, class);
          WHILE (class # 0) & ~R.eof DO Read(R, k); SkipType(R, f); Read(R, class) END
        END
      END;
      IF (ref > 0) & (ref < maxRef) THEN forms[ref] := form END;
      ReadString(R, mname);
      IF mname[0] # 0X THEN  (*re-exported type: key and name follow*)
        ReadLong(R, n); ReadString(R, name)
      END
    END
  END SkipType;

  (* Import module modid: read its symbol file and enter the module with
     its exports into the program's scope. An exported procedure or
     variable gets the value mno * 10000H + n, where mno is the number of
     the import and n the export number, or the address for a variable;
     in a call the loader replaces it by the real address. A constant
     gets its own value.

     The symbol file is looked for beside the output file, then where
     include files are looked for. *)
  PROCEDURE ImportModule*(modid: ARRAY OF CHAR; outName: ARRAY OF CHAR);
    VAR F: Files.File; R: Files.Rider;
      path, fname: ASH.Path; from: ASH.Path;
      mod, obj: Object;
      key, n: LONGINT;
      class, form, k, mno, i: INTEGER;
      name, modname: ASS.Ident;
  BEGIN
    mod := ThisIn(topScope, modid);
    IF (mod # NIL) & (mod.val.form = Mod) THEN (*already imported*)
    ELSIF nofImports >= maxImports THEN ASS.Mark("too many imports")
    ELSE
      ASH.Copy(modid, fname); ASH.Append(".smb", fname);
      ASH.Dir(outName, path); ASH.Append(fname, path);
      F := Files.Old(path);
      IF F = NIL THEN
        IF ASS.src # NIL THEN from := ASS.src.name ELSE from[0] := 0X END;
        F := ASS.Locate(fname, from, path)
      END;
      IF F = NIL THEN ASS.MarkS("cannot open symbol file ", fname)
      ELSE
        Files.Set(R, F, 0);
        ReadLong(R, key); ReadLong(R, key);
        ReadString(R, modname);
        ReadByte(R, version);
        IF (version # 1) & (version # 6) THEN ASS.MarkS("unsupported symbol file version: ", fname)
        ELSE
          imports[nofImports].key := key; ASH.Copy(modid, imports[nofImports].name);
          INC(nofImports); mno := nofImports;
          mod := NewIn(topScope, modid); mod.val.form := Mod; mod.val.base := Abs; mod.dsc := NIL;
          (* the predeclared types: reference = form, but BYTE is an integer *)
          FOR i := 0 TO maxRef - 1 DO forms[i] := i END;
          forms[1] := IntF;
          ReadByte(R, class);
          WHILE (class # 0) & ~R.eof DO
            ReadString(R, name);
            SkipType(R, form);
            IF class = Typ THEN  (*bases of pointer types declared before it*)
              Read(R, k);
              WHILE (k # 0) & ~R.eof DO Read(R, k) END
            ELSE
              IF (class = Const) & (form = RealF) THEN ReadLong(R, n) ELSE ReadNum(R, n) END;
              obj := NewIn(mod, name);
              IF (class = Const) & (form # Proc) THEN SetInt(obj.val, n)
              ELSE SetInt(obj.val, mno * 10000H + n MOD 10000H)
              END
            END;
            ReadByte(R, class)
          END
        END;
        Files.Close(F)
      END
    END
  END ImportModule;

  (* --- initialisation --- *)

  PROCEDURE Enter(name: ARRAY OF CHAR; val: LONGINT);
    VAR obj: Object;
  BEGIN obj := NewIn(universe, name); SetInt(obj.val, val); obj.rdo := TRUE; obj.stamp := Forever
  END Enter;

  PROCEDURE Init*;
    VAR h: INTEGER;
  BEGIN
    FOR h := 0 TO HashSize - 1 DO hash[h] := NIL END;
    topScope := NewScope(); scopes[0] := topScope; nofScopes := 1;
    nofImports := 0; sigs := NIL; types := NIL; lastType := NIL
  END Init;

BEGIN
  universe := NewScope(); topScope := NIL;
  Enter("off", 0); Enter("on", 1);
  Enter("false", 0); Enter("true", 1);
  Enter("no", 0); Enter("yes", 1);
  Enter("__65AS__", 100);  (* version 0.1.0 as major * 10000 + minor * 100 + patch *)
  (* sizes of oc816's: ORG.IntSize, LongSize, RealSize, SetSize *)
  Predef(1, 1, 1); Predef(2, 2, 1); Predef(3, 3, 1); Predef(4, IntF, 2);
  Predef(5, RealF, 4); Predef(6, 6, 2);
  predef[7] := NewType(IntF, 4);   (* LONGINT: no reference, described where used *)
  Init
END ASB.
