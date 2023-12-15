#ifndef elf_h
#define elf_h

/*
ELF is the binary file format for executable files and intermediate code files.

Our format is very similar to ELF but has been simplifed slightly.
*/

#include <inttypes.h>

/* Type for a 16-bit quantity.  */
typedef uint16_t ELF_Half;

/* Types for signed and unsigned 32-bit quantities.  */
typedef uint32_t ELF_Word;
typedef int32_t  ELF_Sword;
                                          
/* Type of addresses.  */
typedef uint32_t ELF_Addr;

/* Type of file offsets.  */
typedef uint32_t ELF_Off;

/* Type for section indices, which are 16-bit quantities.  */
typedef uint16_t ELF_Section;

/* Type of symbol indices.  */
typedef uint32_t ELF_Symndx;

/* The ELF file header.  This appears at the start of every ELF file.  */

#define EI_NIDENT (16)

typedef struct {
  unsigned char e_ident[EI_NIDENT];   /* Magic number and other info */
  ELF_Half    e_type;                 /* Object file type */
  ELF_Half    e_machine;              /* Architecture */
  ELF_Word    e_version;              /* Object file version */
  ELF_Addr    e_entry;                /* Entry point virtual address */
  ELF_Off     e_phoff;                /* Program header table file offset */
  ELF_Off     e_shoff;                /* Section header table file offset */
  ELF_Word    e_flags;                /* Processor-specific flags */
  ELF_Half    e_ehsize;               /* ELF header size in bytes */
  ELF_Half    e_phentsize;            /* Program header table entry size */
  ELF_Half    e_phnum;                /* Program header table entry count */
  ELF_Half    e_shentsize;            /* Section header table entry size */
  ELF_Half    e_shnum;                /* Section header table entry count */
  ELF_Half    e_shstrndx;             /* Section header string table index */
} ELF_Ehdr;

/* Fields in the e_ident array.  The EI_* macros are indices into the
   array.  The macros under each EI_* macro are the values the byte
   may have.  */

#define EI_MAG0         0               /* File identification byte 0 index */
#define ELFMAG0         'E'             /* Magic number byte 0 */

#define EI_MAG1         1               /* File identification byte 1 index */
#define ELFMAG1         'L'             /* Magic number byte 1 */

#define EI_MAG2         2               /* File identification byte 2 index */
#define ELFMAG2         '1'             /* Magic number byte 2 */

#define EI_MAG3         3               /* File identification byte 3 index */
#define ELFMAG3         '6'             /* Magic number byte 3 */

/* Conglomeration of the identification bytes, for easy testing as a word.  */
#define ELFMAG          "EL16"
#define SELFMAG         4

#define EI_CLASS        4               /* File class byte index */
#define ELFCLASSNONE    0               /* Invalid class */
#define ELFCLASS32      1               /* 32-bit objects */
#define ELFCLASSNUM     2

#define EI_DATA         5               /* Data encoding byte index */
#define ELFDATANONE     0               /* Invalid data encoding */
#define ELFDATA2LSB     1               /* 2's complement, little endian */
#define ELFDATA2MSB     2               /* 2's complement, big endian */
#define ELFDATANUM      3

#define EI_VERSION      6               /* File version byte index */
                                        /* Value must be EV_CURRENT */

#define EI_OSABI        7               /* OS ABI identification */
#define ELFOSABI_OS16           1       /* OS 16 */
#define ELFOSABI_OS8            2       /* OS 8 */
#define ELFOSABI_STANDALONE     255     /* Standalone (embedded) application */

#define EI_ABIVERSION   1               /* ABI version */

#define EI_PAD          9               /* Byte index of padding bytes */

/* Legal values for e_type (object file type).  */

#define ET_NONE         0               /* No file type */
#define ET_REL          1               /* Relocatable file */
#define ET_EXEC         2               /* Executable file */
#define ET_DYN          3               /* Shared object file */
#define ET_CORE         4               /* Core file */
#define ET_NUM          5               /* Number of defined types */
#define ET_LOPROC       0xff00          /* Processor-specific */
#define ET_HIPROC       0xffff          /* Processor-specific */

/* Legal values for e_machine (architecture).  */

#define EM_NONE          0              /* No machine */
#define EM_816           1              /* 65C816 */
#define EM_C02           2              /* 65C02 */
#define EM_02            3              /* NMOS 6502 */
#define EM_RC02          4              /* Rockwell 65C02 */
#define EM_RC19          5              /* Rockwell C19 */
#define EM_NUM           6

