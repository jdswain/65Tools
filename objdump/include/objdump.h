#include "elf_file.h"
#include "cpu.h"
#include "buffered_file.h"
#include "value.h"

#define OB_VERSION "0.0.1"

int verbose;

char **files;
int num_files;

elf_context_t *elf_context;

int ob_parse_args(int argc, char** argv);
void ob_cleanup(void);
void ob_split_path(void ***p_array, int *p_num_array, const char *in);
void print_recursive(FILE *file, MapNode *root, int *offset, int *col, int step, int columns);
void ob_print_symbols(FILE *file);
char *mode_to_string(enum AddrMode mode);
char *cpu_to_string(ELF_Half cpu);





