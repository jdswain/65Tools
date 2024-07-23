#ifndef CODEGEN_H
#define CODEGEN_H

#include "cpu.h"
#include "elf_file.h"

void codegen_init(const char *mname, ELF_Half e_machine, long entry);
void codegen_close(void);

int codegen_params(Instr *instr);
void codegen_gen(const char *filename, int line_num, Instr *instr, int value1, int value2, int value3);
void codegen_byte(int b);
void codegen_word(int w);
void codegen_long(int l);

long codegen_here(void);
void codegen_addr(long addr);

int codegen_getb(long addr);
int codegen_getw(long addr);
void codegen_updateb(long addr, int b);
void codegen_updatew(long addr, int w);

/* For 816 */
bool codegen_longa(void);
void codegen_setlonga(bool l);
bool codegen_longi(void);
void codegen_setlongi(bool l);

/* Used for formatting the addressing mode for the listing */
char *codegen_format_mode(AddrMode mode, int value1, int value2, int value3);
char *codegen_format_mode_str(AddrMode mode, const char *value1, int value2, int value3);

#endif
