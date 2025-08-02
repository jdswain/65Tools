#ifndef CODEGEN_H
#define CODEGEN_H

#include <stdbool.h>
#include <stdint.h>
#include "cpu.h"

extern bool longa;
extern bool longi;

void codegen_gen(OpCode opcode, AddrMode mode, int value1, int value2);
void codegen_byte(int b);
void codegen_word(int w);
void codegen_long(int l);

// Internal code generation functions
void or(uint8_t op, int v);   // Relative branch with calculated offset
void of(uint8_t op, int v);   // Fixup branch with chain link

/* Used for formatting the addressing mode for the listing */
char *codegen_format_mode(AddrMode mode, int value1, int value2);
char *codegen_format_mode_str(AddrMode mode, char *value1, int value2);

#endif
