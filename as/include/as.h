#ifndef AS_H
#define AS_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

#include "scanner.h"
#include "value.h"
#include "elf.h"
#include "elf_file.h"
#include "buffered_file.h"

#include "cpu.h"

#define AS_VERSION "0.0.1"

#define INCLUDE_STACK_SIZE 8

#define MAX_LINE 132
#define MAX_INCLUDE_PATHS 10

typedef Symbol OpCode;
struct Instr {
  OpCode opcode;
  AddrMode mode;
  Modifier modifier;
};
typedef struct Instr Instr;

//////////////////////////////
// Global variables

/* Used by parse_args only */
extern char **files;
extern int num_files;

/* Include search paths */
extern char **include_paths;
extern int num_include_paths;

extern char *output_file;

// Output
extern FileType output_mode;

extern MacroDef *macro; /* The executing macro */
extern int macro_end; /* Flag for macro ending */

extern uint8_t verbose; // Counter for verbosity level

// Assembly state
extern uint32_t addr; // Current output address
extern uint32_t pc; // Current pc
extern bool longa;
extern bool longi;
extern ELF_Half cpu;
int pass(void); // Pass number
extern uint16_t dbreg;
extern uint16_t dpage;
extern uint16_t pbreg;

/* Listing */
extern bool list; // Listing on or off

// End Globals

void as_init(void);
int as_parse_args(int argc, char** argv);
void as_cleanup(void);
void as_open_output(const char *name);
void as_compile(const char *file);
void as_close_output(void);
void as_print_stats(uint64_t total_time);

// Context
int as_add_include_path(const char *path);
Object *as_get_symbol(char *ident);
void as_define_symbol(const char *name, Object *value);
void as_print_symbols(FILE *file);

MacroDef *as_get_macro(char *ident);
void as_define_macro(char *ident, MacroDef *value);


#endif
