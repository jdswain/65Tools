#include "ocg.h"

#include <stdio.h>
#include <stdlib.h>
#include "buffered_file.h"
#include "codegen.h"

/*
  This is a code generator for the 65C816 cpu native mode.

  The runtime environment is as follows:

  There are 8 16-bit registers in direct page, R0-R7.

  A small memory model is used, all pointers are 16-bit. This means a module cannot
  be larger than 64k.

  Calls between modules are long calls.

  Code generated is relocatable. A relocation table is generated, the relocations
  and imports must be resolved at load time.

  ToDo
  ----

  x Integer maths
  x Integer assignment
  x Proc call
  x Integer Parameters
  x Reg Stack Error
  x Return value
  x shared library
  x write elf file
  x long calls for exported functions
  x symbols for exported functions
  x multiplication
  x SProcs and SFuncs
  x Hex and binary
  - IF statement and conditions
  Boolean and Char types
  Var params (data pointers)
  x Consts
  Strings, Arrays, Records
  Array initiaisers
  Check Reg save and restore
  Division
  Modulo
  Real type (use SANE?)
  
  Bresenham
    Boolean type
	REPEAT
	IF
	x SYSTEM.Put
	x Graphics
	
  Linker script
  Module import
  Relocatable code
  Optimisations
  - remove unneeded loads, maybe avoid registers?
  - remove unnecessary stores
  - return in A?
  x Restore ELF loader in em16

  OS Kernel
  Drivers
  Relocating ELF loader
  Graphics
  Editor
  
 */
#define maxTD 160 /*max type definitions*/
#define maxCode 0x8000 /*max code size*/
#define MT 16 /*dedicated register*/
#define maxStrx 2400 /*max strtab*/

#define var_base 0x4000

int RH;
bool check;
long fixorgP;
long tdx;
long strx;
long frame;  /*frame offset changed in SaveRegs and RestoreRegs*/
char str[maxStrx];

FILE *asmf;

void gen_incR(void) {
  if (RH < MT-1) {
	RH = RH + 1;
  } else {
	as_error("register stack overflow");
  }
}

void gen_CheckRegs(void) {
  if (RH != 0) { as_error("Reg Stack"); RH = 0; }
  // if (codegen_here() >= maxCode - 40) { as_error("program too long"); }
  if (frame != 0) { as_error("frame error"); frame = 0; }
}

void gen_Trap(long cond, long num) {
}

/* instructions */

void gen_println(void) {
  fprintf(asmf, "\n");
}

void gen_assign(const char *key, const char *value) {
  fprintf(asmf, "        %s := %s\n", key, value);
}

void gen_symbol(const char *label) {
  fprintf(asmf, "%s:\n", label);
  elf_symbol_create(elf_context, label, codegen_here(), 4, 0);
}

void gen_instr(Symbol op, AddrMode mode, Modifier modifier, int addr) {
  Instr instr;
  instr.opcode = op;
  instr.mode = mode;
  instr.modifier = modifier;
  codegen_gen("module", bf_line(), &instr, addr, 0, 0);
}

void gen_abs(Symbol op, int addr) {
  fprintf(asmf, "        %s $%04x ; %04lx\n", token_to_string(op), addr, codegen_here());
  gen_instr(op, Absolute, MWord, addr);
}

void gen_absl(Symbol op, int addr) {
  fprintf(asmf, "        %s $%06x ; %04lx\n", token_to_string(op), addr, codegen_here());
  gen_instr(op, AbsoluteLong, MLong, addr);
}

long gen_dp(Symbol op, int addr) {
  long pc = codegen_here();
  fprintf(asmf, "        %s $%02x ;%04lx\n", token_to_string(op), addr, pc);
  gen_instr(op, DirectPage, MDirect, addr);
  return pc;
}

void gen_dpix(Symbol op, int addr) {
  fprintf(asmf, "        %s $%02x,X ;%04lx\n", token_to_string(op), addr, codegen_here());
  gen_instr(op, DirectPageIndexedX, MDirect, addr);
}

void gen_dpind(Symbol op, int addr) {
  fprintf(asmf, "        %s ($%02x) ;%04lx\n", token_to_string(op), addr, codegen_here());
  gen_instr(op, DirectPageIndirect, MDirect, addr);
}

void gen_dpindy(Symbol op, int addr) {
  fprintf(asmf, "        %s ($%02x),Y ;%04lx\n", token_to_string(op), addr, codegen_here());
  gen_instr(op, DirectPageIndirectIndexedY, MDirect, addr);
}

void gen_sr(Symbol op, int r) {
  fprintf(asmf, "        %s $%02x,S ;%04lx\n", token_to_string(op), r+1, codegen_here());
  gen_instr(op, StackRelative, MDirect, r+1);
}

void gen_impl(Symbol op) {
  fprintf(asmf, "        %s ; %04lx\n", token_to_string(op), codegen_here());
  gen_instr(op, Implied, MNone, 0);
}

void gen_immb(Symbol op, int b) {
  fprintf(asmf, "        %s #$%02x ; %04lx\n", token_to_string(op), b, codegen_here());
  gen_instr(op, Immediate, MByte, b);
}

void gen_immw(Symbol op, int w) {
  fprintf(asmf, "        %s #$%04x ; %04lx\n", token_to_string(op), w, codegen_here());
  gen_instr(op, Immediate, MWord, w);
}

int gen_rel(Symbol op, int a) {
  long pc = codegen_here();
  fprintf(asmf, "        %s $%02lx\n ; %04lx", token_to_string(op), pc-a, codegen_here());
  gen_instr(op, Absolute, MNone, a);
  return pc;
}

