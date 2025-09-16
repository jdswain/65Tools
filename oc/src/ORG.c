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
// WordSize now defined in ORG.h
#define StkOrg0 (-64)
#define VarOrg0 0
#define MT 12
// #define SP 14
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
#define AL 7
#define NV 15

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
  Set16(1, 1);  // We reset here as this is called at the end of every statement.
  // This is required because the start of any statement may be a branch target and we
  // need to ensure that if the statement needs to switch to 8-bit we always generate the SEP.
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
    // printf("DEBUG: SetCC called with condition code n=%ld\n", n);
    // Store the original operand type for signed comparison logic
    x->orig_type = x->type;  // Store original operand type
    x->mode = Cond;
    x->a = 0;
    x->b = 0;
    x->r = n;
    // x->type will be changed to BOOLEAN by the parser, but we have the original in x->orig_type
}

static void Trap(LONGINT cond, LONGINT num) {
  // In future we can use this for exception exits, but for now...
  // It would be useful to print a stack trace
  // ToDo: Should this be signed maths?
  switch (cond) {
  case EQ:  // Branch if Equal (Zero flag set)
	codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 4, 0);
	codegen_gen(sBRK, Immediate, num, 0);
	break;
  case NE:  // Branch if Not Equal (Zero flag clear)
	codegen_gen(sBNE, ProgramCounterRelative, ORG_pc + 4, 0);
	codegen_gen(sBRK, Immediate, num, 0);
	break;
  case MI:  // Branch if Minus (Negative flag set)
	codegen_gen(sBMI, ProgramCounterRelative, ORG_pc + 4, 0);
	codegen_gen(sBRK, Immediate, num, 0);
	break;
  case PL:  // Branch if Plus (Negative flag clear)
	codegen_gen(sBPL, ProgramCounterRelative, ORG_pc + 4, 0);
	codegen_gen(sBRK, Immediate, num, 0);
	break;
  case LT:  // Branch if Less Than - use BCC
	codegen_gen(sBCC, ProgramCounterRelative, ORG_pc + 4, 0);
	codegen_gen(sBRK, Immediate, num, 0);
	break;
  case GE:  // Branch if Greater or Equal - use BCS
	codegen_gen(sBCS, ProgramCounterRelative, ORG_pc + 4, 0);
	codegen_gen(sBRK, Immediate, num, 0);
	break;
  case LE:  // Branch if Less or Equal (also handles negated GT)
            // For negated GT: branch if NOT(A > B), which is A <= B
            // Check equality first, then use BCS for the < case
	codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 4 + 4, 0);
	codegen_gen(sBCC, ProgramCounterRelative, ORG_pc + 4 + 2, 0);
	codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 4, 0);  // over
	codegen_gen(sBRK, Immediate, num, 0);
	break;
  case GT:  // Branch if Greater Than
	codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 4 + 2, 0);
	codegen_gen(sBCS, ProgramCounterRelative, ORG_pc + 4, 0);
	codegen_gen(sBRK, Immediate, num, 0);
	break;
  case AL:
	codegen_gen(sBRK, Immediate, num, 0);
	break;
  default:
	ORS_Mark("Trap not implemented");
	break;
  }
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
        case AL: return NV;   // 7 -> 15
        case NV: return AL;   // 15 -> 7
        default: 
            printf("ERROR: Unknown condition code $%04X in negated()\n", cond);
            return cond;
    }
}

// Generate 65C816 branch instruction based on condition code
// target parameter is always a fixup chain link for forward branches
// (actual target will be resolved later by ORG_FixLink)
static void emitBranch(LONGINT cond, ORB_Type *type, AddrMode mode, LONGINT target) {
    // Debug output to trace condition codes
    // printf("DEBUG: emitBranch called with cond=$%04X, type->form=%d, type->size=$%04X, mode=%d, target=$%04X\n", cond, type->form, type->size, mode, target);

    switch (cond) {
        case EQ:  // Branch if Equal (Zero flag set)
            codegen_gen(sBNE, ProgramCounterRelative, ORG_pc + 2 + 3, 0);
            codegen_gen(sBRL, mode, target, 0);
            break;
        case NE:  // Branch if Not Equal (Zero flag clear)
            codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 3, 0);
			// This BRL is 1+ for some reason
            // printf("DEBUG: About to call codegen_gen(sBRL, mode=%d, target=$%04X, 0)\n", mode, target);
            codegen_gen(sBRL, mode, target, 0);
            break;
        case MI:  // Branch if Minus (Negative flag set)
            codegen_gen(sBPL, ProgramCounterRelative, ORG_pc + 2 + 3, 0);
            codegen_gen(sBRL, mode, target, 0);
            break;
        case PL:  // Branch if Plus (Negative flag clear)
            codegen_gen(sBMI, ProgramCounterRelative, ORG_pc + 2 + 3, 0);
            codegen_gen(sBRL, mode, target, 0);
            break;
        case LT:  // Branch if Less Than
            if (type->size == 2 && type->form == ORB_Int) {
                // Signed 16-bit comparison with single fixup point - INVERTED LOGIC
                // Branch to target when NOT greater or equal (condition is FALSE, i.e., less than)
                // Pattern: BVS INVERT; BMI TO_TARGET; BRA SKIP; INVERT: BPL TO_TARGET; BRA SKIP; TO_TARGET: BRA target; SKIP: ...
                
                codegen_gen(sBVS, ProgramCounterRelative, ORG_pc + 2 + 4, 0);  // BVS: if overflow, jump to INVERT
                codegen_gen(sBMI, ProgramCounterRelative, ORG_pc + 2 + 6, 0);  // BMI: if no overflow & negative, jump to TO_TARGET (less than)
                codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 7, 0);  // BRA: skip to SKIP (greater or equal)
                // INVERT section: overflow inverts meaning  
                codegen_gen(sBPL, ProgramCounterRelative, ORG_pc + 2 + 2, 0);  // BMI: if overflow & negative, jump to TO_TARGET (not less than)
                codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 3, 0);  // BRA: skip to SKIP (less than)
                // TO_TARGET: single fixup point
                codegen_gen(sBRL, mode, target, 0);                            // BRL target (single fixup)
                // SKIP: fall through when condition is TRUE (greater or equal)
            } else {
                // Unsigned comparison - use BCS
                codegen_gen(sBCS, mode, target, 0);
            }
            break;
        case GE:  // Branch if Greater or Equal  
            if (type->size == 2 && type->form == ORB_Int) {
                // Signed 16-bit comparison with single fixup point - INVERTED LOGIC
                // Branch to target when NOT less than (condition is FALSE)
                // Pattern: BVS INVERT; BPL TO_TARGET; BRA SKIP; INVERT: BMI TO_TARGET; BRA SKIP; TO_TARGET: BRA target; SKIP: ...
                
                codegen_gen(sBVS, ProgramCounterRelative, ORG_pc + 2 + 4, 0);  // BVS: if overflow, jump to INVERT
                codegen_gen(sBPL, ProgramCounterRelative, ORG_pc + 2 + 6, 0);  // BPL: if no overflow & positive, jump to TO_TARGET (NOT less)
                codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 7, 0);  // BRA: skip to SKIP (is less than)
                // INVERT section: overflow inverts meaning  
                codegen_gen(sBMI, ProgramCounterRelative, ORG_pc + 2 + 2, 0);  // BMI: if overflow & negative, jump to TO_TARGET (NOT less)
                codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 3, 0);  // BRA: skip to SKIP (is less than)
                // TO_TARGET: single fixup point
                codegen_gen(sBRL, mode, target, 0);                            // BRL target (single fixup)
                // SKIP: fall through when condition is TRUE (less than)
            } else {
                // Unsigned comparison - use BCC
                codegen_gen(sBCC, mode, target, 0);
            }
            break;
        case LE:  // Branch if Less or Equal
            if (type->size == 2 && type->form == ORB_Int) {
                // Signed 16-bit comparison - GT means NOT(LE)
                // First check for equality (if equal, don't branch)
                codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 13, 0);  // BEQ skip all GT logic (12 bytes ahead)
                // Then check for greater using signed logic (same as GE but excluding equality)
                // For signed: if V=0: BPL=GT, BMI=LT; if V=1: BMI=GT, BPL=LT
                codegen_gen(sBVS, ProgramCounterRelative, ORG_pc + 2 + 4, 0);  // BVS: if overflow, jump to INVERT
                codegen_gen(sBMI, ProgramCounterRelative, ORG_pc + 2 + 6, 0);  // BMI: if no overflow & negative, jump to TO_TARGET (less than)
                codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 7, 0);  // BRA: skip to SKIP (greater or equal)
                // INVERT section: overflow inverts meaning  
                codegen_gen(sBPL, ProgramCounterRelative, ORG_pc + 2 + 2, 0);  // BMI: if overflow & negative, jump to TO_TARGET (not less than)
                codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 3, 0);  // BRA: skip to SKIP (less than)
                // TO_TARGET: single fixup point
                codegen_gen(sBRL, mode, target, 0);                            // BRA target (single fixup)
            } else {
                // Unsigned comparison
                codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 2, 0);
                codegen_gen(sBCS, mode, target, 0);
            }
            break;
        case GT:  // Branch if Greater Than
            if (type->size == 2 && type->form == ORB_Int) {
                // Signed 16-bit comparison with single fixup point - INVERTED LOGIC
                // Branch to target when NOT less or equal (condition is FALSE, i.e., greater than)
                // First check for equality (if equal, fall through - don't branch to target)
                codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 13, 0);  // BEQ: skip all GT logic (fall through)
                // Then check for greater than using inverted signed logic
                codegen_gen(sBVS, ProgramCounterRelative, ORG_pc + 2 + 4, 0);  // BVS: if overflow, jump to INVERT
                codegen_gen(sBPL, ProgramCounterRelative, ORG_pc + 2 + 6, 0);  // BPL: if no overflow & positive, jump to TO_TARGET (greater)
                codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 7, 0);  // BRA: skip to SKIP (less or equal)
                // INVERT section: overflow inverts meaning  
                codegen_gen(sBMI, ProgramCounterRelative, ORG_pc + 2 + 2, 0);  // BPL: if overflow & positive result, jump to TO_TARGET (actual less, so GT is false)
                codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 3, 0);  // BRA: skip to SKIP (actual greater with overflow, so LE is false)
                // TO_TARGET: single fixup point
                codegen_gen(sBRL, mode, target, 0);                            // BRA target (single fixup)
                // SKIP: fall through when condition is TRUE (less or equal)
            } else {
                // Unsigned comparison
                // Check equality first, then use BCS for the < case
                codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 4, 0);
                codegen_gen(sBCC, ProgramCounterRelative, ORG_pc + 2 + 2, 0);
                codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 + 3, 0);  // over
                codegen_gen(sBRL, mode, target, 0);
            }
            break;
        case AL:   // Always branch (unconditional)
            codegen_gen(sBRL, mode, target, 0);
            break;
        case NV:  // Never branch (nop - could optimize away)
            // Do nothing for "never" condition
            break;
        default:
            ORS_Mark("condition not implemented");
            break;
    }
}

