#!/bin/sh
# A 20 MB SCSI disk in a real drive's time, em16 -fpga -scsitiming:
# test/hd.s, a boot ROM, waits from power on for the drive to answer and
# spin up, then times reads and a write by polling the 53C80. The image's
# blocks hold their own numbers. The checks are the drive's figures
# (EmSCSI.Mod): it answers a selection 1 s after power on and is NOT READY
# (02 04 01) until 5 s; 3600 rpm, a sector every 0.52 ms; a seek of d of
# its 320 cylinders 3 + 27 * sqrt(d / 320) ms; 0.5 ms a command; a 64K
# read-ahead; a write on the platters before its status. It prints the
# times in ms and "hd: ok".
cd "$(dirname "$0")"
AS=../../bin/as; EM=${EM:-../../bin/em16}
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
"$AS" -o "$work/hd.bin" hd.s > /dev/null || exit 1
python3 - "$work" <<'END'
import sys
with open(f'{sys.argv[1]}/hd.img', 'wb') as f:
    for lba in range(40960):
        f.write(bytes([lba & 255, lba >> 8]) + bytes(i & 255 for i in range(2, 512)))
END
perl -e 'alarm 60; exec @ARGV' "$EM" -fpga -scsitiming -bootrom "$work/hd.bin" -scsi "$work/hd.img" \
  < /dev/null 2> /dev/null | tr -d '\r' > "$work/out"
python3 - "$work/out" <<'END'
import math, re, sys
lines = [l.rstrip() for l in open(sys.argv[1], errors='replace').read().splitlines()]
bad = []
def line(prefix):
    for l in lines:
        if l.startswith(prefix): return l
    bad.append(f'no "{prefix}" line'); return ''
def ms(l):
    m = re.search(r'(?:took|at) ([0-9A-F]{4})$', l)
    return int(m.group(1), 16) / 10 if m else -1.0
def seek(d): return 3 + 27 * math.sqrt(d / 320)
rev, sec = 1000 / 60, 1000 / 60 / 32

first = line('first answer: ')
if 'status 02 ' not in first or not 1000 <= ms(first) < 1010: bad.append('the first answer: ' + first)
if line('sense: ') != 'sense: 06 29 00': bad.append('UNIT ATTENTION: ' + line('sense: '))
spin = line('spin-up: ')
m = re.match(r'spin-up: ([0-9A-F]{4}) not ready, sense 02 04 01 at', spin)
if not m or int(m.group(1), 16) == 0 or not 5000 <= ms(spin) < 5010: bad.append('the spin-up: ' + spin)
if line('capacity: ') != 'capacity: 00 00 9F FF 00 00 02 00': bad.append(line('capacity: '))

# each timed line: its data, and the least and most its time can be: the
# command's 0.5 ms, the seek, a revolution at most for the block to come
# round, and the polled transfer (under 5 ms a block)
xfer = 5
checks = [
    ('read 0: ',        '00 00 ',        0.5, 0.5 + rev + sec + xfer),
    ('read 1: ',        '01 00 ',        0.5, 0.5 + xfer),                         # in the buffer
    ('read 100: ',      '64 00 ',        0.5, 0.5 + 100 * sec + xfer),             # read ahead
    ('read 20000: ',    '20 4E ',        seek(155), 0.5 + seek(156) + rev + sec + xfer),
    ('read 20001 x64: ', '21 4E 60 4E ', 64 * sec, 64 * (sec + xfer)),
    ('write 40000: ',   '',              seek(156) + sec, 0.5 + seek(157) + xfer + rev + sec),
    ('read 40000: ',    'A5 A5 ',        rev - sec, rev + sec + xfer),             # once round again
    ('read 0 again: ',  '00 00 ',        seek(312), 0.5 + seek(312) + rev + sec + xfer),
    ('read 40959: ',    'FF 9F ',        seek(319), 0.5 + seek(319) + rev + sec + xfer),
]
print('hd: from power on, answering', ms(first), 'ms, ready', ms(spin), 'ms')
for name, data, lo, hi in checks:
    l = line(name); t = ms(l)
    if not l.startswith(name + 'status 00 ' + data) or not lo <= t <= hi:
        bad.append(f'{l} ({t} ms, not {lo:.1f} to {hi:.1f})')
    print(f'hd: {name:17}{t:6.1f} ms')
if lines[-1:] != ['hd: done'] and 'hd: done' not in lines: bad.append('no "hd: done"')
for b in bad: print('hd: wrong:', b)
print('hd: ok' if not bad else 'hd: fail')
sys.exit(1 if bad else 0)
END