void gen_long(int a, int i) {
  if ((a != codegen_longa()) || (i != codegen_longi())) {
	if (a) {
	  fprintf(asmf, "        longa=on\n");
	} else {
	  fprintf(asmf, "        longa=ff\n");
	}
	if (i) {
	  fprintf(asmf, "        longi=on\n");
	} else {
	  fprintf(asmf, "        longi=ff\n");
	}
	if (a || i ) {
	  gen_immb(sREP, (a << 5) | (i << 4));
	}
	if (!a || !i) {
	  gen_immb(sSEP, (!a << 5) | (!i << 4));
	}
	codegen_setlonga(a);
	codegen_setlongi(i);
  }
}

/*handling of forward reference, fixups of branch addresses and constant tables*/

int gen_negated(int op) {
  	switch (op) {
	case osLSS: return osGEQ;
	case osLEQ: return osGTR;
	case osGEQ: return osLSS;
	case osEQL: return osNEQ;
	case osGTR: return osLEQ;
	case osNEQ: return osEQL;
	}
	return osNEQ;
}

int gen_brop(int op) {
  switch (op) {
  case osLSS: return sBMI;
  case osLEQ: return sBCC;
  case osGEQ: return sBCS;
  case osEQL: return sBEQ;
  case osGTR: return sBPL;
  case osNEQ: return sBNE;
  }
  return sBRA;
}

void gen_fixabs(long at, long with) {
  codegen_updatew(at, with);
}

void gen_fixrel(long at, long with) {
  long rel;

  rel = with - at - 2; 
  codegen_updateb(at+1, rel);
}

void gen_fix(long at, long with) {
  codegen_updatew(at, codegen_getw(at) + with);
}

void gen_FixOne(long at) {
  gen_fix(at, codegen_here()-at-1);
}

void gen_FixLink(long L) {
  long L1;

  if (L != 0 ) {
	L1 = codegen_getw(L);
	gen_fixrel(L, codegen_here()-L-1);
  }
}

void gen_FixLinkWith(long L0, long dst) {
  long L1;
  
  while (L0 != 0) {
	L1 = codegen_getw(L0);
	// codegen_updatew(L0, 
	//code[L0] = code[L0] / C24 * C24 + ((dst - L0 - 1) % C24);
	L0 = L1;
  }
}

long gen_merged(long L0, long L1) {
  long L2;
  long L3;

  if (L0 != 0) {
	L3 = L0;
	do {
	  L2 = L3;
	  L3 = codegen_getw(L2);
	} while (L3 != 0);
	codegen_updatew(L2, codegen_getw(L2)+L1);
	L1 = L0;
  }
  return L1;
}

/* loading of operands and addresses into registers */

void gen_GetSB(long base) {
  gen_abs(sLDA, var_base + base);
  //Put2(Ldr, RH, -base, codegen_here()-fixorgD);
  //fixorgD = codegen_here()-2;
}

void gen_NilCheck(void) {
  if (check) {
	//gen_Trap(EQ, 4);
  }
}

void gen_load(struct Item *x) {
  // ToDo: Handle other sizes than int (2)
  if (x->mode != Reg) {
	if (x->mode == Const) {
	  if (x->type->form == Proc) {
		if (x->r > 0) {
		  as_error("not allowed");
		} else if (x->r == 0) {
		  // Put3(BL, 7, 0);
		  // Put1a(Sub, RH, LNK, codegen_here()*4 - x.a)
		} else {
		  // gen_GetSB(x->r);
		  //Put1(Add, RH, RH, x.a + 100H) (*mark as progbase-relative*)
		}
	  } else {
		gen_immw(sLDA, x->a);
		gen_dp(sSTA, RH * 2);
	  }
	  x->r = RH;
	  gen_incR();
	} else if (x->mode == Var) {
	  if (x->r > 0) { /*local*/
		gen_sr(sLDA, x->a);
		gen_dp(sSTA, RH * 2);
	  } else {
		gen_abs(sLDA, var_base + x->a);
		gen_dp(sSTA, RH * 2);
	  }
	  x->r = RH;
	  gen_incR();
	} else if (x->mode == Par) {
	  //Put2(Ldr, RH, SP, x.a + frame);
	  //Put2(op, RH, RH, x.b);
	  x->r = RH;
	  gen_incR();
	} else if( x->mode == RegI) {
	  //Put2(op, x.r, x.r, x.a)
	} else if (x->mode == Cond) {
	  gen_rel(gen_brop(gen_negated(x->r)), codegen_here());
	  gen_FixLink(x->b);
	  // Put1(Mov, RH, 0, 1);
	  // Put3(BC, 7, 1);
	  gen_FixLink(x->a);
	  // Put1(Mov, RH, 0, 0);
	  x->r = RH;
	  gen_incR();
	}
	x->mode = Reg;
  }
}

void gen_loadAdr(struct Item *x) {
  if (x->mode == Var) {
	if (x->r > 0) { /*local*/
	  // Put1a(Add, RH, SP, x.a + frame)
	} else {
	  //gen_GetSB(x.r);
	  //Put1a(Add, RH, RH, x.a);
	}
	x->r = RH;
	gen_incR();
  } else if (x->mode == Par) {
	// Put2(Ldr, RH, SP, x.a + frame);
	if (x->b != 0) {
	  //Put1a(Add, RH, RH, x.b)
	}
	x->r = RH;
	gen_incR();
  } else if (x->mode == RegI) {
	if (x->a != 0) {
	  //Put1a(Add, x.r, x.r, x.a);
	} else {
	  as_error("address error");
	}
  }
  x->mode = Reg;
}

