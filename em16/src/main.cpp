//==============================================================================
//                                          .ooooo.     .o      .ooo   
//                                         d88'   `8. o888    .88'     
//  .ooooo.  ooo. .oo.  .oo.   oooo  oooo  Y88..  .8'  888   d88'      
// d88' `88b `888P"Y88bP"Y88b  `888  `888   `88888b.   888  d888P"Ybo. 
// 888ooo888  888   888   888   888   888  .8'  ``88b  888  Y88[   ]88 
// 888    .o  888   888   888   888   888  `8.   .88P  888  `Y88   88P 
// `Y8bod8P' o888o o888o o888o  `V88V"V8P'  `boood8'  o888o  `88bod8'  
//                                                                    
// A Portable C++ WDC 65C816 Emulator  
//------------------------------------------------------------------------------
// Copyright (C),2016 Andrew John Jacobs
// All rights reserved.
//
// This work is made available under the terms of the Creative Commons
// Attribution-NonCommercial-ShareAlike 4.0 International license. Open the
// following URL to see the details.
//
// http://creativecommons.org/licenses/by-nc-sa/4.0/
//------------------------------------------------------------------------------

#include <iostream>
#include <fstream>
#include <string>

using namespace std;

#include <string.h>
#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

#include "emu816.h"

#include "elf.h"
#include "elf_file.h"

// Stub for as_error when building standalone (without assembler toolchain)
#ifndef HAS_BUFFERED_FILE
#include <cstdarg>
static void as_error(const char *message, ...) {
  va_list args;
  va_start(args, message);
  vfprintf(stderr, message, args);
  va_end(args);
  fprintf(stderr, "\n");
  exit(1);
}
#else
#include "buffered_file.h"
#endif


//==============================================================================
// Memory Definitions
//------------------------------------------------------------------------------

// Create a 1024kb RAM area - No ROM.
#define	RAM_SIZE	(2 * 64 * 1024)
#define MEM_MASK	(2 * 64 * 1024L - 1)

bool trace = false;

static Symbol* symtab;

//==============================================================================

// Initialise the emulator
INLINE void setup()
{
  emu816::setMemory(MEM_MASK, RAM_SIZE, NULL);
}

// Execute instructions
INLINE void loop()
{
  emu816::step();
}

//==============================================================================
// S19/28 Record Loader
//------------------------------------------------------------------------------

unsigned int toNybble(char ch)
{
	if ((ch >= '0') && (ch <= '9')) return (ch - '0');
	if ((ch >= 'A') && (ch <= 'F')) return (ch - 'A' + 10);
	if ((ch >= 'a') && (ch <= 'f')) return (ch - 'a' + 10);
	return (0);
}

unsigned int toByte(string &str, int &offset)
{
	unsigned int	h = toNybble(str[offset++]) << 4;
	unsigned int	l = toNybble(str[offset++]);

	return (h | l);
}

unsigned int toWord(string &str, int &offset)
{
	unsigned int	h = toByte(str, offset) << 8;
	unsigned int	l = toByte(str, offset);

	return (h | l);
}

unsigned long toAddr(string &str, int &offset)
{
	unsigned long	h = toByte(str, offset) << 16;
	unsigned long	m = toByte(str, offset) << 8;
	unsigned long	l = toByte(str, offset);

	return (h | m | l);
}

void load(char *filename) {
  ifstream file(filename);
  string line;

  if (file.is_open()) {
    cout << ">> Loading S28: " << filename << endl;
    
    while (!file.eof()) {
      file >> line;
      if (line[0] == 'S') {
	int offset = 2;
	
	if (line[1] == '1') {
	  unsigned int count = toByte(line, offset);
	  unsigned long addr = toWord(line, offset);
	  count -= 3;
	  while (count-- > 0) {
	    emu816::setByte(addr++, toByte(line, offset));
	  }
	} else if (line[1] == '2') {
	  unsigned int count = toByte(line, offset);
	  unsigned long addr = toAddr(line, offset);
	  count -= 4;
	  while (count-- > 0) {
	    emu816::setByte(addr++, toByte(line, offset));
	  }
	}
      }
    }
    file.close();
  } else {
    cerr << "Failed to open file" << endl;
  }
}

//==============================================================================
// ELF Loader
//------------------------------------------------------------------------------

