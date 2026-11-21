#!/bin/sh
# The Mini816's microSD card under em16 -mini816 -sd: test/mini816sd.s
# drives it bit by bit on the VIA and must print "mini816sd: ok" with a
# card (a 2 MB image, block b's byte i i + b) and "mini816sd: none"
# without; block 1 of the image must then hold byte i as i EOR $A5.
cd "$(dirname "$0")"
AS=../../bin/as; EM=../../bin/em16
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
"$AS" -o "$work/sd.bin" mini816sd.s > /dev/null || exit 1
python3 -I -c '
import sys
open(sys.argv[1], "wb").write(bytes((i + b) & 255 for b in range(4096) for i in range(512)))
' "$work/card.img" || exit 1
run() {
  "$EM" -mini816 -turbo -rom "$work/sd.bin" "$@" < /dev/null > "$work/out" 2> /dev/null &
  pid=$!
  i=0
  while [ $i -lt 100 ] && kill -0 $pid 2> /dev/null; do sleep 0.1; i=$((i + 1)); done
  kill $pid 2> /dev/null
  tr -d '\r' < "$work/out" | grep -a '^mini816sd: '
}
card=$(run -sd "$work/card.img")
none=$(run)
blk1=$(od -An -tx1 -j 512 -N 4 "$work/card.img" | tr -d ' ')
echo "$card"
[ "$card" = "mini816sd: ok" ] && [ "$none" = "mini816sd: none" ] && [ "$blk1" = "a5a4a7a6" ] && exit 0
echo "without a card '$none', block 1 '$blk1'"
exit 1
