// ORP.c - Stage 1: Headers and Basic Utility Functions
// Translated from ORP.Mod by N.Wirth

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ORP.h"
#include "ORS.h"
#include "ORB.h"
#include "ORG.h"
#include "Texts.h"
#include "Oberon.h"

// Global variables
static INTEGER sym;
static LONGINT dc;
static INTEGER level, exno, version;
static BOOLEAN newSF;
static void (*expression)(ORG_Item *x);
static void (*Type)(ORB_Type **type);
static void (*FormalType)(ORB_Type **typ, INTEGER dim);
static ORS_Ident modid;
static PtrBase *pbsList;
static ORB_Object *dummy;
static Texts_Writer W;

// Forward declarations
static void expression0(ORG_Item *x);
static void Type0(ORB_Type **type);
static void FormalType0(ORB_Type **typ, INTEGER dim);
static void StatSequence(void);
static void ProcedureType(ORB_Type *ptype, LONGINT *parblksize);
static void Declarations(LONGINT *varsize);
static void ProcedureDecl(void);

// Basic utility functions
static void Check(INTEGER s, char *msg) {
    if (sym == s) {
        ORS_Get(&sym);
    } else {
        ORS_Mark(msg);
    }
}

static void qualident(ORB_Object **obj) {
    *obj = thisObj();
    ORS_Get(&sym);
    if (*obj == NULL) {
        ORS_Mark("undef");
        *obj = dummy;
    }
    if ((sym == ORS_period) && ((*obj)->class == Mod)) {
        ORS_Get(&sym);
        if (sym == ORS_ident) {
            *obj = thisimport(*obj);
            ORS_Get(&sym);
            if (*obj == NULL) {
                ORS_Mark("undef");
                *obj = dummy;
            }
        } else {
            ORS_Mark("identifier expected");
            *obj = dummy;
        }
    }
}

static void CheckBool(ORG_Item *x) {
    if (x->type->form != Bool) {
        ORS_Mark("not Boolean");
        x->type = boolType;
    }
}

static void CheckInt(ORG_Item *x) {
    if (x->type->form != Int) {
        ORS_Mark("not Integer");
        x->type = intType;
    }
}

static void CheckReal(ORG_Item *x) {
    if (x->type->form != Real) {
        ORS_Mark("not Real");
        x->type = realType;
    }
}

static void CheckSet(ORG_Item *x) {
    if (x->type->form != Set) {
        ORS_Mark("not Set");
        x->type = setType;
    }
}

static void CheckSetVal(ORG_Item *x) {
    if (x->type->form != Int) {
        ORS_Mark("not Int");
        x->type = setType;
    } else if (x->mode == ORS_const) {
        if ((x->a < 0) || (x->a >= 32)) {
            ORS_Mark("invalid set");
        }
    }
}

static void CheckConst(ORG_Item *x) {
    if (x->mode != Const) {
        ORS_Mark("not a constant");
        x->mode = ORS_const;
    }
}

static void CheckReadOnly(ORG_Item *x) {
    if (x->rdo) {
        ORS_Mark("read-only");
    }
}

static void CheckExport(BOOLEAN *expo) {
    if (sym == ORS_times) {
        *expo = TRUE;
        ORS_Get(&sym);
        if (level != 0) {
            ORS_Mark("remove asterisk");
        }
    } else {
        *expo = FALSE;
    }
}

static BOOLEAN IsExtension(ORB_Type *t0, ORB_Type *t1) {
    return (t0 == t1) || ((t1 != NULL) && IsExtension(t0, t1->base));
}

/* ORP.c - Parser Implementation - Stage 2: Expression Parsing */

// Stage 2: Expression Parsing Helper Functions

static void TypeTest(ORG_Item *x, ORB_Type *T, BOOLEAN guard) {
    ORB_Type *xt = x->type;
    
    if ((T->form == xt->form) && 
        ((T->form == Pointer) || 
         ((T->form == Record) && (x->mode == Par)))) {
        
        while ((xt != T) && (xt != NULL)) {
            xt = xt->base;
        }
        
        if (xt != T) {
            xt = x->type;
            if (xt->form == Pointer) {
                if (IsExtension(xt->base, T->base)) {
                    ORG_TypeTest(x, T->base, FALSE, guard);
                    x->type = T;
                } else {
                    ORS_Mark("not an extension");
                }
            } else if ((xt->form == Record) && (x->mode == Par)) {
                if (IsExtension(xt, T)) {
                    ORG_TypeTest(x, T, TRUE, guard);
                    x->type = T;
                } else {
                    ORS_Mark("not an extension");
                }
            } else {
                ORS_Mark("incompatible types");
            }
        } else if (!guard) {
            ORG_TypeTest(x, NULL, FALSE, FALSE);
        }
    } else {
        ORS_Mark("type mismatch");
    }
    
    if (!guard) {
        x->type = boolType;
    }
}

static void selector(ORG_Item *x) {
    ORG_Item y;
    ORB_Object *obj;
    
    while ((sym == ORS_lbrak) || (sym == ORS_period) || (sym == ORS_arrow) ||
           ((sym == ORS_lparen) && 
            ((x->type->form == Record) || (x->type->form == Pointer)))) {
        
        if (sym == ORS_lbrak) {
            do {
                ORS_Get(&sym);
                expression(&y);
                if (x->type->form == Array) {
                    CheckInt(&y);
                    ORG_Index(x, &y);
                    x->type = x->type->base;
                } else {
                    ORS_Mark("not an array");
                }
            } while (sym == ORS_comma);
            Check(ORS_rbrak, "no ]");
            
        } else if (sym == ORS_period) {
            ORS_Get(&sym);
            if (sym == ORS_ident) {
                if (x->type->form == Pointer) {
                    ORG_DeRef(x);
                    x->type = x->type->base;
                }
                if (x->type->form == Record) {
                    obj = thisfield(x->type);
                    ORS_Get(&sym);
                    if (obj != NULL) {
                        ORG_Field(x, obj);
                        x->type = obj->type;
                    } else {
                        ORS_Mark("undef");
                    }
                } else {
                    ORS_Mark("not a record");
                }
            } else {
                ORS_Mark("ident?");
            }
            
        } else if (sym == ORS_arrow) {
            ORS_Get(&sym);
            if (x->type->form == Pointer) {
                ORG_DeRef(x);
                x->type = x->type->base;
            } else {
                ORS_Mark("not a pointer");
            }
            
        } else if ((sym == ORS_lparen) && 
                   ((x->type->form == Record) || (x->type->form == Pointer))) {
            ORS_Get(&sym);
            if (sym == ORS_ident) {
                qualident(&obj);
                if (obj->class == Typ) {
                    TypeTest(x, obj->type, TRUE);
                } else {
                    ORS_Mark("guard type expected");
                }
            } else {
                ORS_Mark("not an identifier");
            }
            Check(ORS_rparen, " ) missing");
        }
    }
}

