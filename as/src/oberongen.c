#include "oberongen.h"
#include "interp.h"
#include "cpu.h"
#include "memory.h"
#include "as.h"
#include "codegen.h"

/*
oberongen.c - Oberon code generator

Copyright 2022 Jason Swain
 */


/* Instructions */

void add_instr(OpCode instr, AddrMode mode, Modifier modifier)
{
  char buffer[20];
  
  Object *line = object_new(Const, typeString);
  sprintf(buffer, "%s\n", token_to_string(instr));
  line->string_val = as_strdup(buffer);
  interp_add_instr(instr, mode, modifier);
  interp_add(OpListLine, line);
  object_release(line);
}

void add_instr_int(OpCode instr, AddrMode mode, Modifier modifier, int value)
{
  char buffer[20];

  Object *val = object_new(Const, typeInt);
  val->int_val = value;
  interp_add(OpPush, val);
  object_release(val);
  
  interp_add_instr(instr, mode, modifier);

  Object *line = object_new(Const, typeString);
  sprintf(buffer, "%s %s\n", token_to_string(instr), codegen_format_mode(mode, value, 0, 0));
  line->string_val = as_strdup(buffer);
  interp_add(OpListLine, line);
  object_release(line);
}

void add_instr_object(OpCode instr, AddrMode mode, Modifier modifier, Object *label)
{
  char buffer[40];

  interp_add(OpPushVar, label);
  interp_add_instr(instr, mode, modifier);  

  Object *line = object_new(Const, typeString);
  sprintf(buffer, "%s %s\n", token_to_string(instr), codegen_format_mode_str(mode, label->string_val, 0, 0));
  line->string_val = as_strdup(buffer);
  interp_add(OpListLine, line);
  object_release(line);
}

/* Registers */

/* Registers are allocated as a stack */
const int REG_BASE = 0x10;

int rh = 0; /* The address of the next available register */
const int rmax = 8;

int reg_addr(int reg)
{
  return REG_BASE + reg * WordSize;
}

bool oberon_load_a(Item *x)
{
  if (x->mode == Reg) {
	/* Code assumes that A contains the value, so we need to load it here */
	add_instr_int(sLDA, DirectPage, MWord, reg_addr(x->r));
	return false;
  }
  
  switch (x->mode) {
  case Const:
	add_instr_int(sLDA, Immediate, MWord, x->a);
	break; 
  case Var:
	add_instr_int(sLDA, StackRelative, MWord, x->a + 1);
	break;
  case Par: 
	add_instr_int(sLDA, StackRelative, MWord, x->a + 1);
	break;
  default:
	break;
  }

  return true;
}

bool oberon_load(Item *x) {
  if (oberon_load_a(x)) {

	x->r = rh;
	rh += 1;

	add_instr_int(sSTA, DirectPage, MWord, reg_addr(x->r));

	x->mode = Reg;

	if (rh <= rmax) {
	  return true;
	} else {
	  as_error("Registers over-allocated");
	  return false;
	}
  }
  return false;
}

void oberon_unload(void)
{
  rh -= 1;
}


/*
Adds an object into the scope for compiler defined items such as basic types
and system functions.
*/
void scope_enter(char *name, Form form, Type *tp, int val)
{
  Object *object = object_new(form, tp);
  object->type = type_retain(tp);
  object->int_val = val;
  scope_add_object(name, object);
  object_release(object);
}

void oberon_init(void)
{

  /* Types */
  scope_enter("SET", Typ, typeSet, 0);
  scope_enter("BOOLEAN", Typ, typeBool, 1);
  scope_enter("BYTE", Typ, typeByte, 1);
  scope_enter("CHAR", Typ, typeChar, 1);
  scope_enter("REAL", Typ, typeReal, 4);
  scope_enter("INTEGER", Typ, typeInt, WordSize);

  /* Procedures */
  scope_enter("NEW", SProc, typeNoType, 11);
  scope_enter("ASSERT", SProc, typeNoType, 22);
  scope_enter("DEC", SProc, typeNoType, 31);
  scope_enter("INC", SProc, typeNoType, 41);
  scope_enter("GET", SProc, typeNoType, 102);
  scope_enter("PUT", SProc, typeNoType, 112);

  
  /* Functions */
  scope_enter("LEN", SFunc, typeInt, 11);
  scope_enter("CHR", SFunc, typeChar, 21);
  scope_enter("ORD", SFunc, typeInt, 31);
  scope_enter("FLT", SFunc, typeReal, 41);
  scope_enter("FLOOR", SFunc, typeInt, 51);
  scope_enter("ODD", SFunc, typeBool, 61);
  scope_enter("ABS", SFunc, typeInt, 71);

}

