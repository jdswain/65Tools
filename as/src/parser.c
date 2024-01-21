#include "as.h"

#include <string.h>
#include <stdio.h>

#include "memory.h"
#include "scanner.h"
#include "buffered_file.h"
#include "value.h"
#include "interp.h"
#include "codegen.h"
#include "oberongen.h"

/* Parser variables */

char *decl_name;
Object decl_value;
FuncDef *func;

/* Oberon specific */

bool new_symbol_file;
int exno;

void parseassignment(Object *ident, Symbol *sym);
void parse_block(Symbol *sym);

/* macros */
void exec_macro(const char *name, Object **params)
{
  // Object *macro = dynmap_get(&macros, &num_macros, name);
  
}
/*
void start_segment(const char* name)
{
}

void end_segment(void)
{
}

void start_section(const char *name)
{
}

void end_section(void)
{
}

void start_function(const char *name)
{
}

void end_function(void)
{
}
*/

bool expect(Symbol *sym, Symbol expected)
{
  if (*sym == expected) { scanner_get(sym); return true; }
  as_error("Expected '%s' but found '%s'", token_to_string(expected), token_to_string(*sym));
  scanner_get(sym); return false;
}

void parse_expression(Symbol *sym, bool is_local);

/* factor = integer | real | CharConstant | string | ident [ActualParameters] | "(" expression ")" | "~" factor */
void parse_factor(Symbol *sym, bool is_local)
{
  Object* v;
  
  switch (*sym) {
  case sINTEGER:
  case sCHAR:
	v = object_new(Const, typeInt);
	v->int_val = ival;
    interp_add(OpPush, v);
	//	printf("OpPush Int %d\n", v->int_val);
	object_release(v);
    scanner_get(sym);
    break;
    
  case sREAL:
	v = object_new(Const, typeReal);
	v->real_val = ival;
    interp_add(OpPush, v);
	object_release(v);
    scanner_get(sym);
    break;

  case sSTRING:
	v = object_new(Const, typeString);
    v->string_val = as_strdup(id);
    interp_add(OpPush, v);
	object_release(v);
    scanner_get(sym);
    break;

  case sPERIOD:
	scanner_get(sym);
	expect(sym, sIDENT);
	is_local = true;
  case sIDENT:
	v = object_new(Const, typeString);
    v->string_val = as_strdup(id);
	v->is_local = is_local;
	//	printf("OpPush Ident %s\n", v->string_val);
    interp_add(OpPushVar, v);
	object_release(v);
    scanner_get(sym);
    break;

  case sLPAREN:
    scanner_get(sym);
    parse_expression(sym, false);
    if (*sym == sRPAREN)
      scanner_get(sym);
    else
      as_error("Unbalanced parenthesis");
    break;

  case sNOT:
    scanner_get(sym);
    parse_factor(sym, false);
    interp_add(OpNot, 0);
    break;

  case sLSS:
    scanner_get(sym);
    parse_factor(sym, false);
    interp_add(OpLowByte, 0);
    break;

  case sGTR:
    scanner_get(sym);
    parse_factor(sym, false);
    interp_add(OpHighByte, 0);
    break;

  case sCARET:
    scanner_get(sym);
    parse_factor(sym, false);
    interp_add(OpBankByte, 0);
    break;

  default:
    as_error("Unexpected token: %s", id);
    scanner_get(sym);
    break;
  }
}

/* term = factor {MulOperator factor} */
/* MulOperator = "*" | "/" | div | mod | "&" */
void parse_term(Symbol *sym, bool is_local)
{
  bool done = false;
  
  parse_factor(sym, is_local);

  do {
    switch (*sym) {
    case sAST:
      scanner_get(sym);
      parse_factor(sym, false);
      interp_add(OpMul, 0);
      break;
      
    case sSLASH:
      scanner_get(sym);
      parse_factor(sym, false);
      interp_add(OpDiv, 0);
      break;
      
    case sDIV:
      scanner_get(sym);
      parse_factor(sym, false);
      interp_add(OpIDiv, 0);
      break;
      
    case sMOD:
      scanner_get(sym);
      parse_factor(sym, false);
      interp_add(OpMod, 0);
      break;
      
    case sAMPERSAND:
      scanner_get(sym);
      parse_factor(sym, false);
      interp_add(OpAnd, 0);
      break;
      
    default:
      done = true;
    }
  } while (!done);
}

/* SimpleExpression = ["+"|"-"] term {AddOperator term} */
/* AddOperator = "+" | "-" | or */
void parse_simple_expression(Symbol *sym, bool is_local)
{
  bool negate = false;
  bool done = false;
  
  if (*sym == sPLUS) {
    scanner_get(sym);
  } else if (*sym == sMINUS) {
    negate = true;
    scanner_get(sym);
  }
  parse_term(sym, is_local);

  do {
    switch (*sym) {
    case sPLUS:
      scanner_get(sym);
      parse_term(sym, false);
      interp_add(OpAdd, 0);
      break;
    
    case sMINUS:
      scanner_get(sym);
      parse_term(sym, false);
      interp_add(OpSub, 0);
      break;

    case sBARC:
      scanner_get(sym);
      parse_term(sym, false);
      interp_add(OpOr, 0);
      break;

    default:
      done = true;
      break;
    }
  } while (!done);

  if (negate) {
    interp_add(OpNeg, 0);
  }
}

/* expression = SimpleExpression [relation SimpleExpression] */
/* relation = "==" | "!=" | "<" | "<=" | ">" | ">=" */
void parse_expression(Symbol *sym, bool is_local)
{
  parse_simple_expression(sym, is_local);

  switch (*sym) {
  case sEQL:
    scanner_get(sym);
    parse_simple_expression(sym, false);
    interp_add(OpEqual, 0);
    break;

  case sNEQ:
    scanner_get(sym);
    parse_simple_expression(sym, false);
    interp_add(OpNotEqual, 0);
    break;

  case sLSS:
    scanner_get(sym);
    parse_simple_expression(sym, false);
    interp_add(OpLessThan, 0);
    break;

  case sLEQ:
    scanner_get(sym);
    parse_simple_expression(sym, false);
    interp_add(OpLessThanEqual, 0);
    break;

  case sGTR:
    scanner_get(sym);
    parse_simple_expression(sym, false);
    interp_add(OpGreaterThan, 0);
    break;

  case sGEQ:
    scanner_get(sym);
    parse_simple_expression(sym, false);
    interp_add(OpGreaterThanEqual, 0);
    break;

  case sLEFT_SHIFT:
    scanner_get(sym);
    parse_simple_expression(sym, false);
    interp_add(OpLeftShift, 0);
    break;

  case sRIGHT_SHIFT:
    scanner_get(sym);
    parse_simple_expression(sym, false);
    interp_add(OpRightShift, 0);
    break;
    
  default:
    break;

  }
}

void parse_assignment(Object *ident, Symbol *sym)
{
  // ToDo: += etc.
  if (*sym != sBECOMES) return as_error("Expected '='");
  scanner_get(sym);
  parse_expression(sym, false); // or string
  interp_add(OpPopVar, ident);
}

void parse_if(Symbol *sym)
{
  scanner_get(sym);
  parse_expression(sym, false);
  if (*sym == sBLOCKSTART) {
    interp_add(OpIfBegin, 0);
    scanner_get(sym);
    parse_block(sym);
    scanner_get(sym);
    if (*sym == sELSE) {
      scanner_get(sym);
      interp_add(OpElseBegin, 0);
      parse_block(sym);
      scanner_get(sym);
    }
  } else {
    as_error("Malformed IF expression");
  }
}

void parse_case(Symbol *sym)
{
}

void parse_while(Symbol *sym)
{
}

void parse_repeat(Symbol *sym)
{
}

  /* x Accumulator,                   /\* A *\/ */

  /* x BlockMove,                     /\* #srcbk,#destbk *\/ */
  /* x Immediate,                     /\* #const *\/ */

  /* x Implied,                       /\* *\/ */
  /* x Stack */

  /* DirectPage,                    /\* dp *\/ */
  /* DirectPageIndexedX,            /\* dp,X *\/ */
  /* DirectPageIndexedY,            /\* dp,Y *\/ */
  /* Absolute,                      /\* addr *\/ */
  /* AbsoluteIndexedX,              /\* addr,X *\/ */
  /* AbsoluteIndexedY,              /\* addr,Y *\/ */
  /* AbsoluteLong,                  /\* long *\/ */
  /* AbsoluteLongIndexedX,          /\* long,X *\/ */
  /* StackRelative,                 /\* sr,S *\/ */
  /* BlockMove,                     /\* srcbk,destbk *\/ */
  /* ProgramCounterRelative,        /\* nearlabel *\/ */
  /* ProgramCounterRelativeLong,    /\* label *\/ */

  /* DirectPageIndirect,            /\* (dp) *\/ */
  /* DirectPageIndexedIndirectX,    /\* (dp,X) *\/ */
  /* DirectPageIndirectIndexedY,    /\* (dp),Y *\/ */
  /* AbsoluteIndexedIndirect,       /\* (addr,X) *\/ */
  /* AbsoluteIndirect,              /\* (addr) *\/ */
  /* StackRelativeIndirectIndexedY, /\* (sr,S),Y *\/ */

  /* DirectPageIndirectLong,        /\* [dp] *\/ */
  /* DirectPageIndirectLongIndexedY,/\* [dp],Y *\/ */
  /* AbsoluteIndirectLong,          /\* [addr] *\/ */
    

  /* StackDirectPageIndirect,       /\* dp *\/ */
  /* StackProgramCounterRelative,   /\* label *\/ */

