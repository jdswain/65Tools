#ifndef CODEGEN_H
#define CODEGEN_H

#include "as.h"
#include "scanner.h"

int codegen_params(Instr *instr);
void codegen_gen(char *filename, int line_num, Instr *instr, int value1, int value2, int value3);
void codegen_byte(int b);
void codegen_word(int w);
void codegen_long(int l);

/* Used for formatting the addressing mode for the listing */
char *codegen_format_mode(AddrMode mode, int value1, int value2, int value3);
char *codegen_format_mode_str(AddrMode mode, char *value1, int value2, int value3);

#endif