unsigned int loadELF(char * filename) {
  size_t r;
  int fd;
  wdc816::Byte *buffer = new wdc816::Byte[16 * 1024];
  ELF_Ehdr *ehdr = new ELF_Ehdr;
  ELF_Phdr *phdr = new ELF_Phdr;
  ELF_Shdr *shdr = new ELF_Shdr;
  ELF_Sym *sym = new ELF_Sym;
  
  fd = open(filename, O_RDONLY);
  
  if (fd != 0) {
	
    // Validate the header
    if ((read(fd, ehdr, sizeof(ELF_Ehdr)) != sizeof(ELF_Ehdr)) ||
        (ehdr->e_ident[0] != ELFMAG0) ||
        (ehdr->e_ident[1] != ELFMAG1) ||
        (ehdr->e_ident[2] != ELFMAG2) ||
        (ehdr->e_ident[3] != ELFMAG3)) {
        as_error("Invalid ELF file");
    } else {

	  // Set up the machine
	  ELF_Half machine = ehdr->e_machine;
	  switch (machine) {
	  case EM_816:
		cout << "Configured for 65C816." << endl;
		emu816::setStackPage(0x0100);
		break;
	  case EM_C02:
		cout << "Configured for 65C02." << endl;
		emu816::setStackPage(0x0100);
		break;
	  case EM_02:
		cout << "Configured for 6502." << endl;
		emu816::setStackPage(0x0100);
		break;
	  case EM_RC02:
		cout << "Configured for R65C02." << endl;
		emu816::setStackPage(0x0100);
		break;
	  case EM_RC19:
		cout << "Configured for Rockwell C19." << endl;
		emu816::setStackPage(0x0100);
		break;
	  case EM_RC01:
		cout << "Configured for R6501Q." << endl;
		emu816::setStackPage(0x0000);
		break;
	  }
	  
      // Load the segments
      lseek(fd, ehdr->e_phoff, SEEK_SET);
      for (int i = 0; i < ehdr->e_phnum; i++) {
		lseek(fd, ehdr->e_phoff + i * sizeof(ELF_Phdr), SEEK_SET);
		r = read(fd, phdr, sizeof(ELF_Phdr));
		if (r != sizeof(ELF_Phdr)) as_error("Malformed ELF file");
		if (phdr->p_type == PT_LOAD) {
		  ELF_Addr addr = phdr->p_paddr;
		  ELF_Word len = phdr->p_filesz;
		  if ((addr > 0) && (len > 0)) {
			lseek(fd, phdr->p_offset, SEEK_SET);
			int r = read(fd, buffer, len);
			if (r == (int)len) { 
			  int count = 0;
			  cout << "Read segment into " << hex << addr << ", length " << len << endl;
			  for (count = 0; count<(int)len; count++) {
				emu816::setByte(addr++, buffer[count]);
			  }
			}
		  }
		}
	  }
	}

	// Load the strtab for debugging
	lseek(fd, ehdr->e_shoff + ehdr->e_shstrndx * sizeof(ELF_Shdr), SEEK_SET);
	r = read(fd, shdr, sizeof(ELF_Shdr));
	
	char *strtab = (char *)malloc(shdr->sh_size);
	lseek(fd, shdr->sh_offset, SEEK_SET);
	r = read(fd, strtab, shdr->sh_size);

	int symcount = 0;
	
	// Load the symbol table for debugging
	for (int i = 0; i < ehdr->e_shnum; i++) {
	  lseek(fd, ehdr->e_shoff + i * sizeof(ELF_Shdr), SEEK_SET);
	  r = read(fd, shdr, sizeof(ELF_Shdr));
	  if (shdr->sh_type == SHT_SYMTAB) {
		int size = shdr->sh_size;
		symcount = size / sizeof(ELF_Sym);
		lseek(fd, shdr->sh_offset, SEEK_SET);

		symtab = new struct Symbol[symcount];
	  
		for (int j = 0; j < symcount; j++) {
		  r = read(fd, sym, sizeof(ELF_Sym));
		  symtab[j].addr = sym->st_value;
		  symtab[j].label = sym->st_name;
		}
	  }
	}

	emu816::setSymbols(symtab, symcount, strtab);
	
	close(fd);
  }

  unsigned int result = ehdr->e_entry;
  delete ehdr;
  delete phdr;
  delete[] buffer;
  
  return result;
}

//==============================================================================
// Oberon Loader
//------------------------------------------------------------------------------