static void fix(LONGINT at, LONGINT target) {
    // For 65C816: All fixup locations are BRL instructions (3 bytes: $82 + 2-byte offset)
    // 'at' is the address of the low byte of the 2-byte offset field
    // 'target' is the target address
    // For BRL: offset = target - (branch_addr + 3) = target - (at + 2)
    LONGINT offset = target - (at + 1);
    LONGINT code_index = at - CODE_ORG;  // Index for low byte of offset
    
    if ((offset >= -128) && (offset <= 127)) {
        // Optimize to BRA (1-byte offset) + NOP
        code[code_index-1] = 0x80;           // Change opcode from BRL to BRA
        code[code_index] = offset & 0xFF;    // Store 1-byte offset
        code[code_index+1] = 0xEA;           // NOP in the high byte position
    } else {
	  // Keep as BRL (2-byte offset)
	  offset -= 1; // Adjust for extra byte for BRL
	  code[code_index] = offset & 0xFF;    // Store low byte of offset
	  code[code_index+1] = offset >> 8;    // Store high byte of offset
    }
}

void ORG_FixOne(LONGINT at) {
    // For 65C816: fix a single forward branch
    // 'at' is the address of the offset byte
    // Target is current ORG_pc
    // Original Oberon: fix(at, pc-at-1)
    // For 65C816 branches: offset = target - (branch_addr + 2) = target - (at + 1)
    // So target = ORG_pc, and we want offset = ORG_pc - (at + 1) = ORG_pc - at - 1
    fix(at, ORG_pc);
}

