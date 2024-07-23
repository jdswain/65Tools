#include "ocp.h"

#include <stdio.h>
#include <string.h>

#include "ocs.h"
#include "ocb.h"
#include "ocg.h"
#include "buffered_file.h"
#include "memory.h"
#include "codegen.h"

/*
  Oberon Compiler Parser
*/

struct PtrBase {
  char *name;
  struct Type *type;
  struct PtrBase *next;
};
 
long dc; /*data counter*/
int level;
int exno;
bool newSF; /*option flag*/
char *modid;
struct PtrBase *pbsList; /*list of names of pointer base types*/
struct Object *dummy;

// Forward references
void parser_expression(struct Item *x);
struct Type *parser_Type(void);
struct Type *parser_FormalType(int dim);
void parser_ProcedureType(struct Type *ptype, long *parblksize);
void parser_StatSequence(void);

void parser_Check(OSymbol sym, char *msg) {
  if (scanner_sym == sym) {
	scanner_next();
  } else {
	as_error("%s\n", msg);
  }
}

struct Object *parser_qualident(void) {
  struct Object *obj;

  obj = base_thisObj();
  scanner_next();
  if (obj == 0) {
	as_error("undef");
	obj = dummy;
  }
  if ((scanner_sym == osPERIOD) && (obj->class == Mod)) {
	scanner_next();
	if (scanner_sym == osIDENT) {
	  obj = base_thisimport(obj);
	  scanner_next();
	  if (obj == 0) {
		as_error("undef");
		obj = dummy;
	  }
	} else {
	  as_error("identifier expected");
	  obj = dummy;
	}
  }
  return obj;
}

void parser_CheckBool(struct Item *x) {
  if (x->type->form != Bool) {
	as_error("not Boolean");
	x->type = boolType;
  }
}

void parser_CheckInt(struct Item *x) {
  if (x->type->form != Int) {
	as_error("not Integer");
	x->type = intType;
  }
}

void parser_CheckReal(struct Item *x) {
  if (x->type->form != Real) {
	as_error("not Real");
	x->type = realType;
  }
}

void parser_CheckSet(struct Item *x) {
  if (x->type->form != Set) {
	as_error("not Set");
	x->type = setType;
  }
}

void parser_CheckSetVal(struct Item *x) {
  if (x->type->form != Int) {
	as_error("not Int");
	x->type = setType;
  } else if (x->mode == Const) {
	if ((x->a < 0) || (x->a > 32)) {
	  as_error("invalid set");
	}
  }
}

void parser_CheckConst(struct Item *x) {
  if (x->mode != Const) {
	as_error("not a constant");
	x->mode = Const;
  }
}

void parser_CheckReadOnly(struct Item *x) {
  if (x->rdo) {
	as_error("read-only");
  }
}

void parser_CheckExport(bool *expo) {
  if (scanner_sym == osTIMES) {
	*expo = 1;
	scanner_next();
	if (level != 0) {
	  as_error("remove asterisk");
	}
  } else {
	*expo = 0;
  }
}

bool parser_IsExtension(struct Type *t0, struct Type *t1) {
  /*t1 is an extension of t0*/
  return ((t0 == t1) || (t1 != 0) && parser_IsExtension(t0, t1->base));
}

void parser_TypeTest(void) {
}

void parser_selector(struct Item *x) {
}

void parser_parameter(void) {
}

bool parser_EqualSignatures(struct Type *t0, struct Type *t1) {
  struct Object *p0;
  struct Object *p1;
  bool com;

  com = 1;
  if ((t0->base == t1->base) && (t0->nofpar == t1->nofpar)) {
	p0 = t0->dsc; p1 = t1->dsc;
	while (p0 != 0) {
	  if ((p0->class == p1->class) && (p0->rdo == p1->rdo) &&
          ((p0->type == p1->type) ||
          (p0->type->form == Array) && (p1->type->form == Array) && (p0->type->len == p1->type->len) && (p0->type->base == p1->type->base) ||
		   (p0->type->form == Proc) && (p1->type->form == Proc) && parser_EqualSignatures(p0->type, p1->type))) {
        p0 = p0->next; p1 = p1->next;
	  } else {
        p0 = 0; com = 0;
	  }
	}
  } else {
	com = 0;
  }
  return com;
}

bool parser_CompTypes(struct Type *t0, struct Type *t1, bool varpar) {
  /*check for assignment compatibility*/
  return ((t0 == t1)    /*openarray assignment disallowed in ORG*/
		  || ((t0->form == Array) && (t1->form == Array) && (t0->base == t1->base) && (t0->len == t1->len))
		  || ((t0->form == Record) && (t1->form == Record) && parser_IsExtension(t0, t1))
		  || (!varpar && ((t0->form == Pointer) && (t1->form == Pointer) && parser_IsExtension(t0->base, t1->base)))
		  || ((t0->form == Proc) && (t1->form == Proc) && parser_EqualSignatures(t0, t1))
		  || (((t0->form == Pointer) || (t0->form == Proc)) && (t1->form == NilTyp)));
}

void parser_Parameter(struct Object *par) {
  struct Item *x;
  bool varpar;

  x = as_malloc(sizeof(struct Item));  
  parser_expression(x);
  if (par != 0) {
	varpar = (par->class == Par);
	if (parser_CompTypes(par->type, x->type, varpar)) {
	  if (!varpar) {
		gen_ValueParam(x);
	  } else { /*par.class = Par*/
		if (!par->rdo) {
		  parser_CheckReadOnly(x);
		}
		//gen_VarParam(x, par->type);
	  }
	} else if ((x->type->form == Array) && (par->type->form == Array) &&
			   (x->type->base == par->type->base) && (par->type->len < 0)) {
	  if (!par->rdo) {
		parser_CheckReadOnly(x);
	  }
	  //gen_OpenArrayParam(x);
	} else if ((x->type->form == String) && varpar && par->rdo && (par->type->form == Array) && 
			   (par->type->base->form == Char) && (par->type->len < 0)) {
	  //gen_StringParam(x);
	} else if (!varpar && (par->type->form == Int) && (x->type->form == Int)) {
	  //gen_ValueParam(x);  /*BYTE*/
	} else if ((x->type->form == String) && (x->b == 2) && (par->class == Var) && (par->type->form == Char)) {
	  //gen_StrToChar(x); gen_ValueParam(x);
	} else if ((par->type->form == Array) && (par->type->base == byteType) && 
			   (par->type->len >= 0) && (par->type->size == x->type->size)) {
	  //gen_VarParam(x, par->type);
	} else {
	  as_error("incompatible parameters");
	}
  }
}