void parse_instr(Symbol *sym)
{
  Symbol instr = *sym;
  
  bool longAddr = false;
  bool is_local = false;
  
  scanner_get(sym);
  // Address modifier, or local
  enum Modifier modifier = MNone;
  if (*sym == sPERIOD) {
    scanner_get(sym);
	if (strlen(id) == 1) {
	  switch (id[0] & 0x5f) {
	  case 'B': modifier = MByte; scanner_get(sym); break;
	  case 'D': modifier = MDirect; scanner_get(sym); break;
	  case 'W': modifier = MWord; scanner_get(sym); break;
	  case 'A': modifier = MAbsolute; scanner_get(sym); break;
	  case 'L': modifier = MLong; scanner_get(sym); break;
	  default: modifier = MNone; is_local = true; break;
	  }
    } else {
	  is_local = true;
	}
  }
  
  switch (*sym) {
    
    /* Immediate or BlockMove */
  case sHASH:
    scanner_get(sym);
    parse_expression(sym, false);
    if (*sym == sCOMMA) { /* BlockMove */
      scanner_get(sym);
      if (*sym == sHASH) scanner_get(sym);
      parse_expression(sym, false);
      interp_add_instr(instr, BlockMove, modifier);
    } else { /* Immediate */
      interp_add_instr(instr, Immediate, modifier);
    }
    break;

    /* Accumulator */
  case sREGA:
    scanner_get(sym);
    interp_add_instr(instr, Accumulator, modifier);
    break;

    /* Implied, Accumulator, or Stack */
  case sSTATESEP:
    interp_add_instr(instr, Implied, modifier);
    break;
    

  case sLSQ:
  case sLPAREN:
    if (*sym == sLSQ) longAddr = true;
    scanner_get(sym);
    parse_expression(sym, false);
    if (((*sym == sRPAREN) && !longAddr) || ((*sym == sRSQ) && longAddr)) {
      scanner_get(sym);
      if (*sym == sCOMMA) {
        scanner_get(sym);
        if (*sym == sREGY) {
          scanner_get(sym);
          if (*sym == sSTATESEP) {
	    interp_add_instr(instr, DirectPageIndirectIndexedY, modifier);
          }
        } else if (*sym == sREGX) {
          scanner_get(sym);
          if (*sym == sSTATESEP) {
	    interp_add_instr(instr, DirectPageIndexedIndirectX, modifier);
          }
        } 
      } else if (*sym == sSTATESEP) {
        interp_add_instr(instr, (longAddr?AbsoluteIndirectLong:AbsoluteIndirect), modifier);
      } 
    } else if (*sym == sCOMMA) {
      scanner_get(sym);
      if (*sym == sREGX) {
        scanner_get(sym);
        if (((*sym == sRPAREN) && !longAddr) || ((*sym == sRSQ) && longAddr)) {
          scanner_get(sym);
          if (*sym == sSTATESEP) {
            interp_add_instr(instr, AbsoluteIndexedIndirect, modifier);
          }
        }
      } else if (*sym == sREGS) {
        scanner_get(sym);
        if (*sym == sRPAREN) {
          scanner_get(sym);
          if (*sym == sCOMMA) {
            scanner_get(sym);
            if (*sym == sREGY) {
              scanner_get(sym);
              if (*sym == sSTATESEP) {
		interp_add_instr(instr, StackRelativeIndirectIndexedY, modifier);
              }
            }
          }
        }
      }    
    }
    break;

  default:
    parse_expression(sym, is_local);
    if (*sym == sSTATESEP) {
      interp_add_instr(instr, Absolute, modifier);
    } else if (*sym == sCOMMA) {
      scanner_get(sym);
      if (*sym == sREGX) {
        scanner_get(sym);
        if (*sym == sSTATESEP) {
          // Process IndexedX
		  interp_add_instr(instr, AbsoluteIndexedX, modifier);
        }
      } else if (*sym == sREGY) {
        scanner_get(sym);
        if (*sym == sSTATESEP) {
          // Process IndexedY
		  interp_add_instr(instr, AbsoluteIndexedY, modifier);
        }
      } else if (*sym == sREGS) {
        scanner_get(sym);
        if (*sym == sSTATESEP) {
          interp_add_instr(instr, StackRelative, modifier);
        }
      } else {
        parse_expression(sym, false);
        if (*sym == sSTATESEP) {
		  // Two values, could be Block, BitZeroPage, BitAbsolute
		  interp_add_instr(instr, BlockMove, modifier);
        } else if (*sym == sCOMMA) {
		  scanner_get(sym);
		  parse_expression(sym, false);
		  if (*sym == sSTATESEP) {
			// Three values, could be BitZeroPageRelative or BitAbsoluteRelative
			interp_add_instr(instr, BitAbsoluteRelative, modifier);
		  }
		}
      }
    }
  }
}

int parse_list(Symbol *sym)
{
  int c = 0;
  do {
    if (*sym == sCOMMA) scanner_get(sym);
    if (*sym != sSTATESEP) {
      parse_expression(sym, false);
      c++;
    }
  } while (*sym == sCOMMA);
  return c;
}

int recursive_params(Symbol *sym)
{
  Object *v = object_new(Const, typeString);
  int r = 0;
  if (*sym == sCOMMA) scanner_get(sym);
  if (*sym != sBLOCKSTART) {
    if (*sym == sIDENT) {
      v->string_val = as_strdup(id);
      scanner_get(sym);
      r = recursive_params(sym) + 1;
      interp_add(OpPopVar, v);
	  printf("  param: %s\n", v->string_val);
    }
  }
  object_release(v);
  return r;
}

void parse_message(Symbol *sym, enum OpType type)
{
  int c = parse_list(sym);
  if (c > 0) {
	Object *v = object_new(Const, typeString);
    v->int_val = c;
    interp_add(type, v);
	object_release(v);
  }
}

void parse_data(Symbol *sym, enum Modifier modifier)
{
  int c = parse_list(sym);
  if (c > 0) {
	Object *v = object_new(Const, typeInt);
    v->int_val = c;
    switch (modifier) {
    case MByte: interp_add(OpByte, v); break;
    case MWord: interp_add(OpWord, v); break;
    case MAbsolute: interp_add(OpWord, v); break;
    case MLong: interp_add(OpLong, v); break;
    case MFloat: interp_add(OpFloat, v); break;
    case MDirect: interp_add(OpDouble, v); break;
    case MZero: interp_add(OpByte, v); break;
    case MBit7: interp_add(OpByte, v); break;
    default: interp_add(OpByte, v); break;
    }
	object_release(v);
  }
}

void parse_text(Symbol *sym, enum Modifier modifier)
{
  int c = parse_list(sym);
  if (c > 0) {
	Object *v = object_new(Const, typeInt);
    v->int_val = c;
    switch (modifier) {
    case MByte: interp_add(OpText, v); break;
    case MWord: interp_add(OpText, v); break;
    case MAbsolute: interp_add(OpText, v); break;
    case MLong: interp_add(OpTextLen, v); break;
    case MFloat: interp_add(OpText, v); break;
    case MDirect: interp_add(OpText, v); break;
    case MZero: interp_add(OpTextZero, v); break;
    case MBit7: interp_add(OpTextBit7, v); break;
    default: interp_add(OpText, v); break;
    }
	object_release(v);
  }
}

void parse_fill(Symbol *sym, Modifier modifier)
{
  int c = parse_list(sym);
  if (c > 0) {
	Object *v = object_new(Const, typeInt);
    v->int_val = c;
    switch (modifier) {
    case MByte: interp_add(OpFillByte, v); break;
    case MWord: interp_add(OpFillWord, v); break;
    case MAbsolute: interp_add(OpFillWord, v); break;
    case MLong: interp_add(OpFillLong, v); break;
    case MFloat: interp_add(OpFillByte, v); break;
    case MDirect: interp_add(OpFillByte, v); break;
    case MZero: interp_add(OpFillByte, v); break;
    case MBit7: interp_add(OpFillByte, v); break;
    default: interp_add(OpFillByte, v); break;
    }
	object_release(v);
  }
}

