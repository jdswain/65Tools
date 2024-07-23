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

#include "emu816.h"

#include "elf.h"
#include "elf_file.h"
#include "buffered_file.h" // for as_error


//==============================================================================
// Memory Definitions
//------------------------------------------------------------------------------

// Create a 1024kb RAM area - No ROM.
#define	RAM_SIZE	(64 * 1024)
#define MEM_MASK	(64 * 1024L - 1)

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
// Command Handler
//------------------------------------------------------------------------------

int main(int argc, char **argv)
{
  int index = 1;
  unsigned int entry;
  
  setup();

  while (index < argc) {
    if (argv[index][0] != '-') break;
    
    if (!strcmp(argv[index], "-t")) {
      trace = true;
      ++index;
      continue;
    }
    
    if (!strcmp(argv[index], "-?")) {
      cerr << "Usage: em16 [-t] ELF-file ..." << endl;
      return (1);
    }
    
    cerr << "Invalid: option '" << argv[index] << "'" << endl;
    return (1);
  }
  
  if (index < argc)
    do {
      entry = loadELF(argv[index++]);
    } while (index < argc);
  else {
    cerr << "No ELF files specified" << endl;
    return (1);
  }
  
  timespec start, end;

  clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &start);

  emu816::reset(trace);

  if (entry != 0) {
	cout << "Initialising at " << hex << entry << endl;
	emu816::jumpLong(entry);

	wdc816::Addr mainAddr = emu816::symbol("Main");
	if (mainAddr != 0) {
	  cout << "Running Main at " << hex << mainAddr << endl;
	  emu816::jumpLong(mainAddr);
	} else {
	  cerr << "No Main procedure found." << endl;
	}
	while (1) {}
  } else {
	 mem816::run();
  }
  
  clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &end);
  
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

