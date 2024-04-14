#include <stdio.h>

#include "memory.h"
#include "scanner.h"
#include "parser.h"
#include "interp.h"
#include "elf_file.h"
#include "codegen.h"

//////////////////////////////
// Global variables

/* Used by parse_args only */
char **files;
int num_files;

/* Include search paths */
char **include_paths;
int num_include_paths;

char *output_file;

Object *scope_root;

// Output
FileType output_mode;

MacroDef *macro; /* The executing macro */

uint8_t verbose; // Counter for verbosity level

// Assembly state
uint32_t addr; // Current output address
uint32_t pc; // Current pc
bool longa;
bool longi;
uint8_t _pass; // Pass number
uint16_t dbreg;
uint16_t dpage;
uint16_t pbreg;

int pass(void) { return _pass; }

/* Listing */
bool list; // Listing on or off

// End Globals

void as_print_include_paths(void);

void help(void) {
  printf("as version " AS_VERSION " - 65XXX Assembler - Copyright 2020 Jason Swain.\n"
	 "Usage: as [options...] [-o outfile] infile(s)...\n"
	 "General Options\n"
	 "  -o outfile  set output file name\n"
	 "  -v          verbose output\n"
	 "  -h          show help\n"
	 "  -Idir       add include path 'dir'\n"
	 "  -Dsym[=val] define 'sym' with value 'val'\n"
	 );
}

int main(int argc, char **argv) {
  value_init();
  as_init();
  scanner_init(ASMMode); // We need this for the args
  int optind = as_parse_args(argc - 1, argv + 1);

  if (optind == 0) {
    help();
    return 1;
  }
  
  if (num_files == 0) {
    as_error("No input files");
    return 1;
  }

  if (output_mode != FileNone) {
    char **file = files;
    while ((*file != 0) && (error_count == 0)) {
      as_compile(*file);
      file++;
    }

	if (error_count == 0) {
	  as_close_output();
	}
  }

  as_cleanup();
  
  return 0;
}

void define_bool(const char *key, bool val)
{
  Object *value = object_new(Const, typeBool);
  value->bool_val = val;
  as_define_symbol(key, value);
  object_release(value);
}

void as_init(void)
{
  files = 0;
  num_files = 0;
  scope_root = object_new(Const, typeNoType);
  scope = scope_root;
  current_level = 0;
}

typedef struct ASOption {
  const char *name;
  uint16_t index;
  uint16_t flags;
} ASOption;

enum {
  AS_OPTION_HELP,
  AS_OPTION_I,
  AS_OPTION_D,
  AS_OPTION_v,
  AS_OPTION_o
};

#define AS_OPTION_HAS_ARG 0x0001
#define AS_OPTION_NO_SEP 0x0002

static const ASOption as_options[] = {
  { "h", AS_OPTION_HELP, 0 },
  { "-help", AS_OPTION_HELP, 0 },
  { "?", AS_OPTION_HELP, 0 },
  { "I", AS_OPTION_I, AS_OPTION_HAS_ARG },
  { "D", AS_OPTION_D, AS_OPTION_HAS_ARG },
  { "o", AS_OPTION_o, AS_OPTION_HAS_ARG },
  { "v", AS_OPTION_v, AS_OPTION_HAS_ARG | AS_OPTION_NO_SEP },
};

int strstart(const char *val, const char **str)
{
  const char *p, *q;
  p = *str;
  q = val;
  while (*q) {
    if (*p != *q)
      return 0;
    p++;
    q++;
  }
  *str = p;
  return 1;
}

void parse_option_D(const char *optarg)
{
  if (section == 0) {
    as_error("Output file must be set before defines.");
    return;
  }

  Symbol sym;

  // We use the parser here so that expressions can be used
  bf_memory(optarg, strlen(optarg));
  printf("optarg is '%s'", optarg);
  scanner_start();
  scanner_get(&sym);
  parse_define(&sym);

  interp_run(0);
}