// Relocatable module loader configuration
#define MODULE_BASE_ADDRESS 0x00    // First module loads here within bank
#define MODULE_BANK 0x01              // Use bank 1 for modules (bank 0 for system)
#define MODULE_VAR_BASE 0x1000        // Variable storage base
#define BANK_SIZE 0x10000             // 64KB per bank
#define MODULE_TABLE_BASE 0x0E00      // Module table: 16 entries x 2 bytes = 32 bytes

// Module tracking
#define MAX_EXPORTS 64

typedef struct ModuleInfo {
    char name[64];
    uint8_t bank;
    uint32_t base_address;     // Address within bank
    uint32_t var_address;      // Variable storage address
    uint32_t size;
    uint32_t entry_point;      // Relocated entry point (within bank)
    int relocation_count;
    int export_count;          // Number of exported entries
    uint32_t exports[MAX_EXPORTS]; // Export values indexed by exno (1-based)
    struct ModuleInfo *next;
} ModuleInfo;

static uint8_t current_module_bank = MODULE_BANK;
static uint32_t current_load_address = MODULE_BASE_ADDRESS;
static uint32_t current_var_address = MODULE_VAR_BASE;
static int current_module_index = 0;
static ModuleInfo *loaded_modules = NULL;

// Module entry points for init (moved to file scope for auto-load support)
static int mod_count = 0;
static unsigned int mod_entries[64];

// Search directory for auto-loading dependencies
static char search_dir[256] = "";

// Construct a .816 path from a module name relative to a reference file's directory
// e.g., reference_file="test/Foo.816", module_name="Out" -> "test/Out.816"
static bool construct_module_path(const char *reference_dir, const char *module_name,
                                  char *out, int out_size) {
  int needed = snprintf(out, out_size, "%s%s.816", reference_dir, module_name);
  return needed > 0 && needed < out_size;
}

// Find a loaded module by name
static ModuleInfo *find_module_by_name(const char *name) {
    ModuleInfo *mod = loaded_modules;
    while (mod) {
        if (strcmp(mod->name, name) == 0) return mod;
        mod = mod->next;
    }
    return NULL;
}

