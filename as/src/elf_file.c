#include "elf_file.h"

#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

#include <stdio.h>

#include "memory.h"
#include "value.h"
#include "buffered_file.h" // For as_error

elf_context_t *elf_context;
elf_section_t *section;

elf_context_t *elf_create(const char *filename, ELF_Half e_machine)
{
  elf_context_t *context = 0;

  context = as_malloc(sizeof(elf_context_t));

  context->filename = as_strdup(filename);
  context->ehdr = as_mallocz(sizeof(ELF_Ehdr));
  context->ehdr->e_ident[EI_MAG0] = ELFMAG0;
  context->ehdr->e_ident[EI_MAG1] = ELFMAG1;
  context->ehdr->e_ident[EI_MAG2] = ELFMAG2;
  context->ehdr->e_ident[EI_MAG3] = ELFMAG3;
  context->ehdr->e_ident[EI_CLASS] = ELFCLASS32;
  context->ehdr->e_ident[EI_DATA] = ELFDATA2LSB;
  context->ehdr->e_ident[EI_VERSION] = EV_CURRENT;
  context->ehdr->e_ident[EI_OSABI] = ELFOSABI_OS16;
  context->ehdr->e_type = ET_REL;
  context->ehdr->e_machine = e_machine;
  context->ehdr->e_version = 1;
  context->ehdr->e_entry = 0x00000000;
  context->ehdr->e_phoff = 0;
  context->ehdr->e_shoff = 0;
  context->ehdr->e_flags = 0;
  context->ehdr->e_ehsize = sizeof(ELF_Ehdr);
  context->ehdr->e_phentsize = sizeof(ELF_Phdr);
  context->ehdr->e_phnum = 0;
  context->ehdr->e_shentsize = sizeof(ELF_Shdr);
  context->ehdr->e_shnum = 0;
  context->ehdr->e_shstrndx = 0; // We know it's the first one

  context->sections = 0;

  // Create section 0 SHN_UNDEF
  elf_section_t *undef = elf_section_create(context, 0, 0, SHT_NULL);
  undef->shdr->sh_addr = 0;
  undef->shdr->sh_offset = 0;
  undef->shdr->sh_link = 0;
  undef->shdr->sh_info = 0;
  undef->shdr->sh_addralign = 0;
  undef->shdr->sh_entsize = 0;
  undef->shdr->sh_size = 0;
  undef->data = 0;
  
  // Create the section header string table
  elf_section_t *shstrtab = elf_section_create(context, 0, 0, SHT_STRTAB);
  ELF_Shdr *shdr = shstrtab->shdr;
  shdr->sh_addr = 0;
  shdr->sh_offset = 0;
  shdr->sh_link = 1; // References itself
  shdr->sh_info = 0;
  shdr->sh_addralign = 0;
  shdr->sh_entsize = 0;
  shdr->sh_size = 1;
  shstrtab->data = as_mallocz(1); // First 0 byte
  context->shstrtab = shstrtab;
  shdr->sh_name = elf_string_create(shstrtab, ".shstrtab");
  
  // Create the symbol table
  elf_section_t *symtab = elf_section_create(context, 0, 0, SHT_SYMTAB);
  shdr = symtab->shdr;
  shdr->sh_addr = 0;
  shdr->sh_offset = 0;
  shdr->sh_link = 1; // String section 
  shdr->sh_info = 1;
  shdr->sh_addralign = 0;
  shdr->sh_entsize = sizeof(ELF_Sym);
  shdr->sh_size = sizeof(ELF_Sym);
  symtab->data = as_mallocz(sizeof(ELF_Sym)); // First 0 entry
  context->symtab = symtab;
  shdr->sh_name = elf_string_create(shstrtab, ".symtab");
  /*
  // Create the relocation table
  elf_section_t *reltab = elf_section_create(context, 0);
  shdr = reltab->shdr;
  shdr->sh_type = SHT_REL;
  shdr->sh_flags = 0;
  shdr->sh_addr = 0;
  shdr->sh_offset = 0;
  shdr->sh_link = 2; // References Symtab section
  shdr->sh_info = 10; // The code section that this refers to
  shdr->sh_addralign = 0;
  shdr->sh_entsize = sizeof(ELF_Rel);
  shdr->sh_size = sizeof(ELF_Rel);
  reltab->data = as_mallocz(sizeof(ELF_Rel)); // First 0 entry
  context->reltab = reltab;
  shdr->sh_name = elf_string_create(shstrtab, ".rel");
  */
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
    context->ehdr = as_malloc(sizeof(ELF_Ehdr));
    if ((read(fd, context->ehdr, sizeof(ELF_Ehdr)) != sizeof(ELF_Ehdr)) ||
        (context->ehdr->e_ident[0] != ELFMAG0) ||
        (context->ehdr->e_ident[1] != ELFMAG1) ||
        (context->ehdr->e_ident[2] != ELFMAG2) ||
        (context->ehdr->e_ident[3] != ELFMAG3)) {
      as_free(context); context = 0;
      as_error("Invalid ELF file");
    } else {
      // Load the sections
      lseek(fd, context->ehdr->e_shoff, SEEK_SET);
      for (int i = 0; i < context->ehdr->e_shnum; i++) {
        elf_section_t *section = as_malloc(sizeof(elf_section_t));
		section->shdr = as_malloc(sizeof(ELF_Shdr));
        r = read(fd, section->shdr, sizeof(ELF_Shdr));
		if (r != sizeof(ELF_Shdr)) as_error("Malformed ELF file");
		int num = i;
		int num_alloc = 1;
		
		// Every power of two we double array size
		if ((num & (num - 1)) == 0) {
		  if (num) num_alloc = num * 2;
		  context->sections = as_realloc(context->sections, num_alloc * sizeof(void*));
		}
		context->sections[num++] = section;
		
		section->instrs = 0;
		section->num_instrs = 0;
		section->data = 0;
      }
	  
      // Now load the data
      for (int i = 0; i < context->ehdr->e_shnum; i++) {
		elf_section_t *section = context->sections[i];
		ELF_Word len = section->shdr->sh_size;
		section->data = as_malloc(len);
		lseek(fd, section->shdr->sh_offset, SEEK_SET);
		r = read(fd, section->data, len);
		if (r != len) as_error("Malformed ELF section");
		printf("Read section %d bytes.\n", len);
      }
    }
  }
  close(fd);

  return context;
}

