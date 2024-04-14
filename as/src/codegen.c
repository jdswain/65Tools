#include "codegen.h"

#include "buffered_file.h"
#include "memory.h"

void o(uint8_t byte)
{
  if (!section_is_bss(section)) buf_add_char(&(section->data), &(section->shdr->sh_size), byte);
  addr++;
}

/* Standard formats */

void ob(uint8_t op, int v)
{
  o(op); o(v & 0xff);
}

void odp(uint8_t op, int v)
{
  ob(op, v);
  //  elf_relocation_create(elf_context->reltab, addr + 1, REL_DP | REL_LOCAL);
}

void ow(uint8_t op, int v)
{
  o(op); o(v & 0xff); o(v >> 8);
}

void oabs(uint8_t op, int v)
{
  ow(op, v);
  //  elf_relocation_create(elf_context->reltab, addr + 1, REL_ABS | REL_LOCAL);
}

void ol(uint8_t op, int v)
{
  o(op); o(v & 0xff); o(v >> 8); o(v >> 16);
}

void olong(uint8_t op, int v)
{
  ol(op, v);
  //  elf_relocation_create(elf_context->reltab, addr + 1, REL_LONG | REL_LOCAL);
}

void om(uint8_t op, int v, bool b) { o(op); o(v & 0xff); if( b ) o(v >> 8); }

void or(char *filename, int line_num, uint8_t op, int v) {
  o(op);
  int r = v - (addr + 1);
  if ((pass() == 0) && ((r > 127) || (r < -128)))
	as_gen_error(filename, line_num, "Relative branch out of range, from $%04x to $%04x", addr, v);
  //  printf("r: %04x v: %04x\n", addr, v);
  o(r & 0xff);
}

/* 65C816 formats */

void orl(char *filename, int line_num, uint8_t op, int v) {
  int r = v - (addr + 1);
  if ((pass() == 0) && ((r > 32767) || (r < -32768)))
    as_gen_error(filename, line_num, "Relative branch out of range");
  ow(op, r);
}

void omove(uint8_t op, int src, int dst) { o(op); o(dst >> 16); o(src >> 16); }

/* C19 formats */

void obita(char * filename, int line_num, uint8_t op, int mask, int addr) {
  o(op); o(mask); o(addr &0xff); o(addr >> 8);
}

void obitar(char *filename, int line_num, uint8_t op, int mem, int mask, int v) {
  o(op); o(mem &0xff); o(mem >> 8); o(mask);
  int r = v - (addr + 1);
  if ((pass() == 0) && ((r > 127) || (r < -128)))
    as_gen_error(filename, line_num, "Relative branch out of range");
  o(r & 0xff);
}

void oiz(uint8_t op, int imm, int mem) {
  o(op); o(imm & 0xff); o(mem & 0xff);
}

void obitzr(char *filename, int line_num, uint8_t op, int bit, int mem, int v) {
  o(op | bit << 4); o(mem & 0xff);
  int r = v - (addr + 1);
  if ((pass() == 0) && ((r > 127) || (r < -128)))
    as_gen_error(filename, line_num, "Relative branch out of range: %04x -> %04x = %02x", addr, v, r);
  o(r & 0xff);
}


void codegen_byte(int b) { o(b & 0xff); }
void codegen_word(int w) { o(w & 0xff); o(w >> 8); }
void codegen_long(int l) { o(l & 0xff); o(l >> 8 & 0xff); o(l >> 16 & 0xff); o(l >> 24 & 0xff); }

#include "gen_RC19.c"
#include "gen_RC02.c"
#include "gen_816.c"
#include "gen_C02.c"
#include "gen_02.c"

int codegen_params(Instr *instr)
{
  switch (instr->mode) {
  case Absolute: return 1;
  case Accumulator: return 0;
  case AbsoluteIndexedX: return 1;
  case AbsoluteIndexedY: return 1;
  case AbsoluteLong: return 1;
  case AbsoluteLongIndexedX: return 1;
  case AbsoluteIndirect: return 1;
  case AbsoluteIndirectLong: return 1;
  case AbsoluteIndexedIndirect: return 1;
  case DirectPage: return 1;
  case StackDirectPageIndirect: return 1;
  case DirectPageIndexedX: return 1;
  case DirectPageIndexedY: return 1;
  case DirectPageIndirect: return 1;
  case DirectPageIndirectLong: return 1;
  case Implied: return 0;
  case ProgramCounterRelative: return 1;
  case ProgramCounterRelativeLong: return 1;
  case BlockMove: return 2;
  case DirectPageIndexedIndirectX: return 1;
  case DirectPageIndirectIndexedY: return 1;
  case DirectPageIndirectLongIndexedY: return 1;
  case Immediate: return 1;
  case StackRelative: return 1;
  case StackRelativeIndirectIndexedY: return 1;
  case BitZeroPageRelative: return 3;
  case BitZeroPage: return 2;
  case BitAbsoluteRelative: return 3;
  case BitAbsolute: return 2;
  case ImmediateZeroPage: return 2;
  }
  return 0;
}

