/*
Scanner for 65Tools assembler
*/  
#include <string.h>

#include "buffered_file.h"
#include "scanner.h"
#include "interp.h"
#include "memory.h"
#include "value.h"

#define IdLen 1024
#define NofKeys 202

enum ScannerMode scannerMode;

char id[IdLen];

char ch; // lookahead
int K;

int org;

// int i;

char* key[NofKeys];
Symbol symno[NofKeys];
uint8_t space1[1024];
uint8_t flags[NofKeys];

int ival;
double rval;

char line[2][MAX_LINE];
bool lineno;
int c;


void print_line(void)
{
  Object *v = object_new(Const, typeString);
  v->string_val = as_strdup(line[(lineno?0:1)]);
  interp_add(OpListLine, v);
}

void next(void)
{
  if ((ch == '\n') || (ch == CH_EOF)) {
    // This is all a bit complex but we need to delay the line by one line
    // so that it matches up with the codegen.
    line[(lineno?1:0)][c] = '\0';
    if ((scannerMode == ASMMode) && ((file == 0) || (bf_line() > 2))) print_line();
    lineno = !lineno;
    c = 0;
  }
  ch = bf_next(); if( ch == '\r' ) ch = bf_next();
  if (c < MAX_LINE) line[(lineno?1:0)][c++] = ch;
}

/*///////////////////////////////////////
// Basic types
///////////////////////////////////////*/

void ident(Symbol *sym) {
  *sym = sIDENT;
  
  int i = 0;
  int j, m;
  do {
    if( i < IdLen-1 ) id[i++] = ch; 
    next();
  } while( (ch != CH_EOF) && (((ch >= '0') && (ch <= '9')) || ((ch >= 'A') && (ch <= 'Z')) || (ch == '_') || ((ch >= 'a') && (ch <= 'z'))) );
  id[i] = 0;

  if (*sym == sIDENT) { /* Don't search labels */
    i = 0; 
    j = NofKeys; /* Search for keyword */
    
    while( i < j ) {
      m = (i + j) / 2;
      if( strcasecmp(key[m],id) < 0 ) i = m + 1; else j = m;
    }
    if( strcasecmp(key[j],id) == 0 ) {
      if (scannerMode == ASMMode) {
		if (is_instr(j) || is_asm_keyword(j) || is_directive(j)) *sym = symno[j];
      }
    }
  }
  // printf("indent: %s\n", id);
}

void number(Symbol *sym) {
  ival = 0;
  do {
    ival = 10 * ival + ch - '0';
    next();
  } while( ch >= '0' && ch <= '9' && (ch != CH_EOF) );
  if (ch == '.') {
    
    // ToDo: real
    *sym = sREAL;
  } else {
    *sym = sINTEGER;
  }
}

void hex(void) {
  int d;
  ival = 0;
  do {
    if( ('0' <= ch) && (ch <= '9') ) d = ch - '0';
    else if( ('A' <= ch) && (ch <= 'F') ) d = ch - 'A' + 10;
    else d = ch - 'a' + 10;
    ival = 0x10 * ival + d;
    next();
  } while( (ch != CH_EOF) && ((ch >= '0' && ch <= '9') || ((ch >= 'A') && (ch <= 'F')) || ((ch >= 'a') && (ch <= 'f'))) );
}

void binary(void) {
  ival = 0;
  do {
    ival = 2 * ival + ch - '0';
    next();
  } while( ch >= '0' && ch <= '1' && (ch != CH_EOF) );
}

void string(void) {
  int i = 0;
  do {
    if (ch == '\\') {
      id[i++] = ch;
      next();
      if ((ch != CH_EOF) && (i < IdLen)) id[i++] = ch;
    } else {
      id[i++] = ch;
    }
     next();
  } while( (ch != '"') && (ch != CH_EOF) && (i < IdLen) );
  id[i] = 0;
  // printf("Parsed string '%s'\n", id);
  next();
}

void charconst(void) {
  ival = 0;
  do {
    ival = ival << 8 | ch;
    next();
  } while( (ch != '\'') && (ch != CH_EOF) );
  next();
}

void comment(void) {
  while( (ch != CH_EOF) && (ch == ';') ) next(); // Skip the ;'s
  while( (ch != CH_EOF) && (ch == ' ') ) next(); // Skip leading spaces

  int i = 0;
  while( (ch != '\n') && (ch != CH_EOF) ) {
     id[i++] = ch;
     next();
  }
  if( ch == '\n' ) next();
  id[i] = 0;
}

void oberon_comment(void) {
  next();
  while( (ch != CH_EOF) && (ch != '*') ) next(); 
  if( (ch != CH_EOF) ) { next(); if( ch != ')' ) oberon_comment(); }
  next();
}

////////////////////////////////////////
// Get
////////////////////////////////////////

