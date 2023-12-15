/*
Oberongen.h - Oberon code generator

Based on the project oberon compiler, but generates 65816 code.

Notes on the generated code:

All operations are executed with data in registers. There are 8 16-bit
registers allocated in direct page. 
*/
#ifndef OBERONGEN_H
#define OBERONGEN_H

#include <stdbool.h>

#include "value.h"
#include "scanner.h"

void oberon_stringToChar(Item *x);

void oberon_init(void);

static const int WordSize = 2; /* 16-bit for now */

struct Item {
  Mode mode;
  Type *type;
  long a, b, r;
  bool readonly;
};

typedef struct Item Item;

/*
Item forms and meaning of fields:

mode    r       a        b
---------------------------------
Const   -       value    (proc adr)   (immediate value)
Var     base    off      -            (direct adr)
Par     -       off0     off1         (indirect adr)
Reg     regno
RegI    regno   off      -
Cond    cond    Fchain   Tchain
*/


Item *item_makeConst(int val);
Item *item_makeReal(float val);
Item *item_makeString(const char *str);
Item *item_make(Object *object, long curlev);

bool oberon_load(Item *x);

/* App Lifecycle */
void oberon_app_startup(void);

/* Branches, procedure calls, procedure prolog and epilog */

void oberon_here(Object *label);
void oberon_jump(Object *label);
void oberon_cjump(Object *label, Item *x);

int oberon_prepCall(Item *x); /* x->type->form = ProcForm */
void oberon_call(Object *object, long rx);
void oberon_enter(Object *proc, int parblksize, int locblksize, bool isInt);
void oberon_return(Form form, Item *x, int size, bool isInt);

void oberon_not(Item *x);
void oberon_and1(Item *x); /*x := x & */
void oberon_and2(Item *x, Item *y);
void oberon_or1(Item *x); /* x := x OR */
void oberon_or2(Item *y);

void oberon_neg(Item *x); /* x := -x */
void oberon_addOp(Symbol op, Item *x, Item *y); /* rx := rx +- ry */
void oberon_mulOp(Item *x, Item *y);
void oberon_divOp(Symbol sym, Item *x, Item *y);
void oberon_realOp(Symbol sym, Item *x, Item *y);

void oberon_typeTest(Item *x, Type* t, bool varpar, bool isguard);

void oberon_store(Item *x, Item *y);

/* For statements */
void oberon_for0(Item *x, Item *y);
void oberon_for1(void);
void oberon_for2(void);

/* Code generaton for set operators */
void oberon_singleton(Item *x); /* x := {x} */
void oberon_set(void); /* x := {x..y} */
void oberon_in(Item *x, Item *y); /* x := x in y */
void oberon_setOp(Symbol sym, Item *x, Item *y); /* x := x op y */

/* Code generaton for relations */
void oberon_intRelation(Symbol rel, Item *x, Item *y); /* x := x < y */
void oberon_realRelation(Symbol rel, Item *x, Item *y); /* x := x < y */
void oberon_stringRelation(Symbol rel, Item *x, Item *y); /* x := x < y */

/* Code generation for parameters */
void oberon_openArrayParam(Item *x);
void oberon_varParam(Item *x, Type *typ);
void oberon_valueParam(Item *x);
void oberon_stringParam(Item *x);

/* Standard procedures */
void oberon_get(Item *x, Item *y);
void oberon_put(Item *x, Item *y);

// putb - byte
// putl - low byte of word
// puth - high byte of word
// putw - word


#endif
