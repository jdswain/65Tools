; mini816.s - a boot ROM for em16 -mini816 that checks the Mini816 as
; ../../../Hardware/Mini816/docs/em16-profile.md describes it:
;   1. RAM: banks $00-$07 apart, bank $10 the same as bank $00.
;   2. The boot window is the top of the flash: $00:E000 is $0F:E000.
;   3. Nothing at $C030, $C040 or slot 1's DEVSEL: the open bus, $FF.
;   4. The flash's software ID: $BF, $B7; then its data again.
;   5. Programming ANDs a byte in ($5A, then $0F: $0A); a sector erase
;      leaves $FF; $A5 programmed for test/mini816.sh to find in the
;      file. Commands through the boot window do nothing.
;      The flash's routines run from RAM ($0400), as on the board: the
;      chip in ID mode reads its ID everywhere, the boot window too.
;   6. VIA timer 2: its flag only after its count, cleared by T2C-L.
;   7. VIA timer 1 counts PHI2: 27 between two reads of T1C-L (a store
;      and 10 NOPs apart), the I/O cycles stretched but counted once.
;   8. VIA timer 1 in free run: 8 IRQs, PB7 inverted at each.
;   9. SCC channel B's baud-rate generator: 4 ext/status IRQs, RR3 bit 0
;      and RR2 B's status 001.
;  10. SCC channel A receives "ok" from the host and echoes it.
;  11. WAI with I = 1 ends at timer 2's IRQ, which is not taken.
;  12. WAI again, for the NMI test/mini816.sh sends (SIGUSR1).
; It prints "mini816: ok", or "mini816: fail" and the check's number,
; and stops (STP).

                cpu = "65C816"
                org = $E000

via             = $C000
via_orb         = $C000
via_t1cl        = $C004
via_t1ch        = $C005
via_t1ll        = $C006
via_t1lh        = $C007
via_t2cl        = $C008
via_t2ch        = $C009
via_acr         = $C00B
via_ifr         = $C00D
via_ier         = $C00E
scc_bctl        = $C010
scc_actl        = $C012
scc_adat        = $C013

count           = $10           ; IRQs seen
pb7s            = $12           ; PB7 at each T1 IRQ, a bit each
s1              = $14
nmis            = $16

reset:          clc
                xce
                sep #$20
                rep #$10
                longa = off
                longi = on
                ldx #$01FF
                txs
                ldx #scc_init           ; channel A: 8N1, x16, BRG from PCLK, TC 0
.init:          lda 0,x
                cmp #$FF
                beq .inited
                sta scc_actl
                inx
                bra .init
.inited:        ldx #s_hello
                jsr puts

; --- 1. RAM ---------------------------------------------------------------

                lda #$11
                sta.l $002000
                lda #$22
                sta.l $012000
                lda #$77
                sta.l $072000
                lda.l $002000
                cmp #$11
                bne bad1
                lda.l $012000
                cmp #$22
                bne bad1
                lda.l $102000           ; bank $10 is bank $00
                cmp #$11
                bne bad1
                lda.l $172000
                cmp #$77
                beq t2
bad1:           lda #1
                jmp fail

; --- 2. the boot window ---------------------------------------------------

t2:             lda.l $00E000
                cmp.l $0FE000
                bne bad2
                lda.l $00FFFC
                cmp.l $0FFFFC
                bne bad2
                lda.l $080000           ; the flash below it, erased
                cmp #$FF
                beq t3
bad2:           lda #2
                jmp fail

; --- 3. the open bus ------------------------------------------------------

t3:             lda $C030
                cmp #$FF
                bne bad3
                lda $C040
                cmp #$FF
                bne bad3
                lda $C090
                cmp #$FF
                beq t4
bad3:           lda #3
                jmp fail

; --- 4. the flash's ID ----------------------------------------------------

t4:             ldx #0                  ; the flash's routines into RAM
.cp:            lda fcode,x
                sta ram,x
                inx
                cpx #fend-fcode
                bne .cp
                jsr r_fid
                lda id0
                cmp #$BF
                bne bad4
                lda id1
                cmp #$B7
                bne bad4
                lda.l $080001           ; out of ID mode
                cmp #$FF
                beq t5
bad4:           lda #4
                jmp fail

; --- 5. programming and erasing -------------------------------------------

t5:             lda #$5A
                jsr r_prog
                lda.l $081234
                cmp #$5A
                bne bad5
                lda #$0F
                jsr r_prog
                lda.l $081234
                cmp #$0A
                bne bad5
                jsr r_erase             ; the sector at $08:1000
                lda.l $081234
                cmp #$FF
                bne bad5
                lda #$A5
                jsr r_prog
                lda.l $081234
                cmp #$A5
                bne bad5
                lda #$AA                ; through the boot window: no command
                sta $D555
                lda #$55
                sta $D2AA
                lda #$A0
                sta $D555
                lda #$00
                sta $E000
                lda $E000
                cmp #$00
                bne t6
bad5:           lda #5
                jmp fail

; --- 6. timer 2 -----------------------------------------------------------

t6:             lda #100
                sta via_t2cl
                stz via_t2ch            ; 100 cycles
                lda via_ifr
                and #$20
                bne bad6
                ldx #40                 ; 200 cycles and more
.w6:            dex
                bne .w6
                lda via_ifr
                and #$20
                beq bad6
                lda via_t2cl            ; clears it
                lda via_ifr
                and #$20
                beq t7
bad6:           lda #6
                jmp fail

; --- 7. timer 1 counts PHI2 -----------------------------------------------

t7:             lda #$FF
                sta via_t1cl
                sta via_t1ch
                lda via_t1cl
                sta s1
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                lda via_t1cl
                eor #$FF
                sec
                adc s1
                cmp #27
                beq t8
                pha
                ldx #s_t1
                jsr puts
                pla
                jsr hex
                lda #7
                jmp fail

