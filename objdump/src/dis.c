#include <stdio.h>
#include "elf.h"

ELF_Word addr;

const char **names;
char *modes;

const char *sADC = "ADC";
const char *sAND = "AND";
const char *sASL = "ASL";
const char *sBCC = "BCC";
const char *sBCS = "BCS";
const char *sBEQ = "BEQ";
const char *sBIT = "BIT";
const char *sBMI = "BMI";
const char *sBNE = "BNE";
const char *sBPL = "BPL";
const char *sBRA = "BRA";
const char *sBRK = "BRK";
const char *sBRL = "BRL";
const char *sBVC = "BVC";
const char *sBVS = "BVS";
const char *sCLC = "CLC";
const char *sCLD = "CLD";
const char *sCLI = "CLI";
const char *sCLV = "CLV";
const char *sCMP = "CMP";
const char *sCOP = "COP";
const char *sCPX = "CPX";
const char *sCPY = "CPY";
const char *sDEC = "DEC";
const char *sDEX = "DEX";
const char *sDEY = "DEY";
const char *sEOR = "EOR";
const char *sINC = "INC";
const char *sINX = "INX";
const char *sINY = "INY";
const char *sJML = "JML";
const char *sJMP = "JMP";
const char *sJSL = "JSL";
const char *sJSR = "JSR";
const char *sLDA = "LDA";
const char *sLDX = "LDX";
const char *sLDY = "LDY";
const char *sLSR = "LSR";
const char *sMVN = "MVN";
const char *sMVP = "MVP";
const char *sNOP = "NOP";
const char *sORA = "ORA";
const char *sPEA = "PEA";
const char *sPEI = "PEI";
const char *sPER = "PER";
const char *sPHA = "PHA";
const char *sPHB = "PHB";
const char *sPHD = "PHD";
const char *sPHK = "PHK";
const char *sPHP = "PHP";
const char *sPHX = "PHX";
const char *sPHY = "PHY";
const char *sPLA = "PLA";
const char *sPLB = "PLB";
const char *sPLD = "PLD";
const char *sPLP = "PLP";
const char *sPLX = "PLX";
const char *sPLY = "PLY";
const char *sREP = "REP";
const char *sROL = "ROL";
const char *sROR = "ROR";
const char *sRTI = "RTI";
const char *sRTL = "RTL";
const char *sRTS = "RTS";
const char *sSBC = "SBC";
const char *sSEC = "SEC";
const char *sSED = "SED";
const char *sSEI = "SEI";
const char *sSEP = "SEP";
const char *sSTA = "STA";
const char *sSTP = "STP";
const char *sSTX = "STX";
const char *sSTY = "STY";
const char *sSTZ = "STZ";
const char *sTAX = "TAX";
const char *sTAY = "TAY";
const char *sTCD = "TCD";
const char *sTCS = "TCS";
const char *sTDC = "TDC";
const char *sTRB = "TRB";
const char *sTSB = "TSB";
const char *sTSC = "TSC";
const char *sTSX = "TSX";
const char *sTSY = "TSY";
const char *sTXA = "TXA";
const char *sTXS = "TXS";
const char *sTXY = "TXY";
const char *sTYA = "TYA";
const char *sTYX = "TYX";
const char *sWAI = "WAI";
const char *sWDM = "WDM";
const char *sXBA = "XBA";
const char *sXCE = "XCE";

const char *sUNK = "???";

const char ab = 1; /* Absolute LDA $0000 */
const char aix = 2; /* Absolute Indexed X LDA $0000,x */
const char aiy = 3; /* Absolute Indexed Y LDA $0000,y */
const char aii = 4;
const char ai = 5;
const char ail = 6;
const char al = 7; /* Absolute Long LDA $000000 */
const char alix = 8; 
const char ac = 9; /* Accumulator ASL */
const char bm = 10; /* Block Move MVN #$00, #$00 */
const char dp = 11; /* Direct Page TSB $00 */
const char dpix = 12; /* Direct Page Indexed X LDA $00,X */
const char dpiy = 13; /* Direct Page Indexed Y LDA $00,Y */
const char dpiix = 14; /* Direct Page Indexed Indirect, X ORA ($00,X) */
const char dpi = 15; /* Direct Page Indirect ORA ($00) */
const char dpil = 16; /* Direct Page Indirect Long ORA $00 */
const char dpiiy = 17; /* Direct Page Indexed Indirect, Y ORA ($00),Y */
const char dpiliy = 18; /* Direct Page Indirect Long Indexed Y LDA [$00],Y */
const char im = 19; /* Immediate LDA #$0000 */
const char imp = 20; /* Implied */
const char pcr = 21; /* Program Counter Relative BPL $00 */
const char pcrl = 22;
const char sa = 23; 
const char sdpi = 24; 
const char si = 25; /* Stack Immediate BRK #00 */
const char s = 26; /* Stack PHA */
const char spcr = 27; 
const char sr = 28; /* Stack Relative ORA #$00,s */
const char sriiy = 29; /* Stack Relative Indirect Indexed, Y LDA ($00,s),Y */


