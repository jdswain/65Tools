#!/usr/bin/env python3
"""MakePayload — relocate a single dependency-free .816 into a RAM payload image
that Boot.Mod (B3) loads off the floppy and SYSTEM.EXECs.

The module must import only SYSTEM (no cross-module fixups). Code is relocated to
a RAM code base, its vars/strings/TDs to a RAM var base — both in bank 0, so all
addresses are 16-bit. Bases must sit ABOVE the boot loader's own vars (Boot uses
$1000..~$2300) and clear of the $0800 FDC window.

Output container (all little-endian 16-bit, bank 0):
    codeBase  codeLen  varBase  varSize  dataLen  entry
    code[codeLen]
    data[dataLen]      (strings then TDs; Boot copies to varBase+varSize)

Boot copies code->codeBase, data->varBase+varSize, zeros varBase..+varSize,
then SYSTEM.EXEC(entry, 0). The payload's own Header sets SB and its body runs.

Usage: makepayload.py In.816 out.pld [code_base=0x4000] [var_base=0x8000]
"""
import sys

def rd2(b, o): return b[o] | (b[o+1] << 8)
def rd4(b, o): return b[o] | (b[o+1] << 8) | (b[o+2] << 16) | (b[o+3] << 24)
def w2(v): return bytes((v & 0xFF, (v >> 8) & 0xFF))

def parse816(d):
    o = 0
    e = d.index(0, o); name = d[o:e].decode(); o = e + 1
    o += 4 + 1 + 4                            # key, version, size
    while d[o] != 0:                          # imports {name\0, val4}*
        e = d.index(0, o); o = e + 1 + 4
    o += 1
    tdSize = rd4(d, o); o += 4; td = d[o:o+tdSize]; o += tdSize
    varsize = rd4(d, o); o += 4
    strSize = rd4(d, o); o += 4; strdata = d[o:o+strSize]; o += strSize
    codeLen = rd4(d, o); o += 4; code = bytearray(d[o:o+codeLen]); o += codeLen
    while d[o] != 0:                          # export procs {name\0, val4}*
        e = d.index(0, o); o = e + 1 + 4
    o += 1
    nofent = rd4(d, o); o += 4
    entry = rd4(d, o); o += 4
    o += (nofent - 1) * 4                      # export values
    while rd4(d, o) != 0xFFFFFFFF: o += 4      # pointer map, -1 terminated
    o += 4
    o += 12                                    # fixorgP/D/T
    tdFixC = rd4(d, o); o += 4; o += tdFixC * 4
    vtFixC = rd4(d, o); o += 4; o += vtFixC * 8
    relCount = rd4(d, o); o += 4
    relocs = [rd4(d, o + 4*i) for i in range(relCount)]
    return dict(name=name, td=td, varsize=varsize, strSize=strSize,
                strdata=strdata, codeLen=codeLen, code=code, entry=entry, relocs=relocs)

def relocate(code, relocs, code_base, var_base):
    for v in relocs:
        addr = v & 0xFFFF
        is_bank = (v & 0x80000000) != 0
        op = code[addr]
        if is_bank:                                   # data bank of a pointer -> 0
            if op == 0xA9: code[addr+1] = 0; code[addr+2] = 0
            continue
        if op == 0x20:                                # JSR abs (intra, in-bank)
            t = code_base + rd2(code, addr+1)
            code[addr+1] = t & 0xFF; code[addr+2] = (t >> 8) & 0xFF
        elif op == 0x22:                              # JSL long (intra: bank byte 0)
            if code[addr+3] == 0:
                t = code_base + rd2(code, addr+1)
                code[addr+1] = t & 0xFF; code[addr+2] = (t >> 8) & 0xFF
                code[addr+3] = (t >> 16) & 0xFF
            else:
                raise SystemExit("import JSL in a supposedly dependency-free module")
        elif op == 0xA9:                              # LDA #imm  (var base)
            if rd2(code, addr+1) == 0:
                code[addr+1] = var_base & 0xFF; code[addr+2] = (var_base >> 8) & 0xFF
            else:
                raise SystemExit("imported var base in a dependency-free module")
        else:
            raise SystemExit("unhandled reloc opcode $%02X at $%04X" % (op, addr))

def main():
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(1)
    infile, outfile = sys.argv[1], sys.argv[2]
    code_base = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x4000
    var_base  = int(sys.argv[4], 0) if len(sys.argv) > 4 else 0x8000

    m = parse816(bytearray(open(infile, 'rb').read()))
    for label, val in (("code_base", code_base), ("var_base", var_base),
                       ("entry", code_base + m['entry'])):
        if val > 0xFFFF:
            raise SystemExit("%s $%X exceeds bank 0" % (label, val))

    relocate(m['code'], m['relocs'], code_base, var_base)
    data_img = bytes(m['strdata']) + bytes(m['td'])
    entry = code_base + m['entry']

    out = bytearray()
    out += w2(code_base) + w2(m['codeLen']) + w2(var_base)
    out += w2(m['varsize']) + w2(len(data_img)) + w2(entry)
    out += m['code']
    out += data_img
    open(outfile, 'wb').write(out)

    print("MakePayload: %s -> %s" % (m['name'], outfile))
    print("  code $%04X (%dB)  vars $%04X (%dB)  data %dB @ $%04X  entry $%04X"
          % (code_base, m['codeLen'], var_base, m['varsize'],
             len(data_img), var_base + m['varsize'], entry))
    print("  file %d bytes" % len(out))

if __name__ == '__main__':
    main()