void gen_loadCond(struct Item *x) {
  if (x->type->form == Bool) {
	if (x->mode == Const) {
	  x->r = 15 - x->a*8;
	} else {
      gen_load(x);
	  //if (code[codegen_here()-1] / 0x40000000H != -2) {
		// Put1(Cmp, x.r, x.r, 0);
	  //}
	  x->r = sBNE;
	  RH--;
	}
	x->mode = Cond;
	x->a = 0;
	x->b = 0;
  } else {
	as_error("not Boolean?");
  }
}

void gen_loadTypTagAdr(struct Type *T) {
  struct Item *x;
  x->mode = Var;
  x->a = T->len;
  x->r = -T->mno;
  gen_loadAdr(x);
}

void gen_loadStringAdr(struct Item *x) {
  gen_GetSB(0);
  // Put1a(Add, RH, RH, varsize+x.a);
  x->mode = Reg;
  x->r = RH;
  gen_incR();
}

/* Items: Conversion from constants or from Objects on the Heap to Items on the Stack*/

void gen_MakeConstItem(struct Item *x, struct Type *typ, long val) {
  x->mode = Const;
  x->type = typ;
  x->a = val;
}

void gen_MakeRealItem(struct Item *x, float val) {
 x->mode = Const;
 x->type = realType;
 x->a = 0; // SYSTEM.VAL(LONGINT, val)
}

void gen_MakeStringItem(struct Item *x, long len) { /*copies string from ORS-buffer to ORG-string array*/
  long i;

  x->mode = Const;
  x->type = strType;
  x->a = strx;
  x->b = len;
  i = 0;
  if (strx + len + 4 < maxStrx) {
	while (len > 0) {
	  str[strx] = str[i];
	  strx++;
	  i++;
	  len--;
	}
  } else {
	as_error("too many strings");
  }
}
void gen_MakeItem(struct Item *x, struct Object *y, long curlev) {
  x->mode = y->class;
  x->type = y->type;
  x->a = y->val;
  x->rdo = y->rdo;
  if (y->class == Par) {
	x->b = 0;
  } else if ((y->class == Const) && (y->type->form == String)) {
	x->b = y->lev;  /*len*/
  } else {
	x->r = y->lev;
	x->b = y->expo;
  }
  if ((y->lev > 0) && (y->lev != curlev) && (y->class != Const)) {
	as_error("not accessible ");
  }
}


void gen_SetCC(struct Item* x, long n) {
  x->mode = Cond; x->a = 0; x->b = 0; x->r = n;
}

void gen_open(const char *fname) {
  char buf[20];
  snprintf(buf, 20, "%s.lst", fname);
  asmf = fopen(buf, "w");
  
  codegen_init(fname, EM_816, 0x8000);
  gen_assign("cpu", "\"65C816\"");
  gen_println();
  gen_assign("org", "$8000"); 
  gen_println();
  gen_symbol("_start");
  gen_impl(sCLC);
  gen_impl(sXCE);
  gen_long(1, 1);
  gen_immw(sLDA, 0x01ff); /* Initial Stack Pointer */
  gen_impl(sTCS);
  gen_impl(sRTL);
  gen_println();
  /* Temp default start is called Main */
  // gen_abs(sJSR, 0x8058); // Fixup for main
  // gen_immb(sWDM, 0xff); /* Quit the emulator */
}

void gen_setDataSize(int sz) {
}

void gen_header(void) {
}

void gen_close(char *id, int key, int exno) {
  fprintf(asmf, "\n");
  fprintf(asmf, "\n");

  fclose(asmf);

  codegen_close();
}

void gen_FJump(long *L) {
  gen_abs(sJMP, *L);
  *L = codegen_here()-2;
}

void gen_CFJump(struct Item *x) { /* conditional forward jump */
  if (x->mode != Cond) {
	gen_loadCond(x);
  }
  gen_rel(x->r, codegen_here());
  // gen_FixLink(x->b);
  x->a = codegen_here()-2;
}

void gen_BJump(long L) {
  gen_rel(sBRA, L);
}

void gen_CBJump(struct Item *x, long L) {
  if (x->mode == Cond) {
	gen_loadCond(x);
  }
  gen_rel(x->r, L);
  gen_FixLink(x->b);
  gen_FixLinkWith(x->a, L);
}

void gen_Fixup(struct Item *x) {
  gen_FixLink(x->a);
}

void gen_SaveRegs(int c) {
  int a;
  if (c == 1) {
	gen_dp(sLDA, 0x00);
	gen_impl(sPHA);
  } else if (c == 2) {
	gen_dp(sLDA, 0x02);
	gen_impl(sPHA);
	gen_dp(sLDA, 0x00);
	gen_impl(sPHA);
  } else {
	gen_dp(sLDX, RH * 2);
	a = codegen_here();
	gen_dpix(sLDA, 0x00);
	gen_impl(sPHA);
	gen_impl(sDEX);
	gen_impl(sDEX);
	gen_rel(sBNE, a);
  }
}
 
void gen_RestoreRegs(int c) {
  int a;
  if (c == 1) {
	gen_impl(sPLA);
	gen_dp(sSTA, 0x00);
  } else if (c == 2) {
	gen_impl(sPLA);
	gen_dp(sSTA, 0x02);
	gen_impl(sPLA);
	gen_dp(sSTA, 0x00);
  } else {
	gen_immw(sLDX, RH * 2);
	a = codegen_here();
	gen_impl(sPLA);
	gen_dpix(sSTA, 0x00);
	gen_impl(sDEX);
	gen_impl(sDEX);
	gen_rel(sBNE, a);
  }
}
 