void parser_ParamList(struct Item *x) {
  int n;
  struct Object *par;

  par = x->type->dsc; n = 0;
  if (scanner_sym != osRPAREN) {
	parser_Parameter(par); n = 1;
	while (scanner_sym <= osCOMMA) {
	  parser_Check(osCOMMA, "comma?");
	  if (par != 0) { par = par->next; }
	  n++; parser_Parameter(par);
	}
	parser_Check(osRPAREN, ") missing");
  } else {
	scanner_next();
  }
  if (n < x->type->nofpar) { as_error("too few params");
  } else if (n > x->type->nofpar) { as_error("too many params");
  }
}

void parser_StandFunc(struct Item *x, long fct, struct Type *restyp) {
  struct Item *y;
  long n;
  long npar;

  parser_Check(osLPAREN, "no (");
  npar = fct % 10;
  fct = fct / 10;
  parser_expression(x);
  n = 1;
  while (scanner_sym == osCOMMA) {
	scanner_next();
	parser_expression(y);
	n += 1;
  }
  parser_Check(osRPAREN, "no )");
  if (n == npar) {
	switch (fct) {
	case 0: /*ABS*/
	  if (x->type->form == Int || (x->type->form ==Real)) {
		gen_Abs(x);
		restyp = x->type;
	  } else {
		as_error("bad type");
	  }
	  break;
	case 1: /*ODD*/
	  parser_CheckInt(x);
	  gen_Odd(x);
	  break;
	case 2: /*FLOOR*/
	  parser_CheckReal(x);
	  gen_Floor(x);
	  break;
	case 3: /*FLT*/
	  parser_CheckInt(x);
	  gen_Float(x);
	  break;
	case 4: /*ORD*/
	  if (x->type->form <= Proc) {
		gen_Ord(x);
	  } else if ((x->type->form == String) && (x->b = 2)) {
		gen_StrToChar(x);
	  } else {
		as_error("bad type");
	  }
	  break;
	case 5: /*CHR*/
	  parser_CheckInt(x);
	  gen_Ord(x);
	  break;
	case 6: /*LEN*/
	  if (x->type->form == Array) {
		gen_Len(x);
	  } else {
		as_error("not an array");
	  }
	  break;
	case 7: /*LSL*/
	case 8: /*ASR*/
	case 9: /*ROR*/
	  parser_CheckInt(y);
	  if ((x->type->form == Int) || (x->type->form == Set)) {
		gen_Shift(fct-7, x, y);
		restyp = x->type;
	  } else {
		as_error("bad type");
	  }
	  break;
	case 11: /*ADC*/
	  break;
	case 12: /*SBC*/
	  break;
	case 13: /*UML*/
	  break;
	case 14: /*BIT*/
	  parser_CheckInt(x);
	  parser_CheckInt(y);
	  //gen_Bit(x, y);
	  break;
	case 15: /*REG*/
      //ELSIF fct = 15 THEN (*REG*) CheckConst(x); CheckInt(x); ORG.Register(x)
	case 16: /*VAL*/
	  if ((x->mode == Typ) && (x->type->size <= y->type->size)) {
		restyp = x->type;
		x = y;
	  } else {
		as_error("casting not allowed");
	  }
	  break;
	case 17: /*ADR*/
	  //gen_Adr(x);
	case 18: /*SIZE*/
	  if (x->mode == Typ) {
		gen_MakeConstItem(x, intType, x->type->size);
	  } else {
        as_error("must be a type");
	  }
	  break;
	case 19: /*COND*/
      parser_CheckConst(x);
	  parser_CheckInt(x);
	  gen_Condition(x);
	  break;
	case 20: /*H*/
	  parser_CheckConst(x);
	  parser_CheckInt(x);
	  gen_H(x);
	}
	x->type = restyp;
  } else {
    as_error("wrong nof params");
  }
}

void parser_element(struct Item *x) {
  struct Item *y;

  y = as_malloc(sizeof(struct Item));
  parser_expression(x);
  parser_CheckSetVal(x);
  if (scanner_sym == osUPTO) {
	scanner_next();
	parser_expression(y);
	parser_CheckSetVal(y);
	//gen_Set(x, y);
  } else {
	//gen_Singleton(x);
  }
  x->type = setType;
}

void parser_set(struct Item *x) {
  struct Item *y;

  y = as_malloc(sizeof(struct Item));
  if (scanner_sym > sIF) {
	if (scanner_sym != osRBRACE) {
	  as_error(" } missing");
	}
	//gen_MakeConstItem(x, setType, 0); /*empty set*/
  } else {
	parser_element(x);
	while ((scanner_sym < osRPAREN) || (scanner_sym > osRBRACE)) {
	  if (scanner_sym == osCOMMA) {
		scanner_next();
	  } else if (scanner_sym != osRBRACE) {
		as_error("missing comma");
	  }
	  parser_element(y);
	  //gen_SetOp(sPLUS, x, y);
	}
  }
}

void parser_factor(struct Item *x) {
  struct Object *obj;
  long rx;

  /*symc*/
  if ((scanner_sym < osCHAR) || (scanner_sym > osIDENT)) {
	as_error("expression expected");
	do {
	  scanner_next();
	} while ((scanner_sym < osCHAR) && (scanner_sym > osFOR) && (scanner_sym < osTHEN)); 
  }
  if (scanner_sym == osIDENT) {
	obj = parser_qualident();
	if (obj->class == SFunc) {
	  parser_StandFunc(x, obj->val, obj->type);
	} else {
	  gen_MakeItem(x, obj, level);
	  parser_selector(x);
	  if (scanner_sym == osLPAREN) {
		scanner_next();
		if ((x->type->form == Proc) && (x->type->base->form != NoTyp)) {
		  gen_PrepCall(x, &rx);
		  parser_ParamList(x);
		  gen_Call(x, rx);
		  x->type = x->type->base;
		} else {
		  as_error("not a function");
		  parser_ParamList(x);
		}
	  }
	}
  } else if (scanner_sym == osINT) {
	gen_MakeConstItem(x, intType, scanner_ival);
	scanner_next();
  } else if (scanner_sym == osREAL) {
	//gen_MakeRealItem(x, scanner_rval);
	scanner_next();
  } else if (scanner_sym == osCHAR) {
	//gen_MakeConstItem(x, charType, scanner_ival);
	scanner_next();
  } else if (scanner_sym == osNIL) {
	//gen_MakeConstItem(x, nilType, 0);
	scanner_next();
  } else if (scanner_sym == osSTRING) {
	//gen_MakeStringItem(x, scanner_slen);
	scanner_next();
  } else if (scanner_sym == osLPAREN) {
	scanner_next(); parser_expression(x); parser_Check(osRPAREN, "no )");
  } else if (scanner_sym == osLBRACE) {
	scanner_next(); parser_set(x); parser_Check(osRBRACE, "no }");
  } else if (scanner_sym == osNOT) {
	scanner_next(); parser_factor(x); parser_CheckBool(x); gen_Not(x);
  } else if (scanner_sym == osFALSE) {
	scanner_next(); gen_MakeConstItem(x, boolType, 0);
  } else if (scanner_sym == osTRUE) {
	scanner_next(); gen_MakeConstItem(x, boolType, 1);
  } else {
	as_error("not a factor");
	//gen_MakeConstItem(x, intType, 0);
  }
}

