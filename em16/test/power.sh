#!/bin/sh
# The soft power block under em16 -fpga: test/power.s, a boot ROM, reads
# and writes its registers and turns the supply off; em16 must end with
# its message, within the 20 s alarm.
cd "$(dirname "$0")"
AS=../../bin/as; EM=${EM:-../../bin/em16}
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
"$AS" -o "$work/power.bin" power.s > /dev/null || exit 1
out=$(perl -e 'alarm 20; exec @ARGV' "$EM" -fpga -bootrom "$work/power.bin" < /dev/null 2> /dev/null |
  tr -d '\r' | grep -aE '^power: |^em16: the supply')
want='power: reset 00 01 00
power: control 05 05
power: off 00 80
em16: the supply turned off (OFF)'
[ "$out" = "$want" ] && echo "power: ok" || { echo "power: FAIL"; echo "$out"; exit 1; }