void gen_PrepCall(struct Item *x, long *r) {
  /*x.type.form = ORB.Proc*/
  if (x->mode > Par) {
	gen_load(x);
  }
  *r = RH;
  if (RH > 0) {
	gen_SaveRegs(RH);
	RH = 0;
  }
}

void gen_Call(struct Item *x, long r) {
  /*x.type.form = ORB.Proc*/
  if (x->mode == Const) {
	if (x->r >= 0) {
	  if (x->b) { /*exported*/
		gen_abs(sJSL, x->a);
	  } else {
		gen_abs(sJSR, x->a);
	  }
	} else { /*imported*/
	  if (codegen_here() - fixorgP < 0x1000) {
		gen_absl(sJSL, x->a);
		// Put3(BL, 7, ((-x.r) * 100H + x.a) * 1000H + pc-fixorgP);
		fixorgP = codegen_here()-2;
	  } else {
		as_error("fixup impossible");
	  }
	}
  } else {
	if (x->mode <= Par) {
	  gen_load(x);
	  RH--;
	} else {
	  // Put2(Ldr, RH, SP, 0); Put1(Add, SP, SP, 4); DEC(r); DEC(frame, 4)
	}
	if (check) {
	  // Trap(EQ, 5)
	}
	// Put3(BLR, 7, RH)
  }
  if (x->type->base->form == NoTyp) { /*procedure*/
	RH = 0;
  } else { /*function*/
	if (r > 0) {
	  // This is where we store the return value
	  // Put0(Mov, r, 0, 0);
	  gen_RestoreRegs(r);
	}
	x->mode = Reg;
	x->r = r;
	RH = r+1;
  }
}

void gen_Enter(const char *name, long parblksize, long locblksize, bool interrupt) {
  long a;
  long r;

  frame = 0;

  if (!interrupt) { /*procedure prolog*/
	if (locblksize >= 0xFF) {
	  as_error("too many locals");
	}
	if (locblksize > 0) {
	  gen_impl(sTSC);
	  gen_impl(sSEC);
	  gen_immw(sSBC, locblksize);
	  gen_impl(sTCS);
	}
	a = 0;
	r = parblksize;
    while (a < parblksize) {
	  r -= 2;
	  gen_dp(sLDA, r);
	  gen_impl(sPHA);
	  a += 2;
	}
  } else { /*interrupt procedure*/
	// Put1(Sub, SP, SP, locblksize);
	// Put2(Str, 0, SP, 0);
	// Put2(Str, 1, SP, 4);
	// Put2(Str, 2, SP, 8)
	/*R0, R1, R2 saved on stack*/
  }
}

void gen_Return(struct Object *proc, struct Item *x, long size, bool interrupt) {
  /*All registers should have been freed by now. We return in R0,
	so just need to load(x)*/
  if (proc->type->form != NoTyp) {
	gen_load(x);
  }
  if (!interrupt) { /*procedure epilog*/
	if (size > 0) {
	  gen_impl(sTSC);
	  gen_impl(sCLC);
	  gen_immw(sADC, size);
	  gen_impl(sTCS);
	}
	if (proc->expo) { /*exported*/
	  gen_impl(sRTL);
	} else {
	  gen_impl(sRTS);
	}
	gen_println();
  } else { /*interrupt return*/
	fprintf(asmf, "; Restore the registers etc.\n");
	gen_impl(sRTI);	
	gen_println();
  }
  RH = 0;
}

/*In-line code functions*/

void gen_Abs(struct Item *x) {
  long done;
  if (x->mode == Const) {
	x->a = abs((int)x->a);
  } else {
	gen_load(x);
	if (x->type->form == Real) {
	  // Put1(Lsl, x.r, x.r, 1); Put1(Ror, x.r, x.r, 1)
	} else {
	  gen_dp(sLDA, x->r*2);
	  done = gen_rel(sBPL, codegen_here());
	  gen_immw(sEOR, 0xffff);
	  gen_impl(sCLC);
	  gen_immw(sADC, 0x0001);
	  gen_dp(sSTA, x->r*2);
	  gen_fixrel(done, codegen_here());
	}
  }
}

void gen_Odd(struct Item *x) {
  gen_load(x);
  // Put1(And, x.r, x.r, 1);
  // SetCC(x, NE);
  RH -= 1;
}

void gen_Floor(struct Item *x) {
  gen_load(x);
  // Put1(Mov+U, RH, 0, 4B00H); Put0(Fad+V, x.r, x.r, RH)
}

void gen_Float(struct Item *x) {
  gen_load(x);
  // Put1(Mov+U, RH, 0, 4B00H);  Put0(Fad+U, x.r, x.r, RH)
}

void gen_Ord(struct Item *x) {
  // if (x->mode IN {ORB.Var, ORB.Par, RegI, Cond} THEN load(x) END
}

void gen_Len(struct Item *x) {
  if (x->type->len >= 0) {
	if (x->mode == RegI) {
	  RH -= 1;
	}
	x->mode = Const;
	x->a = x->type->len;
  } else { /*open array*/
	// Put2(Ldr, RH, SP, x.a + 4 + frame);
	x->mode = Reg;
	x->r = RH;
	gen_incR();
  }
}

void gen_Shift(long fct, struct Item *x, struct Item *y) {
  long op;
  gen_load(x);
  if (fct == 0) {
	// op = sLSL;
  } else if (fct == 1) {
	op = sASR;
  } else {
	op = sROR;
  }
  if (y->mode == Const) {
	// Put1(op, x.r, x.r, y.a MOD 20H)
  } else {
	gen_load(y);
	// Put0(op, RH-2, x.r, y.r);
	RH -= 1;
	x->r = RH-1;
  }
}

