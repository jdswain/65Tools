// ORS.c - Oberon Scanner (Lexical Analyzer) Implementation
// Uses new conventions with ORS_ prefix, Texts, and proper types

#include "ORS.h"
#include "Oberon.h"
#include "Texts.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <math.h>

// Constants
#define TAB 0x09
#define LF  0x0A
#define CR  0x0D

// Global variables
ORS_Ident ORS_id;                    // Current identifier
LONGINT ORS_ival;                    // Current integer value
REAL ORS_rval;                       // Current real value
LONGINT ORS_slen;                    // Current string length
char ORS_str[ORS_STRING_LEN];        // Current string value
INTEGER ORS_errcnt;                  // Error count

// Private variables
static Texts_Text *source_text;
static LONGINT source_pos;
static char ch;                      // Current character
static INTEGER errpos;               // Error position

// Keyword table
typedef struct {
    char *name;
    ORS_Symbol sym;
} KeyWord;

static KeyWord keyTab[] = {
    {"ARRAY", ORS_array},
    {"BEGIN", ORS_begin},
    {"BY", ORS_by},
    {"CASE", ORS_case},
    {"CONST", ORS_const},
    {"DIV", ORS_div},
    {"DO", ORS_do},
    {"ELSE", ORS_else},
    {"ELSIF", ORS_elsif},
    {"END", ORS_end},
    {"FALSE", ORS_false},
    {"FOR", ORS_for},
    {"IF", ORS_if},
    {"IMPORT", ORS_import},
    {"IN", ORS_in},
    {"IS", ORS_is},
    {"MOD", ORS_mod},
    {"MODULE", ORS_module},
    {"NIL", ORS_nil},
    {"NOT", ORS_not},
    {"OF", ORS_of},
    {"OR", ORS_or},
    {"POINTER", ORS_pointer},
    {"PROCEDURE", ORS_procedure},
    {"RECORD", ORS_record},
    {"REPEAT", ORS_repeat},
    {"RETURN", ORS_return},
    {"THEN", ORS_then},
    {"TO", ORS_to},
    {"TRUE", ORS_true},
    {"TYPE", ORS_type},
    {"UNTIL", ORS_until},
    {"VAR", ORS_var},
    {"WHILE", ORS_while},
    {NULL, ORS_null}
};

// Forward declarations
static void ReadChar(void);
static void ReadString(void);
static void ReadNumber(void);
static void ReadScaleFactor(void);
static void ReadIdent(void);
static void Comment(void);

// Error reporting
void ORS_Mark(char *msg) {
    INTEGER p;
    
    p = source_pos - 1;  // Position of error
    if (p > errpos && ORS_errcnt < 25) {
        printf("  pos %d  %s\n", p, msg);
        ORS_errcnt++;
    }
    errpos = p + 4;  // Avoid duplicate error messages
}

// Get current position in source
LONGINT ORS_Pos(void) {
    return source_pos;
}

// Read next character from source
static void ReadChar(void) {
    if (source_text && source_pos < source_text->len) {
        ch = source_text->data[source_pos];
        source_pos++;
    } else {
        ch = 0;  // EOF
    }
    // printf("DEBUG: ReadChar: ch=%d, pos=%ld\n", ch, source_pos);
}

// Read string literal
static void ReadString(void) {
    INTEGER i = 0;
    ReadChar();  // Skip opening quote
    
    while (ch != '"' && ch != 0 && ch != CR && ch != LF) {
        if (i < ORS_STRING_LEN - 1) {
            ORS_str[i] = ch;
            i++;
        }
        ReadChar();
    }
    
    ORS_str[i] = 0;
    ORS_slen = i + 1;  // Include null terminator
    
    if (ch == '"') {
        ReadChar();  // Skip closing quote
    } else {
        ORS_Mark("string not terminated");
    }
}