void parse_title(Symbol *sym)
{
  int c = parse_list(sym);
  if (c > 0) {
    Object *v = object_new(Const, typeInt);
    v->int_val = c;
    interp_add(OpTitle, v);
	object_release(v);
  }
}

void parse_subheading(Symbol *sym)
{
  int c = parse_list(sym);
  if (c > 0) {
    Object *v = object_new(Const, typeInt);
    v->int_val = c;
    interp_add(OpSubheading, v);
	object_release(v);
  }
}

void parse_macro_def(Object *ident, Symbol *sym)
{
  interp_macro_begin(ident->string_val);
  if (*sym != sBLOCKSTART) {
    int r = recursive_params(sym);
	printf(" macro has %d params\n", r);
  }
  if (*sym == sBLOCKSTART) scanner_get(sym);
}

void parse_macro_call(Symbol *sym)
{
  Object *m = object_new(Macro, typeString);
  m->string_val = as_strdup(id);

  scanner_get(sym);
  printf("MACRO PRE\n");
  parse_list(sym);
  if (*sym == sSTATESEP) scanner_get(sym);

  Object *macro_scope = object_new(Const, typeMacro);
  scope_add_object(m->string_val, macro_scope);
  interp_add(OpMacroCall, m);
  printf("OpMacroCall %s\n", m->string_val);
  object_release(m);
}

/*
** ERRORIF expr, text
** SECTION name block
** SEGMENT name,attrs block
** FUNCTION
** equate
** MESSAGE text, text, ...
** DATA, DATA.b, DATA.w, DATA.l, DATA.f, DATA.d
** TEXT, TEXT.b, TEXT.0, TEXT.l
** FILL length, value
** GLOBAL symbol
** ALIGN value
*/
void parse_directive(Symbol *sym)
{
  Symbol instr = *sym;
  
  scanner_get(sym);
  // Address modifier
  enum Modifier modifier = MNone;
  if (*sym == sPERIOD) {
    scanner_get(sym);
    if (*sym == sINTEGER) {
      if (ival == 0) modifier = MZero;
      else if (ival == 7) modifier = MBit7;
      else as_error("Unknown modifier");
    } else if (*sym == sIDENT) {
      switch (id[0]) {
      case 'b':
      case 'B': modifier = MByte; break;
      case 'd':
      case 'D': modifier = MDirect; break; /* Or double */
      case 'w':
      case 'W': modifier = MWord; break;
      case 'a':
      case 'A': modifier = MAbsolute; break;
      case 'l':
      case 'L': modifier = MLong; break;
      case 'f':
      case 'F': modifier = MFloat; break;
      default: as_error("Unknown modifier"); break;
      }
    } else {
      as_error("Unknown modifier");
    }
    scanner_get(sym);
  }

  char *path;
  
  switch (instr) {
  case sINCLUDE:
    if (*sym == sSTRING) {
      path = as_strdup(id);
      scanner_get(sym);
      if (*sym != sSTATESEP) {
		as_error("Include not terminated correctly");
      } else {
		if (bf_open(path) < 0) {
		  as_error("Cannot read include file '%s'", id);
		} else {
		  scanner_start();
		  scanner_get(sym);
		}
		as_free(path);
      }
    }
    break;
  case sIMPORT:
    // ToDo: Import Directive
    break;
  case sINSERT:
    // ToDo: Insert Directive
    break;
  case sERROR:
    parse_message(sym, OpError);
    break;

  case sMESSAGE:
    parse_message(sym, OpMessage);
    break;
    
  case sSECTION:
    if (*sym == sSTRING) {
      elf_set_section(id);
      scanner_get(sym);
    }
    break;

  case sDATA:
    parse_data(sym, modifier);
    break;

  case sBYTE:
    parse_data(sym, MByte);
    break;

  case sWORD:
    parse_data(sym, MWord);
    break;

  case sLONG:
    parse_data(sym, MLong);
    break;

  case sFLOAT:
    parse_data(sym, MFloat);
    break;

  case sDOUBLE:
    parse_data(sym, MDouble);
    break;
     
  case sTEXT:
    parse_text(sym, modifier);
    break;
    
  case sFILL:
    parse_fill(sym, modifier);
    break;

  case sSUBHEADING:
    parse_subheading(sym);
    break;

  case sTITLE:
	parse_title(sym);
	break;
	
  case sPAGE:
	interp_add(OpPageBreak, 0);
	break;
	
  default:
    as_error("Directive not implemented: %s", token_to_string(*sym));
    break;
    
  }
}

Object *parse_ident_def(Symbol *sym)
{
  Object *result = object_new(Const, typeString);
  
  if (*sym == sPERIOD) {
    result->is_local = true;
    scanner_get(sym);
  } else {
    result->is_local = false;
  }

  if (*sym == sIDENT) {
    result->string_val = as_strdup(id);
    scanner_get(sym);
  } else {
    as_error("Expected identifier");
  }

  if (*sym == sAST) {
    // result->is_extern = true;
    scanner_get(sym);
  }

  // Colon is optional
  if (*sym == sCOLON) {
    scanner_get(sym);
  }
  
  return result;
}

bool is_macro(Symbol sym) {
  return ((sym == sIDENT) && (as_get_macro(id) != 0));
}

/*
statement  =  [ assignment | MacroDefinition | Instruction 
    IfStatement | WhileStatement | RepeatStatement | LoopStatement ]. 
*/
void parse_statement(Symbol *sym)
{
  bool is_const = true;
  bool is_local = false;
  Object *var;

  if (*sym == sSTATESEP) { scanner_get(sym); return; }
  
  if (is_instr(*sym)) {
    parse_instr(sym);
  } else if (is_directive(*sym)) {
    parse_directive(sym);
  } else if (is_macro(*sym)) {
    parse_macro_call(sym);
  } else {
    switch (*sym) {
    case sVAR:
      is_const = false;
    case sLET:
      scanner_get(sym);
      var = parse_ident_def(sym);
      var->readonly = is_const;
      // printf("Ident %s defined\n", var->string_val);
      parse_assignment(var, sym);
      object_release(var);
      break;
      
    case sPERIOD:
	  is_local = true;
    case sIDENT:
	  var = parse_ident_def(sym);
	  var->is_local = is_local;
	  if (*sym == sBECOMES) {
		parse_assignment(var, sym);
		scanner_get(sym);
	  } else if (*sym == sMACRO) {
		scanner_get(sym);
		parse_macro_def(var, sym);
		parse_block(sym);
		interp_macro_end();
		scanner_get(sym);
	  } else {
		interp_add(OpLabel, var);
		// if (is_macro(var->string_val)) {
		//  parse_macro(var->string_val, sym);
		//} else {
		if (is_instr(*sym)) {
		  parse_instr(sym);
		} else if (is_directive(*sym)) {
		  parse_directive(sym);
		}
	  }
	  object_release(var);
	  break;
      
    case sIF:
      parse_if(sym);
      break;

    case sWHILE:
      // parse_while(sym);
      break;
      
    case sREPEAT:
      // parse_repeat(sym);
      break;
      
    case sSTATESEP:
      scanner_get(sym); // Just move on
      break;

    case sBLOCKSTART:
	  Object *object = object_new(Const, typeNoType);
	  object->mode = Var;
	  scope_add_object("block_unique", object);
	  scope_push_object(object);
	  interp_add(OpScopeBegin, object);
      scanner_get(sym); 
      break;
      
    case sBLOCKEND:
      // Segment, section, macro, or just scope
	  scope_pop();
      interp_add(OpScopeEnd, 0);
      scanner_get(sym); 
      break;

    case sEOF:
      break;

    case sEND:
      break;
      
    default:
      as_error("Unexpected symbol %s", token_to_string(*sym));
      scanner_get(sym); // Move on, likely to cause cascading errors but better than loop
      break;
    }
  }
}

/*
StatementSequence  =  statement {StatementSep statement}. 
*/
void parse_block(Symbol *sym)
{
  do {
    parse_statement(sym);
  } while (*sym != sBLOCKEND);
}


/*----------------------------------------
Oberon Parser
----------------------------------------*/

/* Forward declarations */
void parse_oberon_statementsequence(Symbol *sym);
Item *parse_oberon_expression(Symbol *sym);
Type *parse_oberon_formaltype(Symbol *sym, int dim);

Object *parse_oberon_qualident(Symbol *sym) {
  Object *obj = scope_find_object(id);
  if (obj != 0) {
	obj = object_retain(obj);
	scanner_get(sym);
	if (obj == 0) { as_error("Undefined"); obj = object_retain(&objectZero); }
	if ((*sym == sPERIOD) && (obj->type == typeMod)) {
	  scanner_get(sym);
	  if (*sym == sIDENT) {
		obj = thisImport(obj, id);
		scanner_get(sym);
		if (obj == 0) { as_error("Undefined"); obj = object_retain(&objectZero); }
	  } else {
		as_error("Identifier expected");
		obj = object_retain(&objectZero);
	  }
	}
  } else {
	as_error("Undefined identifier '%s'", id);
	obj = &objectZero;
  }
  return obj;
}