static BOOLEAN EqualSignatures(ORB_Type *t0, ORB_Type *t1) {
    ORB_Object *p0, *p1;
    BOOLEAN com = TRUE;
    
    if ((t0->base == t1->base) && (t0->nofpar == t1->nofpar)) {
        p0 = t0->dsc;
        p1 = t1->dsc;
        while (p0 != NULL) {
            if ((p0->class == p1->class) && (p0->rdo == p1->rdo) &&
                ((p0->type == p1->type) ||
                 ((p0->type->form == Array) && (p1->type->form == Array) &&
                  (p0->type->len == p1->type->len) && (p0->type->base == p1->type->base)) ||
                 ((p0->type->form == Proc) && (p1->type->form == Proc) &&
                  EqualSignatures(p0->type, p1->type)))) {
                p0 = p0->next;
                p1 = p1->next;
            } else {
                p0 = NULL;
                com = FALSE;
            }
        }
    } else {
        com = FALSE;
    }
    return com;
}

static BOOLEAN CompTypes(ORB_Type *t0, ORB_Type *t1, BOOLEAN varpar) {
    return (t0 == t1) ||
           ((t0->form == Array) && (t1->form == Array) && 
            (t0->base == t1->base) && (t0->len == t1->len)) ||
           ((t0->form == Record) && (t1->form == Record) && 
            IsExtension(t0, t1)) ||
           (!varpar &&
            (((t0->form == Pointer) && (t1->form == Pointer) && 
              IsExtension(t0->base, t1->base)) ||
             ((t0->form == Proc) && (t1->form == Proc) && 
              EqualSignatures(t0, t1)) ||
             (((t0->form == Pointer) || (t0->form == Proc)) && 
              (t1->form == NilTyp))));
}

/* ORP.c - Parser Implementation - Stage 3: Statement Parsing */

// Stage 3: Parameter Handling and Standard Functions

static void Parameter(ORB_Object *par) {
    ORG_Item x;
    BOOLEAN varpar;
    
    expression(&x);
    if (par != NULL) {
        varpar = (par->class == Par);
        if (CompTypes(par->type, x.type, varpar)) {
            if (!varpar) {
                ORG_ValueParam(&x);
            } else {
                if (!par->rdo) {
                    CheckReadOnly(&x);
                }
                ORG_VarParam(&x, par->type);
            }
        } else if ((x.type->form == Array) && (par->type->form == Array) &&
                   (x.type->base == par->type->base) && (par->type->len < 0)) {
            if (!par->rdo) {
                CheckReadOnly(&x);
            }
            ORG_OpenArrayParam(&x);
        } else if ((x.type->form == String) && varpar && par->rdo &&
                   (par->type->form == Array) && (par->type->base->form == Char) &&
                   (par->type->len < 0)) {
            ORG_StringParam(&x);
        } else if (!varpar && (par->type->form == Int) && (x.type->form == Int)) {
            ORG_ValueParam(&x);  // BYTE
        } else if ((x.type->form == String) && (x.b == 2) && 
                   (par->class == Var) && (par->type->form == Char)) {
            ORG_StrToChar(&x);
            ORG_ValueParam(&x);
        } else if ((par->type->form == Array) && (par->type->base == byteType) &&
                   (par->type->len >= 0) && (par->type->size == x.type->size)) {
            ORG_VarParam(&x, par->type);
        } else {
            ORS_Mark("incompatible parameters");
        }
    }
}

static void ParamList(ORG_Item *x) {
    INTEGER n = 0;
    ORB_Object *par = x->type->dsc;
    
    if (sym != ORS_rparen) {
        Parameter(par);
        n = 1;
        while (sym <= ORS_comma) {
            Check(ORS_comma, "comma?");
            if (par != NULL) {
                par = par->next;
            }
            n++;
            Parameter(par);
        }
        Check(ORS_rparen, ") missing");
    } else {
        ORS_Get(&sym);
    }
    
    if (n < x->type->nofpar) {
        ORS_Mark("too few params");
    } else if (n > x->type->nofpar) {
        ORS_Mark("too many params");
    }
}

static void StandFunc(ORG_Item *x, LONGINT fct, ORB_Type *restyp) {
    ORG_Item y;
    LONGINT n, npar;
    
    Check(ORS_lparen, "no (");
    npar = fct % 10;
    fct = fct / 10;
    expression(x);
    n = 1;
    
    while (sym == ORS_comma) {
        ORS_Get(&sym);
        expression(&y);
        n++;
    }
    Check(ORS_rparen, "no )");
    
    if (n == npar) {
        if (fct == 0) {  // ABS
            if ((x->type->form == Int) || (x->type->form == Real)) {
                ORG_Abs(x);
                restyp = x->type;
            } else {
                ORS_Mark("bad type");
            }
        } else if (fct == 1) {  // ODD
            CheckInt(x);
            ORG_Odd(x);
        } else if (fct == 2) {  // FLOOR
            CheckReal(x);
            ORG_Floor(x);
        } else if (fct == 3) {  // FLT
            CheckInt(x);
            ORG_Float(x);
        } else if (fct == 4) {  // ORD
            if (x->type->form <= Proc) {
                ORG_Ord(x);
            } else if ((x->type->form == String) && (x->b == 2)) {
                ORG_StrToChar(x);
            } else {
                ORS_Mark("bad type");
            }
        } else if (fct == 5) {  // CHR
            CheckInt(x);
            ORG_Ord(x);
        } else if (fct == 6) {  // LEN
            if (x->type->form == Array) {
                ORG_Len(x);
            } else {
                ORS_Mark("not an array");
            }
        } else if ((fct >= 7) && (fct <= 9)) {  // LSL, ASR, ROR
            CheckInt(&y);
            if ((x->type->form == Int) || (x->type->form == Set)) {
                ORG_Shift(fct - 7, x, &y);
                restyp = x->type;
            } else {
                ORS_Mark("bad type");
            }
        } else if (fct == 11) {  // ADC
            ORG_ADC(x, &y);
        } else if (fct == 12) {  // SBC
            ORG_SBC(x, &y);
        } else if (fct == 13) {  // UML
            ORG_UML(x, &y);
        } else if (fct == 14) {  // BIT
            CheckInt(x);
            CheckInt(&y);
            ORG_Bit(x, &y);
        } else if (fct == 15) {  // REG
            CheckConst(x);
            CheckInt(x);
            ORG_Register(x);
        } else if (fct == 16) {  // VAL
            if ((x->mode == Typ) && (x->type->size <= y.type->size)) {
                restyp = x->type;
                *x = y;
            } else {
                ORS_Mark("casting not allowed");
            }
        } else if (fct == 17) {  // ADR
            ORG_Adr(x);
        } else if (fct == 18) {  // SIZE
            if (x->mode == Typ) {
                ORG_MakeConstItem(x, intType, x->type->size);
            } else {
                ORS_Mark("must be a type");
            }
        } else if (fct == 19) {  // COND
            CheckConst(x);
            CheckInt(x);
            ORG_Condition(x);
        } else if (fct == 20) {  // H
            CheckConst(x);
            CheckInt(x);
            ORG_HH(x);
        }
        x->type = restyp;
    } else {
        ORS_Mark("wrong nof params");
    }
}

static void element(ORG_Item *x) {
    ORG_Item y;
    
    expression(x);
    CheckSetVal(x);
    if (sym == ORS_upto) {
        ORS_Get(&sym);
        expression(&y);
        CheckSetVal(&y);
        ORG_Set(x, &y);
    } else {
        ORG_Singleton(x);
    }
    x->type = setType;
}

