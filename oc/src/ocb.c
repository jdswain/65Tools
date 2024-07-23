#include "ocb.h"

#include "string.h"
#include "strings.h"

#include "buffered_file.h"
#include "memory.h"
#include "ocs.h"

struct Object *topScope;
struct Object *universe;
struct Object *systemScope;
struct Type *byteType;
struct Type *boolType;
struct Type *charType;
struct Type *intType;
struct Type *realType;
struct Type *setType;
struct Type *nilType;
struct Type *noType;
struct Type *strType;
int nofmod;
int Ref;
struct Type *typtab[maxTypTab];


struct Object *base_NewObj(char *id, int class) { /*insert new Object with name id*/
  struct Object *new;
  struct Object *x;

  x = topScope;
  while ((x->next != 0) && (strcmp(x->next->name,id) != 0)) {
	x = x->next;
  }
  if (x->next == 0) {
	new = as_malloc(sizeof(struct Object));
	new->name = id; 
	new->class = class;
	new->next = 0;
	new->rdo = false;
	new->dsc = 0;
	x->next = new;
	return new;
  } else {
	as_error("mult def: %s", id);
	return x->next;
  }
}

struct Object *base_thisObj(void) {
  struct Object *s;
  struct Object *x;

  s = topScope;
  do {
	x = s->next;
	while ((x != 0) && (strcmp(x->name, scanner_id) != 0)) {
	  x = x->next;
	}
	s = s->dsc;
  } while ((x == 0) && (s != 0));
  return x;
}

struct Object *base_thisimport(struct Object *mod) {
  struct Object *obj;

  if (mod->rdo) {
	if (mod->name[0] != 0) {
	  obj = mod->dsc;
	  while ((obj != 0) && (strcmp(obj->name, scanner_id) != 0)) {
		obj = obj->next;
	  }
	} else {
	  obj = 0;
	}
  } else {
	obj = 0;
  }
  return obj;
}

struct Object *base_thisfield(struct Type *rec) {
  struct Object *fld;

  fld = rec->dsc;
  while ((fld != 0) && (strcmp(fld->name, scanner_id) != 0)) {
	fld = fld->next;
  }
  return fld;
}

void base_OpenScope(void) {
  struct Object *s;

  s = as_malloc(sizeof(struct Object));
  s->class = Head;
  s->dsc = topScope;
  s->next = 0;
  topScope = s;
}

void base_CloseScope(void) {
  topScope = topScope->dsc;
  /* Memory leak */
}

/*------------------------------- Import ---------------------------------*/

void base_MakeFileName(char *FName, char *name, char *ext) {
  int i;
  int j;
  i = 0; j = 0;  /*assume name suffix less than 4 characters*/
  //  while (i < ORS.IdLen-5) & (name[i] > 0X) DO FName[i] := name[i]; INC(i) END ;
  //    REPEAT FName[i]:= ext[j]; INC(i); INC(j) UNTIL ext[j] = 0X;
  //FName[i] := 0X
}
  
struct Object *base_ThisModule(const char *name, const char *orgname, bool decl, long key) {
  struct Module *mod;
  struct Object *obj;
  struct Object *obj1;

  obj1 = topScope; obj = obj1->next;  /*search for module*/
  while ((obj != 0) && (((struct Module *)obj)->orgname != orgname)) {
	obj1 = obj; obj = obj1->next;
  }
  if (obj == 0) {  /*new module, search for alias*/
	obj = topScope->next;
	while ((obj != 0) && (obj->name != name)) {
	  obj = obj->next;
	}
	if (obj == 0) { /*insert new module*/
	  mod = as_malloc(sizeof(struct Module));
	  mod->class = Mod; mod->rdo = 0;
	  mod->name = name; mod->orgname = orgname; mod->val = key;
	  mod->lev = nofmod; nofmod += 1; mod->dsc = 0; mod->next = 0;
	  if (decl) {
		mod->type = noType;
	  } else {
		mod->type = nilType;
	  }
	  obj1->next = (struct Object *)mod; obj = (struct Object *)mod;
	} else if (decl) {
	  if (obj->type->form == NoTyp) {
		as_error("mult def");
	  } else {
		as_error("invalid import order");
	  }
	} else {
	  as_error("conflict with alias");
	}
  } else if (decl) { /*module already present, explicit import by declaration*/
	if  (obj->type->form == NoTyp) {
	  as_error("mult def");
	} else {
	  as_error("invalid import order");
	}
  }
  return obj;
}