int as_parse_args(int argc, char** argv)
{
  int optind = 0;
  const char *optarg, *r;
  const ASOption *popt;
  
  while (optind < argc) {
    r = argv[optind++];

    /* Files, any item that doesn't start with - or is '-' */
    if (r[0] != '-' || r[1] == '\0') {
      list_add((void ***)&files, &num_files, as_strdup(r));
#if debug
      printf("Added '%s'\n", r);
#endif
      continue;
    }

    /* find option in table */
    for(popt = as_options; ; ++popt) {
      const char *p1 = popt->name;
      const char *r1 = r + 1;
      if (p1 == 0)
        as_error(0, "Invalid option -- '%s'", r);
      if (!strstart(p1, &r1))
        continue;
      optarg = r1;
      if (popt->flags & AS_OPTION_HAS_ARG) {
        if (*r1 == '\0' && !(popt->flags & AS_OPTION_NO_SEP)) {
          if (optind >= argc)
            as_error(0, "Argument to option '%s' is missing", r);
          optarg = argv[optind++];
        }
      } else if (*r1 != '\0')
        continue;
      break;
    }

    switch(popt->index) {
    case AS_OPTION_HELP:
      return 0;
    case AS_OPTION_I:
      if (as_add_include_path(optarg) < 0)
        as_error("Too many include paths.");
      break;
    case AS_OPTION_D:
      parse_option_D(optarg);
      break;
    case AS_OPTION_v:
      do ++verbose; while (*optarg++ == 'v');
      break;
    case AS_OPTION_o:
      as_open_output(optarg);
    }
  }

#if debugx
  printf("%d input files.\n", num_files);

  char **file = files;
  for( int i = 0; i < num_files; i++)
    printf("File is '%s'\n", *file); file++;
#endif
  
  return optind;
}

void as_cleanup(void)
{
  list_reset((void ***)&files, &num_files);
  elf_release(elf_context);
  // as_print_include_paths();
}

void create_standard_file(void)
{
  // Just a marker for stack size requirements
  elf_context->section_stack = elf_section_create(elf_context, "stack",
												  SHF_WRITE | SHF_ALLOC | SHF_STACK,
												  SHT_NOBITS); 
  // Direct page
  elf_context->section_dp = elf_section_create(elf_context, "dp",
											   SHF_WRITE | SHF_ALLOC | SHF_DP,
											   SHT_NOBITS); 
  // Thread local storage
  elf_context->section_tls = elf_section_create(elf_context, "tls",
												SHF_WRITE | SHF_ALLOC | SHF_TLS,
												SHT_NOBITS); 
 // Uninitalised data
  elf_context->section_bss = elf_section_create(elf_context, "bss",
												SHF_WRITE | SHF_ALLOC,
												SHT_NOBITS);
  // Initialised data
  elf_context->section_data = elf_section_create(elf_context, "data",
												 SHF_WRITE | SHF_ALLOC,
												 SHT_PROGBITS); 
  // Constants
  elf_context->section_rodata = elf_section_create(elf_context, "rodata",
												   SHF_ALLOC,
												   SHT_PROGBITS);
  // The default code
  elf_context->section_text = elf_section_create(elf_context, "text",
												 SHF_ALLOC | SHF_EXECINSTR,
												 SHT_PROGBITS); 
  elf_context->section_text->shdr->sh_addr = 0x8000; // Default
  section = elf_context->section_text;
  
  int a, b, c;
  char *buffer = as_malloc(12);
  
  sscanf(AS_VERSION, "%d.%d.%d", &a, &b, &c);
  snprintf(buffer, 12, "%d", a*10000 + b*100 + c);
  Object *value = object_new(Const, typeString);
  value->string_val = buffer;
  /* Can't set with as_define_symbol */
  scope_add_object("__65AS__", value);
  object_release(value);
  
  // Special constants
  define_bool("off", 0);
  define_bool("on", 1);
  define_bool("false", 0);
  define_bool("true", 1);
  define_bool("no", 0);
  define_bool("yes", 1);
}

void as_open_output(const char *name)
{
  output_mode = as_file_type(name);
  switch (output_mode) {
  case FileExecutable:
    elf_context = elf_create(name, EM_816);
    elf_context->ehdr->e_type = ET_EXEC;
    create_standard_file();
    break;
  case FileObject:
    elf_context = elf_create(name, EM_816);
    elf_context->ehdr->e_type = ET_REL;
    create_standard_file();
    break;
  case FileLib:
    elf_context = elf_create(name, EM_816);
    elf_context->ehdr->e_type = ET_EXEC;
    create_standard_file();
    break;
  case FileDylib:
    elf_context = elf_create(name, EM_816);
    elf_context->ehdr->e_type = ET_DYN;
    create_standard_file();
    break;
  case FileNone:
  case FileBinary:
  case FileS19:
  case FileS28:
  case FileS37:
  case FileIntel:
  case FileTIM:
    elf_context = elf_create(name, EM_02);
    elf_context->ehdr->e_type = ET_EXEC;
    create_standard_file();
    break;
  case FileAsmSrc:
  case FileLinkMap:
  case FileCHeader:
  case FileOberonSrc:
  case FileUnknown:
    as_error("Invalid output file specified '%s'", name);
    
  };
}

