; power.s - a boot ROM for em16 -fpga that checks the soft power block
; (EmPower, $0480; rtl/power.v of the Verilog repository):
;   1. STATUS 0, CONTROL 1 (the LED lit) after reset, ISTAT bit 5 clear
;   2. CONTROL written $05 reads $05; PRESSED cleared by a write of 2
;   3. OFF written $12 is ignored; written $A5 the burst runs (STATUS
;      bit 7), and em16 ends when it is over, as the supply goes off
; It prints "power: ..." lines; test/power.sh checks them and em16's
; message.

                cpu = "65C816"
                org = $E000

istat           = $0440
pstat           = $0480
pctl            = $0481
poff            = $0482
scc_ctl         = $0822
scc_data        = $0823

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
                ldx #s_reset
                jsr puts
                lda pstat
                jsr hex
                lda #' '
                jsr putc
                lda pctl
                jsr hex
                lda #' '
                jsr putc
                lda istat
                and #$20
                jsr hex
                jsr crlf
                lda #$05
                sta pctl
                lda #2
                sta pstat
                ldx #s_ctl
                jsr puts
                lda pctl
                jsr hex
                lda #' '
                jsr putc
                lda $04BD               ; a mirror of CONTROL
                jsr hex
                jsr crlf
                lda #$12
                sta poff
                ldx #s_off
                jsr puts
                lda pstat
                jsr hex
                lda #$A5
                sta poff
                lda #' '
                jsr putc
                lda pstat
                jsr hex
                jsr crlf
.wait:          bra .wait               ; until the supply goes

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

crlf:           lda #13
                jsr putc
                lda #10
                jmp putc

hex:            pha
                lsr a
                lsr a
                lsr a
                lsr a
                jsr .nib
                pla
.nib:           and #$0F
                cmp #10
                bcc .dig
                adc #6
.dig:           adc #$30
                jmp putc

s_reset:        text.0 "power: reset "
s_ctl:          text.0 "power: control "
s_off:          text.0 "power: off "

                fill $FFFC-pc, $FF
                data.w reset, reset