// Apply relocation based on instruction type (JSR, JSL, or LDA)
// import_map maps mno (1-based) to loaded ModuleInfo for resolving imports
static void apply_relocation(uint32_t reloc_addr, uint32_t module_base,
                             uint32_t module_var_base,
                             ModuleInfo **import_map, int import_count) {
    uint8_t opcode = emu816::getByte(reloc_addr);

    if (opcode == 0x20) {           // JSR - 2-byte address
        uint16_t addr = emu816::getByte(reloc_addr + 1) |
                       (emu816::getByte(reloc_addr + 2) << 8);
        addr += module_base;
        emu816::setByte(reloc_addr + 1, addr & 0xFF);
        emu816::setByte(reloc_addr + 2, (addr >> 8) & 0xFF);
        printf("  JSR relocation at $%06X: $%04X -> $%04X\n",
               reloc_addr, addr - (uint16_t)module_base, addr);

    } else if (opcode == 0x22) {    // JSL - 3-byte address
        uint8_t bank_byte = emu816::getByte(reloc_addr + 3);
        uint16_t addr_word = emu816::getByte(reloc_addr + 1) |
                            (emu816::getByte(reloc_addr + 2) << 8);

        if (bank_byte > 0 && bank_byte <= import_count && import_map[bank_byte]) {
            // Inter-module import fixup: bank byte = mno, addr = exno
            int mno = bank_byte;
            int exno = addr_word;
            ModuleInfo *target = import_map[mno];

            if (exno > 0 && exno < target->export_count) {
                uint32_t target_addr = target->exports[exno];
                uint32_t full_addr = target->base_address + target_addr;
                printf("  JSL import fixup at $%06X: mno=%d exno=%d -> %s $%02X:%04X\n",
                       reloc_addr, mno, exno, target->name,
                       target->bank, full_addr);
                emu816::setByte(reloc_addr + 1, full_addr & 0xFF);
                emu816::setByte(reloc_addr + 2, (full_addr >> 8) & 0xFF);
                emu816::setByte(reloc_addr + 3, target->bank);
            } else {
                printf("  Warning: Invalid exno %d for module %s (has %d exports)\n",
                       exno, target->name, target->export_count - 1);
            }
        } else {
            // Intra-module relocation: bank byte == 0
            uint32_t addr = addr_word + module_base;
            emu816::setByte(reloc_addr + 1, addr & 0xFF);
            emu816::setByte(reloc_addr + 2, (addr >> 8) & 0xFF);
            emu816::setByte(reloc_addr + 3, current_module_bank);
            printf("  JSL relocation at $%06X: $%04X -> $%02X:%04X\n",
                   reloc_addr, addr_word, current_module_bank, addr & 0xFFFF);
        }

    } else if (opcode == 0xA9) {    // LDA #imm16 - module var base relocation
        uint16_t operand = emu816::getByte(reloc_addr + 1) |
                          (emu816::getByte(reloc_addr + 2) << 8);
        uint16_t var_base;
        if (operand == 0x0000) {
            var_base = module_var_base;  // own module
        } else {
            int mno = operand;           // import mno
            if (mno <= import_count && import_map[mno]) {
                var_base = import_map[mno]->var_address;
            } else {
                printf("Warning: LDA relocation mno %d not found\n", mno);
                var_base = 0;
            }
        }
        emu816::setByte(reloc_addr + 1, var_base & 0xFF);
        emu816::setByte(reloc_addr + 2, (var_base >> 8) & 0xFF);
        printf("  LDA relocation at $%06X: operand=$%04X -> var_base $%04X\n",
               reloc_addr, operand, var_base);

    } else if (opcode == 0x62) {    // PER - imported procedure address
        uint16_t operand = emu816::getByte(reloc_addr + 1) |
                          (emu816::getByte(reloc_addr + 2) << 8);
        int mno = (operand >> 8) & 0xFF;
        int exno = operand & 0xFF;
        if (mno > 0 && mno <= import_count && import_map[mno]) {
            ModuleInfo *target = import_map[mno];
            if (exno > 0 && exno < target->export_count) {
                uint32_t target_addr = target->base_address + target->exports[exno];
                // PER pushes PC + operand + 3, we want it to push target_addr
                // So operand = target_addr - (reloc_addr - bank_address) - 3
                // where (reloc_addr - bank_address) gives the intra-bank PER address
                uint16_t per_addr_inbank = (uint16_t)(reloc_addr & 0xFFFF);
                int16_t per_offset = (int16_t)(target_addr - per_addr_inbank - 3);
                emu816::setByte(reloc_addr + 1, per_offset & 0xFF);
                emu816::setByte(reloc_addr + 2, (per_offset >> 8) & 0xFF);
                printf("  PER import fixup at $%06X: mno=%d exno=%d -> %s addr=$%04X (PER operand=$%04X)\n",
                       reloc_addr, mno, exno, target->name,
                       target_addr, (uint16_t)per_offset);
            } else {
                printf("  Warning: Invalid exno %d for module %s (has %d exports)\n",
                       exno, target->name, target->export_count - 1);
            }
        } else {
            printf("Warning: PER relocation mno %d not found\n", mno);
        }

    } else {
        printf("Warning: Relocation at $%06X points to unknown opcode $%02X\n",
               reloc_addr, opcode);
    }
}

// (Module info is now created directly in loadMod)

