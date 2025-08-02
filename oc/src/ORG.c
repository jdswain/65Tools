// ORG.c - Code generator for Oberon compiler for RISC processor
// Translated from ORG.Mod by N.Wirth

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "ORG.h"
#include "ORS.h"
#include "ORB.h"
#include "Files.h"
#include "codegen.h"

// Constants
#define CODE_ORG 0x2000         // Code starts at $2000 (must match codegen.c)
#define WordSize 2
#define StkOrg0 (-64)
#define VarOrg0 0
#define MT 12
#define SP 14
#define LNK 15
#define maxStrx 2400
#define maxTD 160
#define C24 0x1000000

// 65C816 register scheme - use first 24 bytes of direct page as 12 registers
#define MAX_REGS 12
#define REG_SIZE 2  // 16-bit registers
static LONGINT reg_addr(int reg) {
    return reg * REG_SIZE;  // $00, $02, $04, $06, $08, $0A, $0C, $0E, $10, $12, $14, $16
}

// 65C816 memory layout
#define MODULE_VAR_BASE 0x1000  // Module global variables start at $1000
#define CODE_ORG 0x2000         // Code starts at $2000

// Internal item modes
#define Reg 10
#define RegI 11
#define Cond 12

// Opcodes
#define U 0x2000
#define V 0x1000
#define Mov 0
#define Lsl 1
#define Asr 2
#define Ror 3
#define And 4
#define Ann 5
#define Ior 6
#define Xor 7
#define Add 8
#define Sub 9
#define Cmp 9
#define Mul 10
#define Div 11
#define Fad 12
#define Fsb 13
#define Fml 14
#define Fdv 15
#define Ldr 8
#define Str 10
#define BR 0
#define BLR 1
#define BC 2
#define BL 3

// Condition codes (Inverted are 8 different)
#define MI 0
#define PL 8
#define EQ 1
#define NE 9
#define LT 5
#define GE 13
#define LE 6
#define GT 14

// Global variables
LONGINT ORG_pc, ORG_varsize;
static LONGINT tdx, strx;
static LONGINT entry;
static LONGINT RH;
static LONGINT frame;
static LONGINT fixorgP, fixorgD, fixorgT;
static BOOLEAN check;
static INTEGER version;
static INTEGER relmap[6];
uint8_t code[maxCode];
static LONGINT data[maxTD];
static char str[maxStrx];

// Forward declarations
static int load(ORG_Item *x);
static void loadAdr(ORG_Item *x);
static void GetSB(LONGINT base);
static LONGINT ORG_log2(LONGINT m, LONGINT *e);

static void Set16(int a, int i) {
  int new_longa = (a?1:longa);
  int new_longi = (i?1:longi);
  if ((longa == new_longa) && (longi == new_longi)) return;
  int val = (a?0x20:0x00) + (i?0x10:0x00);
  longa = new_longa;
  longi = new_longi;
  codegen_gen(sREP, Immediate, val, 0); 
}

static void Set8(int a, int i) {
  int new_longa = (a?0:longa);
  int new_longi = (i?0:longi);
  if ((longa == new_longa) && (longi == new_longi)) return;
  int val = (a?0x20:0x00) + (i?0x10:0x00);
  longa = new_longa;
  longi = new_longi;
  codegen_gen(sSEP, Immediate, val, 0); 
}

static void incR(void) {
    if (RH < MT - 1) {
        RH++;
    } else {
        ORS_Mark("register stack overflow");
    }
}

void ORG_CheckRegs(void) {
    if (RH != 0) {
        ORS_Mark("Reg Stack");
        RH = 0;
    }
    if (ORG_pc >= maxCode - 40) {
        ORS_Mark("program too long");
    }
    // 65C816: Disable frame checking for now - hardware stack management
    if (frame != 0) {
         ORS_Mark("frame error");
         frame = 0;
    }
}

static void SetCC(ORG_Item *x, LONGINT n) {
    x->mode = Cond;
    x->a = 0;
    x->b = 0;
    x->r = n;
}

static void Trap(LONGINT cond, LONGINT num) {
    // RISC: Put3(BLR, cond, ORS_Pos() * 0x100 + num * 0x10 + MT);
}

static LONGINT negated(LONGINT cond) {
    switch (cond) {
        case EQ: return NE;   // 1 -> 9
        case NE: return EQ;   // 9 -> 1
        case LT: return GE;   // 5 -> 13
        case GE: return LT;   // 13 -> 5
        case LE: return GT;   // 6 -> 14
        case GT: return LE;   // 14 -> 6
        case MI: return PL;   // 0 -> 8
        case PL: return MI;   // 8 -> 0
        default: 
            printf("ERROR: Unknown condition code %ld in negated()\n", cond);
            return cond;
    }
}

// Generate 65C816 branch instruction based on condition code
// target parameter is always a fixup chain link for forward branches
// (actual target will be resolved later by ORG_FixLink)
static void emitBranch(LONGINT cond, LONGINT target) {
    // Debug output to trace condition codes
    // printf("DEBUG: emitBranch called with cond=%ld, target=%ld\n", cond, target);
    
    // For now, assume all branches from compiler are forward branches needing fixup
    // TODO: Detect backward branches properly when implementing loops
    AddrMode mode = Fixup;
    
    switch (cond) {
        case EQ:  // Branch if Equal (Zero flag set)
            codegen_gen(sBEQ, mode, target, 0);
            break;
        case NE:  // Branch if Not Equal (Zero flag clear)
            codegen_gen(sBNE, mode, target, 0);
            break;
        case MI:  // Branch if Minus (Negative flag set)
            codegen_gen(sBMI, mode, target, 0);
            break;
        case PL:  // Branch if Plus (Negative flag clear)
            codegen_gen(sBPL, mode, target, 0);
            break;
        case LT:  // Branch if Less Than - use BCC
            codegen_gen(sBCC, mode, target, 0);
            break;
        case GE:  // Branch if Greater or Equal - use BCS
            codegen_gen(sBCS, mode, target, 0);
            break;
        case LE:  // Branch if Less or Equal (also handles negated GT)
            // For negated GT: branch if NOT(A > B), which is A <= B
            // Check equality first, then use BCS for the < case
            codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 4, 0);
            codegen_gen(sBCC, ProgramCounterRelative, ORG_pc + 2 + 2, 0);
			codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 2, 0);  // over
            codegen_gen(sBRA, mode, target, 0);
			
            break;
        case GT:  // Branch if Greater Than
		  codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 2, 0);
		  codegen_gen(sBCS, mode, target, 0);
		  break;
        case 7:   // Always branch (unconditional)
            codegen_gen(sBRA, mode, target, 0);
            break;
        case 15:  // Never branch (nop - could optimize away)
            // Do nothing for "never" condition
            break;
        default:
            ORS_Mark("condition not implemented");
            break;
    }
}

static void fix(LONGINT at, LONGINT with) {
    // For 65C816, patch the offset byte of branch instructions
    // 'at' is the address of the offset byte (branch_addr + 1)
    // 'with' is the target address
    // Offset = target - (branch_addr + 2) = target - (at + 1)
    LONGINT offset = with - (at + 1);
    LONGINT code_index = at - CODE_ORG;  // Same indexing as o() function
    code[code_index] = offset & 0xFF;  // Store only the low byte for branch instructions
}

void ORG_FixOne(LONGINT at) {
    // For 65C816: fix a single forward branch
    // 'at' is the address of the offset byte
    // Target is current ORG_pc
    fix(at, ORG_pc);
}

void ORG_FixLink(LONGINT L) {
    // For 65C816: fix a chain of forward branches
    // L is the address of the offset byte of the most recent branch
    LONGINT L1;
    while (L != 0) {
        // Read the chain link (relative offset to previous branch)
        LONGINT chain_offset = (signed char)code[L];  // Sign-extend to handle negative offsets
        if (chain_offset == 0) {
            L1 = 0;  // End of chain
        } else {
            L1 = L + chain_offset;  // Calculate address of previous offset byte
        }
        
        // Fix this branch: target is current ORG_pc
        fix(L, ORG_pc);
        
        // Move to next branch in chain
        L = L1;
    }
}

static void FixLinkWith(LONGINT L0, LONGINT dst) {
    // For 65C816: fix a chain of forward branches to a specific destination
    // L0 is the address of the offset byte of the most recent branch
    // dst is the target address
    LONGINT L1;
    while (L0 != 0) {
        // Read the chain link (relative offset to previous branch)
        LONGINT chain_offset = (signed char)code[L0];  // Sign-extend to handle negative offsets
        if (chain_offset == 0) {
            L1 = 0;  // End of chain
        } else {
            L1 = L0 + chain_offset;  // Calculate address of previous offset byte
        }
        
        // Fix this branch to the specified destination
        fix(L0, dst);
        
        // Move to next branch in chain
        L0 = L1;
    }
}

static LONGINT merged(LONGINT L0, LONGINT L1) {
    LONGINT L2, L3;
    if (L0 != 0) {
        L3 = L0;
        do {
            L2 = L3;
            L3 = code[L2] % 0x40000;
        } while (L3 != 0);
        code[L2] = code[L2] + L1;
        L1 = L0;
    }
    return L1;
}

static void GetSB(LONGINT base) {
    if (version == 0) {
    // RISC: Put1(Mov, RH, 0, VarOrg0);
    } else {
    // RISC: Put2(Ldr, RH, -base, ORG_pc - fixorgD);
        fixorgD = ORG_pc - 1;
    }
    
    // 65C816: GetSB used to allocate a register for static base
    // But for 65C816, we load directly from absolute addresses, so no register needed
}

static void NilCheck(void) {
    if (check) {
        Trap(EQ, 4);
    }
}

