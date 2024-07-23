/*
Scanner for Oberon compiler
*/  
#include "ocs.h"

#include <string.h>
#include <strings.h>

#include "buffered_file.h"
#include "memory.h"
#include "cpu.h"

char scanner_id[IdLen];

char ch; // lookahead

char* key[NofKeys];
OSymbol symno[NofKeys];

OSymbol scanner_sym;
int scanner_ival;
double scanner_rval;

char line[2][MAX_LINE];
bool lineno;
int c;
int scanner_errcnt;

int K;

const char *otoken_to_string(OSymbol s);

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
  scanner_sym = osIDENT;
  
  int i = 0;
  int j, m, r;
  do {
    if( i < IdLen-1 ) scanner_id[i++] = ch; 
    next();
  } while( (ch != CH_EOF) && (((ch >= '0') && (ch <= '9')) || ((ch >= 'A') && (ch <= 'Z')) || (ch == '_') || ((ch >= 'a') && (ch <= 'z'))) );
  scanner_id[i] = 0;

  i = 0; 
  j = NofKeys; /* Search for keyword */
    
  while( i < j ) {
	m = (i + j) / 2;
	//	printf("[%d] = %s, compared with %s = %d\n", m, key[m], scanner_id, strcasecmp(key[m],scanner_id));
	r = strcasecmp(key[m],scanner_id);
	if (r < 0) {
	  i = m + 1;
	} else if (r > 0) {
	  j = m;
	} else {
	  i = j = m;
	}
  }
  if( strcasecmp(key[m],scanner_id) == 0 ) {
	scanner_sym = symno[m];
	//	printf("symbol %d = %d:'%s'\n", m, scanner_sym, scanner_id);
  } else {
	//	printf("indent: '%s'\n", scanner_id);
  }
}

void number(void) {
  scanner_ival = 0;
  do {
    scanner_ival = 10 * scanner_ival + ch - '0';
    next();
  } while( ch >= '0' && ch <= '9' && (ch != CH_EOF) );
  if (ch == '.') {
    // ToDo: real
    scanner_sym = osREAL;
  } else {
    scanner_sym = osINT;
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
  scanner_sym = osINT;
}

void binary(void) {
  scanner_ival = 0;
  do {
    scanner_ival = 2 * scanner_ival + ch - '0';
    next();
  } while( ch >= '0' && ch <= '1' && (ch != CH_EOF) );
  scanner_sym = osINT;
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
    // if( ch == CH_EOF ) { scanner_sym = sEOF; next(); return; }

    if( ch < 'A' ) {
      if( ch < '0' ) {
        if( ch == '#' ) { next(); scanner_sym = osNEQ;
        } else if( ch == '$' ) { next(); hex();
        } else if( ch == '%' ) { next(); binary();
        } else if( ch == '&' ) { next(); scanner_sym = osAND;
        } else if( ch == '(' ) { next();
		  if( ch == '*' ) { comment(); scanner_sym = osNULL;
		  } else { scanner_sym = osLPAREN; }
        } else if( ch == ')' ) { next(); scanner_sym = osRPAREN;
        } else if( ch == '*' ) { next(); scanner_sym = osTIMES;
        } else if( ch == '+' ) { next(); scanner_sym = osPLUS;
        } else if( ch == ',' ) { next(); scanner_sym = osCOMMA;
        } else if( ch == '-' ) { next(); scanner_sym = osMINUS;
        } else if( ch == '.' ) { next();
		  if( ch == '.') { next(); scanner_sym = osUPTO;
		  } else { scanner_sym = osPERIOD; }
        } else if( ch == '/' ) { next(); scanner_sym = osRDIV;
        } else if( ch == '"' ) { next(); string(); scanner_sym = osSTRING;
        } else { next(); scanner_sym = osNULL; }
      } else if( ch <= '9' ) { number();
      } else if( ch == ':' ) { next();
		if( ch == '=' ) { next(); scanner_sym = osBECOMES;
		} else { scanner_sym = osCOLON; }
      } else if( ch == ';' ) { next();  scanner_sym = osSEMICOLON;
      } else if( ch == '<' ) { next();
        if( ch == '=' ) { next(); scanner_sym = osLEQ;
		} else { scanner_sym = osLSS; }
	  } else if( ch == '=' ) { next(); scanner_sym = osEQL;
      } else if( ch == '>' ) { next();
        if( ch == '=' ) { next(); scanner_sym = osGEQ;
		} else { scanner_sym = osGTR; }
	  } else if( ch < 'a' ) {
		if( ch <= 'Z' ) { ident();
		} else if( ch == '[' ) { next(); scanner_sym = osLBRAK; 
		} else if( ch == ']' ) { next(); scanner_sym = osRBRAK;
		} else if( ch == '_' ) { ident(); 
		} else if( ch == '^' ) { next(); scanner_sym = osARROW; }
	  } else { /* \ `*/ next(); scanner_sym = osNULL; }
	} else if( ch <= 'z' ) { ident();
	} else if( ch == '{' ) { next(); scanner_sym = osLBRACE;
	} else if( ch == '|' ) { next(); scanner_sym = osBAR;
	} else if( ch == '}' ) { next(); scanner_sym = osRBRACE;
	} else if( ch == '~' ) { next(); scanner_sym = osNOT;
	} else { next(); scanner_sym = osNULL; }
  } while( scanner_sym == osNULL );
  as_warn("%s %s", otoken_to_string(scanner_sym), scanner_id);
}

