; romsize.s - a 16K boot ROM for em16 -fpga, its code at $C000, so it runs
; only if the ROM is sized to the image (EmSoC.LoadROM). It checks, as
; fpga/rom/romsize.asm of the Verilog repository does on the RTL:
;   1. $BFFF, just below the ROM, is RAM.
;   2. A write to $DF00 goes to the RAM underneath: $DF00 still reads ROM.
;   3. Copied into the RAM underneath and mapped out ($0300 = 0), it carries
;      on from RAM, and $DF00 reads what was written.
; It prints "romsize: ok", or "romsize: fail" and the number of the check.
; test/romsize.sh runs it.

                cpu = "65C816"
                org = $C000

sysctl          = $0300         ; bit 0: the boot ROM mapped
scc_ctl         = $0822
scc_data        = $0823
probe           = $DF00         ; in the ROM's filler

reset:          clc
                xce
                sep #$20
                rep #$10
                longa = off
                longi = on
                ldx #$01FF
                txs
                lda scc_ctl
                lda #5
                sta scc_ctl
                lda #$68
                sta scc_ctl

                lda #$5A                ; 1. RAM below the ROM
                sta $BFFF
                lda $BFFF
                cmp #$5A
                beq t2
                lda #1
                jmp fail

t2:             lda #$A5                ; 2. a write under the ROM
                sta probe
                lda probe
                cmp #$FF
                beq t3
                lda #2
                jmp fail

t3:             ldx #0                  ; 3. into RAM, the ROM mapped out
.copy:          lda $C000,x
                sta $C000,x
                inx
                cpx #$0400              ; the code, well under 1K
                bne .copy
                stz sysctl
                lda sysctl
                bne .bad
                lda probe
                cmp #$A5
                beq ok
.bad:           lda #3
                jmp fail

ok:             ldx #s_ok
                jsr puts
                stp

fail:           pha
                ldx #s_fail
                jsr puts
                pla
                clc
                adc #$30
                jsr putc
                lda #13
                jsr putc
                lda #10
                jsr putc
                stp

putc:           pha
.wt:            lda scc_ctl
                and #$04
                beq .wt
                pla
                sta scc_data
                rts

puts:           lda 0,x
                beq .done
                jsr putc
                inx
                bra puts
.done:          rts

s_ok:           text.0 "romsize: ok", 13, 10
s_fail:         text.0 "romsize: fail "

                fill $FFFC-pc, $FF
                data.w reset, reset