unsigned int loadMod(char * filename) {
  uint32_t count;
  // module_base and module_var_base are set after imports are parsed,
  // because auto-loading dependencies may advance the load addresses.
  uint32_t module_base;
  uint32_t module_var_base;

  // Set search_dir from filename if not already set
  if (search_dir[0] == '\0') {
    const char *last_slash = strrchr(filename, '/');
    if (last_slash) {
      int dir_len = (int)(last_slash - filename + 1); // include trailing /
      if (dir_len < (int)sizeof(search_dir)) {
        memcpy(search_dir, filename, dir_len);
        search_dir[dir_len] = '\0';
      }
    }
    // If no slash, search_dir stays empty (current directory - no prefix needed)
  }

  // Set up the machine
  cout << "Configured for 65C816." << endl;
  emu816::setStackPage(0x0100);

  FILE *file = fopen(filename, "rb");
  if (!file) {
    printf("Error: Cannot open file %s\n", filename);
    return 0;
  }

  // Read module name (null-terminated string)
  char module_name[64];
  int name_len = 0;
  while (name_len < 63) {
    if (fread(&module_name[name_len], 1, 1, file) != 1) {
      printf("Error: Unexpected end of file reading module name\n");
      fclose(file);
      return 0;
    }
    if (module_name[name_len] == 0) break;
    name_len++;
  }
  module_name[name_len] = 0;

  printf("Module: %s\n", module_name);

  // Read key (4 bytes)
  uint32_t key;
  if (fread(&key, 4, 1, file) != 1) {
    printf("Error: Cannot read key\n");
    fclose(file);
    return 0;
  }

  // Read version (1 byte)
  uint8_t version;
  if (fread(&version, 1, 1, file) != 1) {
    printf("Error: Cannot read version\n");
    fclose(file);
    return 0;
  }

  // Read size (4 bytes)
  uint32_t size;
  if (fread(&size, 4, 1, file) != 1) {
    printf("Error: Cannot read size\n");
    fclose(file);
    return 0;
  }

  printf("Key: %08X, Version: %d, Size: %d bytes\n", key, version, size);

  // Read entry point from end of file
  long current_pos = ftell(file);
  fseek(file, -5, SEEK_END);  // Entry point is 4 bytes before the final 'O'
  uint32_t entry_point;
  if (fread(&entry_point, 4, 1, file) == 1) {
    printf("Entry point: $%04X (%d)\n", entry_point, entry_point);
  }
  fseek(file, current_pos, SEEK_SET);  // Restore position

  // 2. Parse import section - build mno -> module name mapping
  // mno 1 = first imported module (SYSTEM imports are skipped by compiler)
  #define MAX_IMPORTS 16
  ModuleInfo *import_map[MAX_IMPORTS];
  char import_names[MAX_IMPORTS][64];
  int import_count = 0;
  memset(import_map, 0, sizeof(import_map));

  while (1) {
    char ch;
    if (fread(&ch, 1, 1, file) != 1) break;
    if (ch == 0) break; // End of imports

    // Read module name
    char imp_name[64];
    int ni = 0;
    imp_name[ni++] = ch;
    while (1) {
      if (fread(&ch, 1, 1, file) != 1) break;
      if (ch == 0) break;
      if (ni < 63) imp_name[ni++] = ch;
    }
    imp_name[ni] = 0;

    // Skip module key (4 bytes)
    fseek(file, 4, SEEK_CUR);

    import_count++;
    if (import_count < MAX_IMPORTS) {
      strcpy(import_names[import_count], imp_name);
      import_map[import_count] = find_module_by_name(imp_name);

      // Auto-load missing dependency
      if (!import_map[import_count]) {
        char dep_path[256];
        if (construct_module_path(search_dir, imp_name, dep_path, sizeof(dep_path))) {
          FILE *dep_test = fopen(dep_path, "rb");
          if (dep_test) {
            fclose(dep_test);
            printf("  Auto-loading dependency: %s\n", dep_path);
            unsigned int dep_entry = loadMod(dep_path);
            if (dep_entry != 0 && mod_count < 64) {
              mod_entries[mod_count++] = dep_entry;
            }
            import_map[import_count] = find_module_by_name(imp_name);
          } else {
            printf("  Error: Module '%s' not found (looked for %s)\n", imp_name, dep_path);
          }
        }
      }

      if (import_map[import_count]) {
        printf("  Import mno %d: %s -> loaded at $%04X\n",
               import_count, imp_name, import_map[import_count]->base_address);
      } else {
        printf("  Import mno %d: %s -> NOT FOUND\n", import_count, imp_name);
      }
    }
  }

  // Set base addresses now, after auto-loading may have advanced them
  module_base = current_load_address;
  module_var_base = current_var_address;

  printf("Loading module at base address $%04X (bank %d)\n", module_base, current_module_bank);

  // 3. Read type descriptors into module var area
  uint32_t td_size;
  if (fread(&td_size, 4, 1, file) != 1) {
    printf("Error: Cannot read type descriptor size\n");
    fclose(file);
    return 0;
  }
  if (td_size > 0) {
    uint8_t *td_data = (uint8_t*)malloc(td_size);
    if (fread(td_data, 1, td_size, file) != td_size) {
      printf("Error: Cannot read type descriptor data\n");
      free(td_data);
      fclose(file);
      return 0;
    }
    for (uint32_t i = 0; i < td_size; i++) {
      emu816::setByte(module_var_base + i, td_data[i]);
    }
    free(td_data);
    printf("Type descriptors: %d bytes loaded at $%04X\n", td_size, module_var_base);
  }

  // 4. Read variable section size
  uint32_t var_size;
  if (fread(&var_size, 4, 1, file) != 1) {
    printf("Error: Cannot read variable size\n");
    fclose(file);
    return 0;
  }

  // 5. Read string section
  uint32_t str_size;
  if (fread(&str_size, 4, 1, file) != 1) {
    printf("Error: Cannot read string size\n");
    fclose(file);
    return 0;
  }

  uint8_t *string_data = (uint8_t*)malloc(str_size > 0 ? str_size : 1);
  printf("String length: %d bytes\n", str_size);

  if (str_size > 0) {
    if (fread(string_data, 1, str_size, file) != str_size) {
      printf("Error: Cannot read string section\n");
      free(string_data);
      fclose(file);
      return 0;
    }

    for (count = 0; count < str_size; count++) {
      emu816::setByte(module_var_base + td_size + var_size + count, string_data[count]);
    }
  }
  free(string_data);

  // 6. Read code section
  uint32_t code_length;
  if (fread(&code_length, 4, 1, file) != 1) {
    printf("Error: Cannot read code length\n");
    fclose(file);
    return 0;
  }
  uint8_t *code_data = (uint8_t*)malloc(code_length);
  printf("Code length: %d bytes\n", code_length);

  if (fread(code_data, 1, code_length, file) != code_length) {
    printf("Error: Cannot read code section\n");
    free(code_data);
    fclose(file);
    return 0;
  }

  // Load code into bank memory space
  uint32_t bank_address = MODULE_BANK * BANK_SIZE;
  printf("Loading code at bank %d:$%04X (absolute $%06X)\n",
         MODULE_BANK, module_base, bank_address + module_base);

  for (count = 0; count < code_length; count++) {
    emu816::setByte(bank_address + module_base + count, code_data[count]);
  }
  free(code_data);

  // 7. Read export procedures section (name + address pairs)
  printf("Exports:\n");
  while (1) {
    char ch;
    if (fread(&ch, 1, 1, file) != 1) break;
    if (ch == 0) break; // End of export procedures

    // Read procedure name
    char exp_name[64];
    int ni = 0;
    exp_name[ni++] = ch;
    while (1) {
      if (fread(&ch, 1, 1, file) != 1) break;
      if (ch == 0) break;
      if (ni < 63) exp_name[ni++] = ch;
    }
    exp_name[ni] = 0;

    // Read procedure value (4 bytes)
    uint32_t exp_val;
    fread(&exp_val, 4, 1, file);
    printf("  %s = $%04X\n", exp_name, exp_val);
  }

  // 8. Read nofent and entry point
  uint32_t nofent;
  uint32_t file_entry;
  if (fread(&nofent, 4, 1, file) != 1 || fread(&file_entry, 4, 1, file) != 1) {
    printf("Error: Cannot read nofent/entry\n");
    fclose(file);
    return 0;
  }
  printf("nofent: %d, entry: $%04X\n", nofent, file_entry);

  // 9. Read export values section - indexed by exno (1-based)
  // These are the code offsets for exported procedures/variables
  uint32_t export_values[MAX_EXPORTS];
  int export_idx = 1; // exno starts at 1
  memset(export_values, 0, sizeof(export_values));

  while (1) {
    uint32_t word;
    if (fread(&word, 4, 1, file) != 1) break;
    if (word == 0xFFFFFFFF) break; // Found -1 fixup marker
    if (export_idx < MAX_EXPORTS) {
      export_values[export_idx] = word;
      printf("  export[%d] = $%04X\n", export_idx, word);
      export_idx++;
    }
  }

  // 10. Read fixup information (fixorgP, fixorgD, fixorgT)
  int32_t fixorgP, fixorgD, fixorgT;
  if (fread(&fixorgP, 4, 1, file) != 1 ||
      fread(&fixorgD, 4, 1, file) != 1 ||
      fread(&fixorgT, 4, 1, file) != 1) {
    printf("Error reading fixup information\n");
    fclose(file);
    return 0;
  }

  // 10b. Read and process TD fixup entries (ancestor addresses needing relocation)
  int32_t td_fixup_count;
  if (fread(&td_fixup_count, 4, 1, file) != 1) {
    printf("Error reading TD fixup count\n");
    fclose(file);
    return 0;
  }
  if (td_fixup_count > 0) {
    printf("Processing %d TD fixups:\n", td_fixup_count);
    for (int i = 0; i < td_fixup_count; i++) {
      uint16_t byte_offset, mno;
      if (fread(&byte_offset, 2, 1, file) != 1 || fread(&mno, 2, 1, file) != 1) {
        printf("Error reading TD fixup entry %d\n", i);
        break;
      }
      // Read 4-byte ancestor value (lo + hi) from TD area
      uint16_t lo = emu816::getWord(module_var_base + byte_offset);
      uint16_t hi = emu816::getWord(module_var_base + byte_offset + 2);
      uint32_t addr = ((uint32_t)hi << 16) | lo;
      // Add the module's var base for the target module
      uint16_t var_base;
      if (mno == 0) {
        var_base = module_var_base;  // own module
      } else if (mno <= import_count && import_map[mno]) {
        var_base = import_map[mno]->var_address;
      } else {
        var_base = 0;
        printf("  Warning: TD fixup mno %d not resolved\n", mno);
      }
      addr += var_base;
      emu816::setWord(module_var_base + byte_offset, addr & 0xFFFF);
      emu816::setWord(module_var_base + byte_offset + 2, (addr >> 16) & 0xFFFF);
      printf("  TD fixup[%d]: offset=%d mno=%d -> $%04X\n", i, byte_offset, mno, (unsigned)(addr & 0xFFFF));
    }
  }

  // Add module to tracking list BEFORE relocations (so it's findable)
  ModuleInfo *info = (ModuleInfo*)malloc(sizeof(ModuleInfo));
  strcpy(info->name, module_name);
  info->bank = current_module_bank;
  info->base_address = module_base;
  info->var_address = module_var_base;
  info->size = code_length;
  info->entry_point = entry_point + module_base;
  info->export_count = export_idx;
  memcpy(info->exports, export_values, sizeof(export_values));
  info->next = loaded_modules;
  loaded_modules = info;

  // Populate module table entry
  int module_index = current_module_index++;
  emu816::setByte(MODULE_TABLE_BASE + module_index * 2, module_var_base & 0xFF);
  emu816::setByte(MODULE_TABLE_BASE + module_index * 2 + 1, (module_var_base >> 8) & 0xFF);

  printf("Module %s loaded: Bank %d, Code $%04X-$%04X, Vars $%04X, Entry $%04X, MT[%d]=$%04X\n",
         module_name, info->bank, module_base, module_base + code_length - 1,
         module_var_base, info->entry_point, module_index, module_var_base);

  // 11. Read and process relocation table
  int32_t reloc_count;
  if (fread(&reloc_count, 4, 1, file) == 1) {
    if (reloc_count >= 0 && reloc_count < 1024) {
      printf("Processing %d relocations:\n", reloc_count);

      for (int i = 0; i < reloc_count; i++) {
        int32_t reloc_addr;
        if (fread(&reloc_addr, 4, 1, file) == 1) {
          uint32_t bank_reloc_addr = bank_address + module_base + reloc_addr;
          apply_relocation(bank_reloc_addr, module_base, module_var_base, import_map, import_count);
        }
      }
      if (reloc_count > 0) printf("\n");

      info->relocation_count = reloc_count;

      // Update load addresses for next module
      current_load_address += code_length;
      current_var_address += td_size + var_size + str_size;

    } else {
      printf("Invalid relocation count: %d\n", reloc_count);
    }
  }

  fclose(file);

  // Return full 24-bit entry point address (bank:address)
  uint32_t full_entry = (MODULE_BANK << 16) | (module_base + entry_point);
  printf("Entry point: Bank %d:$%04X (24-bit: $%06X)\n",
         MODULE_BANK, module_base + entry_point, full_entry);
  printf("Module loaded successfully\n\n");
  return full_entry;
}

