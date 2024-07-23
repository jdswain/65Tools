#ifndef OCB_H
#define OCB_H

#include <stdbool.h>

void base_init(void);
void base_Import(const char *modid, const char *modid1);
void base_export(char *module, bool newSF, long key); /* Temp */

#define maxTypTab 64
/* Class values */
#define Head 0
#define Const 1
#define Var 2
#define Par 3
#define Fld 4
#define Typ 5
#define SProc 6
#define SFunc 7
#define Mod 8

/* Form values */
#define Byte 1
#define Bool 2
#define Char 3
#define Int 4
#define Real 5
#define Set 6
#define Pointer 7
#define NilTyp 8
#define NoTyp 9
#define Proc 10
#define String 11
#define Array 12
#define Record 13

struct Object {
  char class;
  char exno;
  bool expo; /* Exported */
  bool rdo; /* Read only */
  int lev;
  struct Object* next;
  struct Object* dsc;
  struct Type *type;
  char *name;
  long val;
};

struct Module {
  struct Object; /* C11 */
  const char *orgname;
};

struct Type {
  int form;
  int ref; /* Only used for import/export */
  int mno;
  int nofpar; /* For procedures, extension level for records */
  long len; /* For arrays len < 0 => open array; for records: adr of descriptor */
  struct Object *dsc;
  struct Object *typobj;
  struct Type *base; /* For arrays, records, pointers */
  long size; /* In bytes */
};

  /* Object classes and the meaning of "val":
    class    val
    ----------
    Var      address
    Par      address
    Const    value
    Fld      offset
    Typ      type descriptor (TD) address
    SProc    inline code number
    SFunc    inline code number
    Mod      key

  Type forms and the meaning of "dsc" and "base":
    form     dsc      base
    ------------------------
    Pointer  -        type of dereferenced object
    Proc     params   result type
    Array    -        type of elements
    Record   fields   extension */

extern struct Object *topScope;
extern struct Object *universe;
extern struct Object *systemScope;
extern struct Type *byteType;
extern struct Type *boolType;
extern struct Type *charType;
extern struct Type *intType;
extern struct Type *realType;
extern struct Type *setType;
extern struct Type *nilType;
extern struct Type *noType;
extern struct Type *strType;
extern int nofmod;
extern int Ref;
extern struct Type *typtab[maxTypTab];

/* Insert new Object with name id */
struct Object *base_NewObj(char *id, int class);

/* The Object matching the current scanner symbol */
struct Object *base_thisObj(void);

struct Object *base_thisimport(struct Object *mod);

struct Object *base_thisfield(struct Type *rec);

void base_OpenScope(void);

void base_CloseScope(void);

  /*------------------------------- Import ---------------------------------*/


