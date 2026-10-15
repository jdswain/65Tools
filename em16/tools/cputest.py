#!/usr/bin/env python3
"""Write an assembler program that executes every opcode of a processor
of em16 with varied registers, flags and memory, for comparing the
traces (em16 -t) of the C++ and the Oberon em16 (test/compare.sh).

    python3 tools/cputest.py wdc|rockwell|l28 seed [n16|n8|n168|n816|e] > test.s

The addressing modes come from the opcode tables of em16-c's emu816.cpp.
Before each instruction the registers, the flags (decimal included), the
direct page and the stack are set; the instruction is written as bytes,
its operand pointing into a data area. Instructions that change the flow
of control or the register widths are left out, as are those that would
wait or stop; branches are tried with an offset of zero, taken or not.
"""
import random, re, sys, os

here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, '../../em16-c/src/emu816.cpp')).read()
cpu = sys.argv[1]
random.seed(int(sys.argv[2]) if len(sys.argv) > 2 else 1)

proc = {'wdc': 'step_wdc', 'rockwell': 'step_rockwell', 'l28': 'step_l28'}[cpu]
i = src.index('void emu816::' + proc)
body = src[i:src.index('\n}', i)]
table = {}
for code, op, args in re.findall(r'case 0x([0-9a-fA-F]{2}):\s*op_([a-z0-9_]+)\(([^;]*)\);\s*break;', body):
    modes = re.findall(r'am_([a-z]+)\(\)', args)
    table[int(code, 16)] = (op, modes)

# never executed: flow of control, mode changes, waiting
skip = {'brk', 'cop', 'jmp', 'jsr', 'jsl', 'rts', 'rtl', 'rti', 'stp', 'wai', 'wdm',
        'xce', 'rep', 'sep', 'plp', 'brk_l28', 'jsr_l28', 'rts_l28', 'jsb', 'jpi',
        'tip', 'nxt', 'lii', 'pli', 'pia', 'bar', 'bas', 'mvn', 'mvp'}
branches = {'bcc', 'bcs', 'beq', 'bne', 'bmi', 'bpl', 'bvc', 'bvs', 'bra', 'brl', 'bbs', 'bbr'}

def size(mode, m16, x16):
    return {'absl': 2, 'absx': 2, 'absy': 2, 'absi': 2, 'abxi': 2, 'abil': 2,
            'alng': 3, 'alnx': 3, 'dpag': 1, 'dpgx': 1, 'dpgy': 1, 'dpgi': 1, 'dpix': 1,
            'dpiy': 1, 'diix': 1, 'dpil': 1, 'dily': 1, 'impl': 0, 'acc': 0, 'immb': 1,
            'immw': 2, 'immm': 2 if m16 else 1, 'immx': 2 if x16 else 1, 'lrel': 2,
            'rela': 1, 'srel': 1, 'sriy': 1}[mode]

DP = 0x80 if cpu == 'l28' else 0
extra = {'sti': 1, 'rba': 2, 'sba': 2}     # operand bytes the operation reads itself

def operand(mode, n):
    if mode in ('rela', 'lrel'):
        return [0] * n                        # branch to the next instruction
    if mode in ('absl', 'absx', 'absy'):
        return [random.randrange(0, 0x80), 0x30]
    if mode in ('absi', 'abxi', 'abil'):
        return [DP + 0x40, 0x00]              # pointers kept in page 0 at $40
    if mode in ('alng', 'alnx'):
        return [random.randrange(0, 0x80), 0x30, 0x00]
    if mode in ('srel', 'sriy'):
        return [random.randrange(1, 8)]
    if mode.startswith('dp') or mode == 'diix' or mode == 'dily':
        return [DP + random.randrange(0, 0x20) * 2]
    return [random.randrange(0, 256) for _ in range(n)]

out = []
def emit(s): out.append('                ' + s)

def pointers8():
    """the pointers in page zero, into the data area; on the L28 page zero
    below $80 holds I/O, so they are above"""
    for k in range(DP, DP + 0x48, 2):
        emit('lda #$%02X' % random.randrange(0, 256)); emit('sta $%02X' % k)
        emit('lda #$%02X' % random.randrange(0x30, 0x38)); emit('sta $%02X' % (k + 1))
    emit('lda #0')
    for k in range(DP + 0x42, DP + 0x4A, 2):
        emit('sta $%02X' % k)

