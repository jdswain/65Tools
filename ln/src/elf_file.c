#include "elf_file.h"

#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

#include <stdio.h>

elf_context_t *elf_create(void)
{
  elf_context_t *context = 0;

  context = malloc(sizeof(elf_context_t));

  context->header = malloc(sizeof(ELF_Ehdr));
  context->header->e_ident[0] = ELFMAG0;
  context->header->e_ident[1] = ELFMAG1;
  context->header->e_ident[2] = ELFMAG2;
  context->header->e_ident[3] = ELFMAG3;
  context->header->e_type = ET_REL;
  context->header->e_machine = EM_816;
  context->header->e_version = EV_CURRENT;
  context->header->e_entry = 0x00000000;
  context->header->e_phoff = 0;
  context->header->e_shoff = 0;
  context->header->e_flags = 0;
  context->header->e_ehsize = sizeof(ELF_Ehdr);
  context->header->e_phentsize = sizeof(ELF_Phdr);
  context->header->e_phnum = 0;
  context->header->e_shentsize = sizeof(ELF_Shdr);
  context->header->e_shnum = 0;
  context->header->e_shstrndx = 0;
  
  // Create strings section
  context->shstrtab = malloc(sizeof(ELF_Shdr));
  elf_add_str(context, ".shstrtab");

  return context;
}

