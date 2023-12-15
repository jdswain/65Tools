#ifndef ELF_FILE_H
#define ELF_FILE_H

#include "elf.h"
#include "list.h"

/* 
@brief ELF file API

ELF files can be viewed in two ways, via the program/segment header or the via sections.

An executable file only requires program segments and can omit the sections. An 
intermediate file such as an object file will contain sections which reference more

The program header is automatically generated from the supplied sections. We create the 
following segments:

1. .text     PF_R | PF_X          Executable program
2. .rodata   PF_R                 Constant data
3. .data     PF_R | PF_W          Read/write data
4. .bss      PF_R | PF_W          Uninitialised data
5. .tls      PF_R | PF_W          Thread local storage, copied on fork
6. .dp       PF_R | PF_W | PF_D   Used to define how large the dp area should be
7. .stack    PF_R | PF_W | PF_S   Used to define the stack size

If there are multiple sections for a segment the order cannot be guarenteed, so this is
not normally useful for executable code.
*/
typedef struct {
  ELF_Shdr *shdr;
  struct list_node node;
  uint8_t *data;
  int data_size;
} elf_section_t;

typedef struct {
  char *filename;
  int fd;
  ELF_Ehdr *header;
  struct list_node sections;
  ELF_Shdr* shstrtab;
} elf_context_t;

elf_context_t *elf_create(const char *filename, ELF_Half e_machine);
elf_context_t *elf_read(const char *filename);
void elf_write_object(elf_context_t *context);
void elf_write_executable(elf_context_t *context);
void elf_write_rom(elf_context_t *context);
void elf_release(elf_context_t *context);

ELF_Ehdr* elf_get_header(elf_context_t *context);

elf_section_t* elf_create_section(elf_context_t *context);
elf_section_t* elf_next_section(elf_context_t *context, elf_section_t *current);
void elf_remove_section(elf_context_t *context, elf_section_t *section_header);
void elf_section_add_data(elf_section_t *section, ELF_Word len);

ELF_Word elf_add_str(elf_section_t *section, const char *str);
const char *elf_get_str(elf_section_t *section, ELF_Word offset);
ELF_Word elf_locate_str(elf_section_t *section, const char *str);
// void elf_remove_str(elf_context_t *context, ELF_Word index);

// ToDo: Symbols
// ToDo: Relocations

inline bool section_is_text(ELF_Shdr *section) {
  return (section->sh_type & SHT_PROGBITS);
}
inline bool section_is_code(ELF_Shdr *section) {
  return section_is_text(section) && (section->sh_flags & SHF_EXECINSTR);
}
inline bool section_is_rodata(ELF_Shdr *section) { 
  return section_is_text(section) && !(section->sh_flags & SHF_WRITE); 
}
inline bool section_is_data(ELF_Shdr *section) { 
  return section_is_text(section) && (section->sh_flags & SHF_WRITE); 
}
inline bool section_is_bss(ELF_Shdr *section) { 
  return (section->sh_type & SHT_NOBITS); 
}
inline bool section_is_stack(ELF_Shdr *section) { 
  return (section->sh_flags & SHF_STACK); 
}
inline bool section_is_dp(ELF_Shdr *section) { 
  return (section->sh_flags & SHF_DP); 
}

#endif