// Returns the number of registers used
static int load(ORG_Item *x) {
    if (x->mode != Reg) {
        if (x->mode == ORB_Const) {
            if (x->type->form == ORB_Proc) {
                if (x->r > 0) {
                    ORS_Mark("not allowed");
                } else if (x->r == 0) {
    // RISC: Put3(BL, 7, 0);
    // RISC: Put1a(Sub, RH, LNK, ORG_pc * 4 - x->a);
                } else {
                    GetSB(x->r);
    // RISC: Put1(Add, RH, RH, x->a + 0x100);
                }
            } else if ((x->a <= 0xFFFF) && (x->a >= -0x10000)) {
			  if (x->type->size == 1) {
				Set8(1, 0);
				codegen_gen(sLDA, Immediate, x->a & 0xFF, 0);  // LDA #constant
				codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);  // STA $reg
			  } else {
				Set16(1, 1);
				codegen_gen(sLDA, Immediate, x->a & 0xFFFF, 0);  // LDA #constant
				codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);  // STA $reg
			  }
            } else {
    // RISC: Put1(Mov + U, RH, 0, (x->a / 0x10000) % 0x10000);
                if (x->a % 0x10000 != 0) {
    // RISC: Put1(Ior, RH, RH, x->a % 0x10000);
                }
            }
            
            x->r = RH;
            incR();
        } else if (x->mode == ORB_Var) {
            if (x->r > 0) {
                // 65C816: Load stack-based local variable
			  if (x->type->size == 1) {
				// Byte load from stack (handles BYTE, BOOL, CHAR)
				Set8(1, 0);
				codegen_gen(sLDA, StackRelative, x->a, 0);                // LDA x->a,S (8-bit)
				codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);           // STA $reg
			  } else {
				// Word load from stack (handles INTEGER and other multi-byte types)
				Set16(1, 1);
				codegen_gen(sLDA, StackRelative, x->a, 0);                // LDA x->a,S (16-bit)
				codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);           // STA $reg
                }
            } else {
			  GetSB(x->r);
			  // 65C816: Load module global variable from $1000+offset
			  if (x->type->size == 1) {
				// Byte load from global (handles BYTE, BOOL, CHAR)
				Set8(1, 0);
				codegen_gen(sLDA, Absolute, MODULE_VAR_BASE + x->a, 0);   // LDA $1000+offset (8-bit)
				codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);           // STA $reg
			  } else {
				// Word load from global (handles INTEGER and other multi-byte types)
				Set16(1, 1);
				codegen_gen(sLDA, Absolute, MODULE_VAR_BASE + x->a, 0);   // LDA $1000+offset (16-bit)
				codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);           // STA $reg
			  }
            }
            x->r = RH;
            incR();
        } else if (x->mode == ORB_Par) {
		  // 65C816: Load VAR parameter - first load the 4-byte pointer into registers,
		  // then dereference through the pointer to get the actual value
		  
		  // Load the 4-byte pointer from stack into two registers
		  Set16(1, 1);
		  // Load 16-bit address into first register
		  codegen_gen(sLDA, StackRelative, x->a, 0);        // LDA param_offset,S (load address)
		  codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);   // STA $reg0 (store address)
		  
		  // Load data bank into second register  
		  codegen_gen(sLDA, StackRelative, x->a + 2, 0);    // LDA param_offset+2,S (load data bank)
		  codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0); // STA $reg1 (store data bank)
		  
		  // Now dereference through the pointer using DirectPageIndirectLong
		  if (x->type->size == 1) {
			// Byte load through pointer
			Set8(1, 0);  // 8-bit accumulator
			codegen_gen(sLDA, DirectPageIndirectLong, reg_addr(RH), 0); // LDA [$reg0] (dereference)
			codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);         // STA $reg2 (store result)
		  } else {
			// Word load through pointer  
			Set16(1, 1); // 16-bit accumulator
			codegen_gen(sLDA, DirectPageIndirectLong, reg_addr(RH), 0); // LDA [$reg0] (dereference)
			codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);         // STA $reg2 (store result)
		  }		  
		  x->r = RH;  // Result is in the third register
		  incR();         // Advance to next available register
        } else if (x->mode == RegI) {
		  // RISC: Put2(op, x->r, x->r, x->a);
        } else if (x->mode == Cond) {
		  // RISC: Put3(BC, negated(x->r), 2);
		  ORG_FixLink(x->b);
    // RISC: Put1(Mov, RH, 0, 1);
    // RISC: Put3(BC, 7, 1);
            ORG_FixLink(x->a);
    // RISC: Put1(Mov, RH, 0, 0);
            x->r = RH;
            incR();
        }
        x->mode = Reg;
    }
	return 1; // Temporary, later on we will update this
}

static void loadAdr(ORG_Item *x) {
    if (x->mode == ORB_Var) {
        if (x->r > 0) {
            // 65C816: Local variable - not yet implemented for VAR parameters
            ORS_Mark("loadAdr for local variables not yet implemented");
        } else {
            // 65C816: Global variable - calculate absolute address
            GetSB(x->r);
            Set16(1, 1);
            codegen_gen(sLDA, Immediate, MODULE_VAR_BASE + x->a, 0); // LDA #(MODULE_VAR_BASE + offset)
            codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);         // STA $reg
        }
        x->r = RH;
        incR();
    } else if (x->mode == ORB_Par) {
        // 65C816: Load address from VAR parameter (global variables only for now)
        // The stack contains the absolute address of the variable
        Set16(1, 1);
        codegen_gen(sLDA, StackRelative, x->a, 0);               // LDA param_offset,S (load address)
        codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);          // STA $reg
        if (x->b != 0) {
            // Add offset if present
            codegen_gen(sLDA, DirectPage, reg_addr(RH), 0);      // LDA $reg
            codegen_gen(sCLC, Implied, 0, 0);                    // CLC
            codegen_gen(sADC, Immediate, x->b, 0);               // ADC #offset  
            codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);      // STA $reg
        }
        x->r = RH;
        incR();
    } else if (x->mode == RegI) {
        if (x->a != 0) {
    // RISC: Put1a(Add, x->r, x->r, x->a);
        }
    } else {
        ORS_Mark("address error");
    }
    x->mode = Reg;
}

static void loadCond(ORG_Item *x) {
  if (x->type->form == ORB_Bool) {
	if (x->mode == ORB_Const) {
	  // For boolean constants: FALSE(0) -> 15, TRUE(1) -> 7
	  // This maps to branch conditions: 15=never, 7=always
	  x->r = 15 - x->a * 8;
	} else {
	  load(x);
	  // 65C816: Load sets Z flag. For boolean: 0=FALSE (Z=1), non-zero=TRUE (Z=0)
	  // We don't need explicit CMP if load already set flags appropriately
	  // Check if we need to compare with 0 (similar to RISC5 check)
	  // For now, assume load always sets flags correctly
	  x->r = NE;  // NE (9) = branch if not zero (TRUE condition)
	  RH--;
	}
	x->mode = Cond;
	x->a = 0;  // FALSE branch chain (initially empty)
	x->b = 0;  // TRUE branch chain (initially empty)
  } else {
	ORS_Mark("not Boolean?");
  }
}

static void loadTypTagAdr(ORB_Type *T) {
    ORG_Item x;
    x.mode = ORB_Var;
    x.a = T->len;
    x.r = -T->mno;
    loadAdr(&x);
}

static void loadStringAdr(ORG_Item *x) {
    GetSB(0);
    // RISC: Put1a(Add, RH, RH, ORG_varsize + x->a);
    x->mode = Reg;
    x->r = RH;
    incR();
}

// Item creation functions
void ORG_MakeConstItem(ORG_Item *x, ORB_Type *typ, LONGINT val) {
    x->mode = ORB_Const;
    x->type = typ;
    x->a = val;
}

void ORG_MakeRealItem(ORG_Item *x, REAL val) {
    x->mode = ORB_Const;
    x->type = realType;
    x->a = *(LONGINT*)&val;  // SYSTEM.VAL equivalent
}

void ORG_MakeStringItem(ORG_Item *x, LONGINT len) {
    LONGINT i = 0;
    x->mode = ORB_Const;
    x->type = strType;
    x->a = strx;
    x->b = len;
    
    if (strx + len + 4 < maxStrx) {
        while (len > 0) {
            str[strx] = ORS_str[i];
            strx++;
            i++;
            len--;
        }
        while (strx % 4 != 0) {
            str[strx] = 0;
            strx++;
        }
    } else {
        ORS_Mark("too many strings");
    }
}

void ORG_MakeItem(ORG_Item *x, ORB_Object *y, LONGINT curlev) {
    x->mode = y->class;
    x->type = y->type;
    x->a = y->val;
    x->rdo = y->rdo;
    
    if (y->class == ORB_Par) {
        x->b = 0;
    } else if ((y->class == ORB_Const) && (y->type->form == ORB_String)) {
        x->b = y->lev;
    } else {
        x->r = y->lev;
    }
    
    if ((y->lev > 0) && (y->lev != curlev) && (y->class != ORB_Const)) {
        ORS_Mark("not accessible ");
    }
}

// Selector operations
void ORG_Field(ORG_Item *x, ORB_Object *y) {
    if (x->mode == ORB_Var) {
        if (x->r >= 0) {
            x->a = x->a + y->val;
        } else {
            loadAdr(x);
            x->mode = RegI;
            x->a = y->val;
        }
    } else if (x->mode == RegI) {
        x->a = x->a + y->val;
    } else if (x->mode == ORB_Par) {
        x->b = x->b + y->val;
    }
}

void ORG_Index(ORG_Item *x, ORG_Item *y) {
    LONGINT s, lim;
    s = x->type->base->size;
    lim = x->type->len;
    
    if ((y->mode == ORB_Const) && (lim >= 0)) {
        if ((y->a < 0) || (y->a >= lim)) {
            ORS_Mark("bad index");
        }
        if ((x->mode == ORB_Var) || (x->mode == RegI)) {
            x->a = y->a * s + x->a;
        } else if (x->mode == ORB_Par) {
            x->b = y->a * s + x->b;
        }
    } else {
        load(y);
        if (check) {
            if (lim >= 0) {
    // RISC: Put1a(Cmp, RH, y->r, lim);
            } else {
                if ((x->mode == ORB_Var) || (x->mode == ORB_Par)) {
    // RISC: Put2(Ldr, RH, SP, x->a + 4 + frame);
    // RISC: Put0(Cmp, RH, y->r, RH);
                } else {
                    ORS_Mark("error in Index");
                }
            }
            Trap(10, 1);
        }
        
        if (s == 4) {
    // RISC: Put1(Lsl, y->r, y->r, 2);
        } else if (s > 1) {
    // RISC: Put1a(Mul, y->r, y->r, s);
        }
        
        if (x->mode == ORB_Var) {
            if (x->r > 0) {
    // RISC: Put0(Add, y->r, SP, y->r);
                x->a += frame;
            } else {
                GetSB(x->r);
                if (x->r == 0) {
    // RISC: Put0(Add, y->r, RH, y->r);
                } else {
    // RISC: Put1a(Add, RH, RH, x->a);
    // RISC: Put0(Add, y->r, RH, y->r);
                    x->a = 0;
                }
            }
            x->r = y->r;
            x->mode = RegI;
        } else if (x->mode == ORB_Par) {
    // RISC: Put2(Ldr, RH, SP, x->a + frame);
    // RISC: Put0(Add, y->r, RH, y->r);
            x->mode = RegI;
            x->r = y->r;
            x->a = x->b;
        } else if (x->mode == RegI) {
    // RISC: Put0(Add, x->r, x->r, y->r);
            RH--;
        }
    }
}

void ORG_DeRef(ORG_Item *x) {
    if (x->mode == ORB_Var) {
        if (x->r > 0) {
    // RISC: Put2(Ldr, RH, SP, x->a + frame);
        } else {
            GetSB(x->r);
    // RISC: Put2(Ldr, RH, RH, x->a);
        }
        NilCheck();
        x->r = RH;
        incR();
    } else if (x->mode == ORB_Par) {
    // RISC: Put2(Ldr, RH, SP, x->a + frame);
    // RISC: Put2(Ldr, RH, RH, x->b);
        NilCheck();
        x->r = RH;
        incR();
    } else if (x->mode == RegI) {
    // RISC: Put2(Ldr, x->r, x->r, x->a);
        NilCheck();
    } else if (x->mode != Reg) {
        ORS_Mark("bad mode in DeRef");
    }
    x->mode = RegI;
    x->a = 0;
    x->b = 0;
}

