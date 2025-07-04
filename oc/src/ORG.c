// ORG.c - Code generator for Oberon compiler for RISC processor
// Translated from ORG.Mod by N.Wirth

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ORG.h"
#include "ORS.h"
#include "ORB.h"
#include "Files.h"

// Constants
#define WordSize 4
#define StkOrg0 (-64)
#define VarOrg0 0
#define MT 12
#define SP 14
#define LNK 15
#define maxCode 8000
#define maxStrx 2400
#define maxTD 160
#define C24 0x1000000

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

// Condition codes
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
static LONGINT code[maxCode];
static LONGINT data[maxTD];
static char str[maxStrx];

// Forward declarations
static void load(ORG_Item *x);
static void loadAdr(ORG_Item *x);
static void GetSB(LONGINT base);
static LONGINT ORG_log2(LONGINT m, LONGINT *e);

// Instruction assemblers
static void Put0(LONGINT op, LONGINT a, LONGINT b, LONGINT c) {
    code[ORG_pc] = ((a * 0x10 + b) * 0x10 + op) * 0x10000 + c;
    ORG_pc++;
}

static void Put1(LONGINT op, LONGINT a, LONGINT b, LONGINT im) {
    if (im < 0) op += V;
    code[ORG_pc] = (((a + 0x40) * 0x10 + b) * 0x10 + op) * 0x10000 + (im % 0x10000);
    ORG_pc++;
}

static void Put1a(LONGINT op, LONGINT a, LONGINT b, LONGINT im) {
    if ((im >= -0x10000) && (im <= 0xFFFF)) {
        Put1(op, a, b, im);
    } else {
        Put1(Mov + U, RH, 0, im / 0x10000);
        if (im % 0x10000 != 0) {
            Put1(Ior, RH, RH, im % 0x10000);
        }
        Put0(op, a, b, RH);
    }
}

static void Put2(LONGINT op, LONGINT a, LONGINT b, LONGINT off) {
    code[ORG_pc] = ((op * 0x10 + a) * 0x10 + b) * 0x100000 + (off % 0x100000);
    ORG_pc++;
}

static void Put3(LONGINT op, LONGINT cond, LONGINT off) {
    code[ORG_pc] = ((op + 12) * 0x10 + cond) * 0x1000000 + (off % 0x1000000);
    ORG_pc++;
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
    Put3(BLR, cond, ORS_Pos() * 0x100 + num * 0x10 + MT);
}

static LONGINT negated(LONGINT cond) {
    if (cond < 8) {
        cond = cond + 8;
    } else {
        cond = cond - 8;
    }
    return cond;
}

static void fix(LONGINT at, LONGINT with) {
    code[at] = code[at] / C24 * C24 + (with % C24);
}

void ORG_FixOne(LONGINT at) {
    fix(at, ORG_pc - at - 1);
}

void ORG_FixLink(LONGINT L) {
    LONGINT L1;
    while (L != 0) {
        L1 = code[L] % 0x40000;
        fix(L, ORG_pc - L - 1);
        L = L1;
    }
}

static void FixLinkWith(LONGINT L0, LONGINT dst) {
    LONGINT L1;
    while (L0 != 0) {
        L1 = code[L0] % C24;
        code[L0] = code[L0] / C24 * C24 + ((dst - L0 - 1) % C24);
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
        Put1(Mov, RH, 0, VarOrg0);
    } else {
        Put2(Ldr, RH, -base, ORG_pc - fixorgD);
        fixorgD = ORG_pc - 1;
    }
}

static void NilCheck(void) {
    if (check) {
        Trap(EQ, 4);
    }
}