/* Items: Conversion from constants or from Objects on the heap to items in rodata */
Item *item_makeConst(int val)
{
  elf_section_t* rodata = elf_context->section_rodata;
  // int addr = rodata->shdr->sh_size;
  
  // Add the string to the rodata section
  buf_add_char(&(rodata->data), &(rodata->shdr->sh_size), (char)(val & 0xff));
  buf_add_char(&(rodata->data), &(rodata->shdr->sh_size), (char)(val >> 16) & 0xff);

  // Make the item point to it
  Item *item = as_mallocz(sizeof(Item));
  item->mode = Const;
  item->type = type_retain(typeInt);
  item->a = val; // Test addr;
  item->b = 2;

  return item;
}

Item *item_makeReal(float val)
{
  elf_section_t* rodata = elf_context->section_rodata;
  int addr = rodata->shdr->sh_size;
  
  // Add the string to the rodata section
  //  buf_add_char(&(rodata->data), &(rodata->shdr->sh_size), (char *)&val + 0);
  //  buf_add_char(&(rodata->data), &(rodata->shdr->sh_size), (char *)&val + 1);
  //  buf_add_char(&(rodata->data), &(rodata->shdr->sh_size), (char *)&val + 2);
  //  buf_add_char(&(rodata->data), &(rodata->shdr->sh_size), (char *)&val + 3);

  // Make the item point to it
  Item *item = as_mallocz(sizeof(Item));
  item->mode = Const;
  item->type = type_retain(typeReal);
  item->a = addr;
  item->b = 4;

  return item;
}

Item *item_makeString(const char *str)
{
  elf_section_t* rodata = elf_context->section_rodata;
  int addr = rodata->shdr->sh_size;
  
  // Add the string to the rodata section
  buf_add_string(&(rodata->data), &(rodata->shdr->sh_size), str);

  // Make the item point to it
  Item *item = as_mallocz(sizeof(Item));
  item->mode = Const;
  item->type = type_retain(typeString);
  item->a = addr;
  item->b = strlen(str);

  return item;
}

Item *item_make(Object *object, long curlev)
{
  Item *item = as_mallocz(sizeof(Item));
  item->mode = object->mode;
  item->type = type_retain(object->type);
  item->readonly = object->readonly;
  if (object->mode == Par) {
	item->b = 0;
  } else if ((object->mode == Const) && (object->type == typeString)) {
	item->b = object->level; /* len */ 
  } else {
	item->r = object->level;
	item->a = object->addr;
  }
  if ((object->level > 0) && (object->level != curlev) && (object->mode != Const)) {
	as_error("Not accessible");
  }
  return item;
}

void oberon_store(Item *x, Item *y) { /* x := y */

  switch (x->mode) {
  case Var:
	switch (y->mode) {
	case Const:
	  add_instr_int(sLDA, Immediate, MWord, y->a);
	  break;
	case Var:
	  add_instr_int(sLDA, StackRelative, MWord, y->a + 1);
	  break;
	case Reg:
	  add_instr_int(sLDA, DirectPage, MWord, reg_addr(y->r));
	  break;
	default:
	  break;
	}
	add_instr_int(sSTA, StackRelative, MWord, x->a + 1);
	break;
  case Par:
	switch (y->mode) {
	case Const:
	  add_instr_int(sPEA, Immediate, MWord, y->a);
	  break;
	case Var:
	  add_instr_int(sLDA, StackRelative, MWord, y->a + 1);
	  add_instr(sPHA, Implied, MWord);
	  break;
	case Reg:
	  add_instr_int(sLDA, DirectPage, MWord, reg_addr(y->r));
	  add_instr(sPHA, Implied, MWord);
	  break;
	default:
	  break;
	}
	break;
  case Fld:
	break;
  case Typ:
  case SProc:
  case SFunc:
  case Const:
  case Macro:
  case Reg:
	as_error("Bad mode in store");
  }
}