static void Q(ORB_Type *T, LONGINT *dcw) {
    if (T->base != NULL) {
        Q(T->base, dcw);
        data[*dcw] = (T->mno * 0x1000 + T->len) * 0x1000 + *dcw - fixorgT;
        fixorgT = *dcw;
        (*dcw)++;
    }
}

static void FindPtrFlds(ORB_Type *typ, LONGINT off, LONGINT *dcw) {
    ORB_Object *fld;
    LONGINT i, s;
    
    if ((typ->form == ORB_Pointer) || (typ->form == ORB_NilTyp)) {
        data[*dcw] = off;
        (*dcw)++;
    } else if (typ->form == ORB_Record) {
        fld = typ->dsc;
        while (fld != NULL) {
            FindPtrFlds(fld->type, fld->val + off, dcw);
            fld = fld->next;
        }
    } else if (typ->form == ORB_Array) {
        s = typ->base->size;
        for (i = 0; i < typ->len; i++) {
            FindPtrFlds(typ->base, i * s + off, dcw);
        }
    }
}

void ORG_BuildTD(ORB_Type *T, LONGINT *dc) {
    LONGINT dcw, k, s;
    dcw = *dc / 4;
    s = T->size;
    
    if (s <= 24) {
        s = 32;
    } else if (s <= 56) {
        s = 64;
    } else if (s <= 120) {
        s = 128;
    } else {
        s = (s + 263) / 256 * 256;
    }
    
    T->len = *dc;
    data[dcw] = s;
    dcw++;
    k = T->nofpar;
    
    if (k > 3) {
        ORS_Mark("ext level too large");
    } else {
        Q(T, &dcw);
        while (k < 3) {
            data[dcw] = -1;
            dcw++;
            k++;
        }
    }
    
    FindPtrFlds(T, 0, &dcw);
    data[dcw] = -1;
    dcw++;
    tdx = dcw;
    *dc = dcw * 4;
    
    if (tdx >= maxTD) {
        ORS_Mark("too many record types");
        tdx = 0;
    }
}

void ORG_TypeTest(ORG_Item *x, ORB_Type *T, BOOLEAN varpar, BOOLEAN isguard) {
    LONGINT pc0;
    
    if (T == NULL) {
        if (x->mode >= Reg) {
            RH--;
        }
        SetCC(x, 7);
    } else {
        if (varpar) {
    // RISC: Put2(Ldr, RH, SP, x->a + 4 + frame);
        } else {
            load(x);
            pc0 = ORG_pc;
    // RISC: Put3(BC, EQ, 0);
    // RISC: Put2(Ldr, RH, x->r, -8);
        }
    // RISC: Put2(Ldr, RH, RH, T->nofpar * 4);
        incR();
        loadTypTagAdr(T);
    // RISC: Put0(Cmp, RH - 1, RH - 1, RH - 2);
        RH -= 2;
        
        if (!varpar) {
            fix(pc0, ORG_pc - pc0 - 1);
        }
        
        if (isguard) {
            if (check) {
                Trap(NE, 2);
            }
        } else {
            SetCC(x, EQ);
            if (!varpar) {
                RH--;
            }
        }
    }
}

// Boolean operators
/*
  PROCEDURE Not*(VAR x: Item);   (* x := ~x *)
    VAR t: LONGINT;
  BEGIN
    IF x.mode # Cond THEN loadCond(x) END ;
    x.r := negated(x.r); t := x.a; x.a := x.b; x.b := t
  END Not;
*/
void ORG_Not(ORG_Item *x) {
    LONGINT t;
    
    // Convert to condition mode if not already
    if (x->mode != Cond) {
        loadCond(x);
    }
    
    // Negate the condition code (EQ<->NE, MI<->PL, etc.)
    x->r = negated(x->r);
    
    // Swap the TRUE and FALSE branch chains
    t = x->a;
    x->a = x->b;
    x->b = t;
}

/*
  PROCEDURE And1*(VAR x: Item);   (* x := x & *)
  BEGIN
    IF x.mode # Cond THEN loadCond(x) END ;
    Put3(BC, negated(x.r), x.a); x.a := pc-1; FixLink(x.b); x.b := 0
  END And1;
*/
void ORG_And1(ORG_Item *x) {
    if (x->mode != Cond) {
        loadCond(x);
    }
    // Generate branch with negated condition to FALSE chain
    // If x is FALSE, jump to FALSE result (short-circuit)
    emitBranch(negated(x->r), x->a);
    x->a = ORG_pc - 1;  // Save current branch location for FALSE chain
    ORG_FixLink(x->b);  // Fix up previous TRUE branches
    x->b = 0;           // Reset TRUE chain
}

/*
  PROCEDURE And2*(VAR x, y: Item);
  BEGIN
    IF y.mode # Cond THEN loadCond(y) END ;
    x.a := merged(y.a, x.a); x.b := y.b; x.r := y.r
  END And2;
*/
void ORG_And2(ORG_Item *x, ORG_Item *y) {
    if (y->mode != Cond) {
        loadCond(y);
    }
    // Merge FALSE chains: if either x or y is FALSE, jump to FALSE result
    x->a = merged(y->a, x->a);
    // Use second operand's result for TRUE chain and condition
    x->b = y->b;
    x->r = y->r;
}  

/*
  PROCEDURE Or1*(VAR x: Item);   (* x := x OR *)
  BEGIN
    IF x.mode # Cond THEN loadCond(x) END ;
    Put3(BC, x.r, x.b);  x.b := pc-1; FixLink(x.a); x.a := 0
  END Or1;
*/
void ORG_Or1(ORG_Item *x) {
    if (x->mode != Cond) {
        loadCond(x);
    }
    // Generate branch with condition (NOT negated) to TRUE chain
    // If x is TRUE, jump to TRUE result (short-circuit)
    emitBranch(x->r, x->b);
    x->b = ORG_pc - 1;  // Save current branch location for TRUE chain
    ORG_FixLink(x->a);  // Fix up previous FALSE branches
    x->a = 0;           // Reset FALSE chain
}

/*
  PROCEDURE Or2*(VAR x, y: Item);
  BEGIN
    IF y.mode # Cond THEN loadCond(y) END ;
    x.a := y.a; x.b := merged(y.b, x.b); x.r := y.r
  END Or2;
*/
void ORG_Or2(ORG_Item *x, ORG_Item *y) {
    if (y->mode != Cond) {
        loadCond(y);
    }
    // Use second operand's FALSE chain
    x->a = y->a;
    // Merge TRUE chains: if either x or y is TRUE, jump to TRUE result
    x->b = merged(y->b, x->b);
    // Use second operand's condition
    x->r = y->r;
}

// Arithmetic operators
void ORG_Neg(ORG_Item *x) {
    if (x->type->form == ORB_Int) {
        if (x->mode == ORB_Const) {
            x->a = -x->a;
        } else {
            load(x);
    // RISC: Put1(Mov, RH, 0, 0);
    // RISC: Put0(Sub, x->r, RH, x->r);
        }
    } else if (x->type->form == ORB_Real) {
        if (x->mode == ORB_Const) {
            x->a = x->a + 0x7FFFFFFF + 1;
        } else {
            load(x);
    // RISC: Put1(Mov, RH, 0, 0);
    // RISC: Put0(Fsb, x->r, RH, x->r);
        }
    } else { // Set
        if (x->mode == ORB_Const) {
            x->a = -x->a - 1;
        } else {
            load(x);
    // RISC: Put1(Xor, x->r, x->r, -1);
        }
    }
}

void ORG_AddOp(LONGINT op, ORG_Item *x, ORG_Item *y) {
    int reg_count = 0;
    
    if (op == ORS_plus) {
        if ((x->mode == ORB_Const) && (y->mode == ORB_Const)) {
            x->a = x->a + y->a;
        } else if (y->mode == ORB_Const) {
            reg_count += load(x);
            if (y->a != 0) {
                // RISC: Put1a(Add, x->r, x->r, y->a);
                // 65C816: Add immediate to register
			  if (x->type->form == ORB_Int && x->type->size == 2) {
				Set16(1, 1);
				codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);  // LDA $reg
				codegen_gen(sCLC, Implied, 0, 0);                  // CLC
				codegen_gen(sADC, Immediate, y->a, 0);             // ADC #constant
				codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);  // STA $reg
			  }
            }
        } else {
            reg_count += load(x);
            reg_count += load(y);
            // RISC: Put0(Add, RH - 2, x->r, y->r);
            // 65C816: Add two registers
            if (x->type->form == ORB_Int && x->type->size == 2) {
			  Set16(1, 1);
			  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);  // LDA $reg_x
			  codegen_gen(sCLC, Implied, 0, 0);                  // CLC
			  codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);  // ADC $reg_y
			  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);  // STA $reg_x
            }
            RH -= (reg_count - 1);  // Keep one register for result, deallocate the rest
            x->r = RH - 1;
        }
    } else { // minus
        if ((x->mode == ORB_Const) && (y->mode == ORB_Const)) {
            x->a = x->a - y->a;
        } else if (y->mode == ORB_Const) {
            reg_count += load(x);
            if (y->a != 0) {
                // RISC: Put1a(Sub, x->r, x->r, y->a);
                // 65C816: Subtract immediate from register
                if (x->type->form == ORB_Int && x->type->size == 2) {
				  Set16(1, 1);
				  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);  // LDA $reg
				  codegen_gen(sSEC, Implied, 0, 0);                  // SEC
				  codegen_gen(sSBC, Immediate, y->a, 0);             // SBC #constant
				  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);  // STA $reg
                }
            }
        } else {
            reg_count += load(x);
            reg_count += load(y);
            // RISC: Put0(Sub, RH - 2, x->r, y->r);
            // 65C816: Subtract two registers
            if (x->type->form == ORB_Int && x->type->size == 2) {
			  Set16(1, 1);
			  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);  // LDA $reg_x
			  codegen_gen(sSEC, Implied, 0, 0);                  // SEC
			  codegen_gen(sSBC, DirectPage, reg_addr(y->r), 0);  // SBC $reg_y
			  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);  // STA $reg_x
            }
            RH -= (reg_count - 1);  // Keep one register for result, deallocate the rest
            x->r = RH - 1;
        }
    }
}

static LONGINT ORG_log2(LONGINT m, LONGINT *e) {
    *e = 0;
    while ((m % 2) == 0) {
        m = m / 2;
        (*e)++;
    }
    return m;
}

void ORG_MulOp(ORG_Item *x, ORG_Item *y) {
    LONGINT e;
    
    if ((x->mode == ORB_Const) && (y->mode == ORB_Const)) {
        x->a = x->a * y->a;
    } else if ((y->mode == ORB_Const) && (y->a >= 2) && (ORG_log2(y->a, &e) == 1)) {
        load(x);
    // RISC: Put1(Lsl, x->r, x->r, e);
    } else if (y->mode == ORB_Const) {
        load(x);
    // RISC: Put1a(Mul, x->r, x->r, y->a);
    } else if ((x->mode == ORB_Const) && (x->a >= 2) && (ORG_log2(x->a, &e) == 1)) {
        load(y);
    // RISC: Put1(Lsl, y->r, y->r, e);
        x->mode = Reg;
        x->r = y->r;
    } else if (x->mode == ORB_Const) {
        load(y);
    // RISC: Put1a(Mul, y->r, y->r, x->a);
        x->mode = Reg;
        x->r = y->r;
    } else {
        load(x);
        load(y);
    // RISC: Put0(Mul, RH - 2, x->r, y->r);
        RH--;
        x->r = RH - 1;
    }
}