static void load(ORG_Item *x) {
    LONGINT op;
    
    if (x->type->size == 1) {
        op = Ldr + 1;
    } else {
        op = Ldr;
    }
    
    if (x->mode != Reg) {
        if (x->mode == ORB_Const) {
            if (x->type->form == ORB_Proc) {
                if (x->r > 0) {
                    ORS_Mark("not allowed");
                } else if (x->r == 0) {
                    Put3(BL, 7, 0);
                    Put1a(Sub, RH, LNK, ORG_pc * 4 - x->a);
                } else {
                    GetSB(x->r);
                    Put1(Add, RH, RH, x->a + 0x100);
                }
            } else if ((x->a <= 0xFFFF) && (x->a >= -0x10000)) {
                Put1(Mov, RH, 0, x->a);
            } else {
                Put1(Mov + U, RH, 0, (x->a / 0x10000) % 0x10000);
                if (x->a % 0x10000 != 0) {
                    Put1(Ior, RH, RH, x->a % 0x10000);
                }
            }
            x->r = RH;
            incR();
        } else if (x->mode == ORB_Var) {
            if (x->r > 0) {
                Put2(op, RH, SP, x->a + frame);
            } else {
                GetSB(x->r);
                Put2(op, RH, RH, x->a);
            }
            x->r = RH;
            incR();
        } else if (x->mode == ORB_Par) {
            Put2(Ldr, RH, SP, x->a + frame);
            Put2(op, RH, RH, x->b);
            x->r = RH;
            incR();
        } else if (x->mode == RegI) {
            Put2(op, x->r, x->r, x->a);
        } else if (x->mode == Cond) {
            Put3(BC, negated(x->r), 2);
            ORG_FixLink(x->b);
            Put1(Mov, RH, 0, 1);
            Put3(BC, 7, 1);
            ORG_FixLink(x->a);
            Put1(Mov, RH, 0, 0);
            x->r = RH;
            incR();
        }
        x->mode = Reg;
    }
}

static void loadAdr(ORG_Item *x) {
    if (x->mode == ORB_Var) {
        if (x->r > 0) {
            Put1a(Add, RH, SP, x->a + frame);
        } else {
            GetSB(x->r);
            Put1a(Add, RH, RH, x->a);
        }
        x->r = RH;
        incR();
    } else if (x->mode == ORB_Par) {
        Put2(Ldr, RH, SP, x->a + frame);
        if (x->b != 0) {
            Put1a(Add, RH, RH, x->b);
        }
        x->r = RH;
        incR();
    } else if (x->mode == RegI) {
        if (x->a != 0) {
            Put1a(Add, x->r, x->r, x->a);
        }
    } else {
        ORS_Mark("address error");
    }
    x->mode = Reg;
}

static void loadCond(ORG_Item *x) {
    if (x->type->form == ORB_Bool) {
        if (x->mode == ORB_Const) {
            x->r = 15 - x->a * 8;
        } else {
            load(x);
            if (code[ORG_pc - 1] / 0x40000000 != -2) {
                Put1(Cmp, x->r, x->r, 0);
            }
            x->r = NE;
            RH--;
        }
        x->mode = Cond;
        x->a = 0;
        x->b = 0;
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
    Put1a(Add, RH, RH, ORG_varsize + x->a);
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
                Put1a(Cmp, RH, y->r, lim);
            } else {
                if ((x->mode == ORB_Var) || (x->mode == ORB_Par)) {
                    Put2(Ldr, RH, SP, x->a + 4 + frame);
                    Put0(Cmp, RH, y->r, RH);
                } else {
                    ORS_Mark("error in Index");
                }
            }
            Trap(10, 1);
        }
        
        if (s == 4) {
            Put1(Lsl, y->r, y->r, 2);
        } else if (s > 1) {
            Put1a(Mul, y->r, y->r, s);
        }
        
        if (x->mode == ORB_Var) {
            if (x->r > 0) {
                Put0(Add, y->r, SP, y->r);
                x->a += frame;
            } else {
                GetSB(x->r);
                if (x->r == 0) {
                    Put0(Add, y->r, RH, y->r);
                } else {
                    Put1a(Add, RH, RH, x->a);
                    Put0(Add, y->r, RH, y->r);
                    x->a = 0;
                }
            }
            x->r = y->r;
            x->mode = RegI;
        } else if (x->mode == ORB_Par) {
            Put2(Ldr, RH, SP, x->a + frame);
            Put0(Add, y->r, RH, y->r);
            x->mode = RegI;
            x->r = y->r;
            x->a = x->b;
        } else if (x->mode == RegI) {
            Put0(Add, x->r, x->r, y->r);
            RH--;
        }
    }
}