/*
void gen_ADC(VAR x, y: Item);
  BEGIN load(x); load(y); Put0(Add+2000H, x.r, x.r, y.r); DEC(RH)
  END ADC;

  PROCEDURE SBC*(VAR x, y: Item);
  BEGIN load(x); load(y); Put0(Sub+2000H, x.r, x.r, y.r); DEC(RH)
  END SBC;

  PROCEDURE UML*(VAR x, y: Item);
  BEGIN load(x); load(y); Put0(Mul+2000H, x.r, x.r, y.r); DEC(RH)
  END UML;
*/

void gen_Bit(struct Item *x, struct Item *y) {
  gen_load(x);
  // Put2(Ldr, x.r, x.r, 0);
  if (y->mode == Const) {
	//Put1(Ror, x.r, x.r, y.a+1);
	RH -= 1;
  } else {
    gen_load(y);
	//Put1(Add, y.r, y.r, 1);
	//Put0(Ror, x.r, x.r, y.r);
	RH -= 2;
  }
  // gen_SetCC(x, MI);
}
/*
  PROCEDURE Register*(VAR x: Item);
  BEGIN (*x.mode = Const*)
    Put0(Mov, RH, 0, x.a MOD 10H); x.mode := Reg; x.r := RH; incR
  END Register;
*/

void gen_H(struct Item *x) {
  /*x.mode = Const*/
  // Put0(Mov + U + x.a MOD 2 * V, RH, 0, 0);
  x->mode = Reg;
  x->r = RH;
  gen_incR();
}

void gen_Condition(struct Item *x) {
  /*x.mode = Const*/
  gen_SetCC(x, x->a);
}

/* In-line code procedures*/

void gen_Increment(long upordown, struct Item *x, struct Item *y) {
  long op;
  long zr;
  long v;

  /*frame = 0*/
  if (upordown == 0) {
	//op = sADD;
  } else {
	//op = sSUB;
  }
  if (x->type == byteType) {
	v = 1;
  } else {
	v = 0;
  }
  if (y->type->form == NoTyp) {
	y->mode = Const;
	y->a = 1;
  }
  if ((x->mode == Var) && (x->r > 0)) {
	zr = RH;
	// Put2(Ldr+v, zr, SP, x.a);
	gen_incR();
	if (y->mode == Const) {
	  // Put1a(op, zr, zr, y.a)
	} else {
	  gen_load(y);
	  //Put0(op, zr, zr, y.r);
	  RH -= 1;
	}
	// Put2(Str+v, zr, SP, x.a);
	RH -= 1;
  } else {
	gen_loadAdr(x);
	zr = RH;
	// Put2(Ldr+v, RH, x.r, 0);
	gen_incR();
	if (y->mode == Const) {
	  //Put1a(op, zr, zr, y.a)
	} else {
	  gen_load(y);
	  //Put0(op, zr, zr, y.r);
	  RH -= 1;
	}
	// Put2(Str+v, zr, x.r, 0);
	RH -= 2;
  }
}

/*
  PROCEDURE Include*(inorex: LONGINT; VAR x, y: Item);
    VAR op, zr: LONGINT;
  BEGIN loadAdr(x); zr := RH; Put2(Ldr, RH, x.r, 0); incR;
    IF inorex = 0 THEN op := Ior ELSE op := Ann END ;
    IF y.mode = ORB.Const THEN Put1a(op, zr, zr, LSL(1, y.a))
    ELSE load(y); Put1(Mov, RH, 0, 1); Put0(Lsl, y.r, RH, y.r); Put0(op, zr, zr, y.r); DEC(RH)
    END ;
    Put2(Str, zr, x.r, 0); DEC(RH, 2)
  END Include;

  PROCEDURE Assert*(VAR x: Item);
    VAR cond: LONGINT;
  BEGIN
    IF x.mode # Cond THEN loadCond(x) END ;
    IF x.a = 0 THEN cond := negated(x.r)
    ELSE Put3(BC, x.r, x.b); FixLink(x.a); x.b := pc-1; cond := 7
    END ;
    Trap(cond, 7); FixLink(x.b)
  END Assert; 

  PROCEDURE New*(VAR x: Item);
  BEGIN loadAdr(x); loadTypTagAdr(x.type.base); Trap(7, 0); RH := 0
  END New;

  PROCEDURE Pack*(VAR x, y: Item);
    VAR z: Item;
  BEGIN z := x; load(x); load(y);
    Put1(Lsl, y.r, y.r, 23); Put0(Add, x.r, x.r, y.r); DEC(RH); Store(z, x)
  END Pack;

  PROCEDURE Unpk*(VAR x, y: Item);
    VAR z, e0: Item;
  BEGIN  z := x; load(x); e0.mode := Reg; e0.r := RH; e0.type := ORB.intType;
    Put1(Asr, RH, x.r, 23); Put1(Sub, RH, RH, 127); Store(y, e0); incR;
    Put1(Lsl, RH, RH, 23); Put0(Sub, x.r, x.r, RH); Store(z, x)
  END Unpk;

  PROCEDURE Led*(VAR x: Item);
  BEGIN load(x); Put1(Mov, RH, 0, -60); Put2(Str, x.r, RH, 0); DEC(RH)
  END Led;
*/
void gen_Get(struct Item *x, struct Item *y) {
  gen_load(x);
  x->type = y->type;
  x->mode = RegI;
  x->a = 0;
  gen_Store(y, x);
}

