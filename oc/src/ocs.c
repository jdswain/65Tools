/*
Scanner for Oberon compiler
*/  
#include "ocs.h"

#include <string.h>
#include <strings.h>

#include "buffered_file.h"
#include "memory.h"

char scanner_id[IdLen];

char ch; // lookahead
int K;

char* key[NofKeys];
Symbol symno[NofKeys];

Symbol scanner_sym;
int scanner_ival;
double scanner_rval;

char line[2][MAX_LINE];
bool lineno;
int c;

void print_line(void)
{
}

void next(void)
{
  if ((ch == '\n') || (ch == CH_EOF)) {
    line[(lineno?1:0)][c] = '\0';
    if (bf_line() > 2) print_line();
    lineno = !lineno;
    c = 0;
  }
  ch = bf_next(); if( ch == '\r' ) ch = bf_next();
  if (c < MAX_LINE) line[(lineno?1:0)][c++] = ch;
}

/*///////////////////////////////////////
// Basic types
///////////////////////////////////////*/

void ident(void) {
  scanner_sym = sIDENT;
  
  int i = 0;
  int j, m;
  do {
    if( i < IdLen-1 ) scanner_id[i++] = ch; 
    next();
  } while( (ch != CH_EOF) && (((ch >= '0') && (ch <= '9')) || ((ch >= 'A') && (ch <= 'Z')) || (ch == '_') || ((ch >= 'a') && (ch <= 'z'))) );
  scanner_id[i] = 0;

  if (scanner_sym == sIDENT) { /* Don't search labels */
    i = 0; 
    j = NofKeys; /* Search for keyword */
    
    while( i < j ) {
      m = (i + j) / 2;
      if( strcasecmp(key[m],scanner_id) < 0 ) i = m + 1; else j = m;
    }
    if( strcasecmp(key[j],scanner_id) == 0 ) {
	  scanner_sym = symno[j];
    }
  }
  // printf("indent: %s\n", id);
}

void number(void) {
  scanner_ival = 0;
  do {
    scanner_ival = 10 * scanner_ival + ch - '0';
    next();
  } while( ch >= '0' && ch <= '9' && (ch != CH_EOF) );
  if (ch == '.') {
    // ToDo: real
    scanner_sym = sREAL;
  } else {
    scanner_sym = sINTEGER;
  }
}

void hex(void) {
  int d;
  scanner_ival = 0;
  do {
    if( ('0' <= ch) && (ch <= '9') ) d = ch - '0';
    else if( ('A' <= ch) && (ch <= 'F') ) d = ch - 'A' + 10;
    else d = ch - 'a' + 10;
    scanner_ival = 0x10 * scanner_ival + d;
    next();
  } while( (ch != CH_EOF) && ((ch >= '0' && ch <= '9') || ((ch >= 'A') && (ch <= 'F')) || ((ch >= 'a') && (ch <= 'f'))) );
}

void binary(void) {
  scanner_ival = 0;
  do {
    scanner_ival = 2 * scanner_ival + ch - '0';
    next();
  } while( ch >= '0' && ch <= '1' && (ch != CH_EOF) );
}

void string(void) {
  int i = 0;
  do {
    if (ch == '\\') {
      scanner_id[i++] = ch;
      next();
      if ((ch != CH_EOF) && (i < IdLen)) scanner_id[i++] = ch;
    } else {
      scanner_id[i++] = ch;
    }
	next();
  } while( (ch != '"') && (ch != CH_EOF) && (i < IdLen) );
  scanner_id[i] = 0;
  // printf("Parsed string '%s'\n", id);
  next();
}

void comment(void) {
  next();
  while( (ch != CH_EOF) && (ch != '*') ) next(); 
  if( (ch != CH_EOF) ) { next(); if( ch != ')' ) comment(); }
  next();
}

////////////////////////////////////////
// Get
////////////////////////////////////////