void ORG_DeRef(ORG_Item *x) {
    if (x->mode == ORB_Var) {
        if (x->r > 0) {
            Put2(Ldr, RH, SP, x->a + frame);
        } else {
            GetSB(x->r);
            Put2(Ldr, RH, RH, x->a);
        }
        NilCheck();
        x->r = RH;
        incR();
    } else if (x->mode == ORB_Par) {
        Put2(Ldr, RH, SP, x->a + frame);
        Put2(Ldr, RH, RH, x->b);
        NilCheck();
        x->r = RH;
        incR();
    } else if (x->mode == RegI) {
        Put2(Ldr, x->r, x->r, x->a);
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
            Put2(Ldr, RH, SP, x->a + 4 + frame);
        } else {
            load(x);
            pc0 = ORG_pc;
            Put3(BC, EQ, 0);
            Put2(Ldr, RH, x->r, -8);
        }
        Put2(Ldr, RH, RH, T->nofpar * 4);
        incR();
        loadTypTagAdr(T);
        Put0(Cmp, RH - 1, RH - 1, RH - 2);
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
    if (x->mode != Cond) {
        loadCond(x);
    }
    x->r = negated(x->r);
    t = x->a;
    x->a = x->b;
    x->b = t;
}

void ORG_And1(ORG_Item *x) {
    if (x->mode != Cond) {
        loadCond(x);
    }
    Put3(BC, negated(x->r), x->a);
    x->a = ORG_pc - 1;
    ORG_FixLink(x->b);
    x->b = 0;
}

void ORG_And2(ORG_Item *x, ORG_Item *y) {
    if (y->mode != Cond) {
        loadCond(y);
    }
    x->a = merged(y->a, x->a);
    x->b = y->b;
    x->r = y->r;
}

void ORG_Or1(ORG_Item *x) {
    if (x->mode != Cond) {
        loadCond(x);
    }
    Put3(BC, x->r, x->b);
    x->b = ORG_pc - 1;
    ORG_FixLink(x->a);
    x->a = 0;
}

void ORG_Or2(ORG_Item *x, ORG_Item *y) {
    if (y->mode != Cond) {
        loadCond(y);
    }
    x->a = y->a;
    x->b = merged(y->b, x->b);
    x->r = y->r;
}

// Arithmetic operators
void ORG_Neg(ORG_Item *x) {
    if (x->type->form == ORB_Int) {
        if (x->mode == ORB_Const) {
            x->a = -x->a;
        } else {
            load(x);
            Put1(Mov, RH, 0, 0);
            Put0(Sub, x->r, RH, x->r);
        }
    } else if (x->type->form == ORB_Real) {
        if (x->mode == ORB_Const) {
            x->a = x->a + 0x7FFFFFFF + 1;
        } else {
            load(x);
            Put1(Mov, RH, 0, 0);
            Put0(Fsb, x->r, RH, x->r);
        }
    } else { // Set
        if (x->mode == ORB_Const) {
            x->a = -x->a - 1;
        } else {
            load(x);
            Put1(Xor, x->r, x->r, -1);
        }
    }
}