void ORG_DivOp(LONGINT op, ORG_Item *x, ORG_Item *y) {
    LONGINT e;
    
    if (op == ORS_div) {
        if ((x->mode == ORB_Const) && (y->mode == ORB_Const)) {
            if (y->a > 0) {
                x->a = x->a / y->a;
            } else {
                ORS_Mark("bad divisor");
            }
        } else if ((y->mode == ORB_Const) && (y->a >= 2) && (ORG_log2(y->a, &e) == 1)) {
            load(x);
    // RISC: Put1(Asr, x->r, x->r, e);
        } else if (y->mode == ORB_Const) {
            if (y->a > 0) {
                load(x);
    // RISC: Put1a(Div, x->r, x->r, y->a);
            } else {
                ORS_Mark("bad divisor");
            }
        } else {
            load(y);
            if (check) {
                Trap(LE, 6);
            }
            load(x);
    // RISC: Put0(Div, RH - 2, x->r, y->r);
            RH--;
            x->r = RH - 1;
        }
    } else { // mod
        if ((x->mode == ORB_Const) && (y->mode == ORB_Const)) {
            if (y->a > 0) {
                x->a = x->a % y->a;
            } else {
                ORS_Mark("bad modulus");
            }
        } else if ((y->mode == ORB_Const) && (y->a >= 2) && (ORG_log2(y->a, &e) == 1)) {
            load(x);
            if (e <= 16) {
    // RISC: Put1(And, x->r, x->r, y->a - 1);
            } else {
    // RISC: Put1(Lsl, x->r, x->r, 32 - e);
    // RISC: Put1(Ror, x->r, x->r, 32 - e);
            }
        } else if (y->mode == ORB_Const) {
            if (y->a > 0) {
                load(x);
    // RISC: Put1a(Div, x->r, x->r, y->a);
    // RISC: Put0(Mov + U, x->r, 0, 0);
            } else {
                ORS_Mark("bad modulus");
            }
        } else {
            load(y);
            if (check) {
                Trap(LE, 6);
            }
            load(x);
    // RISC: Put0(Div, RH - 2, x->r, y->r);
    // RISC: Put0(Mov + U, RH - 2, 0, 0);
            RH--;
            x->r = RH - 1;
        }
    }
}

void ORG_RealOp(INTEGER op, ORG_Item *x, ORG_Item *y) {
    load(x);
    load(y);
    
    if (op == ORS_plus) {
    // RISC: Put0(Fad, RH - 2, x->r, y->r);
    } else if (op == ORS_minus) {
    // RISC: Put0(Fsb, RH - 2, x->r, y->r);
    } else if (op == ORS_times) {
    // RISC: Put0(Fml, RH - 2, x->r, y->r);
    } else if (op == ORS_rdiv) {
    // RISC: Put0(Fdv, RH - 2, x->r, y->r);
    }
    
    RH--;
    x->r = RH - 1;
}

// Set operators
void ORG_Singleton(ORG_Item *x) {
    if (x->mode == ORB_Const) {
        x->a = 1L << x->a;
    } else {
        load(x);
    // RISC: Put1(Mov, RH, 0, 1);
    // RISC: Put0(Lsl, x->r, RH, x->r);
    }
}

void ORG_Set(ORG_Item *x, ORG_Item *y) {
    if ((x->mode == ORB_Const) && (y->mode == ORB_Const)) {
        if (x->a <= y->a) {
            x->a = (2L << y->a) - (1L << x->a);
        } else {
            x->a = 0;
        }
    } else {
        if ((x->mode == ORB_Const) && (x->a <= 16)) {
            x->a = (-1L) << x->a;
        } else {
            load(x);
    // RISC: Put1(Mov, RH, 0, -1);
    // RISC: Put0(Lsl, x->r, RH, x->r);
        }
        
        if ((y->mode == ORB_Const) && (y->a < 16)) {
    // RISC: Put1(Mov, RH, 0, (-2L) << y->a);
            y->mode = Reg;
            y->r = RH;
            incR();
        } else {
            load(y);
    // RISC: Put1(Mov, RH, 0, -2);
    // RISC: Put0(Lsl, y->r, RH, y->r);
        }
        
        if (x->mode == ORB_Const) {
            if (x->a != 0) {
    // RISC: Put1(Xor, y->r, y->r, -1);
    // RISC: Put1a(And, RH - 1, y->r, x->a);
            }
            x->mode = Reg;
            x->r = RH - 1;
        } else {
            RH--;
    // RISC: Put0(Ann, RH - 1, x->r, y->r);
        }
    }
}

void ORG_In(ORG_Item *x, ORG_Item *y) {
    load(y);
    if (x->mode == ORB_Const) {
    // RISC: Put1(Ror, y->r, y->r, (x->a + 1) % 0x20);
        RH--;
    } else {
        load(x);
    // RISC: Put1(Add, x->r, x->r, 1);
    // RISC: Put0(Ror, y->r, y->r, x->r);
        RH -= 2;
    }
    SetCC(x, MI);
}

void ORG_SetOp(LONGINT op, ORG_Item *x, ORG_Item *y) {
    if ((x->mode == ORB_Const) && (y->mode == ORB_Const)) {
        // Use direct bit operations instead of SET type
        if (op == ORS_plus) {
            x->a = x->a | y->a;
        } else if (op == ORS_minus) {
            x->a = x->a & ~y->a;
        } else if (op == ORS_times) {
            x->a = x->a & y->a;
        } else if (op == ORS_rdiv) {
            x->a = x->a ^ y->a;
        }
    } else if (y->mode == ORB_Const) {
        load(x);
        if (op == ORS_plus) {
    // RISC: Put1a(Ior, x->r, x->r, y->a);
        } else if (op == ORS_minus) {
    // RISC: Put1a(Ann, x->r, x->r, y->a);
        } else if (op == ORS_times) {
    // RISC: Put1a(And, x->r, x->r, y->a);
        } else if (op == ORS_rdiv) {
    // RISC: Put1a(Xor, x->r, x->r, y->a);
        }
    } else {
        load(x);
        load(y);
        if (op == ORS_plus) {
    // RISC: Put0(Ior, RH - 2, x->r, y->r);
        } else if (op == ORS_minus) {
    // RISC: Put0(Ann, RH - 2, x->r, y->r);
        } else if (op == ORS_times) {
    // RISC: Put0(And, RH - 2, x->r, y->r);
        } else if (op == ORS_rdiv) {
    // RISC: Put0(Xor, RH - 2, x->r, y->r);
        }
        RH--;
        x->r = RH - 1;
    }
}

// Relation operators
/*
  PROCEDURE IntRelation*(op: INTEGER; VAR x, y: Item);   (* x := x < y *)
  BEGIN
    IF (y.mode = ORB.Const) & (y.type.form # ORB.Proc) THEN
      load(x);
      IF (y.a # 0) OR ~(op IN {ORS.eql, ORS.neq}) OR (code[pc-1] DIV 40000000H # -2) THEN Put1a(Cmp, x.r, x.r, y.a) END ;
      DEC(RH)
    ELSE
      IF (x.mode = Cond) OR (y.mode = Cond) THEN ORS.Mark("not implemented") END ;
      load(x); load(y); Put0(Cmp, x.r, x.r, y.r); DEC(RH, 2)
    END ;
    SetCC(x, relmap[op - ORS.eql])
  END IntRelation;
*/
void ORG_IntRelation(INTEGER op, ORG_Item *x, ORG_Item *y) {
    BOOLEAN use_8bit = (x->type->form == ORB_Char) || (x->type->form == ORB_Byte) || (x->type->form == ORB_Bool);
    
    if (use_8bit) {
        Set8(1, 0);  // Switch to 8-bit accumulator mode
    }
    
    if ((y->mode == ORB_Const) && (y->type->form != ORB_Proc)) {
        load(x);
        if ((y->a != 0) || ((op != ORS_eql) && (op != ORS_neq))) {
            // 65C816: Compare with immediate value
		  // ToDo: Handle correct size
		  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);  // LDA $reg_x
		  codegen_gen(sCMP, Immediate, y->a, 0);             // CMP #immediate
        }
        RH--;
    } else {
        if ((x->mode == Cond) || (y->mode == Cond)) {
            ORS_Mark("not implemented");
        }
        load(x);
        load(y);
        // 65C816: Compare two registers
		// ToDo: Handle correct size
        codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);  // LDA $reg_x
        codegen_gen(sCMP, DirectPage, reg_addr(y->r), 0);  // CMP $reg_y
        RH -= 2;
    }
    
    if (use_8bit) {
        Set16(1, 1);  // Switch back to 16-bit accumulator mode
    }
    
    SetCC(x, relmap[op - ORS_eql]);
}

void ORG_RealRelation(INTEGER op, ORG_Item *x, ORG_Item *y) {
    load(x);
    if ((y->mode == ORB_Const) && (y->a == 0)) {
        RH--;
    } else {
        load(y);
    // RISC: Put0(Fsb, x->r, x->r, y->r);
        RH -= 2;
    }
    SetCC(x, relmap[op - ORS_eql]);
}

void ORG_StringRelation(INTEGER op, ORG_Item *x, ORG_Item *y) {
    if (x->type->form == ORB_String) {
        loadStringAdr(x);
    } else {
        loadAdr(x);
    }
    
    if (y->type->form == ORB_String) {
        loadStringAdr(y);
    } else {
        loadAdr(y);
    }
    
    // RISC: Put2(Ldr + 1, RH, x->r, 0);
    // RISC: Put1(Add, x->r, x->r, 1);
    // RISC: Put2(Ldr + 1, RH + 1, y->r, 0);
    // RISC: Put1(Add, y->r, y->r, 1);
    // RISC: Put0(Cmp, RH + 2, RH, RH + 1);
    // RISC: Put3(BC, NE, 2);
    // RISC: Put1(Cmp, RH + 2, RH, 0);
    // RISC: Put3(BC, NE, -8);
    RH -= 2;
    SetCC(x, relmap[op - ORS_eql]);
}

// Assignment operations
void ORG_StrToChar(ORG_Item *x) {
    x->type = charType;
    strx -= 4;
    x->a = str[x->a];
}

