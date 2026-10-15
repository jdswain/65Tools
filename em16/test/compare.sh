#!/bin/sh
# Run the Oberon em16 (bin/em16, or $NEW) and the C++ one it was ported
# from (bin/em16-c, or $OLD) on the same programs and compare what they
# write: standard output without the timing lines, standard error, the
# -t traces, and the files they write.
#
#   cpu     generated programs that execute every opcode of the 65C816
#           (five register width modes), the R65C02 and the L28's R65C19
#           with varied registers, flags and memory (tools/cputest.py);
#           traces compared
#   oc      every compiled test program of ../oc/test
#   boot    OS16's boot loader reading a floppy image; trace and image
#   fpga    a boot ROM that draws into the framebuffer, with -fbdump
#   basic   Business BASIC on the FPGA SoC
#           (fpga and basic: what they write, not traces or time: under
#           -fpga em16 runs the SoC's own core and timing, em16-c did not)
#   devices the L28's USART, LCD and banked memory; the VIA's timer
#           interrupts and ADB
#
# A program that runs until it is stopped is stopped after some seconds;
# its traces are then compared as far as both got.
cd "$(dirname "$0")/.." || exit 1
here=$(pwd)
bin=$(cd ../bin && pwd)
NEW=${NEW:-$bin/em16}
OLD=${OLD:-$bin/em16-c}
AS=${AS:-$bin/as}
work=$here/test/out
rm -rf "$work"; mkdir -p "$work"
pass=0; fail=0

# run name seconds stdin args...: both emulators, output in $work
run() {
  name=$1; secs=$2; input=$3; shift 3
  for v in old new; do
    if [ $v = old ]; then e=$OLD; else e=$NEW; fi
    perl -e 'alarm shift; exec @ARGV' "$secs" "$e" "$@" < "$input" \
      > "$work/$name.$v.out" 2> "$work/$name.$v.err"
  done
}

# Equal, or one a prefix of the other when a run was cut short.
same_prefix() {
  a=$(($(wc -l < "$1"))); b=$(($(wc -l < "$2")))
  if [ "$a" -lt "$b" ]; then m=$a; else m=$b; fi
  if [ "$a" = "$b" ]; then cmp -s "$1" "$2"
  else head -n "$m" "$1" > "$work/.a"; head -n "$m" "$2" > "$work/.b"; cmp -s "$work/.a" "$work/.b"
  fi
}