//static  char ab = 8; /* Absolute LDA $0000 */
void pr_ab( char *label, short p1, short p2, short p3)
{
  printf("%04x: %02x %02x %02x     %s %s $%04x\n", addr, p1, p2, p3, label, names[p1], p2 | p3 << 8);
}

//static  char aix = 17; /* Absolute Indexed X LDA $0000,x */
void pr_aix( char *label, short p1, short p2, short p3)
{
  printf("%04x: %02x %02x %02x     %s  %s $%04x,X\n", addr, p1, p2, p3, label, names[p1], p2 | p3 << 8);
}

//static  char aiy = 16; /* Absolute Indexed Y LDA $0000,y */
void pr_aiy( char *label, short p1, short p2, short p3)
{
  printf("%04x: %02x %02x %02x     %s %s $%04x,Y\n", addr, p1, p2, p3, label, names[p1], p2 | p3 << 8);
}

//static  char aii = 17;
void pr_aii( char *label, short p1, short p2, short p3)
{
  printf("%04x: %02x %02x %02x     %s %s ($%04x,X)\n", addr, p1, p2, p3, label, names[p1], p2 | p3 << 8);
}

//static  char ai = 16;
void pr_ai( char *label, short p1, short p2, short p3)
{
  printf("%04x: %02x %02x %02x     %s %s ($%04x)\n", addr, p1, p2, p3, label, names[p1], p2 | p3 << 8);
}

void pr_ail( char *label, short p1, short p2, short p3)
{
  printf("%04x: %02x %02x %02x     %s %s [$%06x]\n", addr, p1, p2, p3, label, names[p1], p2 | p3 << 8);
}

//static  char al = 9; /* Absolute Long LDA $000000 */
void pr_al( char *label, short p1, short p2, short p3, short p4)
{
  printf("%04x: %02x %02x %02x %02x  %s %s [$%06x]\n", addr, p1, p2, p3, p4, label, names[p1], p2 | p3 << 8 | p4 << 16);
}

//static  char alix = 21; 
void pr_alix( char *label, short p1, short p2, short p3, short p4)
{
  printf("%04x: %02x %02x %02x %02x  %s %s $%06x,X\n", addr, p1, p2, p3, p4, label, names[p1], p2 | p3 << 8 | p4 << 16);
}

//static  char ac = 7; /* Accumulator ASL */
void pr_ac( char *label, short p1)
{
  printf("%04x: %02x          %s %s\n", addr, p1, label, names[p1]);
}

//static  char bm = 18; /* Block Move MVN #$00, #$00 */
void pr_bm( char *label, short p1, short p2, short p3)
{
  printf("%04x: %02x %02x %02x     %s %s #$%02x,#$%02x\n", addr, p1, p2, p3, label, names[p1], p2, p3);
}

void pr_dp( char *label, short p1, short p2)
{
  printf("%04x: %02x %02x        %s %s $%02x\n", addr, p1, p2, label, names[p1], p2);
}

//static  char dpix = 14; /* Direct Page Indexed X LDA $00,X */
void pr_dpix( char *label, short p1, short p2)
{
  printf("%04x: %02x %02x        %s %s $%02x,X\n", addr, p1, p2, label, names[p1], p2);
}

//static  char dpiy = 20; /* Direct Page Indexed Y LDA $00,Y */
void pr_dpiy( char *label, short p1, short p2)
{
  printf("%04x: %02x %02x        %s %s $%02x,Y\n", addr, p1, p2, label, names[p1], p2);
}

void pr_dpiix( char *label, short p1, short p2)
{
  printf("%04x: %02x %02x        %s %s ($%02x,X)\n", addr, p1, p2, label, names[p1], p2);
}

//static  char dpi = 12; /* Direct Page Indirect ORA ($00) */
void pr_dpi( char *label, short p1, short p2)
{
  printf("%04x: %02x %02x        %s %s ($%02x)\n", addr, p1, p2, label, names[p1], p2);
}

//static  char dpil = 4; /* Direct Page Indirect Long ORA $00 */
void pr_dpil( char *label, short p1, short p2)
{
  printf("%04x: %02x %02x        %s %s $%02x\n", addr, p1, p2, label, names[p1], p2);
}

//static  char dpiiy = 11; /* Direct Page Indexed Indirect, Y ORA ($00),Y */
void pr_dpiiy( char *label, short p1, short p2)
{
  printf("%04x: %02x %02x        %s %s ($%02x),Y\n", addr, p1, p2, label, names[p1], p2);
}