void gen_Put(struct Item *x, struct Item *y) {
  if (y->mode == Const) {
	if (x->mode == Const) {
	  gen_immw(sLDA, y->a);
	} else {
	  gen_load(y);
	  gen_dp(sLDA, y->r*2);
	  RH -= 1;
	}
	gen_long(0, 0);
	gen_abs(sSTA, x->a);
	gen_long(1, 1);
  } else {
	gen_load(y);
	if (x->mode == Const) {
	  gen_immw(sLDA, y->a);
	} else {
	  gen_load(x);
	  gen_dp(sLDA, x->r*2);
	  RH -= 1;
	}
	gen_long(0, 0);	
	gen_dpind(sSTA, y->r*2);
	gen_long(1, 1);
	RH -= 1;
  }
}

/*
  PROCEDURE Copy*(VAR x, y, z: Item);
  BEGIN load(x); load(y);
    IF z.mode = ORB.Const THEN
      IF z.a > 0 THEN load(z) ELSE ORS.Mark("bad count") END
    ELSE load(z);
      IF check THEN Trap(LT, 3) END ;
      Put3(BC, EQ, 6)
    END ;
    Put2(Ldr, RH, x.r, 0); Put1(Add, x.r, x.r, 4);
    Put2(Str, RH, y.r, 0); Put1(Add, y.r, y.r, 4);
    Put1(Sub, z.r, z.r, 1); Put3(BC, NE, -6); DEC(RH, 3)
  END Copy;
*/

/* Code generation for selectors, variables, constants*/

void gen_BuildTD(struct Type *T, long *dc) {
  long dcw; /*word adress*/
  long k;
  long s;

  dcw = *dc / 4;
  s = T->size; /*convert size for heap allocation*/
  if (s <= 24) {
	s = 32;
  } else if (s < 56) {
	s = 64;
  } else if (s < 120) {
	s = 128;
  } else {
	s = (s+263) / 256 * 256;
  }
  T->len = *dc;
  // data[dcw] = s;
  dcw++; /*len used as address*/
  k = T->nofpar; /*extension level!*/
  if (k > 3) {
	as_error("ext level too large");
  } else {
	// gen_Q(T, dcw);
	while (k < 3) {
	  // data[dcw] = -1;
	  dcw++;
	  k++;
	}
  }
  //gen_FindPtrFlds(T, 0, dcw);
  //data[dcw] = -1;
  dcw++;
  tdx = dcw;
  *dc = dcw*4;
  if (tdx >= maxTD) {
	as_error("too many record types");
	tdx = 0;
  }
}

void gen_TypeTest(struct Item *x, struct Type *T, bool varpar, bool isguard) {
  long pc0;

  if (T == 0) {
	if (x->mode >= Reg) {
	  RH--;
	}
	gen_SetCC(x, 7);
  } else { /*fetch tag into RH*/
	if (varpar) {
	  // Put2(Ldr, RH, SP, x.a+4+frame)
	} else {
	  gen_load(x);
	  pc0 = codegen_here();
	  //Put3(BC, EQ, 0);  /*NIL belongs to every pointer type*/
	  //Put2(Ldr, RH, x.r, -8)
	}
	//Put2(Ldr, RH, RH, T.nofpar*4); incR;
	//loadTypTagAdr(T);  (*tag of T*)
	//Put0(Cmp, RH-1, RH-1, RH-2); DEC(RH, 2);
	//IF ~varpar THEN fix(pc0, pc - pc0 - 1) END ;
	if (isguard) {
	  if (check) {
		//Trap(NE, 2)
	  }
	} else {
      //SetCC(x, EQ);
	  if (!varpar) {
		RH--;
	  }
	}
  }
}

/* Code generation for Boolean operators */

void gen_Not(struct Item *x) {   /* x := ~x */
  long t;
  if (x->mode != Cond) {
	gen_loadCond(x);
  }
  x->r = gen_negated(x->r);
  t = x->a;
  x->a = x->b;
  x->b = t;
}

void gen_And1(struct Item *x) {   /* x := x & */
  if (x->mode != Cond) {
	gen_loadCond(x);
  }
  gen_rel(gen_brop(gen_negated(x->r)), x->a);
  x->a = codegen_here()-2;
  gen_FixLink(x->b);
  x->b = 0;
}

void gen_And2(struct Item *x, struct Item *y) {
  if (y->mode != Cond) {
	gen_loadCond(y);
  }
  x->a = gen_merged(y->a, x->a);
  x->b = y->b;
  x->r = y->r;
}

void gen_Or1(struct Item *x) {   /* x := x OR */
  if (x->mode != Cond) {
	gen_loadCond(x);
  }
  gen_rel(x->r, x->b);
  x->b = codegen_here()-2;
  gen_FixLink(x->a);
  x->a = 0;
}

void gen_Or2(struct Item *x, struct Item *y) {
  if (y->mode != Cond) {
	gen_loadCond(y);
  }
  x->a = y->a;
  x->b = gen_merged(y->b, x->b);
  x->r = y->r;
}

/* Code generation for arithmetic operators */

void gen_Neg(struct Item *x) { /* x := -x */
  if (x->type->form == Int) {
	if (x->mode == Const) {
	  x->a = -x->a;
	} else {
	  gen_load(x);
	  gen_dp(sLDA, x->r*2);
	  gen_immw(sEOR, 0xffff);
	  gen_impl(sCLC);
	  gen_immw(sADC, 0x0001);
	  gen_dp(sSTA, x->r*2);
	}
  } else if (x->type->form == Real) {
	if (x->mode == Const) {
	  x->a = x->a + 0x7FFFFFFF + 1;
	} else {
	  // load(x); Put1(Mov, RH, 0, 0); Put0(Fsb, x.r, RH, x.r);
	}
  } else { /*form = Set*/
	if (x->mode == Const) {
	  x->a = -x->a-1;
	} else {
	  //load(x); Put1(Xor, x.r, x.r, -1);
	}
  }
}

