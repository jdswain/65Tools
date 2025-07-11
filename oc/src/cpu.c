#include "cpu.h"
#include <stdio.h>

// Instruction name lookup table using the same DEF mechanism
static const char* instruction_names[] = {
#define DEF(tok, str, flags) str,
#include "../include/Instr.h"
#undef DEF
};

char *mode_to_string(enum AddrMode mode)
{
 switch( mode ) {
 case Absolute: return "Absolute";
 case Accumulator: return "Accumulator";
 case AbsoluteIndexedX: return "Absolute Indexed X";
 case AbsoluteIndexedY: return "Absolute Indexed Y";
 case AbsoluteLong: return "Absolute Long";
 case AbsoluteLongIndexedX: return "Absolute Long Indexed X";
 case AbsoluteIndirect: return "Absolute Indirect";
 case AbsoluteIndirectLong: return "Absolute Indirect Long";
 case AbsoluteIndexedIndirect: return "Absolute Indexed Indirect";
 case DirectPage: return "Direct Page";
 case StackDirectPageIndirect: return "Stack Direct Page Indirect";
 case DirectPageIndexedX: return "Direct Page Indexed X";
 case DirectPageIndexedY: return "Direct Page Indexed Y";
 case DirectPageIndirect: return "Direct Page Indirect";
 case DirectPageIndirectLong: return "Direct Page Indirect Long";
 case Implied: return "Implied";
 case ProgramCounterRelative: return "Program Counter Relative";
 case ProgramCounterRelativeLong: return "Program Counter Relative Long";
 case BlockMove: return "Block Move";
 case DirectPageIndexedIndirectX: return "Direct Page Indexed Indirect X";
 case DirectPageIndirectIndexedY: return "Direct Page Indirect Indexed Y";
 case DirectPageIndirectLongIndexedY: return "Direct Page Indirect Long Indexed Y";
 case Immediate: return "Immediate";
 case StackRelative: return "Stack Relative";
 case StackRelativeIndirectIndexedY: return "Stack Relative Indirect IndexedY";
 }
 return "Invalid Mode";
}

const char* opcode_to_string(OpCode op) {
    if (op >= 0 && op < sizeof(instruction_names)/sizeof(instruction_names[0])) {
        return instruction_names[op];
    }
    return "UNKNOWN";
}

// 65C816 opcode to instruction mapping
// This maps actual 65C816 machine code bytes to our OpCode enum
OpCode byte_to_opcode(unsigned char byte) {
    switch (byte) {
        // Common 65C816 opcodes used by our compiler
        case 0x18: return sCLC;    // CLC - Clear Carry
        case 0x38: return sSEC;    // SEC - Set Carry
        case 0xFB: return sXCE;    // XCE - Exchange Carry and Emulation
        case 0xC2: return sREP;    // REP - Reset Status Bits
        case 0xE2: return sSEP;    // SEP - Set Status Bits
        
        // LDA variants
        case 0xA9: return sLDA;    // LDA Immediate
        case 0xA5: return sLDA;    // LDA Direct Page
        case 0xAD: return sLDA;    // LDA Absolute
        case 0xB5: return sLDA;    // LDA Direct Page,X
        case 0xBD: return sLDA;    // LDA Absolute,X
        case 0xB9: return sLDA;    // LDA Absolute,Y
        
        // STA variants
        case 0x85: return sSTA;    // STA Direct Page
        case 0x8D: return sSTA;    // STA Absolute
        case 0x95: return sSTA;    // STA Direct Page,X
        case 0x9D: return sSTA;    // STA Absolute,X
        case 0x99: return sSTA;    // STA Absolute,Y
        
        // ADC variants
        case 0x69: return sADC;    // ADC Immediate
        case 0x65: return sADC;    // ADC Direct Page
        case 0x6D: return sADC;    // ADC Absolute
        case 0x75: return sADC;    // ADC Direct Page,X
        case 0x7D: return sADC;    // ADC Absolute,X
        case 0x79: return sADC;    // ADC Absolute,Y
        
        // SBC variants
        case 0xE9: return sSBC;    // SBC Immediate
        case 0xE5: return sSBC;    // SBC Direct Page
        case 0xED: return sSBC;    // SBC Absolute
        case 0xF5: return sSBC;    // SBC Direct Page,X
        case 0xFD: return sSBC;    // SBC Absolute,X
        case 0xF9: return sSBC;    // SBC Absolute,Y
        
        // Other common instructions
        case 0x20: return sJSR;    // JSR Absolute
        case 0xEA: return sNOP;    // NOP
        case 0x00: return sBRK;    // BRK
        case 0x40: return sRTI;    // RTI
        case 0x60: return sRTS;    // RTS
        case 0x6B: return sRTL;    // RTL
        
        // Stack operations
        case 0x3B: return sTSC;    // TSC - Transfer Stack Pointer to A
        case 0x1B: return sTCS;    // TCS - Transfer A to Stack Pointer
        
        // Stack relative addressing
        case 0xA3: return sLDA;    // LDA sr,S (Stack Relative)
        case 0x83: return sSTA;    // STA sr,S (Stack Relative)
        
        default: return sNOP;      // Unknown opcode, treat as NOP for safety
    }
}

