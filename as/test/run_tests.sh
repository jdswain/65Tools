#!/bin/sh
# Regression tests of the 65xx assembler.
#
#   sh run_tests.sh [path/to/as]          run the tests
#   sh run_tests.sh [path/to/as] -update  accept the current output as expected
#
# Every case assembles a source of this directory into out/ and compares
# the files it produces with those in expected/. The expected output of
# the sources taken from as-c/test was checked against the C assembler.

cd "$(dirname "$0")" || exit 1
AS=${1:-../../bin/as}
UPDATE=$2
mkdir -p out expected
pass=0; fail=0

# check NAME FILE...: compare out/FILE with expected/FILE
check() {
  name=$1; shift; ok=1
  for f in "$@"; do
    if [ "$UPDATE" = "-update" ]; then cp "out/$f" "expected/$f"
    elif ! cmp -s "out/$f" "expected/$f"; then ok=0; echo "  $f differs"
    fi
  done
  if [ $ok = 1 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $name"; fi
}

# run NAME ARGS...: assemble, keeping what is printed in out/NAME.log
run() {
  name=$1; shift
  "$AS" "$@" > "out/$name.log" 2>&1
  echo "exit $?" >> "out/$name.log"
}

for t in 816 branch bss C19 iopmon operators test_longa2; do
  run $t -o out/$t.bin $t.s
  check $t $t.bin $t.log
done

# the text formats carry addresses
for ext in bin tim hex s19 s28 s37 mem; do
  run wozmon-$ext -o out/wozmon.$ext wozmon.s
  check wozmon.$ext wozmon.$ext
done

# Oberon modules, with their symbol files
for t in MathLib TestAsm TestReloc TestImport TestImport6; do
  run $t -o out/$t.816 $t.s
  check $t $t.816 $t.smb $t.log
done
run MathLib-legacy -legacy -o out/MathLibV1.816 MathLib.s
check MathLib-legacy MathLibV1.816 MathLibV1.smb

# ELF
run elf -o out/features features.s -DDEBUG=0
check elf features
run obj -o out/features.o features.s -DDEBUG=0
check obj features.o

# the language: macros, conditions, include, data; and the listing
run features -DDEBUG=0 -o out/features.bin features.s
cp features.lst out/features.lst
check features features.bin features.lst features.log

# every message of the passes, and a failing exit status
run errors -o out/errors.bin errors.s
check errors errors.log
if [ -f out/errors.bin ]; then fail=$((fail + 1)); echo "FAIL errors: output written"; fi

# Round trip through the Oberon compiler and the emulator: oc816 must
# accept the symbol file the assembler writes, and the loader the module.
# This is what catches the two drifting apart. Skipped if either tool is
# not built; name them with OC816 and EM16.
OC816=${OC816:-../../../../oc/self/s816/oc816}
EM16=${EM16:-../../bin/em16}
OUTMOD=../../oc/test/Out.Mod
if [ "$UPDATE" = "-update" ]; then :
elif [ -x "$OC816" ] && [ -x "$EM16" ] && [ -f "$OUTMOD" ]; then
  OC816=$(cd "$(dirname "$OC816")" && pwd)/$(basename "$OC816")
  EM16=$(cd "$(dirname "$EM16")" && pwd)/$(basename "$EM16")
  mkdir -p out/rt
  cp "$OUTMOD" RoundTripTest.Mod out/rt/
  run roundtrip -o out/rt/RoundTrip.816 RoundTrip.s
  ( cd out/rt &&
    "$OC816" Out.Mod -s && "$OC816" RoundTripTest.Mod -s &&
    echo "" | perl -e 'alarm 20; exec @ARGV' "$EM16" Out.816 RoundTrip.816 RoundTripTest.816
  ) > out/roundtrip.run 2>&1
  if grep -qx 42 out/roundtrip.run && grep -qx 43 out/roundtrip.run; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL roundtrip (see test/out/roundtrip.run)"
  fi
else echo "roundtrip skipped: oc816 or em16 not found"
fi

rm -f ./*.lst
echo "$pass passed, $fail failed"
[ $fail = 0 ]