/* Utility functions */

void oberon_stringToChar(Item *x) {
  x->type = type_retain(typeChar);
  /* DEC(strx, 4) */
  // x->a = (char)str[x->a];
}

/* Code generaton for Selectors, Variables, Constants */
/*
void field(item, object) / * x := x.y * /
{
}

void index(item, item) / * x := x[y] * /
{
}

void deref(item)
{
}

void Q(type, long)
{
}

void findPointerFields(type, offset, dcw)
{
}

void buildTD(type, long dc)
{
}
*/
void oberon_typeTest(Item *x, Type* t, bool varpar, bool isguard)
{
  /*
    VAR pc0: LONGINT;
  BEGIN (*fetch tag into RH*)
    IF varpar THEN Put2(Ldr, RH, SP, x.a+4+frame)
    ELSE load(x);
      pc0 := pc; Put3(BC, EQ, 0);  (*NIL belongs to every pointer type*)
      Put2(Ldr, RH, x.r, -8)
    END ;
    Put2(Ldr, RH, RH, T.nofpar*4); incR;
    loadTypTagAdr(T);  (*tag of T*)
    Put0(Cmp, RH-1, RH-1, RH-2); DEC(RH, 2);
    IF ~varpar THEN fix(pc0, pc - pc0 - 1) END ;
    IF isguard THEN
      IF check THEN Trap(NE, 2) END
    ELSE SetCC(x, EQ);
      IF ~varpar THEN DEC(RH) END
    END
  */
}

/* Code generation for boolean operators */

void oberon_not(Item *x) /* x := ~x */
{
  /* int t; */
  /* if (x->mode != ModeCond) { */
  /* 	oberon_loadCond(x); */
  /* } */
  /* x->r = oberon_negated(x->r); */
  /* t = x->a; */
  /* x->a = x->b; */
  /* x->b = t; */
}

void oberon_and1(Item *x) /*x := x & */
{
}

void oberon_and2(Item *x, Item *y)
{
}

void oberon_or1(Item *x) /* x := x OR */
{
}

void oberon_or2(Item *y)
{
}

/* Code generation for arithmetic operators */

void oberon_neg(Item *x) /* x := -x */
{
  /* if (x->type->form == IntForm) { */
  /* 	if (x->mode == Const) { */
  /* 	  x->a = -x->a; */
  /* 	} else { */
  /* 	  oberon_load(x); */
  /* 	  /\* Negate code *\/ */
  /* 	} else if (x->type->form == Real) { */
  /* 	  if (x->mode == Const) { */
  /* 		x->a = x->a + 0x7fffffff + 1; */
  /* 	  } else { */
  /* 		oberon_load(x); */
  /* 		/\* Negate real *\/ */
  /* 	  } */
  /* 	} else { /\* Form == Set *\/ */
  /* 	  if (x->mode == Const) { */
  /* 		x->a = -x->a-1; */
  /* 	  } else { */
  /* 		oberon_load(x); */
  /* 		interp_add_instr(sXOR); */
  /* 		interp_add_instr(sDEC); */
  /* 	  } */
  /* 	} */
  /* } */
}

void oberon_addOp(Symbol op, Item *x, Item *y) /* rx := rx +- ry */
{
  if ((x->mode == Const) && (y->mode == Const)) {
	if (op == sPLUS) {
	  x->a = x->a + y->a;
	} else {
	  x->a = x->a - y->a;
	}
  } else if ((y->mode == Const) && (y->a != 0)) {
	oberon_load(x);
	/* Still in A, so don't need to do this add_instr_int(sLDA, DirectPage, MWord, reg_addr(x->r)); */
	
	if (op == sPLUS) {
	  add_instr(sCLC, Implied, MWord);
	  add_instr_int(sADC, Immediate, MWord, y->a);
	} else {
	  add_instr(sSEC, Implied, MWord);
	  add_instr_int(sSBC, Immediate, MWord, y->a);
	}
	add_instr_int(sSTA, DirectPage, MWord, reg_addr(x->r));
  } else {
	oberon_load(y);
	oberon_load(x);
	
	if (op == sPLUS) {
	  add_instr(sCLC, Implied, MWord);
	  add_instr_int(sADC, StackRelative, MWord, y->a + 1);
	} else {
	  add_instr(sSEC, Implied, MWord);
	  add_instr_int(sSBC, StackRelative, MWord, y->a + 1);
	}
	add_instr_int(sSTA, DirectPage, MWord, reg_addr(x->r));
  }
}