static void set(ORG_Item *x) {
    ORG_Item y;
    
    if (sym >= ORS_if) {
        if (sym != ORS_rbrace) {
            ORS_Mark(" } missing");
        }
        ORG_MakeConstItem(x, setType, 0);  // empty set
    } else {
        element(x);
        while ((sym < ORS_rparen) || (sym > ORS_rbrace)) {
            if (sym == ORS_comma) {
                ORS_Get(&sym);
            } else if (sym != ORS_rbrace) {
                ORS_Mark("missing comma");
            }
            element(&y);
            ORG_SetOp(ORS_plus, x, &y);
        }
    }
}

/* ORP.c - Parser Implementation - Stage 4: Type and Declaration Parsing */

// Stage 4: Expression Parsing Implementation

static void factor(ORG_Item *x) {
    ORB_Object *obj;
    LONGINT rx;
    
    // sync
    if ((sym < ORS_char) || (sym > ORS_ident)) {
        ORS_Mark("expression expected");
        do {
            ORS_Get(&sym);
        } while (((sym < ORS_char) || (sym > ORS_for)) && (sym < ORS_then));
    }
    
    if (sym == ORS_ident) {
        qualident(&obj);
        if (obj->class == SFunc) {
            StandFunc(x, obj->val, obj->type);
        } else {
            ORG_MakeItem(x, obj, level);
            selector(x);
            if (sym == ORS_lparen) {
                ORS_Get(&sym);
                if ((x->type->form == Proc) && (x->type->base->form != NoTyp)) {
                    ORG_PrepCall(x, &rx);
                    ParamList(x);
                    ORG_Call(x, rx);
                    x->type = x->type->base;
                } else {
                    ORS_Mark("not a function");
                    ParamList(x);
                }
            }
        }
    } else if (sym == ORS_int) {
        ORG_MakeConstItem(x, intType, ORS_ival);
        ORS_Get(&sym);
    } else if (sym == ORS_real) {
        ORG_MakeRealItem(x, ORS_rval);
        ORS_Get(&sym);
    } else if (sym == ORS_char) {
        ORG_MakeConstItem(x, charType, ORS_ival);
        ORS_Get(&sym);
    } else if (sym == ORS_nil) {
        ORS_Get(&sym);
        ORG_MakeConstItem(x, nilType, 0);
    } else if (sym == ORS_string) {
        ORG_MakeStringItem(x, ORS_slen);
        ORS_Get(&sym);
    } else if (sym == ORS_lparen) {
        ORS_Get(&sym);
        expression(x);
        Check(ORS_rparen, "no )");
    } else if (sym == ORS_lbrace) {
        ORS_Get(&sym);
        set(x);
        Check(ORS_rbrace, "no }");
    } else if (sym == ORS_not) {
        ORS_Get(&sym);
        factor(x);
        CheckBool(x);
        ORG_Not(x);
    } else if (sym == ORS_false) {
        ORS_Get(&sym);
        ORG_MakeConstItem(x, boolType, 0);
    } else if (sym == ORS_true) {
        ORS_Get(&sym);
        ORG_MakeConstItem(x, boolType, 1);
    } else {
        ORS_Mark("not a factor");
        ORG_MakeConstItem(x, intType, 0);
    }
}

static void term(ORG_Item *x) {
    ORG_Item y;
    INTEGER op, f;
    
    factor(x);
    f = x->type->form;
    
    while ((sym >= ORS_times) && (sym <= ORS_and)) {
        op = sym;
        ORS_Get(&sym);
        
        if (op == ORS_times) {
            if (f == Int) {
                factor(&y);
                CheckInt(&y);
                ORG_MulOp(x, &y);
            } else if (f == Real) {
                factor(&y);
                CheckReal(&y);
                ORG_RealOp(op, x, &y);
            } else if (f == Set) {
                factor(&y);
                CheckSet(&y);
                ORG_SetOp(op, x, &y);
            } else {
                ORS_Mark("bad type");
            }
        } else if ((op == ORS_div) || (op == ORS_mod)) {
            CheckInt(x);
            factor(&y);
            CheckInt(&y);
            ORG_DivOp(op, x, &y);
        } else if (op == ORS_rdiv) {
            if (f == Real) {
                factor(&y);
                CheckReal(&y);
                ORG_RealOp(op, x, &y);
            } else if (f == Set) {
                factor(&y);
                CheckSet(&y);
                ORG_SetOp(op, x, &y);
            } else {
                ORS_Mark("bad type");
            }
        } else {  // op == and
            CheckBool(x);
            ORG_And1(x);
            factor(&y);
            CheckBool(&y);
            ORG_And2(x, &y);
        }
    }
}

static void SimpleExpression(ORG_Item *x) {
    ORG_Item y;
    INTEGER op;
    
    if (sym == ORS_minus) {
        ORS_Get(&sym);
        term(x);
        if ((x->type->form == Int) || (x->type->form == Real) || 
            (x->type->form == Set)) {
            ORG_Neg(x);
        } else {
            CheckInt(x);
        }
    } else if (sym == ORS_plus) {
        ORS_Get(&sym);
        term(x);
    } else {
        term(x);
    }
    
    while ((sym >= ORS_plus) && (sym <= ORS_or)) {
        op = sym;
        ORS_Get(&sym);
        
        if (op == ORS_or) {
            ORG_Or1(x);
            CheckBool(x);
            term(&y);
            CheckBool(&y);
            ORG_Or2(x, &y);
        } else if (x->type->form == Int) {
            term(&y);
            CheckInt(&y);
            ORG_AddOp(op, x, &y);
        } else if (x->type->form == Real) {
            term(&y);
            CheckReal(&y);
            ORG_RealOp(op, x, &y);
        } else {
            CheckSet(x);
            term(&y);
            CheckSet(&y);
            ORG_SetOp(op, x, &y);
        }
    }
}