void ORG_Store(ORG_Item *x, ORG_Item *y) {
    LONGINT op;
    
    load(y);
    if (x->type->size == 1) {
        op = Str + 1;
    } else {
        op = Str;
    }
    
    if (x->mode == ORB_Var) {
        if (x->r > 0) {
            // 65C816: Store to stack-based local variable with type conversion
            if (y->mode == Reg) {
                if (x->type->size == 1 && y->type->size == 1) {
                    // BYTE to BYTE store (no conversion needed)
                    Set8(1, 0);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);     // LDA $reg
                    codegen_gen(sSTA, StackRelative, x->a, 0);            // STA x->a,S (8-bit)
                } else if (x->type->size == 1 && y->type->size > 1) {
                    // INTEGER to BYTE store (truncate to low byte)
                    Set8(1, 0);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);     // LDA $reg
                    codegen_gen(sSTA, StackRelative, x->a, 0);            // STA x->a,S (8-bit)
                } else if (x->type->size > 1 && y->type->size == 1) {
                    // BYTE to INTEGER store (zero-extend)
                    Set16(1, 0);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);     // LDA $reg (already zero-extended from load)
                    codegen_gen(sSTA, StackRelative, x->a, 0);            // STA x->a,S (16-bit)
                } else {
                    // INTEGER to INTEGER store (no conversion needed)
				  Set16(1, 0);
				  codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);     // LDA $reg
				  codegen_gen(sSTA, StackRelative, x->a, 0);            // STA x->a,S (16-bit)
                }
            }
        } else {
            GetSB(x->r);
    // RISC: Put2(op, y->r, RH, x->a);
            // RISC: RH--;  // This was for freeing GetSB register, not needed for 65C816
            
            // 65C816: Store register value to module global variable with type conversion
            if (y->mode == Reg) {
                if (x->type->size == 1 && y->type->size == 1) {
                    // BYTE to BYTE store (no conversion needed)
                    Set8(1, 0);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);        // LDA $reg
                    codegen_gen(sSTA, Absolute, MODULE_VAR_BASE + x->a, 0);  // STA $1000+offset (8-bit)
                } else if (x->type->size == 1 && y->type->size > 1) {
                    // INTEGER to BYTE store (truncate to low byte)
                    Set8(1, 0);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);        // LDA $reg
                    codegen_gen(sSTA, Absolute, MODULE_VAR_BASE + x->a, 0);  // STA $1000+offset (8-bit)
                } else if (x->type->size > 1 && y->type->size == 1) {
                    // BYTE to INTEGER store (zero-extend)
                    Set8(1, 0);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);        // LDA $reg (already zero-extended from load)
                    codegen_gen(sSTA, Absolute, MODULE_VAR_BASE + x->a, 0);  // STA $1000+offset (16-bit)
                } else {
                    // INTEGER to INTEGER store (no conversion needed)
				  Set16(1, 1);
				  codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);        // LDA $reg
				  codegen_gen(sSTA, Absolute, MODULE_VAR_BASE + x->a, 0);  // STA $1000+offset (16-bit)
                }
            }
        }
    } else if (x->mode == ORB_Par) {
        // 65C816: Store to VAR parameter - load the 4-byte pointer into registers,
        // then store through the pointer using DirectPageIndirectLong
        
        if (y->mode == Reg) {
            // Load the 4-byte pointer from stack into two registers
            Set16(1, 1);
            // Load 16-bit address into a temporary register
            codegen_gen(sLDA, StackRelative, x->a, 0);        // LDA param_offset,S (load address)
            codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);   // STA $temp_reg (store address)
            
            // Load data bank into next register  
            codegen_gen(sLDA, StackRelative, x->a + 2, 0);    // LDA param_offset+2,S (load data bank)
            codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0); // STA $temp_reg+1 (store data bank)
            
            // Now store the value through the pointer using DirectPageIndirectLong
            if (x->type->size == 1 && y->type->size == 1) {
                // BYTE to BYTE store (no conversion needed)
                Set8(1, 0);  // 8-bit accumulator
                codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);     // LDA $reg (load value)
                codegen_gen(sSTA, DirectPageIndirectLong, reg_addr(RH), 0); // STA [$temp_reg] (store through pointer)
            } else if (x->type->size == 1 && y->type->size > 1) {
                // INTEGER to BYTE store (truncate to low byte)
                Set8(1, 0);  // 8-bit accumulator
                codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);     // LDA $reg (8-bit truncates)
                codegen_gen(sSTA, DirectPageIndirectLong, reg_addr(RH), 0); // STA [$temp_reg] (store through pointer)
            } else if (x->type->size > 1 && y->type->size == 1) {
                // BYTE to INTEGER store (zero-extend)
                Set16(1, 1); // 16-bit accumulator
                codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);     // LDA $reg (already zero-extended)
                codegen_gen(sSTA, DirectPageIndirectLong, reg_addr(RH), 0); // STA [$temp_reg] (store through pointer)
            } else {
                // INTEGER to INTEGER store (no conversion needed)
                Set16(1, 1); // 16-bit accumulator
                codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);     // LDA $reg (load value)
                codegen_gen(sSTA, DirectPageIndirectLong, reg_addr(RH), 0); // STA [$temp_reg] (store through pointer)
            }
        }
    } else if (x->mode == RegI) {
        // 65C816: Store to register indirect
        // Store value with type conversion
        if (y->mode == Reg) {
            if (x->type->size == 1 && y->type->size == 1) {
                // BYTE to BYTE store (no conversion needed)
                Set8(1, 0);
                codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);  // LDA $reg
                codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0);  // LDX $x->r (address)
                codegen_gen(sSTA, AbsoluteIndexedX, x->a, 0);      // STA x->a,X (8-bit)
            } else if (x->type->size == 1 && y->type->size > 1) {
                // INTEGER to BYTE store (truncate to low byte)
                Set8(1, 0);
                codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);  // LDA $reg
                codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0);  // LDX $x->r (address)
                codegen_gen(sSTA, AbsoluteIndexedX, x->a, 0);      // STA x->a,X (8-bit)
            } else if (x->type->size > 1 && y->type->size == 1) {
                // BYTE to INTEGER store (zero-extend)
                Set16(1, 1);
                codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);  // LDA $reg (already zero-extended from load)
                codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0);  // LDX $x->r (address)
                codegen_gen(sSTA, AbsoluteIndexedX, x->a, 0);      // STA x->a,X (16-bit)
            } else {
                // INTEGER to INTEGER store (no conversion needed)
                Set16(1, 1);
                codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);  // LDA $reg
                codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0);  // LDX $x->r (address)
                codegen_gen(sSTA, AbsoluteIndexedX, x->a, 0);      // STA x->a,X (16-bit)
            }
        }
        RH--;
    } else {
        ORS_Mark("bad mode in Store");
    }
    RH--;
}

void ORG_StoreStruct(ORG_Item *x, ORG_Item *y) {
    LONGINT s, pc0;
    
    if (y->type->size != 0) {
        loadAdr(x);
        loadAdr(y);
        
        if ((x->type->form == ORB_Array) && (x->type->len > 0)) {
            if (y->type->len >= 0) {
                if (x->type->size == y->type->size) {
    // RISC: Put1a(Mov, RH, 0, (y->type->size + 3) / 4);
                } else {
                    ORS_Mark("different length/size, not implemented");
                }
            } else {
    // RISC: Put2(Ldr, RH, SP, y->a + 4);
                s = y->type->base->size;
                pc0 = ORG_pc;
    // RISC: Put3(BC, EQ, 0);
                
                if (s == 1) {
    // RISC: Put1(Add, RH, RH, 3);
    // RISC: Put1(Asr, RH, RH, 2);
                } else if (s != 4) {
    // RISC: Put1a(Mul, RH, RH, s / 4);
                }
                
                if (check) {
    // RISC: Put1a(Mov, RH + 1, 0, (x->type->size + 3) / 4);
    // RISC: Put0(Cmp, RH + 1, RH, RH + 1);
                    Trap(GT, 3);
                }
                fix(pc0, ORG_pc + 5 - pc0);
            }
        } else if (x->type->form == ORB_Record) {
    // RISC: Put1a(Mov, RH, 0, x->type->size / 4);
        } else {
            ORS_Mark("inadmissible assignment");
        }
        
    // RISC: Put2(Ldr, RH + 1, y->r, 0);
    // RISC: Put1(Add, y->r, y->r, 4);
    // RISC: Put2(Str, RH + 1, x->r, 0);
    // RISC: Put1(Add, x->r, x->r, 4);
    // RISC: Put1(Sub, RH, RH, 1);
    // RISC: Put3(BC, NE, -6);
    }
    RH = 0;
}

void ORG_CopyString(ORG_Item *x, ORG_Item *y) {
    LONGINT len;
    
    loadAdr(x);
    len = x->type->len;
    
    if (len >= 0) {
        if (len < y->b) {
            ORS_Mark("string too long");
        }
    } else if (check) {
    // RISC: Put2(Ldr, RH, SP, x->a + 4);
    // RISC: Put1(Cmp, RH, RH, y->b);
        Trap(LT, 3);
    }
    
    loadStringAdr(y);
    // RISC: Put2(Ldr, RH, y->r, 0);
    // RISC: Put1(Add, y->r, y->r, 4);
    // RISC: Put2(Str, RH, x->r, 0);
    // RISC: Put1(Add, x->r, x->r, 4);
    // RISC: Put1(Asr, RH, RH, 24);
    // RISC: Put3(BC, NE, -6);
    RH = 0;
}

// Parameter operations
void ORG_OpenArrayParam(ORG_Item *x) {
    loadAdr(x);
    if (x->type->len >= 0) {
    // RISC: Put1a(Mov, RH, 0, x->type->len);
    } else {
    // RISC: Put2(Ldr, RH, SP, x->a + 4 + frame);
    }
    incR();
}

void ORG_VarParam(ORG_Item *x, ORB_Type *ftype) {
    INTEGER xmd = x->mode;
    
    // Check if this is a local variable - implement 24-bit address calculation
    if (x->mode == ORB_Var && x->r > 0) {
        // 65C816: Calculate 24-bit address of local variable using stack pointer
        // For local variables, we need to store a 3-byte pointer on the stack:
        // - First store 16-bit 0 (this writes 00 00 in first two bytes)
        // - Then store the calculated 16-bit address (overwrites the second 00)
        // - Result: [00] [low addr] [high addr] = 24-bit pointer with data bank 0
        
        Set16(1, 1);
        // Calculate the actual stack address: TSC - SEC - SBC #offset
        codegen_gen(sTSC, Implied, 0, 0);                       // TSC - get stack pointer
        codegen_gen(sCLC, Implied, 0, 0);                       // CLC - clear carry for addition
        codegen_gen(sADC, Immediate, x->a, 0);                  // ADC #offset - add local var offset
        codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);         // STA $reg - store calculated address
		
        x->r = RH;  // Acutally RH and RH+1
        x->mode = Reg;
        incR();

		// Store 16-bit 0 to define this as being in bank 0, where the stack resides
        codegen_gen(sLDA, Immediate, 0, 0);                     // LDA #0
        codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);         // STA $reg (store 0)
        incR();
        
        return;
    }
    
    // For module-level global variables (x->r <= 0), load absolute address
    if (x->mode == ORB_Var && x->r <= 0) {
        // 65C816: Store 24-bit address of global variable using two registers (32-bit space)
        Set16(1, 1);
        // Store the 16-bit address in first register
        codegen_gen(sLDA, Immediate, MODULE_VAR_BASE + x->a, 0);  // LDA #(MODULE_VAR_BASE + offset)
        codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);          // STA $reg (16-bit address)
        
        // Store data bank byte (0) in second register (also zeros high byte)
        codegen_gen(sLDA, Immediate, 0, 0);                      // LDA #0
        codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0);     // STA $reg+1 (data bank = 0)
        
        x->r = RH;
        x->mode = Reg;
        incR();  // Allocate first register
        incR();  // Allocate second register for 24-bit value
    } else {
        // For other cases (parameters, etc.), use original loadAdr approach
        loadAdr(x);
    }
    
    if ((ftype->form == ORB_Array) && (ftype->len < 0)) {
        if (x->type->len >= 0) {
            // 65C816: Load array length for open arrays
            Set16(1, 1);
            codegen_gen(sLDA, Immediate, x->type->len, 0);        // LDA #array_length
            codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);      // STA $reg
        } else {
    // RISC: Put2(Ldr, RH, SP, x->a + 4 + frame);
        }
        incR();
    } else if (ftype->form == ORB_Record) {
        if (xmd == ORB_Par) {
    // RISC: Put2(Ldr, RH, SP, x->a + 4 + frame);
            incR();
        } else {
            loadTypTagAdr(x->type);
        }
    }
}