/**
   This function writes the current symbols to the symtab
*/
void as_write_symbols(MapNode *node)
{
  if (node != 0) {
	as_write_symbols(node->left);
    if (!node->value->is_local) {
	  unsigned char info = 0;
	  // We shouldn't write local symbols to the symbol table, but it's useful
	  // for debugging
	  if (node->value->is_local) info &= STB_LOCAL;
	  if (node->value->is_global) info &= STB_GLOBAL;
	  elf_symbol_create(elf_context, node->key, node->value->int_val, info, 0);
    }
	as_write_symbols(node->right);
  }

}

void as_compile(const char *filename)
{
  Symbol sym;
  int code_len = 0, last_code_len = 0;
  _pass = 1;
  
  bf_init();
  
  if (bf_open(filename)) {
    switch (as_file_type(filename)) {
    case FileAsmSrc:
      printf("Assembling '%s'\n", filename);
	  scanner_init(ASMMode);
	  scanner_start();
	  scanner_get(&sym);
      parse_asm_file(&sym);
      break;
    default:
      as_error("Unknown file type: %s", filename);
    }
	// printf("Close %s\n", file->filename);
    bf_close();
	if (error_count == 0) {
	  _pass++;
	  code_len = interp_run(filename);
	  while (code_len != last_code_len) {
		_pass++;
		last_code_len = code_len;
		code_len = interp_run(filename);
	  }
	  _pass = 0;
	  interp_run(filename); // Output pass
	  as_write_symbols(scope->desc);
	} else {
	  printf("Compilation failed.\n");
	}
  } else {
    as_error("Couldn't open file: %s\n", filename);
  }
}

void as_close_output(void)
{
  switch (output_mode) {
  case FileNone:
    break;
  case FileExecutable:
    elf_write_executable(elf_context);
    break;
  case FileObject:
    elf_write_object(elf_context);
    break;
  case FileLib:
  case FileDylib:
    break;
  case FileS19:
    elf_write_s19(elf_context);
    break;
  case FileS28:
    elf_write_s28(elf_context);
    break;
  case FileS37:
    elf_write_s19(elf_context);
    break;
  case FileIntel:
    elf_write_intel(elf_context);
    break;
  case FileTIM:
    elf_write_tim(elf_context);
    break;
  case FileBinary:
    elf_write_binary(elf_context);
    break;
  case FileAsmSrc:
  case FileLinkMap:
  case FileCHeader:
  case FileOberonSrc:
  case FileUnknown:
    break;
  };
  elf_release(elf_context);
  elf_context = 0;
}

void as_print_stats(uint64_t total_time)
{
}

// Context
void as_split_path(void ***p_array, int *p_num_array, const char *in)
{
  const char *p;
  do {
    int i = 0;
    char c;
    char buffer[MAX_PATH];

    for (p = in; c = *p, c != '\0' && c != PathSep; ++p) {
      buffer[i++] = c;
    }
    buffer[i] = '\0';
    list_add(p_array, p_num_array, as_strdup(buffer));
    in = p + 1;
  } while (*p);
}

int as_add_include_path(const char *path)
{
  if (num_include_paths == MAX_INCLUDE_PATHS) return 0;
  as_split_path((void ***)&include_paths, &num_include_paths, path);
  return num_include_paths;
}

// Context
Object *make_value_str(char *s)
{
  Object *v = object_new(Const, typeString);
  v->string_val = as_strdup(s);
  return v;
}

Object *make_value_int(int i)
{
  Object *v = object_new(Const, typeInt);
  v->int_val = i;
  return v;
}

char *cpu_string()
{
  switch (elf_context->ehdr->e_machine) {
  case EM_NONE: return "None";
  case EM_816: return "65C816";
  case EM_C02: return "65C02";
  case EM_02: return "6502";
  case EM_RC02: return "Rockwell 65C02";
  case EM_RC19: return "Rockwell C19";
  }
  return "Unknown";
}

Object *as_get_symbol(char *ident)
{
  // ToDo: this leaks memory becaue the special values should be released, but the scope objects shouldn't
  // First we do the special values, so that they cannot be overridden.
  if (strcmp("__FILE__", ident) == 0) return make_value_str(file->filename);
  if (strcmp("__LINE__", ident) == 0) return make_value_int(file->line_num);
  // __65AS__ defined in root scope  
  if (strcasecmp("org", ident) == 0) return make_value_int(section->shdr->sh_addr);
  if (strcasecmp("addr", ident) == 0) return make_value_int(addr);
  if (strcasecmp("pc", ident) == 0) return make_value_int(pc);
  if (strcasecmp("longa", ident) == 0) return make_value_int(longa);
  if (strcasecmp("longi", ident) == 0) return make_value_int(longi);
  if (strcasecmp("cpu", ident) == 0) return make_value_str(cpu_string());
  if (strcasecmp("pass", ident) == 0) return make_value_int(pass());
  if (strcasecmp("dbreg", ident) == 0) return make_value_int(dbreg);
  if (strcasecmp("dpage", ident) == 0) return make_value_int(dpage);
  if (strcasecmp("pbreg", ident) == 0) return make_value_int(pbreg);

  return scope_find_object(ident);
}