void parser_term(struct Item *x) {
  struct Item *y;
  int op;
  int f;

  y = as_malloc(sizeof(struct Item));
  parser_factor(x);
  f = x->type->form;
  while ((scanner_sym >= osTIMES) && (scanner_sym <= osAND)) {
	op = scanner_sym;
	scanner_next();
	if (op == osTIMES) {
	  if (f == Int) {
		parser_factor(y);
		parser_CheckInt(y);
		gen_MulOp(x, y);
	  } else if (f == Real) {
		parser_factor(y);
		parser_CheckReal(y);
		//gen_realOp(op, x, y);
	  } else if (f == Set) {
		parser_factor(y);
		parser_CheckSet(y);
		//gen_SetOp(op, x, y);
	  } else {
		as_error("bad type");
	  }
	} else if ((op == osDIV) || (op == osMOD)) {
	  parser_CheckInt(x);
	  parser_factor(y);
	  parser_CheckInt(y);
	  //gen_divOp(op, x, y);
	} else if (op == osRDIV) {
	  if (f == Real) {
		parser_factor(y);
		parser_CheckReal(y);
		//gen_RealOp(op, x, y);
	  } else if (f == Set) {
		parser_factor(y);
		parser_CheckSet(y);
		//gen_SetOp(op, x, y);
	  } else {
		as_error("bad type");
	  }
	} else { /*op = and*/
	  parser_CheckBool(x);
	  gen_And1(x);
	  parser_factor(y);
	  parser_CheckBool(y);
	  gen_And2(x, y);
	}
  }
}

void parser_simpleExpression(struct Item *x) {
  struct Item *y;
  int op;

  y = as_malloc(sizeof(struct Item));
  if (scanner_sym == osMINUS) {
	scanner_next();
	parser_term(x);
	if ((x->type->form == Int) ||
		(x->type->form == Real) ||
		(x->type->form == Set)) {
	  gen_Neg(x);
	} else {
	  parser_CheckInt(x);
	}
  } else if (scanner_sym == osPLUS) {
	scanner_next();
	parser_term(x);
  } else {
	parser_term(x);
  }
  while ((scanner_sym >= osPLUS) && (scanner_sym <= osOR)) {
	op = scanner_sym;
	scanner_next();
	if (op == osOR) {
	  //gen_Or1(x);
	  parser_CheckBool(x);
	  parser_term(y);
	  parser_CheckBool(y);
	  //gen_Or2(x, y);
	} else if (x->type->form == Int) {
	  parser_term(y);
	  parser_CheckInt(y);
	  gen_AddOp(op, x, y);
	} else if (x->type->form == Real) {
	  parser_term(y);
	  parser_CheckReal(y);
	  //gen_RealOp(op, x, y);
	} else {
	  parser_CheckSet(x);
	  parser_term(y);
	  parser_CheckSet(y);
	  //gen_SetOp(op, x, y);
	}
  }
}

void parser_expression(struct Item *x) {
  struct Item * y;
  struct Object *obj;
  int rel;
  int xf;
  int yf;

  y = as_malloc(sizeof(struct Item));
  parser_simpleExpression(x);
  if ((scanner_sym >= osEQL) && (scanner_sym <= osGEQ)) {
	rel = scanner_sym;
	scanner_next();
	parser_simpleExpression(y);
	xf = x->type->form;
	yf = y->type->form;
	if (x->type == y->type) {
	  if ((xf == Char) || (xf == Int)) {
		gen_IntRelation(rel, x, y);
	  } else if (xf == Real) {
		//gen_realRelation(rel, x, y);
	  } else if ((xf == Set) ||
				 (xf == Pointer) ||
				 (xf == Proc) ||
				 (xf == NilTyp) ||
				 (xf == Bool)) {
		if (rel <= osNEQ) {
		  gen_IntRelation(rel, x, y);
		} else {
		  as_error("only = or #");
		}
	  } else if ((xf == Array) && (x->type->base->form == Char) || (xf == String)) {
		//gen_stringRelation(rel, x, y);
	  } else {
		as_error("illegal comparison");
	  }
	} else if (((xf == Pointer) || (xf == Proc)) && (yf == NilTyp)
			   || ((yf == Pointer) || (yf == Proc)) && (xf == NilTyp)) {
	  if (rel <= osNEQ) {
		gen_IntRelation(rel, x,  y);
	  } else {
		as_error("only = or #");
	  }
	} else if ((xf == Pointer) && (yf == Pointer) &&
			   (parser_IsExtension(x->type->base, y->type->base) ||
				parser_IsExtension(y->type->base, x->type->base)) ||
			   (xf == Proc) && (yf == Proc) && parser_EqualSignatures(x->type, y->type)) {
	  if (rel <= sNEQ) {
		gen_IntRelation(rel, x, y);
	  } else {
	  	as_error("only = or #");
	  }
	} else if ((xf == Array) && (x->type->base->form == Char) &&
			   ((yf == String) || (yf == Array) && (y->type->base->form == Char)) ||
			   (yf == Array) && (y->type->base->form == Char) && (xf == String)) {
	  //gen_StringRelation(rel, x, y);
	} else if ((xf == Char) && (yf == String) && (y->b == 2)) {
	  gen_StrToChar(y);
	  gen_IntRelation(rel, x, y);
	} else if ((yf == Char) && (xf == String) && (x->b == 2)) {
	  gen_StrToChar(x);
	  gen_IntRelation(rel, x, y);
	} else if ((xf == Int) && (yf == Int)) {
	  gen_IntRelation(rel, x, y);  /*BYTE*/
	} else {
	  as_error("illegal comparison");
	}
	x->type = boolType;
  } else if (scanner_sym == osIN) {
	scanner_next();
	parser_CheckInt(x);
	parser_simpleExpression(y);
	parser_CheckSet(y);
	//gen_In(x, y);
	x->type = boolType;
  } else if (scanner_sym == osIS) {
	scanner_next();
	obj = parser_qualident();
	//gen_TypeTest(x, obj->type, 0);
	x->type = boolType;
  }
}

