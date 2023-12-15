#include "elf_file.h"

#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

#include <stdio.h>

#include "Memory.h"

elf_context_t *elf_create(const char *filename, ELF_Half e_machine)
{
  elf_context_t *context = 0;

  context = as_malloc(sizeof(elf_context_t));

  context->filename = as_strdup(filename);
  context->header = as_malloc(sizeof(ELF_Ehdr));
  context->header->e_ident[0] = ELFMAG0;
  context->header->e_ident[1] = ELFMAG1;
  context->header->e_ident[2] = ELFMAG2;
  context->header->e_ident[3] = ELFMAG3;
  context->header->e_type = ET_REL;
  context->header->e_machine = e_machine;
  context->header->e_version = EV_CURRENT;
  context->header->e_entry = 0x00000000;
  context->header->e_phoff = 0;
  context->header->e_shoff = 0;
  context->header->e_flags = 0;
  context->header->e_ehsize = sizeof(ELF_Ehdr);
  context->header->e_phentsize = sizeof(ELF_Phdr);
  context->header->e_phnum = 0;
  context->header->e_shentsize = sizeof(ELF_Shdr);
  context->header->e_shnum = 1;
  context->header->e_shstrndx = 0; // We know it's the first one

  list_initialize(&context->sections);
  
  // Create the section header string table
  elf_section_t *shstrtab = elf_create_section(context);
  ELF_Shdr *shdr = shstrtab->shdr;
  shdr->sh_type = SHT_STRTAB;
  shdr->sh_flags = 0;
  shdr->sh_addr = 0;
  shdr->sh_offset = 0;
  shdr->sh_size = 0;
  shdr->sh_link = 0;
  shdr->sh_info = 0;
  shdr->sh_addralign = 0;
  shdr->sh_entsize = 0;
  shdr->sh_name = elf_add_str(shstrtab, ".shstrtab");

  list_add_tail(&context->sections, &shstrtab->node);

  return context;
}

elf_context_t *elf_read(const char *filename) 
{
  size_t r;
  int fd;
  elf_context_t *context = 0;
  fd = open(filename, O_RDONLY);

  if (fd != 0) {

    context = as_malloc(sizeof(elf_context_t));
    context->filename = as_strdup(filename);
    
    // Validate the header
    context->header = as_malloc(sizeof(ELF_Ehdr));
    if ((read(fd, context->header, sizeof(ELF_Ehdr)) != sizeof(ELF_Ehdr)) ||
        (context->header->e_ident[0] != ELFMAG0) ||
        (context->header->e_ident[1] != ELFMAG1) ||
        (context->header->e_ident[2] != ELFMAG2) ||
        (context->header->e_ident[3] != ELFMAG3)) {
      as_free(context); context = 0;
    } else {
      // Load the sections
      list_initialize(&context->sections);
      lseek(fd, context->header->e_shoff, SEEK_SET);
      for (int i = 0; i < context->header->e_shnum; i++) {
        elf_section_t *section = as_malloc(sizeof(elf_section_t));
        r = read(fd, &section->shdr, sizeof(ELF_Shdr));
        list_add_tail(&context->sections, &section->node);
      }
    }
  }
  close(fd);

  return context;
}

/*
This is the simplest write. We don't need to worry about the program/segment header
and can just write out all the sections.
*/
void elf_write_object(elf_context_t *context)
{
  ssize_t r;
  ELF_Word shoff;
  elf_section_t *section;

  int fd = open(context->filename, O_CREAT | O_APPEND | O_WRONLY, S_IRWXU);
  
  if (fd != 0) {
    shoff = sizeof(ELF_Ehdr);
    list_for_every_entry(&context->sections, section, elf_section_t, node) {
      shoff += section->shdr->sh_size;
    }
    context->header->e_phoff = 0;
    context->header->e_shoff = shoff;
    r = write(fd, context->header, sizeof(ELF_Ehdr));

    list_for_every_entry(&context->sections, section, elf_section_t, node) {
      r = write(fd, section->data, section->shdr->sh_size);
    }
    shoff = sizeof(ELF_Ehdr);

    list_for_every_entry(&context->sections, section, elf_section_t, node) {
      section->shdr->sh_offset = shoff;
      r = write(fd, section->shdr, sizeof(ELF_Shdr));
      shoff += section->shdr->sh_size;
    }
    close(fd);
  }
}