; --- 8. timer 1 in free run, PB7 ------------------------------------------

t8:             stz count
                stz pb7s
                lda #$C0                ; free run, PB7
                sta via_acr
                lda #<998
                sta via_t1cl
                lda #>998
                sta via_t1ch            ; a period of 1000
                lda #$C0
                sta via_ier
                cli
.w8:            lda count
                cmp #8
                bcc .w8
                sei
                lda #$40
                sta via_ier
                stz via_acr
                lda pb7s
                cmp #$55                ; high, low, high ... from the first
                beq t9
                cmp #$AA
                beq t9
                pha
                ldx #s_pb7
                jsr puts
                pla
                jsr hex
                lda #8
                jmp fail

; --- 9. SCC channel B's BRG -----------------------------------------------

t9:             stz count
                ldx #sccb_on
                jsr scc_b
                cli
.w9:            lda count
                cmp #4
                bcc .w9
                sei
                ldx #sccb_off
                jsr scc_b
                lda s1                  ; RR2 B in the last IRQ
                and #$0E
                cmp #$02                ; 001: B ext/status
                beq t10
                lda #9
                jmp fail

; --- 10. SCC channel A receives -------------------------------------------

t10:            ldx #s_rx
                jsr puts
                jsr getc
                pha
                jsr getc
                tay
                pla
                jsr putc
                tya
                jsr putc
                lda #']'
                jsr putc
                lda #13
                jsr putc
                lda #10
                jsr putc

; --- 11. WAI, IRQ masked --------------------------------------------------

                lda #100
                sta via_t2cl
                lda #$A0                ; T2's IRQ
                sta via_ier
                stz count
                stz via_t2ch
                wai
                lda count               ; not taken
                bne bad11
                lda via_ifr
                and #$A0
                cmp #$A0
                bne bad11
                lda via_t2cl
                lda #$20
                sta via_ier
                bra t12
bad11:          lda #11
                jmp fail

; --- 12. WAI for the NMI --------------------------------------------------

t12:            stz nmis
                ldx #s_wai
                jsr puts
.w12:           wai
                lda nmis
                beq .w12
                ldx #s_ok
                jsr puts
                stp

fail:           pha
                ldx #s_fail
                jsr puts
                pla
                jsr hex
                lda #13
                jsr putc
                lda #10
                jsr putc
                stp

; The flash's routines, run from RAM at ram (copied by check 4): no
; absolute address of their own. fid the ID into id0 and id1, fprog A
; programmed at $08:1234, ferase the sector at $08:1000.
ram             = $0400
id0             = $20
id1             = $21
r_fid           = ram+fid-fcode
r_prog          = ram+fprog-fcode
r_erase         = ram+ferase-fcode

fcode:
fid:            lda #$AA
                sta.l $085555
                lda #$55
                sta.l $082AAA
                lda #$90
                sta.l $085555
                lda.l $080000
                sta id0
                lda.l $080001
                sta id1
                lda #$F0                ; ID exit
                sta.l $080000
                rts
fprog:          pha
                lda #$AA
                sta.l $085555
                lda #$55
                sta.l $082AAA
                lda #$A0
                sta.l $085555
                pla
                sta.l $081234
                rts
ferase:         lda #$AA
                sta.l $085555
                lda #$55
                sta.l $082AAA
                lda #$80
                sta.l $085555
                lda #$AA
                sta.l $085555
                lda #$55
                sta.l $082AAA
                lda #$30
                sta.l $081000
                rts
fend:

; SCC channel B: register, value pairs from x to $FF
scc_b:          lda 0,x
                cmp #$FF
                beq .done
                sta scc_bctl
                inx
                bra scc_b
.done:          rts

irq:            pha
                phx
                lda via_ifr
                bpl .scc
                and #$40
                beq .t2
                lda via_t1cl            ; clears T1's flag
                lda via_orb             ; PB7
                asl a
                rol pb7s
                inc count
                bra .done
.t2:            lda via_t2cl
                bra .done
.scc:           lda #3                  ; RR3: channel B ext/status?
                sta scc_actl
                lda scc_actl
                and #$01
                beq .done
                lda #2                  ; RR2 B
                sta scc_bctl
                lda scc_bctl
                sta s1
                lda #$10                ; reset ext/status interrupts
                sta scc_bctl
                inc count
.done:          plx
                pla
                rti

nmi:            inc nmis
                rti

putc:           pha
.wt:            lda scc_actl
                and #$04
                beq .wt
                pla
                sta scc_adat
                rts

getc:           lda scc_actl
                and #$01
                beq getc
                lda scc_adat
                rts

puts:           lda 0,x
                beq .done
                jsr putc
                inx
                bra puts
.done:          rts

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

scc_init:       data.b 9, $C0, 4, $44, 3, $C1, 5, $6A, 11, $50, 12, 0, 13, 0, 14, $03, $FF
sccb_on:        data.b 12, <998, 13, >998, 14, $03, 15, $02, 1, $01, 9, $08, $FF
sccb_off:       data.b 9, $00, 1, $00, 15, $00, 14, $00, $FF

s_hello:        text.0 "mini816 test", 13, 10
s_rx:           text.0 "rx: ["
s_wai:          text.0 "wai", 13, 10
s_t1:           text.0 "T1 counted "
s_pb7:          text.0 "PB7 "
s_ok:           text.0 "mini816: ok", 13, 10
s_fail:         text.0 "mini816: fail "

                fill $FFEA-pc, $FF
                data.w nmi
                fill $FFEE-pc, $FF
                data.w irq
                fill $FFFC-pc, $FF
                data.w reset, reset