void ORG_FixLink(LONGINT L) {
    // For 65C816: fix a chain of forward branches
    // L is the address of the offset byte of the most recent branch
    LONGINT L1;
	LONGINT code_index;

    while (L != 0) {
	  code_index = L - CODE_ORG;  // Index for low byte of offset
	  // Read the 2-byte chain link BEFORE fixing (fix() will overwrite it)
	  L1 = code[code_index] | (code[code_index + 1] << 8);
      
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
	LONGINT code_index;
    while (L0 != 0) {
	  	code_index = L0 - CODE_ORG;  // Index for low byte of offset

        // Read the 2-byte chain link BEFORE fixing (fix() will overwrite it)
        L1 = code[code_index] | (code[code_index + 1] << 8);
        
        // Fix this branch to the specified destination
        fix(L0, dst);
        
        // Move to next branch in chain
        L0 = L1;
    }
}

static LONGINT merged(LONGINT L0, LONGINT L1) {
    LONGINT L2, L3;
	LONGINT code_index;
    if (L0 != 0) {
        L3 = L0;
        do {
            L2 = L3;
			code_index = L2 - CODE_ORG;  // Index for low byte of offset

            // For BRL instructions, read 2-byte chain link in little-endian format
            L3 = code[code_index] | (code[code_index + 1] << 8);
        } while (L3 != 0);
        
        // Update the 2-byte offset field with L1 in little-endian format
        code[code_index] = L1 & 0xFF;
        code[code_index + 1] = (L1 >> 8) & 0xFF;
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
				Set16(1, 0);
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
				Set16(1, 0);
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
				Set16(1, 0);
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
		  if (x->type->base->size == 1) {
			// Byte load through pointer
			Set8(1, 0);  // 8-bit accumulator
			codegen_gen(sLDA, DirectPageIndirectLong, reg_addr(RH), 0); // LDA [$reg0] (dereference)
			codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);         // STA $reg2 (store result)
			Set16(1, 0);  // 8-bit accumulator
		  } else {
			// Word load through pointer  
			Set16(1, 1); // 16-bit accumulator
			codegen_gen(sLDA, DirectPageIndirectLong, reg_addr(RH), 0); // LDA [$reg0] (dereference)
			codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);         // STA $reg2 (store result)
		  }		  
		  x->r = RH;  // Result is in the third register
		  incR();         // Advance to next available register
        } else if (x->mode == RegI) {
		  // 65C816: Load value from address in register + offset
		  if (x->a == 0) {
			// Simple case: LDA ($reg) - Direct Page Indirect
			codegen_gen(sLDA, DirectPageIndirect, reg_addr(x->r), 0);
		  } else {
			// Complex case: LDA ($reg),Y with offset
			codegen_gen(sLDY, Immediate, x->a, 0);
			codegen_gen(sLDA, DirectPageIndirectIndexedY, reg_addr(x->r), 0);
		  }
		  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);  // Store result back to same register
        } else if (x->mode == Cond) {
		  ORG_FixLink(x->b);
		  ORG_FixLink(x->a);
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
		    // Put1a(Add, RH, SP, x.a + frame)
            ORS_Mark("loadAdr for local variables not yet implemented");
        } else {
            // 65C816: Global variable - calculate absolute address
            GetSB(x->r);
			// RH := RH + x.a (immediate)
            Set16(1, 1);
            codegen_gen(sLDA, Immediate, (MODULE_VAR_BASE + x->a) & 0xFFFF, 0); // LDA #(MODULE_VAR_BASE + offset)
            codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);                     // STA $reg
            codegen_gen(sLDA, Immediate, (MODULE_VAR_BASE + x->a) >> 16, 0);    // LDA #(MODULE_VAR_BASE + offset)
            codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0);                 // STA $reg
        }
        x->r = RH;
        incR();
        incR();
    } else if (x->mode == ORB_Par) {
        // 65C816: Load address from VAR parameter (global variables only for now)
        // The stack contains the absolute address of the variable
        Set16(1, 1);
        codegen_gen(sLDA, StackRelative, x->a, 0);               // LDA param_offset,S (load address)
        codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);          // STA $reg
        codegen_gen(sLDA, StackRelative, x->a + 2, 0);           // LDA param_offset,S (load address)
        codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0);      // STA $reg
        if (x->b != 0) {
            // Add offset if present
            codegen_gen(sLDA, DirectPage, reg_addr(RH), 0);      // LDA $reg
            codegen_gen(sCLC, Implied, 0, 0);                    // CLC
            codegen_gen(sADC, Immediate, x->b, 0);               // ADC #offset  
            codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);      // STA $reg
        }
        x->r = RH;
        incR();
        incR();
    } else if (x->mode == RegI) {
        // 65C816: Add offset to register address
        if (x->a != 0) {
            Set16(1, 1);
            codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);       // LDA address
            codegen_gen(sCLC, Implied, 0, 0);                       // CLC
            codegen_gen(sADC, Immediate, x->a, 0);                  // ADC #offset
            codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);       // STA address
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
    // 65C816: Load string address = MODULE_VAR_BASE + ORG_varsize + x->a
    Set16(1, 1);  // 16-bit mode
    LONGINT string_addr = MODULE_VAR_BASE + ORG_varsize + x->a;
    codegen_gen(sLDA, Immediate, string_addr, 0);     // LDA #string_address
    codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);   // STA $reg
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
    
    if (strx + len < maxStrx) {
        while (len > 0) {
            str[strx] = ORS_str[i];
            strx++;
            i++;
            len--;
        }
        // Remove 4-byte alignment padding for strings
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
    } else if ((y->class == ORB_Const) && (y->type->form == ORB_Proc)) {
        x->r = y->lev;
        // x->b = y->expo ? 1 : 0;  // Store export flag for procedure calls
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
    // BOOLEAN original_rdo = x->rdo;  // Preserve the read-only flag
    s = x->type->base->size;
    lim = x->type->len;
    
    if ((y->mode == ORB_Const) && (lim >= 0)) {
        // Fixed array with constant index - do compile-time bounds check
        if ((y->a < 0) || (y->a >= lim)) {
            ORS_Mark("bad index");
        }
        if ((x->mode == ORB_Var) || (x->mode == RegI)) {
            x->a = y->a * s + x->a;
        } else if (x->mode == ORB_Par) {
            x->b = y->a * s + x->b;
        }
    } else {
        // Runtime indexing (non-constant index OR open array)
        load(y);
        if (check) {
            if (lim >= 0) {
                // 65C816: Compare index with array limit for fixed arrays
                Set16(1, 1);
                codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);    // LDA index
                codegen_gen(sCMP, Immediate, lim, 0);                // CMP #limit
				Trap(LT, 1);  // Branch if index >= length
            } else {
                if ((x->mode == ORB_Var) || (x->mode == ORB_Par)) {
                    // 65C816: Load array length from stack for open arrays and compare with index
					// We want to trap if index >= array_length  
					// Compare: index - array_length, trap if NOT(index < array_length)
                    Set16(1, 1);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);       // LDA index
					codegen_gen(sCMP, StackRelative, x->a + 4 + frame, 0);  // CMP length,S: index - array_length
                    Trap(LT, 1);  // Trap if NOT(index < array_length), i.e., if index >= array_length
                } else {
                    ORS_Mark("error in Index");
                }
            }
        }
        
        // 65C816: Multiply index by element size
		Set16(1, 1);
        if (s >= 4) {
            codegen_gen(sASL, DirectPage, reg_addr(y->r), 0);
		}
		if (s >= 2) {
		  codegen_gen(sASL, DirectPage, reg_addr(y->r), 0);  // ASL $reg (multiply by 2)
		}
        
        if (x->mode == ORB_Var) {
            if (x->r > 0) {
                // 65C816: Local array - add to stack pointer calculation
                x->a += frame;
            } else {
                // 65C816: Global array - compute absolute address directly
                // Load base address (MODULE_VAR_BASE + x->a) + scaled_index
                Set16(1, 1);
                codegen_gen(sLDA, Immediate, MODULE_VAR_BASE + x->a, 0);  // LDA #(base_addr)
                codegen_gen(sCLC, Implied, 0, 0);                         // CLC
                codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);         // ADC scaled_index
                codegen_gen(sSTA, DirectPage, reg_addr(y->r), 0);         // STA result
                x->a = 0;
            }
            x->r = y->r;
            x->mode = RegI;
        } else if (x->mode == ORB_Par) {
            // 65C816: Open array parameter - set up for both reading and writing
            // Keep the original 24-bit address handling but set correct mode
            // Load array base address into RH, RH+1
            Set16(1, 1);
            codegen_gen(sLDA, StackRelative, x->a + frame, 0);      // LDA base_addr_low,S
            codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);         // STA RH
			incR();
            codegen_gen(sLDA, StackRelative, x->a + 2 + frame, 0);  // LDA base_addr_high,S  
            codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);         // STA RH
            incR();
            
            // Add scaled index to base address (low word)
            Set16(1, 1);
            codegen_gen(sLDA, DirectPage, reg_addr(RH - 2), 0);     // LDA base_addr_low
            codegen_gen(sCLC, Implied, 0, 0);                       // CLC
            codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);       // ADC scaled_index
            codegen_gen(sSTA, DirectPage, reg_addr(y->r), 0);       // STA final_addr_low
            
            // Deallocate base address registers
            RH--;  // Deallocate the second address register (RH)
            RH--;  // Deallocate the first address register (RH-1)
            
            x->mode = RegI;    // Register indirect mode for both read/write
            x->r = y->r;       // Register containing element address
            x->a = x->b;       // Preserve original offset
        } else if (x->mode == RegI) {
            // 65C816: Add index offset to existing address
            Set16(1, 1);
            codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);       // LDA current_addr
            codegen_gen(sCLC, Implied, 0, 0);                       // CLC
            codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);       // ADC index_offset
            codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);       // STA result
            RH--;  // Deallocate y->r register
        }
    }
    
    // Restore the read-only flag - indexed elements inherit the read-only status of the array
    //x->rdo = original_rdo;
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
        // 65C816: Load value from address in register + offset (like RISC5: Put2(Ldr, x.r, x.r, x.a))
        if (x->a == 0) {
            // Simple case: LDA ($reg) - Direct Page Indirect
            codegen_gen(sLDA, DirectPageIndirect, reg_addr(x->r), 0);
        } else {
            // Complex case: LDA ($reg),Y with offset
            codegen_gen(sLDY, Immediate, x->a, 0);
            codegen_gen(sLDA, DirectPageIndirectIndexedY, reg_addr(x->r), 0);
        }
        codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);  // Store result back to same register
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
    emitBranch(negated(x->r), x->orig_type, Fixup, x->a);
    x->a = ORG_pc - 2;  // Save current branch location for FALSE chain (BRL offset field)
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
    emitBranch(x->r, x->orig_type, Fixup, x->b);
    x->b = ORG_pc - 2;  // Save current branch location for TRUE chain (BRL offset field)
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
	Set16(1, 1);
	if (x->mode == ORB_Const) {
	  x->a = -x->a;
	} else {
	  load(x);
	  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
	  codegen_gen(sEOR, Immediate, 0xffff, 0);
	  codegen_gen(sCLC, Implied, 0, 0);
	  codegen_gen(sADC, Immediate, 1, 0);
	  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
	}
  } else if (x->type->form == ORB_Real) {
	if (x->mode == ORB_Const) {
	  x->a = x->a + 0x7FFFFFFF + 1;
	} else {
	  load(x);
	}
  } else { // Set
	if (x->mode == ORB_Const) {
	  x->a = -x->a - 1;
	} else {
	  load(x);
	  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
	  codegen_gen(sEOR, Immediate, 0xffff, 0);
	  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
	}
  }
}

