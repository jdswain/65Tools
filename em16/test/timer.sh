#!/bin/sh
# The SoC's tick timer and interrupt status under em16 -fpga: test/timer.s,
# a boot ROM, must print "timer: ok".
cd "$(dirname "$0")"
AS=../../bin/as; EM=../../bin/em16
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
"$AS" -o "$work/timer.bin" timer.s > /dev/null || exit 1
out=$(perl -e 'alarm 20; exec @ARGV' "$EM" -fpga -bootrom "$work/timer.bin" < /dev/null 2> /dev/null |
  tr -d '\r' | grep -a '^timer: ')
echo "$out"
[ "$out" = "timer: ok" ]