def setup8():
    """registers, flags and stack, with 6502 instructions"""
    emit('ldx #$F0'); emit('txs')
    emit('lda #$%02X' % random.choice([0x30, 0x31, 0x32, 0x70, 0xB0, 0x38, 0x39, 0xF3, 0x3B, 0x71]))
    emit('pha'); emit('plp')
    emit('lda #$%X' % random.randrange(0, 0x100))
    emit('ldx #$%X' % random.randrange(0, 0x100))
    emit('ldy #$%X' % random.randrange(0, 0x100))

def setup(native, m16, x16):
    """registers, flags, direct page, data bank and stack"""
    if cpu != 'wdc':
        setup8(); return
    emit('rep #$30' if native else 'nop')
    emit('longa = on' if native else 'longa = off'); emit('longi = on' if native else 'longi = off')
    if native:
        emit('ldx #$07F0'); emit('txs'); emit('lda #0'); emit('tcd')
    else:
        emit('ldx #$F0'); emit('txs')
    emit('pea 0'); emit('plb'); emit('plb')
    if native:
        flags = (0 if m16 else 0x20) | (0 if x16 else 0x10)
        emit('sep #$30'); emit('rep #$%02X' % (0x30 - flags))
        emit('longa = %s' % ('on' if m16 else 'off')); emit('longi = %s' % ('on' if x16 else 'off'))
    emit('lda #$%X' % random.randrange(0, 0x10000 if m16 else 0x100))
    emit('ldx #$%X' % random.randrange(0, 0x100))
    emit('ldy #$%X' % random.randrange(0, 0x100))
    f = random.choice([0, 1, 2, 0x40, 0x80, 0x08, 0x09, 0xC3, 0x0B, 0x41])
    emit('rep #$CF'); emit('sep #$%02X' % f)

def pointers(native):
    """the pointers in page 0: into the data area at $3000-$38FF, bank 0;
    the four long ones at $40 have a zero bank byte"""
    if native:
        emit('rep #$30'); emit('longa = on'); emit('longi = on')
        emit('lda #0'); emit('tcd')
        for k in range(0, 0x48, 2):
            emit('lda #$%04X' % (random.randrange(0x30, 0x38) * 256 + random.randrange(0, 256))); emit('sta $%02X' % k)
        for k in range(0x42, 0x4A, 2):
            emit('stz $%02X' % k)
    else:
        pointers8()

def block(native, m16, x16):
    count = 0
    for op in range(256):
        name, modes = table[op]
        if name in skip:
            continue
        if count % 16 == 0:
            pointers(native and cpu == 'wdc')
        count += 1
        setup(native, m16, x16)
        if name in ('bbs', 'bbr'):
            bytes_ = [op, DP + random.randrange(0, 0x20) * 2, 0]
        else:
            n = sum(size(m, m16, x16) for m in modes)
            bytes_ = [op] + operand(modes[0] if modes else 'impl', n)
            bytes_ += [random.randrange(0x30, 0x38) for _ in range(extra.get(name, 0))]
        emit('data.b ' + ', '.join('$%02X' % b for b in bytes_))

hdr = {'wdc': '65C816', 'rockwell': 'R65C02', 'l28': 'C19'}[cpu]
out.append('                cpu = "%s"' % hdr)
out.append('                org = $8000')
out.append('start:')
if cpu == 'wdc':
    # one program per mode, as all of them do not fit below $FFFC:
    # native with A and X/Y of 16/16, 8/8, 16/8, 8/16 bits, emulation
    mode = sys.argv[3] if len(sys.argv) > 3 else 'n16'
    if mode == 'e':
        emit('sec'); emit('xce')
        block(False, False, False)
        emit('clc'); emit('xce')
    else:
        m16, x16 = {'n16': (True, True), 'n8': (False, False), 'n168': (True, False), 'n816': (False, True)}[mode]
        block(True, m16, x16)
    emit('jmp $0000')                         # PBR 0, PC 0: em16 stops
else:
    if cpu == 'rockwell':
        emit('data.b $38, $FB')               # SEC, XCE: em16 starts it in native mode
    block(False, False, False)
    out.append('done:           bra done')
out.append('                org = $3000')
for row in range(16):
    out.append('                data.b ' + ', '.join('$%02X' % random.randrange(0, 256) for _ in range(16)))
out.append('                org = $FFFC')
out.append('                data.w start, start')
print('\n'.join(out))
