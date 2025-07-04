/* ORB.c - Symbol Table Management */
/* Original: NW 25.6.2014 / AP 4.3.2020 / 8.3.2019 in Oberon-07 */
/* Definition of data types Object and Type, which together form the data structure
   called "symbol table". Contains procedures for creation of Objects, and for search:
   NewObj, this, thisimport, thisfield (and OpenScope, CloseScope).
   Handling of import and export, i.e. reading and writing of "symbol files" is done by procedures
   Import and Export. This module contains the list of standard identifiers, with which
   the symbol table (universe), and that of the pseudo-module SYSTEM are initialized. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include "ORS.h"
#include "ORB.h"

/* Global variables */
ObjectPtr topScope = NULL;
ObjectPtr universe = NULL;
ObjectPtr systemScope = NULL;  /* renamed from system */
TypePtr byteType = NULL;
TypePtr boolType = NULL;
TypePtr charType = NULL;
TypePtr intType = NULL;
TypePtr realType = NULL;
TypePtr setType = NULL;
TypePtr nilType = NULL;
TypePtr noType = NULL;
TypePtr strType = NULL;

/* Static variables */
static int nofmod;
static int Ref;
static TypePtr typtab[maxTypTab];

/* All file operations now handled by Files.h/Files.c */


/* Symbol table operations */
void NewObj(ObjectPtr *obj, const char *id, int class) {
    ObjectPtr new_obj, x;
    
    x = topScope;
    while ((x->next != NULL) && (strcmp(x->next->name, id) != 0)) {
        x = x->next;
    }
    
    if (x->next == NULL) {
        new_obj = (ObjectPtr)calloc(1, sizeof(ORB_Object));
        strcpy(new_obj->name, id);
        new_obj->class = class;
        new_obj->next = NULL;
        new_obj->rdo = false;
        new_obj->dsc = NULL;
        x->next = new_obj;
        *obj = new_obj;
    } else {
        *obj = x->next;
        ORS_Mark("mult def");
    }
}

ObjectPtr thisObj(void) {
    ObjectPtr s, x;
    
    s = topScope;
    do {
        x = s->next;
        while ((x != NULL) && (strcmp(x->name, ORS_id) != 0)) {
            x = x->next;
        }
        s = s->dsc;
    } while ((x == NULL) && (s != NULL));
    
    return x;
}

ObjectPtr thisimport(ObjectPtr mod) {
    ObjectPtr obj = NULL;
    
    if (mod->rdo) {
        if (mod->name[0] != '\0') {
            obj = mod->dsc;
            while ((obj != NULL) && (strcmp(obj->name, ORS_id) != 0)) {
                obj = obj->next;
            }
        }
    }
    
    return obj;
}

ObjectPtr thisfield(TypePtr rec) {
    ObjectPtr fld = rec->dsc;
    
    while ((fld != NULL) && (strcmp(fld->name, ORS_id) != 0)) {
        fld = fld->next;
    }
    
    return fld;
}

void OpenScope(void) {
    ObjectPtr s = (ObjectPtr)calloc(1, sizeof(ORB_Object));
    s->class = Head;
    s->dsc = topScope;
    s->next = NULL;
    topScope = s;
}

void CloseScope(void) {
    topScope = topScope->dsc;
}

/* Import/Export operations */
void MakeFileName(char *FName, const char *name, const char *ext) {
    int i = 0, j = 0;
    
    while ((i < ORS_IDENT_LEN-5) && (name[i] != '\0')) {
        FName[i] = name[i];
        i++;
    }
    
    while (ext[j] != '\0') {
        FName[i] = ext[j];
        i++;
        j++;
    }
    
    FName[i] = '\0';
}