//static  char dpiliy = 15; /* Direct Page Indirect Long Indexed Y LDA [$00],Y */
void pr_dpiliy( char *label, short p1, short p2)
{
  printf("%04x: %02x %02x        %s %s [$%02x],Y\n", addr, p1, p2, label, names[p1], p2);
}

//static  char im = 19; /* Immediate LDA #$0000 */
void pr_im( char *label, short p1, short p2, short p3)
{
  printf("%04x: %02x %02x %02x     %s %s $%04x\n", addr, p1, p2, p3, label, names[p1], p2 | p3 << 8);
}

//static  char i = 6; /* Implied */
void pr_imp( char *label, short p1)
{
  printf("%04x: %02x           %s %s\n", addr, p1, label, names[p1]);
}

//static  char pcr = 10; /* Program Counter Relative BPL $00 */
void pr_pcr( char *label, short p1, short p2)
{
  short abs = addr + (short)(char)p2; /* sign extend */
  printf("%04x: %02x %02x        %s %s $%04x\n", addr, p1, p2, label, names[p1], abs);
}

//static  char pcrl = 18;
void pr_pcrl( char *label, short p1, short p2, short p3)
{
  int abs = addr + (int)(short)(p2 | p2 << 8); /* sign extend */
  printf("%04x: %02x %02x %02x     %s %s $%06x\n", addr, p1, p2, p3, label, names[p1], abs);
}

/* Stack Absolute */
void pr_sa( char *label, short p1, short p2, short p3)
{
  printf("%04x: %02x %02x %02x     %s %s #%04x\n", addr, p1, p2, p3, label, names[p1], p2 | p3 << 8);
}

/* Stack Direct Page Indirect */
void pr_sdpi( char *label, short p1, short p2)
{
  printf("%04x: %02x %02x        %s %s $%04x\n", addr, p1, p2, label, names[p1], p2);
}

void pr_si( char *label, short p1, short p2)
{
  printf("%04x: %02x %02x        %s %s #$%02x\n", addr, p1, p2, label, names[p1], p2);
}

/* Stack Program Counter Relative */
void pr_spcr( char *label, short p1, short p2)
{
  printf("%04x: %02x %02x        %s %s #$%02x,s\n", addr, p1, p2, label, names[p1], p2);
}

//static  char s = 5; /* Stack PHA */
void pr_s( char *label, short p1)
{
  printf("%04x: %02x           %s %s\n", addr, p1, label, names[p1]);
}

void pr_sr( char *label, short p1, short p2)
{
  printf("%04x: %02x %02x        %s %s #$%02x,S\n", addr, p1, p2, label, names[p1], p2);
}

//static  char sriiy = 13; /* Stack Relative Indirect Indexed, Y LDA ($00,s),Y */
void pr_sriiy( char *label, short p1, short p2)
{
  printf("%04x: %02x %02x        %s %s (#$%02x,S),Y\n", addr, p1, p2, label, names[p1], p2);
}

void dis_instrs(unsigned char *buf, int len)
{
  char *label = "";
  int i = 0;
  int b;
  while (i < len) {
    switch(modes[buf[i]]) {
    case ab:     pr_ab(label, buf[i], buf[i+1], buf[i+2]); b = 3; break;
    case aix:    pr_aix(label, buf[i], buf[i+1], buf[i+2]); b = 3; break;
    case aiy:    pr_aix(label, buf[i], buf[i+1], buf[i+2]); b = 3; break;
    case aii:    pr_aix(label, buf[i], buf[i+1], buf[i+2]); b = 3; break;
    case ai:     pr_aii(label, buf[i], buf[i+1], buf[i+2]); b = 3; break;
    case ail:    pr_ail(label, buf[i], buf[i+1], buf[i+2]); b = 3; break;
    case al:     pr_al(label, buf[i], buf[i+1], buf[i+2], buf[i+3]); b = 4; break;
    case alix:   pr_alix(label, buf[i], buf[i+1], buf[i+2], buf[i+3]); b = 4; break;
    case ac:     pr_ac(label, buf[i]); b = 1; break;
    case bm:     pr_bm(label, buf[i], buf[i+1], buf[i+2]); b = 3; break;
    case dp:     pr_dp(label, buf[i], buf[i+1]); b = 2; break;
    case dpix:   pr_dpix(label, buf[i], buf[i+1]); b = 2; break;
    case dpiy:   pr_dpix(label, buf[i], buf[i+1]); b = 2; break;
    case dpiix:  pr_dpiix(label, buf[i], buf[i+1]); b = 2; break;
    case dpi:    pr_dpi(label, buf[i], buf[i+1]); b = 2; break;
    case dpil:   pr_dpil(label, buf[i], buf[i+1]); b = 2; break;
    case dpiiy:  pr_dpiiy(label, buf[i], buf[i+1]); b = 2; break;
    case dpiliy: pr_dpiliy(label, buf[i], buf[i+1]); b = 2; break;
    case im:     pr_im(label, buf[i], buf[i+1], buf[i+2]); b = 3; break;
    case imp:    pr_imp(label, buf[i]); b = 1; break;
    case pcr:    pr_pcr(label, buf[i], buf[i+1]); b = 2; break;
    case pcrl:   pr_pcrl(label, buf[i], buf[i+1], buf[i+2]); b = 3; break;
    case sa:     pr_sa(label, buf[i], buf[i+1], buf[i+2]); b = 3; break;
    case sdpi:   pr_sdpi(label, buf[i], buf[i+1]); b = 2; break;
    case si:     pr_si(label, buf[i], buf[i+1]); b = 2; break;
    case s:      pr_s(label, buf[i]); b = 1; break;
    case spcr:   pr_spcr(label, buf[i], buf[i+1]); b = 2; break;
    case sr:     pr_sr(label, buf[i], buf[i+1]); b = 2; break;
    case sriiy:  pr_sriiy(label, buf[i], buf[i+1]); b = 2; break;
    default:     printf("Unknown addressing mode %d\n", modes[buf[i]]); b = 0;
    }
    i += b;
    addr += b;
  }
}

