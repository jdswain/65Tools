#!/bin/sh
# The SoC's DMA engine under em16 -fpga: test/dma.s, a boot ROM, moves
# sectors between memory and the carrier's 82077AA and 53C80 by DMA and by
# pseudo-DMA, on a 1.44M floppy and a 5 MB SCSI disk whose blocks hold
# their own numbers; its output must match test/dma.expected, and the
# sectors it writes must land where they should.
cd "$(dirname "$0")"
AS=../../bin/as; EM=../../bin/em16
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
"$AS" -o "$work/dma.bin" dma.s > /dev/null || exit 1
python3 - "$work" <<'END'
import sys
for name, n in (('fd.img', 2880), ('sd.img', 10240)):
    with open(f'{sys.argv[1]}/{name}', 'wb') as f:
        for lba in range(n):
            f.write(bytes([lba & 255, lba >> 8]) + bytes(i & 255 for i in range(2, 512)))
END
perl -e 'alarm 20; exec @ARGV' "$EM" -fpga -bootrom "$work/dma.bin" -disk0 "$work/fd.img" \
  -scsi "$work/sd.img" < /dev/null 2> /dev/null |
  grep -av '^Executed \|^Overall CPU' | sed "s|$work/||" | tr -d '\r' > "$work/out"
[ -n "$DMA_OUT" ] && cp "$work/out" "$DMA_OUT"
fail=0
if diff dma.expected "$work/out"; then echo "dma: output ok"; else echo "dma: output differs"; fail=1; fi
python3 - "$work" <<'END' || fail=1
import sys
f = open(f'{sys.argv[1]}/fd.img', 'rb').read(); s = open(f'{sys.argv[1]}/sd.img', 'rb').read()
o = 198 * 512                       # C5 H1 R1
ok = f[o:o+512] == b'\xa5' * 512 and f[o-512] == 197 and f[o+512] == 199 \
     and s[7*512:8*512] == b'\x5a' * 512 and s[6*512] == 6 and s[8*512] == 8
print('dma: written sectors', 'ok' if ok else 'wrong'); sys.exit(0 if ok else 1)
END
exit $fail