void oberon_checkBool(Item *object) {
  if (object->type->form != BoolForm) {
	as_error("Type is not BOOLEAN");
	object->type = type_retain(typeBool);
  }
}

void oberon_checkInt(Item *object) {
  if (object->type->form != IntForm) {
	as_error("Type is not INTEGER");
	object->type = type_retain(typeInt);
  }
}

void oberon_checkReal(Item *object) {
  if (object->type->form != RealForm) {
	as_error("Type is not REAL");
	object->type = type_retain(typeReal);
  }
}

void oberon_checkSet(Item *object) {
  if (object->type->form != SetForm) {
	as_error("Type is not SET");
	object->type = type_retain(typeSet);
  }
}

void oberon_checkSetval(Object *object) {
  if (object->type->form != IntForm) {
	as_error("Type is not INT");
	object->type = type_retain(typeInt);
  } else if (object->mode != Const) {
	if ((object->int_val < 0) || (object->int_val >= 32)) { 
	  as_error("Invalid SET");
	}
 }
}

void oberon_checkConst(Item *item) {
  if (item->mode != Const) {
	as_error("Not a constant");
	item->mode = Const;
  }
}

void oberon_checkReadOnly(Item *object) {
  if (object->readonly) {
	as_error("Read only");
  }
}

bool oberon_checkExport(Symbol *sym) {
  bool export = false;
  if (*sym == sAST) {
	export = true;
	scanner_get(sym);
	if (current_level != 1) as_warn("Remove asterisk");
  }
  return export;
}

/* t1 is an extension of t0 */
bool oberon_isExtension(Type *t0, Type *t1) {
  return (t0 == t1) || ((t1 != 0) && oberon_isExtension(t0, t1->base));
}

/* Expressions */

void parse_oberon_typetest(void) {
}

void parse_oberon_selector(Symbol *sym, Item *x) {
  while ((*sym == sLSQ) || (*sym == sPERIOD) || (*sym == sCARET) ||
		 ((*sym == sLPAREN) && ((x->type->form == RecordForm) || (x->type->form == PointerForm)))) {
	  if (*sym == sLSQ) {
		do {
		  scanner_get(sym);
		  x = parse_oberon_expression(sym);
		} while (*sym == sCOMMA);
	  } else if (*sym == sPERIOD) {
		scanner_get(sym);
		if (*sym == sIDENT) {
		}
	  } else if (*sym == sCARET) {
		scanner_get(sym);
	  } else if ((*sym == sLPAREN) && ((x->type->form == RecordForm) || (x->type->form == PointerForm))) {
		scanner_get(sym);
		if (*sym == sIDENT) {
		  parse_oberon_qualident(sym);
		}
		expect(sym, sRPAREN);
	  }
	}
}

bool oberon_equalSignatures(Type *t0, Type *t1) {
  Object *p0;
  Object *p1;
  bool com = true;

  if ((t0->base == t1->base) && (t0->nofpar == t1->nofpar)) {
	p0 = t0->desc[0];
	p1 = t1->desc[0];
	while (p0 != 0) {
	  if ((p0->mode == p1->mode) && (p0->readonly == p1->readonly)
		  && ((p0->type == p1->type) ||
			  ((p0->type->form == ArrayForm) && (p1->type->form == ArrayForm) && (p0->type->len == p1->type->len) && (p0->type->base == p1->type->base)) ||
			  ((p0->type->form == ProcForm) && (p1->type->form == ProcForm) && oberon_equalSignatures(p0->type, p1->type)))) {
		// p0 = p0->next;
		// p1 = p1->next;
	  } else {
		p0 = 0;
		com = false;
	  }
	}
  } else {
	com = false;
  }
  return com;
}

/* Check for assignment compatibility */
bool oberon_compTypes(Type *t0, Type *t1, bool varpar) {
  return (t0 == t1)
	|| ((t0->form == ArrayForm) && (t1->form == ArrayForm) && (t0->base == t1->base) && (t0->len == t1->len))
	|| ((t0->form == RecordForm) && (t1->form == RecordForm) && oberon_isExtension(t0, t1))
	|| (!varpar &&
		((t0->form == PointerForm) && (t1->form == PointerForm) && oberon_isExtension(t0->base, t1->base)))
	|| ((t0->form == ProcForm) && (t1->form == ProcForm) && oberon_equalSignatures(t0->base, t1->base))
	|| ((t0->form == PointerForm) || (((t0->form == ProcForm)) && (t1->form = NilTypeForm)));
}

void parse_oberon_parameter(Symbol *sym, Object *par) {
  Item *x;
  bool varpar;
  
  x = parse_oberon_expression(sym);

  if (par != 0) {
	varpar = (par->mode == Par);
	if (oberon_compTypes(par->type, x->type, varpar)) {
	  if (!varpar) {
		oberon_valueParam(x);
	  } else {
		if (!par->readonly) {
		  oberon_checkReadOnly(x);
		}
		oberon_varParam(x, par->type);
	  }
	} else if ((x->type->form == ArrayForm) && (par->type->form == ArrayForm) &&
			   (x->type->base == par->type->base) && (par->type->len < 0)) {
	  if (!par->readonly) {
		oberon_checkReadOnly(x);
	  }
	  oberon_openArrayParam(x);
	} else if ((x->type->form == StringForm) && varpar && par->readonly && (par->type->form == ArrayForm) &&
			   (par->type->base->form == CharForm) && (par->type->len < 0)) {
	  oberon_stringParam(x);
	} else if (!varpar && (par->type->form == IntForm) && (x->type->form == IntForm)) {
	  oberon_valueParam(x); /* Byte */
	} else if ((x->type->form == StringForm) && (x->b = 2) && (par->mode = Var) && (par->type->form == CharForm)) {
	  oberon_stringToChar(x);
	  oberon_valueParam(x);
	} else if ((par->type->form == ArrayForm) && (par->type->base == typeByte) &&
			   (par->type->len >= 0) && (par->type->size == x->type->size)) {
	  oberon_varParam(x, par->type);
	} else {
	  as_error("Incompatible parameters");
	}
  }
  // item_release(x);
}

void parse_oberon_paramlist(Symbol *sym, Item *x) {
  int n = 0;
  int nofpar = x->type->nofpar; 

  if (*sym != sRPAREN) {
	Object **par_list = x->type->desc;

	while (n < nofpar) {
	  Object *par = par_list[n];
	  parse_oberon_parameter(sym, par);
	  n += 1;
	  if (n < nofpar) expect(sym, sCOMMA);
	}
	expect(sym, sRPAREN);
  } else {
	scanner_get(sym);
  }
  if (n < nofpar) as_error("Too few paramenters");
  else if (n > nofpar) as_error("Too many parameters");
}

Item *parse_oberon_standfunc(Symbol *sym,int fct, Type *restype) {
  return 0;
}

void parse_oberon_element(Symbol *sym, Item *x) {
  // parse_oberon_expression(sym, x);
  //  oberon_checkSetVal(x);
  //if (*sym == sUPTO) {
  //	Item *y = item_make(???);
  //	scanner_get(sym);
  //	parse_oberon_expression(sym, y);
  //	oberon_checkSetVal(y);
  //	oberon_set(x, y);
  //  } else {
  //	oberon_singleton(x);
  //  }
  // x->type = typeSet;
}

Item *parse_oberon_set(Symbol *sym) {
  return 0;
}

bool is_factor(Symbol *sym) {
	if (*sym == sCHAR) return true;
	if (*sym == sINTEGER) return true;
	if (*sym == sCHAR) return true;
	if (*sym == sREAL) return true;
	if (*sym == sFALSE) return true;
	if (*sym == sTRUE) return true;
	if (*sym == sNIL) return true;
	if (*sym == sSTRING) return true;
	if (*sym == sNOT) return true;
	if (*sym == sLPAREN) return true;
	if (*sym == sLPAREN) return true;
	if (*sym == sBLOCKSTART) return true;
	if (*sym == sIDENT) return true;
	if (*sym == sEOF) return true; // Got to exit here
	return false;
}