result() {
  if [ "$1" = 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "DIFF $2"; fi
}

check() {    # name: stdout (no timing) and stderr (traces as far as both got)
  grep -av '^Executed \|^Overall CPU Frequency' "$work/$1.old.out" > "$work/.o"
  grep -av '^Executed \|^Overall CPU Frequency' "$work/$1.new.out" > "$work/.n"
  same_prefix "$work/.o" "$work/.n" && same_prefix "$work/$1.old.err" "$work/$1.new.err"
  result $? "$1"
}

echo "cpu"
for seed in 1 2 3; do
  for m in n16 n8 n168 n816 e; do
    python3 tools/cputest.py wdc $seed $m > "$work/t.s" && (cd "$work" && "$AS" -o "w$m$seed" t.s > /dev/null)
    run "w$m$seed" 10 /dev/null -t "$work/w$m$seed"; check "w$m$seed"
  done
  for c in rockwell l28; do
    python3 tools/cputest.py $c $seed > "$work/t.s" && (cd "$work" && "$AS" -o "$c$seed" t.s > /dev/null)
    if [ $c = rockwell ]; then cpu=rockwell; else cpu=l28; fi
    run "$c$seed" 5 /dev/null -t -cpu $cpu "$work/$c$seed"; check "$c$seed"
  done
done

echo "oc"
for f in ../oc/test/*.816; do
  n=oc_$(basename "$f" .816)
  run "$n" 10 /dev/null "$f"; check "$n"
done

echo "boot"
cp ../OS16/images/BootDisk.img "$work/old.img"; cp ../OS16/images/BootDisk.img "$work/new.img"
for v in old new; do
  if [ $v = old ]; then e=$OLD; else e=$NEW; fi
  perl -e 'alarm 60; exec @ARGV' "$e" -t -disk0 "$work/$v.img" ../OS16/boot/Boot.816 \
    < /dev/null > "$work/boot.$v.out" 2> "$work/boot.$v.err"
  sed -i '' "s|$work/$v.img|disk.img|" "$work/boot.$v.out"
done
check boot
cmp -s "$work/old.img" "$work/new.img"; result $? "boot disk image"

echo "fpga"
# a boot ROM that draws into the framebuffer and changes the palette
cat > "$work/fb.s" <<'END'
                cpu = "65C816"
                org = $E000
reset:          clc
                xce
                rep #$30
                longa = on
                longi = on
                ldx #0
.fill:          txa
                and #$00FF
                sta $700000,x
                inx
                inx
                cpx #$5800
                bne .fill
                sep #$20
                longa = off
                ldx #0
.pal:           txa
                asl a
                asl a
                sta $0240,x
                inx
                cpx #$0018
                bne .pal
                jmp $0000
                fill $FFFC-pc, $FF
                data.w reset, reset
END
(cd "$work" && "$AS" -o fb.bin fb.s > /dev/null)
for v in old new; do
  if [ $v = old ]; then e=$OLD; else e=$NEW; fi
  perl -e 'alarm 20; exec @ARGV' "$e" -fpga -bootrom "$work/fb.bin" -fbdump "$work/fb.$v.ppm" \
    < /dev/null > "$work/fb.$v.out" 2> "$work/fb.$v.err"
  sed -i '' "s|$work/fb.$v.ppm|fb.ppm|" "$work/fb.$v.out"
done
check fb
cmp -s "$work/fb.old.ppm" "$work/fb.new.ppm"; result $? "fb framebuffer"

echo "basic"
B=../../BusinessBasic/basic
if [ -f $B/build/basic ]; then
  for v in old new; do
    if [ $v = old ]; then e=$OLD; else e=$NEW; fi
    ( (sleep 1; printf 'PRINT 355/113\rHOME\rPRINT "HELLO"\rFOR I=1 TO 3:PRINT I*I:NEXT\r'; sleep 2) |
      perl -e 'alarm 4; exec @ARGV' "$e" -fpga -bootrom $B/build/boot.bin $B/build/basic \
      > "$work/basic.$v.out" 2> /dev/null ) 2> /dev/null
  done
  grep -av '^Executed \|^Overall CPU' "$work/basic.old.out" > "$work/.o"
  grep -av '^Executed \|^Overall CPU' "$work/basic.new.out" > "$work/.n"
  cmp -s "$work/.o" "$work/.n"; result $? basic
fi

echo "devices"
# the L28: USART, LCD text, line, rectangle and fill, bank select into
# ES0 RAM and ES2 flash, and its report when it reaches address 0
cat > "$work/l28dev.s" <<'END'
                cpu = "C19"
                org = $8000
lcd             macro reg, val {
                lda #reg
                sta $0600
                lda #val
                sta $0601
}
reset:          sei
                ldx #$FF
                txs
                lda #'H'
                sta $38
                lda #'I'
                sta $38
                lda $3C
                lcd $03, $04
                lcd $CC, $00
                lcd $CD, $05
                lcd $D2, $FF
                lcd $D3, $80
                lcd $D5, $10
                lcd $63, 10
                lcd $65, 20
                lcd $04, 'A'
                lcd $04, 'B'
                lcd $CC, $20
                lcd $04, 'C'
                lcd $68, 5
                lcd $6A, 6
                lcd $6C, 100
                lcd $6E, 70
                lcd $67, $80
                lcd $67, $A8
                lcd $A2, 50
                lcd $A4, 60
                lcd $A6, 30
                lcd $A8, 20
                lcd $91, $07
                lcd $98, 50
                lcd $9A, 60
                lcd $A2, 200
                lcd $91, $03
                lcd $87, $80
                lda #$63
                sta $0600
                lda $0601
                lda $0600
                lda #$02
                sta $1A
                lda #$5A
                sta $4000
                lda $4000
                lda #$10
                sta $1B
                lda $6000
                lda $00
                lda $14
                jmp $0000
                org = $FFFC
                data.w reset, reset
END
(cd "$work" && "$AS" -o l28dev l28dev.s > /dev/null)
run l28dev 10 /dev/null -t "$work/l28dev"; check l28dev

# the default machine: timer 1 of the VIA in free running mode
# interrupting 20 times, and an ADB command through its ports
cat > "$work/via.s" <<'END'
                cpu = "65C816"
                org = $8000
count           = $10
reset:          clc
                xce
                sep #$30
                lda #$40
                sta $C02B
                lda #$C0
                sta $C02E
                lda #$40
                sta $C024
                stz count
                lda #$00
                sta $C025
                cli
.wait:          lda count
                cmp #20
                bcc .wait
                sei
                lda #$2C
                sta $C02F
                stz $C020
                lda #1
                sta $C020
                lda $C020
                lda $C02F
                lda $C02F
                lda $C02D
                jmp $0000
irq:            pha
                lda $C024
                inc count
                pla
                rti
                org = $FFEE
                data.w irq
                org = $FFFC
                data.w reset, reset
END
(cd "$work" && "$AS" -o via via.s > /dev/null)
run via 10 /dev/null -t "$work/via"; check via
grep -q 'RTI' "$work/via.new.err"; result $? "via interrupts happen"

echo "$pass same, $fail different"
[ $fail = 0 ]