/* statements */

void parser_TypeCase(struct Object *obj, struct Item *x) {
  struct Object *typobj;

  if (scanner_sym == osIDENT) {
	typobj = parser_qualident();
	gen_MakeItem(x, obj, level);
	if (typobj->class != Typ) { as_error("not a type"); }
	gen_TypeTest(x, typobj->type, 0, 0);
	obj->type = typobj->type;
	gen_CFJump(x);
	parser_Check(osCOLON, ": expected");
	parser_StatSequence();
  } else {
	gen_CFJump(x);
	as_error("type id expected");
  }
}

void parser_SkipCase(void) {
  while (scanner_sym != sCOLON) {
	scanner_next();
  }
  scanner_next();
  parser_StatSequence();
}

/* statements */

void parser_StandProc(long pno) {
  long nap; /*nof actual/formal parameters*/
  long npar;
  struct Item *x;
  struct Item *y;
  struct Item *z;

  x = as_malloc(sizeof(struct Item));
  y = as_malloc(sizeof(struct Item));
  z = as_malloc(sizeof(struct Item));
  parser_Check(osLPAREN, "no (");
  npar = pno % 10;
  pno = pno / 10;
  parser_expression(x);
  nap = 1;
  if (scanner_sym == osCOMMA) {
	scanner_next();
	parser_expression(y);
	nap = 2;
	z->type = noType;
	while (scanner_sym == osCOMMA) {
	  scanner_next();
	  parser_expression(z);
	  nap++;
	}
  } else {
	y->type = noType;
  }
  parser_Check(osRPAREN, "no )");
  if ((npar == nap) || (pno <= 1)) {
	if (pno <= 1) { /*INC, DEC*/
	  parser_CheckInt(x);
	  parser_CheckReadOnly(x);
	  if (y->type != noType) {
		parser_CheckInt(y);
	  }
	  gen_Increment(pno, x, y);
	} else if (pno <= 3) { /*INCL, EXCL*/
	  parser_CheckSet(x);
	  parser_CheckReadOnly(x);
	  parser_CheckInt(y);
	  //gen_Include(pno-2, x, y);
	} else if (pno == 4) {
	  parser_CheckBool(x);
	  //gen_Assert(x);
	} else if (pno == 5) { /*NEW*/
	  parser_CheckReadOnly(x);
	  if ((x->type->form == Pointer) && (x->type->base->form == Record)) {
		//gen_New(x);
	  } else {
		as_error("not a pointer to record");
	  }
	} else if (pno == 6) {
	  parser_CheckReal(x);
	  parser_CheckInt(y);
	  parser_CheckReadOnly(x);
	  //gen_Pack(x, y);
	} else if(pno == 7) {
	  parser_CheckReal(x);
	  parser_CheckInt(y);
	  parser_CheckReadOnly(x);
	  //gen_Unpk(x, y);
	} else if (pno == 8) {
	  if (x->type->form <= Set) {
		//gen_Led(x);
	  } else {
		as_error("bad type");
	  }
	} else if (pno == 10) {
	  parser_CheckInt(x);
	  gen_Get(x, y);
	} else if (pno == 11) {
	  parser_CheckInt(x);
	  gen_Put(x, y);
	} else if (pno == 12) {
	  parser_CheckInt(x);
	  parser_CheckInt(y);
	  parser_CheckInt(z);
	  //gen_Copy(x, y, z);
	} else if (pno == 13) {
	  parser_CheckConst(x);
	  parser_CheckInt(x);
	  //gen_LDPSR(x);
	} else if (pno == 14) {
	  parser_CheckInt(x);
	  //gen_LDREG(x, y);
	}
  } else {
	as_error("wrong nof parameters");
  }
}

