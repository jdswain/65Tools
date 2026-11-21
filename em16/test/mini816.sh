#!/bin/sh
# The Mini816 under em16 -mini816: test/mini816.s, a boot ROM put at the
# top of the flash, must print "mini816: ok" and "rx: [ok]" (channel A
# received what was sent), and the flash file must then hold $A5 at
# $1234 (check 5). The NMI of check 12 is SIGUSR1, sent once the ROM
# prints "wai".
cd "$(dirname "$0")"
AS=../../bin/as; EM=../../bin/em16
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
"$AS" -o "$work/mini816.bin" mini816.s > /dev/null || exit 1
printf ok > "$work/in"
"$EM" -mini816 -turbo -rom "$work/mini816.bin" -flash "$work/flash.img" < "$work/in" > "$work/out" 2> /dev/null &
pid=$!
i=0
while [ $i -lt 200 ] && ! grep -q '^wai' "$work/out"; do sleep 0.1; i=$((i + 1)); done
kill -USR1 $pid 2> /dev/null
i=0
while [ $i -lt 100 ] && kill -0 $pid 2> /dev/null; do sleep 0.1; i=$((i + 1)); done
kill $pid 2> /dev/null
out=$(tr -d '\r' < "$work/out" | grep -a '^mini816: ')
rx=$(tr -d '\r' < "$work/out" | grep -a '^rx: ')
flash=$(od -An -tx1 -j 4660 -N 1 "$work/flash.img" 2> /dev/null | tr -d ' ')
echo "$out"
[ "$out" = "mini816: ok" ] && [ "$rx" = "rx: [ok]" ] && [ "$flash" = "a5" ] && exit 0
echo "rx '$rx', flash \$1234 '$flash'"
exit 1