void ORG_ValueParam(ORG_Item *x) {
    load(x);
}

void ORG_StringParam(ORG_Item *x) {
    loadStringAdr(x);
    // RISC: Put1(Mov, RH, 0, x->b);
    incR();
}

// For statement operations
void ORG_For0(ORG_Item *x, ORG_Item *y) {
    load(y);
}

void ORG_For1(ORG_Item *x, ORG_Item *y, ORG_Item *z, ORG_Item *w, LONGINT *L) {
    // Compare loop variable with limit
    if (z->mode == ORB_Const) {
        // Compare y register with immediate constant z->a
        load(y);
		if (z->type->size == 1) {
		  Set8(1, 0);
		} else {
		  Set16(1, 1);
		}
        codegen_gen(sCMP, Immediate, z->a, 0);
    } else {
        // Compare y register with z register
        load(y);
        load(z);
		if ((y->type->size == 1) && (z->type->size == 1)) {
		  Set8(1, 0);
		} else {
		  Set16(1, 1);
		}
        codegen_gen(sCMP, DirectPage, reg_addr(y->r), 0);
        RH--;
    }
    
    // Generate conditional branch based on increment direction
    if (w->a > 0) {
        // Positive increment: branch if greater than limit (exit loop)
        emitBranch(GT, 0);  // Forward branch, will be fixed up later
    } else if (w->a < 0) {
        // Negative increment: branch if less than limit (exit loop)
        emitBranch(LT, 0);  // Forward branch, will be fixed up later
    } else {
        ORS_Mark("zero increment");
        emitBranch(MI, 0);  // This shouldn't happen, but handle error case
    }
    
    *L = ORG_pc - 1;  // Save location of branch for later fixup
    
    // Store initial value in loop variable
    ORG_Store(x, y);
}

void ORG_For2(ORG_Item *x, ORG_Item *y, ORG_Item *w) {
    // Increment/decrement loop variable by step amount
    load(x);

    // Add the increment value to the loop variable
    if (w->mode == ORB_Const) {
        // Add immediate constant to accumulator
        if (w->a > 0) {
            codegen_gen(sADC, Immediate, w->a, 0);
        } else {
            // For negative increment, use SBC (subtract)
            codegen_gen(sSBC, Immediate, -w->a, 0);
        }
    } else {
        // Add register value (less common case)
        load(w);
        codegen_gen(sADC, DirectPage, reg_addr(w->r), 0);
        RH--;
    }
    
    // Store the incremented value back to the loop variable
    // The value is already in the accumulator, just store it to x
    if (x->mode == ORB_Var) {
        codegen_gen(sSTA, Absolute, MODULE_VAR_BASE + x->a, 0);
    } else {
        codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
    }
    RH--;
}

// Branch and jump operations
LONGINT ORG_Here(void) {
    return ORG_pc;
}

/*
  PROCEDURE FJump*(VAR L: LONGINT);
  BEGIN Put3(BC, 7, L); L := pc-1
  END FJump;
*/
void ORG_FJump(LONGINT *L) {
    // Generate unconditional forward jump
    emitBranch(7, *L);  // Unconditional branch (condition 7 = always)
    *L = ORG_pc - 1;    // Save location for later fixup
}

/*
  PROCEDURE CFJump*(VAR x: Item);
  BEGIN
    IF x.mode # Cond THEN loadCond(x) END ;
    Put3(BC, negated(x.r), x.a); FixLink(x.b); x.a := pc-1
  END CFJump;
*/
void ORG_CFJump(ORG_Item *x) {
    if (x->mode != Cond) {
        loadCond(x);
    }
    // Generate branch with negated condition (for forward jump on FALSE)
    emitBranch(negated(x->r), x->a);
    ORG_FixLink(x->b);  // Fix up TRUE branches
    x->a = ORG_pc - 1;  // Save location for FALSE branch fixup
}

/*
  PROCEDURE BJump*(L: LONGINT);
  BEGIN Put3(BC, 7, L-pc-1)
  END BJump;
*/
void ORG_BJump(LONGINT L) {
    emitBranch(7, L);  // Unconditional branch
}

/*
  PROCEDURE CBJump*(VAR x: Item; L: LONGINT);
  BEGIN
    IF x.mode # Cond THEN loadCond(x) END ;
    Put3(BC, negated(x.r), L-pc-1); FixLink(x.b); FixLinkWith(x.a, L)
  END CBJump;
*/
void ORG_CBJump(ORG_Item *x, LONGINT L) {
    if (x->mode != Cond) {
        loadCond(x);
    }
    // Generate branch with negated condition (for backward jump on FALSE)
    emitBranch(negated(x->r), L);
    ORG_FixLink(x->b);     // Fix up TRUE branches
    FixLinkWith(x->a, L);  // Fix up FALSE branches to target L
}

void ORG_Fixup(ORG_Item *x) {
    ORG_FixLink(x->a);
}

static void SaveRegs(LONGINT r) {
    LONGINT ri = 0;
    // 65C816: Push registers to stack
	Set16(1, 1);
    frame += 2 * r;  // Each register is 2 bytes (16-bit)
    do {
        // LDA $reg and PHA to push register value onto stack
        codegen_gen(sLDA, DirectPage, reg_addr(ri), 0);  // LDA $reg
        codegen_gen(sPHA, Implied, 0, 0);                // PHA
        ri++;
    } while (ri < r);
}

static void RestoreRegs(LONGINT r) {
    LONGINT ri = r;
    // 65C816: Pull registers from stack in reverse order
	Set16(1, 1);
    do {
        ri--;
        // PLA and STA $reg to restore register value from stack
        codegen_gen(sPLA, Implied, 0, 0);                // PLA
        codegen_gen(sSTA, DirectPage, reg_addr(ri), 0);  // STA $reg
    } while (ri > 0);
    frame -= 2 * r;  // Each register is 2 bytes (16-bit)
}

void ORG_PrepCall(ORG_Item *x, LONGINT *r) {
    if (x->mode > ORB_Par) {
        load(x);
    }
    *r = RH;
    if (RH > 0) {
        SaveRegs(RH);
        RH = 0;
    }
    
    // 65C816: Stack allocation moved to ORG_Call to happen immediately before JSR
}

void ORG_Call(ORG_Item *x, LONGINT r) {
    if (x->mode == ORB_Const) {
        if (x->r >= 0) {
    // RISC: Put3(BL, 7, (x->a / 4) - ORG_pc - 1);
            // 65C816: Allocate stack space immediately before JSR
			Set16(1, 1); // Ensure Long A when starting a procedure
            LONGINT frame_size = x->type->size;  // Frame size stored in procedure type
            if (frame_size > 0) {
			  codegen_gen(sTSC, Implied, 0, 0);           // TSC (Transfer Stack to A)
			  codegen_gen(sSEC, Implied, 0, 0);           // SEC
			  codegen_gen(sSBC, Immediate, frame_size, 0); // SBC #frame_size
			  codegen_gen(sTCS, Implied, 0, 0);           // TCS (Transfer A to Stack)
            }
            // 65C816: JSR to procedure address
            codegen_gen(sJSR, Absolute, x->a, 0);  // JSR procedure_address
        } else {
		  if (ORG_pc - fixorgP < 0x100) {
			fixorgP = ORG_pc - 1;
		  } else {
			ORS_Mark("fixup impossible");
		  }
        }
    } else {
	  if (x->mode <= ORB_Par) {
		load(x);
		RH--;
	  } else {
		// RISC: Put2(Ldr, RH, SP, 0);
		// RISC: Put1(Add, SP, SP, 4);
		r--;
		frame -= 2;
	  }
	  if (check) {
		Trap(EQ, 5);
	  }
	  // RISC: Put3(BLR, 7, RH);
    }
    
    if (x->type->base->form == ORB_NoTyp) {
	  RH = 0;
    } else {
	  if (r > 0) {
		// RISC: Put0(Mov, r, 0, 0);
		RestoreRegs(r);
	  }
	  x->mode = Reg;
	  x->r = r;
	  RH = r + 1;
    }
}

void ORG_Enter(ORB_Object *params, LONGINT locblksize, BOOLEAN int_proc) {
  LONGINT a, r;
  ORB_Object *param;
  
  if (!int_proc) {
	if (locblksize >= 0x10000) {
	  ORS_Mark("too many locals");
	}
	a = 4;
	r = 0;
        
	// 65C816: Stack allocation now happens in caller before JSR
        
	// 65C816: Store register parameters to their stack locations using actual parameter types
	r = 0;  // Start with register 0
	param = params;  // Start with first parameter

	Set16(1, 1);
	while (param != NULL && (param->class == ORB_Var || param->class == ORB_Par)) {
	  // For VAR parameters (ORB_Par with rdo=FALSE), we need to store the pointer value itself 
	  // to the stack frame, not store through the pointer
	  if (param->class == ORB_Par && !param->rdo) {
	    // VAR parameter: Store 4-byte pointer value to stack using two registers
	    // First register contains 16-bit address, second register contains data bank (0)
	    
	    // Store the 16-bit address from first register
	    codegen_gen(sLDA, DirectPage, reg_addr(r), 0);     // LDA $reg (load 16-bit address)
	    codegen_gen(sSTA, StackRelative, param->val, 0);   // STA param->val,S (store address)
	    
	    // Store the data bank and high byte from second register
	    codegen_gen(sLDA, DirectPage, reg_addr(r + 1), 0); // LDA $reg+1 (load data bank)
	    codegen_gen(sSTA, StackRelative, param->val + 2, 0); // STA param->val+2,S (store data bank)
	    
	    // Result on stack: [addr_low] [addr_high] [00] [00] = 4-byte pointer
	  } else {
	    // Regular parameter or complex type parameter: Use normal ORG_Store
	    ORG_Item param_item, reg_item;
	    
	    // Use ORG_MakeItem to create parameter item (destination) from ORB_Object
	    ORG_MakeItem(&param_item, param, param->lev);
	    
	    // Set up register item (source) 
	    reg_item.mode = Reg;
	    reg_item.type = param->type;
	    reg_item.r = r;             // Register number
	    reg_item.rdo = TRUE;
	    
	    // Use ORG_Store to handle the transfer with correct processor modes
	    ORG_Store(&param_item, &reg_item);
	  }
	  
	  // VAR parameters use two registers, regular parameters use one
	  if (param->class == ORB_Par && !param->rdo) {
	    r += 2;  // VAR parameter uses two registers for 24-bit pointer
	  } else {
	    r++;     // Regular parameter uses one register
	  }
	  param = param->next;
	}
	
	// Reset register stack - parameters are now stored on stack, registers are free
	RH = 0;
  } else {
	// Interrupt procedure - allocate full stack frame
	if (locblksize > 0) {
	  codegen_gen(sSEC, Implied, 0, 0);           // SEC
	  codegen_gen(sSBC, Immediate, locblksize, 0); // SBC #locblksize
	  codegen_gen(sTCS, Implied, 0, 0);           // TCS (Transfer A to Stack)
	}
  }
}