elf_context_t *elf_load(const char *filename) 
{
  size_t r;
  int fd;
  elf_context_t *context = 0;
  fd = open(filename, O_RDONLY);

  if (fd != 0) {

    context = as_malloc(sizeof(elf_context_t));
    context->filename = as_strdup(filename);
    
    // Validate the header
    context->ehdr = as_malloc(sizeof(ELF_Ehdr));
    if ((read(fd, context->ehdr, sizeof(ELF_Ehdr)) != sizeof(ELF_Ehdr)) ||
        (context->ehdr->e_ident[0] != ELFMAG0) ||
        (context->ehdr->e_ident[1] != ELFMAG1) ||
        (context->ehdr->e_ident[2] != ELFMAG2) ||
        (context->ehdr->e_ident[3] != ELFMAG3)) {
      as_free(context); context = 0;
      as_error("Invalid ELF file");
    } else {
      // Load the segments
      lseek(fd, context->ehdr->e_shoff, SEEK_SET);
      for (int i = 0; i < context->ehdr->e_shnum; i++) {
        elf_section_t *section = as_malloc(sizeof(elf_section_t));
		section->shdr = as_malloc(sizeof(ELF_Shdr));
        r = read(fd, section->shdr, sizeof(ELF_Shdr));
		if (r != sizeof(ELF_Shdr)) as_error("Malformed ELF file");
		int num = i;
		int num_alloc = 1;
		
		// Every power of two we double array size
		if ((num & (num - 1)) == 0) {
		  if (num) num_alloc = num * 2;
		  context->sections = as_realloc(context->sections, num_alloc * sizeof(void*));
		}
		context->sections[num++] = section;
		
		section->instrs = 0;
		section->num_instrs = 0;
		section->data = 0;
      }
	  
      // Now load the data
      for (int i = 0; i < context->ehdr->e_shnum; i++) {
		elf_section_t *section = context->sections[i];
		ELF_Word len = section->shdr->sh_size;
		section->data = as_malloc(len);
		lseek(fd, section->shdr->sh_offset, SEEK_SET);
		r = read(fd, section->data, len);
		if (r != len) as_error("Malformed ELF section");
		printf("Read section %d bytes.\n", len);
      }
    }
  }
  close(fd);

  return context;
}