void log2Func(void)
{
}

void oberon_mulOp(Item *x, Item *y)
{
  /*
if both are consts then calculate now and just load a const

if x or y is a const then
  if const is 2 shift left
  if const is 4 shift left twice
  if const is 8 shift left 4 times etc.
  if const is 10 then shift 4 and add to shift 2, 10x = 8x + 2x

lda #0 ; Result
mult1 LDX rega
      BEQ done
      LSR rega
      BCC mult2
      CLC
      ADC regb

mult2 ASL regb
      BRA mult1

done  RTS

; https://llx.com/Neil/a2/mult.html
        LDA #0       ;Initialize RESULT to 0
        LDX #16      ;There are 16 bits in NUM2
L1      LSR r1     ;Get low bit of NUM2
        BCC L2       ;0 or 1?
        CLC          ;If 1, add NUM1
        ADC r0
L2      ROR A        ;"Stairstep" shift (catching carry from add)
        ROR r2
        DEX
        BNE L1
        STA r3
  */
}

void oberon_divOp(Symbol sym, Item *x, Item *y)
{
}

void oberon_realOp(Symbol sym, Item *x, Item *y)
{
}


/* Code generaton for set operators */

void oberon_singleton(Item *x) /* x := {x} */
{
}

void oberon_set(void) /* x := {x..y} */
{
}

void oberon_in(Item *x, Item *y) /* x := x in y */
{
}

void oberon_setOp(Symbol sym, Item *x, Item *y) /* x := x op y */
{
}

/* Code generaton for relations */

void oberon_intRelation(Symbol rel, Item *x, Item *y) /* x := x < y */
{
  if ((x->mode == Const) && (y->mode == Const)) {
	switch (rel) {
	case sEQL:
	  x->a = x->a == y->a; break;
	case sNEQ:
	  x->a = x->a != y->a; break;
	case sLSS:
	  x->a = x->a < y->a; break;
	case sLEQ:
	  x->a = x->a <= y->a; break;
	case sGTR:
	  x->a = x->a > y->a; break;
	case sGEQ:
	  x->a = x->a >= y->a; break;
	}
  } else if (y->mode == Const) {
	oberon_load(x);
	/* Still in A, so don't need to do this add_instr_int(sLDA, DirectPage, MWord, reg_addr(x->r)); */

	switch (rel) {
	case sEQL:
	  add_instr_int(sCMP, Immediate, MWord, y->a);
	  // BEQ +4
		
	  x->a = x->a == y->a; break;
	case sNEQ:
	  x->a = x->a != y->a; break;
	case sLSS:
	  x->a = x->a < y->a; break;
	case sLEQ:
	  x->a = x->a <= y->a; break;
	case sGTR:
	  x->a = x->a > y->a; break;
	case sGEQ:
	  x->a = x->a >= y->a; break;
	}
	/*
	if (op == sPLUS) {
	  add_instr(sCLC, Implied, MWord);
	  add_instr_int(sADC, Immediate, MWord, y->a);
	} else {
	  add_instr(sSEC, Implied, MWord);
	  add_instr_int(sSBC, Immediate, MWord, y->a);
	}
	*/
	add_instr_int(sSTA, DirectPage, MWord, reg_addr(x->r));
  } else {
	oberon_load(y);
	oberon_load(x);
	/*
	if (op == sPLUS) {
	  add_instr(sCLC, Implied, MWord);
	  add_instr_int(sADC, StackRelative, MWord, y->a + 1);
	} else {
	  add_instr(sSEC, Implied, MWord);
	  add_instr_int(sSBC, StackRelative, MWord, y->a + 1);
	}
	*/
	add_instr_int(sSTA, DirectPage, MWord, reg_addr(x->r));
  }
}