/* Legal values for e_version (version).  */

#define EV_NONE         0               /* Invalid ELF version */
#define EV_CURRENT      1               /* Current version */
#define EV_NUM          2

/* Section header.  */

typedef struct
{
  ELF_Word    sh_name;                /* Section name (string tbl index) */
  ELF_Word    sh_type;                /* Section type */
  ELF_Word    sh_flags;               /* Section flags */
  ELF_Addr    sh_addr;                /* Section virtual addr at execution */
  ELF_Off     sh_offset;              /* Section file offset */
  ELF_Word    sh_size;                /* Section size in bytes */
  ELF_Word    sh_link;                /* Link to another section */
  ELF_Word    sh_info;                /* Additional section information */
  ELF_Word    sh_addralign;           /* Section alignment */
  ELF_Word    sh_entsize;             /* Entry size if section holds table */
} ELF_Shdr;

/* Legal values for sh_type (section type).  */

#define SHT_NULL         0              /* Section header table entry unused */
#define SHT_PROGBITS     1              /* Program data */
#define SHT_SYMTAB       2              /* Symbol table */
#define SHT_STRTAB       3              /* String table */
#define SHT_REL          4              /* Relocation entries */
#define SHT_HASH         5              /* Symbol hash table */
#define SHT_DYNAMIC      6              /* Dynamic linking information */
#define SHT_NOTE         7              /* Notes */
#define SHT_NOBITS       8              /* Program space with no data (bss) */
#define SHT_DYNSYM       11             /* Dynamic linker symbol table */
#define SHT_INIT_ARRAY   14             /* Array of constructors */
#define SHT_FINI_ARRAY   15             /* Array of destructors */
#define SHT_PREINIT_ARRAY 16            /* Array of pre-constructors */
#define SHT_GROUP        17             /* Section group */

/* Legal values for sh_flags (section flags).  */

#define SHF_WRITE       (1 << 0)        /* Writable */
#define SHF_ALLOC       (1 << 1)        /* Occupies memory during execution */
#define SHF_EXECINSTR   (1 << 2)        /* Executable */
#define SHF_DP          (1 << 3)        /* Direct Page */
#define SHF_STACK       (1 << 4)        /* Stack Size */

#define SHF_TLS         0x400

/* Symbol table entry.  */

typedef struct
{
  ELF_Word    st_name;                  /* Symbol name (string tbl index) */
  ELF_Addr    st_value;                 /* Symbol value */
  ELF_Word    st_size;                  /* Symbol size */
  unsigned char st_info;                /* Symbol type and binding */
  unsigned char st_other;               /* No defined meaning, 0 */
  ELF_Section st_shndx;                 /* Section index */
} ELF_Sym;

/* Relocation table entry (in section of type SHT_REL).  */

typedef struct
{
  ELF_Addr    r_offset;                 /* Address */
  ELF_Word    r_info;                   /* Relocation type and symbol index */
} ELF_Rel;

/* Program segment header.  */

typedef struct
{
  ELF_Word    p_type;                 /* Segment type */
  ELF_Off     p_offset;               /* Segment file offset */
  ELF_Addr    p_vaddr;                /* Segment virtual address */
  ELF_Addr    p_paddr;                /* Segment physical address */
  ELF_Word    p_filesz;               /* Segment size in file */
  ELF_Word    p_memsz;                /* Segment size in memory */
  ELF_Word    p_flags;                /* Segment flags */
  ELF_Word    p_align;                /* Segment alignment */
} ELF_Phdr;

/* Legal values for p_type (segment type).  */

#define PT_NULL         0               /* Program header table entry unused */
#define PT_LOAD         1               /* Loadable program segment */
#define PT_DYNAMIC      2               /* Dynamic linking information */
#define PT_INTERP       3               /* Program interpreter */
#define PT_NOTE         4               /* Auxiliary information */
#define PT_SHLIB        5               /* Reserved */
#define PT_PHDR         6               /* Entry for header table itself */
#define PT_TLS          7               /* Thread local storage */
#define PT_NUM          8               /* Number of defined types.  */

/* Legal values for p_flags (segment flags).  */

#define PF_X            (1 << 0)        /* Segment is executable */
#define PF_W            (1 << 1)        /* Segment is writable */
#define PF_R            (1 << 2)        /* Segment is readable */
#define PF_D            (1 << 3)        /* Segment is direct page */
#define PF_S            (1 << 4)        /* Segment is stack */

#endif