static void expression0(ORG_Item *x) {
    ORG_Item y;
    ORB_Object *obj;
    INTEGER rel, xf, yf;
    
    SimpleExpression(x);
    
    if ((sym >= ORS_eql) && (sym <= ORS_geq)) {
        rel = sym;
        ORS_Get(&sym);
        SimpleExpression(&y);
        xf = x->type->form;
        yf = y.type->form;
        
        if (x->type == y.type) {
            if ((xf == Char) || (xf == Int)) {
                ORG_IntRelation(rel, x, &y);
            } else if (xf == Real) {
                ORG_RealRelation(rel, x, &y);
            } else if ((xf == Set) || (xf == Pointer) || (xf == Proc) || 
                       (xf == NilTyp) || (xf == Bool)) {
                if (rel <= ORS_neq) {
                    ORG_IntRelation(rel, x, &y);
                } else {
                    ORS_Mark("only = or #");
                }
            } else if (((xf == Array) && (x->type->base->form == Char)) || 
                       (xf == String)) {
                ORG_StringRelation(rel, x, &y);
            } else {
                ORS_Mark("illegal comparison");
            }
        } else if (((xf == Pointer) || ((xf == Proc) && (yf == NilTyp))) ||
                   ((yf == Pointer) || ((yf == Proc) && (xf == NilTyp)))) {
            if (rel <= ORS_neq) {
                ORG_IntRelation(rel, x, &y);
            } else {
                ORS_Mark("only = or #");
            }
        } else if ((((xf == Pointer) && (yf == Pointer)) &&
					((IsExtension(x->type->base, y.type->base)) || 
                    (IsExtension(y.type->base, x->type->base)))) ||
                   ((xf == Proc) && (yf == Proc) && 
                    EqualSignatures(x->type, y.type))) {
            if (rel <= ORS_neq) {
                ORG_IntRelation(rel, x, &y);
            } else {
                ORS_Mark("only = or #");
            }
        } else if (((xf == Array) && (x->type->base->form == Char) &&
                    ((yf == String) || ((yf == Array) && 
                     (y.type->base->form == Char)))) ||
                   ((yf == Array) && (y.type->base->form == Char) && 
                    (xf == String))) {
            ORG_StringRelation(rel, x, &y);
        } else if ((xf == Char) && (yf == String) && (y.b == 2)) {
            ORG_StrToChar(&y);
            ORG_IntRelation(rel, x, &y);
        } else if ((yf == Char) && (xf == String) && (x->b == 2)) {
            ORG_StrToChar(x);
            ORG_IntRelation(rel, x, &y);
        } else if ((xf == Int) && (yf == Int)) {
            ORG_IntRelation(rel, x, &y);  // BYTE
        } else {
            ORS_Mark("illegal comparison");
        }
        x->type = boolType;
    } else if (sym == ORS_in) {
        ORS_Get(&sym);
        CheckInt(x);
        SimpleExpression(&y);
        CheckSet(&y);
        ORG_In(x, &y);
        x->type = boolType;
    } else if (sym == ORS_is) {
        ORS_Get(&sym);
        qualident(&obj);
        TypeTest(x, obj->type, FALSE);
        x->type = boolType;
    }
}

// ORP Stage 5 - Main Procedures and Module Functions

// Stage 5: Statements, Declarations, and Main Functions

static void StandProc(LONGINT pno) {
    LONGINT nap, npar;
    ORG_Item x, y, z;
    
    Check(ORS_lparen, "no (");
    npar = pno % 10;
    pno = pno / 10;
    expression(&x);
    nap = 1;
    
    if (sym == ORS_comma) {
        ORS_Get(&sym);
        expression(&y);
        nap = 2;
        z.type = noType;
        while (sym == ORS_comma) {
            ORS_Get(&sym);
            expression(&z);
            nap++;
        }
    } else {
        y.type = noType;
    }
    Check(ORS_rparen, "no )");
    
    if ((npar == nap) || ((pno == 0) || (pno == 1))) {
        if ((pno == 0) || (pno == 1)) {  // INC, DEC
            CheckInt(&x);
            CheckReadOnly(&x);
            if (y.type != noType) {
                CheckInt(&y);
            }
            ORG_Increment(pno, &x, &y);
        } else if ((pno == 2) || (pno == 3)) {  // INCL, EXCL
            CheckSet(&x);
            CheckReadOnly(&x);
            CheckInt(&y);
            ORG_Include(pno - 2, &x, &y);
        } else if (pno == 4) {  // ASSERT
            CheckBool(&x);
            ORG_Assert(&x);
        } else if (pno == 5) {  // NEW
            CheckReadOnly(&x);
            if ((x.type->form == Pointer) && (x.type->base->form == Record)) {
                ORG_New(&x);
            } else {
                ORS_Mark("not a pointer to record");
            }
        } else if (pno == 6) {  // PACK
            CheckReal(&x);
            CheckInt(&y);
            CheckReadOnly(&x);
            ORG_Pack(&x, &y);
        } else if (pno == 7) {  // UNPK
            CheckReal(&x);
            CheckInt(&y);
            CheckReadOnly(&x);
            ORG_Unpk(&x, &y);
        } else if (pno == 8) {  // LED
            if (x.type->form <= Set) {
                ORG_Led(&x);
            } else {
                ORS_Mark("bad type");
            }
        } else if (pno == 10) {  // GET
            CheckInt(&x);
            ORG_Get(&x, &y);
        } else if (pno == 11) {  // PUT
            CheckInt(&x);
            ORG_Put(&x, &y);
        } else if (pno == 12) {  // COPY
            CheckInt(&x);
            CheckInt(&y);
            CheckInt(&z);
            ORG_Copy(&x, &y, &z);
        } else if (pno == 13) {  // LDPSR
            CheckConst(&x);
            CheckInt(&x);
            ORG_LDPSR(&x);
        } else if (pno == 14) {  // LDREG
            CheckInt(&x);
            ORG_LDREG(&x, &y);
        }
    } else {
        ORS_Mark("wrong nof parameters");
    }
}

