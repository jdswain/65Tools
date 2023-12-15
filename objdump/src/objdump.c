#include <stdio.h>

#include "objdump.h"

#include "buffered_file.h"
#include "memory.h"
#include "elf_file.h"
#include "cpu.h"
#include "dis.h"


void ob_init(void);
void ob_print_include_paths(void);

void help(void) {
  printf("objdump version " OB_VERSION " - 65XXX Object File Disassembler - Copyright 2020 Jason Swain.\n"
	 "Usage: objdump [options...] infile(s)...\n"
	 "General Options\n"
	 "  -v          verbose output\n"
	 "  -h          show help\n"
	 );
}

void ob_disassemble_elf(char *file)
{
  elf_context_t *context = elf_read(file);
  elf_section_t *strtab = context->sections[context->ehdr->e_shstrndx];
  ELF_Word textndx = elf_string_locate(strtab, "text");
  elf_section_t *text_section = elf_section_find(context, textndx);
  printf("text section index is %d, length is %d.\n", textndx, text_section->shdr->sh_size);
  dis(text_section->data, text_section->shdr->sh_size, text_section->shdr->sh_addr);
}

void ob_disassemble(char *file)
{
  int base = 0xf400;

  bf_init();
  BufferedFile *bf = bf_open(file);
  dis(bf, base);
  bf_close(file);
}

int main(int argc, char **argv)
{
  ob_init();

  int optind = ob_parse_args(argc - 1, argv + 1);

  if (optind == 0) {
    help();
    return 1;
  }
  
  if (num_files == 0) {
    as_error("No input files");
    return 1;
  }

  char **file = files;
  while (*file != 0) {
    ob_disassemble_elf(*file);
    file++;
  }
    
  ob_cleanup();
  
  return 0;
}

void ob_init(void)
{
  files = 0;
  num_files = 0;
}

typedef struct OBOption {
  const char *name;
  uint16_t index;
  uint16_t flags;
} OBOption;

enum {
  OB_OPTION_HELP,
  OB_OPTION_v,
};

#define OB_OPTION_HAS_ARG 0x0001
#define OB_OPTION_NO_SEP 0x0002

static const OBOption ob_options[] = {
  { "h", OB_OPTION_HELP, 0 },
  { "-help", OB_OPTION_HELP, 0 },
  { "?", OB_OPTION_HELP, 0 },
  { "v", OB_OPTION_v, OB_OPTION_HAS_ARG | OB_OPTION_NO_SEP },
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

int ob_parse_args(int argc, char** argv)
{
  int optind = 0;
  const char *optarg, *r;
  const OBOption *popt;
  
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
    for(popt = ob_options; ; ++popt) {
      const char *p1 = popt->name;
      const char *r1 = r + 1;
      if (p1 == 0)
        as_error(0, "Invalid option -- '%s'", r);
      if (!strstart(p1, &r1))
        continue;
      optarg = r1;
      if (popt->flags & OB_OPTION_HAS_ARG) {
        if (*r1 == '\0' && !(popt->flags & OB_OPTION_NO_SEP)) {
          if (optind >= argc)
            as_error(0, "Argument to option '%s' is missing", r);
          optarg = argv[optind++];
        }
      } else if (*r1 != '\0')
        continue;
      break;
    }

    switch(popt->index) {
    case OB_OPTION_HELP:
      return 0;
    case OB_OPTION_v:
      do ++verbose; while (*optarg++ == 'v');
      break;
    }
  }

  return optind;
}

void ob_cleanup(void)
{
  list_reset((void ***)&files, &num_files);
  elf_release(elf_context);
}

void ob_split_path(void ***p_array, int *p_num_array, const char *in)
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

void print_recursive(FILE *file, MapNode *root, int *offset, int *col, int step, int columns)
{
  if (root != 0) {
    print_recursive(file, root->left, offset, col, step, columns);
    if ((*offset == 0) && (*col < columns)) {
      if (root->value->is_extern)
	fprintf(file, "%-12.12s* ", root->key);
      else
	fprintf(file, "%-12.12s  ", root->key);
      value_print(file, root->value);
      fprintf(file, " ");
      *offset = step;
      *col = *col + 1;
    } else {
      *offset = *offset - 1;
    }
    print_recursive(file, root->right, offset, col, step, columns);
  }
}

void ob_print_symbols(FILE *file)
{
  /*
  int count;
  int rows;
  int row;
  int columns = 5;
  int column;

  fprintf(file, "Symbols:");
  Scope *s = section->scope;
  while (s->parent != 0) { // Don't print top level
    count = map_count(s->values);
    rows = ((count - 1) / columns) + 1;
    // fprintf(file, "Scope: %d in %d rows.\n", count, rows);
    for (int r = 0; r < rows; r++) {
      row = r; column = 0; fprintf(file, "\n"); print_recursive(file, s->values, &row, &column, rows - 1, columns);
    }
    fprintf(file, "\n");
    s = s->parent;
  };
  fprintf(file, "\n");  
  */
}

char *mode_to_string(enum AddrMode mode)
{
 switch( mode ) {
 case Absolute: return "Absolute";
 case Accumulator: return "Accumulator";
 case AbsoluteIndexedX: return "Absolute Indexed X";
 case AbsoluteIndexedY: return "Absolute Indexed Y";
 case AbsoluteLong: return "Absolute Long";
 case AbsoluteLongIndexedX: return "Absolute Long Indexed X";
 case AbsoluteIndirect: return "Absolute Indirect";
 case AbsoluteIndirectLong: return "Absolute Indirect Long";
 case AbsoluteIndexedIndirect: return "Absolute Indexed Indirect";
 case BitAbsolute: return "Bit Absolute";
 case BitAbsoluteRelative: return "Bit Absolute Relative";
 case BitZeroPage: return "Bit Zero Page";
 case BitZeroPageRelative: return "Bit Zero Page Relative";
 case DirectPage: return "Direct Page";
 case StackDirectPageIndirect: return "Stack Direct Page Indirect";
 case DirectPageIndexedX: return "Direct Page Indexed X";
 case DirectPageIndexedY: return "Direct Page Indexed Y";
 case DirectPageIndirect: return "Direct Page Indirect";
 case DirectPageIndirectLong: return "Direct Page Indirect Long";
 case Implied: return "Implied";
 case ImmediateZeroPage: return "ImmediateZeroPage";
 case ProgramCounterRelative: return "Program Counter Relative";
 case ProgramCounterRelativeLong: return "Program Counter Relative Long";
 case BlockMove: return "Block Move";
 case DirectPageIndexedIndirectX: return "Direct Page Indexed Indirect X";
 case DirectPageIndirectIndexedY: return "Direct Page Indirect Indexed Y";
 case DirectPageIndirectLongIndexedY: return "Direct Page Indirect Long Indexed Y";
 case Immediate: return "Immediate";
 case StackRelative: return "Stack Relative";
 case StackRelativeIndirectIndexedY: return "Stack Relative Indirect IndexedY";
 }
 return "Invalid Mode";
}

char *cpu_to_string(ELF_Half cpu)
{
  switch (cpu) {
  case EM_NONE: return "None";
  case EM_816: return "65C816";
  case EM_C02: return "65C02";
  case EM_02: return "6502";
  case EM_RC02: return "Rockwell 65C02";
  case EM_RC19: return "Rockwell C19";
  }
  return "Unknown";
}

/* We don't use func, but value requires it, so this is a workaround */
void func_delete(FuncDef *func)
{
}