void parser_StatSequence(void) {
  struct Object *obj;
  struct Type *orgtype; /*original type of case var*/
  struct Item *x = as_malloc(sizeof(struct Item));
  struct Item *y = as_malloc(sizeof(struct Item));
  struct Item *z = as_malloc(sizeof(struct Item));
  struct Item *w = as_malloc(sizeof(struct Item));
  long L0 = 0;
  long L1 = 0;
  long rx = 0;
  
  do { /*sync*/
	obj = 0;
	if (!((scanner_sym >= osIDENT) && (scanner_sym <= osFOR) || (scanner_sym >= osSEMICOLON))) {
	  as_error("statement expected");
	  do {
		scanner_next();
	  } while (scanner_sym < osIDENT);
	}
	if (scanner_sym == osIDENT) {
	  obj = parser_qualident();
	  gen_MakeItem(x, obj, level);
	  if (x->mode == SProc) {
		parser_StandProc(obj->val);
	  } else {
		parser_selector(x);
		if (scanner_sym == osBECOMES) { /*assignment*/
		  scanner_next();
		  parser_CheckReadOnly(x);
		  parser_expression(y);
		  if (parser_CompTypes(x->type, y->type, 0)) {
			if ((x->type->form <= Pointer) || (x->type->form == Proc)) {
			  gen_Store(x, y);
			} else {
			  gen_StoreStruct(x, y);
			}
		  } else if ((x->type->form == Array) && (y->type->form == Array) && (x->type->base == y->type->base) && (y->type->len < 0)) {
			gen_StoreStruct(x, y);
		  } else if ((x->type->form == Array) && (x->type->base->form == Char) && (y->type->form == String)) {
			gen_CopyString(x, y);
		  } else if ((x->type->form == Int) && (y->type->form == Int)) {
			gen_Store(x, y);  /*BYTE*/
		  } else if ((x->type->form == Char) && ((y->type->form == String) && (y->b == 2))) {
			gen_StrToChar(y);
			gen_Store(x, y);
		  } else {
			as_error("illegal assignment");
		  }
		} else if (scanner_sym == osEQL) {
		  as_error("should be :=");
		  scanner_next();
		  parser_expression(y);
		} else if (scanner_sym == osLPAREN) { /*procedure call*/
		  scanner_next();
		  if ((x->type->form == Proc) && (x->type->base->form == NoTyp)) {
			gen_PrepCall(x, &rx);
			parser_ParamList(x);
			gen_Call(x, rx);
		  } else {
			as_error("not a procedure");
			parser_ParamList(x);
		  }
		} else if (x->type->form == Proc) { /*procedure call without parameters*/
		  if (x->type->nofpar > 0) {
			as_error("missing parameters");
		  }
		  if (x->type->base->form == NoTyp) {
			gen_PrepCall(x, &rx);
			gen_Call(x, rx);
		  } else {
			as_error("not a procedure");
		  }
		} else if (x->mode == Typ) {
		  as_error("illegal assignment");
		} else {
		  as_error("not a procedure");
		}
	  }
	} else if (scanner_sym == osIF) {
	  scanner_next();
	  parser_expression(x);
	  parser_CheckBool(x);
	  gen_CFJump(x);
	  parser_Check(osTHEN, "no THEN");
	  parser_StatSequence();
	  L0 = 0;
	  while (scanner_sym == osELSIF) {
		scanner_next();
		gen_FJump(&L0);
		gen_Fixup(x);
		parser_expression(x);
		parser_CheckBool(x);
		gen_CFJump(x);
		parser_Check(osTHEN, "no THEN");
		parser_StatSequence();
	  }
	  if (scanner_sym == osELSE) {
		scanner_next();
		gen_FJump(&L0);
		gen_Fixup(x);
		parser_StatSequence();
	  } else {
		gen_Fixup(x);
	  }
	  // gen_FixLink(L0);
	  parser_Check(osEND, "no END");
	} else if (scanner_sym == osWHILE) {
	  scanner_next();
	  L0 = codegen_here();
	  parser_expression(x);
	  parser_CheckBool(x);
	  gen_CFJump(x);
	  parser_Check(osDO, "no DO");
	  parser_StatSequence();
	  gen_BJump(L0);
	  while (scanner_sym == sELSIF) {
		scanner_next();
		gen_Fixup(x);
		parser_expression(x);
		parser_CheckBool(x);
		gen_CFJump(x);
		parser_Check(osDO, "no DO");
		parser_StatSequence();
		gen_BJump(L0);
	  }
	  gen_Fixup(x);
	  parser_Check(osEND, "no END");
	} else if (scanner_sym == osREPEAT) {
	  scanner_next();
	  L0 = codegen_here();
	  parser_StatSequence();
	  if (scanner_sym == osUNTIL) {
		scanner_next();
		parser_expression(x);
		parser_CheckBool(x);
		gen_CBJump(x, L0);
	  } else {
		as_error("missing UNTIL");
	  }
	} else if (scanner_sym == osFOR) {
	  scanner_next();
	  if (scanner_sym == osIDENT) {
		obj = parser_qualident();
		gen_MakeItem(x, obj, level);
		parser_CheckInt(x);
		parser_CheckReadOnly(x);
		if (scanner_sym == osBECOMES) {
		  scanner_next();
		  parser_expression(y);
		  parser_CheckInt(y);
		  gen_For0(x, y);
		  L0 = codegen_here();
		  parser_Check(osTO, "no TO");
		  parser_expression(z);
		  parser_CheckInt(z);
		  obj->rdo = 1;
		  if (scanner_sym == osBY) {
			scanner_next();
			parser_expression(w);
			parser_CheckConst(w);
			parser_CheckInt(w);
		  } else {
			gen_MakeConstItem(w, intType, 1);
		  }
		  parser_Check(osDO, "no DO");
		  gen_For1(x, y, z, w, &L1);
		  parser_StatSequence();
		  parser_Check(osEND, "no END");
		  gen_For2(x, y, w);
		  gen_BJump(L0);
		  // <gen_FixLink(L1);
		  obj->rdo = 0;
		} else {
		  as_error(":= expected");
		}
	  } else {
		as_error("identifier expected");
	  }
	} else if (scanner_sym == osCASE) {
	  scanner_next();
	  if (scanner_sym == osIDENT) {
		obj = parser_qualident();
		orgtype = obj->type;
		if ((orgtype->form == Pointer) || (orgtype->form == Record) && (obj->class == Par)) {
		  parser_Check(osOF, "OF expected");
		  parser_TypeCase(obj, x);
		  L0 = 0;
		  while (scanner_sym == osBAR) {
			scanner_next();
			gen_FJump(&L0);
			gen_Fixup(x);
			obj->type = orgtype;
			parser_TypeCase(obj, x);
		  }
		  gen_Fixup(x);
		  gen_FixLink(L0);
		  obj->type = orgtype;
		} else {
		  as_error("numeric case not implemented");
		  parser_Check(osOF, "OF expected");
		  parser_SkipCase();
		  while (scanner_sym == osBAR) {
			parser_SkipCase();
		  }
		}
	  } else {
		as_error("ident expected");
	  }
	  parser_Check(osEND, "no END");
	}
	gen_CheckRegs();
	if (scanner_sym == osSEMICOLON) {
	  scanner_next();
	} else if (scanner_sym < osSEMICOLON) {
	  as_error("missing semicolon?");
	}
  } while (scanner_sym <= osSEMICOLON);
}

/* types and declarations */

struct Object *parser_IdentList(int class) {
  struct Object *first;
  struct Object *obj;

  if (scanner_sym == osIDENT) {
	first = base_NewObj(scanner_CopyId(), class);
	scanner_next();
	parser_CheckExport(&first->expo);
	while (scanner_sym == osCOMMA) {
	  scanner_next();
	  if (scanner_sym == osIDENT) {
		obj = base_NewObj(scanner_CopyId(), class);
		scanner_next();
		parser_CheckExport(&obj->expo);
	  } else {
		as_error("ident?");
	  }
	}
	if (scanner_sym == osCOLON) {
	  scanner_next();
	} else {
	  as_error(":?");
	}
  } else {
	first = 0;
  }
  return first;
}