void ORG_AddOp(LONGINT op, ORG_Item *x, ORG_Item *y) {
    int reg_count = 0;
    
    if (op == ORS_plus) {
        if ((x->mode == ORB_Const) && (y->mode == ORB_Const)) {
            x->a = x->a + y->a;
        } else if (x->mode == ORB_Const) {
            // x is constant, y is register - swap operands and use immediate add
            if (x->a != 0) {
                // 65C816: Add immediate to register (y = y + x)
                if (y->type->form == ORB_Int && y->type->size == 2) {
                    Set16(1, 1);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);  // LDA $reg_y
                    codegen_gen(sCLC, Implied, 0, 0);                  // CLC
                    codegen_gen(sADC, Immediate, x->a, 0);             // ADC #constant
                    codegen_gen(sSTA, DirectPage, reg_addr(y->r), 0);  // STA $reg_y
                }
            }
            // Result is in y's register
            x->mode = y->mode;
            x->r = y->r;
        } else if (y->mode == ORB_Const) {
            reg_count += load(x);
            if (y->a != 0) {
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
            // 65C816: Add two registers
            if (x->type->form == ORB_Int && x->type->size == 2) {
			  Set16(1, 1);
			  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);  // LDA $reg_x
			  codegen_gen(sCLC, Implied, 0, 0);                  // CLC
			  codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);  // ADC $reg_y
			  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);  // STA $reg_x
            }
            RH -= (reg_count - 1);  // Keep one register for result, deallocate the rest
            // Result is already stored in x->r, don't change the register assignment
        }
    } else { // minus
        if ((x->mode == ORB_Const) && (y->mode == ORB_Const)) {
            x->a = x->a - y->a;
        } else if (y->mode == ORB_Const) {
            reg_count += load(x);
            if (y->a != 0) {
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
            // 65C816: Subtract two registers
            if (x->type->form == ORB_Int && x->type->size == 2) {
			  Set16(1, 1);
			  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);  // LDA $reg_x
			  codegen_gen(sSEC, Implied, 0, 0);                  // SEC
			  codegen_gen(sSBC, DirectPage, reg_addr(y->r), 0);  // SBC $reg_y
			  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);  // STA $reg_x
            }
            RH -= (reg_count - 1);  // Keep one register for result, deallocate the rest
            // Result is already stored in x->r, don't change the register assignment
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
		Set16(1, 1);
		codegen_gen(sLDX, Immediate, e, 0);
		codegen_gen(sASL, DirectPage, reg_addr(x->r), 0);
		codegen_gen(sDEX, Implied, 0, 0);
		codegen_gen(sBNE, ProgramCounterRelative, ORG_pc + 2 - 8, 0);  
    } else if (y->mode == ORB_Const) {
        load(x);
        load(y);
		Set16(1, 1);
		codegen_gen(sLDA, Immediate, 0, 0);               // Initialize result
		codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0); // MULT1: operand 1
		codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 11, 0);  // if operand 1 is zero, TO DONE
		codegen_gen(sLSR, DirectPage, reg_addr(x->r), 0); // get right bit, operand 1
		codegen_gen(sBCC, ProgramCounterRelative, ORG_pc + 2 + 3, 0);   // if clear, no addition to previous products
		codegen_gen(sCLC, Implied, 0, 0);                 // else add oprd 2 to partial result
		codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);
		codegen_gen(sASL, DirectPage, reg_addr(y->r), 0); // MCAND2: now shift oprd 2 left for poss add next time
		codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 - 15, 0);  // To MULT1
		codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0); // store result
        RH--;
        x->r = RH - 1;
    } else if ((x->mode == ORB_Const) && (x->a >= 2) && (ORG_log2(x->a, &e) == 1)) {
        load(y);
		Set16(1, 1);
		codegen_gen(sLDX, Immediate, e, 0);
		codegen_gen(sASL, DirectPage, reg_addr(y->r), 0);
		codegen_gen(sDEX, Implied, 0, 0);
		codegen_gen(sBNE, ProgramCounterRelative, ORG_pc + 2 - 8, 0);  
        x->mode = Reg;
        x->r = y->r;
    } else if (x->mode == ORB_Const) {
        load(x);
        load(y);
		Set16(1, 1);
		codegen_gen(sLDA, Immediate, 0, 0);               // Initialize result
		codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0); // MULT1: operand 1
		codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 11, 0);  // if operand 1 is zero, TO DONE
		codegen_gen(sLSR, DirectPage, reg_addr(x->r), 0); // get right bit, operand 1
		codegen_gen(sBCC, ProgramCounterRelative, ORG_pc + 2 + 3, 0);   // if clear, no addition to previous products
		codegen_gen(sCLC, Implied, 0, 0);                 // else add oprd 2 to partial result
		codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);
		codegen_gen(sASL, DirectPage, reg_addr(y->r), 0); // MCAND2: now shift oprd 2 left for poss add next time
		codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 - 15, 0);  // To MULT1
		codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0); // store result
        RH--;
        x->r = RH - 1;
    } else {
        load(x);
        load(y);
		Set16(1, 1);
		codegen_gen(sLDA, Immediate, 0, 0);               // Initialize result
		codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0); // MULT1: operand 1
		codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 11, 0);  // if operand 1 is zero, TO DONE
		codegen_gen(sLSR, DirectPage, reg_addr(x->r), 0); // get right bit, operand 1
		codegen_gen(sBCC, ProgramCounterRelative, ORG_pc + 2 + 3, 0);   // if clear, no addition to previous products
		codegen_gen(sCLC, Implied, 0, 0);                 // else add oprd 2 to partial result
		codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);
		codegen_gen(sASL, DirectPage, reg_addr(y->r), 0); // MCAND2: now shift oprd 2 left for poss add next time
		codegen_gen(sBRA, ProgramCounterRelative, ORG_pc + 2 - 15, 0);  // To MULT1
		codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0); // store result
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
			codegen_gen(sCMP, Immediate, 0x8000, 0); // Set carry if negative
			codegen_gen(sAND, Immediate, 0x7FFF, 0); // Clear the sign bit
			if (e > 1) {
			  codegen_gen(sPHP, Implied, 0, 0); // Save the carry
			  codegen_gen(sCLC, Implied, 0, 0); // Clear  the carry
			  codegen_gen(sROR, Implied, 0, 0); // Divide by two
			  if (e > 2) {
				codegen_gen(sROR, Implied, 0, 0); // Divide by two
			  }
			  if (e > 3) {
				codegen_gen(sROR, Implied, 0, 0); // Divide by two
			  }
			  codegen_gen(sPLP, Implied, 0, 0); // Restore the carry
			}
			codegen_gen(sROR, Implied, 0, 0); // Last divide by two restores the sign
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
		  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
		  codegen_gen(sORA, Immediate, y->a, 0);
		  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
        } else if (op == ORS_minus) {
		  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
		  codegen_gen(sORA, Immediate, ~y->a, 0);
		  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
        } else if (op == ORS_times) {
		  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
		  codegen_gen(sAND, Immediate, y->a, 0);
		  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
        } else if (op == ORS_rdiv) {
		  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
		  codegen_gen(sEOR, Immediate, y->a, 0);
		  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
        }
    } else {
        load(x);
        load(y);
        if (op == ORS_plus) {
		  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
		  codegen_gen(sORA, DirectPage, reg_addr(y->r), 0);
		  codegen_gen(sSTA, DirectPage, reg_addr(RH-2), 0);
        } else if (op == ORS_minus) {
		  codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);
		  codegen_gen(sEOR, Immediate, 0xFFFF, 0);
		  codegen_gen(sAND, DirectPage, reg_addr(x->r), 0);
		  codegen_gen(sSTA, DirectPage, reg_addr(RH-2), 0);
        } else if (op == ORS_times) {
		  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
		  codegen_gen(sAND, DirectPage, reg_addr(y->r), 0);
		  codegen_gen(sSTA, DirectPage, reg_addr(RH-2), 0);
        } else if (op == ORS_rdiv) {
		  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
		  codegen_gen(sEOR, DirectPage, reg_addr(y->r), 0);
		  codegen_gen(sSTA, DirectPage, reg_addr(RH-2), 0);
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
    BOOLEAN use_signed = !use_8bit && (x->type->form == ORB_Int);  // 16-bit integers need signed comparison
    
    // printf("DEBUG: ORG_IntRelation op=%d, x->type->form=%d, x->type->size=%d, y->type->form=%d, y->type->size=%d, use_8bit=%d, use_signed=%d\n", 
    //        op, x->type->form, x->type->size, y->type->form, y->type->size, use_8bit, use_signed);
    
    if (use_8bit) {
        Set8(1, 0);  // Switch to 8-bit accumulator mode
    }
    
    if ((y->mode == ORB_Const) && (y->type->form != ORB_Proc)) {
        load(x);
        if ((y->a != 0) || ((op != ORS_eql) && (op != ORS_neq))) {
            // 65C816: Compare with immediate value
            codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);  // LDA $reg_x
            
            if (use_signed && (op == ORS_lss || op == ORS_geq || op == ORS_leq || op == ORS_gtr)) {
                // For signed comparisons of 16-bit integers, use SBC instead of CMP
                codegen_gen(sSEC, Implied, 0, 0);               // SEC (set carry for subtraction)
                codegen_gen(sSBC, Immediate, y->a, 0);          // SBC #immediate
            } else {
                // For unsigned comparisons or EQ/NE, use CMP
                codegen_gen(sCMP, Immediate, y->a, 0);          // CMP #immediate
            }
        }
        RH--;
    } else {
        if ((x->mode == Cond) || (y->mode == Cond)) {
            ORS_Mark("not implemented");
        }
        load(x);
        load(y);
        // 65C816: Compare two registers
        codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);  // LDA $reg_x
        
        if (use_signed && (op == ORS_lss || op == ORS_geq || op == ORS_leq || op == ORS_gtr)) {
            // For signed comparisons of 16-bit integers, use SBC instead of CMP
            codegen_gen(sSEC, Implied, 0, 0);               // SEC (set carry for subtraction)
            codegen_gen(sSBC, DirectPage, reg_addr(y->r), 0);  // SBC $reg_y
        } else {
            // For unsigned comparisons or EQ/NE, use CMP
            codegen_gen(sCMP, DirectPage, reg_addr(y->r), 0);  // CMP $reg_y
        }
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
                    Set16(1, 0);
                } else if (x->type->size == 1 && y->type->size > 1) {
                    // INTEGER to BYTE store (truncate to low byte)
                    Set8(1, 0);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);     // LDA $reg
                    codegen_gen(sSTA, StackRelative, x->a, 0);            // STA x->a,S (8-bit)
                    Set16(1, 0);
                } else if (x->type->size > 1 && y->type->size == 1) {
                    // BYTE to INTEGER store (zero-extend)
                    Set16(1, 0);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);     // LDA $reg (already zero-extended from load)
                    codegen_gen(sSTA, StackRelative, x->a, 0);            // STA x->a,S (16-bit)
                    Set16(1, 0);
                } else {
                    // INTEGER to INTEGER store (no conversion needed)
				  Set16(1, 0);
				  codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);     // LDA $reg
				  codegen_gen(sSTA, StackRelative, x->a, 0);            // STA x->a,S (16-bit)
				  Set16(1, 0);
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
                    Set16(1, 0);
                } else if (x->type->size == 1 && y->type->size > 1) {
                    // INTEGER to BYTE store (truncate to low byte)
                    Set8(1, 0);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);        // LDA $reg
                    codegen_gen(sSTA, Absolute, MODULE_VAR_BASE + x->a, 0);  // STA $1000+offset (8-bit)
                    Set16(1, 0);
                } else if (x->type->size > 1 && y->type->size == 1) {
                    // BYTE to INTEGER store (zero-extend)
                    Set8(1, 0);
                    codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);        // LDA $reg (already zero-extended from load)
                    codegen_gen(sSTA, Absolute, MODULE_VAR_BASE + x->a, 0);  // STA $1000+offset (16-bit)
                    Set16(1, 0);
                } else {
                    // INTEGER to INTEGER store (no conversion needed)
				  Set16(1, 1);
				  codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);        // LDA $reg
				  codegen_gen(sSTA, Absolute, MODULE_VAR_BASE + x->a, 0);  // STA $1000+offset (16-bit)
				  Set16(1, 0);
                }
            }
        }
    } else if (x->mode == ORB_Par) {
        // 65C816: Store to VAR parameter - load the 4-byte pointer into registers,
        // then store through the pointer using DirectPageIndirectLong
        
        if (y->mode == Reg) {
            // Load the 4-byte pointer from stack into two registers
            Set16(1, 1);
            // Store long pointer
            codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);   
            codegen_gen(sSTA, StackRelative, x->a, 0);
            codegen_gen(sLDA, DirectPage, reg_addr(y->r + 1), 0);   
            codegen_gen(sSTA, StackRelative, x->a + 2, 0);

			// If it is an array, store the size as well
			if (x->type->form == ORB_Array) {
			  codegen_gen(sLDA, DirectPage, reg_addr(y->r + 2), 0);   
			  codegen_gen(sSTA, StackRelative, x->a + 4, 0);
			}

			/*
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
			*/
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
				Set16(1, 0);
            } else if (x->type->size == 1 && y->type->size > 1) {
                // INTEGER to BYTE store (truncate to low byte)
                Set8(1, 0);
                codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);  // LDA $reg
                codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0);  // LDX $x->r (address)
                codegen_gen(sSTA, AbsoluteIndexedX, x->a, 0);      // STA x->a,X (8-bit)
				Set16(1, 0);
            } else if (x->type->size > 1 && y->type->size == 1) {
                // BYTE to INTEGER store (zero-extend)
                Set16(1, 1);
                codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);  // LDA $reg (already zero-extended from load)
                codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0);  // LDX $x->r (address)
                codegen_gen(sSTA, AbsoluteIndexedX, x->a, 0);      // STA x->a,X (16-bit)
				Set16(1, 0);
            } else {
                // INTEGER to INTEGER store (no conversion needed)
                Set16(1, 1);
                codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);  // LDA $reg
                codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0);  // LDX $x->r (address)
                codegen_gen(sSTA, AbsoluteIndexedX, x->a, 0);      // STA x->a,X (16-bit)
				Set16(1, 0);
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
	  // ToDo:
    // RISC: Put2(Ldr, RH, SP, x->a + 4);
    // RISC: Put1(Cmp, RH, RH, y->b);
        Trap(LT, 3);
    }
    
    loadStringAdr(y);  // Load source string address
    
    // 65C816 string copy implementation using loop with Y as index counter
    // Simpler approach: use Y as index, load addresses into other registers
    
    Set8(1, 0);   // 8-bit accumulator for byte operations
    Set16(0, 1);  // 16-bit index registers
    
    // Initialize Y register to 0 (index counter)
    codegen_gen(sLDY, Immediate, 0, 0);  // LDY #0
    
    // Mark loop start for branch target
    LONGINT loop_start = ORG_pc;
    
    // Load byte from source[Y] using indirect indexed addressing
    codegen_gen(sLDA, DirectPageIndirectIndexedY, reg_addr(y->r), 0);  // LDA (src_ptr),Y
    
    // Store byte to destination[Y] using indirect indexed addressing  
    codegen_gen(sSTA, DirectPageIndirectIndexedY, reg_addr(x->r), 0);  // STA (dst_ptr),Y
    
    // Test for null terminator (zero)  
    // BEQ needs to skip: STA (2 bytes) + INY (1 byte) + BRA (2 bytes) = 5 bytes
    codegen_gen(sBEQ, ProgramCounterRelative, ORG_pc + 2 + 3, 0);  // BEQ to exit (skip increment)
    
    // Increment Y (index counter)
    codegen_gen(sINY, Implied, 0, 0);                      // INY
    
    // Branch back to loop start
    codegen_gen(sBRA, ProgramCounterRelative, loop_start, 0);  // BRA loop_start
    
    // Exit point - null terminator already stored by loop condition (no extra store needed)
    
    RH -= 3;      // Clean up: loadAdr(x) +2, loadStringAdr(y) +1, total 3 registers used
}

