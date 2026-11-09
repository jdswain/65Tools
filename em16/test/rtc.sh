#!/bin/sh
# The rev B's real-time clock under em16 -fpga: test/rtc.s, a boot ROM,
# reads and writes the DS12C887 (EmRTC) and turns the supply off. Run at
# -rtctime 2026-11-09 23:59:58; then with -rtc's file not there (a new
# module, started by the ROM), and again with it (kept: running, its RAM).
cd "$(dirname "$0")"
AS=../../bin/as; EM=${EM:-../../bin/em16}
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
"$AS" -o "$work/rtc.bin" rtc.s > /dev/null || exit 1
run() { perl -e 'alarm 30; exec @ARGV' "$EM" -fpga -bootrom "$work/rtc.bin" "$@" < /dev/null 2> /dev/null | tr -d '\r' | grep -a '^rtc: '; }
out=$(run -rtctime 20261109235958)
want='rtc: regs 20 06 80
rtc: ram 00
rtc: index FF 5A 5A
rtc: time 3A 3B 17 02 09 0B 1A 14
rtc: then 00 00 00 03 0A 0B 1A 14
rtc: uip 80
rtc: irq 08 90 00
rtc: bcd 00 00 00 06 01 01 00 21
rtc: 12h 12
rtc: pf 40'
new=$(run -rtc "$work/rtc.nv"; run -rtc "$work/rtc.nv" | grep -E '^rtc: (regs|ram)')
wantnew='rtc: regs 00 00 80
rtc: regs 20 06 80
rtc: ram A7'
[ "$out" = "$want" ] && [ "$new" = "$wantnew" ] && echo "rtc: ok" || { echo "rtc: FAIL"; echo "$out"; echo "$new"; exit 1; }
