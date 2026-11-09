; rtc.s - a boot ROM for em16 -fpga that checks the rev B's real-time
; clock, a DS12C887 (EmRTC; $0870 the index, $0871 the data):
;   a new module (A not $20: -rtc's file not there yet): its registers,
;   then A $20, B $06 and RAM $20 $A7 written, and the supply off
;   else (rtctime 2026-11-09 23:59:58, or the file kept):
;   1. A, B, D, and RAM $20 (0, or $A7 kept by the file)
;   2. the index port reads $FF; RAM written, read, and through a mirror
;   3. the time, then two updates later (midnight: the date, the day)
;      and UIP seen while waiting
;   4. UIE: ISTAT bit 3 at the update, C $90, then bit 3 clear
;   5. BCD, 24 h, SET: 2099-12-31 23:59:59, an update: 2100-01-01, a
;      Friday, the century carried; 12 h: 11:59:59 PM to 12 AM
;   6. RS 15: PF in half a second
; It prints "rtc: ..." lines; test/rtc.sh checks them.

                cpu = "65C816"
                org = $E000

istat           = $0440
poff            = $0482
rtc_i           = $0870
rtc_d           = $0871
scc_ctl         = $0822
scc_data        = $0823
uip             = $0010                 ; in the direct page: UIP seen

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
                lda #$0B                ; B: the enables off, as OS16 does
                jsr rd
                and #$87
                tay
                lda #$0B
                jsr wr
                lda #$0C
                jsr rd
                ldx #s_regs             ; 1.
                jsr puts
                lda #$0A
                jsr rd
                pha
                jsr hex
                jsr space
                lda #$0B
                jsr rd
                jsr hex
                jsr space
                lda #$0D
                jsr rd
                jsr hex
                jsr crlf
                pla
                cmp #$20
                beq running
                ldy #$20                ; a new module: started
                lda #$0A
                jsr wr
                ldy #$06
                lda #$0B
                jsr wr
                ldy #$A7
                lda #$20
                jsr wr
                jmp supply

running:        ldx #s_ram
                jsr puts
                lda #$20
                jsr rd
                jsr hex
                jsr crlf
                ldx #s_index            ; 2.
                jsr puts
                lda rtc_i
                jsr hex
                jsr space
                ldy #$5A
                lda #$40
                jsr wr
                lda #$40
                jsr rd
                jsr hex
                jsr space
                lda #$40
                sta $08F0               ; a mirror
                lda $08F1
                jsr hex
                jsr crlf
                ldx #s_time             ; 3.
                jsr puts
                jsr time
                stz uip
                jsr update
                jsr update
                ldx #s_then
                jsr puts
                jsr time
                ldx #s_uip
                jsr puts
                lda uip
                jsr hex
                jsr crlf
                ldy #$16                ; 4. UIE
                lda #$0B
                jsr wr
.irq:           lda istat
                and #$08
                beq .irq
                ldx #s_irq
                jsr puts
                lda istat
                and #$08
                jsr hex
                jsr space
                lda #$0C
                jsr rd
                jsr hex
                jsr space
                lda istat
                and #$08
                jsr hex
                jsr crlf
                ldy #$82                ; 5. SET, BCD, 24 h
                lda #$0B
                jsr wr
                ldx #0
.put:           lda bcd_v,x
                tay
                lda bcd_r,x
                jsr wr
                inx
                cpx #8
                bne .put
                ldy #$02
                lda #$0B
                jsr wr
                jsr update
                ldx #s_bcd
                jsr puts
                jsr time
                ldy #$80                ; 12 h, BCD: 11:59:59 PM
                lda #$0B
                jsr wr
                ldy #$91
                lda #4
                jsr wr
                ldy #$59
                lda #2
                jsr wr
                ldy #$59
                lda #0
                jsr wr
                ldy #$00
                lda #$0B
                jsr wr
                jsr update
                ldx #s_12h
                jsr puts
                lda #4
                jsr rd
                jsr hex
                jsr crlf
                ldy #$2F                ; 6. RS 15
                lda #$0A
                jsr wr
                lda #$0C
                jsr rd
.pf:            lda #$0C
                jsr rd
                and #$40
                beq .pf
                pha
                ldx #s_pf
                jsr puts
                pla
                jsr hex
                jsr crlf
                ldy #$20
                lda #$0A
                jsr wr
                ldy #$06
                lda #$0B
                jsr wr
supply:         lda #$A5
                sta poff
.wait:          bra .wait               ; until the supply goes

; register A read: its value in A
rd:             sta rtc_i
                lda rtc_d
                rts

; register A written with Y's low byte
wr:             sta rtc_i
                tya
                sta rtc_d
                rts

; until an update (C's UF), UIP noted
update:         lda #$0A
                jsr rd
                and #$80
                tsb uip
                lda #$0C
                jsr rd
                and #$10
                beq update
                rts

; seconds, minutes, hours, day, date, month, year, century
time:           ldx #0
.t:             phx
                lda regs,x
                jsr rd
                jsr hex
                plx
                inx
                cpx #8
                beq .end
                phx
                jsr space
                plx
                bra .t
.end:           jmp crlf

regs:           data.b 0, 2, 4, 6, 7, 8, 9, $32
bcd_r:          data.b 0, 2, 4, 6, 7, 8, 9, $32
bcd_v:          data.b $59, $59, $23, $05, $31, $12, $99, $20

space:          lda #' '
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

s_regs:         text.0 "rtc: regs "
s_ram:          text.0 "rtc: ram "
s_index:        text.0 "rtc: index "
s_time:         text.0 "rtc: time "
s_then:         text.0 "rtc: then "
s_uip:          text.0 "rtc: uip "
s_irq:          text.0 "rtc: irq "
s_bcd:          text.0 "rtc: bcd "
s_12h:          text.0 "rtc: 12h "
s_pf:           text.0 "rtc: pf "


                fill $FFFC-pc, $FF
                data.w reset, reset
