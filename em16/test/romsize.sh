#!/bin/sh
# The boot ROM sized to its image under em16 -fpga: test/romsize.s, a 16K
# boot ROM with its code at $C000, must print "romsize: ok".
cd "$(dirname "$0")"
AS=../../bin/as; EM=../../bin/em16
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
"$AS" -o "$work/romsize.bin" romsize.s > /dev/null || exit 1
out=$(perl -e 'alarm 20; exec @ARGV' "$EM" -fpga -bootrom "$work/romsize.bin" < /dev/null 2> /dev/null |
  tr -d '\r' | grep -a '^romsize: ')
echo "$out"
[ "$out" = "romsize: ok" ]
