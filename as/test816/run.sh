#!/bin/sh
# The assembler compiled for the 65C816, run on OS16 under em16.
#
#   sh run.sh [-v]
#
# Compiles the sources of ../src with oc816 against OS16's kernel (its
# Files and Out; Env, here, gives the arguments, which Seed sets) and
# boots OS16 on em16 -fpga from a floppy with sample.s, the assembler's
# modules and RUN.TXT: Seed, AS (which assembles sample.s into the files
# sample.bin and sample.lst on the floppy) and Dump (which prints them).
# The output file and the listing must equal those of the host assembler
# ../../bin/as. Name the tools with OC816, EM16, AS and OS16B (OS16's
# build directory: cd ../../../OS16 && make first).

cd "$(dirname "$0")" || exit 1
abs() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }
OC816=$(abs "${OC816:-../../../../oc/self/s816/oc816}")
EM16=$(abs "${EM16:-../../bin/em16}")
AS=$(abs "${AS:-../../bin/as}")
OS16B=$(abs "${OS16B:-../../../OS16/build}")
for t in "$OC816" "$EM16" "$AS"; do
  [ -x "$t" ] || { echo "test816 skipped: $t not found"; exit 0; }
done
[ -f "$OS16B/KERNEL.IMG" ] || { echo "test816 skipped: no OS16 kernel in $OS16B (cd ../../../OS16 && make)"; exit 0; }
KERNEL=$(cat "$OS16B/KERNEL.TXT")

MODS="ASC ASH ASS ASB ASG ASL ASI ASP ASO"
rm -rf out; mkdir -p out/host
cp Env.Mod Dump.Mod ../src/*.Mod sample.s out/
python3 mkseed.py sample.s sample.bin && mv Seed.Mod out/
cd out || exit 1
for k in $KERNEL; do cp "$OS16B/$k.smb" .; done
cp "$OS16B/KERNEL.IMG" "$OS16B/boot.rom" .

# compile, in order of import
for m in Env $MODS Seed AS Dump; do
  if ! "$OC816" $m.Mod -s > $m.log 2>&1 || grep -q "  pos " $m.log; then
    echo "FAIL: oc816 $m.Mod"; grep -E "pos|rror" $m.log | head; exit 1
  fi
done
[ "$1" = "-v" ] && ls -l *.816 | awk '{ printf "  %-10s %6d bytes\n", $NF, $5 }'

# run: Startup loads Seed, which sets the arguments, AS, which assembles,
# and Dump, which prints the results
python3 ../../../../OS16/tools/mkfloppy.py -d . -x "$(echo $KERNEL | tr ' ' ,)" -m Seed -m AS -m Dump \
  -n "RUN.TXT=Seed AS Dump" -S KERNEL.IMG boot.img sample.s || exit 1
echo "" | perl -e 'alarm 300; exec @ARGV' "$EM16" -fpga -bootrom boot.rom -disk0 boot.img 2>&1 | tr -d '\r' > em16.log
sed -n '/^--- output$/,/^--- listing$/p' em16.log | sed '1d;$d' > sample.hex
sed -n '/^--- listing$/,/^--- end$/p' em16.log | sed '1d;$d' > sample.lst

# the same on the host
( cd host && cp ../sample.s . && "$AS" -o sample.bin sample.s > as.log 2>&1 &&
  xxd -p -c 16 sample.bin > sample.hex )

ok=1
[ -s sample.hex ] || { ok=0; echo "  no output from the emulator (see test816/out/em16.log)"; }
cmp -s sample.hex host/sample.hex || { ok=0; echo "  output differs"; }
cmp -s sample.lst host/sample.lst || { ok=0; echo "  listing differs"; }
if [ $ok = 1 ]; then echo "test816 passed: $(wc -c < host/sample.bin | tr -d ' ') bytes assembled under em16 match the host"
else echo "test816 FAILED"; exit 1
fi