void oberon_realRelation(Symbol rel, Item *x, Item *y) /* x := x < y */
{
}

void oberon_stringRelation(Symbol rel, Item *x, Item *y) /* x := x < y */
{
}

/* Code generation of assignments */
/*
void strToChar()
{
}

void storeStruct()
{
}

void copyString()
{
}
*/
/* Code generation for parameters */

void oberon_openArrayParam(Item *x)
{
}

void oberon_varParam(Item *x, Type *typ)
{
  if (x->mode == Const) {
	add_instr_int(sPEA, Immediate, MWord, x->a);
  } else {
	oberon_load_a(x);
	add_instr(sPHA, Implied, MWord);
  }
}

void oberon_valueParam(Item *x)
{
  if (x->mode == Const) {
	add_instr_int(sPEA, Immediate, MWord, x->a);
  } else {
	oberon_load_a(x);
	add_instr(sPHA, Implied, MWord);
  }
}

void oberon_stringParam(Item *x)
{
}

/* For statements */

void oberon_for0(Item *x, Item *y)
{
}

void oberon_for1(void)
{
}

void oberon_for2(void)
{
}

/* Branches, procedure calls, procedure prolog and epilog */

Object * oberon_new_label(void) /* private */
{
  static int labelIndex = 0;
  char buf[12];
  Object *label = object_new(Const, typeString);
  sprintf(buf, "l%i", labelIndex++);
  label->string_val = as_strdup((char *)&buf);
  return label;
}

void oberon_here(Object *label)
{
  interp_add(OpLabel, label);
}

void oberon_jump(Object *destLabel)
{
  add_instr_object(sBRA, ProgramCounterRelative, MLong, destLabel);
}

void oberon_cjump(Object *label, Item *x)
{
  Object *destLabel = oberon_new_label();
  add_instr_int(sCMP, Immediate, MWord, x);
  add_instr_object(sBNE, ProgramCounterRelative, MLong, label);
}

void oberon_saveRegs(int c)
{
  int i = 0;
  while (i < c) {
	add_instr_int(sLDA, DirectPage, MLong, reg_addr(i));
	add_instr(sPHA, Implied, MLong);
	i++;
  }
}

void oberon_restoreRegs(int c)
{
  int i = c;
  while (i > 0) {
	i--;
	add_instr(sPLA, Implied, MLong);
	add_instr_int(sSTA, DirectPage, MLong, reg_addr(i));
  }
}

int oberon_prepCall(Item *x) /* x->type->form = ProcForm */
{
  int r;
  int rhs = rh;
  
  if (x->mode > Par) {
	oberon_load(x);
  }
  r = rh;
  if (rh > 0) {
	oberon_saveRegs(rhs); 
	rh = 0;
  }
  return r;
}

void oberon_call(Object *object, long rx)
{
  int rp = 0; /* Param register count */
  if (rh > 0) {
	rp = rh;
	oberon_saveRegs(rp);
  }

  add_instr_object(sJSL, AbsoluteLong, MLong, object);

  for (int i = 0; i < rp; i++ ) { /* Pop the params */
	add_instr(sPLA, Implied, MLong);
  }
  
  if (rx > 0) { /* Restore the registers */
	oberon_restoreRegs(rx);
  }
  
  /* x.type.form = ORB.Proc * /
  if (object->mode == ORB.Const) {
	if (x.r >= 0) {
	  //Put3(BL, 7, (x.a DIV 4)-pc-1)
	  add_instr_object(sJSL, AbsoluteLong, MLong, object);
	} else { /* imported * /
	  //IF pc - fixorgP < 1000H THEN
      //    Put3(BL, 7, ((-x.r) * 100H + x.a) * 1000H + pc-fixorgP); fixorgP := pc-1
      //  ELSE ORS.Mark("fixup impossible")
	}
  } else {
	if (object->mode <= ORB.Par) {
	  load(x);
	  RH--;
	} else {
	  // Put2(Ldr, RH, SP, 0);
	  // Put1(Add, SP, SP, 4);
	  // DEC(r);
	  // DEC(frame, 4)
	}
	if (check()) {
	  // Trap(EQ, 5)
	}
	// Put3(BLR, 7, RH)
  }
  if (object->type->base->form == NoType) { /*procedure* /
	RH = 0;
  } else { /* function * /
	if (r > 0) {
	  //Put0(Mov, r, 0, 0);
	  oberon_restoreRegs(rx);
	}
	x->mode = Reg;
	x->r = r;
	RH = r + 1;
  }
  */
}