static ObjectPtr ThisModule(const char *name, const char *orgname, bool decl, int32_t key) {
    ModulePtr mod;
    ObjectPtr obj, obj1;
    
    obj1 = topScope;
    obj = obj1->next;
    
    /* Search for module */
    while ((obj != NULL) && (strcmp(((ModulePtr)obj)->orgname, orgname) != 0)) {
        obj1 = obj;
        obj = obj1->next;
    }
    
    if (obj == NULL) {
        /* New module, search for alias */
        obj = topScope->next;
        while ((obj != NULL) && (strcmp(obj->name, name) != 0)) {
            obj = obj->next;
        }
        
        if (obj == NULL) {
            /* Insert new module */
            mod = (ModulePtr)calloc(1, sizeof(ORB_Module));
            mod->base.class = Mod;
            mod->base.rdo = false;
            strcpy(mod->base.name, name);
            strcpy(mod->orgname, orgname);
            mod->base.val = key;
            mod->base.lev = nofmod;
            nofmod++;
            mod->base.dsc = NULL;
            mod->base.next = NULL;
            
            if (decl) {
                mod->base.type = noType;
            } else {
                mod->base.type = nilType;
            }
            
            obj1->next = (ObjectPtr)mod;
            obj = (ObjectPtr)mod;
        } else if (decl) {
            if (obj->type->form == NoTyp) {
                ORS_Mark("mult def");
            } else {
                ORS_Mark("invalid import order");
            }
        } else {
            ORS_Mark("conflict with alias");
        }
    } else if (decl) {
        /* Module already present, explicit import by declaration */
        if (obj->type->form == NoTyp) {
            ORS_Mark("mult def");
        } else {
            ORS_Mark("invalid import order");
        }
    }
    
    return obj;
}

static void Read(Files_Rider *R, int *x) {
    BYTE b;
    Files_ReadByte(R, &b);
    if (b < 0x80) {
        *x = b;
    } else {
        *x = b - 0x100;
    }
}

static void Write(Files_Rider *R, int x) {
    Files_WriteByte(R, (BYTE)x);
}

static void InType(Files_Rider *R, ObjectPtr thismod, TypePtr *T) {
    int32_t key;
    int ref, class, form, np, readonly;
    ObjectPtr fld, par, obj, mod, last;
    TypePtr t;
    char name[ORS_IDENT_LEN], modname[ORS_IDENT_LEN];
    
    Read(R, &ref);
    if (ref < 0) {
        *T = typtab[-ref];  /* Already read */
    } else {
        t = (TypePtr)calloc(1, sizeof(ORB_Type));
        *T = t;
        typtab[ref] = t;
        t->mno = thismod->lev;
        
        Read(R, &form);
        t->form = form;
        
        if (form == Pointer) {
            InType(R, thismod, &t->base);
            t->size = 4;
        } else if (form == Array) {
            InType(R, thismod, &t->base);
            Files_ReadNum(R, &t->len);
            Files_ReadNum(R, &t->size);
        } else if (form == Record) {
            InType(R, thismod, &t->base);
            if (t->base->form == NoTyp) {
                t->base = NULL;
                obj = NULL;
            } else {
                obj = t->base->dsc;
            }
            
            Files_ReadNum(R, &t->len);     /* TD adr/exno */
            Files_ReadNum(R, &t->nofpar);  /* ext level */
            Files_ReadNum(R, &t->size);
            
            Read(R, &class);
            last = NULL;
            
            while (class != 0) {  /* Fields */
                fld = (ObjectPtr)calloc(1, sizeof(ORB_Object));
                fld->class = class;
                Files_ReadString(R, fld->name);
                
                if (last == NULL) {
                    t->dsc = fld;
                } else {
                    last->next = fld;
                }
                last = fld;
                
                if (fld->name[0] != '\0') {
                    fld->expo = true;
                    InType(R, thismod, &fld->type);
                } else {
                    fld->expo = false;
                    fld->type = nilType;
                }
                
                Files_ReadNum(R, &fld->val);
                Read(R, &class);
            }
            
            if (last == NULL) {
                t->dsc = obj;
            } else {
                last->next = obj;
            }
        } else if (form == Proc) {
            InType(R, thismod, &t->base);
            obj = NULL;
            np = 0;
            Read(R, &class);
            
            while (class != 0) {  /* Parameters */
                par = (ObjectPtr)calloc(1, sizeof(ORB_Object));
                par->class = class;
                Read(R, &readonly);
                par->rdo = (readonly == 1);
                InType(R, thismod, &par->type);
                par->next = obj;
                obj = par;
                np++;
                Read(R, &class);
            }
            
            t->dsc = obj;
            t->nofpar = np;
            t->size = 4;
        }
        
        Files_ReadString(R, modname);
        if (modname[0] != '\0') {  /* Re-import */
            Files_ReadInt(R, &key);
            Files_ReadString(R, name);
            mod = ThisModule(modname, modname, false, key);
            obj = mod->dsc;
            
            /* Search type */
            while ((obj != NULL) && (strcmp(obj->name, name) != 0)) {
                obj = obj->next;
            }
            
            if (obj != NULL) {
                *T = obj->type;  /* Type object found */
            } else {
                /* Insert new type object */
                obj = (ObjectPtr)calloc(1, sizeof(ORB_Object));
                strcpy(obj->name, name);
                obj->class = Typ;
                obj->next = mod->dsc;
                mod->dsc = obj;
                obj->type = t;
                t->mno = mod->lev;
                t->typobj = obj;
                *T = t;
            }
            typtab[ref] = *T;
        }
    }
}