// Read scale factor for real numbers (E notation)
static void ReadScaleFactor(void) {
    REAL s, e;
    
    s = 1.0;
    ReadChar();  // Skip 'E' or 'D'
    
    if (ch == '+') {
        ReadChar();
    } else if (ch == '-') {
        s = -1.0;
        ReadChar();
    }
    
    e = 0.0;
    while (isdigit(ch)) {
        e = e * 10.0 + (ch - '0');
        ReadChar();
    }
    
    if (e <= 38) {
        e = 1.0;
        while (s > 0) {
            e = e * 10.0;
            s = s - 1.0;
        }
        while (s < 0) {
            e = e / 10.0;
            s = s + 1.0;
        }
        ORS_rval = ORS_rval * e;
    } else {
        ORS_Mark("too large");
        ORS_rval = 0.0;
    }
}

// Read number (integer or real)
static void ReadNumber(void) {
  INTEGER i, k, d; //, n;
    REAL x;
    // BOOLEAN negE;
    
    ORS_ival = 0;
    k = 0;
    
    // Read integer part
    do {
        if (k < 16) {  // Avoid overflow
            d = ch - '0';
            if (ORS_ival <= (LONGINT)(2147483647 - d) / 10) {
                ORS_ival = ORS_ival * 10 + d;
                k++;
            } else {
                ORS_Mark("number too large");
                ORS_ival = 0;
            }
        }
        ReadChar();
    } while (isdigit(ch));
    
    if (ch == '.') {
        ReadChar();
        if (ch == '.') {
            // This is ".." (range operator), back up
            ch = 0x7F;  // Special marker for ".."
        } else {
            // Real number
            x = (REAL)ORS_ival;
            ORS_rval = x;
            i = 0;
            
            while (isdigit(ch)) {
                x = (ch - '0');
                i++;
                ReadChar();
                ORS_rval = ORS_rval + x / pow(10.0, i);
            }
            
            if (ch == 'E' || ch == 'D') {
                ReadScaleFactor();
            }
        }
    } else if (ch == 'H') {
        // Hexadecimal number
        ReadChar();
        if (ORS_ival > (LONGINT)0xFFFFFFFF) {
            ORS_Mark("hexadecimal number too large");
            ORS_ival = 0;
        }
    } else if (ch == 'X') {
        // Character constant
        ReadChar();
        if (ORS_ival < 256) {
            // Valid character code
        } else {
            ORS_Mark("invalid character");
            ORS_ival = 0;
        }
    }
}

// Read identifier
static void ReadIdent(void) {
    INTEGER i, k;
    
    i = 0;
    do {
        if (i < ORS_IDENT_LEN - 1) {
            ORS_id[i] = ch;
            i++;
        }
        ReadChar();
    } while (isalnum(ch) || ch == '_');
    
    ORS_id[i] = 0;
}

// Skip comment
static void Comment(void) {
    ReadChar();  // Skip '*'
    
    do {
        while (ch != '*' && ch != 0) {
            if (ch == '(' && source_pos < source_text->len && 
                source_text->data[source_pos] == '*') {
                Comment();  // Nested comment
            } else {
                ReadChar();
            }
        }
        
        if (ch == '*') {
            ReadChar();
        }
    } while (ch != ')' && ch != 0);
    
    if (ch == ')') {
        ReadChar();
    } else {
        ORS_Mark("comment not closed");
    }
}