void oberon_app_startup()
{
  /* Ensure we are in native mode, not needed once we have OS */
  add_instr(sCLC, Implied, MWord);
  add_instr(sXCE, Implied, MWord);
  add_instr_int(sREP, Immediate, MByte, 0x30);

  add_instr_int(sLDA, Immediate, MWord, 0x1000);
  add_instr(sTAS, Implied, MWord);

  /* This code should now JSR to the actual main function */
  Object *label = object_new(Const, typeString);
  label->string_val = as_strdup("App.main");
  add_instr_object(sJSL, AbsoluteLong, MLong, label);
  object_release(label);
  
  /* Once returning we should call os_exit with the correct exit code */
  add_instr(sBRK, Implied, MByte);
}

void oberon_enter(Object *proc, int parblksize, int locblksize, bool isInt)
{
  if (isInt) {
	/* Interrupt saves Flags, A, X, Y */
	add_instr(sPHP, Implied, MLong);
	add_instr_int(sSEP, Immediate, MByte, 0x30);
	add_instr(sPHA, Implied, MLong);
	add_instr(sPHX, Implied, MLong);
	add_instr(sPHY, Implied, MLong);
  } else {
	if (locblksize > 255) {
	  as_error("Too many locals");
	}
	add_instr(sTSA, Implied, MLong);
	add_instr(sSEC, Implied, MLong);
	add_instr_int(sSBC, Immediate, MLong, locblksize);
	add_instr(sTAS, Implied, MLong);
  }
  rh = 0;
}

void oberon_return(Form form, Item *x, int size, bool isInt)
{
  /* Tidy up the stack */
  add_instr(sTSA, Implied, MLong);
  add_instr(sCLC, Implied, MLong);
  add_instr_int(sADC, Immediate, MLong, size);
  add_instr(sTAS, Implied, MLong);

  if (!isInt) {
	add_instr(sRTL, Implied, MLong);
  } else { /* Interrupt return */
	add_instr(sPLY, Implied, MLong);
	add_instr(sPLX, Implied, MLong);
	add_instr(sPLA, Implied, MLong);
	add_instr(sPLP, Implied, MByte); /* Restores MX */	
	add_instr(sRTI, Implied, MLong);
  }

  if (form != NoTypeForm) { /* Store the return value as the top param on the stack */
	oberon_load(x);
	add_instr_int(sSTA, StackRelative, MWord, 1);
  }


}

/* Inline code procedures */

void oberon_increment(void)
{
}

void oberon_include(void)
{
}

void oberon_assert(void)
{
}

void oberon_new(void)
{
}

void oberon_pack(void)
{
}

void oberon_unpack(void)
{
}

void oberon_led(void)
{
}

void oberon_get(Item *x, Item *y)
{
}

void oberon_put(Item *x, Item *y)
{
  bool loaded = oberon_load(y);
  add_instr_int(sSTA, Absolute, MLong, x->a);
  if (loaded) oberon_unload();
}

void oberon_copy(void)
{
}

void oberon_ldpsr(void)
{
}

void oberon_ldreg(void)
{
}

/* Inline code functions */

void oberon_abs(void)
{
}

void oberon_odd(void)
{
}

void oberon_floor(void)
{
}

void oberon_float(void)
{
}

void oberon_ord(void)
{
}

void oberon_len(void)
{
}

void oberon_shift(void)
{
}

void oberon_adc(void)
{
}

void oberon_sbc(void)
{
}

void oberon_uml(void)
{
}

void oberon_bit(void)
{
}

void oberon_register(void)
{
}

void oberon_h(void)
{
}

void oberon_adr(void)
{
}

void oberon_condition(void)
{
}

void oberon_open(void)
{
}

void oberon_setDataSize(void)
{
}

void oberon_header(void)
{
}

void oberon_nOfPointers(void)
{
}

void oberon_findPointers(void)
{
}

void oberon_close(void)
{
}


