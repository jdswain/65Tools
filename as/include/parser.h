#ifndef PARSER_H
#define PARSER_H

#include "scanner.h"

void parse_define(Symbol *sym);
void parse_asm_file(Symbol *sym);
void parse_oberon_file(Symbol *sym);


#endif