void ORG_Return(INTEGER form, ORG_Item *x, LONGINT size, BOOLEAN int_proc) {
  if (form != ORB_NoTyp) {
	load(x);
  }
  
  if (!int_proc) {
	// 65C816: Handle return address and frame deallocation
	if (size > 0) {  // Only if caller allocated space
	  // PLX - Pull return address into X register (2 bytes)
	  Set16(1, 1);
	  codegen_gen(sPLX, Implied, 0, 0);           // PLX
	  
	  // Deallocate frame space using A register
	  codegen_gen(sTSC, Implied, 0, 0);           // TSC (Transfer Stack to A)
	  codegen_gen(sCLC, Implied, 0, 0);           // CLC
	  codegen_gen(sADC, Immediate, size, 0);     // ADC #size (frame space)
	  codegen_gen(sTCS, Implied, 0, 0);           // TCS (Transfer A to Stack)
	  
	  // PHX - Push return address back to top of stack
	  codegen_gen(sPHX, Implied, 0, 0);           // PHX
	}
	// 65C816: RTS to return from subroutine
	codegen_gen(sRTS, Implied, 0, 0);  // RTS
  } else {
	// Interrupt procedure - deallocate full stack frame
	if (size > 0) {
	  codegen_gen(sCLC, Implied, 0, 0);           // CLC
	  codegen_gen(sADC, Immediate, size, 0);     // ADC #size
	  codegen_gen(sTCS, Implied, 0, 0);           // TCS (Transfer A to Stack)
	}
	codegen_gen(sRTI, Implied, 0, 0);  // RTI
  }
  RH = 0;
}

// Inline procedures
void ORG_Increment(LONGINT upordown, ORG_Item *x, ORG_Item *y) {
      LONGINT op, zr, v;
    
    if (upordown == 0) {
	  op = Add;
    } else {
	  op = Sub;
    }
    
    if (x->type == byteType) {
	  v = 1;
    } else {
	  v = 0;
    }
    
    if (y->type->form == ORB_NoTyp) {
	  y->mode = ORB_Const;
	  y->a = 1;
    }
    
    if ((x->mode == ORB_Var) && (x->r > 0)) {
	  zr = RH;
	  // RISC: Put2(Ldr + v, zr, SP, x->a);
	  incR();
	  if (y->mode == ORB_Const) {
		// RISC: Put1a(op, zr, zr, y->a);
	  } else {
		load(y);
		// RISC: Put0(op, zr, zr, y->r);
		RH--;
	  }
	  // RISC: Put2(Str + v, zr, SP, x->a);
	  RH--;
    } else {
	  loadAdr(x);
	  zr = RH;
	  // RISC: Put2(Ldr + v, RH, x->r, 0);
	  incR();
	  if (y->mode == ORB_Const) {
		// RISC: Put1a(op, zr, zr, y->a);
	  } else {
		load(y);
		// RISC: Put0(op, zr, zr, y->r);
		RH--;
	  }
	  // RISC: Put2(Str + v, zr, x->r, 0);
	  RH -= 2;
    }
}

void ORG_Include(LONGINT inorex, ORG_Item *x, ORG_Item *y) {
  LONGINT op, zr;
  
  loadAdr(x);
  zr = RH;
  // RISC: Put2(Ldr, RH, x->r, 0);
  incR();
  
  if (inorex == 0) {
	op = Ior;
  } else {
	op = Ann;
  }
  
  if (y->mode == ORB_Const) {
    // RISC: Put1a(op, zr, zr, 1L << y->a);
  } else {
	load(y);
    // RISC: Put1(Mov, RH, 0, 1);
    // RISC: Put0(Lsl, y->r, RH, y->r);
    // RISC: Put0(op, zr, zr, y->r);
	RH--;
  }
  // RISC: Put2(Str, zr, x->r, 0);
  RH -= 2;
}

void ORG_Assert(ORG_Item *x) {
  LONGINT cond;
  
  if (x->mode != Cond) {
	loadCond(x);
  }
  
  if (x->a == 0) {
	cond = negated(x->r);
  } else {
    // RISC: Put3(BC, x->r, x->b);
	ORG_FixLink(x->a);
	x->b = ORG_pc - 1;
	cond = 7;
  }
  Trap(cond, 7);
  ORG_FixLink(x->b);
}

void ORG_New(ORG_Item *x) {
  loadAdr(x);
  loadTypTagAdr(x->type->base);
  Trap(7, 0);
  RH = 0;
}

void ORG_Pack(ORG_Item *x, ORG_Item *y) {
  ORG_Item z = *x;
  load(x);
  load(y);
  // RISC: Put1(Lsl, y->r, y->r, 23);
  // RISC: Put0(Add, x->r, x->r, y->r);
  RH--;
  ORG_Store(&z, x);
}

void ORG_Unpk(ORG_Item *x, ORG_Item *y) {
  ORG_Item z, e0;
  z = *x;
  load(x);
  e0.mode = Reg;
  e0.r = RH;
  e0.type = intType;
  // RISC: Put1(Asr, RH, x->r, 23);
  // RISC: Put1(Sub, RH, RH, 127);
  ORG_Store(y, &e0);
  incR();
  // RISC: Put1(Lsl, RH, RH, 23);
  // RISC: Put0(Sub, x->r, x->r, RH);
  ORG_Store(&z, x);
}

void ORG_Led(ORG_Item *x) {
  load(x);
  // RISC: Put1(Mov, RH, 0, -60);
  // RISC: Put2(Str, x->r, RH, 0);
  RH--;
}

void ORG_Get(ORG_Item *x, ORG_Item *y) {
  // 65C816: GET(address, var) - load byte value from address into variable
  // For system procedures, parameters are passed as expressions and need to be loaded
  
  // Load address parameter into r0
  load(x);
  
  // Load address from r0 into X register for indexed addressing
  codegen_gen(sLDX, DirectPage, reg_addr(0), 0);  // LDX $00 (r0 = address)
  
  // Clear the high byte of A before changing to shorta
  codegen_gen(sLDA, Immediate, 0, 0);  
  
  // Switch to 8-bit accumulator mode for byte operations (keep X/Y 16-bit)
  Set8(1, 0);
  
  // Load byte value from address: LDA address,X
  codegen_gen(sLDA, AbsoluteIndexedX, 0, 0);      // LDA $0000,X (8-bit load)
  
  // Restore 16-bit accumulator mode
  Set16(1, 1);
  
  // Store the loaded value into r0 for assignment
  codegen_gen(sSTA, DirectPage, reg_addr(0), 0);  // STA $00 (r0 = result)
  
  // Set up result item for assignment to the variable
  y->mode = Reg;
  y->r = 0;
  
  // Reset register stack
  RH = 1;
}

void ORG_Put(ORG_Item *x, ORG_Item *y) {
  // 65C816: PUT(address, value) - store byte value at address
  // For system procedures, parameters are passed as expressions and need to be loaded
  
  // Load address parameter into r0
  load(x);
  
  // Load value parameter into r1  
  load(y);
  
  // Load address from r0 into X register for indexed addressing
  codegen_gen(sLDX, DirectPage, reg_addr(0), 0);  // LDX $00 (r0 = address)
  
  // Switch to 8-bit accumulator mode for byte operations (keep X/Y 16-bit)
  Set8(1, 0);
  
  // Load value from r1 into A register (8-bit load)
  codegen_gen(sLDA, DirectPage, reg_addr(1), 0);  // LDA $02 (r1 = value, 8-bit)
  
  // Store byte value to address: STA address,X 
  codegen_gen(sSTA, AbsoluteIndexedX, 0, 0);      // STA $0000,X (8-bit store)
  
  // Restore 16-bit accumulator mode
  Set16(1, 1);
  
  // Reset register stack
  RH = 0;
}

void ORG_Copy(ORG_Item *x, ORG_Item *y, ORG_Item *z) {
  load(x);
  load(y);
  
  if (z->mode == ORB_Const) {
	if (z->a > 0) {
	  load(z);
	} else {
	  ORS_Mark("bad count");
	}
  } else {
	load(z);
	if (check) {
	  Trap(LT, 3);
	}
    // RISC: Put3(BC, EQ, 6);
  }
    
  // RISC: Put2(Ldr, RH, x->r, 0);
  // RISC: Put1(Add, x->r, x->r, 4);
  // RISC: Put2(Str, RH, y->r, 0);
  // RISC: Put1(Add, y->r, y->r, 4);
  // RISC: Put1(Sub, z->r, z->r, 1);
  // RISC: Put3(BC, NE, -6);
  RH -= 3;
}

void ORG_LDPSR(ORG_Item *x) {
  // RISC: Put3(0, 15, x->a + 0x20);
}

void ORG_LDREG(ORG_Item *x, ORG_Item *y) {
  if (y->mode == ORB_Const) {
    // RISC: Put1a(Mov, x->a, 0, y->a);
  } else {
	load(y);
    // RISC: Put0(Mov, x->a, 0, y->r);
	RH--;
  }
}

// Inline functions
void ORG_Abs(ORG_Item *x) {
  if (x->mode == ORB_Const) {
	x->a = (x->a < 0) ? -x->a : x->a;  // ABS equivalent
  } else {
	load(x);
	if (x->type->form == ORB_Real) {
	  // RISC: Put1(Lsl, x->r, x->r, 1);
	  // RISC: Put1(Ror, x->r, x->r, 1);
	} else {
	  // RISC: Put1(Cmp, x->r, x->r, 0);
	  // RISC: Put3(BC, GE, 2);
	  // RISC: Put1(Mov, RH, 0, 0);
	  // RISC: Put0(Sub, x->r, RH, x->r);
	}
  }
}

void ORG_Odd(ORG_Item *x) {
  load(x);
  // RISC: Put1(And, x->r, x->r, 1);
  SetCC(x, NE);
  RH--;
}

void ORG_Floor(ORG_Item *x) {
  load(x);
  // RISC: Put1(Mov + U, RH, 0, 0x4B00);
  // RISC: Put0(Fad + V, x->r, x->r, RH);
}