//==============================================================================
// Heap Allocator
//------------------------------------------------------------------------------

static uint32_t heap_top = 0;
static uint8_t  heap_bank = 0;
static uint32_t heap_limit = 0xBFFF;

static uint16_t heap_alloc(uint16_t size) {
    // Align to 2 bytes
    size = (size + 1) & ~1;
    if (heap_top + size > heap_limit) {
        printf("OUT OF MEMORY\n");
        return 0;
    }
    uint16_t addr = heap_top;
    heap_top += size;
    // Zero-fill allocated block
    for (int i = 0; i < size; i++)
        emu816::setByte((heap_bank << 16) | (addr + i), 0);
    return addr;
}

static void trap_handler(int trap_num) {
    if (trap_num == 0) {
        // Module return halt - silent stop
        emu816::stop();
    } else if (trap_num == 10) {
        // NEW: allocate heap memory
        uint16_t size = emu816::getRegA();
        uint16_t addr = heap_alloc(size);
        emu816::setRegA(addr);
        emu816::setRegX(heap_bank);
    } else {
        // Runtime error traps 1-9
        printf("TRAP %d at %02X:%04X\n", trap_num, emu816::getPBR(), emu816::getPC() - 2);
        // Stop execution
        emu816::stop();
    }
}

//==============================================================================
// Command Handler
//------------------------------------------------------------------------------