/*
  
  PROCEDURE MakeFileName*(VAR FName: ORS.Ident; name, ext: ARRAY OF CHAR);
    VAR i, j: INTEGER;
  BEGIN i := 0; j := 0;  (*assume name suffix less than 4 characters*)
    WHILE (i < ORS.IdLen-5) & (name[i] > 0X) DO FName[i] := name[i]; INC(i) END ;
    REPEAT FName[i]:= ext[j]; INC(i); INC(j) UNTIL ext[j] = 0X;
    FName[i] := 0X
  END MakeFileName;
  
  PROCEDURE ThisModule(name, orgname: ORS.Ident; decl: BOOLEAN; key: LONGINT): Object;
    VAR mod: Module; obj, obj1: Object;
  BEGIN obj1 := topScope; obj := obj1.next;  (*search for module*)
    WHILE (obj # NIL) & (obj(Module).orgname # orgname) DO obj1 := obj; obj := obj1.next END ;
    IF obj = NIL THEN  (*new module, search for alias*)
      obj := topScope.next;
      WHILE (obj # NIL) & (obj.name # name) DO obj := obj.next END ;
      IF obj = NIL THEN (*insert new module*)
        NEW(mod); mod.class := Mod; mod.rdo := FALSE;
        mod.name := name; mod.orgname := orgname; mod.val := key;
        mod.lev := nofmod; INC(nofmod); mod.dsc := NIL; mod.next := NIL;
        IF decl THEN mod.type := noType ELSE mod.type := nilType END ;
        obj1.next := mod; obj := mod
      ELSIF decl THEN
        IF obj.type.form = NoTyp THEN ORS.Mark("mult def") ELSE ORS.Mark("invalid import order") END
      ELSE ORS.Mark("conflict with alias")
      END
    ELSIF decl THEN (*module already present, explicit import by declaration*)
      IF  obj.type.form = NoTyp THEN ORS.Mark("mult def") ELSE ORS.Mark("invalid import order") END
    END ;
    RETURN obj
  END ThisModule;
  
  PROCEDURE Read(VAR R: Files.Rider; VAR x: INTEGER);
    VAR b: BYTE;
  BEGIN Files.ReadByte(R, b);
    IF b < 80H THEN x := b ELSE x := b - 100H END
  END Read;
  
  PROCEDURE InType(VAR R: Files.Rider; thismod: Object; VAR T: Type);
    VAR key: LONGINT;
      ref, class, form, np, readonly: INTEGER;
      fld, par, obj, mod, last: Object;
      t: Type;
      name, modname: ORS.Ident;
  BEGIN Read(R, ref);
    IF ref < 0 THEN T := typtab[-ref]  (*already read*)
    ELSE NEW(t); T := t; typtab[ref] := t; t.mno := thismod.lev;
      Read(R, form); t.form := form;
      IF form = Pointer THEN InType(R, thismod, t.base); t.size := 4
      ELSIF form = Array THEN
        InType(R, thismod, t.base); Files.ReadNum(R, t.len); Files.ReadNum(R, t.size)
      ELSIF form = Record THEN
        InType(R, thismod, t.base);
        IF t.base.form = NoTyp THEN t.base := NIL; obj := NIL ELSE obj := t.base.dsc END ;
        Files.ReadNum(R, t.len); (*TD adr/exno*)
        Files.ReadNum(R, t.nofpar);  (*ext level*)
        Files.ReadNum(R, t.size);
        Read(R, class); last := NIL;
        WHILE class # 0 DO  (*fields*)
          NEW(fld); fld.class := class; Files.ReadString(R, fld.name);
          IF last = NIL THEN t.dsc := fld ELSE last.next := fld END ;
          last := fld;
          IF fld.name[0] # 0X THEN fld.expo := TRUE; InType(R, thismod, fld.type) ELSE fld.expo := FALSE; fld.type := nilType END ;
          Files.ReadNum(R, fld.val); Read(R, class)
        END ;
        IF last = NIL THEN t.dsc := obj ELSE last.next := obj END
      ELSIF form = Proc THEN
        InType(R, thismod, t.base);
        obj := NIL; np := 0; Read(R, class);
        WHILE class # 0 DO  (*parameters*)
          NEW(par); par.class := class; Read(R, readonly); par.rdo := readonly = 1; 
          InType(R, thismod, par.type); par.next := obj; obj := par; INC(np); Read(R, class)
        END ;
        t.dsc := obj; t.nofpar := np; t.size := 4
      END ;
      Files.ReadString(R, modname);
      IF modname[0] #  0X THEN  (*re-import ========*)
        Files.ReadInt(R, key); Files.ReadString(R, name);
        mod := ThisModule(modname, modname, FALSE, key);
        obj := mod.dsc;  (*search type*)
        WHILE (obj # NIL) & (obj.name # name) DO obj := obj.next END ;
        IF obj # NIL THEN T := obj.type   (*type object found in object list of mod*)
        ELSE (*insert new type object in object list of mod*)
          NEW(obj); obj.name := name; obj.class := Typ; obj.next := mod.dsc; mod.dsc := obj; obj.type := t;
          t.mno := mod.lev; t.typobj := obj; T := t
        END ;
        typtab[ref] := T
      END
    END
  END InType;
  
  PROCEDURE Import*(VAR modid, modid1: ORS.Ident);
    VAR key: LONGINT; class, k: INTEGER;
      obj: Object;  t: Type;
      thismod: Object;
      modname, fname: ORS.Ident;
      F: Files.File; R: Files.Rider;
  BEGIN
    IF modid1 = "SYSTEM" THEN
      thismod := ThisModule(modid, modid1, TRUE,  key); DEC(nofmod);
      thismod.lev := 0; thismod.dsc := systemScope; thismod.rdo := TRUE
    ELSE MakeFileName(fname, modid1, ".smb"); F := Files.Old(fname);
      IF F # NIL THEN
        Files.Set(R, F, 0); Files.ReadInt(R, key); Files.ReadInt(R, key); Files.ReadString(R, modname);
        thismod := ThisModule(modid, modid1, TRUE, key); thismod.rdo := TRUE;
        Read(R, class); (*version key*)
        IF class # versionkey THEN ORS.Mark("wrong version") END ;
        Read(R, class);
        WHILE class # 0 DO
          NEW(obj); obj.class := class; Files.ReadString(R, obj.name);
          InType(R, thismod, obj.type); obj.lev := -thismod.lev;
          IF class = Typ THEN
            t := obj.type; t.typobj := obj; Read(R, k);  (*fixup bases of previously declared pointer types*)
            WHILE k # 0 DO typtab[k].base := t; Read(R, k) END
          ELSE
            IF class = Const THEN
              IF obj.type.form = Real THEN Files.ReadInt(R, obj.val) ELSE Files.ReadNum(R, obj.val) END
            ELSIF class = Var THEN Files.ReadNum(R, obj.val); obj.rdo := TRUE
            END
          END ;
          obj.next := thismod.dsc; thismod.dsc := obj; Read(R, class)
        END ;
      ELSE ORS.Mark("import not available")
      END
    END
  END Import;
  
  (*-------------------------------- Export ---------------------------------*)

  PROCEDURE Write(VAR R: Files.Rider; x: INTEGER);
  BEGIN Files.WriteByte(R, x)
  END Write;

  PROCEDURE OutType(VAR R: Files.Rider; t: Type);
    VAR obj, mod, fld, bot: Object;

    PROCEDURE OutPar(VAR R: Files.Rider; par: Object; n: INTEGER);
      VAR cl: INTEGER;
    BEGIN
      IF n > 0 THEN
        OutPar(R, par.next, n-1); cl := par.class;
        Write(R, cl);
        IF par.rdo THEN Write(R, 1) ELSE Write(R, 0) END ;
        OutType(R, par.type)
      END
    END OutPar;

    PROCEDURE FindHiddenPointers(VAR R: Files.Rider; typ: Type; offset: LONGINT);
      VAR fld: Object; i, n: LONGINT;
    BEGIN
      IF (typ.form = Pointer) OR (typ.form = NilTyp) THEN Write(R, Fld); Write(R, 0); Files.WriteNum(R, offset)
      ELSIF typ.form = Record THEN fld := typ.dsc;
        WHILE fld # NIL DO FindHiddenPointers(R, fld.type, fld.val + offset); fld := fld.next END
      ELSIF typ.form = Array THEN i := 0; n := typ.len;
        WHILE i < n DO FindHiddenPointers(R, typ.base, typ.base.size * i + offset); INC(i) END
      END
    END FindHiddenPointers;

  BEGIN
    IF t.ref > 0 THEN (*type was already output*) Write(R, -t.ref)
    ELSE obj := t.typobj;
      IF obj # NIL THEN Write(R, Ref); t.ref := Ref; INC(Ref) ELSE (*anonymous*) Write(R, 0) END ;
      Write(R, t.form);
      IF t.form = Pointer THEN OutType(R, t.base)
      ELSIF t.form = Array THEN OutType(R, t.base); Files.WriteNum(R, t.len); Files.WriteNum(R, t.size)
      ELSIF t.form = Record THEN
        IF t.base # NIL THEN OutType(R, t.base); bot := t.base.dsc ELSE OutType(R, noType); bot := NIL END ;
        IF obj # NIL THEN Files.WriteNum(R, obj.exno) ELSE Write(R, 0) END ;
        Files.WriteNum(R, t.nofpar); Files.WriteNum(R, t.size);
        fld := t.dsc;
        WHILE fld # bot DO  (*fields*)
          IF fld.expo THEN
            Write(R, Fld); Files.WriteString(R, fld.name); OutType(R, fld.type); Files.WriteNum(R, fld.val)  (*offset*)
          ELSE FindHiddenPointers(R, fld.type, fld.val)
          END ;
          fld := fld.next
        END ;
        Write(R, 0)
      ELSIF t.form = Proc THEN OutType(R, t.base); OutPar(R, t.dsc, t.nofpar); Write(R, 0)
      END ;
      IF (t.mno > 0) & (obj # NIL) THEN  (*re-export, output name*)
        mod := topScope.next;
        WHILE (mod # NIL) & (mod.lev # t.mno) DO mod := mod.next END ;
        IF mod # NIL THEN Files.WriteString(R, mod(Module).orgname); Files.WriteInt(R, mod.val); Files.WriteString(R, obj.name)
        ELSE ORS.Mark("re-export not found"); Write(R, 0)
        END
      ELSE Write(R, 0)
      END
    END
  END OutType;

  PROCEDURE Export*(VAR modid: ORS.Ident; VAR newSF: BOOLEAN; VAR key: LONGINT);
    VAR x, sum, oldkey: LONGINT;
      obj, obj0: Object;
      filename: ORS.Ident;
      F, F1: Files.File; R, R1: Files.Rider;
  BEGIN Ref := Record + 1; MakeFileName(filename, modid, ".smb");
    F := Files.New(filename); Files.Set(R, F, 0);
    Files.WriteInt(R, 0); (*placeholder*)
    Files.WriteInt(R, 0); (*placeholder for key to be inserted at the end*)
    Files.WriteString(R, modid); Write(R, versionkey);
    obj := topScope.next;
    WHILE obj # NIL DO
      IF obj.expo THEN
        Write(R, obj.class); Files.WriteString(R, obj.name);
        OutType(R, obj.type);
        IF obj.class = Typ THEN
          IF obj.type.form = Record THEN
            obj0 := topScope.next;  (*check whether this is base of previously declared pointer types*)
            WHILE obj0 # obj DO
              IF (obj0.type.form = Pointer) & (obj0.type.base = obj.type) & (obj0.type.ref > 0) THEN Write(R, obj0.type.ref) END ;
              obj0 := obj0.next
            END
          END ;
          Write(R, 0)
        ELSIF obj.class = Const THEN
          IF obj.type.form = Proc THEN Files.WriteNum(R, obj.exno)
          ELSIF obj.type.form = Real THEN Files.WriteInt(R, obj.val)
          ELSE Files.WriteNum(R, obj.val)
          END
        ELSIF obj.class = Var THEN Files.WriteNum(R, obj.exno)
        END
      END ;
      obj := obj.next
    END ;
    REPEAT Write(R, 0) UNTIL Files.Length(F) MOD 4 = 0;
    FOR Ref := Record+1 TO maxTypTab-1 DO typtab[Ref] := NIL END ;
    Files.Set(R, F, 0); sum := 0; Files.ReadInt(R, x);  (* compute key (checksum) *)
    WHILE ~R.eof DO sum := sum + x; Files.ReadInt(R, x) END ;
    F1 := Files.Old(filename); (*sum is new key*)
    IF F1 # NIL THEN Files.Set(R1, F1, 4); Files.ReadInt(R1, oldkey) ELSE oldkey := sum+1 END ;
    IF sum # oldkey THEN
      IF newSF OR (F1 = NIL) THEN
        key := sum; newSF := TRUE; Files.Set(R, F, 4); Files.WriteInt(R, sum); Files.Register(F)  (*insert checksum*)
      ELSE ORS.Mark("new symbol file inhibited")
      END
    ELSE newSF := FALSE; key := sum
    END
  END Export;
*/


struct Type *base_type(int ref, int form, long size);

#endif