void ORG_Float(ORG_Item *x) {
  load(x);
  // RISC: Put1(Mov + U, RH, 0, 0x4B00);
  // RISC: Put0(Fad + U, x->r, x->r, RH);
}

void ORG_Ord(ORG_Item *x) {
  if ((x->mode == ORB_Var) || (x->mode == ORB_Par) || 
	  (x->mode == RegI) || (x->mode == Cond)) {
	load(x);
  }
}

void ORG_Len(ORG_Item *x) {
  if (x->type->len >= 0) {
	if (x->mode == RegI) {
	  RH--;
	}
	x->mode = ORB_Const;
	x->a = x->type->len;
  } else {
    // RISC: Put2(Ldr, RH, SP, x->a + 4 + frame);
	x->mode = Reg;
	x->r = RH;
	incR();
  }
}

void ORG_Shift(LONGINT fct, ORG_Item *x, ORG_Item *y) {
  LONGINT op;
  
  load(x);
  if (fct == 0) {
	op = Lsl;
  } else if (fct == 1) {
	op = Asr;
  } else {
	op = Ror;
  }
  
  if (y->mode == ORB_Const) {
    // RISC: Put1(op, x->r, x->r, y->a % 0x20);
  } else {
	load(y);
    // RISC: Put0(op, RH - 2, x->r, y->r);
	RH--;
	x->r = RH - 1;
  }
}

void ORG_ADC(ORG_Item *x, ORG_Item *y) {
  load(x);
  load(y);
  // RISC: Put0(Add + 0x2000, x->r, x->r, y->r);
  RH--;
}

void ORG_SBC(ORG_Item *x, ORG_Item *y) {
  load(x);
  load(y);
  // RISC: Put0(Sub + 0x2000, x->r, x->r, y->r);
  RH--;
}

void ORG_UML(ORG_Item *x, ORG_Item *y) {
  load(x);
  load(y);
  // RISC: Put0(Mul + 0x2000, x->r, x->r, y->r);
  RH--;
}

void ORG_Bit(ORG_Item *x, ORG_Item *y) {
  load(x);
  // RISC: Put2(Ldr, x->r, x->r, 0);
  if (y->mode == ORB_Const) {
    // RISC: Put1(Ror, x->r, x->r, y->a + 1);
	RH--;
  } else {
	load(y);
    // RISC: Put1(Add, y->r, y->r, 1);
    // RISC: Put0(Ror, x->r, x->r, y->r);
	RH -= 2;
  }
  SetCC(x, MI);
}

void ORG_Register(ORG_Item *x) {
  // RISC: Put0(Mov, RH, 0, x->a % 0x10);
  x->mode = Reg;
  x->r = RH;
  incR();
}

void ORG_HH(ORG_Item *x) {
  // RISC: Put0(Mov + U + (x->a % 2) * V, RH, 0, 0);
  x->mode = Reg;
  x->r = RH;
  incR();
}

void ORG_Adr(ORG_Item *x) {
    if ((x->mode == ORB_Var) || (x->mode == ORB_Par) || (x->mode == RegI)) {
	  loadAdr(x);
    } else if ((x->mode == ORB_Const) && (x->type->form == ORB_Proc)) {
	  load(x);
    } else if ((x->mode == ORB_Const) && (x->type->form == ORB_String)) {
	  loadStringAdr(x);
    } else {
	  ORS_Mark("not addressable");
    }
}

void ORG_Condition(ORG_Item *x) {
  SetCC(x, x->a);
}

// Module management functions
void ORG_Open(INTEGER v) {
  ORG_pc = CODE_ORG;
  tdx = 0;
  strx = 0;
  RH = 0;
  fixorgP = 0;
  fixorgD = 0;
  fixorgT = 0;
  check = (v != 0);
  version = v;
  
  if (v == 0) {
	ORG_pc = 1;
	do {
	  code[ORG_pc] = 0;
	  ORG_pc++;
	} while (ORG_pc < 8);
  }
  longa = true; longi = true;         
}

void ORG_SetDataSize(LONGINT dc) {
  ORG_varsize = dc;
}

void ORG_Header(void) {
  entry = ORG_pc;  // 65C816 uses byte addresses, no multiplication needed
  if (version == 0) {
	// code[0] = 0xE7000000 - 1 + ORG_pc;
    // RISC: Put1a(Mov, SP, 0, StkOrg0);
  } else {
    // RISC: Put1(Sub, SP, SP, 4);
    // RISC: Put2(Str, LNK, SP, 0);
  }
  
  // 65C816: Initialize native mode (16-bit accumulator and index registers)
  codegen_gen(sCLC, Implied, 0, 0);        // Clear carry for XCE
  codegen_gen(sXCE, Implied, 0, 0);        // Switch to native mode
  longa = false; longi = false;            // Force the REP
  Set16(1, 1);
}

static LONGINT NofPtrs(ORB_Type *typ) {
  ORB_Object *fld;
  LONGINT n;
  
  if ((typ->form == ORB_Pointer) || (typ->form == ORB_NilTyp)) {
	n = 1;
  } else if (typ->form == ORB_Record) {
	fld = typ->dsc;
	n = 0;
	while (fld != NULL) {
	  n = NofPtrs(fld->type) + n;
	  fld = fld->next;
	}
  } else if (typ->form == ORB_Array) {
	n = NofPtrs(typ->base) * typ->len;
  } else {
	n = 0;
  }
  return n;
}

static void FindPtrs(Files_Rider *R, ORB_Type *typ, LONGINT adr) {
  ORB_Object *fld;
  LONGINT i, s;
  
  if ((typ->form == ORB_Pointer) || (typ->form == ORB_NilTyp)) {
	Files_WriteInt(R, adr);
  } else if (typ->form == ORB_Record) {
	fld = typ->dsc;
	while (fld != NULL) {
	  FindPtrs(R, fld->type, fld->val + adr);
	  fld = fld->next;
	}
  } else if (typ->form == ORB_Array) {
	s = typ->base->size;
	for (i = 0; i < typ->len; i++) {
	  FindPtrs(R, typ->base, i * s + adr);
	}
  }
}

void ORG_Close(ORS_Ident modid, LONGINT key, LONGINT nofent) {
  ORB_Object *obj;
  LONGINT i, comsize, nofimps, nofptrs, size;
  ORS_Ident name;
  Files_File *F;
  Files_Rider R;
  
  // Exit code
  if (version == 0) {
    // RISC: Put1(Mov, 0, 0, 0);
    // RISC: Put3(BR, 7, 0);
	// 65C816: Return to system
	codegen_gen(sRTS, Implied, 0, 0);
  } else {
    // RISC: Put2(Ldr, LNK, SP, 0);
    // RISC: Put1(Add, SP, SP, 4);
    // RISC: Put3(BR, 7, LNK);
	// 65C816: Return from subroutine
	codegen_gen(sRTS, Implied, 0, 0);
  }
  
  obj = topScope->next;
  nofimps = 0;
  comsize = 4;
  nofptrs = 0;
  
  while (obj != NULL) {
	if ((obj->class == ORB_Mod) && (obj->dsc != systemScope)) {
	  nofimps++;
	} else if ((obj->exno != 0) && (obj->class == ORB_Const) && 
			   (obj->type->form == ORB_Proc) && (obj->type->nofpar == 0) && 
			   (obj->type->base == noType)) {
	  i = 0;
	  while (obj->name[i] != 0) i++;
	  i = (i + 4) / 4 * 4;
	  comsize += i + 4;
	} else if (obj->class == ORB_Var) {
	  nofptrs += NofPtrs(obj->type);
	}
	obj = obj->next;
  }
  
  size = ORG_varsize + strx + comsize + (ORG_pc + nofimps + nofent + nofptrs + 1) * 4;
  
  MakeFileName(name, modid, ".816");
  F = Files_New(name);
  Files_Set(&R, F, 0);
  Files_WriteString(&R, modid);
  Files_WriteInt(&R, key);
  Files_Write(&R, (char)version);
  Files_WriteInt(&R, size);
  
  obj = topScope->next;
  while ((obj != NULL) && (obj->class == ORB_Mod)) {
	if (obj->dsc != systemScope) {
	  Files_WriteString(&R, ((ORB_Module*)obj)->orgname);
	  Files_WriteInt(&R, obj->val);
	}
	obj = obj->next;
  }
  Files_Write(&R, 0);
  
  Files_WriteInt(&R, tdx * 4);
  i = 0;
  while (i < tdx) {
	Files_WriteInt(&R, data[i]);
	i++;
  }
  
  Files_WriteInt(&R, ORG_varsize - tdx * 4);
  Files_WriteInt(&R, strx);
  for (i = 0; i < strx; i++) {
	Files_Write(&R, str[i]);
  }
  
  Files_WriteInt(&R, ORG_pc - CODE_ORG);
  for (i = 0; i < ORG_pc - CODE_ORG; i++) {
	Files_Write(&R, code[i]);
  }
  
  obj = topScope->next;
  while (obj != NULL) {
	if ((obj->exno != 0) && (obj->class == ORB_Const) && 
		(obj->type->form == ORB_Proc) && (obj->type->nofpar == 0) && 
		(obj->type->base == noType)) {
	  Files_WriteString(&R, obj->name);
	  Files_WriteInt(&R, obj->val);
	}
	obj = obj->next;
  }
  Files_Write(&R, 0);
  
  Files_WriteInt(&R, nofent);
  Files_WriteInt(&R, entry);
  
  obj = topScope->next;
  while (obj != NULL) {
	if (obj->exno != 0) {
	  if (((obj->class == ORB_Const) && (obj->type->form == ORB_Proc)) || 
		  (obj->class == ORB_Var)) {
		Files_WriteInt(&R, obj->val);
	  } else if (obj->class == ORB_Typ) {
		if (obj->type->form == ORB_Record) {
		  Files_WriteInt(&R, obj->type->len % 0x10000);
		} else if ((obj->type->form == ORB_Pointer) && 
				   ((obj->type->base->typobj == NULL) || 
					(obj->type->base->typobj->exno == 0))) {
		  Files_WriteInt(&R, obj->type->base->len % 0x10000);
		}
	  }
	}
	obj = obj->next;
  }
  
  obj = topScope->next;
  while (obj != NULL) {
	if (obj->class == ORB_Var) {
	  FindPtrs(&R, obj->type, obj->val);
	}
	obj = obj->next;
  }
  
  Files_WriteInt(&R, -1);
  Files_WriteInt(&R, fixorgP);
  Files_WriteInt(&R, fixorgD);
  Files_WriteInt(&R, fixorgT);
  Files_WriteInt(&R, entry);
  Files_Write(&R, 'O');
  Files_Register(F);
}

// Module initialization
void ORG_Init(void) {
  relmap[0] = EQ;   // eql -> EQ
  relmap[1] = NE;   // neq -> NE  
  relmap[2] = LT;   // lss -> LT
  relmap[3] = GE;   // geq -> GE
  relmap[4] = LE;  // leq -> LE
  relmap[5] = GT;  // gtr -> GT
  longa = true; longi = true;        
}