int main(int argc, char **argv)
{
  int index = 1;
  unsigned int entry;
  int custom_dp = -1;    // -1 = use default (0), else custom DP address
  int custom_sp = -1;    // -1 = use default ($0100), else custom SP address

  setup();

  while (index < argc) {
    if (argv[index][0] != '-') break;

    if (!strcmp(argv[index], "-t")) {
      trace = true;
      ++index;
      continue;
    }

    if (!strcmp(argv[index], "-dp") && index + 1 < argc) {
      custom_dp = (int)strtol(argv[index + 1], NULL, 0);
      index += 2;
      continue;
    }

    if (!strcmp(argv[index], "-sp") && index + 1 < argc) {
      custom_sp = (int)strtol(argv[index + 1], NULL, 0);
      index += 2;
      continue;
    }

    if (!strcmp(argv[index], "-?")) {
      cerr << "Usage: em16 [-t] [-dp addr] [-sp addr] ELF-file ..." << endl;
      return (1);
    }

    cerr << "Invalid: option '" << argv[index] << "'" << endl;
    return (1);
  }
  
  // Reset module tracking (file-scope mod_count and mod_entries)
  mod_count = 0;

  if (index < argc)
    do {
      char *suffix = strrchr(argv[index], '.');
      if (suffix == 0) {
        entry = loadELF(argv[index]);
      } else if (strcmp(suffix, ".816") == 0) {
        entry = loadMod(argv[index]);
        if (mod_count < 64) {
          mod_entries[mod_count++] = entry;
        }
      } else {
        entry = loadELF(argv[index]);
      }
      index++;
    } while (index < argc);
  else {
    cerr << "No ELF files specified" << endl;
    return (1);
  }

  timespec start, end;

#ifdef __APPLE__
  clock_gettime(CLOCK_MONOTONIC, &start);
#else
  clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &start);
