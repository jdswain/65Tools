/*

WDC 65C816 code generation

*/

void gen_816(const char* filename, int line_num, Instr *instr, AddrMode mode, int value1, int value2)
{
  switch( instr->opcode ) {
  case sADC:
    switch( mode ) {
    case Immediate:                      om(0x69, value1, longa); return;
    case Absolute:                       oabs(0x6d, value1); return;
    case AbsoluteLong:                   olong(0x6f, value1); return;
    case DirectPage:                     odp(0x65, value1); return;
    case DirectPageIndirect:             odp(0x72, value1); return;
    case DirectPageIndirectLong:         odp(0x67, value1); return;
    case AbsoluteIndexedX:               oabs(0x7d, value1); return;
    case AbsoluteLongIndexedX:           olong(0x7f, value1); return;
    case AbsoluteIndexedY:               oabs(0x79, value1); return;
    case DirectPageIndexedX:             odp(0x75, value1); return;
    case DirectPageIndexedIndirectX:     odp(0x61, value1); return;
    case DirectPageIndirectIndexedY:     odp(0x71, value1); return;
    case DirectPageIndirectLongIndexedY: odp(0x77, value1); return;
    case StackRelative:                  ob(0x63, value1); return;
    case StackRelativeIndirectIndexedY:  ob(0x73, value1); return;
    default:                             break;
    }
    break;
  case sAND:
    switch( mode ) {
    case Immediate:                      om(0x29, value1, longa); return;
    case Absolute:                       ow(0x2d, value1); return;
    case AbsoluteLong:                   ol(0x2f, value1); return;
    case DirectPage:                     ob(0x25, value1); return;
    case DirectPageIndirect:             ob(0x32, value1); return;
    case DirectPageIndirectLong:         ob(0x27, value1); return;
    case AbsoluteIndexedX:               ow(0x3d, value1); return;
    case AbsoluteLongIndexedX:           ol(0x3f, value1); return;
    case AbsoluteIndexedY:               ow(0x39, value1); return;
    case DirectPageIndexedX:             ob(0x35, value1); return;
    case DirectPageIndexedIndirectX:     ob(0x21, value1); return;
    case DirectPageIndirectIndexedY:     ob(0x31, value1); return;
    case DirectPageIndirectLongIndexedY: ob(0x37, value1); return;
    case StackRelative:                  ob(0x23, value1); return;
    case StackRelativeIndirectIndexedY:  ob(0x33, value1); return;
    default:                             break;
    }
    break;
  case sASL:
    switch( mode ) {
    case Implied:
    case Accumulator:                    o(0x0a); return;
    case Absolute:                       ow(0x0e, value1); return;
    case DirectPage:                     ob(0x06, value1); return;
    case AbsoluteIndexedX:               ow(0x1e, value1); return;
    case DirectPageIndexedX:             ob(0x16, value1); return;
    default:                             break;
    }
    break;
  case sBCC:
    if (value1 == 0) return; /* Optimisation */
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case ProgramCounterRelative:         or(filename, line_num, 0x90, value1); return;
    default:                             break;
    }
    break;
  case sBCS:
    if (value1 == 0) return; /* Optimisation */
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case ProgramCounterRelative:         or(filename, line_num, 0xb0, value1); return;
    default:                             break;
    }
    break;
  case sBEQ:
    if (value1 == 0) return; /* Optimisation */
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case ProgramCounterRelative:         or(filename, line_num, 0xf0, value1); return;
    default:                             break;
    }
    break;
  case sBIT:
    switch( mode ) {
    case Immediate:                      om(0x89, value1, longa); return;
    case Absolute:                       ow(0x2c, value1); return;
    case DirectPage:                     ob(0x24, value1); return;
    case AbsoluteIndexedX:               ow(0x3c, value1); return;
    case DirectPageIndexedX:             ob(0x34, value1); return;
    default:                             break;
    }
    break;
  case sBMI:
    if (value1 == 0) return; /* Optimisation */
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case ProgramCounterRelative:         or(filename, line_num, 0x30, value1); return;
    default:                             break;
    }
    break;
  case sBNE:
    if (value1 == 0) return; /* Optimisation */
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case ProgramCounterRelative:         or(filename, line_num, 0xd0, value1); return;
    default:                             break;
    }
    break;
  case sBPL:
    if (value1 == 0) return; /* Optimisation */
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case ProgramCounterRelative:         or(filename, line_num, 0x10, value1); return;
    default:                             break;
    }
    
    break;
  case sBRA:
    if (value1 == 0) return; /* Optimisation */
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case ProgramCounterRelative:
      {
	int r = value1 - (addr + 1);
	if ((r > 127) || (r < -128)) {
	  as_gen_warn(filename, line_num, "BRA promoted to BRL %d", value1);
	  orl(filename, line_num, 0x82, value1);
	} else {
	  or(filename, line_num, 0x80, value1);
	}
      }
      return;
    default:                             break;
    }
    break;
  case sBRK:
    switch( mode ) {
    case Implied:                        o(0x00); return;
    case Immediate:                      ob(0x00, value1); return;
    default:                             break;
    }
    break;
  case sBRL:
    if (value1 == 0) return; /* Optimisation */
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case ProgramCounterRelative:
      {
	int r = value1 - (addr + 1);
	if ((r > 127) || (r < -128)) {
	  orl(filename, line_num, 0x82, value1);
	} else {
	  as_gen_warn(filename, line_num, "BRL demoted to BRA %d", value1);
	  or(filename, line_num, 0x80, value1);
	}
      }
      return;
    default:                             break;
    }
    break;
  case sBVC:
    if (value1 == 0) return; /* Optimisation */
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case ProgramCounterRelative:         or(filename, line_num, 0x50, value1); return;
    default:                             break;
    }
    break;
  case sBVS:
    if (value1 == 0) return; /* Optimisation */
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case ProgramCounterRelative:         or(filename, line_num, 0x70, value1); return;
    default:                             break;
    }
    break;
  case sCLC:
    switch( mode ) {
    case Implied:                        o(0x18); return;
    default:                             break;
    }
    break;
  case sCLD:
    switch( mode ) {
    case Implied:                        o(0xd8); return;
    default:                             break;
    }
    break;
  case sCLI:
    switch( mode ) {
    case Implied:                        o(0x58); return;
    default:                             break;
    }
    break;
  case sCLV:
    switch( mode ) {
    case Implied:                        o(0xb8); return;
    default:                             break;
    }
    break;
  case sCMP:
    switch( mode ) {
    case Immediate:                      om(0xc9, value1, longa); return;
    case Absolute:                       ow(0xcd, value1); return;
    case AbsoluteLong:                   ol(0xcf, value1); return;
    case DirectPage:                     ob(0xc5, value1); return;
    case DirectPageIndirect:             ob(0xd2, value1); return;
    case DirectPageIndirectLong:         ob(0xc7, value1); return;
    case AbsoluteIndexedX:               ow(0xdd, value1); return;
    case AbsoluteLongIndexedX:           ol(0xdf, value1); return;
    case AbsoluteIndexedY:               ow(0xd9, value1); return;
    case DirectPageIndexedX:             ob(0xd5, value1); return;
    case DirectPageIndexedIndirectX:     ob(0xc1, value1); return;
    case DirectPageIndirectIndexedY:     ob(0xd1, value1); return;
    case DirectPageIndirectLongIndexedY: ob(0xd7, value1); return;
    case StackRelative:                  ob(0xc3, value1); return;
    case StackRelativeIndirectIndexedY:  ob(0xd3, value1); return;
    default:                             break;
    }
    break;
  case sCOP:
    switch( mode ) {
      // Note implied is not available, signature byte is required
    case Immediate:                      ob(0x02, value1); return;
    default:                             break;
    }
    break;
  case sCPX:
    switch( mode ) {
    case Immediate:                      om(0xe0, value1, longi); return;
    case Absolute:                       ow(0xec, value1); return;
    case DirectPage:                     ob(0xe4, value1); return;
    default:                             break;
    }
    break;
  case sCPY:
    switch( mode ) {
    case Immediate:                      om(0xc0, value1, longi); return;
    case Absolute:                       ow(0xcc, value1); return;
    case DirectPage:                     ob(0xc4, value1); return;
    default:                             break;
    }
    break;
  case sDEC:
    switch( mode ) {
    case Accumulator:
    case Implied:                        o(0x3a); return;
    case Absolute:                       ow(0xce, value1); return;
    case DirectPage:                     ob(0xc6, value1); return;
    case AbsoluteIndexedX:               ow(0xde, value1); return;
    case DirectPageIndexedX:             ob(0xd6, value1); return;
    default:                             break;
    }
    break;
  case sDEX:
    switch( mode ) {
    case Implied:                        o(0xca); return;
    default:                             break;
    }
    break;
  case sDEY:
    switch( mode ) {
    case Implied:                        o(0x88); return;
    default:                             break;
    }
    break;
  case sEOR:
    switch( mode ) {
    case Immediate:                      om(0x49, value1, longa); return;
    case Absolute:                       ow(0x4d, value1); return;
    case AbsoluteLong:                   ol(0x4f, value1); return;
    case DirectPage:                     ob(0x45, value1); return;
    case DirectPageIndirect:             ob(0x52, value1); return;
    case DirectPageIndirectLong:         ob(0x47, value1); return;
    case AbsoluteIndexedX:               ow(0x5d, value1); return;
    case AbsoluteLongIndexedX:           ol(0x5f, value1); return;
    case AbsoluteIndexedY:               ow(0x59, value1); return;
    case DirectPageIndexedX:             ob(0x55, value1); return;
    case DirectPageIndexedIndirectX:     ob(0x41, value1); return;
    case DirectPageIndirectIndexedY:     ob(0x51, value1); return;
    case DirectPageIndirectLongIndexedY: ob(0x57, value1); return;
    case StackRelative:                  ob(0x43, value1); return;
    case StackRelativeIndirectIndexedY:  ob(0x53, value1); return;
    default:                             break;
    }
    break;
  case sINC:
    switch( mode ) {
    case Accumulator:
    case Implied:                        o(0x1a); return;
    case Absolute:                       ow(0xee, value1); return;
    case DirectPage:                     ob(0xe6, value1); return;
    case AbsoluteIndexedX:               ow(0xfe, value1); return;
    case DirectPageIndexedX:             ob(0xf6, value1); return;
    default:                             break;
    }
    break;
  case sINX:
    switch( mode ) {
    case Implied:                        o(0xe8); return; 
    default:                             break;
    }
    break;
  case sINY:
    switch( mode ) {
    case Implied:                        o(0xc8); return;
    default:                             break;
    }
    break;
  case sJMP:
    switch( mode ) {
    case DirectPage: /* Less than $100, treat as absolute */
    case Absolute:                       ow(0x4c, value1); return;
    case AbsoluteIndirect:               ow(0x6c, value1); return;
    case AbsoluteIndexedIndirect:        ow(0x7c, value1); return;
    case AbsoluteLong:                   ol(0x5c, value1); return;
    case AbsoluteIndirectLong:           ow(0xdc, value1); return; 
    default:                             break;
    }
    break;
  case sJML:
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case AbsoluteLong:                   ol(0x5c, value1); return;
    case AbsoluteIndirect:
    case AbsoluteIndirectLong:           ow(0xdc, value1); return; 
    default:                             break;
    }
    break;
  case sJSL:
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case AbsoluteLong:                   ol(0x22, value1); return;
    default:                             break;
    }
    break;
  case sJSR:
    switch( mode ) {
    case DirectPage:
    case Absolute:                       ow(0x20, value1); return;
    case AbsoluteIndexedIndirect:        ow(0xfc, value1); return;
    case AbsoluteLong:                   ol(0x22, value1); return;
    default:                             break;
    }
    break;
  case sLDA:
    switch( mode ) {
    case Immediate:                      om(0xa9, value1, longa); return;
    case Absolute:                       ow(0xad, value1); return;
    case AbsoluteLong:                   ol(0xaf, value1); return;
    case DirectPage:                     ob(0xa5, value1); return;
      /* This is DirectPageIndirect, but the parser is not 
	 smart enough to figure that out */
    case AbsoluteIndirect:
    case DirectPageIndirect:             ob(0xb2, value1); return;
    case DirectPageIndirectLong:         ob(0xa7, value1); return;
    case AbsoluteIndexedX:               ow(0xbd, value1); return;
    case AbsoluteLongIndexedX:           ol(0xbf, value1); return;
    case AbsoluteIndexedY:               ow(0xb9, value1); return;
    case DirectPageIndexedX:             ob(0xb5, value1); return;
    case DirectPageIndexedIndirectX:     ob(0xa1, value1); return;
    case DirectPageIndirectIndexedY:     ob(0xb1, value1); return;
    case DirectPageIndirectLongIndexedY: ob(0xb7, value1); return;
    case StackRelative:                  ob(0xa3, value1); return;
    case StackRelativeIndirectIndexedY:  ob(0xb3, value1); return;
    default:                             return;
    }
    break;
  case sLDX:
    switch( mode ) {
    case Immediate:                      om(0xa2, value1, longi); return;
    case Absolute:                       ow(0xae, value1); return;
    case DirectPage:                     ob(0xa6, value1); return;
    case AbsoluteIndexedY:               ow(0xbe, value1); return;
    case DirectPageIndexedY:             ob(0xb6, value1); return;
    default:                             break;
    }
    break;
  case sLDY:
    switch( mode ) {
    case Immediate:                      om(0xa0, value1, longi); return;
    case Absolute:                       ow(0xac, value1); return;
    case DirectPage:                     ob(0xa4, value1); return;
    case AbsoluteIndexedX:               ow(0xbc, value1); return;
    case DirectPageIndexedX:             ob(0xb4, value1); return;
    default:                             break;
    }
    break;
  case sLSR:
    switch( mode ) {
    case Accumulator:
    case Implied:                        o(0x4a); return;
    case Absolute:                       ow(0x4e, value1); return;
    case DirectPage:                     ob(0x46, value1); return;
    case AbsoluteIndexedX:               ow(0x5e, value1); return;
    case DirectPageIndexedX:             ob(0x56, value1); return;
    default:                             break;
    }
    break;
  case sMVN:
    switch( mode ) {
    case BlockMove:                      omove(0x54, value2, value1); return;
    default:                             break;
    }
    break;
  case sMVP:
    switch( mode ) {
    case BlockMove:                      omove(0x44, value2, value1); return;
    default:                             break;
    }
    break;
  case sNOP:
    switch( mode ) {
    case Implied:                        o(0xea); return;
    default:                             break;
    }
    break;
  case sORA:
    switch( mode ) {
    case Immediate:                      om(0x09, value1, longa); return;
    case Absolute:                       ow(0x0d, value1); return;
    case AbsoluteLong:                   ol(0x0f, value1); return;
    case DirectPage:                     ob(0x05, value1); return;
    case DirectPageIndirect:             ob(0x12, value1); return;
    case DirectPageIndirectLong:         ob(0x07, value1); return;
    case AbsoluteIndexedX:               ow(0x1d, value1); return;
    case AbsoluteLongIndexedX:           ol(0x1f, value1); return;
    case AbsoluteIndexedY:               ow(0x19, value1); return;
    case DirectPageIndexedX:             ob(0x15, value1); return;
    case DirectPageIndexedIndirectX:     ob(0x01, value1); return;
    case DirectPageIndirectIndexedY:     ob(0x11, value1); return;
    case DirectPageIndirectLongIndexedY: ob(0x17, value1); return;
    case StackRelative:                  ob(0x03, value1); return;
    case StackRelativeIndirectIndexedY:  ob(0x13, value1); return;
    default:                             break;
    }
    break;
  case sPEA:
    switch( mode ) {
    case Immediate:
    case Absolute:                        ow(0xf4, value1); return;
    default:                              break;
    }
    break;
  case sPEI:
    switch( mode ) {
    case DirectPageIndirect:              ob(0xd4, value1); return;
    default:                              break;
    }
    break;
  case sPER:
    switch( mode ) {
    case Immediate:
    case DirectPage:
    case Absolute:                        ow(0x62, value1); return;
    default:                              break;
    }
    break;
  case sPHA:
    switch( mode ) {
    case Implied:                         o(0x48); return;
    default:                              break;
    }
    break;
  case sPHB:
    switch( mode ) {
    case Implied:                         o(0x8b); return;
    default:                              break;
    }
    break;
  case sPHD:
    switch( mode ) {
    case Implied:                         o(0x0b); return;
    default:                              break;
    }
    break;
  case sPHK:
    switch( mode ) {
    case Implied:                         o(0x4b); return;
    default:                              break;
    }
    break;
  case sPHP:
    switch( mode ) {
    case Implied:                         o(0x08); return;
    default:                              break;
    }
    break;
  case sPHX:
    switch( mode ) {
    case Implied:                         o(0xda); return;
    default:                              break;
    }
    break;
  case sPHY:
    switch( mode ) {
    case Implied:                         o(0x5a); return;
    default:                              break;
    }
    break;
  case sPLA:
    switch( mode ) {
    case Implied:                         o(0x68); return;
    default:                              break;
    }
    break;
  case sPLB:
    switch( mode ) {
    case Implied:                         o(0xab); return;
    default:                              break;
    }
    break;
  case sPLD:
    switch( mode ) {
    case Implied:                         o(0x2b); return;
    default:                              break;
    }
    break;
  case sPLP:
    switch( mode ) {
    case Implied:                         o(0x28); return;
    default:                              break;
    }
    break;
  case sPLX:
    switch( mode ) {
    case Implied:                         o(0xfa); return;
    default:                              break;
    }
    break;
  case sPLY:
    switch( mode ) {
    case Implied:                         o(0x7a); return;
    default:                              break;
    }
    break;
  case sREP:
    switch( mode ) {
    case Immediate:                       ob(0xc2, value1); return;
    default:                              break;
    }
    break;
  case sROL:
    switch( mode ) {
    case Accumulator:
    case Implied:                         o(0x2a); return;
    case Absolute:                        ow(0x2e, value1); return;
    case DirectPage:                      ob(0x26, value1); return;
    case AbsoluteIndexedX:                ow(0x3e, value1); return;
    case DirectPageIndexedX:              ob(0x36, value1); return;
    default:                              break;
    }
    break;
  case sROR:
    switch( mode ) {
    case Accumulator:
    case Implied:                         o(0x6a); return;
    case Absolute:                        ow(0x6e, value1); return;
    case DirectPage:                      ob(0x66, value1); return;
    case AbsoluteIndexedX:                ow(0x7e, value1); return;
    case DirectPageIndexedX:              ob(0x76, value1); return;
    default:                              break;
    }
    break;
  case sRTI:
    switch( mode ) {
    case Implied:                         o(0x40); return;
    default:                              break;
    }
    break;
  case sRTL:
    switch( mode ) {
    case Implied:                         o(0x6b); return;
    default:                              break;
    }
    break;
  case sRTS:
    switch( mode ) {
    case Implied:                         o(0x60); return;
    default:                              break;
    }
    break;
  case sSBC:
    switch( mode ) {
    case Immediate:                      om(0xe9, value1, longa); return;
    case Absolute:                       ow(0xed, value1); return;
    case AbsoluteLong:                   ol(0xef, value1); return;
    case DirectPage:                     ob(0xe5, value1); return;
    case DirectPageIndirect:             ob(0xf2, value1); return;
    case DirectPageIndirectLong:         ob(0xe7, value1); return;
    case AbsoluteIndexedX:               ow(0xfd, value1); return;
    case AbsoluteLongIndexedX:           ol(0xff, value1); return;
    case AbsoluteIndexedY:               ow(0xf9, value1); return;
    case DirectPageIndexedX:             ob(0xf5, value1); return;
    case DirectPageIndexedIndirectX:     ob(0xe1, value1); return; 
    case DirectPageIndirectIndexedY:     ob(0xf1, value1); return;
    case DirectPageIndirectLongIndexedY: ob(0xf7, value1); return;
    case StackRelative:                  ob(0xe3, value1); return;
    case StackRelativeIndirectIndexedY:  ob(0xf3, value1); return;
    default:                              break;
    }
    break;
  case sSEC:
    switch( mode ) {
    case Implied:                         o(0x38); return;
    default:                              break;
    }
    break;
  case sSED:
    switch( mode ) {
    case Implied:                         o(0xf8); return;
    default:                              break;
    }
    break;
  case sSEI:
    switch( mode ) {
    case Implied:                         o(0x78); return;
    default:                              break;
    }
    break;
  case sSEP:
    switch( mode ) {
    case Immediate:                       ob(0xe2, value1); return;
    default:                              break;
    }
    break;
  case sSTA:
    switch( mode ) {
    case Absolute:                       ow(0x8d, value1); return;
    case AbsoluteLong:                   ol(0x8f, value1); return;
    case DirectPage:                     ob(0x85, value1); return;
    case DirectPageIndirect:             ob(0x92, value1); return;
    case DirectPageIndirectLong:         ob(0x87, value1); return;
    case AbsoluteIndexedX:               ow(0x9d, value1); return;
    case AbsoluteLongIndexedX:           ol(0x9f, value1); return;
	case DirectPageIndexedY:
    case AbsoluteIndexedY:               ow(0x99, value1); return;
    case DirectPageIndexedX:             ob(0x95, value1); return;
    case DirectPageIndexedIndirectX:     ob(0x81, value1); return;
    case DirectPageIndirectIndexedY:     ob(0x91, value1); return;
    case DirectPageIndirectLongIndexedY: ob(0x97, value1); return;
    case StackRelative:                  ob(0x83, value1); return;
    case StackRelativeIndirectIndexedY:  ob(0x93, value1); return;
    default:                              break;
    }
    break;
  case sSTP:
    switch( mode ) {
    case Implied:                         o(0xdb); return;
    default:                              break;
    }
    break;
  case sSTX:
    switch( mode ) {
    case Absolute:                        ow(0x8e, value1); return;
    case DirectPage:                      ob(0x86, value1); return;
    case DirectPageIndexedY:              ow(0x96, value1); return;
    default:                              break;
    }
    break;
  case sSTY:
    switch( mode ) {
    case Absolute:                        ow(0x8c, value1); return;
    case DirectPage:                      ob(0x84, value1); return;
    case DirectPageIndexedX:              ob(0x94, value1); return;
    default:                              break;
    }
    break;
  case sSTZ:
    switch( mode ) {
    case Absolute:                        ow(0x9c, value1); return;
    case DirectPage:                      ob(0x64, value1); return;
    case AbsoluteIndexedX:                ow(0x9e, value1); return;
    case DirectPageIndexedX:              ow(0x74, value1); return;
    default:                              break;
    }
    break;
  case sTAX:
    switch( mode ) {
    case Implied:                         o(0xaa); return;
    default:                              break;
    }
    break;
  case sTAY:
    switch( mode ) {
    case Implied:                         o(0xa8); return;
    default:                              break;
    }
    break;
  case sTAD:
  case sTCD:
    switch( mode ) {
    case Implied:                         o(0x5b); return;
    default:                              break;
    }
    break;
  case sTAS:
  case sTCS:
    switch( mode ) {
    case Implied:                         o(0x1b); return;
    default:                              break;
    }
    break;
  case sTDA:
  case sTDC:
    switch( mode ) {
    case Implied:                         o(0x7b); return;
    default:                              break;
    }
    break;
  case sTRB:
    switch( mode ) {
    case Absolute:                        ow(0x1c, value1); return;
    case DirectPage:                      ob(0x14, value1); return;
    default:                              break;
    }
    break;
  case sTSB:
    switch( mode ) {
    case Absolute:                        ow(0x0c, value1); return;
    case DirectPage:                      ob(0x04, value1); return;
    default:                              break;
    }
    break;
  case sTSA:
  case sTSC:
    switch( mode ) {
    case Implied:                         o(0x3b); return;
    default:                              break;
    }
    break;
  case sTSX:
    switch( mode ) {
    case Implied:                         o(0xba); return;
    default:                              break;
    }
    break;
  case sTXA:
    switch( mode ) {
    case Implied:                         o(0x8a); return;
    default:                              break;
    }
    break;
  case sTXS:
    switch( mode ) {
    case Implied:                         o(0x9a); return;
    default:                              break;
    }
    break;
  case sTXY:
    switch( mode ) {
    case Implied:                         o(0x9b); return;
    default:                              break;
    }
    break;
  case sTYA:
    switch( mode ) {
    case Implied:                         o(0x98); return;
    default:                              break;
    }
    break;
  case sTYX:
    switch( mode ) {
    case Implied:                         o(0xbb); return;
    default:                              break;
    }
    break;
  case sWAI:
    switch( mode ) {
    case Implied:                         o(0xcb); return;
    default:                              break;
    }
    break;
  case sWDM:
    switch( mode ) {
    case Immediate:                       ob(0x42, value1); return;
    default:                              break;
    }
    break;
  case sSWA:
  case sXBA:
    switch( mode ) {
    case Implied:                         o(0xeb); return;
    default:                              break;
    }
    break;
  case sXCE:
    switch( mode ) {
    case Implied:                         o(0xfb); return;
    default:                              break;
    }
    break;
  default:
      break;
  }
  as_gen_error(filename, line_num, "%s %s not supported on 65C816",
	   token_to_string(instr->opcode),
			   mode_to_string(mode));
}
