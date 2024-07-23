# 0 "include/ocs.h"
# 0 "<built-in>"
# 0 "<command-line>"
# 1 "/usr/include/stdc-predef.h" 1 3 4
# 0 "<command-line>" 2
# 1 "include/ocs.h"



# 1 "/usr/lib/gcc/aarch64-linux-gnu/13/include/stdbool.h" 1 3 4
# 5 "include/ocs.h" 2
# 14 "include/ocs.h"
typedef enum {


# 1 "include/oc_tokens.h" 1


sARRAY,
sBEGIN,
sBY,
sCASE,
sCHAR,
sCONST,
sDIV,
sDO,
sELSE,
sELSIF,
sEND,
sEXIT,
sFALSE,
sFOR,
sIF,
sIMPORT,
sIN,
sIS,
sLOOP,
sMOD,
sMODULE,
sNIL,
sOF,
sOR,
sPOINTER,
sPROCEDURE,
sRECORD,
sREPEAT,
sRETURN,
sTHEN,
sTO,
sTRUE,
sTYPE,
sUNTIL,
sVAR,
sWHILE,
sWITH,

sIDENT,
sINTEGER,
sREAL,
sSTRING,
sPLUS,
sMINUS,
sAST,
sSLASH,
sTILDE,
sAND,
sPERIOD,
sCOMMA,
sSEMICOLON,
sBAR,
sLPAREN,
sRPAREN,
sLSQ,
sRSQ,
sLBRACE,
sRBRACE,
sBECOMES,
sCARET,
sEQL,
sNEQ,
sLSS,
sLEQ,
sGTR,
sGEQ,
sDOTDOT,
sCOLON,
sNULL,
sEOF,
# 18 "include/ocs.h" 2


} Symbol;




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
