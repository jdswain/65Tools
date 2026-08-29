#!/usr/bin/env python3
"""MakeROM — relocate a single dependency-free .816 module into a boot ROM image.

The module must import only SYSTEM (no cross-module imports, so no import
fixups). Code goes to a fixed ROM base ($E000, or $C000 for 16 KB); the module's
variables/strings/TDs go to a fixed RAM var base. A ~41-byte reset stub (the
only machine code) sets native mode + stack, copies the string/TD data image
from ROM to RAM, zeroes the BSS, and JMLs the module entry; the module's own
Header then sets SB and runs its body — pure Oberon from there.

Usage: makerom.py Boot.816 boot.rom [rom_base=0xE000] [ram_var=0x1000] [size=8192]
"""
import sys

def rd2(b, o): return b[o] | (b[o+1] << 8)
def rd4(b, o): return b[o] | (b[o+1] << 8) | (b[o+2] << 16) | (b[o+3] << 24)

def parse816(d):
    o = 0
    e = d.index(0, o); name = d[o:e].decode(); o = e + 1
    o += 4                                    # key
    o += 1                                    # version
    o += 4                                    # size
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
    o += (nofent - 1) * 4                     # export values
    while rd4(d, o) != 0xFFFFFFFF: o += 4     # pointer map, -1 terminated
    o += 4
    o += 12                                   # fixorgP/D/T
    tdFixC = rd4(d, o); o += 4; o += tdFixC * 4
    vtFixC = rd4(d, o); o += 4; o += vtFixC * 8
    relCount = rd4(d, o); o += 4
    relocs = [rd4(d, o + 4*i) for i in range(relCount)]
    if any(nm for nm in []):
        pass
    return dict(name=name, tdSize=tdSize, td=td, varsize=varsize, strSize=strSize,
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

STUB_SIZE = 43

def build_stub(var_base, varsize, str_src, str_dst, strSize, entry):
    s = bytearray()
    def b(*xs): s.extend(xs)
    lo = lambda x: x & 0xFF; hi = lambda x: (x >> 8) & 0xFF
    b(0x18, 0xFB)              # CLC XCE            -> native mode
    b(0xC2, 0x30)              # REP #$30           16-bit A/X/Y
    b(0xA9, 0xFF, 0x01, 0x1B)  # LDA #$01FF; TCS    stack
    b(0xE2, 0x20)              # SEP #$20           8-bit A (X/Y stay 16-bit)
    b(0xA2, 0x00, 0x00)        # LDX #0
    z = len(s)
    b(0x9E, lo(var_base), hi(var_base))  # STZ var_base,X
    b(0xE8)                    # INX
    b(0xE0, lo(varsize), hi(varsize))    # CPX #varsize
    b(0xD0, (z - (len(s)+2)) & 0xFF)     # BNE z
    b(0xA2, 0x00, 0x00)        # LDX #0
    c = len(s)
    b(0xBD, lo(str_src), hi(str_src))    # LDA str_src,X  (ROM)
    b(0x9D, lo(str_dst), hi(str_dst))    # STA str_dst,X  (RAM)
    b(0xE8)                    # INX
    b(0xE0, lo(strSize), hi(strSize))    # CPX #strSize
    b(0xD0, (c - (len(s)+2)) & 0xFF)     # BNE c
    b(0xC2, 0x30)              # REP #$30  -> 16-bit A/X/Y (Oberon code is longa/longi=on)
    b(0x5C, lo(entry), hi(entry), (entry >> 16) & 0xFF)  # JML entry
    assert len(s) == STUB_SIZE, len(s)
    return s

def main():
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(1)
    infile, outfile = sys.argv[1], sys.argv[2]
    rom_base = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0xE000
    ram_var  = int(sys.argv[4], 0) if len(sys.argv) > 4 else 0x1000
    rom_size = int(sys.argv[5], 0) if len(sys.argv) > 5 else 8192

    m = parse816(bytearray(open(infile, 'rb').read()))
    code_base = rom_base + STUB_SIZE
    # Data image (strings then TDs) sits in ROM right after the code; the stub
    # copies it to RAM at var_base+varsize (v2 deferred layout: vars, str, TD).
    data_img = bytes(m['strdata']) + bytes(m['td'])
    str_src  = code_base + m['codeLen']
    str_dst  = ram_var + m['varsize']
    entry    = code_base + m['entry']

    relocate(m['code'], m['relocs'], code_base, ram_var)
    stub = build_stub(ram_var, m['varsize'], str_src, str_dst, len(data_img), entry)

    rom = bytearray([0xFF] * rom_size)
    rom[0:STUB_SIZE] = stub
    rom[STUB_SIZE:STUB_SIZE + m['codeLen']] = m['code']
    off = STUB_SIZE + m['codeLen']
    rom[off:off + len(data_img)] = data_img
    used = off + len(data_img)
    if used > rom_size - 6:
        raise SystemExit("image (%d) overflows ROM (%d)" % (used, rom_size))
    # vectors: NMI/RESET/IRQ -> the reset stub at rom_base
    for v in (rom_size - 6, rom_size - 4, rom_size - 2):
        rom[v] = rom_base & 0xFF; rom[v+1] = (rom_base >> 8) & 0xFF

    open(outfile, 'wb').write(rom)
    print("MakeROM: %s -> %s" % (m['name'], outfile))
    print("  ROM  $%04X  stub %dB, code %dB @ $%04X, data %dB @ $%04X, used %d/%d"
          % (rom_base, STUB_SIZE, m['codeLen'], code_base, len(data_img), str_src, used, rom_size))
    print("  vars @ $%04X (%dB)  entry $%04X  reset vector -> $%04X"
          % (ram_var, m['varsize'], entry, rom_base))

if __name__ == '__main__':
    main()