void ORG_AddOp(LONGINT op, ORG_Item *x, ORG_Item *y) {
    if (op == ORS_plus) {
        if ((x->mode == ORB_Const) && (y->mode == ORB_Const)) {
            x->a = x->a + y->a;
        } else if (y->mode == ORB_Const) {
            load(x);
            if (y->a != 0) {
                Put1a(Add, x->r, x->r, y->a);
            }
        } else {
            load(x);
            load(y);
            Put0(Add, RH - 2, x->r, y->r);
            RH--;
            x->r = RH - 1;
        }
    } else { // minus
        if ((x->mode == ORB_Const) && (y->mode == ORB_Const)) {
            x->a = x->a - y->a;
        } else if (y->mode == ORB_Const) {
            load(x);
            if (y->a != 0) {
                Put1a(Sub, x->r, x->r, y->a);
            }
        } else {
            load(x);
            load(y);
            Put0(Sub, RH - 2, x->r, y->r);
            RH--;
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
        Put1(Lsl, x->r, x->r, e);
    } else if (y->mode == ORB_Const) {
        load(x);
        Put1a(Mul, x->r, x->r, y->a);
    } else if ((x->mode == ORB_Const) && (x->a >= 2) && (ORG_log2(x->a, &e) == 1)) {
        load(y);
        Put1(Lsl, y->r, y->r, e);
        x->mode = Reg;
        x->r = y->r;
    } else if (x->mode == ORB_Const) {
        load(y);
        Put1a(Mul, y->r, y->r, x->a);
        x->mode = Reg;
        x->r = y->r;
    } else {
        load(x);
        load(y);
        Put0(Mul, RH - 2, x->r, y->r);
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
            Put1(Asr, x->r, x->r, e);
        } else if (y->mode == ORB_Const) {
            if (y->a > 0) {
                load(x);
                Put1a(Div, x->r, x->r, y->a);
            } else {
                ORS_Mark("bad divisor");
            }
        } else {
            load(y);
            if (check) {
                Trap(LE, 6);
            }
            load(x);
            Put0(Div, RH - 2, x->r, y->r);
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
                Put1(And, x->r, x->r, y->a - 1);
            } else {
                Put1(Lsl, x->r, x->r, 32 - e);
                Put1(Ror, x->r, x->r, 32 - e);
            }
        } else if (y->mode == ORB_Const) {
            if (y->a > 0) {
                load(x);
                Put1a(Div, x->r, x->r, y->a);
                Put0(Mov + U, x->r, 0, 0);
            } else {
                ORS_Mark("bad modulus");
            }
        } else {
            load(y);
            if (check) {
                Trap(LE, 6);
            }
            load(x);
            Put0(Div, RH - 2, x->r, y->r);
            Put0(Mov + U, RH - 2, 0, 0);
            RH--;
            x->r = RH - 1;
        }
    }
}

void ORG_RealOp(INTEGER op, ORG_Item *x, ORG_Item *y) {
    load(x);
    load(y);
    
    if (op == ORS_plus) {
        Put0(Fad, RH - 2, x->r, y->r);
    } else if (op == ORS_minus) {
        Put0(Fsb, RH - 2, x->r, y->r);
    } else if (op == ORS_times) {
        Put0(Fml, RH - 2, x->r, y->r);
    } else if (op == ORS_rdiv) {
        Put0(Fdv, RH - 2, x->r, y->r);
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
        Put1(Mov, RH, 0, 1);
        Put0(Lsl, x->r, RH, x->r);
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
            Put1(Mov, RH, 0, -1);
            Put0(Lsl, x->r, RH, x->r);
        }
        
        if ((y->mode == ORB_Const) && (y->a < 16)) {
            Put1(Mov, RH, 0, (-2L) << y->a);
            y->mode = Reg;
            y->r = RH;
            incR();
        } else {
            load(y);
            Put1(Mov, RH, 0, -2);
            Put0(Lsl, y->r, RH, y->r);
        }
        
        if (x->mode == ORB_Const) {
            if (x->a != 0) {
                Put1(Xor, y->r, y->r, -1);
                Put1a(And, RH - 1, y->r, x->a);
            }
            x->mode = Reg;
            x->r = RH - 1;
        } else {
            RH--;
            Put0(Ann, RH - 1, x->r, y->r);
        }
    }
}

void ORG_In(ORG_Item *x, ORG_Item *y) {
    load(y);
    if (x->mode == ORB_Const) {
        Put1(Ror, y->r, y->r, (x->a + 1) % 0x20);
        RH--;
    } else {
        load(x);
        Put1(Add, x->r, x->r, 1);
        Put0(Ror, y->r, y->r, x->r);
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
            Put1a(Ior, x->r, x->r, y->a);
        } else if (op == ORS_minus) {
            Put1a(Ann, x->r, x->r, y->a);
        } else if (op == ORS_times) {
            Put1a(And, x->r, x->r, y->a);
        } else if (op == ORS_rdiv) {
            Put1a(Xor, x->r, x->r, y->a);
        }
    } else {
        load(x);
        load(y);
        if (op == ORS_plus) {
            Put0(Ior, RH - 2, x->r, y->r);
        } else if (op == ORS_minus) {
            Put0(Ann, RH - 2, x->r, y->r);
        } else if (op == ORS_times) {
            Put0(And, RH - 2, x->r, y->r);
        } else if (op == ORS_rdiv) {
            Put0(Xor, RH - 2, x->r, y->r);
        }
        RH--;
        x->r = RH - 1;
    }
}