void as_define_symbol(const char *name, Object *object)
{
  // First we do the special values, so that they cannot be overridden.
  if (strcmp("__FILE__", name) == 0) { as_error("__FILE__ cannot be set"); return; }
  if (strcmp("__LINE__", name) == 0) { as_error("__LINE__ cannot be set"); return; }
  if (strcmp("__65AS__", name) == 0) { as_error("__65AS__ cannot be set"); return; }
  if (strcasecmp("pass", name) == 0) { as_error("pass cannot be set"); return; }
  if (strcasecmp("org", name) == 0) {
    addr = object->int_val;
    section->shdr->sh_addr = addr;
    return;
  }
  if (strcasecmp("addr", name) == 0) { addr = object->int_val; return; }
  if (strcasecmp("pc", name) == 0) { pc = object->int_val; return; }
  if (strcasecmp("longa", name) == 0) { longa = object->int_val; return; }
  if (strcasecmp("longi", name) == 0) { longi = object->int_val; return; }
  if (strcasecmp("cpu", name) == 0) {
    if (object->type == typeString) {
	  ELF_Half cpu;
      if (strcasecmp(object->string_val, "6502") == 0) cpu = EM_02;
      if (strcasecmp(object->string_val, "65C02") == 0) cpu = EM_C02;
      if (strcasecmp(object->string_val, "R65C02") == 0) cpu = EM_RC02;
      if (strcasecmp(object->string_val, "R6501Q") == 0) cpu = EM_RC01;
      if (strcasecmp(object->string_val, "65C816") == 0) cpu = EM_816;
      if (strcasecmp(object->string_val, "816") == 0) cpu = EM_816;
      if (strcasecmp(object->string_val, "C19") == 0) cpu = EM_RC19;
      if (strcasecmp(object->string_val, "RC19") == 0) cpu = EM_RC19;
	  elf_context->ehdr->e_machine = cpu;
	} else {
      as_error("cpu directive requires string value");
    }
    return;
  }
  if (strcasecmp("dbreg", name) == 0) { dbreg = object->int_val; return; }
  if (strcasecmp("dpage", name) == 0) { dpage = object->int_val; return; }
  if (strcasecmp("pbreg", name) == 0) { pbreg = object->int_val; return; }
  if (strcasecmp("entry", name) == 0) { elf_context->ehdr->e_entry = object->int_val; return; }

  scope_add_object(name, object);
}

MacroDef *as_get_macro(char *ident)
{
  Object *value = scope_find_object(ident);
  if ((value != 0) && (value->mode == Macro)) {
	printf("Macro '%s' found.\n", ident);
	return value->macro_val;
  }
  return 0;
}
 
void as_define_macro(char *ident, MacroDef *macro)
{
  Object *value = object_new(Macro, typeMacro);
  value->macro_val = macro;
  scope_add_object(ident, value);
  object_release(value);
  printf("Macro '%s' defined\n", ident);
}

void print_recursive(FILE *file, MapNode *root, int *offset, int *col, int step, int columns)
{
  if (root != 0) {
    print_recursive(file, root->left, offset, col, step, columns);
    if (!root->value->is_local) {
      if ((*offset == 0) && (*col < columns)) {
		fprintf(file, "%-12.12s  ", root->key);
		object_print(file, root->value);
		fprintf(file, " ");
		*offset = step;
		*col = *col + 1;
      } else {
		*offset = *offset - 1;
      }
    }
    print_recursive(file, root->right, offset, col, step, columns);
  }
}

void as_print_symbols(FILE *file)
{
  int count;
  int rows;
  int row;
  int columns = 5;
  int column;

  fprintf(file, "\nSymbols:");
  Object *s = scope;

  count = map_count(s->desc);
  rows = ((count - 1) / columns) + 1;
  for (int r = 0; r < rows; r++) {
	row = r; column = 0;
	fprintf(file, "\n");
	print_recursive(file, s->desc, &row, &column, rows - 1, columns);
  }
  fprintf(file, "\n\n");
}

void as_print_include_paths(void)
{
  if (num_include_paths != 0) {
    printf("Include paths: %d\n", num_include_paths);
    char **path = include_paths;
    while (*path != 0) {
      printf("  %s\n", *path);
      path++;
    }
  } else {
    printf("No include paths.\n");
  }
}

