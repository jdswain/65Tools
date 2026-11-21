; mini816kbd.s - a boot ROM for em16 -mini816 -video: the keyboard's matrix
; on the TMS9118, a box for each key that fills while the key is down
; (columns 0-7 and 15 across, rows 0-7 down; 8-14 are not wired), and a
; ball the joystick moves, red while fire is down. A byte on channel A
; (the console) stops it, two frames later.
;
;   as -o kbd.bin test/mini816kbd.s
;   em16 -mini816 -video -rom kbd.bin

                cpu = "65C816"
                org = $E000

via_ora         = $C00F         ; port A, no handshake
via_orb         = $C000
via_ddrb        = $C002
via_pcr         = $C00C
scc_actl        = $C012
scc_adat        = $C013
vdp_data        = $C020
vdp_ctl         = $C021

bx              = $11           ; the ball
by              = $12
quit            = $13           ; frames to go once stopping, 0 running
rows            = $20           ; each column's keys down, 16 bytes

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
                lda #$20                ; the SD card's CS high, PB0-PB2 the column
                sta via_orb
                lda #$BF
                sta via_ddrb
                lda #$80                ; blank, then VRAM cleared
                ldx #1
                jsr setreg
                ldx #0
                jsr wraddr
                ldy #$4000
.clr:           stz vdp_data
                dey
                bne .clr
                ldx #$0008              ; patterns 1 (a box) and 2 (filled)
                jsr wraddr
                ldx #0
.pat:           lda pats,x
                sta vdp_data
                inx
                cpx #16
                bne .pat
                ldx #$2000              ; their colours: white on the backdrop
                jsr wraddr
                lda #$F0
                sta vdp_data
                ldx #$3800              ; sprite pattern 0: the ball
                jsr wraddr
                ldx #0
.ball:          lda ball,x
                sta vdp_data
                inx
                cpx #8
                bne .ball
                lda #124
                sta bx
                lda #150
                sta by
                stz quit
                ldx #regs
                jsr regs8

loop:           jsr waitf
                jsr scan
                jsr grid
                jsr joy
                lda quit
                bne .stopping
                lda scc_actl            ; a byte from the console: stop
                and #$01
                beq loop
                lda scc_adat
                lda #2
                sta quit
                bra loop
.stopping:      dec quit
                bne loop
                stp

; the columns' rows down, 1 a key, into rows
scan:           ldx #0                  ; the column
.col:           txa
                and #7
                ora #$20
                sta via_orb
                txa
                cmp #8
                lda #$0C                ; CA2 low: columns 0-7
                bcc .lo
                lda #$0E                ; high: 8-15
.lo:            sta via_pcr
                lda via_ora
                eor #$FF
                sta rows,x
                inx
                cpx #16
                bne .col
                rts

; the boxes: rows 0-7 at tile rows 4-11, columns 0-15 at tiles 8-23
grid:           ldy #0                  ; the row
.row:           rep #$20
                longa = on
                tya
                clc
                adc #4
                asl a
                asl a
                asl a
                asl a
                asl a
                clc
                adc #$1808
                tax
                sep #$20
                longa = off
                jsr wraddr
                ldx #0                  ; the column
.key:           lda #0                  ; 8-14: nothing
                cpx #8
                bcc .wired
                cpx #15
                bcc .put
.wired:         lda rows,x
                and bits,y
                beq .box
                lda #2
                bra .put
.box:           lda #1
.put:           sta vdp_data
                inx
                cpx #16
                bne .key
                iny
                cpy #8
                bne .row
                rts

; the ball moved by the joystick (column 15: up, down, left, right, fire)
joy:            lda rows+15
                lsr a
                bcc .nu
                dec by
                dec by
.nu:            lsr a
                bcc .nd
                inc by
                inc by
.nd:            lsr a
                bcc .nl
                dec bx
                dec bx
.nl:            lsr a
                bcc .nr
                inc bx
                inc bx
.nr:            ldx #$1B00
                jsr wraddr
                lda by
                sta vdp_data
                lda bx
                sta vdp_data
                stz vdp_data
                lda rows+15
                and #$10
                beq .cold
                lda #$08                ; fire: red
                bra .colour
.cold:          lda #$0B
.colour:        sta vdp_data
                lda #$D0
                sta vdp_data
                rts

; register x (0-7) := A
setreg:         sta vdp_ctl
                txa
                ora #$80
                sta vdp_ctl
                rts

regs8:          ldy #0
.reg:           lda 0,x
                phx
                tyx
                jsr setreg
                plx
                inx
                iny
                cpy #8
                bne .reg
                rts

; the address x set up for a write
wraddr:         rep #$20
                longa = on
                txa
                ora #$4000
                sep #$20
                longa = off
                sta vdp_ctl
                xba
                sta vdp_ctl
                rts

waitf:          lda vdp_ctl
.untilf:        lda vdp_ctl
                bpl .untilf
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

regs:           data.b $00, $C0, $06, $80, $00, $36, $07, $04
pats:           data.b $FF, $81, $81, $81, $81, $81, $81, $FF
                data.b $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
ball:           data.b $3C, $7E, $FF, $FF, $FF, $FF, $7E, $3C
bits:           data.b $01, $02, $04, $08, $10, $20, $40, $80
scc_init:       data.b 9, $C0, 4, $44, 3, $C1, 5, $6A, 11, $50, 12, 0, 13, 0, 14, $03, $FF
s_hello:        text.0 "mini816kbd: the keys on the VDP; a key here stops it", 13, 10

                fill $FFEA-pc, $FF
                data.w nmi
                fill $FFEE-pc, $FF
                data.w irq
                fill $FFFC-pc, $FF
                data.w reset, reset
