#include "as.h"

#include <string.h>
#include <stdio.h>

#include "memory.h"
#include "scanner.h"
#include "buffered_file.h"
#include "value.h"
#include "interp.h"
#include "codegen.h"

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
	while (*sym == sELSE) {
	  interp_add(OpScopeEnd, 0);
      scanner_get(sym);
	  if (*sym == sIF) {
		scanner_get(sym);
		parse_expression(sym, false);
		if (*sym == sBLOCKSTART) {
		  interp_add(OpElseIfBegin, 0);
		  scanner_get(sym);
		  parse_block(sym);
		  scanner_get(sym);
		}
	  } else if (*sym == sBLOCKSTART) {
		interp_add(OpElseBegin, 0);
		scanner_get(sym);
		parse_block(sym);
		scanner_get(sym);
	  } else {
		as_error("Malformed IF expression");
	  }
    }
	interp_add(OpScopeEnd, 0);
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
	Object *v = object_new(Const, typeInt);
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

  case sERRORIF:
	scanner_get(sym);
	parse_if(sym);
    parse_message(sym, OpErrorIf);
	*sym = sEND;
    break;

  case sMESSAGE:
    parse_message(sym, OpMessage);
    break;
    
  case sSECTION:
	{
	  char *name;
	  int section_flags = SHF_EXECINSTR;
	  int section_type = SHT_PROGBITS;
	  if (*sym == sSTRING) {
		name = as_strdup(id);
		scanner_get(sym);

		if (*sym == sCOMMA) {
		  scanner_get(sym);
		  if (*sym == sINTEGER) {
			section_type = ival;
		  }
		  scanner_get(sym);
		}
		if (*sym == sCOMMA) {
		  scanner_get(sym);
		  if (*sym == sINTEGER) {
			section_flags = ival;
		  }
		  scanner_get(sym);
		}
		section = elf_section_create(elf_context, name, section_flags, section_type);
		as_free(name);
	  }
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
    result->is_global = true;
    scanner_get(sym);
  }

  // Colon is optional, but useful for searching
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
Public entry points
----------------------------------------*/

void parse_asm_file(Symbol *sym)
{
  do {
    parse_statement(sym);
  } while ((*sym != sEOF) && (*sym != sEND));
}

void parse_define(Symbol *sym)
{
  Object *var = parse_ident_def(sym);
  if (*sym == sBECOMES) {
    parse_assignment(var, sym);
  } else {
    Object *one = object_new(Const, typeInt);
    one->bool_val = 1;
    as_define_symbol(var->string_val, one);
	object_release(one);
  }
  object_release(var);
}