// Relation operators
void ORG_IntRelation(INTEGER op, ORG_Item *x, ORG_Item *y) {
    if ((y->mode == ORB_Const) && (y->type->form != ORB_Proc)) {
        load(x);
        if ((y->a != 0) || ((op != ORS_eql) && (op != ORS_neq)) || 
            (code[ORG_pc - 1] / 0x40000000 != -2)) {
            Put1a(Cmp, x->r, x->r, y->a);
        }
        RH--;
    } else {
        if ((x->mode == Cond) || (y->mode == Cond)) {
            ORS_Mark("not implemented");
        }
        load(x);
        load(y);
        Put0(Cmp, x->r, x->r, y->r);
        RH -= 2;
    }
    SetCC(x, relmap[op - ORS_eql]);
}

void ORG_RealRelation(INTEGER op, ORG_Item *x, ORG_Item *y) {
    load(x);
    if ((y->mode == ORB_Const) && (y->a == 0)) {
        RH--;
    } else {
        load(y);
        Put0(Fsb, x->r, x->r, y->r);
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
    
    Put2(Ldr + 1, RH, x->r, 0);
    Put1(Add, x->r, x->r, 1);
    Put2(Ldr + 1, RH + 1, y->r, 0);
    Put1(Add, y->r, y->r, 1);
    Put0(Cmp, RH + 2, RH, RH + 1);
    Put3(BC, NE, 2);
    Put1(Cmp, RH + 2, RH, 0);
    Put3(BC, NE, -8);
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
            Put2(op, y->r, SP, x->a + frame);
        } else {
            GetSB(x->r);
            Put2(op, y->r, RH, x->a);
        }
    } else if (x->mode == ORB_Par) {
        Put2(Ldr, RH, SP, x->a + frame);
        Put2(op, y->r, RH, x->b);
    } else if (x->mode == RegI) {
        Put2(op, y->r, x->r, x->a);
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
                    Put1a(Mov, RH, 0, (y->type->size + 3) / 4);
                } else {
                    ORS_Mark("different length/size, not implemented");
                }
            } else {
                Put2(Ldr, RH, SP, y->a + 4);
                s = y->type->base->size;
                pc0 = ORG_pc;
                Put3(BC, EQ, 0);
                
                if (s == 1) {
                    Put1(Add, RH, RH, 3);
                    Put1(Asr, RH, RH, 2);
                } else if (s != 4) {
                    Put1a(Mul, RH, RH, s / 4);
                }
                
                if (check) {
                    Put1a(Mov, RH + 1, 0, (x->type->size + 3) / 4);
                    Put0(Cmp, RH + 1, RH, RH + 1);
                    Trap(GT, 3);
                }
                fix(pc0, ORG_pc + 5 - pc0);
            }
        } else if (x->type->form == ORB_Record) {
            Put1a(Mov, RH, 0, x->type->size / 4);
        } else {
            ORS_Mark("inadmissible assignment");
        }
        
        Put2(Ldr, RH + 1, y->r, 0);
        Put1(Add, y->r, y->r, 4);
        Put2(Str, RH + 1, x->r, 0);
        Put1(Add, x->r, x->r, 4);
        Put1(Sub, RH, RH, 1);
        Put3(BC, NE, -6);
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
        Put2(Ldr, RH, SP, x->a + 4);
        Put1(Cmp, RH, RH, y->b);
        Trap(LT, 3);
    }
    
    loadStringAdr(y);
    Put2(Ldr, RH, y->r, 0);
    Put1(Add, y->r, y->r, 4);
    Put2(Str, RH, x->r, 0);
    Put1(Add, x->r, x->r, 4);
    Put1(Asr, RH, RH, 24);
    Put3(BC, NE, -6);
    RH = 0;
}

// Parameter operations
void ORG_OpenArrayParam(ORG_Item *x) {
    loadAdr(x);
    if (x->type->len >= 0) {
        Put1a(Mov, RH, 0, x->type->len);
    } else {
        Put2(Ldr, RH, SP, x->a + 4 + frame);
    }
    incR();
}