void scanner_next(void) {
  do {

    // Skip whitespace
    while( (ch != CH_EOF) && (ch != '\n') && (ch <= ' ') ) {
      next();
    }
    if( ch == CH_EOF ) { scanner_sym = sEOF; next(); return; }

    if( ch < 'A' ) {
      if( ch < '0' ) {
        if( ch == '#' ) { next(); scanner_sym = sNEQ;
        } else if( ch == '&' ) { next(); scanner_sym = sAND;
        } else if( ch == '(' ) { next();
		  if( ch == '*' ) { comment(); scanner_sym = sNULL;
		  } else { scanner_sym = sLPAREN; }
        } else if( ch == ')' ) { next(); scanner_sym = sRPAREN;
        } else if( ch == '*' ) { next(); scanner_sym = sAST;
        } else if( ch == '+' ) { next(); scanner_sym = sPLUS;
        } else if( ch == ',' ) { next(); scanner_sym = sCOMMA;
        } else if( ch == '-' ) { next(); scanner_sym = sMINUS;
        } else if( ch == '.' ) { next();
		  if( ch == '.') { next(); scanner_sym = sDOTDOT;
		  } else { scanner_sym = sPERIOD; }
        } else if( ch == '/' ) { next(); scanner_sym = sSLASH;
        } else if( ch == '"' ) { next(); string(); scanner_sym = sSTRING;
        } else { next(); scanner_sym = sNULL; }
      } else if( ch <= '9' ) { number();
      } else if( ch == ':' ) { next();
		if( ch == '=' ) { next(); scanner_sym = sBECOMES;
		} else { scanner_sym = sCOLON; }
      } else if( ch == ';' ) { scanner_sym = sSEMICOLON;
      } else if( ch == '<' ) { next();
        if( ch == '=' ) { next(); scanner_sym = sLEQ;
		} else { scanner_sym = sLSS; }
	  } else if( ch == '=' ) { next(); scanner_sym = sEQL;
      } else if( ch == '>' ) { next();
        if( ch == '=' ) { next(); scanner_sym = sGEQ;
		} else { scanner_sym = sGTR; }
	  } else if( ch < 'a' ) {
		if( ch <= 'Z' ) { ident();
		} else if( ch == '[' ) { next(); scanner_sym = sLSQ; 
		} else if( ch == ']' ) { next(); scanner_sym = sRSQ;
		} else if( ch == '_' ) { ident(); 
		} else if( ch == '^' ) { next(); scanner_sym = sCARET; }
	  } else { /* \ `*/ next(); scanner_sym = sNULL; }
	} else if( ch <= 'z' ) { ident();
	} else if( ch == '{' ) { next(); scanner_sym = sLBRACE;
	} else if( ch == '|' ) { next(); scanner_sym = sBAR;
	} else if( ch == '}' ) { next(); scanner_sym = sRBRACE;
	} else if( ch == '~' ) { next(); scanner_sym = sTILDE;
	} else { next(); scanner_sym = sNULL; }
  } while( scanner_sym == sNULL );
}

void enter(char* word, Symbol val) {
  key[K] = word;
  symno[K] = val;
}

void scanner_init()
{
  K = 0;

#define DEF(tok, str) enter(str, s ## tok);
#define TOK(tok) ;
#include "oc_tokens.h"
#undef DEF
#undef TOK
  
  key[K++] = "~";
#if debug
  if( K != NofKeys ) printf("There are %d keys, please update NoOfKeys in scanner.c.\n", K);
#endif

  scanner_errcnt = 0;
}

void scanner_start()
{
  c = 0;
  next();
}

void scanner_mark(char *msg) {
  as_error(msg);
}

void scanner_copyId(char *dest) {
  strncpy(dest, (char *)&scanner_id, IdLen);
}

char *token_to_string(Symbol val)
{
 switch( val ) {
#define DEF(tok, str) case s ## tok: return str;
#define TOK(tok) case s ## tok: return #tok;
#include "oc_tokens.h"
#undef DEF
#undef TOK
 }
 return "Unknown token";
}


