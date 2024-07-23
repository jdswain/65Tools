#ifndef OCG_H
#define OCG_H

#include <stdbool.h>
#include "cpu.h"
#include "ocs.h"
#include "ocb.h"

#define WordSize 2

#define Reg 10
#define RegI 11
#define Cond 12  /*internal item modes*/

struct Item {
  int mode;
  struct Type *type;
  long a;
  long b;
  long r;
  bool rdo; /*read only*/
};
  /* Item forms and meaning of fields:
    mode    r      a       b
    --------------------------------
    Const   -      value   (proc adr)   (immediate value)
    Var     base   off     -            (direct adr)
    Par     -      off0    off1         (indirect adr)
    Reg     regno
    RegI    regno  off     -
    Cond    cond   Fchain  Tchain
	Proc    lev    value   expo
  */

void gen_open(const char *fname);
void gen_setDataSize(int sz);
void gen_header(void);
void gen_close(char *id, int key, int exno);

void gen_CheckRegs(void);

/* Items: Conversion from constants or from Objects on the Heap to Items on the Stack*/

void gen_MakeConstItem(struct Item *Item, struct Type *typ, long val);
void gen_MakeRealItem(struct Item *x, float val);
void gen_MakeStringItem(struct Item *x, long len); 
void gen_MakeItem(struct Item *Item, struct Object *obj, long curlev);

/* Branches, procedure calls, procedure prolog and epilog */

void gen_symbol(const char *label);
void gen_FJump(long *L);
void gen_CFJump(struct Item *x);
void gen_BJump(long L);
void gen_CBJump(struct Item *x, long L);
void gen_Fixup(struct Item *x);
void gen_PrepCall(struct Item *x, long *r);
void gen_Call(struct Item *x, long r);
void gen_Enter(const char *name, long parblksize, long locblksize, bool interrupt);
void gen_Return(struct Object *proc, struct Item *x, long size, bool interrupt);

/* Code generation for Boolean operators */

void gen_Not(struct Item *x);   /* x := ~x */
void gen_And1(struct Item *x);   /* x := x & */
void gen_And2(struct Item *x, struct Item *y);
void gen_Or1(struct Item *x);   /* x := x OR */
void gen_Or2(struct Item *x, struct Item *y);

/* Code generation for arithmetic operators */

void gen_Neg(struct Item *x); /* x := -x */
void gen_AddOp(long op, struct Item *x, struct Item *y);   /* x := x +- y */
void gen_MulOp(struct Item *x, struct Item *y);   /* x := x * y */

/*In-line code functions*/

void gen_Abs(struct Item *x);
void gen_Odd(struct Item *x);
void gen_Floor(struct Item *x);
void gen_Float(struct Item *x);
void gen_Ord(struct Item *x);
void gen_Len(struct Item *x);
void gen_Shift(long fct, struct Item *x, struct Item *y);
void gen_Bit(struct Item *x, struct Item *y);
void gen_H(struct Item *x);
void gen_Condition(struct Item *x);

/* In-line code procedures*/

void gen_Increment(long upordown, struct Item *x, struct Item *y);
void gen_Get(struct Item *x, struct Item *y);
void gen_Put(struct Item *x, struct Item *y);

/* Code generation for selectors, variables, constants*/

void gen_BuildTD(struct Type *T, long *dc);
void gen_TypeTest(struct Item *x, struct Type *T, bool varpar, bool isguard);

/* Code generation for REAL operators */

/* Code generation for set operators */

/* Code generation for relations */
void gen_IntRelation(int op, struct Item *x, struct Item *y);   /* x := x < y */
void gen_RealRelation(int op, struct Item *x, struct Item *y);   /* x := x < y */
void gen_StringRelation(int op, struct Item *x, struct Item *y);   /* x := x < y */

/* Code generation of Assignments */

void gen_StrToChar(struct Item *x);
void gen_Store(struct Item *x, struct Item *y); /* x := y */
void gen_StoreStruct(struct Item *x, struct Item *y); /* x := y, frame = 0 */
void gen_CopyString(struct Item*x, struct Item *y);  /* x := y */ 

/* Code generation for parameters */

void gen_OpenArrayParam(struct Item *x);
void gen_VarParam(struct Item *x, struct Type *ftype);
void gen_ValueParam(struct Item *x);
void gen_StringParam(struct Item *x);

/*For Statements*/

void gen_For0(struct Item *x, struct Item *y);
void gen_For1(struct Item *x, struct Item *y, struct Item *z, struct Item *w, int *L);
void gen_For2(struct Item *x, struct Item *y, struct Item *w);

#endif
