#!/usr/bin/env python3
"""Write the opcode dispatch of EmCPU.Mod from em16-c/src/emu816.cpp.

The three switch statements of step_wdc, step_rockwell and step_l28 become
the CASE statements of DispatchWDC, DispatchRockwell and DispatchL28: each
"case 0xNN: op_xxx(am_yyy()); break;" an arm "0NNH: Xxx(Yyy())". Run once
when the port was made; prints the procedures, which were pasted into
EmCPU.Mod.
"""
import re, sys

def name(s, prefix):
    s = s[len(prefix):]
    parts = s.split('_')
    return ''.join(p[:1].upper() + p[1:] for p in parts)

src = open(sys.argv[1]).read()
out = []
for proc, title in (('step_wdc', 'WDC'), ('step_rockwell', 'Rockwell'), ('step_l28', 'L28')):
    i = src.index('void emu816::' + proc)
    j = src.index('\n}', i)
    body = src[i:j]
    cases = re.findall(r'case 0x([0-9a-fA-F]{2}):\s*op_([a-z0-9_]+)\(([^;]*)\);\s*break;', body)
    assert len(cases) == 256, (proc, len(cases))
    out.append('  PROCEDURE Dispatch%s(op: INTEGER);' % title)
    out.append('    VAR n, ea: INTEGER;')
    out.append('  BEGIN')
    out.append('    CASE op OF')
    arms = []
    for code, op, args in cases:
        opn = name('op_' + op, 'op_')
        args = [a.strip() for a in re.split(r',\s*(?![^()]*\))', args)] if args.strip() else []
        conv = []
        for a in args:
            m = re.fullmatch(r'am_([a-z]+)\(\)', a)
            conv.append(name('am_' + m.group(1), 'am_') if m else a)
        label = '0%sH' % code.upper() if code.upper()[0] in 'ABCDEF' else '%sH' % code.upper()
        if len(conv) == 3:          # BBR/BBS: bit, zero page byte, branch target, in this order
            stmt = 'n := %s(); ea := %s(); %s(%s, n, ea)' % (conv[1], conv[2], opn, conv[0])
        elif len(conv) == 2:
            stmt = '%s(%s, %s())' % (opn, conv[0], conv[1])
        else:
            stmt = '%s(%s())' % (opn, conv[0])
        arms.append('      %s: %s' % (label, stmt))
    out.append('\n    | '.join(a if k == 0 else a.strip() for k, a in enumerate(arms)))
    out.append('    END')
    out.append('  END Dispatch%s;' % title)
    out.append('')
print('\n'.join(out))
