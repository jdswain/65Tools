/*

Rockwell C19 instruction set.

This includes L28.

*/
void gen_RC19(const char *filename, int line_num, Instr *instr, AddrMode mode, int value1, int value2, int value3)
{
  switch( instr->opcode ) {
  case sADC:
    switch( mode ) {
    case Immediate:                      ob(0x69, value1); return;
    case DirectPage:                     ob(0x65, value1); return;
    case DirectPageIndexedX:             ob(0x75, value1); return;
    case Absolute:                       ow(0x6d, value1); return;
    case AbsoluteIndexedX:               ow(0x7d, value1); return;
    case AbsoluteIndexedY:               ow(0x79, value1); return;
    case AbsoluteIndirect:
    case DirectPageIndirect:             ob(0x61, value1); return;
    case DirectPageIndexedIndirectX:     ob(0x71, value1); return;
    default:                             break;
    }
    break;
  case sADD:
    switch( mode ) {
    case Immediate:                      ob(0x89, value1); return;
    case DirectPage:                     ob(0x64, value1); return;
    case DirectPageIndexedX:             ob(0x74, value1); return;
    default:                             break;
    }
    break;
  case sAND:
    switch( mode ) {
    case Immediate:                      ob(0x29, value1); return;
    case DirectPage:                     ob(0x25, value1); return;
    case DirectPageIndexedX:             ob(0x35, value1); return;
    case Absolute:                       ow(0x2d, value1); return;
    case AbsoluteIndexedX:               ow(0x3d, value1); return;
    case AbsoluteIndexedY:               ow(0x39, value1); return;
    case AbsoluteIndirect:
    case DirectPageIndirect:             ob(0x21, value1); return;
    case DirectPageIndexedIndirectX:     ob(0x31, value1); return;
    default:                             break;
    }
    break;
  case sASL:
    switch( mode ) {
    case Accumulator:
    case Implied:                        o(0x0a); return;
    case DirectPage:                     ob(0x06, value1); return;
    case DirectPageIndexedX:             ob(0x16, value1); return;
    case Absolute:                       ow(0x0e, value1); return;
    case AbsoluteIndexedX:               ow(0x1e, value1); return;
    default:                             break;
    }
    break;
  case sASR:
    switch( mode ) {
    case Implied:
    case Accumulator:                    o(0x3a); return;
    default:                             break;
    }
    break;
  case sBAR:
    switch( mode ) {
    case BitAbsoluteRelative:            obitar(filename, line_num, 0xe2, value3, value2, value1); return;
    default:                             break;
    }
    break;
  case sBAS:
    switch( mode ) {
    case BitAbsoluteRelative:            obitar(filename, line_num, 0xf2, value3, value2, value1); return;
    default:                             break;
    }
    break;
  case sBBR:
    switch( mode ) {
    case BitAbsoluteRelative:
    case BitZeroPageRelative:            obitzr(filename, line_num, 0x0f, value3, value2, value1); return;
    default:                             break;
    }
    break;
  case sBBS:
    switch( mode ) {
    case BitAbsoluteRelative:
    case BitZeroPageRelative:            obitzr(filename, line_num, 0x8f, value3, value2, value1); return;
    default:                             break;
    }
    break;
  case sBCC:
    switch( mode ) {
    case Absolute:
    case ProgramCounterRelative:         or(filename, line_num, 0x90, value1); return;
    default:                             break;
    }
    break;
  case sBCS:
    switch( mode ) {
    case Absolute:
    case ProgramCounterRelative:         or(filename, line_num, 0xb0, value1); return;
    default:                             break;
    }
    break;
  case sBEQ:
    switch( mode ) {
    case Absolute:
    case DirectPage:
    case ProgramCounterRelative:         or(filename, line_num, 0xf0, value1); return;
    default:                             break;
    }
    break;
  case sBIT:
    switch( mode ) { 
    case DirectPage:                     ob(0x24, value1); return;
    case Absolute:                       ow(0x2c, value1); return;
    default:                             break;
    }
    break;
  case sBMI:
    switch( mode ) {
    case Absolute:
    case ProgramCounterRelative:         or(filename, line_num, 0x30, value1); return;
    default:                             break;
    }
    break;
  case sBNE:
    switch( mode ) {
    case Absolute:
    case ProgramCounterRelative:         or(filename, line_num, 0xd0, value1); return;
    default:                             break;
    }
    break;
  case sBPL:
    switch( mode ) {
    case Absolute:
    case ProgramCounterRelative:         or(filename, line_num, 0x10, value1); return;
    default:                             break;
    }
    break;
  case sBRA:
    switch( mode ) {
    case Absolute:
    case ProgramCounterRelative:         or(filename, line_num, 0x80, value1); return;
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
  case sBVC:
    switch( mode ) {
    case Absolute:
    case ProgramCounterRelative:         or(filename, line_num, 0x50, value1); return;
    default:                             break;
    }
    break;
  case sBVS:
    switch( mode ) {
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
  case sCLW:
    switch( mode ) {
    case Implied:                        o(0x52); return;
    default:                             break;
    }
    break;
  case sCMP:
    switch( mode ) {
    case Immediate:                      ob(0xc9, value1); return;
    case DirectPage:                     ob(0xc5, value1); return;
    case DirectPageIndexedX:             ob(0xd5, value1); return;
    case Absolute:                       ow(0xcd, value1); return;
    case AbsoluteIndexedX:               ow(0xdd, value1); return;
    case AbsoluteIndexedY:               ow(0xd9, value1); return;
    case AbsoluteIndirect:
    case DirectPageIndirect:             ob(0xc1, value1); return;
    case DirectPageIndexedIndirectX:     ob(0xd1, value1); return;
    default:                             break;
    }
    break;
  case sCPX:
    switch( mode ) {
    case Immediate:                      ob(0xe0, value1); return;
    case DirectPage:                     ob(0xe4, value1); return;
    case Absolute:                       ow(0xec, value1); return;
    default:                             break;
    }
    break;
  case sCPY:
    switch( mode ) {
    case Immediate:                      ob(0xc0, value1); return;
    case DirectPage:                     ob(0xc4, value1); return;
    case Absolute:                       ow(0xcc, value1); return;
    default:                             break;
    }
    break;
  case sDEC:
    switch( mode ) {
    case DirectPage:                     ob(0xc6, value1); return;
    case DirectPageIndexedX:             ob(0xd6, value1); return;
    case Absolute:                       ow(0xce, value1); return;
    case AbsoluteIndexedX:               ow(0xde, value1); return;
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
    case Immediate:                      ob(0x49, value1); return;
    case DirectPage:                     ob(0x45, value1); return;
    case DirectPageIndexedX:             ob(0x55, value1); return;
    case Absolute:                       ow(0x4d, value1); return;
    case AbsoluteIndexedX:               ow(0x5d, value1); return;
    case AbsoluteIndexedY:               ow(0x59, value1); return;
    case AbsoluteIndirect:
    case DirectPageIndirect:             ob(0x41, value1); return;
    case DirectPageIndexedIndirectX:     ob(0x51, value1); return;
    default:                             break;
    }
    break;
  case sEXC:
    switch( mode ) {
    case DirectPageIndexedX:             ob(0xd4, value1); return;
    default:                             break;
    }
    break;
  case sINC:
    switch( mode ) {
    case DirectPage:                     ob(0xe6, value1); return;
    case DirectPageIndexedX:             ob(0xf6, value1); return;
    case Absolute:                       ow(0xee, value1); return;
    case AbsoluteIndexedX:               ow(0xfe, value1); return;
    default:                             break;
    }
    break;
  case sINI:
    switch( mode ) {
    case Implied:                        o(0xbb); return;
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
    case DirectPage:
    case Absolute:                       ow(0x4c, value1); return;
    case AbsoluteIndirect:               ow(0x6c, value1); return;
    case AbsoluteIndexedIndirect:        ow(0x7c, value1); return;
    default:                             break;
    }
    break;
  case sJPI:
    switch( mode ) {
    case AbsoluteIndirect:               ow(0x0c, value1); return;
    default:                             break;
    }
    break;
  case sJSB:
    switch( mode ) {
    case Immediate:
    case DirectPage:                     o(0x0b | value1 << 4); return;
    default:                             break;
    }
    break;
  case sJSR:
    switch( mode ) {
    case DirectPage:
    case Absolute:                       ow(0x20, value1); return;
    default:                             break;
    }
    break;
  case sLAB:
    switch( mode ) {
    case Implied:
    case Accumulator:                    o(0x13); return;
    default:                             break;
    }
    break;
  case sLAI:
    switch( mode ) {
    case Implied:                        o(0xeb); return;
    default:                             break;
    }
    break;
  case sLAN:
    switch( mode ) {
    case Implied:                        o(0xab); return;
    default:                             break;
    }
    break;
  case sLDA:
    switch( mode ) {
    case Immediate:                      ob(0xa9, value1); return;
    case DirectPage:                     ob(0xa5, value1); return;
    case DirectPageIndexedX:             ob(0xb5, value1); return;
    case Absolute:                       ow(0xad, value1); return;
    case AbsoluteIndexedX:               ow(0xbd, value1); return;
    case AbsoluteIndexedY:               ow(0xb9, value1); return;
    case AbsoluteIndirect:
    case DirectPageIndirect:             ob(0xa1, value1); return;
    case DirectPageIndexedIndirectX:     ob(0xb1, value1); return;
    default:                             break;
    }
    break;
  case sLDX:
    switch( mode ) {
    case Immediate:                      o(0xa2); return;
    case DirectPage:                     ob(0xa6, value1); return;
    case DirectPageIndexedY:             ob(0xb6, value1); return;
    case Absolute:                       ow(0xae, value1); return;
    case AbsoluteIndexedY:               ow(0xbe, value1); return;
    default:                             break;
    }
    break;
  case sLDY:
    switch( mode ) {
    case Immediate:                      o(0xa0); return;
    case DirectPage:                     ob(0xa4, value1); return;
    case DirectPageIndexedX:             ob(0xb4, value1); return;
    case Absolute:                       ow(0xac, value1); return;
    case AbsoluteIndexedX:               ow(0xbc, value1); return;
    default:                             break;
    }
    break;
  case sLII:
    switch( mode ) {
    case Implied:                        o(0x9b); return;
    default:                             break;
    }
    break;
  case sLSR:
    switch( mode ) {
    case Implied:
    case Accumulator:                    o(0x4a); return;
    case DirectPage:                     ob(0x46, value1); return;
    case DirectPageIndexedX:             ob(0x56, value1); return;
    case Absolute:                       ow(0x4e, value1); return;
    case AbsoluteIndexedX:               ow(0x5e, value1); return;
    default:                             break;
    }
    break;
  case sMPA:
    switch( mode ) {
    case Implied:                        o(0x12); return;
    default:                             break;
    }
    break;
  case sMPY:
    switch( mode ) {
    case Implied:                        o(0x02); return;
    default:                             break;
    }
    break;
  case sNEG:
    switch( mode ) {
    case Implied:
    case Accumulator:                    o(0x1a); return;
    default:                             break;
    }
    break;
  case sNOP:
    switch( mode ) {
    case Implied:                        o(0xea); return;
    default:                             break;
    }
    break;
  case sNXT:
    switch( mode ) {
    case Implied:                        o(0x8b); return;
    default:                             break;
    }
    break;
  case sORA:
    switch( mode ) {
    case Immediate:                      ob(0x09, value1); return;
    case DirectPage:                     ob(0x05, value1); return;
    case DirectPageIndexedX:             ob(0x15, value1); return;
    case Absolute:                       ow(0x0d, value1); return;
    case AbsoluteIndexedX:               ow(0x1d, value1); return;
    case AbsoluteIndexedY:               ow(0x19, value1); return;
    case AbsoluteIndirect:
    case DirectPageIndirect:             ob(0x01, value1); return;
    case DirectPageIndexedIndirectX:     ob(0x11, value1); return;
    default:                             break;
    }
    break;
  case sPHA:
    switch( mode ) {
    case Implied:                         o(0x48); return;
    default:                              break;
    }
    break;
  case sPHI:
    switch( mode ) {
    case Implied:                         o(0xcb); return;
    default:                              break;
    }
    break;
  case sPHP:
    switch( mode ) {
    case Implied:                         o(0x08); return;
    default:                              break;
    }
    break;
  case sPHW:
    switch( mode ) {
    case Implied:                         o(0x23); return;
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
  case sPIA:
    switch( mode ) {
    case Implied:                         o(0xfb); return;
    default:                              break;
    }
    break;
  case sPLA:
    switch( mode ) {
    case Implied:                         o(0x68); return;
    default:                              break;
    }
    break;
  case sPLI:
    switch( mode ) {
    case Implied:                         o(0xdb); return;
    default:                              break;
    }
    break;
  case sPLP:
    switch( mode ) {
    case Implied:                         o(0x28); return;
    default:                              break;
    }
    break;
  case sPLW:
    switch( mode ) {
    case Implied:                         o(0x33); return;
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
  case sPSH:
    switch( mode ) {
    case Implied:                         o(0x22); return;
    default:                              break;
    }
    break;
  case sPUL:
    switch( mode ) {
    case Implied:                         o(0x32); return;
    default:                              break;
    }
    break;
  case sRBA:
    switch( mode ) {
    case BlockMove:
    case BitAbsolute:                     obita(filename, line_num, 0xc2, value2, value1); return;
    default:                              break;
    }
    break;
  case sRMB:
    switch( mode ) {
    case BlockMove:
    case BitZeroPage:                     ob(0x07 | value2 << 4, value1); return;
    default:                              break;
    }
    break;
  case sRND:
    switch( mode ) {
    case Implied:                         o(0x42); return;
    default:                              break;
    }
    break;
  case sROL:
    switch( mode ) {
    case Implied:
    case Accumulator:                     o(0x2a); return;
    case DirectPage:                      ob(0x26, value1); return;
    case DirectPageIndexedX:              ob(0x36, value1); return;
    case Absolute:                        ow(0x2e, value1); return;
    case AbsoluteIndexedX:                ow(0x3e, value1); return;
    default:                              break;
    }
    break;
  case sROR:
    switch( mode ) {
    case Implied:
    case Accumulator:                     o(0x6a); return;
    case DirectPage:                      ob(0x66, value1); return;
    case DirectPageIndexedX:              ob(0x76, value1); return;
    case Absolute:                        ow(0x6e, value1); return;
    case AbsoluteIndexedX:                ow(0x7e, value1); return;
    default:                              break;
    }
    break;
  case sRTI:
    switch( mode ) {
    case Implied:                         o(0x40); return;
    default:                              break;
    }
    break;
  case sRTS:
    switch( mode ) {
    case Implied:                         o(0x60); return;
    default:                              break;
    }
    break;
  case sSBA:
    switch( mode ) {
    case BlockMove:
    case BitAbsolute:                     obita(filename, line_num, 0xd2, value2, value1); return;
    default:                              break;
    }
    break;
  case sSBC:
    switch( mode ) {
    case Immediate:                       ob(0xe9, value1); return;
    case DirectPage:                      ob(0xe5, value1); return;
    case DirectPageIndexedX:              ob(0xf5, value1); return;
    case Absolute:                        ow(0xed, value1); return;
    case AbsoluteIndexedX:                ow(0xfd, value1); return;
    case AbsoluteIndexedY:                ow(0xf9, value1); return;
    case AbsoluteIndirect:
    case DirectPageIndirect:              ob(0xe1, value1); return;
    case DirectPageIndexedIndirectX:      ob(0xf1, value1); return; 
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
  case sSMB:
    switch( mode ) {
    case BlockMove:
    case BitZeroPage:                     ob(0x87 | value2 << 4, value1); return;
    default:                              break;
    }
    break;
  case sSTA:
    switch( mode ) {
    case DirectPage:                      ob(0x85, value1); return;
    case DirectPageIndexedX:              ob(0x95, value1); return;
    case Absolute:                        ow(0x8d, value1); return;
    case AbsoluteIndexedX:                ow(0x9d, value1); return;
    case AbsoluteIndexedY:                ow(0x99, value1); return;
    case AbsoluteIndirect:
    case DirectPageIndirect:              ob(0x81, value1); return;
    case DirectPageIndexedIndirectX:      ob(0x91, value1); return;
    default:                              break;
    }
    break;
  case sSTI:
    switch( mode ) {
    case BlockMove: /* Works but doesn't detect errors with #'s */
    case ImmediateZeroPage:               oiz(0xb2, value2, value1); return;
    default:                              break;
    }
    break;
  case sSTX:
    switch( mode ) {
    case DirectPage:                      ob(0x86, value1); return;
    case DirectPageIndexedY:              ow(0x96, value1); return;
    case Absolute:                        ow(0x8e, value1); return;
    default:                              break;
    }
    break;
  case sSTY:
    switch( mode ) {
    case DirectPage:                      ob(0x84, value1); return;
    case DirectPageIndexedX:              ob(0x94, value1); return;
    case Absolute:                        ow(0x8c, value1); return;
    default:                              break;
    }
    break;
  case sTAW:
    switch( mode ) {
    case Implied:                         o(0x62); return;
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
  case sTIP:
    switch( mode ) {
    case Implied:                         o(0x03); return;
    default:                              break;
    }
    break;
  case sTSX:
    switch( mode ) {
    case Implied:                         o(0xba); return;
    default:                              break;
    }
    break;
  case sTWA:
    switch( mode ) {
    case Implied:                         o(0x72); return;
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
  case sTYA:
    switch( mode ) {
    case Implied:                         o(0x98); return;
    default:                              break;
    }
    break;
  default:
      break;
  }
  as_gen_error(filename, line_num, "%s %s not supported on RC19",
			   token_to_string(instr->opcode), mode_to_string(mode));
}