void Import(char *modid, char *modid1) {
    int32_t key = 0;  /* Initialize to 0 */
    int class, k;
    ObjectPtr obj;
    TypePtr t;
    ObjectPtr thismod;
    char modname[ORS_IDENT_LEN], fname[ORS_IDENT_LEN];
    Files_File *F;
    Files_Rider R;
    
    if (strcmp(modid1, "SYSTEM") == 0) {
        thismod = ThisModule(modid, modid1, true, key);
        nofmod--;
        thismod->lev = 0;
        thismod->dsc = systemScope;
        thismod->rdo = true;
    } else {
        MakeFileName(fname, modid1, ".smb");
        F = Files_Old(fname);
        
        if (F != NULL) {
            Files_Set(&R, F, 0);
            Files_ReadInt(&R, &key);
            Files_ReadInt(&R, &key);
            Files_ReadString(&R, modname);
            thismod = ThisModule(modid, modid1, true, key);
            thismod->rdo = true;
            
            Read(&R, &class);  /* version key */
            if (class != versionkey) {
                ORS_Mark("wrong version");
            }
            
            Read(&R, &class);
            while (class != 0) {
                obj = (ObjectPtr)calloc(1, sizeof(ORB_Object));
                obj->class = class;
                Files_ReadString(&R, obj->name);
                InType(&R, thismod, &obj->type);
                obj->lev = -thismod->lev;
                
                if (class == Typ) {
                    t = obj->type;
                    t->typobj = obj;
                    Read(&R, &k);
                    
                    /* Fixup bases of previously declared pointer types */
                    while (k != 0) {
                        typtab[k]->base = t;
                        Read(&R, &k);
                    }
                } else {
                    if (class == Const) {
                        if (obj->type->form == Real) {
                            Files_ReadInt(&R, &obj->val);
                        } else {
                            Files_ReadNum(&R, &obj->val);
                        }
                    } else if (class == Var) {
                        Files_ReadNum(&R, &obj->val);
                        obj->rdo = true;
                    }
                }
                
                obj->next = thismod->dsc;
                thismod->dsc = obj;
                Read(&R, &class);
            }
            
            Files_Register(F);
        } else {
            ORS_Mark("import not available");
        }
    }
}

static void OutType(Files_Rider *R, TypePtr t);

static void OutPar(Files_Rider *R, ObjectPtr par, int n) {
    int cl;
    
    if (n > 0) {
        OutPar(R, par->next, n-1);
        cl = par->class;
        Write(R, cl);
        if (par->rdo) {
            Write(R, 1);
        } else {
            Write(R, 0);
        }
        OutType(R, par->type);
    }
}

static void FindHiddenPointers(Files_Rider *R, TypePtr typ, int32_t offset) {
    ObjectPtr fld;
    int32_t i, n;
    
    if ((typ->form == Pointer) || (typ->form == NilTyp)) {
        Write(R, Fld);
        Write(R, 0);
        Files_WriteNum(R, offset);
    } else if (typ->form == Record) {
        fld = typ->dsc;
        while (fld != NULL) {
            FindHiddenPointers(R, fld->type, fld->val + offset);
            fld = fld->next;
        }
    } else if (typ->form == Array) {
        i = 0;
        n = typ->len;
        while (i < n) {
            FindHiddenPointers(R, typ->base, typ->base->size * i + offset);
            i++;
        }
    }
}