Item *parse_oberon_factor(Symbol *sym) {
  Item *x = 0;
  int rx;
  if (!is_factor(sym)) {
	as_error("Expression expected");
	do {
	  scanner_get(sym);
	} while (!is_factor(sym));
  }
  if (*sym == sIDENT) {
	Object *object = parse_oberon_qualident(sym);

	if (object->mode == SFunc) {
	  x = parse_oberon_standfunc(sym, object->int_val, object->type);
	} else {
	  x = item_make(object, current_level);
	  parse_oberon_selector(sym, x);
	  if (*sym == sLPAREN) {
		scanner_get(sym);
		if ((x->type->form == ProcForm) && (x->type->base->form != NoTypeForm)) {
		  rx = oberon_prepCall(x);
		  parse_oberon_paramlist(sym, x);
		  oberon_call(object, rx);
		  x->type = type_retain(x->type->base);
		} else {
		  as_error("Not a function");
		  parse_oberon_paramlist(sym, x);
		}
	  }
	}
	object_release(object);
  } else if (*sym == sINTEGER) {
	x = item_makeConst(ival);
	scanner_get(sym);
  } else if (*sym == sREAL) {
	scanner_get(sym);
  } else if (*sym == sCHAR) {
	x = item_makeConst(ival);
	scanner_get(sym);
  } else if (*sym == sNIL) {
	scanner_get(sym);
  } else if (*sym == sSTRING) {
	scanner_get(sym);
  } else if (*sym == sLPAREN) {
	scanner_get(sym);
	x = parse_oberon_expression(sym);
	expect(sym, sRPAREN);
  } else if (*sym == sBLOCKSTART) {
	scanner_get(sym);
	x = parse_oberon_set(sym);
	expect(sym, sBLOCKEND);
  } else if (*sym == sNOT) {
	scanner_get(sym);
	x = parse_oberon_factor(sym);
	oberon_checkBool(x);
	oberon_not(x);
  } else if (*sym == sFALSE) {
	scanner_get(sym);
	x = item_make(&objectFalse, current_level);
  } else if (*sym == sTRUE) {
	scanner_get(sym);
	x = item_make(&objectTrue, current_level);
  } else {
	as_error("not a factor");
  }
  return x;
}

bool is_term(Symbol *sym) {
  if (*sym == sAST) return true;
  if (*sym == sDIV) return true;
  if (*sym == sMOD) return true;
  if (*sym == sSLASH) return true;
  if (*sym == sAND) return true;
  return false;
}

Item *parse_oberon_term(Symbol *sym) {
  Item *x;
  Item *y;
  Symbol op;
  Form form;
  
  x = parse_oberon_factor(sym);
  form = x->type->form;
  while (is_term(sym)) {
	op = *sym;
	scanner_get(sym);
	if (op == sAST) {
	  if (form == IntForm) {
		y = parse_oberon_factor(sym);
		oberon_checkInt(y);
		oberon_mulOp(x, y);
	  } else if (form == RealForm) {
		y = parse_oberon_factor(sym);
		oberon_checkReal(y);
		oberon_realOp(op, x, y);
	  } else if (form == SetForm) {
		y = parse_oberon_factor(sym);
		oberon_checkSet(y);
		oberon_setOp(op, x, y);
	  } else {
		as_error("Bad type");
	  }
	} else if ((op == sDIV) || (op == sMOD)) {
	  oberon_checkInt(x);
	  y = parse_oberon_factor(sym);
	  oberon_checkInt(y);
	  oberon_divOp(op, x, y);
	} else if (op == sSLASH) { /* rdiv */
	  if (form == RealForm) {
		y = parse_oberon_factor(sym);
		oberon_checkReal(y);
		oberon_realOp(op, x, y);
	  } else if (form == SetForm) {
		y = parse_oberon_factor(sym);
		oberon_checkSet(y);
		oberon_setOp(op, x, y);
	  } else {
		as_error("Bad type");
	  }
	} else { /* and */
	  oberon_checkBool(x);
	  oberon_and1(x);
	  y = parse_oberon_factor(sym);
	  oberon_checkBool(y);
	  oberon_and2(x, y);
	}
  }
  return x;
}

Item *parse_oberon_simpleexpression(Symbol *sym) {
  Item *x;
  Item *y;
  Symbol op;
  
  if (*sym == sMINUS) {
	scanner_get(sym);
	x = parse_oberon_term(sym);
	if ((x->type->form == IntForm) || (x->type->form == RealForm) || (x->type->form == SetForm)) {
	  oberon_neg(x);
	} else {
	  oberon_checkInt(x);
	}
  } else if (*sym == sPLUS) {
	scanner_get(sym);
	x = parse_oberon_term(sym);
  } else {
	x = parse_oberon_term(sym);
  }
  while ((*sym == sPLUS) || (*sym == sMINUS) || (*sym == sOR)) {
	op = *sym;
	scanner_get(sym);
	if (op == sOR) {
	  oberon_or1(x);
	  oberon_checkBool(x);
	  y = parse_oberon_term(sym);
	  oberon_checkBool(y);
	  oberon_or2(y);
	} else if (x->type->form == IntForm) {
	  y = parse_oberon_term(sym);
	  oberon_checkInt(y);
	  oberon_addOp(op, x, y);
	} else if (x->type->form == RealForm) {
	  y = parse_oberon_term(sym);
	  oberon_checkReal(y);
	  oberon_realOp(op, x, y);
	} else {
	  oberon_checkSet(x);
	  y = parse_oberon_term(sym);
	  oberon_checkSet(y);
	  oberon_setOp(op, x, y);
	}
  }
  return x;
}

bool is_comparison(Symbol *sym) {
  if (*sym == sEQL) return true;
  if (*sym == sNEQ) return true;
  if (*sym == sLSS) return true;
  if (*sym == sLEQ) return true;
  if (*sym == sGTR) return true;
  if (*sym == sGEQ) return true;
  return false;
}

void parse_oberon_typeTest(Symbol *sym, Item *x, Type *t, bool guard) {
  /* Type * xtype = x->type; */
  /* if ((t->form == xtype->form) && (t->form == PointerForm) || (t->form == RecordForm) && (x->mode == Par)) { */
  /* 	while ((xtype != t) && (xtype != 0)) { */
  /* 	  xtype = xtype->base; */
  /* 	} */
  /* 	if (xtype != t) { */
  /* 	  xt = x->type; */
  /*       IF xt.form = ORB.Pointer THEN */
  /*         IF IsExtension(xt.base, T.base) THEN ORG.TypeTest(x, T.base, FALSE, guard); x.type := T */
  /*         ELSE ORS.Mark("not an extension") */
  /*         END */
  /*       ELSIF (xt.form = ORB.Record) & (x.mode = ORB.Par) THEN */
  /*         IF IsExtension(xt, T) THEN  ORG.TypeTest(x, T, TRUE, guard); x.type := T */
  /*         ELSE ORS.Mark("not an extension") */
  /*         END */
  /*       ELSE ORS.Mark("incompatible types") */
  /*       END */
  /*     ELSIF ~guard THEN ORG.MakeConstItem(x, ORB.boolType, 1) */
  /*     END */
  /*   ELSE ORS.Mark("type mismatch") */
  /*   END ; */
  /* 		if (!guard) { */
  /* 		  x->type = typeBool; */
  /* 		} */
}
  
Item *parse_oberon_expression(Symbol *sym) {
  Item *x;
  Item *y;
  Symbol rel;
  Form xform;
  Form yform;
  x = parse_oberon_simpleexpression(sym);
  if (is_comparison(sym)) {
	rel = *sym;
	scanner_get(sym);
	y = parse_oberon_simpleexpression(sym);
	xform = x->type->form;
	yform = y->type->form;
	if (x->type == y->type) {
	  switch (xform) {
	  case CharForm:
	  case IntForm:
		oberon_intRelation(rel, x, y);
		break;
	  case RealForm:
		oberon_realRelation(rel, x, y);
		break;
	  case SetForm:
	  case PointerForm:
	  case ProcForm:
	  case NilTypeForm:
	  case BoolForm:
		if ((*sym == sEQL) || (*sym == sNEQ)) {
		  oberon_intRelation(rel, x, y);
		} else {
		  as_error("Only = or # allowed with this type");
		}
		break;
	  case ArrayForm:
		if (x->type->base->form == CharForm) {
		  oberon_stringRelation(rel, x, y);
		}  else {
		  as_error("Can't use relations on arrays");
		}
		break;
	  case StringForm:
		oberon_stringRelation(rel, x, y);
		break;
	  default:
		as_error("Illegal comparison");
	  }
	} else if ((((xform == PointerForm) || (xform == ProcForm)) && (yform == NilTypeForm)) ||
			   (((yform == PointerForm) || (yform == ProcForm)) && (xform == NilTypeForm))) {
	  if ((rel == sEQL) || (rel = sNEQ)) {
		oberon_intRelation(rel, x, y);
	  } else {
		as_error("Only = or # allowed");
	  }
	} else if (((xform == PointerForm) && (yform == PointerForm) &&
			   (oberon_isExtension(x->type->base, y->type->base) || oberon_isExtension(y->type->base, x->type->base)))
			   || ((xform == ProcForm) && (yform == ProcForm) && oberon_equalSignatures(x->type, y->type))) {
	  if (rel <= sNEQ) {
		oberon_intRelation(rel, x, y);
	  } else {
		as_error("only = or #");
	  }
	} else if ((xform == ArrayForm) && (x->type->base->form == CharForm) && 
			   ((((yform == StringForm) || (yform == ArrayForm)) && (y->type->base->form == CharForm))
				|| ((yform == ArrayForm) && (y->type->base->form == CharForm) && (xform == StringForm)))) {
	  oberon_stringRelation(rel, x, y);
	} else if ((xform == CharForm) && (yform == StringForm) && (y->b == 2)) {
	  oberon_stringToChar(y);
	  oberon_intRelation(rel, x, y);
	} else if ((yform == CharForm) && (xform == StringForm) && (x->b == 2)) {
	  oberon_stringToChar(x);
	  oberon_intRelation(rel, x, y);
	} else if ((xform == IntForm) && (yform == IntForm)) {
	  oberon_intRelation(rel, x, y); /* BYTE */
	} else {
	  as_error("Illegal comparison");
	}
	x->type = type_retain(typeBool);
  } else if (*sym == sIN) {
	scanner_get(sym);
	oberon_checkInt(x);
	y = parse_oberon_simpleexpression(sym);
	oberon_checkSet(y);
	oberon_in(x, y);
	x->type = type_retain(typeBool);
  } else if (*sym == sIS) {
	scanner_get(sym);
	Object *object = parse_oberon_qualident(sym);
	parse_oberon_typeTest(sym, x, object->type, false);
	x->type = type_retain(typeBool);
	object_release(object);
  }
  return x;
}