bool is_dp(int addr)
{
  return (addr < 0x100) || ((addr - dpage) < 0x100);
}

bool is_long_program(int addr)
{ 
  return (addr > 0xffff) || ((addr - pbreg) < 0x10000);
}

bool is_long_data(int addr)
{
  return (addr > 0xffff); // || ((addr - dbreg) < 0x10000);
}

void codegen_gen(char *filename, int line_num, Instr *instr, int value1, int value2, int value3)
{
  AddrMode mode = instr->mode;
  if (mode == Absolute) {
    if ((instr->modifier == MDirect) || (instr->modifier == MByte)) mode = DirectPage;
    else if (is_dp(value1) && ((instr->modifier != MAbsolute) && (instr->modifier != MWord))) mode = DirectPage;
  }
  else if (mode == AbsoluteIndexedX) {
    if (instr->modifier == MDirect) mode = DirectPageIndexedX;
    else if (is_dp(value1) && ((instr->modifier != MAbsolute) && (instr->modifier != MWord))) mode = DirectPageIndexedX;
	else if ((instr->modifier == MLong) || (value1 > 0xffff)) mode = AbsoluteLongIndexedX;
  }
  else if (mode == AbsoluteIndexedY) {
    if (instr->modifier == MDirect) mode = DirectPageIndexedY;
    else if (is_dp(value1) && ((instr->modifier != MAbsolute) && (instr->modifier != MWord))) mode = DirectPageIndexedY;
  }
  else if (mode == AbsoluteIndexedIndirect) {
    if (instr->modifier == MDirect) mode = DirectPageIndexedIndirectX;
    else if (is_dp(value1) && (instr->modifier != MAbsolute)) mode = DirectPageIndexedIndirectX;
  }
  else if (mode == AbsoluteIndirect) {
    if (instr->modifier == MLong) mode = AbsoluteIndirectLong;
    else if (is_long_data(value1) && (instr->modifier != MAbsolute)) mode = AbsoluteIndirectLong;

    else if ((instr->modifier == MDirect) || (instr->modifier == MByte)) mode = AbsoluteIndirect;
    else if (is_dp(value1) && ((instr->modifier != MAbsolute) && (instr->modifier != MWord))) mode = AbsoluteIndirect;
  }

  switch (elf_context->ehdr->e_machine) {
  case EM_816:   gen_816(filename, line_num, instr, mode, value1, value2); break;
  case EM_C02:   gen_C02(filename, line_num, instr, mode, value1, value2); break;
  case EM_02:    gen_02(filename, line_num, instr, mode, value1, value2); break;
  case EM_RC02:  gen_RC02(filename, line_num, instr, mode, value1, value2, value3); break;
  case EM_RC01:  gen_RC02(filename, line_num, instr, mode, value1, value2, value3); break;
  case EM_RC19:  gen_RC19(filename, line_num, instr, mode, value1, value2, value3); break;
  }
}