elf_context_t *elf_read(char *path) 
{
  int fd;
  elf_context_t *context = 0;
  fd = open(path, O_RDONLY);

  if (fd != 0) {

    context = malloc(sizeof(elf_context_t));

    // Validate the header
    context->header = malloc(sizeof(ELF_Ehdr));
    if ((read(fd, context->header, sizeof(ELF_Ehdr)) != sizeof(ELF_Ehdr)) ||
	(context->header->e_ident[0] != ELFMAG0) ||
	(context->header->e_ident[1] != ELFMAG1) ||
	(context->header->e_ident[2] != ELFMAG2) ||
	(context->header->e_ident[3] != ELFMAG3)) {
      free(context); context = 0;
    } else {
      // Load the sections
      lseek(fd, context->header->e_shoff, SEEK_SET);
      for (int i = 0; i < context->header->e_shnum; i++) {
	section_t *section_t = malloc(sizeof(section_t));
	read(fd, &section_t->shdr, sizeof(ELF_Shdr));
	list_add_head(&context->sections, &section_t->node);
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
void elf_write_object(elf_context_t *context, char *path)
{
  ELF_Word shoff;
  section_t *section;

  int fd = open(path, O_WRONLY);
  
  if (fd != 0) {
    shoff = sizeof(ELF_Ehdr);
    list_for_every_entry(&context->sections, section, section_t, node) {
      shoff += section->shdr->sh_size;
    }
    context->header->e_phoff = 0;
    context->header->e_shoff = shoff;
    write(fd, context->header, sizeof(ELF_Ehdr));

    list_for_every_entry(&context->sections, section, section_t, node) {
      write(fd, section->data, section->shdr->sh_size);
    }
    shoff = sizeof(ELF_Ehdr);

    list_for_every_entry(&context->sections, section, section_t, node) {
      section->shdr->sh_offset = shoff;
      write(fd, section->shdr, sizeof(ELF_Shdr));
      shoff += section->shdr->sh_size;
    }
    close(fd);
  }
}

void write_program_header(int fd, ELF_Phdr *buf, ELF_Word filesz, ELF_Word memsz, 
			  ELF_Word flags)
{
  if (filesz > 0) {
    buf->p_flags = flags;
    buf->p_filesz = filesz;
    buf->p_memsz = memsz;
    write(fd, buf, sizeof(ELF_Phdr));
    buf->p_offset += filesz;
  }
}

void elf_write_executable(elf_context_t *context, char *path)
{
  section_t *section;
  ELF_Shdr *shdr;

  int fd = open(path, O_WRONLY);
  
  if (fd != 0) {
    // Find our sizes
    ELF_Word text_size = 0;
    ELF_Word rodata_size = 0;
    ELF_Word data_size = 0;
    ELF_Word bss_size = 0;
    ELF_Word tls_size = 0;
    ELF_Word dp_size = 0;
    ELF_Word stack_size = 0;
    list_for_every_entry(&context->sections, section, section_t, node) {
      shdr = section->shdr;
      if (section_is_text(shdr)) {
	if (section_is_code(shdr)) 
	  text_size += shdr->sh_size;
	else if (section_is_rodata(shdr)) 
	  rodata_size += shdr->sh_size;
	else if (section_is_data(shdr)) 
	  data_size += shdr->sh_size;
      } else if (section_is_bss(shdr)) {
	if (section_is_stack(shdr)) 
	  stack_size += shdr->sh_size;
	else if (section_is_dp(shdr)) 
	  dp_size += shdr->sh_size;
	else 
	  bss_size += shdr->sh_size;
      }
    }

    // Elf Header
    int phcount = (text_size?1:0) + (rodata_size?1:0) + (data_size?1:0) +
      (bss_size?1:0) + (stack_size?1:0) + (dp_size?1:0) + (tls_size?1:0);
    context->header->e_phoff = sizeof(ELF_Ehdr);
    context->header->e_shoff = sizeof(ELF_Ehdr) + phcount * sizeof(ELF_Phdr) +
      text_size + rodata_size + data_size + tls_size;
    write(fd, context->header, sizeof(ELF_Ehdr));

    // Create the program headers
    ELF_Phdr* segment_buf = malloc(sizeof(ELF_Phdr));
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
      list_for_every_entry(&context->sections, section, section_t, node) {
	shdr = section->shdr;
	if (section_is_text(shdr)) {
	  if (section_is_code(shdr)) {
	    if (s == 0) write(fd, section->data, shdr->sh_size);
	  } else if (section_is_rodata(shdr)) {
	    if (s == 1) write(fd, section->data, shdr->sh_size);
	  } else if (section_is_data(shdr)) {
	    if (s == 2) write(fd, section->data, shdr->sh_size);
	  } else {
	    if (s == 3) write(fd, section->data, shdr->sh_size);
	  } 
	} else if (!section_is_bss(shdr)) {
	    if (s == 3) write(fd, section->data, shdr->sh_size);
	}
      }
    }

    // And finally the section headers
    ELF_Word shoff = sizeof(ELF_Ehdr); 
    for (int s = 0; s < 7; s++) {
      list_for_every_entry(&context->sections, section, section_t, node) {
	shdr = section->shdr;
	if (section_is_text(shdr)) {
	  if (section_is_code(shdr)) {
	    if (s == 0) {
	      shdr->sh_offset = shoff;
	      write(fd, section->data, sizeof(ELF_Shdr));
	      shoff += shdr->sh_size;
	    }
	  } else if (section_is_rodata(shdr)) {
	    if (s == 1) {
	      shdr->sh_offset = shoff;
	      write(fd, section->data, sizeof(ELF_Shdr));
	      shoff += shdr->sh_size;
	    }
	  } else if (section_is_data(shdr)) {
	    if (s == 2) {
	      shdr->sh_offset = shoff;
	      write(fd, section->data, sizeof(ELF_Shdr));
	      shoff += shdr->sh_size;
	    }
	  } else {
	    if (s == 6) {
	      shdr->sh_offset = shoff;
	      write(fd, section->data, sizeof(ELF_Shdr));
	      shoff += shdr->sh_size;
	    }
	  } 
	} else if (section_is_bss(shdr)) {
	  if (section_is_stack(shdr)) {
	    if (s == 3) {
	      shdr->sh_offset = shoff;
	      write(fd, section->data, sizeof(ELF_Shdr));
	    }
	  } else if (section_is_dp(shdr)) {
	    if (s == 4) {
	      shdr->sh_offset = shoff;
	      write(fd, section->data, sizeof(ELF_Shdr));
	      shoff += shdr->sh_size;
	    }
	  } else {
	    if (s == 5) {
	      shdr->sh_offset = shoff;
	      write(fd, section->data, sizeof(ELF_Shdr));
	    }
	  }
	} else {
	    if (s == 6) {
	      shdr->sh_offset = shoff;
	      write(fd, section->data, sizeof(ELF_Shdr));
	      shoff += shdr->sh_size;
	    }
	}
      }
    }
    close(fd);
  }
}

void elf_write_rom(elf_context_t *context, char *path)
{
}

void elf_release(elf_context_t *context)
{
  free(context->header);
  free(context); 
  context = 0;
}


ELF_Ehdr *elf_get_header(elf_context_t *context) 
{
  return context->header;
}

ELF_Shdr* elf_create_section(elf_context_t *context)
{
  context->header->e_shnum += 1;
  section_t *section = malloc(sizeof(section_t));

  list_add_head(&context->sections, &section->node);

  return section->shdr;
}

ELF_Shdr* elf_next_section(elf_context_t *context, ELF_Shdr *current)
{
  struct list_node node;
  if (current == 0) 
    node = context->sections;
  else
return deref(context->sections)->shdr;
  
}

void elf_remove_section(elf_context_t *context, ELF_Shdr *section_header)
{
}


ELF_Word elf_add_str(elf_context_t *context, char *str) 
{
}

ELF_Word elf_find_str(elf_context_t *context, char *str)
{
}

void elf_remove_str(elf_context_t *context, ELF_Word index)
{
}

