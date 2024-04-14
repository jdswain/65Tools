#include "cpu.h"

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
 case BitAbsolute: return "Bit Absolute";
 case BitAbsoluteRelative: return "Bit Absolute Relative";
 case BitZeroPage: return "Bit Zero Page";
 case BitZeroPageRelative: return "Bit Zero Page Relative";
 case DirectPage: return "Direct Page";
 case StackDirectPageIndirect: return "Stack Direct Page Indirect";
 case DirectPageIndexedX: return "Direct Page Indexed X";
 case DirectPageIndexedY: return "Direct Page Indexed Y";
 case DirectPageIndirect: return "Direct Page Indirect";
 case DirectPageIndirectLong: return "Direct Page Indirect Long";
 case Implied: return "Implied";
 case ImmediateZeroPage: return "ImmediateZeroPage";
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

