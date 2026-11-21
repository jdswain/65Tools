; mini816sd.s - a boot ROM for em16 -mini816 -sd that drives the microSD
; card as Mini816 software does, its SPI bit by bit on the VIA's port B
; (PB3 MOSI, PB4 SCK, PB5 CS, PB6 MISO, mode 0). test/mini816sd.sh gives
; it a 2 MB image whose block b holds byte i as i + b.
;   1. MISO reads 1 with the card deselected.
;   2. CMD0 after 80 clocks: idle ($01). No card: no answer, "none".
;   3. CMD8: R7, the check pattern $AA echoed.
;   4. CMD55 and ACMD41 until ready ($00).
;   5. CMD58: the OCR, powered up, CCS set ($C0).
;   6. CMD9: a version 2 CSD, C_SIZE 3 (4096 blocks).
;   7. CMD17: block 0.
;   8. CMD24: block 1 written, byte i as i EOR $A5; accepted ($05),
;      then busy until $FF.
;   9. CMD17: block 1 as written.
;  10. CMD18 from block 2: blocks 2 and 3, then CMD12 and its R1b.
;  11. MISO reads 1 again with the card deselected.
; It prints "mini816sd: ok", "mini816sd: none", or "mini816sd: fail"
; and the check's number, and stops (STP).

                cpu = "65C816"
                org = $E000

via_orb         = $C000
via_ddrb        = $C002
scc_actl        = $C012
scc_adat        = $C013

MOSI            = $08
SCK             = $10
CS              = $20

pb              = $10           ; port B's other bits as driven: CS
sout            = $11
sin             = $12
base            = $13
cmdbuf          = $20           ; a command built: 6 bytes
buf             = $1000         ; a block

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

; --- 1. deselected, MISO pulled up ------------------------------------------

                lda #CS
                sta pb
                sta via_orb
                lda #$BF                ; all but PB6 outputs
                sta via_ddrb
                bit via_orb
                bvs .c2
                lda #1
                jmp fail

; --- 2. CMD0 ---------------------------------------------------------------

.c2:            ldx #10                 ; 80 clocks, CS high
.clk:           lda #$FF
                jsr spi
                dex
                bne .clk
                stz pb                  ; CS low
                lda pb
                sta via_orb
                ldx #cmd0
                jsr cmd
                cmp #$FF
                bne .card
                ldx #s_none
                jsr puts
                stp
.card:          cmp #$01
                beq .c3
                lda #2
                jmp fail

; --- 3. CMD8 ---------------------------------------------------------------

.c3:            ldx #cmd8
                jsr cmd
                cmp #$01
                bne .bad3
                jsr spi4
                lda cmdbuf+2
                cmp #$01
                bne .bad3
                lda cmdbuf+3
                cmp #$AA
                beq .c4
.bad3:          lda #3
                jmp fail

; --- 4. ACMD41 until ready ----------------------------------------------------

.c4:            ldy #10
.acmd:          ldx #cmd55
                jsr cmd
                ldx #acmd41
                jsr cmd
                cmp #$00
                beq .c5
                dey
                bne .acmd
                lda #4
                jmp fail

; --- 5. CMD58 --------------------------------------------------------------

.c5:            ldx #cmd58
                jsr cmd
                cmp #$00
                bne .bad5
                jsr spi4
                lda cmdbuf
                cmp #$C0
                beq .c6
.bad5:          lda #5
                jmp fail

; --- 6. CMD9 ---------------------------------------------------------------

.c6:            ldx #cmd9
                jsr cmd
                cmp #$00
                bne .bad6
                ldx #16
                jsr rdblk
                bcs .bad6
                lda buf
                cmp #$40                ; CSD version 2
                bne .bad6
                lda buf+7
                ora buf+8
                bne .bad6
                lda buf+9
                cmp #3
                beq .c7
.bad6:          lda #6
                jmp fail

; --- 7. CMD17, block 0 ------------------------------------------------------

.c7:            lda #$51
                ldx #0
                jsr mkcmd
                cmp #$00
                bne .bad7
                ldx #512
                jsr rdblk
                bcs .bad7
                lda #0
                jsr chk
                bcc .c8
.bad7:          lda #7
                jmp fail

; --- 8. CMD24, block 1 ------------------------------------------------------

.c8:            lda #$58
                ldx #1
                jsr mkcmd
                cmp #$00
                bne .bad8
                lda #$FF
                jsr spi
                lda #$FE                ; the start block token
                jsr spi
                ldx #0
.wrdata:            txa
                eor #$A5
                jsr spi
                inx
                cpx #512
                bne .wrdata
                lda #$FF                ; the CRC
                jsr spi
                lda #$FF
                jsr spi
                lda #$FF                ; the data response
                jsr spi
                and #$1F
                cmp #$05
                bne .bad8
                ldx #1000
.busy:          lda #$FF
                jsr spi
                cmp #$FF
                beq .c9
                dex
                bne .busy
