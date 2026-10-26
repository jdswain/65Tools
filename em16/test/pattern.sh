#!/bin/sh
# The blitter's patterns under em16 -fpga: test/pattern.s, a boot ROM, draws
# with them and prints what it drew; a model here, which knows only the
# definition (rtl/blitter.v of the Verilog repository), must agree.
cd "$(dirname "$0")"
AS=../../bin/as; EM=../../bin/em16
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
"$AS" -o "$work/pattern.bin" pattern.s > /dev/null || exit 1
perl -e 'alarm 20; exec @ARGV' "$EM" -fpga -bootrom "$work/pattern.bin" < /dev/null 2> /dev/null |
  tr -d '\r' | grep -aE '^ctl |^[0-9A-F]{64}$|^pattern: ' > "$work/out"
python3 - "$work/out" <<'END'
import sys
pat = bytes.fromhex('1E9C35A99047C2D8 6BF02983 5AE907B4 99127DC648A3F90E D1698F24B75CE39A'.replace(' ', ''))
W = 640
pix = {}                                # (x, y) -> pixel, of the 64 x 12 corner
for y in range(12):
    for i in range(320):
        b = (3 + 7 * (y * 320 + i)) & 255
        pix[2 * i, y], pix[2 * i + 1, y] = b & 15, b >> 4
def rop(op, s, d):
    return sum(((op >> (2 * (1 - (s >> b & 1)) + (1 - (d >> b & 1)))) & 1) << b for b in range(4))
# x, y, width, height, op, transparent colour or None, PAT_Y
for x0, y0, w, h, op, key, py in ((3, 0, 21, 3, 3, None, 5), (1, 3, 6, 2, 7, None, 0),
                                  (7, 5, 50, 4, 6, None, 3), (2, 9, 33, 3, 4, None, 7),
                                  (40, 0, 17, 12, 3, 9, 2)):
    for y in range(h):
        r = (py + y) & 7
        for x in range(x0, x0 + w):
            b = pat[4 * r + (x & 7) // 2]
            s = b >> 4 if x & 1 else b & 15
            if s != key:
                pix[x, y0 + y] = rop(op, s, pix[x, y0 + y])
want = ['ctl 0806%02X%02X' % (pat[0], pat[31])] + \
    [''.join('%X%X' % (pix[2 * i + 1, y], pix[2 * i, y]) for i in range(32)) for y in range(12)] + \
    ['pattern: done']
got = open(sys.argv[1]).read().split('\n')[:-1]
if got == want:
    print('pattern: ok'); sys.exit(0)
for i, (g, w) in enumerate(zip(got + [''] * 20, want)):
    if g != w: print(f'line {i}: got  {g}\n        want {w}')
print('pattern: fail'); sys.exit(1)
END