// Parameter operations
void ORG_OpenArrayParam(ORG_Item *x) {
    loadAdr(x);
    // Note: loadAdr increments RH by 2, so x->r points to the first register (address)
    // and x->r + 1 contains the bank byte (0). We need to store the length in the next register.
    
    if (x->type->len >= 0) {
        // 65C816: Load array length for fixed arrays passed to open array parameters
        Set16(1, 1);
        codegen_gen(sLDA, Immediate, x->type->len, 0);        // LDA #array_length
        codegen_gen(sSTA, DirectPage, reg_addr(x->r + 2), 0); // STA $reg+2 (next available register)
    } else {
        // 65C816: Load array length for open arrays passed to open array parameters
        // Load the length from the stack frame (x->a + 2 + frame)
        Set16(1, 1);
        codegen_gen(sLDA, StackRelative, x->a + 2 + frame, 0);  // LDA x->a + 2 + frame,S
        codegen_gen(sSTA, DirectPage, reg_addr(x->r + 2), 0);   // STA $reg+2 (next available register)
    }
    incR(); // Allocate the length register
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
        // VAR open arrays: use same layout as ORG_OpenArrayParam
        if (x->type->len >= 0) {
            // 65C816: Load array length for fixed arrays passed to VAR open array parameters
            Set16(1, 1);
            codegen_gen(sLDA, Immediate, x->type->len, 0);        // LDA #array_length
            codegen_gen(sSTA, DirectPage, reg_addr(x->r + 2), 0); // STA $reg+2 (same as ORG_OpenArrayParam)
        } else {
            // 65C816: Load array length for open arrays passed to VAR open array parameters
            // Load the length from the stack frame at offset +4 (length is at $05,S in the parameter layout)
            Set16(1, 1);
            codegen_gen(sLDA, StackRelative, x->a + 4 + frame, 0);  // LDA x->a + 4 + frame,S
            codegen_gen(sSTA, DirectPage, reg_addr(x->r + 2), 0);   // STA $reg+2 (same as ORG_OpenArrayParam)
        }
        incR(); // Allocate the length register
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
    // Load 4-byte string address like loadAdr for global string constants
    Set16(1, 1);
    LONGINT string_addr = MODULE_VAR_BASE + ORG_varsize + x->a;
    
    // Load lower 16 bits of address into RH
    codegen_gen(sLDA, Immediate, string_addr & 0xFFFF, 0);     // LDA #string_address_low
    codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);            // STA $reg
    
    // Load upper 16 bits of address into RH+1 
    codegen_gen(sLDA, Immediate, (string_addr >> 16) & 0xFFFF, 0);  // LDA #string_address_high
    codegen_gen(sSTA, DirectPage, reg_addr(RH + 1), 0);             // STA $reg+1
    
    x->mode = Reg;
    x->r = RH;
    incR(); // Allocate address register (low)
    incR(); // Allocate address register (high)
    
    // Load string length into next register (RH+2)
    Set16(1, 1);
    codegen_gen(sLDA, Immediate, x->b, 0);                     // LDA #string_length
    codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);            // STA $reg+2
    incR(); // Allocate length register
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
	Set16(1, 0);

    // Generate conditional branch based on increment direction
    if (w->a > 0) {
        // Positive increment: branch if greater than limit (exit loop)
        emitBranch(GT, y->type, Fixup, 0);  // Forward branch, will be fixed up later
    } else if (w->a < 0) {
        // Negative increment: branch if less than limit (exit loop)
        emitBranch(LT, y->type, Fixup, 0);  // Forward branch, will be fixed up later
    } else {
        ORS_Mark("zero increment");
        emitBranch(MI, y->type, Fixup, 0);  // This shouldn't happen, but handle error case
    }
    
    *L = ORG_pc - 2;  // Save location of branch for later fixup (BRL offset field)
    
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
    emitBranch(AL, intType, Fixup, *L);  // Unconditional forward branch (condition 7 = always)
    *L = ORG_pc - 2;    // Save location for later fixup (BRL offset field)
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
    
	emitBranch(negated(x->r), x->orig_type, Fixup, x->a);
	ORG_FixLink(x->b);  // Fix up TRUE branches
	x->a = ORG_pc - 2;  // Save location for FALSE branch fixup (BRL offset field)
}

