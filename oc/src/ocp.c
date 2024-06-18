#include "ocp.h"

#include <stdio.h>

#include "ocs.h"
#include "ocb.h"
#include "ocg.h"
#include "buffered_file.h"

/*
  Oberon Compiler Parser
*/

struct PtrBase {
  char *name;
  struct Type *type;
  struct PtrBase *next;
};
  
int dc;
char modid[IdLen];
int level;
int exno;
bool newSF; /* Option flag */
struct PtrBase *pbsList;

void parser_check(Symbol sym, char *msg) {
  if (scanner_sym == sym) {
	scanner_next();
  } else {
	printf("%s\n", msg);
  }
}

void parser_typeTest(void) {
}

void parser_selector(void) {
}

void parser_parameter(void) {
}

void parser_parameterList(void) {
}

void parser_element(void) {
}

void parser_set(void) {
}

void parser_factor(void) {
}

void parser_term(void) {
}

void parser_simpleExpression(void) {
}

void parser_expression(void) {
}

void parser_statSequence(void) {
}

void parser_identList(void) {
}

void parser_arrayType(void) {
}

void parser_recordType(void) {
}
  
void parser_formalType(void) {
}

void parser_fpsection(void) {
}

void parser_signature(void) {
}

void parser_type(void) {
}

void parser_declarations(int dc) {
}

void parser_procedureDecl(void) {
}

void parser_import(void) {
}

void parser_module(void) {
  long key;

  printf( "  compiling ");
  scanner_next();
  if (scanner_sym == sMODULE) {
	scanner_next();
	if (scanner_sym == sAST) {
	  dc = 8;
	  printf("*");
	  scanner_next();
	} else {
	  dc = 0;
	}
	base_init();
	base_openScope();
	if (scanner_sym == sIDENT) {
	  scanner_copyId(modid);
	  scanner_next();
	  printf("%s", modid);
	} else {
	  scanner_mark("identifier expected");
	}
	parser_check(sSEMICOLON, "no ;"); level = 0; exno = 1; key = 0;
	if (scanner_sym == sIMPORT) {
	  scanner_next();
	  parser_import();
	  while (scanner_sym == sCOMMA) { scanner_next(); parser_import(); }
	  parser_check(sSEMICOLON, "; missing");
	}
	gen_open();
	parser_declarations(dc);
	gen_setDataSize((dc + 3) / 4 * 4);
	while (scanner_sym == sPROCEDURE) {
	  parser_procedureDecl();
	  parser_check(sSEMICOLON, "no ;");
	}
	gen_header();
	if (scanner_sym == sBEGIN) {
	  scanner_next();
	  parser_statSequence();
	}
	parser_check(sEND, "no end");
	if (scanner_sym == sIDENT) {
	  if (scanner_id != modid) { scanner_mark("no match"); }
	  scanner_next();
	} else { scanner_mark("identifier missing"); }
	if (scanner_sym != sPERIOD) { scanner_mark("period missing"); }
	if (scanner_errcnt == 0) {
	  base_export(modid, newSF, key);
	  if (newSF) { printf(" new symbol file\n"); }
	}
	if (scanner_errcnt == 0) {
	  gen_close(modid, key, exno);
	  printf("%d %d %0lx'", gen_pc, dc, key);
	} else {
	  printf("\ncompilation FAILED\n");
	}
	printf("\n");
	base_closeScope();
	pbsList = 0;
  } else {
	scanner_mark("must start with MODULE");
  }
}

void compile(const char* file) {
  bf_init();
  bf_open(file);
  scanner_init();
  scanner_start();
  parser_module();
  bf_close();
}

int main(int argc, char** argv) {
  compile(argv[1]);
  return 0;
}