ELF_Word file_size(elf_section_t *section)
{
  if (section_is_bss(section)) return 0;
  return section->shdr->sh_size;
}

/*
This is the simplest write. We don't need to worry about the program/segment header
and can just write out all the sections.

Both Intel and 6502 are little endian, so we don't need to worry about that here.

  make_segment("stack", PF_R | PF_W | PF_S);
  make_segment("dp", PF_R | PF_W | PF_D);
  make_segment("tls", PF_R | PF_W);
  make_segment("bss", PF_R | PF_W);
  make_segment("data", PF_R | PF_W);
  make_segment("rodata", PF_R);
  make_segment("text", PF_R | PF_W);

use readelf -h to test this output.
*/
void elf_write_object(elf_context_t *context)
{
  ssize_t r;
  ELF_Word shoff;

  int fd = open(context->filename, O_CREAT | O_TRUNC | O_WRONLY, S_IRWXU);
  
  if (fd != 0) {
    elf_section_t **sections;
    elf_section_t *section;
    
    shoff = sizeof(ELF_Ehdr);

    sections = context->sections;
    for (int i = 0; i < context->ehdr->e_shnum; i++) {
      section = *sections;
	  ELF_Word sz = file_size(section);
	  if (sz > 0) {
		shoff += sz;
	  }
	  sections++;
    }

    context->ehdr->e_phoff = 0;
    context->ehdr->e_shoff = shoff;
    r = write(fd, context->ehdr, sizeof(ELF_Ehdr));
    if (r != sizeof(ELF_Ehdr)) { as_error("Write failed"); return; }

    sections = context->sections;
    for (int i = 0; i < context->ehdr->e_shnum; i++) {
      section = *sections;
	  if (section->shdr->sh_size > 0) {
		//as_warn("Writing section data for %s, length $%04x\n",
		//	   elf_string_get(context->shstrtab, section->shdr->sh_name), section->shdr->sh_size);
		r = write(fd, section->data, section->shdr->sh_size);
		if (r != section->shdr->sh_size) { as_error("Write failed"); return; }
	  }
	  sections++;
    }

    shoff = sizeof(ELF_Ehdr);

    sections = context->sections;
    for (int i = 0; i < context->ehdr->e_shnum; i++) {
      section = *sections;
	  //as_warn("Writing section header for %s, offset $%04x\n",
	  //		   elf_string_get(context->shstrtab, section->shdr->sh_name), section->shdr->sh_offset);
	  r = write(fd, section->shdr, sizeof(ELF_Shdr));
	  if (r != sizeof(ELF_Shdr)) { as_error("Write failed"); return; }
	  sections++;
    }
    
    close(fd);
  }
}

void elf_write_executable_simple(elf_context_t *context)
{
  ssize_t r;

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

    
    // Write File Header - exists in the ELF context
    int phcount = (text_size?1:0) + (rodata_size?1:0) + (data_size?1:0) +
      (bss_size?1:0) + (stack_size?1:0) + (dp_size?1:0) + (tls_size?1:0);
    context->ehdr->e_phoff = sizeof(ELF_Ehdr);
    context->ehdr->e_shoff = sizeof(ELF_Ehdr) + phcount * sizeof(ELF_Phdr) +
      text_size + rodata_size + data_size + tls_size;
    r = write(fd, context->ehdr, sizeof(ELF_Ehdr));

    close(fd);
    printf("Wrote %ld bytes to '%s'\n", r, context->filename);
  }
}

ELF_Word pflags(ELF_Word sflags) {
  ELF_Word result = PT_NULL;

  if (sflags & SHF_ALLOC) {
	//	result |= PT_LOAD;
  }
  if (sflags & SHF_EXECINSTR) {
	result |= PT_LOAD;
  }

  return result;
}