void write_program_header(int fd, ELF_Phdr *buf, ELF_Word filesz, ELF_Word memsz, 
			  ELF_Word flags)
{
  ssize_t r;

  if (filesz > 0) {
    buf->p_flags = flags;
    buf->p_filesz = filesz;
    buf->p_memsz = memsz;
    r = write(fd, buf, sizeof(ELF_Phdr));
    buf->p_offset += filesz;
  }
}

void elf_write_executable(elf_context_t *context)
{
  ssize_t r;

  elf_section_t *section;
  ELF_Shdr *shdr;

  int fd = open(context->filename, O_CREAT | O_APPEND | O_WRONLY, S_IRWXU);
  
  if (fd != 0) {
    // Find our sizes
    ELF_Word text_size = 0;
    ELF_Word rodata_size = 0;
    ELF_Word data_size = 0;
    ELF_Word bss_size = 0;
    ELF_Word tls_size = 0;
    ELF_Word dp_size = 0;
    ELF_Word stack_size = 0;
    list_for_every_entry(&context->sections, section, elf_section_t, node) {
      shdr = section->shdr;
      if (section_is_text(shdr)) {
        if (section_is_code(shdr)) 
          text_size += section->data_size;
        else if (section_is_rodata(shdr)) 
          rodata_size += section->data_size;
        else if (section_is_data(shdr)) 
          data_size += section->data_size;
      } else if (section_is_bss(shdr)) {
        if (section_is_stack(shdr)) 
          stack_size += section->data_size;
        else if (section_is_dp(shdr)) 
          dp_size += section->data_size;
        else 
          bss_size += section->data_size;
      }
    }
    
    // Elf Header
    int phcount = (text_size?1:0) + (rodata_size?1:0) + (data_size?1:0) +
      (bss_size?1:0) + (stack_size?1:0) + (dp_size?1:0) + (tls_size?1:0);
    context->header->e_phoff = sizeof(ELF_Ehdr);
    context->header->e_shoff = sizeof(ELF_Ehdr) + phcount * sizeof(ELF_Phdr) +
      text_size + rodata_size + data_size + tls_size;
    r = write(fd, context->header, sizeof(ELF_Ehdr));
    printf("wrote %ld", r);
    // Create the program headers
    ELF_Phdr* segment_buf = as_malloc(sizeof(ELF_Phdr));
    segment_buf->p_type = PT_LOAD;
    segment_buf->p_offset = sizeof(ELF_Ehdr);  // Segment file offset 
    segment_buf->p_vaddr = 0;                  // Segment virtual address 
    segment_buf->p_paddr = 0;                  // Segment physical address 
    segment_buf->p_filesz = 0;                 // Segment size in file 
    segment_buf->p_memsz = 0;;                 // Segment size in memory
    segment_buf->p_flags = 0;;                 // Segment flags 
    segment_buf->p_align = 0;                  // Segment alignment, not used
    
    // .text   
    write_program_header(fd, segment_buf, text_size, text_size, PF_R | PF_X);
    
    // .rodata   
    write_program_header(fd, segment_buf, rodata_size, rodata_size, PF_R);

    // .data     
    write_program_header(fd, segment_buf, data_size, data_size, PF_R | PF_W);

    // .bss      
    write_program_header(fd, segment_buf, 0, bss_size, PF_R | PF_X);

    // .tls
    write_program_header(fd, segment_buf, 0, tls_size, PF_R | PF_X);

    // .dp 
    write_program_header(fd, segment_buf, 0, dp_size, PF_R | PF_W | PF_D);
      
    // .stack
    write_program_header(fd, segment_buf, 0, stack_size, PF_R | PF_W | PF_S);

    // Now write the section data in type order
    for (int s = 0; s < 4; s++) {
      list_for_every_entry(&context->sections, section, elf_section_t, node) {
        shdr = section->shdr;
        if (section_is_text(shdr)) {
          if (section_is_code(shdr)) {
            if (s == 0) r = write(fd, section->data, shdr->sh_size);
          } else if (section_is_rodata(shdr)) {
            if (s == 1) r = write(fd, section->data, shdr->sh_size);
          } else if (section_is_data(shdr)) {
            if (s == 2) r =write(fd, section->data, shdr->sh_size);
          } else {
            if (s == 3) r = write(fd, section->data, shdr->sh_size);
          } 
        } else if (!section_is_bss(shdr)) {
          if (s == 3) r = write(fd, section->data, shdr->sh_size);
        }
      }
    }
    
    // And finally the section headers
    ELF_Word shoff = sizeof(ELF_Ehdr); 
    for (int s = 0; s < 7; s++) {
      list_for_every_entry(&context->sections, section, elf_section_t, node) {
        shdr = section->shdr;
        if (section_is_text(shdr)) {
          if (section_is_code(shdr)) {
            if (s == 0) {
              shdr->sh_offset = shoff;
              r = write(fd, section->data, sizeof(ELF_Shdr));
              shoff += shdr->sh_size;
            }
          } else if (section_is_rodata(shdr)) {
            if (s == 1) {
              shdr->sh_offset = shoff;
              r = write(fd, section->data, sizeof(ELF_Shdr));
              shoff += shdr->sh_size;
            }
          } else if (section_is_data(shdr)) {
            if (s == 2) {
              shdr->sh_offset = shoff;
              r = write(fd, section->data, sizeof(ELF_Shdr));
              shoff += shdr->sh_size;
            }
          } else {
            if (s == 6) {
              shdr->sh_offset = shoff;
              r = write(fd, section->data, sizeof(ELF_Shdr));
              shoff += shdr->sh_size;
            }
          } 
        } else if (section_is_bss(shdr)) {
          if (section_is_stack(shdr)) {
            if (s == 3) {
              shdr->sh_offset = shoff;
              r = write(fd, section->data, sizeof(ELF_Shdr));
            }
          } else if (section_is_dp(shdr)) {
            if (s == 4) {
              shdr->sh_offset = shoff;
              r = write(fd, section->data, sizeof(ELF_Shdr));
              shoff += shdr->sh_size;
            }
          } else {
            if (s == 5) {
              shdr->sh_offset = shoff;
              r = write(fd, section->data, sizeof(ELF_Shdr));
            }
          }
        } else {
          if (s == 6) {
            shdr->sh_offset = shoff;
            r = write(fd, section->data, sizeof(ELF_Shdr));
            shoff += shdr->sh_size;
          }
        }
      }
    }
    close(fd);
  }
}

