#!/bin/sh
# The core's banked direct page and stack under em16 -fpga: banked.s of
# the Verilog repository, which the core's test bench runs too (make
# banked there), must report every check passed.
cd "$(dirname "$0")"
AS=../../bin/as; EM=../../bin/em16; SRC=../../../Verilog65C816/banked.s
[ -f "$SRC" ] || { echo "banked: $SRC not found, skipped"; exit 0; }
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
"$AS" -D BENCH=0 -o "$work/banked.bin" "$SRC" > /dev/null || exit 1
out=$(perl -e 'alarm 10; exec @ARGV' "$EM" -fpga -bootrom "$work/banked.bin" < /dev/null 2> /dev/null |
  tr -d '\r' | grep -a '^banked:')
echo "${out:-banked: no answer}"
[ "$out" = "banked: ok" ]