void elf_write_executable(elf_context_t *context)
{
  ssize_t r;

  int fd = open(context->filename, O_CREAT | O_TRUNC | O_APPEND | O_WRONLY, S_IRWXU);
  
  if (fd != 0) {

	elf_section_t **sections;
    elf_section_t *section;
    
    int phcount = 0;
	ELF_Word shoff = sizeof(ELF_Ehdr);

    sections = context->sections;
    for (int i = 0; i < context->ehdr->e_shnum; i++) {
      section = *sections;
	  ELF_Word sz = file_size(section);
	  if (sz > 0) {
		shoff += sizeof(ELF_Phdr) + sz;
		phcount++;
	  }
	  sections++;
    }

    // Elf Header
    context->ehdr->e_phnum = phcount;
    context->ehdr->e_phoff = sizeof(ELF_Ehdr);
    context->ehdr->e_shoff = shoff;
    r = write(fd, context->ehdr, sizeof(ELF_Ehdr));
	// as_warn("Program header is $%04x bytes. There are $%02x program headers.\n", sizeof(ELF_Phdr), phcount);
    if (r != sizeof(ELF_Ehdr)) {
      perror("Couldn't write ELF file");
      return;
    }

	// Write the program headers
    ELF_Phdr* phdr_buf = as_malloc(sizeof(ELF_Phdr));
    phdr_buf->p_type = PT_LOAD;
    phdr_buf->p_offset = sizeof(ELF_Ehdr) + sizeof(ELF_Phdr) * context->ehdr->e_phnum;  // Segment data file offset 
    phdr_buf->p_vaddr = 0;                  // Segment virtual address 
    phdr_buf->p_paddr = 0;                  // Segment physical address 
    phdr_buf->p_filesz = 0;                 // Segment size in file 
    phdr_buf->p_memsz = 0;;                 // Segment size in memory
    phdr_buf->p_flags = 0;;                 // Segment flags 
    phdr_buf->p_align = 0;                  // Segment alignment, not used

	sections = context->sections;
    for (int i = 0; i < context->ehdr->e_shnum; i++) {
      section = *sections;
	  ELF_Word sz = file_size(section);
	  if (sz > 0) {
		phdr_buf->p_vaddr = section->shdr->sh_addr;
		phdr_buf->p_paddr = section->shdr->sh_addr;
		phdr_buf->p_filesz = sz;
		phdr_buf->p_memsz = sz;
		phdr_buf->p_flags = pflags(section->shdr->sh_flags);
		// as_warn("Wrote program header, org is $%04x, size is $%04x",
		//		phdr_buf->p_paddr, sz);
		r = write(fd, phdr_buf, sizeof(ELF_Phdr));
		if (r != sizeof(ELF_Phdr)) { as_error("Write failed"); return; }

		phdr_buf->p_offset += sz;
	  }
	  sections++;
    }

    // Write the data
	ELF_Word offset = sizeof(ELF_Ehdr) + phcount * sizeof(ELF_Phdr);
	// b4 = 34 + 4 * 20 !214
    sections = context->sections;
    for (int i = 0; i < context->ehdr->e_shnum; i++) {
      section = *sections;
	  section->shdr->sh_offset = offset;
	  ELF_Word sz = file_size(section);
	  // Only write if we have data
	  if (sz) {
		r = write(fd, section->data, sz);
		if (r != sz) { as_error("Write failed"); return; }
		//as_warn("Writing segment data for %s, length $%04x",
		//		elf_string_get(context->shstrtab, section->shdr->sh_name), sz);
		as_warn("Writing segment data for %s, offset = $%04x (%d), length $%04x (%d)\n",
				elf_string_get(context->shstrtab, section->shdr->sh_name), offset, offset, sz, sz);
		offset += sz;
	  }
	  sections++;
    }
	
	// Write the section headers
    sections = context->sections;
    for (int i = 0; i < context->ehdr->e_shnum; i++) {
      section = *sections;
	  //as_warn("Writing section header for %s, offset $%04x\n",
	  //		  elf_string_get(context->shstrtab, section->shdr->sh_name),
	  //		  section->shdr->sh_offset);
	  r = write(fd, section->shdr, sizeof(ELF_Shdr));
	  if (r != sizeof(ELF_Shdr)) { as_error("Write failed"); return; }
	  sections++;
    }
	
    close(fd);
  }
}