void dis_instrs(FILE *f)
{
  char *label = "";
  char b = fgetc(f);
  while (!feof(f)) {
    switch(modes[buf[i]]) {
    case ab:     pr_ab(label, b, buf[i+1], buf[i+2]); b = 3; break;
    case aix:    pr_aix(label, buf[i], buf[i+1], buf[i+2]); b = 3; break;
    case aiy:    pr_aix(label, buf[i], buf[i+1], buf[i+2]); b = 3; break;
    case aii:    pr_aix(label, buf[i], buf[i+1], buf[i+2]); b = 3; break;
    case ai:     pr_aii(label, buf[i], buf[i+1], buf[i+2]); b = 3; break;
    case ail:    pr_ail(label, buf[i], buf[i+1], buf[i+2]); b = 3; break;
    case al:     pr_al(label, buf[i], buf[i+1], buf[i+2], buf[i+3]); b = 4; break;
    case alix:   pr_alix(label, buf[i], buf[i+1], buf[i+2], buf[i+3]); b = 4; break;
    case ac:     pr_ac(label, buf[i]); b = 1; break;
    case bm:     pr_bm(label, buf[i], buf[i+1], buf[i+2]); b = 3; break;
    case dp:     pr_dp(label, buf[i], buf[i+1]); b = 2; break;
    case dpix:   pr_dpix(label, buf[i], buf[i+1]); b = 2; break;
    case dpiy:   pr_dpix(label, buf[i], buf[i+1]); b = 2; break;
    case dpiix:  pr_dpiix(label, buf[i], buf[i+1]); b = 2; break;
    case dpi:    pr_dpi(label, buf[i], buf[i+1]); b = 2; break;
    case dpil:   pr_dpil(label, buf[i], buf[i+1]); b = 2; break;
    case dpiiy:  pr_dpiiy(label, buf[i], buf[i+1]); b = 2; break;
    case dpiliy: pr_dpiliy(label, buf[i], buf[i+1]); b = 2; break;
    case im:     pr_im(label, buf[i], buf[i+1], buf[i+2]); b = 3; break;
    case imp:    pr_imp(label, buf[i]); b = 1; break;
    case pcr:    pr_pcr(label, buf[i], buf[i+1]); b = 2; break;
    case pcrl:   pr_pcrl(label, buf[i], buf[i+1], buf[i+2]); b = 3; break;
    case sa:     pr_sa(label, buf[i], buf[i+1], buf[i+2]); b = 3; break;
    case sdpi:   pr_sdpi(label, buf[i], buf[i+1]); b = 2; break;
    case si:     pr_si(label, buf[i], buf[i+1]); b = 2; break;
    case s:      pr_s(label, buf[i]); b = 1; break;
    case spcr:   pr_spcr(label, buf[i], buf[i+1]); b = 2; break;
    case sr:     pr_sr(label, buf[i], buf[i+1]); b = 2; break;
    case sriiy:  pr_sriiy(label, buf[i], buf[i+1]); b = 2; break;
    default:     printf("Unknown addressing mode %d\n", modes[buf[i]]); b = 0;
    }
    i += b;
    addr += b;
  }
}

#include "dis_816.c"

void dis(unsigned char *b, int len, int base_addr)
{
  addr = base_addr;
  names = names_816;
  modes = modes_816;
  dis_instrs(b, len);
}

void dis(FILE *f, int base_addr)
{
  addr = base_addr;
  names = names_816;
  modes = modes_816;
  dis_instrs(f);
}