void ORG_BJump(LONGINT L) {
  codegen_gen(sBRA, ProgramCounterRelative, L, 0);
}

void ORG_CBJump(ORG_Item *x, LONGINT L) {
    if (x->mode != Cond) {
        loadCond(x);
    }
    // Generate branch with negated condition (for backward jump on FALSE)
    emitBranch(negated(x->r), x->orig_type, ProgramCounterRelative, L);
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
  Set16(1, 1); // Always in long mode when entering a procedure
  if (x->mode == ORB_Const) {
	if ((x->r >= 0) && (x->b == 0)) {
	  // 65C816: Local procedure - JSR to procedure address
	  codegen_gen(sJSR, Absolute, x->a, 0);  // JSR procedure_address
	} else {
	  // 65C816: Imported procedure (x->r < 0) or exported procedure (x->b == 1) - JSL
	  codegen_gen(sJSL, Absolute, x->a, 0);  // JSL procedure_address
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

void ORG_Enter(ORB_Object *params, LONGINT frame_size, BOOLEAN int_proc) {
  LONGINT a, r;
  ORB_Object *param;
  
  if (!int_proc) {
	if (frame_size >= 0x4000) {
	  ORS_Mark("too many locals");
	}
	
	if (frame_size > 0) {
	  // Allocate stack space for parameters and locals
	  Set16(1, 1);
	  codegen_gen(sTSC, Implied, 0, 0);                        // TSC (Transfer Stack to A)
	  codegen_gen(sSEC, Implied, 0, 0);                        // SEC
	  codegen_gen(sSBC, Immediate, frame_size, 0);       // SBC #total_frame_size
	  codegen_gen(sTCS, Implied, 0, 0);                        // TCS (Transfer A to Stack)
	}
	
	a = 4;
	r = 0;
        
	// 65C816: Store register parameters to their stack locations using actual parameter types
	r = 0;  // Start with register 0
	param = params;  // Start with first parameter

	Set16(1, 1);
	while (param != NULL && (param->class == ORB_Var || param->class == ORB_Par)) {
	  // For VAR parameters (ORB_Par with rdo=FALSE), we need to store the pointer value itself 
	  // to the stack frame, not store through the pointer
	  if (param->class == ORB_Par && !param->rdo && param->type->form == ORB_Array && param->type->len < 0) {
	    // Open array parameter: Store both array address and length
	    // First register contains array address, second register contains array length
	    
	    // Store the array address from first two registers  
	    codegen_gen(sLDA, DirectPage, reg_addr(r + 0), 0);     // LDA $reg (load address low)
	    codegen_gen(sSTA, StackRelative, param->val, 0);       // STA param->val,S (store address low)
	    codegen_gen(sLDA, DirectPage, reg_addr(r + 1), 0);     // LDA $reg+1 (load address high)  
	    codegen_gen(sSTA, StackRelative, param->val + 2, 0);   // STA param->val+1,S (store address high)
	    
	    // Store the array length from third register  
	    codegen_gen(sLDA, DirectPage, reg_addr(r + 2), 0);     // LDA $reg+2 (load array length)
	    codegen_gen(sSTA, StackRelative, param->val + 4, 0);   // STA param->val+4,S (store length)
	    
	    // Result on stack: [addr_low] [addr_high] [data_bank] [padding] [len_low] [len_high] = 6-byte VAR open array
	  } else if (param->class == ORB_Par && !param->rdo) {
	    // VAR parameter: Store 4-byte pointer value to stack using two registers
	    // First register contains 16-bit address, second register contains data bank (0)
	    
	    // Store the 16-bit address from first register
	    codegen_gen(sLDA, DirectPage, reg_addr(r + 0), 0);     // LDA $reg (load 16-bit address)
	    codegen_gen(sSTA, StackRelative, param->val, 0);       // STA param->val,S (store address)
	    
	    // Store the data bank and high byte from second register
	    codegen_gen(sLDA, DirectPage, reg_addr(r + 1), 0);     // LDA $reg+1 (load data bank)
	    codegen_gen(sSTA, StackRelative, param->val + 2, 0);   // STA param->val+2,S (store data bank)
	    
	    // Result on stack: [addr_low] [addr_high] [data_bank] [padding] = 4-byte pointer
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
	  
	  // Advance register pointer based on parameter type
	  if (param->class == ORB_Par && !param->rdo) {
	    r += 2;  // VAR parameter uses two registers (address + data bank)
	  } else if (param->class == ORB_Par && !param->rdo && param->type->form == ORB_Array && param->type->len < 0) {
	    r += 3;  // Open array parameter uses three registers (addr_low + addr_high + length)
	  } else {
	    r++;     // Regular parameter uses one register
	  }
	  param = param->next;
	}
	
	// Reset register stack - parameters are now stored on stack, registers are free
	RH = 0;
  } else {
	// Interrupt procedure - allocate full stack frame
	if (frame_size > 0) {
	  codegen_gen(sSEC, Implied, 0, 0);           // SEC
	  codegen_gen(sSBC, Immediate, frame_size, 0); // SBC #locblksize
	  codegen_gen(sTCS, Implied, 0, 0);           // TCS (Transfer A to Stack)
	}
  }
}

void ORG_Return(INTEGER form, ORG_Item *x, LONGINT size, BOOLEAN expo, BOOLEAN int_proc) {
  if (form != ORB_NoTyp) {
	load(x);
  }
  
  if (!int_proc) {
	Set16(1, 1);
	// 65C816: Simple stack frame deallocation 
	if (size > 0) {
	  codegen_gen(sTSC, Implied, 0, 0);           // TSC (Transfer Stack to A)
	  codegen_gen(sCLC, Implied, 0, 0);           // CLC
	  codegen_gen(sADC, Immediate, size, 0);     // ADC #size (deallocate frame)
	  codegen_gen(sTCS, Implied, 0, 0);           // TCS (Transfer A to Stack)
	}
	// 65C816: RTS to return from subroutine
	if (expo) {
	  codegen_gen(sRTL, Implied, 0, 0);  // RTL
	} else {
	  codegen_gen(sRTS, Implied, 0, 0);  // RTS
	}
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
    // Follow the RISC implementation exactly but adapt to 65C816
    BOOLEAN is_byte = (x->type == byteType);
    BOOLEAN is_increment = (upordown == 0);
    LONGINT zr;
    
    // Default y to 1 if no type specified
    if (y->type->form == ORB_NoTyp) {
        y->mode = ORB_Const;
        y->a = 1;
    }
    
    // Check if we can optimize to INC/DEC (increment/decrement by 1)
    BOOLEAN can_use_inc_dec = (y->mode == ORB_Const) && (y->a == 1);
    
    if ((x->mode == ORB_Var) && (x->r > 0)) {
        // Local variable case: RISC: zr := RH; Put2(Ldr+v, zr, SP, x->a); incR;
        zr = RH;
        if (is_byte) Set8(1, 0); else Set16(1, 1);
        
        // Load from stack to register: LDA x,S -> STA $zr  
        codegen_gen(sLDA, StackRelative, x->a, 0);
        codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);
        incR();
        
        // Perform operation
        if (y->mode == ORB_Const) {
            if (can_use_inc_dec) {
                // Use INC/DEC instructions
                codegen_gen(sLDA, DirectPage, reg_addr(zr), 0);
                if (is_increment) {
                    codegen_gen(sINC, Accumulator, 0, 0);
                } else {
                    codegen_gen(sDEC, Accumulator, 0, 0);
                }
                codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);
            } else {
                // Use ADC/SBC instructions
                codegen_gen(sLDA, DirectPage, reg_addr(zr), 0);
                if (is_increment) {
                    codegen_gen(sADC, Immediate, y->a, 0);
                } else {
                    codegen_gen(sSBC, Immediate, y->a, 0);
                }
                codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);
            }
        } else {
            load(y);
            codegen_gen(sLDA, DirectPage, reg_addr(zr), 0);
            if (is_increment) {
                codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);
            } else {
                codegen_gen(sSBC, DirectPage, reg_addr(y->r), 0);
            }
            codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);
            RH--;
        }
        
        // Store back to stack: RISC: Put2(Str+v, zr, SP, x->a);
        codegen_gen(sLDA, DirectPage, reg_addr(zr), 0);
        codegen_gen(sSTA, StackRelative, x->a, 0);
        
        if (is_byte) Set16(1, 1);  // Restore 16-bit mode
        RH--;  // RISC: DEC(RH)
        
    } else {
        // Global variable case: RISC: loadAdr(x); zr := RH; Put2(Ldr+v, RH, x->r, 0); incR;
        loadAdr(x);    // After this: RH=2, x->r=0 (address in registers 0,1)
        zr = RH;       // zr = 2 (next available register)
        if (is_byte) Set8(1, 0); else Set16(1, 1);
        
        // Load value from address into register zr
        codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0);      // LDX $address_low (reg 0)
        codegen_gen(sLDA, AbsoluteIndexedX, 0, 0);             // LDA $0000,X
        codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);        // STA $zr (reg 2)
        incR();        // RH = 3
        
        // Perform operation on register zr
        if (y->mode == ORB_Const) {
            // RISC: Put1a(op, zr, zr, y->a);
            if (can_use_inc_dec) {
                // Use INC/DEC instructions  
                codegen_gen(sLDA, DirectPage, reg_addr(zr), 0);
                if (is_increment) {
                    codegen_gen(sINC, Accumulator, 0, 0);
                } else {
                    codegen_gen(sDEC, Accumulator, 0, 0);
                }
                codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);
            } else {
                // Use ADC/SBC instructions
                codegen_gen(sLDA, DirectPage, reg_addr(zr), 0);
                if (is_increment) {
                    codegen_gen(sADC, Immediate, y->a, 0);
                } else {
                    codegen_gen(sSBC, Immediate, y->a, 0);
                }
                codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);
            }
        } else {
            load(y);
            // RISC: Put0(op, zr, zr, y->r);
            codegen_gen(sLDA, DirectPage, reg_addr(zr), 0);
            if (is_increment) {
                codegen_gen(sADC, DirectPage, reg_addr(y->r), 0);
            } else {
                codegen_gen(sSBC, DirectPage, reg_addr(y->r), 0);
            }
            codegen_gen(sSTA, DirectPage, reg_addr(zr), 0);
            RH--;
        }
        
        // Store back to address: RISC: Put2(Str+v, zr, x->r, 0);
        codegen_gen(sLDX, DirectPage, reg_addr(x->r), 0);      // LDX $address_low (reg 0)  
        codegen_gen(sLDA, DirectPage, reg_addr(zr), 0);        // LDA $zr (reg 2)
        codegen_gen(sSTA, AbsoluteIndexedX, 0, 0);             // STA $0000,X
        
        if (is_byte) Set16(1, 1);  // Restore 16-bit mode
        
        // Clean up registers: RISC: DEC(RH, 2)
        // We had: loadAdr incremented RH by 2 (0->2), then we incremented by 1 (2->3)
        // So we need to decrement by 3 to get back to 0
        RH -= 3;
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
  Trap(AL, 10);
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