static void OutType(Files_Rider *R, TypePtr t) {
    ObjectPtr obj, mod, fld, bot;
    
    if (t->ref > 0) {
        /* Type was already output */
        Write(R, -t->ref);
    } else {
        obj = t->typobj;
        if (obj != NULL) {
            Write(R, Ref);
            t->ref = Ref;
            Ref++;
        } else {
            /* Anonymous */
            Write(R, 0);
        }
        
        Write(R, t->form);
        
        if (t->form == Pointer) {
            OutType(R, t->base);
        } else if (t->form == Array) {
            OutType(R, t->base);
            Files_WriteNum(R, t->len);
            Files_WriteNum(R, t->size);
        } else if (t->form == Record) {
            if (t->base != NULL) {
                OutType(R, t->base);
                bot = t->base->dsc;
            } else {
                OutType(R, noType);
                bot = NULL;
            }
            
            if (obj != NULL) {
                Files_WriteNum(R, obj->exno);
            } else {
                Write(R, 0);
            }
            
            Files_WriteNum(R, t->nofpar);
            Files_WriteNum(R, t->size);
            
            fld = t->dsc;
            while (fld != bot) {
                if (fld->expo) {
                    Write(R, Fld);
                    Files_WriteString(R, fld->name);
                    OutType(R, fld->type);
                    Files_WriteNum(R, fld->val);  /* offset */
                } else {
                    FindHiddenPointers(R, fld->type, fld->val);
                }
                fld = fld->next;
            }
            Write(R, 0);
        } else if (t->form == Proc) {
            OutType(R, t->base);
            OutPar(R, t->dsc, t->nofpar);
            Write(R, 0);
        }
        
        if ((t->mno > 0) && (obj != NULL)) {
            /* Re-export, output name */
            mod = topScope->next;
            while ((mod != NULL) && (mod->lev != t->mno)) {
                mod = mod->next;
            }
            
            if (mod != NULL) {
                Files_WriteString(R, ((ModulePtr)mod)->orgname);
                Files_WriteInt(R, mod->val);
                Files_WriteString(R, obj->name);
            } else {
                ORS_Mark("re-export not found");
                Write(R, 0);
            }
        } else {
            Write(R, 0);
        }
    }
}

void Export(const char *modid, BOOLEAN *newSF, int32_t *key) {
    int32_t x, sum, oldkey;
    ObjectPtr obj, obj0;
    char filename[ORS_IDENT_LEN];
    Files_File *F, *F1;
    Files_Rider R, R1;
    
    Ref = Record + 1;
    MakeFileName(filename, modid, ".smb");
    
    /* Read old checksum first before overwriting file */
    F1 = Files_Old(filename);
    if (F1 != NULL) {
        Files_Set(&R1, F1, 4);
        Files_ReadInt(&R1, &oldkey);
        Files_Close(F1);
    } else {
        oldkey = 0; /* No old file exists */
    }
    
    F = Files_New(filename);
    Files_Set(&R, F, 0);
    
    Files_WriteInt(&R, 0);  /* placeholder */
    Files_WriteInt(&R, 0);  /* placeholder for key */
    Files_WriteString(&R, modid);
    Write(&R, versionkey);
    
    obj = topScope->next;
    while (obj != NULL) {
        if (obj->expo) {
            Write(&R, obj->class);
            Files_WriteString(&R, obj->name);
            OutType(&R, obj->type);
            
            if (obj->class == Typ) {
                if (obj->type->form == Record) {
                    obj0 = topScope->next;
                    /* Check whether this is base of previously declared pointer types */
                    while (obj0 != obj) {
                        if ((obj0->type->form == Pointer) && 
                            (obj0->type->base == obj->type) && 
                            (obj0->type->ref > 0)) {
                            Write(&R, obj0->type->ref);
                        }
                        obj0 = obj0->next;
                    }
                }
                Write(&R, 0);
            } else if (obj->class == Const) {
                if (obj->type->form == Proc) {
                    Files_WriteNum(&R, obj->exno);
                } else if (obj->type->form == Real) {
                    Files_WriteInt(&R, obj->val);
                } else {
                    Files_WriteNum(&R, obj->val);
                }
            } else if (obj->class == Var) {
                Files_WriteNum(&R, obj->exno);
            }
        }
        obj = obj->next;
    }
    
    /* Pad to 4-byte boundary */
    do {
        Write(&R, 0);
    } while (Files_Length(F) % 4 != 0);
    
    /* Clear type table */
    for (Ref = Record + 1; Ref < maxTypTab; Ref++) {
        typtab[Ref] = NULL;
    }
    
    /* Register (flush) the file before reading for checksum */
    Files_Register(F);
    
    /* Reopen the file for reading */
    F = Files_Old(filename);
    if (F == NULL) {
        *key = 0;
        return;
    }
    
    /* Compute checksum */
    Files_Set(&R, F, 0);
    sum = 0;
    Files_ReadInt(&R, &x);
    while (!R.eof) {
        sum = sum + x;
        Files_ReadInt(&R, &x);
    }
    
    if (sum != oldkey) {
        if (*newSF || (oldkey == 0)) {
            *key = sum;
            *newSF = true;
            // Reopen file for writing to update checksum
            Files_Close(F);
            F = Files_Update(filename);
            if (F) {
                Files_Set(&R, F, 4);
                Files_WriteInt(&R, sum);
                Files_Register(F);
                Files_Close(F);
            }
        } else {
            ORS_Mark("new symbol file inhibited");
        }
    } else {
        *newSF = false;
        *key = sum;
    }
}

