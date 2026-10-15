#!/usr/bin/env python3
"""Write the decode table of EmCore.Mod from the Verilog core.

    python3 tools/gencore.py ../../Verilog65C816/cpu_65c816.v

The function dec() of cpu_65c816.v gives each opcode an addressing mode,
a class and an operation; this prints Oberon statements that fill the
arrays mode, cls and op of EmCore with the same, and a string of the
256 mnemonics for the trace. Run once when EmCore was written; the
output was pasted into it.
"""
import re, sys

v = open(sys.argv[1]).read()
body = v[v.index('function [12:0] dec('):v.index('endfunction', v.index('function [12:0] dec('))]
mode, cls, op = {}, {}, {}
for m in re.finditer(r"8'h([0-9A-F]{2}):\s*(begin(.*?)end|dm=(MD_\w+);)", body):
    code = int(m.group(1), 16)
    text = m.group(2)
    for k, d in (('dm', mode), ('dc', cls), ('dp', op)):
        mm = re.search(k + r'=(\w+);', text)
        if mm:
            d[code] = mm.group(1)

out = []
for code in range(256):
    parts = []
    if code in mode: parts.append('mode[%03XH] := %s' % (code, mode[code].lower().replace('md_', 'md')))
    if code in cls: parts.append('cls[%03XH] := %s' % (code, cls[code].lower().replace('cl_', 'cl')))
    if code in op: parts.append('op[%03XH] := %s' % (code, op[code].lower().replace('op_', 'op')))
    if parts:
        out.append('    ' + '; '.join(parts) + ';')
print('\n'.join(out))

# mnemonics, in opcode order
mn = ("BRK ORA COP ORA TSB ORA ASL ORA PHP ORA ASL PHD TSB ORA ASL ORA "
      "BPL ORA ORA ORA TRB ORA ASL ORA CLC ORA INC TCS TRB ORA ASL ORA "
      "JSR AND JSL AND BIT AND ROL AND PLP AND ROL PLD BIT AND ROL AND "
      "BMI AND AND AND BIT AND ROL AND SEC AND DEC TSC BIT AND ROL AND "
      "RTI EOR WDM EOR MVP EOR LSR EOR PHA EOR LSR PHK JMP EOR LSR EOR "
      "BVC EOR EOR EOR MVN EOR LSR EOR CLI EOR PHY TCD JML EOR LSR EOR "
      "RTS ADC PER ADC STZ ADC ROR ADC PLA ADC ROR RTL JMP ADC ROR ADC "
      "BVS ADC ADC ADC STZ ADC ROR ADC SEI ADC PLY TDC JMP ADC ROR ADC "
      "BRA STA BRL STA STY STA STX STA DEY BIT TXA PHB STY STA STX STA "
      "BCC STA STA STA STY STA STX STA TYA STA TXS TXY STZ STA STZ STA "
      "LDY LDA LDX LDA LDY LDA LDX LDA TAY LDA TAX PLB LDY LDA LDX LDA "
      "BCS LDA LDA LDA LDY LDA LDX LDA CLV LDA TSX TYX LDY LDA LDX LDA "
      "CPY CMP REP CMP CPY CMP DEC CMP INY CMP DEX WAI CPY CMP DEC CMP "
      "BNE CMP CMP CMP PEI CMP DEC CMP CLD CMP PHX STP JML CMP DEC CMP "
      "CPX SBC SEP SBC CPX SBC INC SBC INX SBC NOP XBA CPX SBC INC SBC "
      "BEQ SBC SBC SBC PEA SBC INC SBC SED SBC PLX XCE JSR SBC INC SBC").split()
assert len(mn) == 256
print('    mnem := "%s";' % ''.join(mn))
