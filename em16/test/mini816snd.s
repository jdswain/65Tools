; mini816snd.s - a boot ROM for em16 -mini816 that sounds the speaker, for
; test/mini816snd.sh to hear in -wav's file: three tones of 250 ms, 100 ms
; apart, the CPU waiting between in loops without I/O (so that PHI2 keeps
; the wall's time):
;   A. Timer 1 in free run on PB7, its latch 3684: 7372800 / (2 x 3686),
;      1000.11 Hz.
;   B. ORB bit 7 toggled by the CPU every 20 + 5 x 1470 clocks (the
;      store's I/O cycle 8 of them): 500.19 Hz.
;   C. The shift register in free run on CB2, $0F at T2's latch 228:
;      8 bits of 2 x (228 + 2) cycles, 2003.48 Hz; heard with -soundcb2.
; Then it prints "mini816snd: done" and stops (STP).
;
; As a demonstration: as -o snd.bin test/mini816snd.s, then
; em16 -mini816 -soundcb2 -rom snd.bin.

                cpu = "65C816"
                org = $E000

via_orb         = $C000
via_ddrb        = $C002
via_t1cl        = $C004
via_t1ch        = $C005
via_t2cl        = $C008
via_sr          = $C00A
via_acr         = $C00B
scc_actl        = $C012
scc_adat        = $C013

reset:          clc
                xce
                sep #$20
                rep #$10
                longa = off
                longi = on
                ldx #$01FF
                txs
                ldx #scc_init
.init:          lda 0,x
                cmp #$FF
                beq .inited
                sta scc_actl
                inx
                bra .init
.inited:        ldx #s_hello
                jsr puts
                lda #$A0                ; PB7 high, the SD card's CS high
                sta via_orb
                lda #$BF
                sta via_ddrb
                ldx #50
                jsr delay

                lda #<3684              ; A. timer 1 on PB7
                sta via_t1cl
                lda #$C0                ; free run, PB7
                sta via_acr
                lda #>3684
                sta via_t1ch
                ldx #250
                jsr delay
                stz via_acr             ; PB7 the ORB's again
                ldx #100
                jsr delay

                lda #$A0                ; B. PB7 toggled
                ldx #250                ; half periods
.half:          eor #$80
                sta via_orb
                ldy #1470
.wait:          dey
                bne .wait
                dex
                bne .half
                lda #$A0
                sta via_orb
                ldx #100
                jsr delay

                lda #228                ; C. the shift register on CB2
                sta via_t2cl
                lda #$10                ; free run at T2's rate
                sta via_acr
                lda #$0F
                sta via_sr
                ldx #250
                jsr delay
                stz via_acr
                ldx #50
                jsr delay

                ldx #s_done
                jsr puts
                stp

; x ms: 7372 clocks each, no I/O
delay:          ldy #1473
.loop:          dey
                bne .loop
                dex
                bne delay
                rts

nmi:
irq:            rti

putc:           pha
.wt:            lda scc_actl
                and #$04
                beq .wt
                pla
                sta scc_adat
                rts

puts:           lda 0,x
                beq .done
                jsr putc
                inx
                bra puts
.done:          rts

scc_init:       data.b 9, $C0, 4, $44, 3, $C1, 5, $6A, 11, $50, 12, 0, 13, 0, 14, $03, $FF
s_hello:        text.0 "mini816snd test", 13, 10
s_done:         text.0 "mini816snd: done", 13, 10

                fill $FFEA-pc, $FF
                data.w nmi
                fill $FFEE-pc, $FF
                data.w irq
                fill $FFFC-pc, $FF
                data.w reset, reset