// Get next symbol
void ORS_Get(INTEGER *sym) {
    INTEGER k;
    INTEGER loop_count = 0;
    
    // Skip whitespace and comments with safety counter
    while (ch != 0 && (ch <= ' ' || (ch == '(' && source_pos < source_text->len && 
                                     source_text->data[source_pos] == '*'))) {
        loop_count++;
        if (loop_count > 1000) {  // Safety limit to prevent infinite loops
            ch = 0;  // Force EOF
            break;
        }
        
        if (ch == '(' && source_pos < source_text->len && 
            source_text->data[source_pos] == '*') {
            ReadChar();  // Skip '('
            Comment();   // Parse comment
        } else {
            ReadChar();  // Skip whitespace
        }
    }
    
    if (isalpha(ch)) {
        ReadIdent();
        
        // Check for keyword
        k = 0;
        while (keyTab[k].name != NULL) {
            if (strcmp(ORS_id, keyTab[k].name) == 0) {
                *sym = keyTab[k].sym;
                return;
            }
            k++;
        }
        *sym = ORS_ident;
        
    } else if (isdigit(ch)) {
        ReadNumber();
        if (ch == '.') {
            *sym = ORS_real;
        } else {
            *sym = ORS_int;
        }
        
    } else {
        switch (ch) {
            case 0:
                *sym = ORS_eof;
                break;
            case '"':
                ReadString();
                *sym = ORS_string;
                break;
            case '\'':
                ReadChar();
                ORS_ival = ch;
                ReadChar();
                if (ch == '\'') {
                    ReadChar();
                    *sym = ORS_char;
                } else {
                    ORS_Mark("' expected");
                    *sym = ORS_char;
                }
                break;
            case '#':
                ReadChar();
                *sym = ORS_neq;
                break;
            case '&':
                ReadChar();
                *sym = ORS_and;
                break;
            case '(':
                ReadChar();
                *sym = ORS_lparen;
                break;
            case ')':
                ReadChar();
                *sym = ORS_rparen;
                break;
            case '*':
                ReadChar();
                *sym = ORS_times;
                break;
            case '+':
                ReadChar();
                *sym = ORS_plus;
                break;
            case ',':
                ReadChar();
                *sym = ORS_comma;
                break;
            case '-':
                ReadChar();
                *sym = ORS_minus;
                break;
            case '.':
                ReadChar();
                if (ch == '.') {
                    ReadChar();
                    *sym = ORS_upto;
                } else {
                    *sym = ORS_period;
                }
                break;
            case '/':
                ReadChar();
                *sym = ORS_rdiv;
                break;
            case ':':
                ReadChar();
                if (ch == '=') {
                    ReadChar();
                    *sym = ORS_becomes;
                } else {
                    *sym = ORS_colon;
                }
                break;
            case ';':
                ReadChar();
                *sym = ORS_semicolon;
                break;
            case '<':
                ReadChar();
                if (ch == '=') {
                    ReadChar();
                    *sym = ORS_leq;
                } else {
                    *sym = ORS_lss;
                }
                break;
            case '=':
                ReadChar();
                *sym = ORS_eql;
                break;
            case '>':
                ReadChar();
                if (ch == '=') {
                    ReadChar();
                    *sym = ORS_geq;
                } else {
                    *sym = ORS_gtr;
                }
                break;
            case '[':
                ReadChar();
                *sym = ORS_lbrak;
                break;
            case ']':
                ReadChar();
                *sym = ORS_rbrak;
                break;
            case '^':
                ReadChar();
                *sym = ORS_arrow;
                break;
            case '{':
                ReadChar();
                *sym = ORS_lbrace;
                break;
            case '|':
                ReadChar();
                *sym = ORS_bar;
                break;
            case '}':
                ReadChar();
                *sym = ORS_rbrace;
                break;
            case '~':
                ReadChar();
                *sym = ORS_not;
                break;
            case 0x7F:  // Special marker for ".."
                ch = '.';  // Restore for next call
                *sym = ORS_period;
                break;
            default:
                ReadChar();
                *sym = ORS_null;
                ORS_Mark("illegal character");
                break;
        }
    }
    // printf("DEBUG: Got symbol %d\n", *sym);
}

// Copy current identifier
void ORS_CopyId(ORS_Ident dest) {
    strcpy(dest, ORS_id);
}

// Initialize scanner
void ORS_Init(Texts_Text *T, LONGINT pos) {
    source_text = T;
    source_pos = pos;
    ORS_errcnt = 0;
    errpos = 0;
    
    // Initialize scanner state
    ORS_id[0] = 0;
    ORS_ival = 0;
    ORS_rval = 0.0;
    ORS_slen = 0;
    ORS_str[0] = 0;
    
    // Read first character
    ReadChar();
}
