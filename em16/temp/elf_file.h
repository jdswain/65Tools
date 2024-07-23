#ifndef ELF_FILE_H
#define ELF_FILE_H

#include <stdbool.h>

#include "elf.h"

// Value.h
struct Scope;
typedef struct Scope Scope;

// Interp.h
struct Op;
typedef struct Op Op;

enum OutputMode {
  None = 0,
  Executable,
  StaticLib,
  DynamicLib,
  Object,
  Binary,
  SRec
};
typedef enum OutputMode OutputMode;

/* 
@brief ELF file API

ELF files can be viewed in two ways, via the program/segment header or the via sections.

An executable file only requires program segments and can omit the sections. An 
intermediate file such as an object file will contain sections which reference more

The program header is automatically generated from the supplied sections. We create the 
following segments:

1. text     PF_R | PF_X          Executable program
2. rodata   PF_R                 Constant data
3. data     PF_R | PF_W          Read/write data
4. bss      PF_R | PF_W          Uninitialised data
5. tls      PF_R | PF_W          Thread local storage, copied on fork
6. dp       PF_R | PF_W | PF_D   Used to define how large the dp area should be
7. stack    PF_R | PF_W | PF_S   Used to define the stack size

If there are multiple sections for a segment the order cannot be guaranteed, so this is
not normally useful for executable code.
*/
typedef struct {
  ELF_Shdr *shdr;

  unsigned char *data;

  Op **instrs;
  int num_instrs;

  Scope *scope;
} elf_section_t;

typedef struct {
  ELF_Phdr *phdr;
  unsigned char *data;
} elf_segment_t;

typedef struct {
  char *filename;
  int fd;
  ELF_Ehdr *ehdr;
  elf_section_t **sections;
  elf_segment_t **segments;
  elf_section_t* shstrtab;
  elf_section_t* symtab;
  elf_section_t* reltab;

  // Standard sections
  elf_section_t* section_text;
  elf_section_t* section_rodata;
  elf_section_t* section_bss;
  elf_section_t* section_data;
  elf_section_t* section_tls;
  elf_section_t* section_dp;
  elf_section_t* section_stack;
} elf_context_t;

elf_context_t *elf_create(const char *filename, ELF_Half e_machine);
elf_context_t *elf_read(const char *filename);
void elf_write_object(elf_context_t *context);
void elf_write_executable(elf_context_t *context);
void elf_release(elf_context_t *context);

/* Non-ELF formats that we convert to */
void elf_write_binary(elf_context_t *context);
void elf_write_s19(elf_context_t *context);
void elf_write_s28(elf_context_t *context);
void elf_write_s37(elf_context_t *context);
void elf_write_intel(elf_context_t *context);
void elf_write_tim(elf_context_t *context);

/* Section */
elf_section_t* elf_section_create(elf_context_t *context, ELF_Word name);
elf_section_t* elf_section_find(elf_context_t *context, ELF_Word name);

static inline bool section_is_text(elf_section_t *section) {
  return (section->shdr->sh_type & SHT_PROGBITS);
}
static inline bool section_is_code(elf_section_t *section) {
  return section_is_text(section) && (section->shdr->sh_flags & SHF_EXECINSTR);
}
static inline bool section_is_rodata(elf_section_t *section) { 
  return section_is_text(section) && !(section->shdr->sh_flags & SHF_WRITE); 
}
static inline bool section_is_data(elf_section_t *section) { 
  return section_is_text(section) && (section->shdr->sh_flags & SHF_WRITE); 
}
static inline bool section_is_bss(elf_section_t *section) { 
  return (section->shdr->sh_type & SHT_NOBITS); 
}
static inline bool section_is_stack(elf_section_t *section) { 
  return (section->shdr->sh_flags & SHF_STACK); 
}
static inline bool section_is_dp(elf_section_t *section) { 
  return (section->shdr->sh_flags & SHF_DP); 
}

/* Segment */

/* String */
ELF_Word elf_string_create(elf_section_t *section, const char *str);
const char *elf_string_get(elf_section_t *section, ELF_Word offset);
ELF_Word elf_string_locate(elf_section_t *section, const char *str);

/* Symbol */
ELF_Word elf_symbol_add(elf_section_t *section, ELF_Sym *symbol);
const ELF_Sym *elf_symbol_get(elf_section_t *section, ELF_Word offset);
ELF_Word elf_symbol_locate(elf_section_t *section, ELF_Word st_name);

/* Relocation */
#define REL_DP   0x01
#define REL_ABS  0x02
#define REL_LONG 0x03

#define REL_LOCAL 0x10
#define REL_GLOBAL 0x20

static inline bool rel_is_dp(ELF_Word info) { return info & REL_DP; }
static inline bool rel_is_abs(ELF_Word info) { return info & REL_ABS; }
static inline bool rel_is_long(ELF_Word info) { return info & REL_LONG; }

static inline bool rel_is_local(ELF_Word info) { return info & REL_LOCAL; }
static inline bool rel_is_global(ELF_Word info) { return info & REL_GLOBAL; }

ELF_Word elf_relocation_create(elf_section_t *section, ELF_Addr offset, ELF_Word info);
const ELF_Rel *elf_relocation_next(elf_section_t *section, ELF_Rel *current);

extern elf_context_t *elf_context;
extern elf_section_t *section;
void elf_set_section(const char *name);


#endif
