#include "elf.h"
#include "elf_file.h"

#include <stdio.h>

void print_hdr(ELF_Ehdr *hdr)
{
  switch( hdr->e_type ) {
  case ET_NONE: printf("Type:           None\n"); break;
  case ET_REL:  printf("Type:           Relocatable\n"); break;
  case ET_EXEC: printf("Type:           Executable\n"); break;
  case ET_DYN:  printf("Type:           Shared Library\n"); break;
  case ET_CORE: printf("Type:           Core\n"); break;
  }
  switch( hdr->e_machine ) {
  case EM_NONE: printf("Architecture:   None\n"); break;
  case EM_816:  printf("Architecture:   65C816\n"); break;
  case EM_C02:  printf("Architecture:   65C02\n"); break;
  case EM_02:   printf("Architecture:   6502\n"); break;
  case EM_RC02: printf("Architecture:   Rockwell 65C02\n"); break;
  case EM_RC19: printf("Architecture:   Rockwell C19\n"); break;
  }
  printf("Version:        %d\n", hdr->e_version);
  printf("Entry Address:  %d\n", hdr->e_entry);
  printf("Program Offset: %d\n", hdr->e_phoff);
  printf("Section Offset: %d\n", hdr->e_shoff);
  printf("Flags:          %d\n", hdr->e_flags);
  printf("Header Size:    %d\n", hdr->e_ehsize);
  printf("Program Size:   %d\n", hdr->e_phentsize);
  printf("Program Count:  %d\n", hdr->e_phnum);
  printf("Section Size:   %d\n", hdr->e_shentsize);
  printf("Section Count:  %d\n", hdr->e_shnum);
  printf("String Index:   %d\n\n", hdr->e_shstrndx);
}

void print_section(elf_context_t *context, ELF_Shdr *hdr, void *data, int data_len)
{
  printf("Section %s", elf_find_str(context, hdr->sh_name));
  printf("  type:       %d", hdr->sh_type);
  printf("  flags:      %d", hdr->sh_flags);
  printf("  addr:       %d", hdr->sh_addr);
  printf("  offset:     %d", hdr->sh_offset);
  printf("  size:       %d", hdr->sh_size);
  printf("  link:       %d", hdr->sh_link);
  printf("  info:       %d", hdr->sh_info);
  printf("  addralign:  %d", hdr->sh_addralign);
  printf("  entsize:    %d", hdr->sh_entsize);
}

int main(int argc, char **argv)
{
  const char *filename;
  
  if( argc != 2 ) {
    printf("readelf version 0.0.1 - Decode 65OS ELF file - Copyright 2019 Jason Swain.\n");
    printf("Usage: readelf file\n");
    return 1;
  }
  filename = argv[1];
  
  elf_context_t *context = elf_read(filename);

  if( context == 0 ) {
    printf("%s is not a valid ELF file.\n", filename);
    return 1;
  }

  print_hdr(context->header);

  elf_section_t *section;
  list_for_every_entry(&context->sections, section, elf_section_t, node) {
    print_section(context, section->shdr, section->data, section->data_size);
  }
  
  return 0;
}