void elf_write_rom(elf_context_t *context)
{
}

void elf_release(elf_context_t *context)
{
  if( context ) {
    as_free(context->filename);
    as_free(context->header);
    as_free(context); 
  }
}


ELF_Ehdr *elf_get_header(elf_context_t *context) 
{
  return context->header;
}

elf_section_t *elf_create_section(elf_context_t *context)
{
  context->header->e_shnum += 1;
  elf_section_t *section = as_mallocz(sizeof(elf_section_t));
  section->shdr = as_mallocz(sizeof(ELF_Shdr));
  list_add_tail(&context->sections, &section->node);

  return section;
}
void elf_section_add_data(elf_section_t *section, ELF_Word len)
{
}

elf_section_t *elf_next_section(elf_context_t *context, elf_section_t *current)
{
    return containerof(list_next(&context->sections, &current->node), elf_section_t, node);
}

void elf_remove_section(elf_context_t *context, elf_section_t *section_header)
{
}


ELF_Word elf_add_str(elf_section_t *section, const char *str) 
{
  ELF_Word len, offset;
  char *ptr;

  offset = elf_locate_str(section, str);
  if (!offset) {
    len = strlen(str) + 1;
    offset = section->data_offset;
    ptr = elf_section_add_data(section, len);
    memcpy(ptr, str, len);
  }
  return offset;
}

const char *elf_get_str(elf_section_t *section, ELF_Word offset)
{
  return section->data + offset;
}

ELF_Word elf_locate_str(elf_section_t *section, const char *str)
{
  return 0;
}

// void elf_remove_str(elf_context_t *context, ELF_Word index)
// {
// }

