#!/bin/sh
# The blitter's colour expansion under em16 -fpga: test/expand.s, a boot ROM,
# draws 1-bit glyphs with it and prints what it drew; a model here, which
# knows only the definition (rtl/blitter.v of the Verilog repository), must
# agree.
cd "$(dirname "$0")"
AS=../../bin/as; EM=../../bin/em16
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
"$AS" -o "$work/expand.bin" expand.s > /dev/null || exit 1
perl -e 'alarm 20; exec @ARGV' "$EM" -fpga -bootrom "$work/expand.bin" < /dev/null 2> /dev/null |
  tr -d '\r' | grep -aE '^ctl |^[0-9A-F]{64}$|^expand: ' > "$work/out"
python3 - "$work/out" <<'END'
import sys
g = bytes.fromhex('708898A8C8887000 F82050D81E9C35A9 9047C2D86BF02983 5AE907B499127DC6'
                  '48A3F90ED1698F24 B75CE39AFF01803C C36618E7815AA50F F033CC55AA966900'.replace(' ', ''))
pix = {}                                # (x, y) -> pixel, of the 64 x 12 corner
for y in range(12):
    for i in range(320):
        b = (3 + 7 * (y * 320 + i)) & 255
        pix[2 * i, y], pix[2 * i + 1, y] = b & 15, b >> 4
def rop(op, s, d):
    return sum(((op >> (2 * (1 - (s >> b & 1)) + (1 - (d >> b & 1)))) & 1) << b for b in range(4))
# first line's x, y and glyph byte, the strides (lines, bytes), width, height,
# op, colour, background, transparent, fill
for x0, y0, a0, dy, sst, w, h, op, fg, bg, trans, fill in (
        (3, 11, 0x00, -1, 1, 5, 12, 3, 12, 5, 0, 0),
        (10, 0, 0x10, 1, 2, 13, 8, 3, 7, 0, 1, 0),
        (29, 8, 0x2A, -1, -2, 16, 6, 6, 15, 3, 0, 0),
        (48, 6, 0x31, 1, 3, 7, 5, 7, 10, 0, 1, 0),
        (58, 1, 0x00, 1, 1, 4, 3, 3, 9, 2, 0, 1)):
    for l in range(h):
        y, a = y0 + l * dy, a0 + l * sst
        for x in range(w):
            bit = g[a + x // 8] >> (7 - x % 8) & 1
            s = fg if fill or bit else bg
            if fill or not trans or bit:
                pix[x0 + x, y] = rop(op, s, pix[x0 + x, y])
want = ['ctl 12'] + \
    [''.join('%X%X' % (pix[2 * i + 1, y], pix[2 * i, y]) for i in range(32)) for y in range(12)] + \
    ['expand: done']
got = open(sys.argv[1]).read().split('\n')[:-1]
if got == want:
    print('expand: ok'); sys.exit(0)
for i, (g, w) in enumerate(zip(got + [''] * 20, want)):
    if g != w: print(f'line {i}: got  {g}\n        want {w}')
print('expand: fail'); sys.exit(1)
END
