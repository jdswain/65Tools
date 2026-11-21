; mini816vdp.s - a boot ROM for em16 -mini816 that checks the TMS9118 and
; the keyboard. The first byte on channel A picks the test:
;   f  the VDP's ports and flags, printing "vdp: ok" or "vdp: fail" and
;      the check's number:
;      1. VRAM written and read, the address wrapping at $3FFF.
;      2. A read's setup reads ahead: a write then goes one further.
;      3. A status read resets the setup's latch.
;      4. F with IE clear: no CB1. With IE set: CB1's flag, and F.
;      5. 60 frames by CB1's IRQ in 146-148 of timer 1's 50000 cycles
;         (59.92 Hz: 147.6; WAI between, so that PHI2 is nearly the
;         wall's time), timed from a frame's IRQ.
;      6. Four sprites on a line: no 5S. Five: 5S and 4, in the frame.
;      7. Two sprites overlapping: C, though one is transparent; apart,
;         or the second a fifth on its line: none.
;   k  the keyboard: each column selected (PB0-PB2, CA2 by PCR) and its
;      rows read; prints "keys:" and each key down as column and row.
;   g h 2 3 m t b  a display mode: VRAM filled from a 16-bit xorshift
;      (7, 9, 8) from 1, its low byte a byte, the sprites' table then
;      written, the registers set; two frames waited, for -fbdump, and
;      "frame" printed. test/mini816vdp.sh draws the frame from the same
;      VRAM and compares.
; Then it stops (STP).

                cpu = "65C816"
                org = $E000

via_ora         = $C00F         ; port A, no handshake
via_orb         = $C000
via_ddrb        = $C002
via_t1cl        = $C004
via_t1ch        = $C005
via_acr         = $C00B
via_pcr         = $C00C
via_ifr         = $C00D
via_ier         = $C00E
scc_actl        = $C012
scc_adat        = $C013
vdp_data        = $C020
vdp_ctl         = $C021

seed            = $10           ; the xorshift's state, 2 bytes
acc             = $12           ; the status bits seen
st5             = $13           ; the status read with 5S
t1n             = $14           ; timer 1's IRQs
vn              = $15           ; the VDP's IRQs
col             = $16
tmp             = $17

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
                jsr getc
                sta col
                ldx #modes
.find:          lda 0,x                 ; the mode's character, its registers
                beq .none
                cmp col
                beq .found
                inx
                inx
                inx
                inx
                inx
                inx
                inx
                inx
                inx
                bra .find
.none:          lda col
                cmp #'f'
                bne .notf
                jmp flags
.notf:          cmp #'k'
                bne .notk
                jmp keys
.notk:          stp
.found:         inx
                stx tmp                 ; 2 bytes: tmp, tmp+1
                jmp draw

; --- a display mode ----------------------------------------------------

draw:           lda #$80                ; blank while VRAM is filled
                ldx #1
                jsr setreg
                jsr vfill
                ldx tmp                 ; the SAT's base: R5 * $80
                lda 5,x
                rep #$20
                longa = on
                and #$007F
                asl a
                asl a
                asl a
                asl a
                asl a
                asl a
                asl a
                tax
                sep #$20
                longa = off
                jsr wraddr
                ldx #sprites
.sat:           lda 0,x
                sta vdp_data
                inx
                cpx #sprites_end
                bne .sat
                ldx tmp
                jsr regs8
                jsr waitf
                jsr waitf
                ldx #s_frame
                jsr puts
                stp

; VRAM from the xorshift
vfill:          ldx #0
                jsr wraddr
                rep #$20
                longa = on
                lda #1
                sta seed
                ldy #$4000
.gen:           lda seed
                asl a
                asl a
                asl a
                asl a
                asl a
                asl a
                asl a
                eor seed
                sta seed
                lsr a
                lsr a
                lsr a
                lsr a
                lsr a
                lsr a
                lsr a
                lsr a
                lsr a
                eor seed
                sta seed
                xba
                and #$FF00
                eor seed
                sta seed
                sep #$20
                longa = off
                sta vdp_data
                rep #$20
                longa = on
                dey
                bne .gen
                sep #$20
                longa = off
                rts

; --- the keyboard ------------------------------------------------------

keys:           lda #$20                ; the SD card's CS high
                sta via_orb
                lda #$BF
                sta via_ddrb
                ldx #s_keys
                jsr puts
                stz col
.col:           lda col
                and #7
                ora #$20
                sta via_orb
                lda col
                cmp #8
                lda #$0C                ; CA2 low: columns 0-7
                bcc .lo
                lda #$0E                ; high: 8-15
.lo:            sta via_pcr
                lda via_ora
                sta tmp
                ldy #0
.row:           lsr tmp
                bcs .up
                lda #' '
                jsr putc
                lda col
                jsr nib
                tya
                jsr nib
.up:            iny
                cpy #8
                bne .row
                inc col
                lda col
                cmp #16
                bne .col
                lda #13
                jsr putc
                lda #10
                jsr putc
                stp

; --- the flags ---------------------------------------------------------

flags:          ldx #$3FFE              ; 1. write, the address wrapping
                jsr wraddr
                lda #$11
                sta vdp_data
                lda #$22
                sta vdp_data
                lda #$33
                sta vdp_data
                ldx #$3FFE
                jsr rdaddr
                lda vdp_data
                cmp #$11
                bne .bad1
                lda vdp_data
                cmp #$22
                bne .bad1
                lda vdp_data
                cmp #$33
                bne .bad1
                ldx #0
                jsr rdaddr
                lda vdp_data
                cmp #$33
                beq .c2
.bad1:          lda #1
                jmp fail

.c2:            ldx #$3FFE              ; 2. read ahead: the write goes to $3FFF
                jsr rdaddr
                lda #$44
                sta vdp_data
                ldx #$3FFF
                jsr rdaddr
                lda vdp_data
                cmp #$44
                bne .bad2
                ldx #$3FFE
                jsr rdaddr
                lda vdp_data
                cmp #$11
                beq .c3
.bad2:          lda #2
                jmp fail

.c3:            lda #$55                ; 3. a status read resets the latch
                sta vdp_ctl
                lda vdp_ctl
                ldx #$0010
                jsr wraddr
                lda #$66
                sta vdp_data
                ldx #$0010
                jsr rdaddr
                lda vdp_data
                cmp #$66
                beq .c4
                lda #3
                jmp fail

.c4:            ldx #regs_f             ; 4. Graphics I, IE clear
                jsr regs8
                lda #$7F
                sta via_ifr
                jsr waitf
                lda via_ifr
                and #$10
                bne .bad4
                lda #$E0                ; IE
                ldx #1
                jsr setreg
                ldx #0
.w4:            lda via_ifr
                and #$10
                bne .cb1
                dex
                bne .w4
                bra .bad4
.cb1:           lda vdp_ctl
                bmi .c5
.bad4:          lda #4
                jmp fail

.c5:            lda #$10                ; 5. 60 frames by CB1's IRQ, timed by T1
                sta via_ifr
                stz t1n
                stz vn
                lda #$40                ; T1 free run
                sta via_acr
                lda #$D0                ; T1 and CB1 interrupt
                sta via_ier
                lda #<49998
                sta via_t1cl
                lda #>49998
                sta via_t1ch
                lda vdp_ctl
                cli
.w0:            wai                     ; from a frame's IRQ: T1 started again
                lda vn
                beq .w0
                sei
                lda #>49998
                sta via_t1ch
                stz t1n
                stz vn
                cli
.w5:            wai
                lda vn
                cmp #60
                bcc .w5
                sei
                lda #$7F
                sta via_ier
                lda t1n
                cmp #146
                bcc .bad5
                cmp #149
                bcc .c6
.bad5:          lda #5
                jmp fail

.c6:            lda #$C0                ; 6. 5S: four on a line, then five
                ldx #1
                jsr setreg
                ldx #$3800              ; sprite pattern 0 solid
                jsr wraddr
                ldy #8
                lda #$FF
.p0:            sta vdp_data
                dey
                bne .p0
                ldx #sat_4
                jsr frame
                and #$40
                bne .bad6
                ldx #sat_5
                jsr frame
                lda st5
                and #$5F
                cmp #$44
                beq .c7
.bad6:          lda #6
                jmp fail

.c7:            ldx #sat_c              ; 7. coincidence
                jsr frame
                and #$20
                beq .bad7
                ldx #sat_nc
                jsr frame
                and #$20
                bne .bad7
                ldx #sat_5c
                jsr frame
                and #$60
                cmp #$40
                beq .ok
.bad7:          lda #7
                jmp fail
.ok:            ldx #s_ok
                jsr puts
                stp

; The SAT at x (to a Y of $D0) written; a frame waited for, then the
; status bits of the next frame in A and acc, the one with 5S in st5
frame:          phx
                ldx #$1B00
                jsr wraddr
                plx
.copy:          lda 0,x
                sta vdp_data
                inx
                cmp #$D0
                beq .end
                lda 0,x
                sta vdp_data
                inx
                lda 0,x
                sta vdp_data
                inx
                lda 0,x
                sta vdp_data
                inx
                bra .copy
.end:           jsr waitf
                stz acc
                stz st5
.poll:          lda vdp_ctl
                bit #$40
                beq .no5
                sta st5
.no5:           tsb acc
                bit #$80
                beq .poll
                lda acc
                rts

; --- the VDP -----------------------------------------------------------

; register x (0-7) := A
setreg:         sta vdp_ctl
                txa
                ora #$80
                sta vdp_ctl
                rts

; the 8 registers from x
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

; the address x set up for a write, or (rdaddr) a read
wraddr:         rep #$20
                longa = on
                txa
                ora #$4000
                bra setaddr
rdaddr:         rep #$20
                txa
setaddr:        sep #$20
                longa = off
                sta vdp_ctl
                xba
                sta vdp_ctl
                rts

; F: cleared, then waited for
waitf:          lda vdp_ctl
.untilf:        lda vdp_ctl
                bpl .untilf
                rts

; --- the rest ----------------------------------------------------------

irq:            pha
                lda via_ifr
                and #$40
                beq .vdp
                lda via_t1cl
                inc t1n
                bra .out
.vdp:           lda via_ifr
                and #$10
                beq .out
                lda vdp_ctl
                lda #$10
                sta via_ifr
                inc vn
.out:           pla
                rti

nmi:            rti

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
                jsr nib
                pla
nib:            and #$0F
                cmp #10
                bcc .dig
                adc #6
.dig:           adc #$30
                jmp putc

; the display modes: the character, R0-R7
modes:          data.b 'g', $00, $C0, $06, $80, $00, $36, $07, $F4   ; Graphics I, 8 x 8
                data.b 'h', $00, $C3, $06, $80, $00, $36, $07, $15   ; Graphics I, 16 x 16 magnified
                data.b '2', $02, $C2, $0E, $FF, $03, $76, $03, $01   ; Graphics II, 16 x 16
                data.b '3', $02, $C1, $0E, $9F, $00, $76, $03, $0C   ; Graphics II, the tables masked
                data.b 'm', $00, $C9, $02, $00, $00, $20, $03, $0D   ; multicolour, magnified
                data.b 't', $00, $D0, $02, $00, $00, $20, $03, $F5   ; text
                data.b 'b', $00, $80, $06, $80, $00, $36, $07, $06   ; blank
                data.b 0

; the flags' registers: Graphics I, SAT $1B00, sprites at $3800
regs_f:         data.b $00, $C0, $06, $80, $00, $36, $07, $01

; the display modes' sprites: Y, X, name, colour (bit 7 the early clock)
sprites:        data.b 20, 30, 1, $0F
                data.b 24, 34, 2, $00           ; transparent, over 2
                data.b 26, 36, 3, $08
                data.b 100, 250, 4, $8A         ; the early clock: X 218
                data.b 100, 10, 5, $03
                data.b 100, 60, 6, $0C
                data.b 100, 90, 7, $0D          ; a fifth on its lines with 3-6
                data.b 100, 120, 8, $0E
                data.b $F8, 200, 9, $09         ; above the top
                data.b 185, 245, 10, $07        ; at the bottom right
                data.b $D0, 0, 0, 0
                data.b 50, 50, 11, $02          ; after the end: not there
sprites_end:

; the flags' sprites, pattern 0 solid
sat_4:          data.b 50, 0, 0, 1, 50, 20, 0, 1, 50, 40, 0, 1, 50, 60, 0, 1, 150, 80, 0, 1, $D0
sat_5:          data.b 50, 0, 0, 1, 50, 20, 0, 1, 50, 40, 0, 1, 50, 60, 0, 1, 52, 80, 0, 1, $D0
sat_c:          data.b 80, 80, 0, $00, 83, 84, 0, $0F, $D0
sat_nc:         data.b 80, 80, 0, $00, 83, 100, 0, $0F, $D0
sat_5c:         data.b 50, 0, 0, 1, 50, 20, 0, 1, 50, 40, 0, 1, 50, 60, 0, 1, 50, 2, 0, 1, $D0

scc_init:       data.b 9, $C0, 4, $44, 3, $C1, 5, $6A, 11, $50, 12, 0, 13, 0, 14, $03, $FF

s_hello:        text.0 "mini816vdp test", 13, 10
s_frame:        text.0 "frame", 13, 10
s_keys:         text.0 "keys:"
s_ok:           text.0 "vdp: ok", 13, 10
s_fail:         text.0 "vdp: fail "

                fill $FFEA-pc, $FF
                data.w nmi
                fill $FFEE-pc, $FF
                data.w irq
                fill $FFFC-pc, $FF
                data.w reset, reset