char *codegen_format_mode(AddrMode mode, int value1, int value2, int value3)
{
  /* ToDo: modifer for value length is not implemented here, assuming 65C816 native mode */
  char buffer[24];
  switch (mode) {
  case Absolute: sprintf(buffer, "$%04x", value1); break;
  case Accumulator: sprintf(buffer, "A"); break;
  case AbsoluteIndexedX: sprintf(buffer, "$%04x,X", value1); break;
  case AbsoluteIndexedY: sprintf(buffer, "$%04x,Y", value1); break;
  case AbsoluteLong: sprintf(buffer, "$%06x", value1); break;
  case AbsoluteLongIndexedX: sprintf(buffer, "$%06x,X", value1); break;
  case AbsoluteIndirect: sprintf(buffer, "($%04x)", value1); break;
  case AbsoluteIndexedIndirect: sprintf(buffer, "($%04x,X)", value1); break;
  case DirectPage: sprintf(buffer, "$%02x", value1); break;
  case StackDirectPageIndirect: sprintf(buffer, "$%02x,s", value1); break;
  case DirectPageIndexedX: sprintf(buffer, "$%02x,X", value1); break;
  case DirectPageIndexedY: sprintf(buffer, "$%02x,Y", value1); break;
  case DirectPageIndirectLongIndexedY: sprintf(buffer, "[$%02x],Y", value1); break;
  case DirectPageIndirect: sprintf(buffer, "($%02x)", value1); break;
  case DirectPageIndirectLong: sprintf(buffer, "[$%02x]", value1); break;
  case Implied: buffer[0] = 0; break;
  /* Stack, */
  case ProgramCounterRelative: sprintf(buffer, "$%02x", value1); break;
  case ProgramCounterRelativeLong: sprintf(buffer, "$%04x", value1); break;
  case AbsoluteIndirectLong: sprintf(buffer, "[$%04x]", value1); break;
  case BlockMove: sprintf(buffer, "$%02x,$%02x", value1, value2); break;
  case DirectPageIndexedIndirectX: sprintf(buffer, "($%02x,X)", value1); break;
  case DirectPageIndirectIndexedY: sprintf(buffer, "($%02x),Y", value1); break;
  case Immediate: sprintf(buffer, "#$%04x", value1); break;
  case StackRelative: sprintf(buffer, "#$%02x,S", value1); break;
  case StackRelativeIndirectIndexedY: sprintf(buffer, "(#$%02x,S),Y", value1); break;

  /* C19 specific */
  case BitZeroPageRelative: sprintf(buffer, "%01x,$%02x,$%02x", value1, value2, value3); break;
  case BitZeroPage: sprintf(buffer, "%01x,$%02x", value1, value2); break;
  case BitAbsoluteRelative: sprintf(buffer, "%01x,$%04x,$%02x", value1, value2, value3); break;
  case BitAbsolute: sprintf(buffer, "%01x,$%04x", value1, value2); break;
  case ImmediateZeroPage: sprintf(buffer, "#$%02x,#$%02x", value1, value2); break;
  }

  return as_strdup(buffer);
}

char *codegen_format_mode_str(AddrMode mode, char *value1, int value2, int value3)
{
  /* ToDo: modifer for value length is not implemented here, assuming 65C816 native mode */
  char buffer[24];
  switch (mode) {
  case Absolute: sprintf(buffer, "%s", value1); break;
  case Accumulator: sprintf(buffer, "A"); break;
  case AbsoluteIndexedX: sprintf(buffer, "%s,X", value1); break;
  case AbsoluteIndexedY: sprintf(buffer, "%s,Y", value1); break;
  case AbsoluteLong: sprintf(buffer, "%s", value1); break;
  case AbsoluteLongIndexedX: sprintf(buffer, "%s,X", value1); break;
  case AbsoluteIndirect: sprintf(buffer, "(%s)", value1); break;
  case AbsoluteIndexedIndirect: sprintf(buffer, "(%s,X)", value1); break;
  case DirectPage: sprintf(buffer, "%s", value1); break;
  case StackDirectPageIndirect: sprintf(buffer, "%s,s", value1); break;
  case DirectPageIndexedX: sprintf(buffer, "%s,X", value1); break;
  case DirectPageIndexedY: sprintf(buffer, "%s,Y", value1); break;
  case DirectPageIndirectLongIndexedY: sprintf(buffer, "[%s],Y", value1); break;
  case DirectPageIndirect: sprintf(buffer, "(%s)", value1); break;
  case DirectPageIndirectLong: sprintf(buffer, "[%s]", value1); break;
  case Implied: buffer[0] = 0; break;
  /* Stack, */
  case ProgramCounterRelative: sprintf(buffer, "%s", value1); break;
  case ProgramCounterRelativeLong: sprintf(buffer, "%s", value1); break;
  case AbsoluteIndirectLong: sprintf(buffer, "[%s]", value1); break;
  case BlockMove: sprintf(buffer, "%s,$%02x", value1, value2); break;
  case DirectPageIndexedIndirectX: sprintf(buffer, "(%s,X)", value1); break;
  case DirectPageIndirectIndexedY: sprintf(buffer, "(%s),Y", value1); break;
  case Immediate: sprintf(buffer, "#%s", value1); break;
  case StackRelative: sprintf(buffer, "#%s,S", value1); break;
  case StackRelativeIndirectIndexedY: sprintf(buffer, "(#%s,S),Y", value1); break;

  /* C19 specific */
  case BitZeroPageRelative: sprintf(buffer, "%s,$%02x,$%02x", value1, value2, value3); break;
  case BitZeroPage: sprintf(buffer, "%s,$%02x", value1, value2); break;
  case BitAbsoluteRelative: sprintf(buffer, "%s,$%04x,$%02x", value1, value2, value3); break;
  case BitAbsolute: sprintf(buffer, "%s,$%04x", value1, value2); break;
  case ImmediateZeroPage: sprintf(buffer, "#%s,#$%02x", value1, value2); break;
  }

  return as_strdup(buffer);
}