void parser_ArrayType(struct Type *type) {
  struct Item *x;
  struct Type *typ;
  long len;

  x = as_malloc(sizeof(struct Item));
  typ = as_malloc(sizeof(struct Type));
  typ->form = NoTyp;
  parser_expression(x);
  if ((x->mode == Const) && (x->type->form == Int) && (x->a >= 0)) {
	len = x->a;
  } else {
	len = 1;
	as_error("not a valid length");
  }
  if (scanner_sym == osOF) {
	scanner_next();
	typ->base = parser_Type();
	if ((typ->base->form == Array) && (typ->base->len < 0)) {
	  as_error("dyn array not allowed");
	} else if (scanner_sym == osCOMMA) {
	  scanner_next();
	  parser_ArrayType(typ->base);
	}
  } else {
	as_error("missing OF");
	typ->base = intType;
  }
  typ->size = (len * typ->base->size + 3) / 4 * 4;
  typ->form = Array; typ->len = len; type = typ;
}

void parser_RecordType(struct Type *type) {
  struct Object *obj;
  struct Object *obj0;
  struct Object *new;
  struct Object *bot;
  struct Object *base;
  struct Type *typ;
  struct Type *tp;
  long offset;
  long off;
  long n;

  typ = as_malloc(sizeof(struct Type));
  typ->form = NoTyp;
  typ->base = 0;
  typ->mno = -level;
  typ->nofpar = 0;
  offset = 0;
  bot = 0;
  if (scanner_sym == osLPAREN) {
	scanner_next(); /*record extension*/
	if (level != 0) {
	  as_error("extension of local types not implemented");
	}
	if (scanner_sym == osIDENT) {
	  base = parser_qualident();
	  if (base->class == Typ) {
		if (base->type->form == Record) {
		  typ->base = base->type;
		} else {
		  typ->base = intType;
		  as_error("invalid extension");
		}
		typ->nofpar = typ->base->nofpar + 1; /*"nofpar" here abused for extension level*/
		bot = typ->base->dsc;
		offset = typ->base->size;
	  } else {
		as_error("type expected");
	  }
	} else {
	  as_error("ident expected");
	}
	parser_Check(osRPAREN, "no )");
  }
  while (scanner_sym == osIDENT) { /*fields*/
	n = 0; obj = bot;
	while (scanner_sym == osIDENT) {
	  obj0 = obj;
	  while ((obj0 != 0) && (strcmp(obj0->name, scanner_id) != 0)) {
		obj0 = obj0->next;
	  }
	  if (obj0 != 0) {
		as_error("mult def (1)");
	  }
      new = as_malloc(sizeof(struct Object));
	  new->name = scanner_CopyId();
	  new->class = Fld;
	  new->next = obj;
	  obj = new;
	  n++;
	  scanner_next();
	  parser_CheckExport(&new->expo);
	  if ((scanner_sym != osCOMMA) && (scanner_sym != osCOLON)) {
		as_error("comma expected");
	  } else if (scanner_sym == osCOMMA) {
		scanner_next();
	  }
	}
	parser_Check(osCOLON, "colon expected");
	tp = parser_Type();
	if ((tp->form == Array) && (tp->len < 0)) {
	  as_error("dyn array not allowed");
	}
	if (tp->size > 1) {
	  offset = (offset+3) / 4 * 4;
	}
	offset = offset + n * tp->size;
	off = offset;
	obj0 = obj;
	while (obj0 != bot) {
	  obj0->type = tp;
	  obj0->lev = 0;
	  off = off - tp->size;
	  obj0->val = off;
	  obj0 = obj0->next;
	}
	bot = obj;
	if (scanner_sym == osSEMICOLON) {
	  scanner_next();
	} else if (scanner_sym != osEND) {
	  as_error(" ; or END");
	}
  }
 typ->form = Record;
 typ->dsc = bot;
 typ->size = (offset + 3) / 4 * 4;
 type = typ;
}

struct Type *parser_FormalType(int dim) {
  struct Type *typ;
  struct Object *obj;
  long dmy;

  if (scanner_sym == osIDENT) {
	obj = parser_qualident();
	if (obj->class == Typ) {
	  typ = obj->type;
	} else {
	  as_error("not a type");
	  typ = intType;
	}
  } else if (scanner_sym == osARRAY) {
	scanner_next();
	parser_Check(osOF, "OF ?");
	if (dim >= 1) {
	  as_error("multi-dimensional open arrays not implemented");
	}
    typ = as_malloc(sizeof(struct Type));
	typ->form = Array;
	typ->len = -1;
	typ->size = 2*WordSize; 
	typ->base = parser_FormalType(dim+1);
  } else if (scanner_sym == osPROCEDURE) {
	scanner_next();
	base_OpenScope();
	typ = as_malloc(sizeof(struct Type));
	typ->form = Proc;
	typ->size = WordSize;
	dmy = 0;
	parser_ProcedureType(typ, &dmy);
	typ->dsc = topScope->next;
	base_CloseScope();
  } else {
	as_error("identifier expected");
	typ = noType;
  }
  return typ;
}

void parser_CheckRecLevel(int lev) {
  if (lev != 0) { as_error("ptr base must be global"); }
}


void parser_FPSection(long *adr, int *nofpar) {
  struct Object *obj;
  struct Object *first;
  struct Type *tp;
  long parsize;
  int cl;
  bool rdo;
  
  if (scanner_sym == osVAR) {
	scanner_next();
	cl = Par;
  } else {
	cl = Var;
  }
  first = parser_IdentList(cl);
  tp = parser_FormalType(0);
  rdo = false;
  if ((cl == Var) && (tp->form >= Array)) {
	cl = Par;
	rdo = 1;
  }
  if (((tp->form == Array) && (tp->len < 0)) || (tp->form == Record)) {
	parsize = 2 * WordSize; /*open array or record, needs second word for length or type tag*/
  } else {
	parsize = WordSize;
  }
  obj = first;
  while (obj != 0) {
	*nofpar = *nofpar+1;
	obj->class = cl;
	obj->type = tp;
	obj->rdo = rdo;
	obj->lev = level;
	obj->val = *adr;
	*adr = *adr + parsize;
	obj = obj->next;
  }
  if (*adr >= 52) {
	as_error("too many parameters");
  }
}

