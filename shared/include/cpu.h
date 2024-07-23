#ifndef CPU_H
#define CPU_H

#include "elf.h"

/* Symbols - for assembler, but needed everwhere */

typedef enum {
#define DEF(tok, str, flags) s ## tok,
#define TOK(tok) s ## tok,
#include "as_tokens.h"
#undef DEF
#undef TOK
} Symbol;

enum AddrMode {
  Absolute,                      /* addr */
  Accumulator,                   /* A */
  AbsoluteIndexedX,              /* addr,X */
  AbsoluteIndexedY,              /* addr,Y */
  AbsoluteLong,                  /* long */
  AbsoluteLongIndexedX,          /* long,X */
  AbsoluteIndirect,              /* (addr) */
  AbsoluteIndexedIndirect,       /* (addr,X) */
  DirectPage,                    /* dp*/
  StackDirectPageIndirect,       /* dp,s */
  DirectPageIndexedX,            /* dp,X */
  DirectPageIndexedY,            /* dp,Y */
  DirectPageIndirect,            /* (dp) */
  DirectPageIndirectLong,        /* [dp] */
  Implied,                       /* */
  /* Stack, */
  ProgramCounterRelative,        /* nearlabel */
  ProgramCounterRelativeLong,    /* label */
  AbsoluteIndirectLong,          /* [addr] */
  BlockMove,                     /* srcbk,destbk */
  DirectPageIndexedIndirectX,    /* (dp,X) */
  DirectPageIndirectIndexedY,    /* (dp),Y */
  DirectPageIndirectLongIndexedY,/* [dp],Y */
  Immediate,                     /* #const */
  //StackProgramCounterRelative,   /* label */
  StackRelative,                 /* sr,S d,s */
  StackRelativeIndirectIndexedY, /* (sr,S),Y */

  /* C19 specific */
  BitZeroPageRelative,           /* b,zp,r BBR/BBS */
  BitZeroPage,                   /* b,zp RMB/SMB */
  BitAbsoluteRelative,           /* b,addr,r BAR/BAS */
  BitAbsolute,                   /* b,addr RBA/SBA */
  ImmediateZeroPage,             /* #const,zp */
};
typedef enum AddrMode AddrMode;

enum Modifier {
  MByte,
  MDirect,
  MAbsolute,
  MWord,
  MLong,
  MFloat,
  MDouble,
  MZero,
  MBit7,
  MNone
};
typedef enum Modifier Modifier;

typedef Symbol OpCode;
struct Instr {
  OpCode opcode;
  AddrMode mode;
  Modifier modifier;
};
typedef struct Instr Instr;

char *token_to_string(Symbol val);
char *mode_to_string(enum AddrMode mode);

#endif
