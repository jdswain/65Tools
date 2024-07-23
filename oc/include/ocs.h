#ifndef ORS_H
#define ORS_H

#include <stdbool.h>

/*
Scanner for Oberon compiler
*/  

#define debug 1
#define MAX_LINE 80

// Lexical Symbols
#define osNULL 0
#define osTIMES 1
#define osRDIV 2
#define osDIV 3
#define osMOD 4
#define osAND 5
#define osPLUS 6
#define osMINUS 7
#define osOR 8
#define osEQL 9
#define osNEQ 10
#define osLSS 11
#define osLEQ 12
#define osGTR 13
#define osGEQ 14
#define osIN 15
#define osIS 16
#define osARROW 17
#define osPERIOD 18
#define osCHAR 20
#define osINT 21
#define osREAL 22
#define osFALSE 23
#define osTRUE 24
#define osNIL 25
#define osSTRING 26
#define osNOT 27
#define osLPAREN 28
#define osLBRAK 29
#define osLBRACE 30
#define osIDENT 31
#define osIF 32
#define osWHILE 34
#define osREPEAT 35
#define osCASE 36
#define osFOR 37
#define osCOMMA 40
#define osCOLON 41
#define osBECOMES 42
#define osUPTO 43
#define osRPAREN 44
#define osRBRAK 45
#define osRBRACE 46
#define osTHEN 47
#define osOF 48
#define osDO 49
#define osTO 50
#define osBY 51
#define osSEMICOLON 52
#define osEND 53
#define osBAR 54
#define osELSE 55
#define osELSIF 56
#define osUNTIL 57
#define osRETURN 58
#define osARRAY 60
#define osRECORD 61
#define osPOINTER 62
#define osCONST 63
#define osTYPE 64
#define osVAR 65
#define osPROCEDURE 66
#define osBEGIN 67
#define osIMPORT 68
#define osMODULE 69
#define osEOT 70

typedef int OSymbol;

#define IdLen 1024
#define NofKeys 34

extern OSymbol scanner_sym;
extern char scanner_id[];

extern int scanner_ival;
extern double scanner_rval;

extern int scanner_errcnt;

void scanner_init(void);
void scanner_start(void);
void scanner_next(void);
void scanner_mark(char *msg);
char *scanner_CopyId(void);

#endif
