#ifndef SCANNER_H
#define SCANNER_H

#include <stdbool.h>

/*
Scanner for 65Tools assembler and compiler
*/  

// Symbols
typedef enum {
#define DEF(tok, str, flags) s ## tok,
#define TOK(tok) s ## tok,
#include "as_tokens.h"
#undef DEF
#undef TOK
} Symbol;

extern const int IdLen;
extern const int NofKeys;

extern char id[];

extern int ival;
extern double rval;

extern int org;

enum ScannerMode {
  OberonMode,
  ASMMode,
};

void scanner_ident(Symbol* sym);
void scanner_get(Symbol* sym);
void scanner_init(enum ScannerMode mode);
void scanner_start(void);

bool is_instr(Symbol val);
bool is_directive(Symbol val);
bool is_asm_keyword(Symbol val);
bool is_oberon_keyword(Symbol val);

char *token_to_string(Symbol val);

#endif
