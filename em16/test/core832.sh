#!/bin/sh
# EmCore against the core's own checks of the WDM extension and the
# 65C832 mode: test832_gen.py of the Verilog repository, whose images
# tb_cpu.v runs there (make test816x, make test832), under em16 -bench.
# The core as the Tang Nano builds it (C832=0), then with -c832, the
# 65C832 image without its NMI and ABORT checks (--irq-only), which
# EmCore has neither of.
cd "$(dirname "$0")"
EM=../../bin/em16; GEN=../../../Verilog65C816/test832_gen.py
[ -f "$GEN" ] || { echo "core832: $GEN not found, skipped"; exit 0; }
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
python3 "$GEN" --c816 -o "$work/t816x" > /dev/null || exit 1
python3 "$GEN" --irq-only -o "$work/t832" > /dev/null || exit 1
ok=1
out=$(perl -e 'alarm 60; exec @ARGV' "$EM" -bench "$work/t816x.hex" 2> /dev/null)
echo "core832: 65C816 and the extension: ${out:-no answer}"
case "$out" in PASS*) ;; *) ok=0 ;; esac
out=$(perl -e 'alarm 60; exec @ARGV' "$EM" -bench "$work/t832.hex" -c832 2> /dev/null)
echo "core832: 65C832 (-c832): ${out:-no answer}"
case "$out" in PASS*) ;; *) ok=0 ;; esac
[ $ok = 1 ]