void elf_write_binary(elf_context_t *context)
{
  ssize_t r;

  elf_section_t **sections;
  elf_section_t *section;
  ELF_Shdr *shdr;

  int fd = open(context->filename, O_CREAT | O_TRUNC | O_APPEND | O_WRONLY, S_IRWXU);
  if (fd != 0) {
    sections = context->sections;
	// Write the section data in type order
    for (int s = 0; s < 4; s++) {
	  //      sections = context->sections;
      for (int i = 0; i < context->ehdr->e_shnum; i++) {
		section = sections[i];
        shdr = section->shdr;
        if (section_is_text(section)) {
          if (section_is_code(section)) {
            if (s == 0) {
			  r = write(fd, section->data, shdr->sh_size);
			  if (r != shdr->sh_size) as_error("Write error");
			}
          } else if (section_is_rodata(section)) {
            //if (s == 1) r = write(fd, section->data, shdr->sh_size);
          } else if (section_is_data(section)) {
            //if (s == 2) r = write(fd, section->data, shdr->sh_size);
          } else {
            //if (s == 3) r = write(fd, section->data, shdr->sh_size);
          } 
        } else if (!section_is_bss(section)) {
          //if (s == 3) r = write(fd, section->data, shdr->sh_size);
        }
      }
    }
   	close(fd);
  }
}

void elf_write_s19(elf_context_t *context)
{
}

void elf_write_s28(elf_context_t *context)
{
}

void elf_write_s37(elf_context_t *context)
{
}

void elf_write_intel(elf_context_t *context)
{
}

#define TIM_STEP 16
void elf_write_tim(elf_context_t *context)
{
  int i, j;
  int c;
  int size;
  int addr;
  int csum;

  elf_set_section("text");
  if (section == 0) {
    as_error("text section not found while writing TIM file.");
    return;
  }
  int fd = open(context->filename, O_CREAT | O_APPEND | O_WRONLY, S_IRWXU);
  
  if (fd != 0) {
    addr = section->shdr->sh_addr;
    size = section->shdr->sh_size;
    for (i = 0; i < size; i += TIM_STEP) {
      c = size - i;
      if (c > TIM_STEP) c = TIM_STEP;
      csum = c;
      csum += (addr + i) >> 8;
      csum += (addr + i) % 0x100;
      dprintf(fd, ";%02X%04X", c, addr + i); 
      for (j = 0; j < c; j++) {
	csum += section->data[i+j];
	dprintf(fd, "%02X", section->data[i+j]);
      }
      dprintf(fd, "%04X\n", csum);
    }
    dprintf(fd, ";00\n");
    close(fd);
  }

}

void elf_release(elf_context_t *context)
{
  if( context ) {
    elf_section_t **sections = context->sections;
    for (int i = 0; i < context->ehdr->e_shnum; i++) {
      section = *sections;
      as_free(section->data);
      as_free(section->shdr);
      as_free(section);
      sections++;
    }
    as_free(context->filename);
    as_free(context->ehdr);
    as_free(context); 
  }
}

elf_section_t *elf_section_create(elf_context_t *context,
								  const char *nm,
								  ELF_Word flags,
								  ELF_Word type)
{
  ELF_Word name = 0;
  if (nm != 0) {
	name = elf_string_locate(elf_context->shstrtab, nm);
	if (nm == 0) {
	  name = elf_string_create(elf_context->shstrtab, nm);
	}
  }
  
  elf_section_t *section = 0;
  elf_section_t **sections = context->sections;
  for (int i = 0; i < context->ehdr->e_shnum; i++) {
	section = *sections;
	if (section->shdr->sh_name == name) return section;
  }

  // Create it
  section = as_mallocz(sizeof(elf_section_t));
  section->shdr = as_mallocz(sizeof(ELF_Shdr));
  section->shdr->sh_name = name;  
  section->shdr->sh_flags = flags;
  section->shdr->sh_type = type;
  
  // section->instrs = 0;
  // section->num_instrs = 0;
  // section->data = 0;

  int num = context->ehdr->e_shnum;
  int num_alloc = 1;

  // Every power of two we double array size
  if ((num & (num - 1)) == 0) {
    if (num) num_alloc = num * 2;
    context->sections = as_realloc(context->sections, num_alloc * sizeof(void*));
  }
  context->sections[num++] = section;
  context->ehdr->e_shnum = num;

  return section;
}

elf_section_t* elf_section_find(elf_context_t *context, ELF_Word name)
{
  elf_section_t **sections = context->sections;
  elf_section_t *section;
  for (int i = 0; i < context->ehdr->e_shnum; i++) {
    section = *sections;
    if (section->shdr->sh_name == name) return section;
    sections++;
  }
  return 0;
}