void ORG_VarParam(ORG_Item *x, ORB_Type *ftype) {
    INTEGER xmd = x->mode;
    loadAdr(x);
    
    if ((ftype->form == ORB_Array) && (ftype->len < 0)) {
        if (x->type->len >= 0) {
            Put1a(Mov, RH, 0, x->type->len);
        } else {
            Put2(Ldr, RH, SP, x->a + 4 + frame);
        }
        incR();
    } else if (ftype->form == ORB_Record) {
        if (xmd == ORB_Par) {
            Put2(Ldr, RH, SP, x->a + 4 + frame);
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
    Put1(Mov, RH, 0, x->b);
    incR();
}

// For statement operations
void ORG_For0(ORG_Item *x, ORG_Item *y) {
    load(y);
}

void ORG_For1(ORG_Item *x, ORG_Item *y, ORG_Item *z, ORG_Item *w, LONGINT *L) {
    if (z->mode == ORB_Const) {
        Put1a(Cmp, RH, y->r, z->a);
    } else {
        load(z);
        Put0(Cmp, RH - 1, y->r, z->r);
        RH--;
    }
    
    *L = ORG_pc;
    if (w->a > 0) {
        Put3(BC, GT, 0);
    } else if (w->a < 0) {
        Put3(BC, LT, 0);
    } else {
        ORS_Mark("zero increment");
        Put3(BC, MI, 0);
    }
    ORG_Store(x, y);
}

void ORG_For2(ORG_Item *x, ORG_Item *y, ORG_Item *w) {
    load(x);
    RH--;
    Put1a(Add, x->r, x->r, w->a);
}

// Branch and jump operations
LONGINT ORG_Here(void) {
    return ORG_pc;
}

void ORG_FJump(LONGINT *L) {
    Put3(BC, 7, *L);
    *L = ORG_pc - 1;
}

void ORG_CFJump(ORG_Item *x) {
    if (x->mode != Cond) {
        loadCond(x);
    }
    Put3(BC, negated(x->r), x->a);
    ORG_FixLink(x->b);
    x->a = ORG_pc - 1;
}

void ORG_BJump(LONGINT L) {
    Put3(BC, 7, L - ORG_pc - 1);
}

void ORG_CBJump(ORG_Item *x, LONGINT L) {
    if (x->mode != Cond) {
        loadCond(x);
    }
    Put3(BC, negated(x->r), L - ORG_pc - 1);
    ORG_FixLink(x->b);
    FixLinkWith(x->a, L);
}

void ORG_Fixup(ORG_Item *x) {
    ORG_FixLink(x->a);
}

static void SaveRegs(LONGINT r) {
    LONGINT r0 = 0;
    Put1(Sub, SP, SP, r * 4);
    frame += 4 * r;
    do {
        Put2(Str, r0, SP, (r - r0 - 1) * 4);
        r0++;
    } while (r0 < r);
}

static void RestoreRegs(LONGINT r) {
    LONGINT r0 = r;
    do {
        r0--;
        Put2(Ldr, r0, SP, (r - r0 - 1) * 4);
    } while (r0 > 0);
    Put1(Add, SP, SP, r * 4);
    frame -= 4 * r;
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
}

void ORG_Call(ORG_Item *x, LONGINT r) {
    if (x->mode == ORB_Const) {
        if (x->r >= 0) {
            Put3(BL, 7, (x->a / 4) - ORG_pc - 1);
        } else {
            if (ORG_pc - fixorgP < 0x1000) {
                Put3(BL, 7, ((-x->r) * 0x100 + x->a) * 0x1000 + ORG_pc - fixorgP);
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
            Put2(Ldr, RH, SP, 0);
            Put1(Add, SP, SP, 4);
            r--;
            frame -= 4;
        }
        if (check) {
            Trap(EQ, 5);
        }
        Put3(BLR, 7, RH);
    }
    
    if (x->type->base->form == ORB_NoTyp) {
        RH = 0;
    } else {
        if (r > 0) {
            Put0(Mov, r, 0, 0);
            RestoreRegs(r);
        }
        x->mode = Reg;
        x->r = r;
        RH = r + 1;
    }
}

void ORG_Enter(LONGINT parblksize, LONGINT locblksize, BOOLEAN int_proc) {
    LONGINT a, r;
    
    frame = 0;
    if (!int_proc) {
        if (locblksize >= 0x10000) {
            ORS_Mark("too many locals");
        }
        a = 4;
        r = 0;
        Put1(Sub, SP, SP, locblksize);
        Put2(Str, LNK, SP, 0);
        while (a < parblksize) {
            Put2(Str, r, SP, a);
            r++;
            a += 4;
        }
    } else {
        Put1(Sub, SP, SP, locblksize);
        Put2(Str, 0, SP, 0);
        Put2(Str, 1, SP, 4);
        Put2(Str, 2, SP, 8);
    }
}

void ORG_Return(INTEGER form, ORG_Item *x, LONGINT size, BOOLEAN int_proc) {
    if (form != ORB_NoTyp) {
        load(x);
    }
    
    if (!int_proc) {
        Put2(Ldr, LNK, SP, 0);
        Put1(Add, SP, SP, size);
        Put3(BR, 7, LNK);
    } else {
        Put2(Ldr, 2, SP, 8);
        Put2(Ldr, 1, SP, 4);
        Put2(Ldr, 0, SP, 0);
        Put1(Add, SP, SP, size);
        Put3(BR, 7, 0x10);
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
        Put2(Ldr + v, zr, SP, x->a);
        incR();
        if (y->mode == ORB_Const) {
            Put1a(op, zr, zr, y->a);
        } else {
            load(y);
            Put0(op, zr, zr, y->r);
            RH--;
        }
        Put2(Str + v, zr, SP, x->a);
        RH--;
    } else {
        loadAdr(x);
        zr = RH;
        Put2(Ldr + v, RH, x->r, 0);
        incR();
        if (y->mode == ORB_Const) {
            Put1a(op, zr, zr, y->a);
        } else {
            load(y);
            Put0(op, zr, zr, y->r);
            RH--;
        }
        Put2(Str + v, zr, x->r, 0);
        RH -= 2;
    }
}

void ORG_Include(LONGINT inorex, ORG_Item *x, ORG_Item *y) {
    LONGINT op, zr;
    
    loadAdr(x);
    zr = RH;
    Put2(Ldr, RH, x->r, 0);
    incR();
    
    if (inorex == 0) {
        op = Ior;
    } else {
        op = Ann;
    }
    
    if (y->mode == ORB_Const) {
        Put1a(op, zr, zr, 1L << y->a);
    } else {
        load(y);
        Put1(Mov, RH, 0, 1);
        Put0(Lsl, y->r, RH, y->r);
        Put0(op, zr, zr, y->r);
        RH--;
    }
    Put2(Str, zr, x->r, 0);
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
        Put3(BC, x->r, x->b);
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
    Put1(Lsl, y->r, y->r, 23);
    Put0(Add, x->r, x->r, y->r);
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
    Put1(Asr, RH, x->r, 23);
    Put1(Sub, RH, RH, 127);
    ORG_Store(y, &e0);
    incR();
    Put1(Lsl, RH, RH, 23);
    Put0(Sub, x->r, x->r, RH);
    ORG_Store(&z, x);
}

void ORG_Led(ORG_Item *x) {
    load(x);
    Put1(Mov, RH, 0, -60);
    Put2(Str, x->r, RH, 0);
    RH--;
}

void ORG_Get(ORG_Item *x, ORG_Item *y) {
    load(x);
    x->type = y->type;
    x->mode = RegI;
    x->a = 0;
    ORG_Store(y, x);
}

void ORG_Put(ORG_Item *x, ORG_Item *y) {
    load(x);
    x->type = y->type;
    x->mode = RegI;
    x->a = 0;
    ORG_Store(x, y);
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
        Put3(BC, EQ, 6);
    }
    
    Put2(Ldr, RH, x->r, 0);
    Put1(Add, x->r, x->r, 4);
    Put2(Str, RH, y->r, 0);
    Put1(Add, y->r, y->r, 4);
    Put1(Sub, z->r, z->r, 1);
    Put3(BC, NE, -6);
    RH -= 3;
}

void ORG_LDPSR(ORG_Item *x) {
    Put3(0, 15, x->a + 0x20);
}

void ORG_LDREG(ORG_Item *x, ORG_Item *y) {
    if (y->mode == ORB_Const) {
        Put1a(Mov, x->a, 0, y->a);
    } else {
        load(y);
        Put0(Mov, x->a, 0, y->r);
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
            Put1(Lsl, x->r, x->r, 1);
            Put1(Ror, x->r, x->r, 1);
        } else {
            Put1(Cmp, x->r, x->r, 0);
            Put3(BC, GE, 2);
            Put1(Mov, RH, 0, 0);
            Put0(Sub, x->r, RH, x->r);
        }
    }
}

void ORG_Odd(ORG_Item *x) {
    load(x);
    Put1(And, x->r, x->r, 1);
    SetCC(x, NE);
    RH--;
}

void ORG_Floor(ORG_Item *x) {
    load(x);
    Put1(Mov + U, RH, 0, 0x4B00);
    Put0(Fad + V, x->r, x->r, RH);
}

void ORG_Float(ORG_Item *x) {
    load(x);
    Put1(Mov + U, RH, 0, 0x4B00);
    Put0(Fad + U, x->r, x->r, RH);
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
        Put2(Ldr, RH, SP, x->a + 4 + frame);
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
        Put1(op, x->r, x->r, y->a % 0x20);
    } else {
        load(y);
        Put0(op, RH - 2, x->r, y->r);
        RH--;
        x->r = RH - 1;
    }
}