void ORG_IntEn(ORG_Item *x) {
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
  // ToDo: Support long addressing
  load(x);
  load(y);
  codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0); 
  Set8(1, 0);
  codegen_gen(sSTA, DirectPageIndirect, reg_addr(x->r), 0);
  Set16(1, 0);
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

void ORG_TRB(ORG_Item *x, ORG_Item *y) {
}

void ORG_TSB(ORG_Item *x, ORG_Item *y) {
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

/*
    IF x.type.len >= 0 THEN
      IF x.mode = RegI THEN DEC(RH) END ;
      x.mode := ORB.Const; x.a := x.type.len
    ELSE (*open array*) Put2(Ldr, RH, SP, x.a + 4 + frame); x.mode := Reg; x.r := RH; incR
 */

void ORG_Len(ORG_Item *x) {
  if (x->type->len >= 0) {
	if (x->mode == RegI) {
	  RH--;
	}
	x->mode = ORB_Const;
	x->a = x->type->len;
  } else { // Open array (must be local)
	// For 65C816: Length is always at parameter base + 4
	// For first parameter: x->a=3, so length is at 3+4=7
	Set16(1, 1);
	codegen_gen(sLDA, StackRelative, x->a + 4 + frame, 0);  // LDA length,S
	codegen_gen(sSTA, DirectPage, reg_addr(RH), 0);         // STA $reg (store length to register)
	x->mode = Reg;
	x->r = RH;
	incR();
  }
}

void ORG_Shift(LONGINT fct, ORG_Item *x, ORG_Item *y) {
  LONGINT op = sAND;
  
  load(x);
  switch (fct) {
  case 0: op = sASL; break;
  case 1: op = sLSR; break;
  case 2: op = sROL; break;
  }
  
  if (y->mode == ORB_Const) {
	if (y->a == 1) {
	  codegen_gen(op, DirectPage, reg_addr(x->r), 0);
	} else {
	  codegen_gen(sLDA, DirectPage, reg_addr(x->r), 0);
	  for (int i = 0; i < y->a; i++) {
		codegen_gen(op, Implied, 0, 0);
	  }
	  codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0);
	}
  } else {
	// Not implement yet
	printf("non-const shift not implemented\n");
	//load(y);
	//codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);
	//codegen_gen(op, DirectPage, reg_addr(x->r), 0);
	//codegen_gen(sSTA, DirectPage, reg_addr(RH-2), 0); 
	//RH--;
	//x->r = RH - 1;
  }
}

void ORG_Bitwise(LONGINT fct, ORG_Item *x, ORG_Item *y) {
  LONGINT op = sAND;

  load(x);
  switch (fct) {
  case 0: op = sAND; break;
  case 1: op = sEOR; break;
  case 2: op = sORA; break;
  }
  
  if (y->mode == ORB_Const) {
	codegen_gen(sLDA, Immediate, y->a % 0xffff, 0);
	codegen_gen(op, DirectPage, reg_addr(x->r), 0);
	codegen_gen(sSTA, DirectPage, reg_addr(x->r), 0); 
  } else {
	load(y);
	codegen_gen(sLDA, DirectPage, reg_addr(y->r), 0);
	codegen_gen(op, DirectPage, reg_addr(x->r), 0);
	codegen_gen(sSTA, DirectPage, reg_addr(RH-2), 0); 
	RH--;
	x->r = RH - 1;
  }
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
  // 65C816: Return to system - emulator calls main with JSL so return with RTL
  codegen_gen(sRTL, Implied, 0, 0);
  
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