void base_Import(const char *modid, const char *modid1) {
  long key;
  int class;
  int k;
  struct Object *object;
  struct Type *type;
  struct Object *thismod;
  char *modname;
  char *fname;
  //F: Files.File; R: Files.Rider;

  if (strcmp(modid1, "SYSTEM") == 0) {
	thismod = base_ThisModule(modid, modid1, 1,  key);
	nofmod -= 1;
	thismod->lev = 0;
	thismod->dsc = systemScope;
	thismod->rdo = 1;
  } else {
	/*
      MakeFileName(fname, modid1, ".smb"); F := Files.Old(fname);
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
	*/
  }
}
		
void base_enter(char *name, int cl, struct Type *type, long n) {
  struct Object *obj;

  obj = as_malloc(sizeof(struct Object));
  obj->name = as_strdup(name);
  obj->class = cl;
  obj->type = type;
  obj->val = n;
  obj->dsc = 0;
  if (cl == Typ) {
	type->typobj = obj;
  }
  obj->next = systemScope;
  systemScope = obj;
}

void base_init(void) {

  byteType = base_type(Byte, Int, 1);
  boolType = base_type(Bool, Bool, 1);
  charType = base_type(Char, Char,1);
  intType = base_type(Int, Int, 2);
  realType = base_type(Real, Real, 4);
  setType = base_type(Set, Set,2);
  nilType = base_type(NilTyp, NilTyp, 1);
  noType = base_type(NoTyp, NoTyp, 1);
  strType = base_type(String, String, 4);
  
  /*initialize universe with data types and in-line procedures;
    LONGINT is synonym to INTEGER, LONGREAL to REAL.
    LED, ADC, SBC; LDPSR, LDREG, REG, COND are not in language definition*/
  systemScope = 0;  /*n = procno*10 + nofpar*/
  base_enter("UML", SFunc, intType, 132);  /*functions*/
  base_enter("SBC", SFunc, intType, 122);
  base_enter("ADC", SFunc, intType, 112);
  base_enter("ROR", SFunc, intType, 92);
  base_enter("ASR", SFunc, intType, 82);
  base_enter("LSL", SFunc, intType, 72);
  base_enter("LEN", SFunc, intType, 61);
  base_enter("CHR", SFunc, charType, 51);
  base_enter("ORD", SFunc, intType, 41);
  base_enter("FLT", SFunc, realType, 31);
  base_enter("FLOOR", SFunc, intType, 21);
  base_enter("ODD", SFunc, boolType, 11);
  base_enter("ABS", SFunc, intType, 1);
  base_enter("LED", SProc, noType, 81);  /*procedures*/
  base_enter("UNPK", SProc, noType, 72);
  base_enter("PACK", SProc, noType, 62);
  base_enter("NEW", SProc, noType, 51);
  base_enter("ASSERT", SProc, noType, 41);
  base_enter("EXCL", SProc, noType, 32);
  base_enter("INCL", SProc, noType, 22);
  base_enter("DEC", SProc, noType, 11);
  base_enter("INC", SProc, noType, 1);
  base_enter("SET", Typ, setType, 0);   /*types*/
  base_enter("BOOLEAN", Typ, boolType, 0);
  base_enter("BYTE", Typ, byteType, 0);
  base_enter("CHAR", Typ, charType, 0);
  base_enter("LONGREAL", Typ, realType, 0);
  base_enter("REAL", Typ, realType, 0);
  base_enter("LONGINT", Typ, intType, 0);
  base_enter("INTEGER", Typ, intType, 0);
  topScope = 0; base_OpenScope(); topScope->next = systemScope; universe = topScope;
  
  systemScope = 0;  /* initialize "unsafe" pseudo-module SYSTEM*/
  base_enter("H", SFunc, intType, 201);     /*functions*/
  base_enter("COND", SFunc, boolType, 191);
  base_enter("SIZE", SFunc, intType, 181);
  base_enter("ADR", SFunc, intType, 171);
  base_enter("VAL", SFunc, intType, 162);
  base_enter("REG", SFunc, intType, 151);
  base_enter("BIT", SFunc, boolType, 142);
  base_enter("LDREG", SProc, noType, 142);  /*procedures*/
  base_enter("LDPSR", SProc, noType, 131);
  base_enter("COPY", SProc, noType, 123);
  base_enter("PUT", SProc, noType, 112);
  base_enter("GET", SProc, noType, 102);

  topScope = universe;
  nofmod = 1;
}

struct Type *base_type(int ref, int form, long size) {
  struct Type *tp;

  tp = as_malloc(sizeof(struct Type));
  tp->form = form;
  tp->size = size;
  tp->ref = ref;
  tp->base = 0;
  typtab[ref] = tp;

  return tp;
}

void base_export(char *module, bool newSF, long key) {
}