void parse_oberon_standproc(Symbol *sym, int pno) {
  int nap; /* Number of actual parameters */
  int npar; /* Number of formal parameters */
  Item *x = 0;
  Item *y = 0;
  Item *z = 0;

  expect(sym, sLPAREN);
  npar = pno % 10;
  pno = pno / 10;
  x = parse_oberon_expression(sym);
  nap = 1;
  if (*sym == sCOMMA) {
	scanner_get(sym);
	y = parse_oberon_expression(sym);
	nap = 2;
	while (*sym == sCOMMA) {
	  scanner_get(sym);
	  z = parse_oberon_expression(sym);
	  nap += 1;
	}
  }
  expect(sym, sRPAREN);
  if ((npar == nap) || ((pno == 0) || (pno == 1))) {
	  switch (pno) {
	  case 0: /* INC */
	  case 1: /* DEC */
		oberon_checkInt(x);
		oberon_checkReadOnly(x);
		if (y != 0) {
		  oberon_checkInt(y);
		}
		// oberon_increment(pno, x, y);/* pno is up or down */
		break;
	  case 2: /* INCL set */
	  case 3: /* EXCL set */
		oberon_checkSet(x);
		oberon_checkReadOnly(x);
		oberon_checkInt(y);
		// oberon_include(pno-2, x, y);
		break;
	  case 4: /* ASSERT */
		oberon_checkBool(x);
		// oberon_assert(x);
		break;
	  case 5: /* NEW */
		oberon_checkReadOnly(x);
		if ((x->type->form == PointerForm) && (x->type->base->form == RecordForm)) {
		  // oberon_new(x);
		} else {
		  as_error("Not a pointer to a record");
		}
		break;
	  case 6: /* PACK */
		oberon_checkReal(x);
		oberon_checkInt(y);
		oberon_checkReadOnly(x);
		// oberon_pack(x, y);
		break;
	  case 7: /* UNPACK */
		oberon_checkReal(x);
		oberon_checkInt(y);
		oberon_checkReadOnly(x);
		// oberon_unpack(x, y);
		break;
	  case 8: /* LED */
		switch (x->type->form) {
		case IntForm:
		  // oberon_led(x);
		  break;
		default:
		  as_error("Bad type");
		}
		break;
	  case 10: /* GET */
		oberon_checkInt(x);
		oberon_get(x, y);
		break;
	  case 11: /* PUT */
		oberon_checkInt(x);
		oberon_put(x, y);
		break;
	  case 12:
		oberon_checkInt(x);
		oberon_checkInt(y);
		oberon_checkInt(z);
		//oberon_copy(x, y, z);
		break;
	  };
	} else {
	  as_error("Wrong number of parameters");
	}
}

void parse_oberon_type_case(Symbol *sym) {
  if (*sym == sIDENT) {
	parse_oberon_qualident(sym);
	expect(sym, sCOLON);
	parse_oberon_statementsequence(sym);
  } else {
	as_error("type id expected");
  }
}

void parse_oberon_skip_case(Symbol *sym) {
  while (*sym != sCOLON) {
	scanner_get(sym);
  }
  scanner_get(sym); // colon
  parse_oberon_statementsequence(sym);
}

void parse_oberon_statementsequence(Symbol *sym) {
  Object *object = 0;
  Item *x = 0;
  Item *y = 0;
  Item *z = 0;
  Item *w = 0;
  int rx = 0;
  Object *L0 = 0;
  // Object *L1 = 0;
  do {
	object = 0; /* FREE? */
	/* Make sure we have an statement, can maybe do this in an else at the end
      IF ~((sym >= ORS.ident)  & (sym <= ORS.for) OR (sym >= ORS.semicolon)) THEN
        ORS.Mark("statement expected");
        REPEAT ORS.Get(sym) UNTIL (sym >= ORS.ident)
      END ;
	*/
	if (*sym == sIDENT) {
	  object = parse_oberon_qualident(sym);
	  x = item_make(object, current_level);
	  if (x->mode == SProc) {
		parse_oberon_standproc(sym, object->int_val);
	  } else {
		parse_oberon_selector(sym, x);
		if (*sym == sBECOMES) { /* assignment */
		  scanner_get(sym);
		  oberon_checkReadOnly(x);
		  y = parse_oberon_expression(sym);
		  if (oberon_compTypes(x->type, y->type, false)) {
			if ((x->type->form <= PointerForm) || (x->type->form == ProcForm)) {
			  oberon_store(x, y);
			} else {
			  // oberon_storeStruct(x, y);
			}
		  } else if ((x->type->form == ArrayForm) && (y->type->form == ArrayForm) && (x->type->base == y->type->base) && (y->type->len < 0)) {
			// oberon_storeStruct(x, y);
		  } else if ((x->type->form == ArrayForm) && (x->type->base->form == CharForm) && (y->type->form == StringForm)) {
			//oberon_copyString(x, y);
		  } else if ((x->type->form == IntForm) && (y->type->form == IntForm)) {
			oberon_store(x, y); 
		  } else if ((x->type->form == CharForm) && (y->type->form == StringForm) && (y->b == 2)) {
			oberon_stringToChar(y);
			// oberon_store(x, y);
		  } else {
			as_error("Illegal assignment");
		  }
		} else if (*sym == sEQL) {
		  as_error("Should be :=");
		  scanner_get(sym);
		  y = parse_oberon_expression(sym);
		} else if (*sym == sLPAREN) { /* procedure call */
		  scanner_get(sym);
		  if ((x->type->form == ProcForm) && (x->type->base->form == NoTypeForm)) {
			rx = oberon_prepCall(x);
			parse_oberon_paramlist(sym, x);
			oberon_call(object, rx);
		  } else {
			as_error("Not a procedure");
			parse_oberon_paramlist(sym, x);			
		  }
		} else if (x->type->form == ProcForm) { /* Procedure call without parameters */
		  if (x->type->nofpar > 0) {
			as_error("Missing parameters");
		  }
		  if (x->type->base->form == NoTypeForm) {
			rx = oberon_prepCall(x);
			oberon_call(object, rx);
		  } else {
			as_error("Not a procedure");
		  }
		} else if (x->mode == Typ) {
		  as_error("Illegal assignment");
		} else {
		  as_error("Not a procedure");
		}
	  }
	  object_release(object);
	} else if (*sym == sIF) {
	  scanner_get(sym);
	  x = parse_oberon_expression(sym);
	  oberon_checkBool(x);
	  if (x->mode == Const) {
		// ToDo: Optimise out const false 
	  }
	  Object *flabel = 0; // object_make();
	  // oberon_cjump(flabel, x);
	  expect(sym, sTHEN);
	  parse_oberon_statementsequence(sym);
	  while (*sym == sELSIF) {
		scanner_get(sym);
		oberon_jump(L0);
		x = parse_oberon_expression(sym);
		oberon_checkBool(x);
		// oberon_cjump(x);
		expect(sym, sTHEN);
		parse_oberon_statementsequence(sym);
	  }
	  if (*sym == sELSE) {
		scanner_get(sym);
		parse_oberon_statementsequence(sym);
	  }
	  expect(sym, sEND);
	} else if (*sym == sWHILE) {
	  scanner_get(sym);
	  // L0 = oberon_here();
	  x = parse_oberon_expression(sym);
	  oberon_checkBool(x);
	  // oberon_cjump(x);
	  expect(sym, sDO);
	  parse_oberon_statementsequence(sym);
	  // oberon_bjump(L0);
	  while (*sym == sELSIF) {
		scanner_get(sym);
		// oberon_fixup(x);
		x = parse_oberon_expression(sym);
		oberon_checkBool(x);
		// oberon_cfjump(x);
		expect(sym, sDO);
		parse_oberon_statementsequence(sym);
		// oberon_bjump(L0);
	  }
	  // oberon_fixup(x);
	  expect(sym, sEND);
	} else if (*sym == sREPEAT) {
	  scanner_get(sym);
	  // L0 = oberon_here();
	  parse_oberon_statementsequence(sym);
	  if (*sym == sUNTIL) {
		scanner_get(sym);
		x = parse_oberon_expression(sym);
		oberon_checkBool(x);
		// oberon_cbjump(x, L0);
	  } else {
		as_error("Missing until");
	  }
	} else if (*sym == sFOR) {
	  scanner_get(sym);
	  if (*sym == sIDENT) {
		object = parse_oberon_qualident(sym);
		x = item_make(object, current_level);
		oberon_checkInt(x);
		oberon_checkReadOnly(x);
		if (*sym == sBECOMES) {
		  scanner_get(sym);
		  y = parse_oberon_expression(sym);
		  oberon_checkInt(y);
		  oberon_for0(x, y);
		  // L0 = oberon_here();
		  expect(sym, sTO);
		  z = parse_oberon_expression(sym);
		  oberon_checkInt(z);
		  object->readonly = true;
		  if (*sym == sBY) {
			scanner_get(sym);
			w = parse_oberon_expression(sym);
			oberon_checkConst(w);
			oberon_checkInt(w);
		  } else {
			w = item_makeConst(1);
		  }
		  expect(sym, sDO);
		  // oberon_for1(x, y, z, w, L1);
		  parse_oberon_statementsequence(sym);
		  expect(sym, sEND);
		  // oberon_for2(x, y, w);
		  // oberon_bjump(L0);
		  // oberon_fixLink(L1);
		  object->readonly = false;
		} else {
		  as_error(":= expectecd");
		}
		object_release(object);
	  } else {
		as_error("identifer expected");
	  }
	} else if (*sym == sCASE) {
	  scanner_get(sym);
	  if (*sym == sIDENT) {
		object = parse_oberon_qualident(sym);
		Type *orgtype = object->type;
		if ((orgtype->form == PointerForm) || ((orgtype->form == RecordForm) && (object->mode = Par))) {
		  expect(sym, sOF);
		  // oberon_typeCase(object, x);
		  L0 = 0;
		  while (*sym == sBAR) {
			scanner_get(sym);
			// oberon_fjump(L0);
			// oberon_fixup(x);
			object->type = type_retain(orgtype);
			// oberon_typeCase(object, x);
		  }
		  // oberon_fixup(x);
		  // oberon_fixlink(L0);
		  object->type = type_retain(orgtype);
		} else {
		  as_error("Numeric case not implemented");
		}
		expect(sym, sOF);
		// oberon_skipCase();
		while (*sym == sBAR) {
		  // oberon_skipCase();
		}
		object_release(object);
	  } else {
		as_error("Ident expected");
	  }
	  expect(sym, sEND);
	}
	// oberon_checkRegs();
	if (*sym == sSTATESEP) {
	  scanner_get(sym);
	} else if (*sym < sSTATESEP) {
	  as_error("Missing semicolon");
	}
  }	while ((*sym != sEND) && (*sym != sRETURN));		   
}
 
