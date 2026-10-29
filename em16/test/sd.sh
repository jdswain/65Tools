#!/bin/sh
# The microSD slot under em16 -fpga -sd: test/sd.s, a boot ROM, starts the
# card, reads, writes and reads back blocks, and prints what it got; a
# model here, which knows only the SD spec's SPI mode and the controller's
# definition (rtl/sd_spi.v of the Verilog repository), must agree, and the
# blocks written must be in the image file. The "t17" line, a block read's
# cycles, is printed, not checked.
cd "$(dirname "$0")"
AS=../../bin/as; EM=../../bin/em16
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
"$AS" -o "$work/sd.bin" sd.s > /dev/null || exit 1
python3 -c "
import sys
open(sys.argv[1], 'wb').write(bytes((k * 37 + (k >> 9) * 11 + 5) & 255 for k in range(2048 * 512)))
" "$work/card.img"
perl -e 'alarm 20; exec @ARGV' "$EM" -fpga -bootrom "$work/sd.bin" -sd "$work/card.img" < /dev/null 2> /dev/null |
  tr -d '\r' | grep -aE '^[0-9A-F ]+$|^t17 |^sd: ' > "$work/out"
python3 - "$work/out" "$work/card.img" <<'END'
import sys
blocks = 2048
img = bytearray((k * 37 + (k >> 9) * 11 + 5) & 255 for k in range(blocks * 512))
def crc16(d):
    c = 0
    for b in d:
        c ^= b << 8
        for _ in range(8):
            c = ((c << 1) ^ 0x1021) if c & 0x8000 else c << 1
            c &= 0xFFFF
    return c
def blk(n): return img[n * 512:(n + 1) * 512]
def read(n):
    d = blk(n)
    return ' %s %04X %04X' % (d[:4].hex().upper(), sum(d) & 0xFFFF, crc16(d))
def write(n, seed):
    img[n * 512:(n + 1) * 512] = bytes((seed * (i + 1)) & 255 for i in range(512))
    return ' 05'
csize = blocks // 1024 - 1
csd = [0x40, 0x0E, 0x00, 0x32, 0x5B, 0x59, 0x00, (csize >> 16) & 0x3F, (csize >> 8) & 255,
       csize & 255, 0x7F, 0x80, 0x0A, 0x40, 0x00, 0x01]
want = ['090101000001AA', '0200C0FF8000', '00' + ''.join('%02X' % b for b in csd),
        '00' + read(1)]
want.append('00' + write(2, 5))
want.append('00' + read(2))
want.append('00' + read(3) + read(4) + '00')
w6, w7 = write(6, 3), write(7, 11)
want.append('00' + w6 + w7 + '00' + read(7))
got = open(sys.argv[1]).read().split('\n')[:-1]
t17 = [g for g in got if g.startswith('t17 ')]
body = [g for g in got if not g.startswith('t17 ')]
ok = body == want + ['sd: done']
card = open(sys.argv[2], 'rb').read()
if card != bytes(img):
    print('sd: the image file is not as written'); ok = False
if t17: print('sd: a block read takes $%s cycles' % t17[0][4:])
if ok:
    print('sd: ok'); sys.exit(0)
for i, (g, w) in enumerate(zip(body + [''] * 20, want + ['sd: done'])):
    if g != w: print(f'line {i}: got  {g}\n        want {w}')
print('sd: fail'); sys.exit(1)
END
