#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>

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
uint32_t pc; // Current pc
uint8_t _pass; // Pass number
uint16_t dbreg;
uint16_t dpage;
uint16_t pbreg;

int pass(void) { return _pass; }

/* Listing */
bool list; // Listing on or off

// End Globals

void as_print_include_paths(void);
extern void create_standard_file(void);

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
  scanner_init(); // We need this for the args
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
  codegen_close();
  // as_print_include_paths();
}

static void create_builtin_symbols(void)
{
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
    create_builtin_symbols();
    break;
  case FileObject:
    elf_context = elf_create(name, EM_816);
    elf_context->ehdr->e_type = ET_REL;
    create_standard_file();
    create_builtin_symbols();
    break;
  case FileLib:
    elf_context = elf_create(name, EM_816);
    elf_context->ehdr->e_type = ET_EXEC;
    create_standard_file();
    create_builtin_symbols();
    break;
  case FileDylib:
    elf_context = elf_create(name, EM_816);
    elf_context->ehdr->e_type = ET_DYN;
    create_standard_file();
    create_builtin_symbols();
    break;
  case File816:
    elf_context = elf_create(name, EM_816);
    elf_context->ehdr->e_type = ET_EXEC;
    create_standard_file();
    create_builtin_symbols();
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
    create_builtin_symbols();
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
	  unsigned char bind = node->value->is_global ? STB_GLOBAL : STB_LOCAL;
	  unsigned char info = ELF32_ST_INFO(bind, 0);
	  elf_symbol_create(elf_context, node->key, node->value->int_val, 0, info);
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
  
  if (bf_open(filename) >= 0) {
    switch (as_file_type(filename)) {
    case FileAsmSrc:
      printf("Assembling '%s'\n", filename);
	  scanner_init();
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
	  codegen_current_pass = _pass;
	  code_len = interp_run(filename);
	  while (code_len != last_code_len) {
		_pass++;
		codegen_current_pass = _pass;
		last_code_len = code_len;
		code_len = interp_run(filename);
	  }
	  _pass = 0;
	  codegen_current_pass = 0;
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
  case File816:
    elf_write_816(elf_context);
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
  if (strcasecmp("addr", ident) == 0) return make_value_int(codegen_here());
  if (strcasecmp("pc", ident) == 0) return make_value_int(pc);
  if (strcasecmp("longa", ident) == 0) return make_value_int(codegen_longa());
  if (strcasecmp("longi", ident) == 0) return make_value_int(codegen_longi());
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
    codegen_addr(object->int_val);
    section->shdr->sh_addr = object->int_val;
    return;
  }
  if (strcasecmp("addr", name) == 0) { codegen_addr(object->int_val); return; }
  if (strcasecmp("pc", name) == 0) { pc = object->int_val; return; }
  if (strcasecmp("longa", name) == 0) { codegen_setlonga(object->int_val); return; }
  if (strcasecmp("longi", name) == 0) { codegen_setlongi(object->int_val); return; }
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

/* .smb file reading for import directive */

static int smb_read_byte(int fd) {
  unsigned char b;
  if (read(fd, &b, 1) != 1) return -1;
  return b;
}

static int32_t smb_read_int32(int fd) {
  unsigned char buf[4];
  if (read(fd, buf, 4) != 4) return 0;
  return buf[0] | (buf[1] << 8) | (buf[2] << 16) | (buf[3] << 24);
}

static int smb_read_string(int fd, char *buf, int maxlen) {
  int i = 0;
  unsigned char ch;
  while (i < maxlen - 1) {
    if (read(fd, &ch, 1) != 1) break;
    buf[i++] = ch;
    if (ch == 0) return i;
  }
  buf[i] = 0;
  return i;
}

static int32_t smb_read_num(int fd) {
  int32_t x = 0;
  int shift = 0;
  unsigned char b;
  do {
    if (read(fd, &b, 1) != 1) return 0;
    x |= (int32_t)(b & 0x7F) << shift;
    shift += 7;
  } while (b & 0x80);
  /* Sign extend */
  if ((b & 0x40) && shift < 32) {
    x |= -(1 << shift);
  }
  return x;
}

/* Skip an OutType encoding in .smb without fully parsing it */
static void smb_skip_type(int fd) {
  int ref = (int8_t)smb_read_byte(fd);
  if (ref < 0) return; /* back-reference, done */

  int form = smb_read_byte(fd);

  if (form == 7) { /* ORB_Pointer */
    smb_skip_type(fd);
  } else if (form == 12) { /* ORB_Array */
    smb_skip_type(fd);
    smb_read_num(fd); /* len */
    smb_read_num(fd); /* size */
  } else if (form == 13) { /* ORB_Record */
    smb_skip_type(fd); /* base */
    /* skip 3 Nums: extension level, descr address, size */
    smb_read_num(fd);
    smb_read_num(fd);
    smb_read_num(fd);
    /* skip fields until class==0 */
    int cls;
    while ((cls = smb_read_byte(fd)) != 0) {
      char fname[64];
      if (cls == 4) { /* ORB_Fld */
        smb_read_string(fd, fname, sizeof(fname));
        smb_skip_type(fd);
        smb_read_num(fd); /* offset */
      } else {
        /* hidden pointer field: class != ORB_Fld */
        smb_read_byte(fd); /* 0 */
        smb_skip_type(fd);
        smb_read_num(fd); /* offset */
      }
    }
  } else if (form == 10) { /* ORB_Proc */
    smb_skip_type(fd); /* return type */
    /* skip params until class==0 */
    int cls;
    while ((cls = smb_read_byte(fd)) != 0) {
      smb_read_byte(fd); /* rdo */
      smb_skip_type(fd); /* param type */
    }
  }
  /* basic types (1-6, 8, 9): no extra data */

  /* re-export marker */
  int reexport = smb_read_byte(fd);
  if (reexport != 0) {
    char str[64];
    smb_read_string(fd, str, sizeof(str)); /* module name */
    smb_read_int32(fd);                    /* key */
    smb_read_string(fd, str, sizeof(str)); /* original name */
  }
}

void as_import(const char *modname)
{
  char smbpath[256];
  int fd = -1;

  /* Try 1: relative to output file directory */
  const char *outfile = elf_context->filename;
  const char *slash = strrchr(outfile, '/');
  if (slash) {
    int dirlen = (int)(slash - outfile) + 1;
    memcpy(smbpath, outfile, dirlen);
    smbpath[dirlen] = 0;
    strncat(smbpath, modname, sizeof(smbpath) - strlen(smbpath) - 5);
    strcat(smbpath, ".smb");
    fd = open(smbpath, O_RDONLY);
  }

  /* Try 2: relative to source file directory */
  if (fd < 0 && file && file->filename[0]) {
    const char *srcslash = strrchr(file->filename, '/');
    if (srcslash) {
      int dirlen = (int)(srcslash - file->filename) + 1;
      memcpy(smbpath, file->filename, dirlen);
      smbpath[dirlen] = 0;
    } else {
      smbpath[0] = 0;
    }
    strncat(smbpath, modname, sizeof(smbpath) - strlen(smbpath) - 5);
    strcat(smbpath, ".smb");
    fd = open(smbpath, O_RDONLY);
  }

  /* Try 3: current directory */
  if (fd < 0) {
    snprintf(smbpath, sizeof(smbpath), "%s.smb", modname);
    fd = open(smbpath, O_RDONLY);
  }

  if (fd < 0) {
    as_error("Cannot open symbol file: %s.smb", modname);
    return;
  }

  /* Read .smb header */
  smb_read_int32(fd); /* placeholder */
  int32_t key = smb_read_int32(fd);
  char name[64];
  smb_read_string(fd, name, sizeof(name));
  smb_read_byte(fd); /* versionkey */

  /* Assign mno (1-based) */
  int mno = elf_context->import_count + 1;

  /* Store import in elf_context */
  if (elf_context->import_count < MAX_IMPORTS) {
    strncpy(elf_context->imports[elf_context->import_count].name, modname, 63);
    elf_context->imports[elf_context->import_count].name[63] = 0;
    elf_context->imports[elf_context->import_count].key = key;
    elf_context->import_count++;
  }

  /* Create scope object for the module */
  Object *mod = object_new(Const, typeNoType);
  mod->mode = Var;
  mod->is_import = true;
  scope_add_object(modname, mod);

  /* Read exports */
  int class;
  while ((class = smb_read_byte(fd)) != 0) {
    char ename[64];
    smb_read_string(fd, ename, sizeof(ename));
    smb_skip_type(fd);

    int32_t exno;
    if (class == 1) { /* ORB_Const = procedure */
      exno = smb_read_num(fd);
    } else if (class == 2) { /* ORB_Var */
      exno = smb_read_num(fd);
    } else if (class == 3) { /* ORB_Par */
      exno = smb_read_num(fd);
    } else if (class == 5) { /* ORB_Typ */
      exno = smb_read_num(fd);
    } else {
      exno = smb_read_num(fd);
    }

    /* Create child entry: value = (mno << 16) | exno
       This encodes as bank=mno, addr=exno for JSL */
    Object *entry = object_new(Const, typeInt);
    entry->int_val = (mno << 16) | (exno & 0xFFFF);
    entry->is_import = true;

    /* Add to module's desc map */
    mod->desc = map_set(mod->desc, as_strdup(ename), entry);
    object_release(entry);
  }

  close(fd);
  object_release(mod);

  printf("  Imported %s (key=%d, mno=%d)\n", modname, key, mno);
}