void gen_AddOp(long op, struct Item *x, struct Item *y) {   /* x := x +- y */
  if (op == osPLUS) {
	if ((x->mode == Const) && (y->mode == Const)) {
	  x->a = x->a + y->a;
	} else if (y->mode == Const) {
	  gen_load(x);
	  if (y->a != 0) {
		gen_dp(sLDA, x->r*2);
		gen_impl(sCLC);
		gen_immw(sADC, y->a);
		gen_dp(sSTA, x->r*2);
	  }
	} else {
	  gen_load(x);
	  gen_load(y);
	  gen_dp(sLDA, x->r*2);
	  gen_impl(sCLC);
	  gen_dp(sADC, y->r*2);
	  gen_dp(sSTA, x->r);
	  RH -= 1;
	  x->r = RH-1;
	}
  } else { /*op = osMINUS*/
	if ((x->mode == Const) && (y->mode == Const)) {
	  x->a = x->a - y->a;
	} else if(y->mode == Const) {
	  gen_load(x);
	  if (y->a != 0) {
		gen_dp(sLDA, x->r*2);
		gen_impl(sSEC);
		gen_immw(sSBC, y->a);
		gen_dp(sSTA, x->r*2);
	  }
	} else {
	  gen_load(x);
	  gen_load(y);
	  gen_dp(sLDA, x->r*2);
	  gen_impl(sSEC);
	  gen_dp(sSBC, y->r*2);
	  gen_dp(sSTA, x->r*2);
	  RH -= 1;
	  x->r = RH-1;
	}
  }
}

void gen_MulOp(struct Item *x, struct Item *y) {   /* x := x * y */
  long mult1;
  long mult2;
  long done;
  
  if ((x->mode == Const) && (y->mode == Const)) {
	x->a = x->a + y->a;
  } else if (y->mode == Const) {
	gen_load(x);
	if (y->a == 0) {
	  gen_immw(sLDA, 0);
	  gen_dp(sSTA, x->r*2);
	} else if (y->a == 1) {
	  // Do nothing
	} else if (y->a == 2) {
	  // Shift left but preserve sign
	}
  } else {
	gen_load(x);
	gen_load(y);
	gen_immw(sLDA, 0);
	mult1 = gen_dp(sLDX, x->r*2); // 8023 LDX $00
	done = gen_rel(sBEQ, codegen_here());      // 8025 BEQ $0E done = 8025+1
	gen_dp(sLSR, x->r*2);         // 8027 LSR #$00  
	mult2 = gen_rel(sBCC, codegen_here());     // 8029 BCC $00
	gen_impl(sCLC);               // 802b CLC
	gen_dp(sADC, y->r*2);         // 802c ADC $01
	gen_fixrel(mult2, codegen_here());            // 802e
	gen_dp(sASL, y->r*2);         // 802e ASL $00
	gen_rel(sBRA, mult1);         // 8030 BRA $00 8023
	gen_fixrel(done, codegen_here());       ;
	gen_dp(sSTA, x->r*2);         // 8032
	RH -= 1;
  }
}

/* Code generation for REAL operators */

/* Code generation for set operators */

/* Code generation for relations */

void gen_IntRelation(int op, struct Item *x, struct Item *y) {   /* x := x < y */
  if ((y->mode == Const) && (y->type->form != Proc)) {
	gen_load(x);
	if ((y->a != 0) || !((op == osEQL) || (op == osNEQ))) {
	  gen_dp(sLDA, x->r*2);
	  gen_immw(sCMP, y->a);
      RH -= 1;
    } else {
      if ((x->mode == Cond) || (y->mode == Cond)) {
		as_error("not implemented");
	  }
      gen_load(x);
	  gen_load(y);
	  gen_dp(sLDA, x->r*2);
	  gen_dp(sCMP, y->r*2);
	  RH -= 2;
    }
    gen_SetCC(x, gen_brop(gen_negated(op)));
  }
}

void gen_RealRelation(int op, struct Item *x, struct Item *y) {   /* x := x < y */
  gen_load(x);
  if ((y->mode == Const) && (y->a == 0)) {
	RH -= 1;
  } else {
    gen_load(y);
	//Put0(Fsb, x.r, x.r, y.r);
	RH -= 2;
  }
  //  gen_SetCC(x, relmap[op - ORS.eql])
}

void gen_StringRelation(int op, struct Item *x, struct Item *y) {   /* x := x < y */
  /*x, y are char arrays or strings*/
  if (x->type->form == String) {
	gen_loadStringAdr(x);
  } else {
	gen_loadAdr(x);
  }
  if (y->type->form == String) {
	gen_loadStringAdr(y);
  } else {
	gen_loadAdr(y);
  }
  //Put2(Ldr+1, RH, x.r, 0); Put1(Add, x.r, x.r, 1);
  //Put2(Ldr+1, RH+1, y.r, 0); Put1(Add, y.r, y.r, 1);
  //Put0(Cmp, RH+2, RH, RH+1); Put3(BC, NE, 2);
  //Put1(Cmp, RH+2, RH, 0); Put3(BC, NE, -8);
  RH -= 2;
  // gen_SetCC(x, relmap[op - ORS.eql])
}

/* Code generation of Assignments */

void gen_StrToChar(struct Item *x) {
  x->type = charType;
  strx -= 4;
  x->a = str[x->a];
}

