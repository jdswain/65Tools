#ifndef SCANNER_H
#define SCANNER_H

#include <stdbool.h>
#include "cpu.h" /* For symbols */

/*
Scanner for 65Tools assembler
*/  

extern const int IdLen;
extern const int NofKeys;

extern char id[];

extern int ival;
extern double rval;

extern int org;

void scanner_ident(Symbol* sym);
void scanner_get(Symbol* sym);
void scanner_init(void);
void scanner_start(void);

bool is_instr(Symbol val);
bool is_directive(Symbol val);
bool is_asm_keyword(Symbol val);

#endif