void scanner_get(Symbol* sym) {
  do {

    // Skip whitespace
    while( (ch != CH_EOF) && (ch != '\n') && (ch <= ' ') ) {
      next();
    }
    if( ch == CH_EOF ) { *sym = sEOF; next(); return; }

    if( ch < 'A' ) {
      if( ch < '0' ) {
        if( ch == '\n' ) { next(); *sym = sSTATESEP;
       	} else if( ch == '!' ) { next();
          if( ch == '=' ) { next(); *sym = sNEQ;
          } else { next(); *sym = sNOT;
          }
        } else if( ch == '#' ) { next(); *sym = sHASH;
        } else if( ch == '$' ) { next(); hex(); *sym = sINTEGER;
        } else if( ch == '%' ) { next();
		  if( ch == '=' ) { next(); *sym = sMOD_ASN;
		  } else {
			if (ch == '0' || ch == '1') {
			  binary(); *sym = sINTEGER;
			} else {
			  *sym = sMOD;
			}
		  }
        } else if( ch == '&' ) { next();
		  if( ch == '=' ) { next(); *sym = sAND_ASN;
		  } else if( ch == '&' ) { next(); *sym = sLAND;
		  } else { *sym = sAMPERSAND; }
        } else if( ch == '(' ) { next();
		  if( ch == '*' ) { oberon_comment(); *sym = sNULL;
		  } else { *sym = sLPAREN; }
        } else if( ch == ')' ) { next(); *sym = sRPAREN;
        } else if( ch == '*' ) {
		  if( c == 1) {
			comment(); *sym = sNULL;
		  } else {
			next();
			if ( ch == '=' ) { next(); *sym = sMUL_ASN;
			} else { *sym = sAST; }
		  }
        } else if( ch == '+' ) { next();
		  if( ch == '=' ) { next(); *sym = sADD_ASN;
		  } else if( ch == '+') { next(); *sym = sINCOP;
		  } else { *sym = sPLUS; }
        } else if( ch == ',' ) { next(); *sym = sCOMMA;
        } else if( ch == '-' ) { next();
		  if( ch == '=' ) { next(); *sym = sSUB_ASN;
		  } else if( ch == '-') { next(); *sym = sDECOP;
		  } else { *sym = sMINUS; }
        } else if( ch == '.' ) { next();
		  if( ch == '.') { next();
			if (ch == '.') { next();
			  *sym = sELLIPSIS;
			} else {
			  *sym = sDOTDOT;
			}
		  } else {
			*sym = sPERIOD;
		  }
        } else if( ch == '/' ) { next(); *sym = sSLASH;
        } else if( ch == '"' ) { next(); string(); *sym = sSTRING;
        } else if( ch == '\'' ) { next(); charconst(); *sym = sCHAR;
        } else { next(); *sym = sNULL;
        }
      } else if( ch <= '9' ) { number(sym);
      } else if( ch == ':' ) { next();
		if( ch == '=' ) { next(); *sym = sBECOMES; } else { *sym = sCOLON; }
      } else if( ch == ';' ) { comment(); *sym = sSTATESEP;
      } else if( ch == '<' ) { next();
        if( ch == '=' ) { next(); *sym = sLEQ;
		} else if( ch == '<' ) { next();
		  if( ch == '=' ) { next(); *sym = sLEFT_ASN;
		  } else { *sym = sLEFT_SHIFT; }
		} else { *sym = sLSS; }
      } else if( ch == '=' ) { next();
        if( ch == '=' ) { next(); *sym = sEQL; } else { *sym = sBECOMES; }
      } else if( ch == '>' ) { next();
        if( ch == '=' ) { next(); *sym = sGEQ;
		} else if( ch == '>') { next();
		  if( ch == '=' ) { next(); *sym = sRIGHT_ASN;
		  } else { *sym = sRIGHT_SHIFT; }
		} else { *sym = sGTR; }
      } else if( ch == '?' ) { next(); *sym = sQUESTION;
      } else { /* @ */ next(); *sym = sNULL;
      }
    } else if( ch < 'a' ) {
      if( ch <= 'Z' ) { ident(sym);
      } else if( ch == '[' ) { next(); *sym = sLSQ; 
      } else if( ch == ']' ) { next(); *sym = sRSQ;
      } else if( ch == '_' ) { ident(sym); 
      } else if( ch == '^' ) { next();
		if( ch == '=' ) { next(); *sym = sXOR_ASN;
		} else { *sym = sCARET; }
      } else { /* \ `*/ next(); *sym = sNULL;
      }
    } else if( ch <= 'z' ) { ident(sym);
    } else if( ch == '{' ) { next(); *sym = sBLOCKSTART;
    } else if( ch == '|' ) { next();
      if( ch == '=' ) { next(); *sym = sOR_ASN;
      } else if( ch =='|' ) { next(); *sym = sLOR;
      } else { *sym = sBARC; }
    } else if( ch == '}' ) { next(); *sym = sBLOCKEND;
    } else if( ch == '~' ) { next(); *sym = sTILDE;
    } else { next(); *sym = sNULL;
    }
  } while( *sym == sNULL );
  // Note: This crashes when parsing command line args
  // printf("%s: %s\n", file->filename, token_to_string(*sym));
}

void enter(char* word, Symbol val, uint8_t flag) {
  key[K] = word;
  symno[K] = val;
  flags[K++] = flag;
}

void scanner_init(enum ScannerMode mode)
{
  scannerMode = mode;
  
  K = 0;

#define DEF(tok, str, flags) enter(str, s ## tok, flags);
#define TOK(tok) ;
#include "as_tokens.h"
#undef DEF
#undef TOK
  
  key[K++] = "~";
#if debug
  if( K != NofKeys ) printf("There are %d keys, please update NoOfKeys in scanner.c.\n", K);
#endif
}

void scanner_start()
{
  c = 0;
  next();
}

bool is_instr(Symbol val) { return (val < K) && (flags[val] & F_INSTR); }
bool is_directive(Symbol val) { return (val < K) && (flags[val] & F_DIRECTIVE); }
bool is_asm_keyword(Symbol val) { return (val < K) && (flags[val] & F_AKEYWORD); } 

char *token_to_string(Symbol val)
{
 switch( val ) {
#define DEF(tok, str, flags) case s ## tok: return str;
#define TOK(tok) case s ## tok: return #tok;
#include "as_tokens.h"
#undef DEF
#undef TOK
 }
 return "Unknown token";
}