void gen_Store(struct Item *x, struct Item *y) { /* x := y */
  long op;
  gen_load(y);
  if (x->mode == Var) {
	if (x->r > 0) { /*local*/
	  gen_dp(sLDA, y->r);
	  gen_sr(sSTA, x->a);
	} else {
	  gen_dp(sLDA, y->r);
	  gen_abs(sSTA, var_base + x->a);
	}
  } else if (x->mode == Par) {
	//Put2(Ldr, RH, SP, x.a + frame);
	//Put2(op, y.r, RH, x.b);
  } else if (x->mode == RegI) {
	gen_dp(sLDA, y->r);
	if (x->a == 0) {
	  gen_dpind(sSTA, x->r*2);
	} else {
	  gen_immw(sLDY, x->a);
	  gen_dpindy(sSTA, x->r*2);
	}
  } else {
	as_error("bad mode in Store");
  }
  RH -= 1;
}

void gen_StoreStruct(struct Item *x, struct Item *y) { /* x := y, frame = 0 */
  long s;
  long pc0;

  if (y->type->size != 0) {
	gen_loadAdr(x);
	gen_loadAdr(y);
	if ((x->type->form == Array) && (x->type->len > 0)) {
	  if (y->type->len >= 0) {
		if (x->type->size == y->type->size) {
		  //Put1a(Mov, RH, 0, (y.type.size+3) DIV 4)
		} else {
		  as_error("different length/size, not implemented");
		}
	  } else { /*y  open array*/
		//Put2(Ldr, RH, SP, y.a+4);
		s = y->type->base->size;  /*element size*/
		pc0 = codegen_here();
		//Put3(BC, EQ, 0);
		if (s == 1) {
		  //Put1(Add, RH, RH, 3); Put1(Asr, RH, RH, 2)
		} else if (s != 4) {
		  //Put1a(Mul, RH, RH, s DIV 4)
		}
		if (check) {
		  //Put1a(Mov, RH+1, 0, (x.type.size+3) DIV 4);
		  //Put0(Cmp, RH+1, RH, RH+1);
		  //Trap(GT, 3)
		}
		//fix(pc0, pc + 5 - pc0)
	  }
	} else if (x->type->form == Record) {
	  //Put1a(Mov, RH, 0, x.type.size DIV 4)
	} else {
	  as_error("inadmissible assignment");
	}
	// Put2(Ldr, RH+1, y.r, 0); Put1(Add, y.r, y.r, 4);
    //  Put2(Str, RH+1, x.r, 0); Put1(Add, x.r, x.r, 4);
    //  Put1(Sub, RH, RH, 1); Put3(BC, NE, -6)
  }
  RH = 0;
}

void gen_CopyString(struct Item*x, struct Item *y) {  /* x := y */ 
  long len;

  gen_loadAdr(x);
  len = x->type->len;
  if (len >= 0) {
	if (len < y->b) {
	  as_error("string too long");
	}
  } else if (check) {
	//Put2(Ldr, RH, SP, x.a+4);  /*open array len, frame = 0*/
	//Put1(Cmp,RH, RH, y.b); Trap(LT, 3)
  }
  gen_loadStringAdr(y);
  //Put2(Ldr, RH, y.r, 0); Put1(Add, y.r, y.r, 4);
  //Put2(Str, RH, x.r, 0); Put1(Add, x.r, x.r, 4);
  //Put1(Asr, RH, RH, 24); Put3(BC, NE,  -6);  RH := 0
}

/* Code generation for parameters */

void gen_OpenArrayParam(struct Item *x) {
  gen_loadAdr(x);
  if (x->type->len >= 0) {
	//Put1a(Mov, RH, 0, x.type.len)
  } else {
	//Put2(Ldr, RH, SP, x.a+4+frame);
  }
  gen_incR();
}

void gen_VarParam(struct Item *x, struct Type *ftype) {
  int xmd;
  xmd = x->mode;
  gen_loadAdr(x);
  if ((ftype->form == Array) && (ftype->len < 0)) { /*open array*/
	if (x->type->len >= 0) {
	  //Put1a(Mov, RH, 0, x.type.len)
	} else {
	  //Put2(Ldr, RH, SP, x.a+4+frame)
	}
	gen_incR();
  } else if (ftype->form == Record) {
	if (xmd == Par) {
	  //Put2(Ldr, RH, SP, x.a+4+frame);
	  gen_incR();
	} else {
	  // loadTypTagAdr(x.type)
	}
  }
}

void gen_ValueParam(struct Item *x) {
  gen_load(x);
}

void gen_StringParam(struct Item *x) {
  gen_loadStringAdr(x);
  //Put1(Mov, RH, 0, x.b);
  gen_incR();  /*len*/
}

/*For Statements*/

void gen_For0(struct Item *x, struct Item *y) {
  gen_load(y);
}

void gen_For1(struct Item *x, struct Item *y, struct Item *z, struct Item *w, int *L) {
  if (z->mode == Const) {
	// Put1a(Cmp, RH, y.r, z.a)
  } else {
	gen_load(z);
	//Put0(Cmp, RH-1, y.r, z.r);
	RH--;
  }
  *L = codegen_here();
  if (w->a > 0) {
	//Put3(BC, GT, 0)
  } else if (w->a < 0) {
	//Put3(BC, LT, 0)
  } else {
	as_error("zero increment");
	//Put3(BC, MI, 0)
  }
  gen_Store(x, y);
}

void gen_For2(struct Item *x, struct Item *y, struct Item *w) {
  gen_load(x);
  RH--;
  //Put1a(Add, x.r, x.r, w.a)
}