#endif

  if (custom_sp >= 0) {
    emu816::setStackPage(custom_sp);
  }

  emu816::reset(trace);

  if (custom_dp >= 0) {
    emu816::setDP(custom_dp);
    printf("DP set to $%04X\n", custom_dp);
  }

  // Initialize heap allocator: starts right after module variables
  heap_top = current_var_address;
  heap_bank = 0;  // heap in bank 0
  printf("Heap initialized at $%04X (bank %d)\n", heap_top, heap_bank);

  // Register trap handler for runtime traps (BRK #1..#10)
  emu816::setTrapHandler(trap_handler);

  if (mod_count > 0) {
    // Run each module's entry point in load order
    // This initializes modules (runs their BEGIN sections)
    for (int i = 0; i < mod_count; i++) {
      if (mod_entries[i] != 0) {
        cout << "Initialising at " << hex << mod_entries[i] << endl;
        emu816::jumpLong(mod_entries[i]);
      }
    }
  } else if (entry != 0) {
    cout << "Initialising at " << hex << entry << endl;
    emu816::jumpLong(entry);
  } else {
    mem816::run();
  }
  
#ifdef __APPLE__
  clock_gettime(CLOCK_MONOTONIC, &end);
#else
  clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &end);
#endif
  
  double secs = (end.tv_sec + end.tv_nsec / 1000000000.0)
    - (start.tv_sec + start.tv_nsec / 1000000000.0);

  double speed = emu816::getCycles() / secs;

  cout << endl << "Executed " << emu816::getCycles() << " in " << secs << " Secs";
  cout << endl << "Overall CPU Frequency = ";
  if (speed < 1000.0) {
    cout << speed << " Hz";
  } else {
    if ((speed /= 1000.0) < 1000.0) {
      cout << speed << " KHz";
    } else {
      cout << (speed /= 1000.0) << " Mhz";
    }
  }
  cout << endl;
  
  return(0);
}