void ORG_ADC(ORG_Item *x, ORG_Item *y) {
    load(x);
    load(y);
    Put0(Add + 0x2000, x->r, x->r, y->r);
    RH--;
}

void ORG_SBC(ORG_Item *x, ORG_Item *y) {
    load(x);
    load(y);
    Put0(Sub + 0x2000, x->r, x->r, y->r);
    RH--;
}

void ORG_UML(ORG_Item *x, ORG_Item *y) {
    load(x);
    load(y);
    Put0(Mul + 0x2000, x->r, x->r, y->r);
    RH--;
}

void ORG_Bit(ORG_Item *x, ORG_Item *y) {
    load(x);
    Put2(Ldr, x->r, x->r, 0);
    if (y->mode == ORB_Const) {
        Put1(Ror, x->r, x->r, y->a + 1);
        RH--;
    } else {
        load(y);
        Put1(Add, y->r, y->r, 1);
        Put0(Ror, x->r, x->r, y->r);
        RH -= 2;
    }
    SetCC(x, MI);
}

void ORG_Register(ORG_Item *x) {
    Put0(Mov, RH, 0, x->a % 0x10);
    x->mode = Reg;
    x->r = RH;
    incR();
}

void ORG_HH(ORG_Item *x) {
    Put0(Mov + U + (x->a % 2) * V, RH, 0, 0);
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
    ORG_pc = 0;
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
}

void ORG_SetDataSize(LONGINT dc) {
    ORG_varsize = dc;
}

void ORG_Header(void) {
    entry = ORG_pc * 4;
    if (version == 0) {
        code[0] = 0xE7000000 - 1 + ORG_pc;
        Put1a(Mov, SP, 0, StkOrg0);
    } else {
        Put1(Sub, SP, SP, 4);
        Put2(Str, LNK, SP, 0);
    }
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
        Put1(Mov, 0, 0, 0);
        Put3(BR, 7, 0);
    } else {
        Put2(Ldr, LNK, SP, 0);
        Put1(Add, SP, SP, 4);
        Put3(BR, 7, LNK);
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
    
    MakeFileName(name, modid, ".rsc");
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
    
    Files_WriteInt(&R, ORG_pc);
    for (i = 0; i < ORG_pc; i++) {
        Files_WriteInt(&R, code[i]);
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
    relmap[0] = 1;   // eql -> EQ
    relmap[1] = 9;   // neq -> NE  
    relmap[2] = 5;   // lss -> LT
    relmap[3] = 6;   // leq -> LE
    relmap[4] = 14;  // gtr -> GT
    relmap[5] = 13;  // geq -> GE
}