void parser_ProcedureType(struct Type *ptype, long *parblksize) {
  struct Object *obj;
  long size;
  int nofpar;

  ptype->base = noType;
  size = *parblksize;
  nofpar = 0;
  ptype->dsc = 0;
  if (scanner_sym == osLPAREN) {
	scanner_next();
	if (scanner_sym == osRPAREN) {
	  scanner_next();
	} else {
	  parser_FPSection(&size, &nofpar);
	  while (scanner_sym == osSEMICOLON) {
		scanner_next();
		parser_FPSection(&size, &nofpar);
	  }
	  parser_Check(osRPAREN, "no )");
	}
	if (scanner_sym == osCOLON) { /*function*/
	  scanner_next();
	  if (scanner_sym == osIDENT) {
		obj = parser_qualident();
		ptype->base = obj->type;
		if (!((obj->class == Typ) && (((obj->type->form >= Byte) && obj->type->form <= Pointer)) || (obj->type->form == Proc))) {
		  as_error("illegal function type");
		}
	  } else {
		as_error("type identifier expected");
	  }
	}
  }
  ptype->nofpar = nofpar;
  *parblksize = size;
}

void parser_signature(void) {
}

struct Type *parser_Type(void) {
  struct Type *type = 0;
  long dmy;
  struct Object *obj;
  struct PtrBase *ptbase;
  
  type = intType; /*sync*/
  if ((scanner_sym != osIDENT) && (scanner_sym < osARRAY)) {
	as_error("not a type");
	do {
	  scanner_next();
	} while ((scanner_sym != osIDENT) && (scanner_sym < osARRAY));
  }
  if (scanner_sym == osIDENT) {
	obj = parser_qualident();
	if (obj->class == Typ) {
	  if ((obj->type != 0) && (obj->type->form != NoTyp)) {
		type = obj->type;
	  } else {
		as_error("not a type or undefined");
	  }
	}
  } else if (scanner_sym == osARRAY) {
	scanner_next();
	parser_ArrayType(type);
  } else if (scanner_sym == osRECORD) {
	scanner_next();
	parser_RecordType(type);
	parser_Check(osEND, "no END (1)");
  } else if (scanner_sym == osPOINTER) {
	scanner_next();
	parser_Check(osTO, "no TO");
	type = as_malloc(sizeof(struct Type));
	type->form = Pointer;
	type->size = WordSize;
	type->base = intType;
	if (scanner_sym == osIDENT) {
	  obj = base_thisObj();
	  if (obj != 0) {
		if ((obj->class = Typ) && ((obj->type->form == Record) || (obj->type->form == NoTyp))) {
		  parser_CheckRecLevel(obj->lev);
		  type->base = obj->type;
		} else if (obj->class == Mod) {
		  as_error("external base type not implemented");
		} else {
		  as_error("no valid base type");
		}
	  } else {
		parser_CheckRecLevel(level); /*enter into list of forward references to be fixed in Declarations*/
		ptbase = as_malloc(sizeof(struct PtrBase));
		ptbase->name = scanner_CopyId();
		ptbase->type = type;
		ptbase->next = pbsList;
		pbsList = ptbase;
	  }
	  scanner_next();
	} else {
	  type->base = parser_Type();
	  if ((type->base->form != Record) || (type->base->typobj) == 0) {
		as_error("must point to named record");
	  }
	  parser_CheckRecLevel(level);
	}
  } else if( scanner_sym == osPROCEDURE) {
	scanner_next();
	base_OpenScope();
	type = as_malloc(sizeof(struct Type));
	type->form = Proc;
	type->size = WordSize;
	dmy = 0;
	parser_ProcedureType(type, &dmy);
	type->dsc = topScope->next;
	base_CloseScope();
  } else {
	as_error("illegal type");
  }
  return type;
}

void parser_declarations(long *varsize) {
  struct Object *obj;
  struct Object *first;
  struct Item *x;
  struct Type *tp;
  struct PtrBase *ptbase;
  bool expo;
  char *id;
  
  /*sync*/
  x = as_malloc(sizeof(struct Item));
  pbsList = 0;
  if ((scanner_sym < osCONST) && ((scanner_sym != osEND) && (scanner_sym != osRETURN))) {
	as_error("declaration?");
	do {
	  scanner_next();
	} while ((scanner_sym < osCONST) && ((scanner_sym != osEND) && (scanner_sym != osRETURN)));
  }
  if (scanner_sym == osCONST) {
	scanner_next();
	while (scanner_sym == osIDENT) {
	  id = scanner_CopyId();
	  scanner_next();
	  parser_CheckExport(&expo);
	  parser_Check(osEQL, "= ?");
	  parser_expression(x);
	  if ((x->type->form == String) && (x->b = 2)) {
		gen_StrToChar(x);
	  }
	  obj = base_NewObj(scanner_CopyId(), Const);
	  obj->expo = expo;
	  if (x->mode == Const) {
		obj->val = x->a;
		obj->lev = x->b;
		obj->type = x->type;
	  } else {
		as_error("expression not constant");
		obj->type = intType;
	  }
	  parser_Check(osSEMICOLON, "; missing");
	}
  }
  if (scanner_sym == osTYPE) {
	scanner_next();
	while( scanner_sym == osIDENT) {
	  id = scanner_CopyId();
	  scanner_next();
	  parser_CheckExport(&expo);
	  parser_Check(osEQL, "=?");
	  tp = parser_Type();
	  obj = base_NewObj(scanner_CopyId(), Typ);
	  obj->type = tp;
	  obj->expo = expo;
	  obj->lev = level;
	  if (tp->typobj == 0) {
		tp->typobj = obj;
	  }
	  if (expo && (obj->type->form == Record)) {
		obj->exno = exno;
		exno++;
	  } else {
		obj->exno = 0;
	  }
	  if (tp->form == Record) {
		ptbase = pbsList;  /*check whether this is base of a pointer type; search and fixup*/
		while (ptbase != 0) {
		  if (obj->name == ptbase->name) {
			ptbase->type->base = obj->type;
		  }
		  ptbase = ptbase->next;
		}
		if (level == 0) {
		  gen_BuildTD(tp, &dc);
		}  /*type descriptor; len used as its address*/
	  }
	  parser_Check(osSEMICOLON, "; missing");
	}
  }
  if (scanner_sym == osVAR) {
	scanner_next();
	while (scanner_sym == osIDENT) {
	  first = parser_IdentList(Var);
	  tp = parser_Type();
	  obj = first;
	  while (obj != 0) {
		obj->type = tp;
		obj->lev = level;
		obj->val = *varsize;
		*varsize = *varsize + obj->type->size;
		if (obj->expo) {
		  obj->exno = exno;
		  exno++;
		}
		obj = obj->next;
	  }
	  parser_Check(osSEMICOLON, "; missing");
	}
  }
  ptbase = pbsList;
  while (ptbase != 0) {
	if (ptbase->type->base->form == Int) {
	  as_error("undefined pointer base of");
	}
	ptbase = ptbase->next;
  }
  if ((scanner_sym >= osCONST) && (scanner_sym <= osVAR)) {
	as_error("declaration in bad order");
  }
}