void ORB_Init(void) {
    topScope = universe;
    nofmod = 1;
}

/* Helper functions */
static TypePtr type(int ref, int form, int32_t size) {
    TypePtr tp = (TypePtr)calloc(1, sizeof(ORB_Type));
    tp->form = form;
    tp->size = size;
    tp->ref = ref;
    tp->base = NULL;
    typtab[ref] = tp;
    return tp;
}

static void enter(const char *name, int cl, TypePtr type, int32_t n) {
    ObjectPtr obj = (ObjectPtr)calloc(1, sizeof(ORB_Object));
    strcpy(obj->name, name);
    obj->class = cl;
    obj->type = type;
    obj->val = n;
    obj->dsc = NULL;
    
    if (cl == Typ) {
        type->typobj = obj;
    }
    
    obj->next = systemScope;
    systemScope = obj;
}

/* Module initialization - call this once at program start */
void ORB_Initialize(void) {
    /* Initialize basic types */
    byteType = type(Byte, Int, 1);
    boolType = type(Bool, Bool, 1);
    charType = type(Char, Char, 1);
    intType = type(Int, Int, 4);
    realType = type(Real, Real, 4);
    setType = type(Set, Set, 4);
    nilType = type(NilTyp, NilTyp, 4);
    noType = type(NoTyp, NoTyp, 4);
    strType = type(String, String, 8);
    
    /* Initialize universe with data types and in-line procedures;
       LONGINT is synonym to INTEGER, LONGREAL to REAL.
       LED, ADC, SBC; LDPSR, LDREG, REG, COND are not in language definition */
    systemScope = NULL;  /* n = procno*10 + nofpar */
    
    /* Functions */
    enter("UML", SFunc, intType, 132);
    enter("SBC", SFunc, intType, 122);
    enter("ADC", SFunc, intType, 112);
    enter("ROR", SFunc, intType, 92);
    enter("ASR", SFunc, intType, 82);
    enter("LSL", SFunc, intType, 72);
    enter("LEN", SFunc, intType, 61);
    enter("CHR", SFunc, charType, 51);
    enter("ORD", SFunc, intType, 41);
    enter("FLT", SFunc, realType, 31);
    enter("FLOOR", SFunc, intType, 21);
    enter("ODD", SFunc, boolType, 11);
    enter("ABS", SFunc, intType, 1);
    
    /* Procedures */
    enter("LED", SProc, noType, 81);
    enter("UNPK", SProc, noType, 72);
    enter("PACK", SProc, noType, 62);
    enter("NEW", SProc, noType, 51);
    enter("ASSERT", SProc, noType, 41);
    enter("EXCL", SProc, noType, 32);
    enter("INCL", SProc, noType, 22);
    enter("DEC", SProc, noType, 11);
    enter("INC", SProc, noType, 1);
    
    /* Types */
    enter("SET", Typ, setType, 0);
    enter("BOOLEAN", Typ, boolType, 0);
    enter("BYTE", Typ, byteType, 0);
    enter("CHAR", Typ, charType, 0);
    enter("LONGREAL", Typ, realType, 0);
    enter("REAL", Typ, realType, 0);
    enter("LONGINT", Typ, intType, 0);
    enter("INTEGER", Typ, intType, 0);
    
    topScope = NULL;
    OpenScope();
    topScope->next = systemScope;
    universe = topScope;
    
    /* Initialize "unsafe" pseudo-module SYSTEM */
    systemScope = NULL;
    
    /* Functions */
    enter("H", SFunc, intType, 201);
    enter("COND", SFunc, boolType, 191);
    enter("SIZE", SFunc, intType, 181);
    enter("ADR", SFunc, intType, 171);
    enter("VAL", SFunc, intType, 162);
    enter("REG", SFunc, intType, 151);
    enter("BIT", SFunc, boolType, 142);
    
    /* Procedures */
    enter("LDREG", SProc, noType, 142);
    enter("LDPSR", SProc, noType, 131);
    enter("COPY", SProc, noType, 123);
    enter("PUT", SProc, noType, 112);
    enter("GET", SProc, noType, 102);
}