static void StatSequence(void) {
    ORB_Object *obj;
    ORB_Type *orgtype;
    ORG_Item x, y, z, w;
    LONGINT L0, L1, rx;
    
    // TypeCase procedure
    void TypeCase(ORB_Object *obj, ORG_Item *x) {
        ORB_Object *typobj;
        if (sym == ORS_ident) {
            qualident(&typobj);
            ORG_MakeItem(x, obj, level);
            if (typobj->class != Typ) {
                ORS_Mark("not a type");
            }
            TypeTest(x, typobj->type, FALSE);
            obj->type = typobj->type;
            ORG_CFJump(x);
            Check(ORS_colon, ": expected");
            StatSequence();
        } else {
            ORG_CFJump(x);
            ORS_Mark("type id expected");
        }
    }
    
    // SkipCase procedure
    void SkipCase(void) {
        while (sym != ORS_colon) {
            ORS_Get(&sym);
        }
        ORS_Get(&sym);
        StatSequence();
    }
    
    do {
        obj = NULL;
        
        // sync
        if (!((sym >= ORS_ident) && (sym <= ORS_for)) && (sym < ORS_semicolon)) {
            ORS_Mark("statement expected");
            do {
                ORS_Get(&sym);
            } while (sym < ORS_ident);
        }
        
        if (sym == ORS_ident) {
            qualident(&obj);
            ORG_MakeItem(&x, obj, level);
            if (x.mode == SProc) {
                StandProc(obj->val);
            } else {
                selector(&x);
                if (sym == ORS_becomes) {  // assignment
                    ORS_Get(&sym);
                    CheckReadOnly(&x);
                    expression(&y);
                    if (CompTypes(x.type, y.type, FALSE)) {
                        if ((x.type->form <= Pointer) || (x.type->form == Proc)) {
                            ORG_Store(&x, &y);
                        } else {
                            ORG_StoreStruct(&x, &y);
                        }
                    } else if ((x.type->form == Array) && (y.type->form == Array) &&
                               (x.type->base == y.type->base) && (y.type->len < 0)) {
                        ORG_StoreStruct(&x, &y);
                    } else if ((x.type->form == Array) && (x.type->base->form == Char) &&
                               (y.type->form == String)) {
                        ORG_CopyString(&x, &y);
                    } else if ((x.type->form == Int) && (y.type->form == Int)) {
                        ORG_Store(&x, &y);  // BYTE
                    } else if ((x.type->form == Char) && (y.type->form == String) &&
                               (y.b == 2)) {
                        ORG_StrToChar(&y);
                        ORG_Store(&x, &y);
                    } else {
                        ORS_Mark("illegal assignment");
                    }
                } else if (sym == ORS_eql) {
                    ORS_Mark("should be :=");
                    ORS_Get(&sym);
                    expression(&y);
                } else if (sym == ORS_lparen) {  // procedure call
                    ORS_Get(&sym);
                    if ((x.type->form == Proc) && (x.type->base->form == NoTyp)) {
                        ORG_PrepCall(&x, &rx);
                        ParamList(&x);
                        ORG_Call(&x, rx);
                    } else {
                        ORS_Mark("not a procedure");
                        ParamList(&x);
                    }
                } else if (x.type->form == Proc) {  // procedure call without parameters
                    if (x.type->nofpar > 0) {
                        ORS_Mark("missing parameters");
                    }
                    if (x.type->base->form == NoTyp) {
                        ORG_PrepCall(&x, &rx);
                        ORG_Call(&x, rx);
                    } else {
                        ORS_Mark("not a procedure");
                    }
                } else if (x.mode == Typ) {
                    ORS_Mark("illegal assignment");
                } else {
                    ORS_Mark("not a procedure");
                }
            }
        } else if (sym == ORS_if) {
            ORS_Get(&sym);
            expression(&x);
            CheckBool(&x);
            ORG_CFJump(&x);
            Check(ORS_then, "no THEN");
            StatSequence();
            L0 = 0;
            while (sym == ORS_elsif) {
                ORS_Get(&sym);
                ORG_FJump(&L0);
                ORG_Fixup(&x);
                expression(&x);
                CheckBool(&x);
                ORG_CFJump(&x);
                Check(ORS_then, "no THEN");
                StatSequence();
            }
            if (sym == ORS_else) {
                ORS_Get(&sym);
                ORG_FJump(&L0);
                ORG_Fixup(&x);
                StatSequence();
            } else {
                ORG_Fixup(&x);
            }
            ORG_FixLink(L0);
            Check(ORS_end, "no END");
        } else if (sym == ORS_while) {
            ORS_Get(&sym);
            L0 = ORG_Here();
            expression(&x);
            CheckBool(&x);
            ORG_CFJump(&x);
            Check(ORS_do, "no DO");
            StatSequence();
            ORG_BJump(L0);
            while (sym == ORS_elsif) {
                ORS_Get(&sym);
                ORG_Fixup(&x);
                expression(&x);
                CheckBool(&x);
                ORG_CFJump(&x);
                Check(ORS_do, "no DO");
                StatSequence();
                ORG_BJump(L0);
            }
            ORG_Fixup(&x);
            Check(ORS_end, "no END");
        } else if (sym == ORS_repeat) {
            ORS_Get(&sym);
            L0 = ORG_Here();
            StatSequence();
            if (sym == ORS_until) {
                ORS_Get(&sym);
                expression(&x);
                CheckBool(&x);
                ORG_CBJump(&x, L0);
            } else {
                ORS_Mark("missing UNTIL");
            }
        } else if (sym == ORS_for) {
            ORS_Get(&sym);
            if (sym == ORS_ident) {
                qualident(&obj);
                ORG_MakeItem(&x, obj, level);
                CheckInt(&x);
                CheckReadOnly(&x);
                if (sym == ORS_becomes) {
                    ORS_Get(&sym);
                    expression(&y);
                    CheckInt(&y);
                    ORG_For0(&x, &y);
                    L0 = ORG_Here();
                    Check(ORS_to, "no TO");
                    expression(&z);
                    CheckInt(&z);
                    obj->rdo = TRUE;
                    if (sym == ORS_by) {
                        ORS_Get(&sym);
                        expression(&w);
                        CheckConst(&w);
                        CheckInt(&w);
                    } else {
                        ORG_MakeConstItem(&w, intType, 1);
                    }
                    Check(ORS_do, "no DO");
                    ORG_For1(&x, &y, &z, &w, &L1);
                    StatSequence();
                    Check(ORS_end, "no END");
                    ORG_For2(&x, &y, &w);
                    ORG_BJump(L0);
                    ORG_FixLink(L1);
                    obj->rdo = FALSE;
                } else {
                    ORS_Mark(":= expected");
                }
            } else {
                ORS_Mark("identifier expected");
            }
        } else if (sym == ORS_case) {
            ORS_Get(&sym);
            if (sym == ORS_ident) {
                qualident(&obj);
                orgtype = obj->type;
                if ((orgtype->form == Pointer) ||
                    ((orgtype->form == Record) && (obj->class == Par))) {
                    Check(ORS_of, "OF expected");
                    TypeCase(obj, &x);
                    L0 = 0;
                    while (sym == ORS_bar) {
                        ORS_Get(&sym);
                        ORG_FJump(&L0);
                        ORG_Fixup(&x);
                        obj->type = orgtype;
                        TypeCase(obj, &x);
                    }
                    ORG_Fixup(&x);
                    ORG_FixLink(L0);
                    obj->type = orgtype;
                } else {
                    ORS_Mark("numeric case not implemented");
                    Check(ORS_of, "OF expected");
                    SkipCase();
                    while (sym == ORS_bar) {
                        SkipCase();
                    }
                }
            } else {
                ORS_Mark("ident expected");
            }
            Check(ORS_end, "no END");
        }
        
        ORG_CheckRegs();
        if (sym == ORS_semicolon) {
            ORS_Get(&sym);
        } else if (sym < ORS_semicolon) {
            ORS_Mark("missing semicolon?");
            ORS_Get(&sym);  // Advance past problematic symbol to prevent infinite loop
        }
    } while (sym <= ORS_semicolon);
}

static void IdentList(INTEGER class, ORB_Object **first) {
    ORB_Object *obj;
    
    if (sym == ORS_ident) {
        NewObj(first, ORS_id, class);
        ORS_Get(&sym);
        CheckExport(&(*first)->expo);
        while (sym == ORS_comma) {
            ORS_Get(&sym);
            if (sym == ORS_ident) {
                NewObj(&obj, ORS_id, class);
                ORS_Get(&sym);
                CheckExport(&obj->expo);
            } else {
                ORS_Mark("ident?");
            }
        }
        if (sym == ORS_colon) {
            ORS_Get(&sym);
        } else {
            ORS_Mark(":?");
        }
    } else {
        *first = NULL;
    }
}

static void ArrayType(ORB_Type **type) {
    ORG_Item x;
    ORB_Type *typ;
    LONGINT len;
    
    typ = (ORB_Type*)malloc(sizeof(ORB_Type));
    typ->form = NoTyp;
    expression(&x);
    
    if ((x.mode == ORS_const) && (x.type->form == Int) && (x.a >= 0)) {
        len = x.a;
    } else {
        len = 1;
        ORS_Mark("not a valid length");
    }
    
    if (sym == ORS_of) {
        ORS_Get(&sym);
        Type(&typ->base);
        if ((typ->base->form == Array) && (typ->base->len < 0)) {
            ORS_Mark("dyn array not allowed");
        }
    } else if (sym == ORS_comma) {
        ORS_Get(&sym);
        ArrayType(&typ->base);
    } else {
        ORS_Mark("missing OF");
        typ->base = intType;
    }
    
    typ->size = (len * typ->base->size + 3) / 4 * 4;
    typ->form = Array;
    typ->len = len;
    *type = typ;
}