void parser_procedureDecl(void) {
  struct Object *proc;
  struct Type *type;
  char *procid;
  struct Item *x;
  long locblksize;
  long parblksize;
  long L;
  bool interrupt;

  x = as_malloc(sizeof(struct Item));
  interrupt = 0;
  scanner_next();
  if (scanner_sym == osTIMES) {
	scanner_next();
	interrupt = 1;
  }
  if (scanner_sym == osIDENT) {
	procid = scanner_CopyId();
	scanner_next();
	proc = base_NewObj(scanner_CopyId(), Const);
	if (interrupt) {
	  parblksize = 0;
	} else {
	  parblksize = 0;
	}
	type = as_malloc(sizeof(struct Type));
	type->form = Proc;
	type->size = WordSize;
	proc->type = type;
	proc->val = -1;
	proc->lev = level;
	parser_CheckExport(&proc->expo);
	if (proc->expo) {
	  gen_symbol(procid);
	  proc->exno = exno++;
	}
	base_OpenScope();
	level += 1;
	type->base = noType;
	parser_ProcedureType(type, &parblksize); /*formal parameter list*/
	parser_Check(osSEMICOLON, "no ; (1)");
	locblksize = 0;
	parser_declarations(&locblksize);
	proc->val = codegen_here();
	proc->type->dsc = topScope->next;
	if (scanner_sym == osPROCEDURE) {
	  L = 0;
	  gen_FJump(&L);
	  do {
		parser_procedureDecl();
		parser_Check(osSEMICOLON, "no ; (2)");
	  } while (scanner_sym == osPROCEDURE);
	  //gen_FixOne(L);
	  proc->val = codegen_here();
	  proc->type->dsc = topScope->next;
	}
	gen_Enter(proc->name, parblksize, locblksize, interrupt);
	if (scanner_sym == osBEGIN) {
	  scanner_next();
	  parser_StatSequence();
	}
	if (scanner_sym == osRETURN) {
	  scanner_next();
	  parser_expression(x);
	  if (type->base == noType) {
		as_error("this is not a function");
	  } else if (!parser_CompTypes(type->base, x->type, 0)) {
		as_error("wrong result type");
	  }
	} else if (type->base->form != NoTyp) {
	  as_error("function without result");
	  type->base = noType;
	}
	gen_Return(proc, x, parblksize + locblksize, interrupt);
	base_CloseScope();
	level = level - 1;
	parser_Check(osEND, "no END (2)");
	if (scanner_sym == osIDENT) {
	  if (strcmp(scanner_id, procid) != 0) {
		as_error("no match %s %s", scanner_id, procid);
	  }
	  scanner_next();
	} else {
	  as_error("no proc id");
	}
  } else {
	as_error("proc id expected");
  }
}

void parser_import(void) {
  char *impid;
  char *impid1;

  if (scanner_sym == osIDENT) {
	impid = scanner_CopyId();
	scanner_next();
	if (scanner_sym == osBECOMES) {
	  scanner_next();
	  if (scanner_sym == osIDENT) {
		impid1 = scanner_CopyId();
		scanner_next();
	  } else {
        as_error("id expected");
		impid1 = impid;
	  }
	} else {
	  impid1 = impid;
	}
	base_Import(impid, impid1);
  } else {
	as_error("id expected");
  }
}

void parser_module(void) {
  long key;

  printf( "  compiling\n");
  scanner_next();
  if (scanner_sym == osMODULE) {
	scanner_next();
	if (scanner_sym == osTIMES) {
	  dc = 8;
	  printf("*");
	  scanner_next();
	} else {
	  dc = 0;
	}
	base_init();
	base_OpenScope();
	if (scanner_sym == osIDENT) {
	  modid = scanner_CopyId();
	  printf("%s\n", modid);
	  scanner_next();
	} else {
	  as_error("identifier expected");
	}
	parser_Check(osSEMICOLON, "no ; (3)"); level = 0; exno = 1; key = 0;
	if (scanner_sym == osIMPORT) {
	  scanner_next();
	  parser_import();
	  while (scanner_sym == osCOMMA) { scanner_next(); parser_import(); }
	  parser_Check(osSEMICOLON, "; missing");
	}
	gen_open(modid);
	parser_declarations(&dc);
	gen_setDataSize((dc + 3) / 4 * 4);
	while (scanner_sym == osPROCEDURE) {
	  parser_procedureDecl();
	  parser_Check(osSEMICOLON, "no ; (4)");
	}
	gen_header();
	if (scanner_sym == osBEGIN) {
	  scanner_next();
	  parser_StatSequence();
	}
	parser_Check(osEND, "no END (3)");
	if (scanner_sym == osIDENT) {
	  if (strcmp(scanner_id, modid) != 0) { as_error("no match"); }
	  scanner_next();
	} else { as_error("identifier missing"); }
	if (scanner_sym != osPERIOD) { as_error("period missing"); }
	if (scanner_errcnt == 0) {
	  base_export(modid, newSF, key);
	  if (newSF) { printf(" new symbol file\n"); }
	  gen_close(modid, key, exno);
	  //printf("%d %ld %0lx'", codegen_here(), dc, key);
	} else {
	  printf("\ncompilation FAILED\n");
	}
	printf("\n");
	base_CloseScope();
	pbsList = 0;
  } else {
	as_error("must start with MODULE");
  }
}

void compile(const char* file) {
  bf_init();
  bf_open(file);
  scanner_init();
  scanner_start();
  parser_module();
  bf_close();
}

int main(int argc, char** argv) {
  printf("Oberon Compiler 19.06.2024\n");
  dummy = as_malloc(sizeof(struct Object));
  dummy->class = Var;
  dummy->type = intType;
  
  compile(argv[1]);
  return 0;
}