void scanner_enter(char* word, OSymbol val) {
  key[K] = word;
  symno[K++] = val;
}

void scanner_init()
{
  K = 0;

  scanner_enter("ARRAY", osARRAY);
  scanner_enter("BEGIN", osBEGIN);
  scanner_enter("BY", osBY);
  scanner_enter("CASE", osCASE);
  scanner_enter("CONST", osCONST);
  scanner_enter("DIV", osDIV);
  scanner_enter("DO", osDO);
  scanner_enter("ELSE", osELSE);
  scanner_enter("ELSIF", osELSIF);
  scanner_enter("END", osEND);
  scanner_enter("FALSE", osFALSE);
  scanner_enter("FOR", osFOR);
  scanner_enter("IF", osIF);
  scanner_enter("IMPORT", osIMPORT);
  scanner_enter("IN", osIN);
  scanner_enter("IS", osIS);
  scanner_enter("MOD", osMOD);
  scanner_enter("MODULE", osMODULE);
  scanner_enter("NIL", osNIL);
  scanner_enter("OF", osOF);
  scanner_enter("OR", osOR);
  scanner_enter("POINTER", osPOINTER);
  scanner_enter("PROCEDURE", osPROCEDURE);
  scanner_enter("RECORD", osRECORD);
  scanner_enter("REPEAT", osREPEAT);
  scanner_enter("RETURN", osRETURN);
  scanner_enter("THEN", osTHEN);
  scanner_enter("TO", osTO);
  scanner_enter("TRUE", osTRUE);
  scanner_enter("TYPE", osTYPE);
  scanner_enter("UNTIL", osUNTIL);
  scanner_enter("VAR", osVAR);
  scanner_enter("WHILE", osWHILE);
  
  key[K++] = "~";
  #if debug
    if( K != NofKeys ) printf("There are %d keys, please update NoOfKeys in ocs.h.\n", K);
  #endif

}

void scanner_start()
{
  scanner_errcnt = 0;
  c = 0;
  scanner_sym = osNULL;
  next();
}

char *scanner_CopyId(void) {
  char *dest;
  int l;
  l = strlen(scanner_id);
  dest = as_malloc(l);
  strncpy(dest, (char *)&scanner_id, l);
  return dest;
}

const char *otoken_to_string(OSymbol s) {
  switch (s) {
  case osNULL: return "NULL";
  case osTIMES: return "TIMES";
  case osRDIV: return "RDIV";
  case osDIV: return "DIV";
  case osMOD: return "MOD";
  case osAND: return "AND";
  case osPLUS: return "PLUS";
  case osMINUS: return "MINUS";
  case osOR: return "OR";
  case osEQL: return "EQL";
  case osNEQ: return "NEQ";
  case osLSS: return "LSS";
  case osLEQ: return "LEQ";
  case osGTR: return "GTR";
  case osGEQ: return "GEQ";
  case osIN: return "IN";
  case osIS: return "IS";
  case osARROW: return "ARROW";
  case osPERIOD: return "PERIOD";
  case osCHAR: return "CHAR";
  case osINT: return "INT";
  case osREAL: return "REAL";
  case osFALSE: return "FALSE";
  case osTRUE: return "TRUE";
  case osNIL: return "NIL";
  case osSTRING: return "STRING";
  case osNOT: return "NOT";
  case osLPAREN: return "LPAREN";
  case osLBRAK: return "LBRAK";
  case osLBRACE: return "LBRACE";
  case osIDENT: return "IDENT";
  case osIF: return "IF";
  case osWHILE: return "WHILE";
  case osREPEAT: return "REPEAT";
  case osCASE: return "CASE";
  case osFOR: return "FOR";
  case osCOMMA: return "COMMA";
  case osCOLON: return "COLON";
  case osBECOMES: return "BECOMES";
  case osUPTO: return "UPTO";
  case osRPAREN: return "RPAREN";
  case osRBRAK: return "RBRAK";
  case osRBRACE: return "RBRACE";
  case osTHEN: return "THEN";
  case osOF: return "OF";
  case osDO: return "DO";
  case osTO: return "TO";
  case osBY: return "BY";
  case osSEMICOLON: return "SEMICOLON";
  case osEND: return "END";
  case osBAR: return "BAR";
  case osELSE: return "ELSE";
  case osELSIF: return "ELSIF";
  case osUNTIL: return "UNTIL";
  case osRETURN: return "RETURN";
  case osARRAY: return "ARRAY";
  case osRECORD: return "RECORD";
  case osPOINTER: return "POINTER";
  case osCONST: return "CONST";
  case osTYPE: return "TYPE";
  case osVAR: return "VAR";
  case osPROCEDURE: return "PROCEDURE";
  case osBEGIN: return "BEGIN";
  case osIMPORT: return "IMPORT";
  case osMODULE: return "MODULE";
  case osEOT: return "EOT";
  }
  return "Unknown";
}