/* Types and declarations */

void parse_oberon_identlist(Symbol *sym, Object ***objects, int *num) {
  Object *object;
  
  list_reset((void ***)objects, num);
  if (*sym == sIDENT) {
	object = object_new(Const, typeNoType); /* We don't know the form yet */
	object->mode = Var;
	scope_add_object(as_strdup(id), object);
	scanner_get(sym);
	oberon_checkExport(sym);
	list_add((void ***)objects, num, object);
	object_release(object);
	while (*sym == sCOMMA) {
	  scanner_get(sym);
	  if (*sym == sIDENT) {
		object = object_new(Const, typeNoType); /* We don't know the form yet */
		object->mode = Var;
		scope_add_object(as_strdup(id), object);
		scanner_get(sym);
		oberon_checkExport(sym);
		list_add((void ***)objects, num, object);
		object_release(object);
	  } else {
		as_warn("ident?");
	  }
	}
	if (*sym == sCOLON) {
	  scanner_get(sym);
	} else {
	  expect(sym, sCOLON);
	  as_error("Expected : and type");
	}
  } else {
  }
}

void parse_oberon_arraytype(Symbol *sym) {
}

void parse_oberon_recordtype(Symbol *sym) {
}

int parse_oberon_fpsection(Symbol *sym, Type *ptype) {
  int num = 0;
  Object **objects = 0;
  int parsize = 0;
  Mode mode;
  bool rdo = false;
  int adr = 0;
  
  if (*sym == sVAR) {
	scanner_get(sym);
	mode = Par;
  } else {
	mode = Var;
  }

  parse_oberon_identlist(sym, &objects, &num); 
  Type *tp = parse_oberon_formaltype(sym, 0);

  if (num > 0) {
	if ((mode == Var) && (tp->form >= ArrayForm)) {
	  mode = Par;
	  rdo = true;
	}
	if (((tp->form == ArrayForm) && (tp->len < 0)) || (tp->form == RecordForm)) {
	  parsize = 2 * WordSize; /* Open array or record, needs second word for length or type tag */
	} else {
	  parsize = WordSize;
	}
  }
  
  for (int i = 0; i < num; i++) {
	objects[i]->type = tp;
	objects[i]->readonly = rdo;
	objects[i]->level = current_level;
	objects[i]->addr = adr;
	adr = adr + parsize;
	object_list_add(&ptype->desc, &ptype->nofpar, objects[i]);
  }
  type_release(tp);

  if (adr >= 52) {
	as_error("Too many parameters");
  }
  return adr;
}

int parse_oberon_procedure_type(Symbol *sym, Type *ptype, int parblksize) {
  Object *object;
  int size;

  ptype->base = typeNoType;
  size = parblksize;
  ptype->desc = 0;
  if (*sym == sLPAREN) {
	scanner_get(sym);
	if (*sym == sRPAREN) {
	  scanner_get(sym);
	} else {
	  size = parse_oberon_fpsection(sym, ptype);
	  while (*sym == sSTATESEP) {
		scanner_get(sym);
		size += parse_oberon_fpsection(sym, ptype);
	  }
	  expect(sym, sRPAREN);
	}
	if (*sym == sCOLON) { /* function */
	  scanner_get(sym);
	  if (*sym == sIDENT) {
		object = parse_oberon_qualident(sym);
		ptype->base = object->type;
		// IF ~((obj.class = ORB.Typ) & (obj.type.form IN {ORB.Byte .. ORB.Pointer, ORB.Proc})) THEN
		// as_error("Illegal function type");
		// END
		object_release(object);
	  } else {
		as_error("Type identifier expected");
	  }
	}
  }
  return size;
}

Type *parse_oberon_formaltype(Symbol *sym, int dim) {
  Object *object;
  Type *typ;
  if (*sym == sIDENT) {
	object = parse_oberon_qualident(sym);
	if (object->mode == Typ) {
	  typ = type_retain(object->type);
	} else {
	  as_error("Not a type");
	  typ = type_retain(typeInt);
	}
	object_release(object);
  } else if (*sym == sARRAY) {
	scanner_get(sym);
	expect(sym, sOF);
	if (dim >= 1) {
	  as_error("Multi-dimensional open arrays not implemented");
	}
	typ = type_new();
	typ->form = ArrayForm;
	typ->len = -1;
	typ->size = 2 * WordSize;
	typ->base = parse_oberon_formaltype(sym, dim + 1);
  } else if (*sym == sPROCEDURE) {
	scanner_get(sym);
	object = object_new(Const, typeProc);
	typ = type_new();
	typ->form = ProcForm;
	typ->size = parse_oberon_procedure_type(sym, typ, 0);
	object_release(object);
  } else {
	as_error("Identifier expected");
	typ = type_retain(typeInt);
  }
  return typ;
}
/*
  PROCEDURE FormalType0(VAR typ: ORB.Type; dim: INTEGER);
    VAR obj: ORB.Object; dmy: LONGINT;
  BEGIN
    IF sym = ORS.ident THEN
      qualident(obj);
      IF obj.class = ORB.Typ THEN typ := obj.type ELSE ORS.Mark("not a type"); typ := ORB.intType END
    ELSIF sym = ORS.array THEN
      ORS.Get(sym); Check(ORS.of, "OF ?");
      IF dim >= 1 THEN ORS.Mark("multi-dimensional open arrays not implemented") END ;
      NEW(typ); typ.form := ORB.Array; typ.len := -1; typ.size := 2*ORG.WordSize;
      FormalType(typ.base, dim+1)
    ELSIF sym = ORS.procedure THEN
      ORS.Get(sym); ORB.OpenScope;
      NEW(typ); typ.form := ORB.Proc; typ.size := ORG.WordSize; dmy := 0; ProcedureType(typ, dmy);
      typ.dsc := ORB.topScope.next; ORB.CloseScope
    ELSE ORS.Mark("identifier expected"); typ := ORB.noType
    END
  END FormalType0;
*/
void oberon_checkRecLevel(int level) {
  if (current_level != 1) as_error("Pointer base must be global");
}