static void RecordType(ORB_Type **type) {
    ORB_Object *obj, *obj0, *new_obj, *bot, *base;
    ORB_Type *typ, *tp;
    LONGINT offset, off, n;
    
    typ = (ORB_Type*)malloc(sizeof(ORB_Type));
    typ->form = NoTyp;
    typ->base = NULL;
    typ->mno = -level;
    typ->nofpar = 0;
    offset = 0;
    bot = NULL;
    
    if (sym == ORS_lparen) {
        ORS_Get(&sym);
        if (level != 0) {
            ORS_Mark("extension of local types not implemented");
        }
        if (sym == ORS_ident) {
            qualident(&base);
            if (base->class == Typ) {
                if (base->type->form == Record) {
                    typ->base = base->type;
                } else {
                    typ->base = intType;
                    ORS_Mark("invalid extension");
                }
                typ->nofpar = typ->base->nofpar + 1;
                bot = typ->base->dsc;
                offset = typ->base->size;
            } else {
                ORS_Mark("type expected");
            }
        } else {
            ORS_Mark("ident expected");
        }
        Check(ORS_rparen, "no )");
    }
    
    while (sym == ORS_ident) {
        n = 0;
        obj = bot;
        while (sym == ORS_ident) {
            obj0 = obj;
            while ((obj0 != NULL) && (strcmp(obj0->name, ORS_id) != 0)) {
                obj0 = obj0->next;
            }
            if (obj0 != NULL) {
                ORS_Mark("mult def");
            }
            new_obj = (ORB_Object*)malloc(sizeof(ORB_Object));
            strcpy(new_obj->name, ORS_id);
            new_obj->class = Fld;
            new_obj->next = obj;
            obj = new_obj;
            n++;
            ORS_Get(&sym);
            CheckExport(&new_obj->expo);
            if ((sym != ORS_comma) && (sym != ORS_colon)) {
                ORS_Mark("comma expected");
            } else if (sym == ORS_comma) {
                ORS_Get(&sym);
            }
        }
        Check(ORS_colon, "colon expected");
        Type(&tp);
        if ((tp->form == Array) && (tp->len < 0)) {
            ORS_Mark("dyn array not allowed");
        }
        if (tp->size > 1) {
            offset = (offset + 3) / 4 * 4;
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
        if (sym == ORS_semicolon) {
            ORS_Get(&sym);
        } else if (sym != ORS_end) {
            ORS_Mark(" ; or END");
        }
    }
    
    typ->form = Record;
    typ->dsc = bot;
    typ->size = (offset + 3) / 4 * 4;
    *type = typ;
}

static void FPSection(LONGINT *adr, INTEGER *nofpar) {
    ORB_Object *obj, *first;
    ORB_Type *tp;
    LONGINT parsize;
    INTEGER cl;
    BOOLEAN rdo;
    
    if (sym == ORS_var) {
        ORS_Get(&sym);
        cl = Par;
    } else {
        cl = Var;
    }
    
    IdentList(cl, &first);
    FormalType(&tp, 0);
    rdo = FALSE;
    
    if ((cl == Var) && (tp->form >= Array)) {
        cl = Par;
        rdo = TRUE;
    }
    
    if (((tp->form == Array) && (tp->len < 0)) || (tp->form == Record)) {
        parsize = 2 * 4;
    } else {
        parsize = 4;
    }
    
    obj = first;
    while (obj != NULL) {
        (*nofpar)++;
        obj->class = cl;
        obj->type = tp;
        obj->rdo = rdo;
        obj->lev = level;
        obj->val = *adr;
        *adr = *adr + parsize;
        obj = obj->next;
    }
    
    if (*adr >= 52) {
        ORS_Mark("too many parameters");
    }
}

static void ProcedureType(ORB_Type *ptype, LONGINT *parblksize) {
    ORB_Object *obj;
    LONGINT size;
    INTEGER nofpar;
    
    ptype->base = noType;
    size = *parblksize;
    nofpar = 0;
    ptype->dsc = NULL;
    
    if (sym == ORS_lparen) {
        ORS_Get(&sym);
        if (sym == ORS_rparen) {
            ORS_Get(&sym);
        } else {
            FPSection(&size, &nofpar);
            while (sym == ORS_semicolon) {
                ORS_Get(&sym);
                FPSection(&size, &nofpar);
            }
            Check(ORS_rparen, "no )");
        }
        
        if (sym == ORS_colon) {
            ORS_Get(&sym);
            if (sym == ORS_ident) {
                qualident(&obj);
                ptype->base = obj->type;
                if (!((obj->class == Typ) && 
                      (((obj->type->form >= Byte) && (obj->type->form <= Pointer)) ||
                      (obj->type->form == Proc)))) {
                    ORS_Mark("illegal function type");
                }
            } else {
                ORS_Mark("type identifier expected");
            }
        }
    }
    
    ptype->nofpar = nofpar;
    *parblksize = size;
}

static void FormalType0(ORB_Type **typ, INTEGER dim) {
    ORB_Object *obj;
    LONGINT dmy;
    
    if (sym == ORS_ident) {
        qualident(&obj);
        if (obj->class == Typ) {
            *typ = obj->type;
        } else {
            ORS_Mark("not a type");
            *typ = intType;
        }
    } else if (sym == ORS_array) {
        ORS_Get(&sym);
        Check(ORS_of, "OF ?");
        if (dim >= 1) {
            ORS_Mark("multi-dimensional open arrays not implemented");
        }
        *typ = (ORB_Type*)malloc(sizeof(ORB_Type));
        (*typ)->form = Array;
        (*typ)->len = -1;
        (*typ)->size = 2 * 4;
        FormalType(&(*typ)->base, dim + 1);
    } else if (sym == ORS_procedure) {
        ORS_Get(&sym);
        OpenScope();
        *typ = (ORB_Type*)malloc(sizeof(ORB_Type));
        (*typ)->form = Proc;
        (*typ)->size = 4;
        dmy = 0;
        ProcedureType(*typ, &dmy);
        (*typ)->dsc = topScope->next;
        CloseScope();
    } else {
        ORS_Mark("identifier expected");
        *typ = noType;
    }
}

static void CheckRecLevel(INTEGER lev) {
    if (lev != 0) {
        ORS_Mark("ptr base must be global");
    }
}

static void Type0(ORB_Type **type) {
    LONGINT dmy;
    ORB_Object *obj;
    PtrBase *ptbase;
    
    *type = intType;
    if ((sym != ORS_ident) && (sym < ORS_array)) {
        ORS_Mark("not a type");
        do {
            ORS_Get(&sym);
        } while ((sym != ORS_ident) && (sym < ORS_array));
    }
    
    if (sym == ORS_ident) {
        qualident(&obj);
        if (obj->class == Typ) {
            if ((obj->type != NULL) && (obj->type->form != NoTyp)) {
                *type = obj->type;
            }
        } else {
            ORS_Mark("not a type or undefined");
        }
    } else if (sym == ORS_array) {
        ORS_Get(&sym);
        ArrayType(type);
    } else if (sym == ORS_record) {
        ORS_Get(&sym);
        RecordType(type);
        Check(ORS_end, "no END");
    } else if (sym == ORS_pointer) {
        ORS_Get(&sym);
        Check(ORS_to, "no TO");
        *type = (ORB_Type*)malloc(sizeof(ORB_Type));
        (*type)->form = Pointer;
        (*type)->size = 4;
        (*type)->base = intType;
        
        if (sym == ORS_ident) {
            obj = thisObj();
            if (obj != NULL) {
                if ((obj->class == Typ) && 
                    ((obj->type->form == Record) || (obj->type->form == NoTyp))) {
                    CheckRecLevel(obj->lev);
                    (*type)->base = obj->type;
                } else if (obj->class == Mod) {
                    ORS_Mark("external base type not implemented");
                } else {
                    ORS_Mark("no valid base type");
                }
            } else {
                CheckRecLevel(level);
                ptbase = (PtrBase*)malloc(sizeof(PtrBase));
                strcpy(ptbase->name, ORS_id);
                ptbase->type = *type;
                ptbase->next = pbsList;
                pbsList = ptbase;
            }
            ORS_Get(&sym);
        } else {
            Type(type);
            if (((*type)->base->form != Record) || ((*type)->base->typobj == NULL)) {
                ORS_Mark("must point to named record");
            }
            CheckRecLevel(level);
        }
    } else if (sym == ORS_procedure) {
        ORS_Get(&sym);
        OpenScope();
        *type = (ORB_Type*)malloc(sizeof(ORB_Type));
        (*type)->form = Proc;
        (*type)->size = 4;
        dmy = 0;
        ProcedureType(*type, &dmy);
        (*type)->dsc = topScope->next;
        CloseScope();
    } else {
        ORS_Mark("illegal type");
    }
}

static void Declarations(LONGINT *varsize) {
    ORB_Object *obj, *first;
    ORG_Item x;
    ORB_Type *tp;
    PtrBase *ptbase;
    BOOLEAN expo;
    ORS_Ident id;
    
    pbsList = NULL;
    if ((sym < ORS_const) && (sym != ORS_end) && (sym != ORS_return)) {
        ORS_Mark("declaration?");
        do {
            ORS_Get(&sym);
        } while ((sym < ORS_const) && (sym != ORS_end) && (sym != ORS_return));
    }
    
    if (sym == ORS_const) {
        ORS_Get(&sym);
        while (sym == ORS_ident) {
            strcpy(id, ORS_id);
            ORS_Get(&sym);
            CheckExport(&expo);
            if (sym == ORS_eql) {
                ORS_Get(&sym);
            } else {
                ORS_Mark("= ?");
            }
            expression(&x);
            if ((x.type->form == String) && (x.b == 2)) {
                ORG_StrToChar(&x);
            }
            NewObj(&obj, id, ORS_const);
            obj->expo = expo;
            if (x.mode == ORS_const) {
                obj->val = x.a;
                obj->lev = x.b;
                obj->type = x.type;
            } else {
                ORS_Mark("expression not constant");
                obj->type = intType;
            }
            Check(ORS_semicolon, "; missing");
        }
    }
    
    if (sym == ORS_type) {
        ORS_Get(&sym);
        while (sym == ORS_ident) {
            strcpy(id, ORS_id);
            ORS_Get(&sym);
            CheckExport(&expo);
            if (sym == ORS_eql) {
                ORS_Get(&sym);
            } else {
                ORS_Mark("=?");
            }
            Type(&tp);
            NewObj(&obj, id, Typ);
            obj->type = tp;
            obj->expo = expo;
            obj->lev = level;
            if (tp->typobj == NULL) {
                tp->typobj = obj;
            }
            if (expo && (obj->type->form == Record)) {
                obj->exno = exno;
                exno++;
            } else {
                obj->exno = 0;
            }
            if (tp->form == Record) {
                ptbase = pbsList;
                while (ptbase != NULL) {
                    if (strcmp(obj->name, ptbase->name) == 0) {
                        ptbase->type->base = obj->type;
                    }
                    ptbase = ptbase->next;
                }
                if (level == 0) {
                    ORG_BuildTD(tp, &dc);
                }
            }
            Check(ORS_semicolon, "; missing");
        }
    }
    
    if (sym == ORS_var) {
        ORS_Get(&sym);
        while (sym == ORS_ident) {
            IdentList(Var, &first);
            Type(&tp);
            obj = first;
            while (obj != NULL) {
                obj->type = tp;
                obj->lev = level;
                if (tp->size > 1) {
                    *varsize = ((*varsize + 3) / 4) * 4;
                }
                obj->val = *varsize;
                *varsize = *varsize + obj->type->size;
                if (obj->expo) {
                    obj->exno = exno;
                    exno++;
                }
                obj = obj->next;
            }
            Check(ORS_semicolon, "; missing");
        }
    }
    
    *varsize = ((*varsize + 3) / 4) * 4;
    ptbase = pbsList;
    while (ptbase != NULL) {
        if (ptbase->type->base->form == Int) {
            ORS_Mark("undefined pointer base of");
        }
        ptbase = ptbase->next;
    }
    if ((sym >= ORS_const) && (sym <= ORS_var)) {
        ORS_Mark("declaration in bad order");
    }
}

static void ProcedureDecl(void) {
    ORB_Object *proc;
    ORB_Type *type;
    ORS_Ident procid;
    ORG_Item x;
    LONGINT locblksize, parblksize, L;
    BOOLEAN int_proc;
    
    int_proc = FALSE;
    ORS_Get(&sym);
    if (sym == ORS_times) {
        ORS_Get(&sym);
        int_proc = TRUE;
    }
    if (sym == ORS_ident) {
        strcpy(procid, ORS_id);
        ORS_Get(&sym);
        NewObj(&proc, ORS_id, ORS_const);
        if (int_proc) {
            parblksize = 12;
        } else {
            parblksize = 4;
        }
        type = (ORB_Type*)malloc(sizeof(ORB_Type));
        type->form = Proc;
        type->size = 4;
        proc->type = type;
        proc->val = -1;
        proc->lev = level;
        CheckExport(&proc->expo);
        if (proc->expo) {
            proc->exno = exno;
            exno++;
        }
        OpenScope();
        level++;
        type->base = noType;
        ProcedureType(type, &parblksize);
        Check(ORS_semicolon, "no ;");
        locblksize = parblksize;
        Declarations(&locblksize);
        proc->val = ORG_Here() * 4;
        proc->type->dsc = topScope->next;
        if (sym == ORS_procedure) {
            L = 0;
            ORG_FJump(&L);
            do {
                ProcedureDecl();
                Check(ORS_semicolon, "no ;");
            } while (sym == ORS_procedure);
            ORG_FixOne(L);
            proc->val = ORG_Here() * 4;
            proc->type->dsc = topScope->next;
        }
        ORG_Enter(parblksize, locblksize, int_proc);
        if (sym == ORS_begin) {
            ORS_Get(&sym);
            StatSequence();
        }
        if (sym == ORS_return) {
            ORS_Get(&sym);
            expression(&x);
            if (type->base == noType) {
                ORS_Mark("this is not a function");
            } else if (!CompTypes(type->base, x.type, FALSE)) {
                ORS_Mark("wrong result type");
            }
        } else if (type->base->form != NoTyp) {
            ORS_Mark("function without result");
            type->base = noType;
        }
        ORG_Return(type->base->form, &x, locblksize, int_proc);
        CloseScope();
        level--;
        Check(ORS_end, "no END");
        if (sym == ORS_ident) {
            if (strcmp(ORS_id, procid) != 0) {
                ORS_Mark("no match");
            }
            ORS_Get(&sym);
        } else {
            ORS_Mark("no proc id");
        }
    } else {
        ORS_Mark("proc id expected");
    }
}

static void ORP_Import(void) {
    ORS_Ident impid, impid1;
    
    if (sym == ORS_ident) {
        strcpy(impid, ORS_id);
        ORS_Get(&sym);
        if (sym == ORS_becomes) {
            ORS_Get(&sym);
            if (sym == ORS_ident) {
                strcpy(impid1, ORS_id);
                ORS_Get(&sym);
            } else {
                ORS_Mark("id expected");
                strcpy(impid1, impid);
            }
        } else {
            strcpy(impid1, impid);
        }
        Import(impid, impid1);
    } else {
        ORS_Mark("id expected");
    }
}

static void ORP_Module(void) {
    LONGINT key;
    
    Texts_WriteString(&W, "  compiling ");
    ORS_Get(&sym);
    if (sym == ORS_module) {
        ORS_Get(&sym);
        if (sym == ORS_times) {
            version = 0;
            dc = 8;
            Texts_WriteChar(&W, '*');
            ORS_Get(&sym);
        } else {
            dc = 0;
            version = 1;
        }
        // ORS_Init should be called before this function
        OpenScope();
        if (sym == ORS_ident) {
            strcpy(modid, ORS_id);
            ORS_Get(&sym);
            Texts_WriteString(&W, modid);
            Texts_Append(Oberon_Log, W.buf);
            Texts_ClearWriter(&W);
        } else {
            ORS_Mark("identifier expected");
        }
        Check(ORS_semicolon, "no ;");
        level = 0;
        exno = 1;
        key = 0;
        if (sym == ORS_import) {
                ORS_Get(&sym);
            ORP_Import();
            while (sym == ORS_comma) {
                ORS_Get(&sym);
                ORP_Import();
            }
            Check(ORS_semicolon, "; missing");
        }
        ORG_Open(version);
        Declarations(&dc);
        ORG_SetDataSize(((dc + 3) / 4) * 4);
        while (sym == ORS_procedure) {
            ProcedureDecl();
            Check(ORS_semicolon, "no ;");
        }
        ORG_Header();
        if (sym == ORS_begin) {
            ORS_Get(&sym);
            StatSequence();
        }
        Check(ORS_end, "no END");
        if (sym == ORS_ident) {
            if (strcmp(ORS_id, modid) != 0) {
                ORS_Mark("no match");
            }
            ORS_Get(&sym);
        } else {
            ORS_Mark("identifier missing");
        }
        if (sym != ORS_period) {
            ORS_Mark("period missing");
        } else {
            ORS_Get(&sym);  // Consume the period
            if (sym != ORS_eof) {
                ORS_Mark("garbage after module");
            }
        }
        if ((ORS_errcnt == 0) && (version != 0)) {
            Export(modid, &newSF, &key);
            if (newSF) {
                Texts_WriteString(&W, " new symbol file");
            }
        }
        if (ORS_errcnt == 0) {
            ORG_Close(modid, key, exno);
            Texts_WriteInt(&W, ORG_pc, 6);
            Texts_WriteInt(&W, dc, 6);
            Texts_WriteHex(&W, key);
        } else {
            Texts_WriteLn(&W);
            Texts_WriteString(&W, "compilation FAILED");
        }
        Texts_WriteLn(&W);
        Texts_Append(Oberon_Log, W.buf);
        Texts_ClearWriter(&W);
        CloseScope();
        pbsList = NULL;
    } else {
        ORS_Mark("must start with MODULE");
    }
}


void ORP_Compile(const char *filename, bool forceNewSF) {
    Texts_Text *T;
    
    if (!filename) {
        Texts_WriteString(&W, "Error: No filename provided");
        Texts_WriteLn(&W);
        Texts_Append(Oberon_Log, W.buf);
        Texts_ClearWriter(&W);
        return;
    }
    
    newSF = forceNewSF;
    
    Texts_WriteString(&W, "Compiling ");
    Texts_WriteString(&W, (char*)filename);
    Texts_WriteLn(&W);
    Texts_Append(Oberon_Log, W.buf);
    Texts_ClearWriter(&W);
    
    T = (Texts_Text*)malloc(sizeof(Texts_Text));
    if (!T) {
        Texts_WriteString(&W, "Error: Memory allocation failed");
        Texts_WriteLn(&W);
        Texts_Append(Oberon_Log, W.buf);
        Texts_ClearWriter(&W);
        return;
    }
    
    Texts_Open(T, (char*)filename);
    if (T->len > 0) {
        ORS_Init(T, 0);
        ORP_Module();
    } else {
        Texts_WriteString(&W, "Error: File not found or empty: ");
        Texts_WriteString(&W, (char*)filename);
        Texts_WriteLn(&W);
        Texts_Append(Oberon_Log, W.buf);
        Texts_ClearWriter(&W);
    }
    
    if (T) {
        Texts_Close(T);
        free(T);
    }
}

int main(int argc, char **argv) {
    const char *filename = NULL;
    bool forceNewSF = false;
    int i;
    
    // Parse command line arguments
    if (argc < 2) {
        printf("Usage: %s <module.Mod> [/s]\n", argv[0]);
        printf("  /s  Force new symbol file\n");
        return 1;
    }
    
    filename = argv[1];
    
    // Check for /s option
    for (i = 2; i < argc; i++) {
        if (strcmp(argv[i], "/s") == 0) {
            forceNewSF = true;
        }
    }
    
    // Initialize the compiler
    Texts_OpenWriter(&W);
    Texts_WriteString(&W, "OR Compiler  8.3.2020");
    Texts_WriteLn(&W);
    Texts_Append(Oberon_Log, W.buf);
    Texts_ClearWriter(&W);
    
    // Initialize ORB (symbol table)
    ORB_Initialize();  // Create basic types (INTEGER, BOOLEAN, etc.)
    ORB_Init();
    
    // Set up dummy object for parser
    dummy = (ORB_Object*)malloc(sizeof(ORB_Object));
    dummy->class = Var;
    dummy->type = intType;
    
    // Set up function pointers for parser
    expression = expression0;
    Type = Type0;
    FormalType = FormalType0;
    
    // Initialize ORG (code generator)
    ORG_Init();

    // Compile the module
    ORP_Compile(filename, forceNewSF);
    
    // Check for errors
    if (ORS_errcnt > 0) {
        printf("Compilation failed with %d errors\n", ORS_errcnt);
        return 1;
    }
    
    printf("Compilation successful\n");
    return 0;
}