/* Symbol */
void elf_symbol_create(elf_context_t *context,
					   const char *name,
					   ELF_Addr value,
					   ELF_Word size,
					   unsigned char info) 
{
  ELF_Word elf_string = elf_string_create(context->shstrtab, name);

  elf_section_t *symtab = context->symtab; 

  // We realloc every time, this could definitely be better
  ELF_Word new_size = symtab->shdr->sh_size + sizeof(ELF_Sym);
  symtab->data = as_realloc(symtab->data, new_size);

  ELF_Sym *sym = (ELF_Sym *)(symtab->data + symtab->shdr->sh_size);
  sym->st_name = elf_string;
  sym->st_value = value;
  sym->st_size = size;
  sym->st_info = info;
  sym->st_other = 0;
  sym->st_shndx = 0; // Not currently used

  //  as_warn("Symbol created with name %s(%04x) and value %04x", name, elf_string, value);
  symtab->shdr->sh_size = new_size;
}

/* String */

ELF_Word elf_string_create(elf_section_t *section, const char *str) 
{
  ELF_Word len, offset;

  offset = elf_string_locate(section, str);
  if (!offset) {
    offset = section->shdr->sh_size;
    len = strlen(str) + 1;

    // We realloc every time, this could definitely be better
    section->data = as_realloc(section->data, offset + len);
    memcpy(section->data + offset, str, len);
    section->shdr->sh_size = offset + len;
  }
  return offset;
}

const char *elf_string_get(elf_section_t *section, ELF_Word offset)
{
  return (const char *)section->data + offset;
}

ELF_Word elf_string_locate(elf_section_t *section, const char *str)
{
  unsigned char *o = section->data + 1; /* First char is \0 */
  ELF_Word len = strlen(str);
  unsigned char *end = section->data + section->shdr->sh_size;
  while (o < end) {
    unsigned char *next = o + strlen((const char *)o) + 1;
    o = (unsigned char *)strstr((const char *)o, str);
    while (o != 0) {
      if (*(o + len) == '\0') return (o - section->data);
      o += len;
      o = (unsigned char *)strstr((const char *)o, str);
    }
    o = next;
  };
  return 0;
}

/* Symbol */

ELF_Word elf_symbol_add(elf_section_t *section, ELF_Sym *symbol) 
{
  ELF_Word len, offset;

  offset = section->shdr->sh_size;
  len = sizeof(ELF_Sym);

  /* We realloc every time, this could definitely be better */
  section->data = as_realloc(section->data, offset + len);
  memcpy(section->data + offset, symbol, len);
  section->shdr->sh_size = offset + len;
  section->shdr->sh_info += 1;
  return offset;
}

const ELF_Sym *elf_symbol_get(elf_context_t *context, ELF_Word offset)
{
  return (const ELF_Sym *)context->symtab->data + offset;
}

ELF_Word elf_symbol_locate(elf_context_t *context, ELF_Word st_name)
{
  elf_section_t *symtab = context->symtab;
  ELF_Sym* p = (ELF_Sym *)symtab->data;
  void *end = symtab->data + symtab->shdr->sh_size;
  while ((void *)p < end) {
    if( p->st_name == st_name)
	  return ((ELF_Word)((void *)p - (void *)symtab->data));
    p += sizeof(ELF_Sym);
  } 
  return 0;
}

/* Relocation */

ELF_Word elf_relocation_create(elf_section_t *section, ELF_Addr offset, ELF_Word info)
{
  ELF_Word len, off;

  off = section->shdr->sh_size;
  len = sizeof(ELF_Rel);

  // We realloc every time, this could definitely be better
  section->data = as_realloc(section->data, off + len);
  section->shdr->sh_size = off + len;

  ELF_Rel *rel = (ELF_Rel *)(section->data + off);
  rel->r_offset = offset;
  rel->r_info = info;

  return off;
}

const ELF_Rel *elf_relocation_next(elf_section_t *section, ELF_Rel *current)
{
  void *p;
  
  if (current == 0)
    p = section->data;
  else
    p = current + section->shdr->sh_size;
  return (const ELF_Rel *)p;
}

void elf_set_section(const char *name)
{
  ELF_Word nm = elf_string_locate(elf_context->shstrtab, name);
  if (nm != 0) {
    section = elf_section_find(elf_context, nm);
    if (section == 0) {
      section = elf_section_create(elf_context, name, 0, SHF_EXECINSTR);
    }
  }
}