.bad8:          lda #8
                jmp fail

; --- 9. CMD17, block 1 ------------------------------------------------------

.c9:            lda #$51
                ldx #1
                jsr mkcmd
                cmp #$00
                bne .bad9
                ldx #512
                jsr rdblk
                bcs .bad9
                ldx #0
.v9:            txa
                eor #$A5
                cmp buf,x
                bne .bad9
                inx
                cpx #512
                bne .v9
                bra .c10
.bad9:          lda #9
                jmp fail

; --- 10. CMD18 from block 2, CMD12 ------------------------------------------

.c10:           lda #$52
                ldx #2
                jsr mkcmd
                cmp #$00
                bne .bad10
                ldx #512
                jsr rdblk
                bcs .bad10
                lda #2
                jsr chk
                bcs .bad10
                ldx #512
                jsr rdblk
                bcs .bad10
                lda #3
                jsr chk
                bcs .bad10
                ldx #cmd12
                jsr cmd
                cmp #$00
                bne .bad10
                ldx #1000
.busy10:        lda #$FF
                jsr spi
                cmp #$FF
                beq .c11
                dex
                bne .busy10
.bad10:         lda #10
                jmp fail

; --- 11. deselected again ---------------------------------------------------

.c11:           lda #CS
                sta pb
                sta via_orb
                bit via_orb
                bvs .ok
                lda #11
                jmp fail
.ok:            ldx #s_ok
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

; A byte each way, MSB first: A out, A in (N, Z as it). The card has its
; bit on MISO before SCK rises, and takes MOSI as it does.
spi:            sta sout
                phy
                ldy #8
.bits:           lda pb
                asl sout
                bcc .zero
                ora #MOSI
.zero:             sta via_orb             ; MOSI, SCK low
                ora #SCK
                sta via_orb             ; SCK rises
                bit via_orb             ; V: MISO
                clc
                bvc .got
                sec
.got:            rol sin
                eor #SCK
                sta via_orb             ; SCK falls: the card's next bit
                dey
                bne .bits
                ply
                lda sin
                rts

; four bytes in to cmdbuf
spi4:           ldx #0
.lp:             lda #$FF
                jsr spi
                sta cmdbuf,x
                inx
                cpx #4
                bne .lp
                rts

; The command at x, 6 bytes, after a byte of $FF; A its R1, $FF if none
; (flags not set by it)
cmd:            phy
                lda #$FF
                jsr spi
                ldy #6
.send:          lda 0,x
                jsr spi
                inx
                dey
                bne .send
                ldy #10
.resp:          lda #$FF
                jsr spi
                bpl .done
                dey
                bne .resp
.done:          ply
                rts

; The command A for block x: built in cmdbuf, then sent
mkcmd:          sta cmdbuf
                stz cmdbuf+1
                stz cmdbuf+2
                stx cmdbuf+3            ; x's two bytes, big-endian
                lda cmdbuf+3
                xba
                lda cmdbuf+4
                sta cmdbuf+3
                xba
                sta cmdbuf+4
                lda #$FF
                sta cmdbuf+5
                ldx #cmdbuf
                jmp cmd

; A data block of x bytes into buf, after its token; C set if no token
rdblk:          phx
                ldx #200
.tok:             lda #$FF
                jsr spi
                cmp #$FE
                beq .go
                dex
                bne .tok
                plx
                sec
                rts
.go:            ply                     ; the count
                ldx #0
.data:             lda #$FF
                jsr spi
                sta buf,x
                inx
                dey
                bne .data
                lda #$FF                ; the CRC
                jsr spi
                lda #$FF
                jsr spi
                clc
                rts

; Is buf block A's, byte i i + A? C set if not
chk:            sta base
                ldx #0
.lp:             txa
                clc
                adc base
                cmp buf,x
                bne .bad
                inx
                cpx #512
                bne .lp
                clc
                rts
.bad:           sec
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

cmd0:           data.b $40, 0, 0, 0, 0, $95
cmd8:           data.b $48, 0, 0, $01, $AA, $87
cmd9:           data.b $49, 0, 0, 0, 0, $AF
cmd12:          data.b $4C, 0, 0, 0, 0, $61
cmd55:          data.b $77, 0, 0, 0, 0, $65
acmd41:         data.b $69, $40, 0, 0, 0, $77
cmd58:          data.b $7A, 0, 0, 0, 0, $FD

scc_init:       data.b 9, $C0, 4, $44, 3, $C1, 5, $6A, 11, $50, 12, 0, 13, 0, 14, $03, $FF

s_hello:        text.0 "mini816sd test", 13, 10
s_ok:           text.0 "mini816sd: ok", 13, 10
s_none:         text.0 "mini816sd: none", 13, 10
s_fail:         text.0 "mini816sd: fail "

                fill $FFEA-pc, $FF
                data.w nmi
                fill $FFEE-pc, $FF
                data.w irq
                fill $FFFC-pc, $FF
                data.w reset, reset
