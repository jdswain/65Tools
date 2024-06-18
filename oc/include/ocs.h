#ifndef ORS_H
#define ORS_H

#include <stdbool.h>

/*
Scanner for Oberon compiler
*/  

#define MAX_LINE 80

// Symbols
typedef enum {
#define DEF(tok, str) s ## tok,
#define TOK(tok) s ## tok,
#include "oc_tokens.h"
#undef DEF
#undef TOK
} Symbol;

#define IdLen 1024
#define NofKeys 202

extern Symbol scanner_sym;
extern char scanner_id[];

extern int scanner_ival;
extern double scanner_rval;

extern int scanner_errcnt;

void scanner_init(void);
void scanner_start(void);
void scanner_next(void);
void scanner_mark(char *msg);
void scanner_copyId(char *dest);

char *token_to_string(Symbol val);

#endif
