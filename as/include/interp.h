#ifndef INTERP_H
#define INTERP_H

#include "as.h"
#include "scanner.h"
#include "value.h"

/*
The immediate form defines a stack based language that is interpreted 
to form the output.

It has these instructions:
push value
push ref
pop value
dup
add
sub
mul
div
not
emit instr
if
endif
jmp op
*/  

enum OpType {
	     OpPush,
	     OpPushVar,
	     OpPop,
	     OpPopVar,
	     OpDup,
	     OpAdd,
	     OpSub,
	     OpMul,
	     OpDiv,
	     OpIDiv,
	     OpMod,
	     OpAnd,
	     OpOr,
	     OpNeg,
	     OpNot,
	     OpLowByte,
	     OpHighByte,
	     OpBankByte,
	     OpEqual,
	     OpNotEqual,
	     OpGreaterThan,
	     OpGreaterThanEqual,
	     OpLessThan,
	     OpLessThanEqual,
	     OpLeftShift,
	     OpRightShift,
	     OpEmit,
	     OpIfBegin,
	     OpElseBegin,
	     OpJump,
	     OpScopeBegin,
		 OpScopeEnd,
	     OpError,
	     OpErrorIf,
	     OpMessage,
	     OpLabel,
	     OpFillByte,
	     OpFillWord,
	     OpFillLong,
	     OpConCat, // Concat two strings (or variables)
	     OpByte,
	     OpWord,
	     OpLong,
	     OpFloat,
	     OpDouble,
	     OpText,
	     OpTextBit7,
	     OpTextLen,
	     OpTextZero,
	     OpListLine,
	     OpMacroCall,
	     OpTitle,
	     OpSubheading,
	     OpPageBreak,
};

struct Op {
  enum OpType type;
  union {
    Object *value; // Can point to either a variable or a constant value
    Op *op; // For goto
    Instr instr; // The instruction to emit
  };
  int line_num;  // For errors
  char *filename;
};

int interp_run(const char *filename);
//ELF_Word interp_section(elf_section_t *section);

void interp_add(enum OpType type, Object *value);
void interp_add_byte(char val);
void interp_add_word(int val);

/* Adds an instruction with any paremeters already set in the interp list */
void interp_add_instr(OpCode instr, AddrMode mode, Modifier modifier);

void interp_macro_begin(char *label);
void interp_macro_end(void);

#endif /* INTERP_H */