void parse_oberon_type(Symbol *sym) {
  
}

bool is_not_decl(Symbol *sym) {
  if (*sym == sTYPE) return false;
  if (*sym == sVAR) return false;
  if (*sym == sPROCEDURE) return false;
  if (*sym == sBEGIN) return false;
  if (*sym == sIMPORT) return false;
  if (*sym == sMODULE) return false;
  if (*sym == sEND) return false;
  if (*sym == sRETURN) return false;
  return true;
}

int parse_oberon_declarations(Symbol *sym, int size) {
  
  if (is_not_decl(sym)) {
	as_warn("Declaration?");
	do { } while (is_not_decl(sym));
  }
  if (*sym == sCONST) {
	scanner_get(sym);
	while (*sym == sIDENT) {
	  scanner_get(sym);
	  oberon_checkExport(sym);
	  if (*sym == sEQL) {
		scanner_get(sym);
		// parse_oberon_expression(sym, x);
	  } else {
		as_warn("= ?");
	  }
	}
	expect(sym, sSTATESEP);
  }
  if (*sym == sTYPE) {
	scanner_get(sym);
	while (*sym == sIDENT) {
	  scanner_get(sym);
	  oberon_checkExport(sym);
	  if (*sym == sEQL) {
		scanner_get(sym);
	  } else {
		as_warn("= ?");
	  }
	  parse_oberon_formaltype(sym, 0);
	  expect(sym, sSTATESEP);
	}
  }
  if (*sym == sVAR) {
	scanner_get(sym);
	while (*sym == sIDENT) {
	  int num = 0;
	  Object **objects = 0;
	  parse_oberon_identlist(sym, &objects, &num); 
	  Type *tp = parse_oberon_formaltype(sym, 0);
	  for (int i = 0; i < num; i++) {
		objects[i]->type = type_retain(tp);
		/* no need for alignment */
		objects[i]->addr = size;
		size += tp->size;
		objects[i]->int_val = tp->size;
	  }
	  type_release(tp);
	  expect(sym, sSTATESEP);
	}
  }
  return size;
}

void parse_oberon_proceduredecl(Symbol *sym) {
  Object* proc;
  //  Object* type;
  char *procid = 0;
  Item *x = 0;
  int locblksize;
  int parblksize;
  //int L;
  char isInterrupt;
  /*
      type: ORB.Type;
      procid: ORS.Ident;
  */
  isInterrupt = false;
  scanner_get(sym);
  if (*sym == sAST) {
	isInterrupt = true;
	scanner_get(sym);
  }
  if (*sym == sIDENT) {
	procid = as_strdup(id);
	scanner_get(sym);
	proc = object_new(Const, typeProc);
	scope_add_object(procid, proc);
	if (isInterrupt) parblksize = 6;
	else parblksize = 0; 
	Type *typ = type_new();
	typ->form = ProcForm;
	typ->size = WordSize;
	proc->type = type_retain(typ);
	proc->string_val = procid;
	proc->exported = oberon_checkExport(sym);
	if (proc->exported ) {
	  proc->exno = exno;
	  exno += 1;
	}
	scope_push_object(proc);
	interp_add(OpScopeBegin, proc);
	typ->base = typeNoType;
	typ->size = parse_oberon_procedure_type(sym, typ, parblksize);
	expect(sym, sSTATESEP);
	locblksize = parse_oberon_declarations(sym, 0);

	for (int i = 0; i < typ->nofpar; i++) {
	  typ->desc[i]->addr += locblksize + 3; /* Move below locals and return value (JSL) */
	}
	
	// proc->int_val = oberon_here();
	// proc.type.dsc := ORB.topScope.next;
	if (*sym == sPROCEDURE) {
	  // L = 0; oberon_fjump(L);
	  do {
		parse_oberon_proceduredecl(sym);
		expect(sym, sSTATESEP);
	  } while (*sym == sPROCEDURE);
	  // oberon_fixone(L);
	  // proc->int_val = oberon_here();
	  // proc.type.dsc := ORB.topScope.next;
	}
	oberon_enter(proc, parblksize, locblksize, isInterrupt);
	if (*sym == sBEGIN) {
	  scanner_get(sym);
	  parse_oberon_statementsequence(sym);
	}

	if (*sym == sRETURN) {
	  scanner_get(sym);
	  x = parse_oberon_expression(sym);
	  if (typ->base == typeNoType) {
		as_error("This is not a function");
	  } else if (!oberon_compTypes(typ->base, x->type, false)) {
		as_error("Wrong result type");
	  }
	} else if (typ->base != typeNoType) {
	  // as_error("Function without result");
	  typ->base = typeNoType;
	}
	oberon_return(typ->base->form, x, locblksize, isInterrupt);
	scope_pop();
	interp_add(OpScopeEnd, 0);
	expect(sym, sEND);
	if (*sym == sIDENT) {
	  if (strcmp(id, procid) != 0) as_warn("Procedure name mismatch");
	  scanner_get(sym);
	} else {
	  as_warn("No procedure id");
	}
	object_release(proc);
	type_release(typ);
  } else {
	as_error("Procedure name expected");
  }
}

void parse_oberon_import(Symbol *sym) {
  char *import_id;
  char *import_id1;
  
  if (*sym == sIDENT) {
	import_id = as_strdup(id);
	scanner_get(sym);
	if (*sym == sBECOMES) {
	  scanner_get(sym);
	  if (*sym == sIDENT) {
		import_id1 = as_strdup(id);
		scanner_get(sym);
	  } else {
		as_error("Expected identifier");
		return;
	  }
	} else {
	  import_id1 = as_strdup(import_id);
	}
	// value_import(import_id, import_id1);
	as_free(import_id1);
	as_free(import_id);
  }
}

// module = MODULE ident ";" [ImportList] DeclarationSequence
void parse_oberon_module(Symbol *sym) {

  scanner_get(sym); // MODULE
  // Init codegen
  if (*sym == sIDENT) {
	Object *object = object_new(Const, typeMod);
	char *name = as_strdup(id);
	object->string_val = name;
	scope_add_object(name, object);
	scope_push_object(object);
	interp_add(OpScopeBegin, object);
	
	scanner_get(sym);
	printf("Compiling MODULE %s.\n", name);
	object_release(object);
  } else {
	as_error("expected identifier for module");
  }
  expect(sym, sSTATESEP);
  if (*sym == sIMPORT) {
	scanner_get(sym);
	parse_oberon_import(sym);
	while (*sym == sCOMMA) {
	  scanner_get(sym);
	  parse_oberon_import(sym);
	}
	expect(sym, sSTATESEP);
  }

  // codegen_open()
  // Declarations
  // codegen_set_data_size((dc + 3) / 4 * 4);
  while (*sym == sPROCEDURE) {
	parse_oberon_proceduredecl(sym);
	expect(sym, sSTATESEP);
  }
  // codegen_header
  if (*sym == sBEGIN) {
	scanner_get(sym);
	parse_oberon_statementsequence(sym);
  }
  expect(sym, sEND);
  if (*sym == sIDENT) {
	if (strcmp(id, scope->string_val) != 0) as_error("No module name match");
	scanner_get(sym);
  } else {
	as_error("Identifier missing");
  }
  expect(sym, sPERIOD);
  if (error_count == 0) {
	// ORB export(module_name, new_symbol_file, key);
	if (new_symbol_file) printf("New symbol file.");
	// codegen_close()
  }
  scope_pop(); /* Module */
  interp_add(OpScopeEnd, scope);
}

/*----------------------------------------
Public entry points
----------------------------------------*/

void parse_asm_file(Symbol *sym)
{
  do {
    parse_statement(sym);
    //  } while (*sym != sEOF);
  } while ((*sym != sEOF) && (*sym != sEND));
}

void parse_define(Symbol *sym)
{
  Object *var = parse_ident_def(sym);
  if (*sym == sBECOMES) {
    parse_assignment(var, sym);
  } else {
    Object one;
    one.type = typeInt;
    one.bool_val = 1;
    // one.is_extern = var->is_extern;
    as_define_symbol(var->string_val, &one);
  }
  object_release(var);
}

void parse_oberon_file(Symbol *sym)
{
  new_symbol_file = false;
  if (*sym == sMODULE) {
	parse_oberon_module(sym);
	if (*sym != sEOF) as_warn("Extra text after end of module");
  } else {
	as_error("MODULE not found");
  }
}

