#!/bin/sh
# The Mini816's TMS9118 and keyboard under em16 -mini816: test/mini816vdp.s
# checks the VDP's ports and flags ("vdp: ok"), scans the keyboard with
# keys held by -key, and sets up each display mode for -fbdump; a model
# here, which knows only the TMS9918A's definition, draws each frame from
# the same VRAM and must agree pixel for pixel.
cd "$(dirname "$0")"
AS=../../bin/as; EM=../../bin/em16
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
"$AS" -o "$work/vdp.bin" mini816vdp.s > /dev/null || exit 1
run() {
  printf "$1" > "$work/in"; shift
  perl -e 'alarm 30; exec @ARGV' "$EM" -mini816 -turbo -rom "$work/vdp.bin" "$@" < "$work/in" 2> /dev/null | tr -d '\r'
}
ok=0
flags=$(run f | grep -a '^vdp: ')
[ "$flags" = "vdp: ok" ] || { echo "mini816vdp: $flags"; ok=1; }
keys=$(run k -key 3,4 -key 15,4 -key 0,0 -key 7,7 -key 15,0 | grep -a '^keys:')
[ "$keys" = "keys: 00 34 77 F0 F4" ] || { echo "mini816vdp: $keys"; ok=1; }
for m in g h 2 3 m t b; do
  run $m -fbdump "$work/$m.ppm" > /dev/null
  python3 -I - "$work/$m.ppm" $m <<'END' || ok=1
import sys
path, mode = sys.argv[1], sys.argv[2]
REGS = {'g': (0x00, 0xC0, 0x06, 0x80, 0x00, 0x36, 0x07, 0xF4), 'h': (0x00, 0xC3, 0x06, 0x80, 0x00, 0x36, 0x07, 0x15),
        '2': (0x02, 0xC2, 0x0E, 0xFF, 0x03, 0x76, 0x03, 0x01), '3': (0x02, 0xC1, 0x0E, 0x9F, 0x00, 0x76, 0x03, 0x0C),
        'm': (0x00, 0xC9, 0x02, 0x00, 0x00, 0x20, 0x03, 0x0D), 't': (0x00, 0xD0, 0x02, 0x00, 0x00, 0x20, 0x03, 0xF5),
        'b': (0x00, 0x80, 0x06, 0x80, 0x00, 0x36, 0x07, 0x06)}
SPRITES = (20, 30, 1, 0x0F, 24, 34, 2, 0x00, 26, 36, 3, 0x08, 100, 250, 4, 0x8A, 100, 10, 5, 0x03,
           100, 60, 6, 0x0C, 100, 90, 7, 0x0D, 100, 120, 8, 0x0E, 0xF8, 200, 9, 0x09, 185, 245, 10, 0x07,
           0xD0, 0, 0, 0, 50, 50, 11, 0x02)
PAL = (0x000000, 0x000000, 0x21C842, 0x5EDC78, 0x5455ED, 0x7D76FC, 0xD4524D, 0x42EBF5,
       0xFC5554, 0xFF7978, 0xD4C154, 0xE6CE80, 0x21B03B, 0xC95BBA, 0xCCCCCC, 0xFFFFFF)
r = REGS[mode]
vram = bytearray(16384)
s = 1
for i in range(16384):
    s ^= (s << 7) & 0xFFFF
    s ^= s >> 9
    s ^= (s << 8) & 0xFFFF
    vram[i] = s & 0xFF
sat = (r[5] & 0x7F) << 7
vram[sat:sat + len(SPRITES)] = bytes(SPRITES)
nt, pg, spg = (r[2] & 15) << 10, (r[4] & 7) << 11, (r[6] & 7) << 11
fg7, bd = r[7] >> 4, r[7] & 15

def bits(b, n):                         # MSB first
    return [(b >> (n - 1 - k)) & 1 for k in range(n)]

def background(y):
    row = [0] * 256
    if r[1] & 0x10:                     # text
        for c in range(40):
            for k, on in enumerate(bits(vram[pg + 8 * vram[nt + 40 * (y // 8) + c] + y % 8], 8)[:6]):
                row[8 + 6 * c + k] = fg7 if on else bd
    elif r[1] & 0x08:                   # multicolour
        for c in range(32):
            b = vram[pg + 8 * vram[nt + 32 * (y // 8) + c] + 2 * ((y // 8) % 4) + (y % 8) // 4]
            row[8 * c:8 * c + 8] = [b >> 4] * 4 + [b & 15] * 4
    else:
        for c in range(32):
            name = vram[nt + 32 * (y // 8) + c]
            if r[0] & 2:                # Graphics II
                a = ((y // 64) << 11) | (name << 3) | (y % 8)
                p = vram[((r[4] & 4) << 11) | (a & (((r[4] & 3) << 11) | 0x7FF))]
                col = vram[((r[3] & 0x80) << 6) | (a & (((r[3] & 0x7F) << 6) | 0x3F))]
            else:
                p, col = vram[pg + 8 * name + y % 8], vram[(r[3] << 6) + name // 8]
            row[8 * c:8 * c + 8] = [col >> 4 if on else col & 15 for on in bits(p, 8)]
    return row

def sprites(y, row):
    size = 16 if r[1] & 2 else 8
    mag = 2 if r[1] & 1 else 1
    on = []
    for i in range(32):
        e = sat + 4 * i
        if vram[e] == 0xD0:
            break
        if (y - vram[e] - 1) & 0xFF < size * mag:
            on.append(e)
    for e in reversed(on[:4]):          # the lowest numbered drawn last, in front
        line = ((y - vram[e] - 1) & 0xFF) // mag
        x0 = vram[e + 1] - (32 if vram[e + 3] & 0x80 else 0)
        colour = vram[e + 3] & 15
        if size == 16:
            n = vram[e + 2] & 0xFC
            pat = bits(vram[spg + 8 * n + line], 8) + bits(vram[spg + 8 * n + 16 + line], 8)
        else:
            pat = bits(vram[spg + 8 * vram[e + 2] + line], 8)
        for k, b in enumerate(pat):
            for m in range(mag):
                x = x0 + k * mag + m
                if b and colour and 0 <= x < 256:
                    row[x] = colour

W, H, L, T = 288, 240, 16, 24
want = [[bd] * W for _ in range(H)]
for y in range(192):
    if r[1] & 0x40:
        row = background(y)
        if not r[1] & 0x10:
            sprites(y, row)
    else:
        row = [0] * 256
    want[T + y][L:L + 256] = [c or bd for c in row]
data = open(path, 'rb').read()
head = b'P6\n288 240\n255\n'
if not data.startswith(head) or len(data) != len(head) + W * H * 3:
    print(f'mini816vdp: mode {mode}: no frame ({len(data)} bytes)'); sys.exit(1)
px = data[len(head):]
bad = [(x, y) for y in range(H) for x in range(W)
       if int.from_bytes(px[3 * (y * W + x):3 * (y * W + x) + 3], 'big') != PAL[want[y][x]]]
if bad:
    print(f'mini816vdp: mode {mode}: {len(bad)} pixels differ, first at {bad[:4]}'); sys.exit(1)
END
done
[ $ok = 0 ] && echo "mini816vdp: ok (ports, flags, keys, 7 modes as the model)"
exit $ok
