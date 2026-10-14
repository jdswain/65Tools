#!/bin/sh
# The assembler compiled for the 65C816, run under em16.
#
#   sh run.sh [-v]
#
# Compiles the sources of ../src with oc816 against the small runtime in
# this directory (files in memory, arguments set by a module), loads the
# lot into em16 and has it assemble sample.s. The output file and the
# listing it produces must equal those of the host assembler ../../bin/as.
# Name the tools with OC816, EM16 and AS.

cd "$(dirname "$0")" || exit 1
abs() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }
OC816=$(abs "${OC816:-../../../../oc/self/s816/oc816}")
EM16=$(abs "${EM16:-../../bin/em16}")
AS=$(abs "${AS:-../../bin/as}")
for t in "$OC816" "$EM16" "$AS"; do
  [ -x "$t" ] || { echo "test816 skipped: $t not found"; exit 0; }
done

RUNTIME="Out Files Env"
MODS="ASC ASH ASS ASB ASG ASL ASI ASP ASO"
mkdir -p out/host
cp Out.Mod Files.Mod Env.Mod Dump.Mod ../src/*.Mod sample.s out/
python3 mkseed.py sample.s sample.bin && mv Seed.Mod out/
cd out || exit 1

# compile, in order of import
for m in $RUNTIME $MODS Seed AS Dump; do
  if ! "$OC816" $m.Mod -s > $m.log 2>&1; then
    echo "FAIL: oc816 $m.Mod"; grep -E "pos|rror" $m.log | head; exit 1
  fi
done
[ "$1" = "-v" ] && ls -l *.816 | awk '{ printf "  %-10s %6d bytes\n", $NF, $5 }'

# run: the modules initialise in the order given, so Seed prepares the
# source and the arguments, AS assembles, Dump prints the results
LOAD=""
for m in $RUNTIME $MODS Seed AS Dump; do LOAD="$LOAD $m.816"; done
echo "" | perl -e 'alarm 120; exec @ARGV' "$EM16" $LOAD > em16.log 2>&1
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
