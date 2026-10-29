; expand.s - a boot ROM for em16 -fpga that draws 1-bit glyphs with the
; blitter's colour expansion (EmBlit: CONTROL bit 4, BACKGROUND at $14), as
; OS16's GraphicsCore draws text: five blits into a 64 x 12 pixel corner of a
; 640-wide pixel map at $01:0000, from glyph bytes copied to $01:8000. Widths
; that are not multiples of 8, odd and even destinations, glyph rows going up
; the screen (DST_STRIDE -640), a negative source stride too, background and
; transparent, OR and XOR, a source line on an odd byte, and fill set as well
; (fill wins). It prints CONTROL, then the corner's bytes, a row a line;
; test/expand.sh checks them against a model of its own.

                cpu = "65C816"
                org = $E000

blt             = $03C0
bltCtl          = blt+$12
scc_ctl         = $0822
scc_data        = $0823

rows            = $10           ; the dump's rows left
row             = $12           ; the dump's row start

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

                ldx #0                  ; the pixel map's 12 rows: 3, 10, 17 ...
                lda #3
.init:          sta.l $010000,x
                clc
                adc #7
                inx
                cpx #12*320
                bne .init

                ldx #0                  ; the glyphs, into SDRAM
.gl:            lda glyphs,x
                sta.l $018000,x
                inx
                cpx #64
                bne .gl

                ldx #0                  ; the blits
.next:          jsr blit
                cpx #5*21
                bne .next
                jsr wait

                ldx #s_ctl
                jsr puts
                lda bltCtl
                jsr hex
                jsr crlf

                lda #12                 ; the corner: 32 bytes of each row
                sta rows
                ldx #0
.row:           stx row
                ldy #32
.byte:          lda.l $010000,x
                jsr hex
                inx
                dey
                bne .byte
                jsr crlf
                rep #$20
                longa = on
                lda row
                clc
                adc #320
                tax
                sep #$20
                longa = off
                dec rows
                bne .row
                ldx #s_done
                jsr puts
                stp

; the blit at blits+X, its registers $00-$14 in order, X moved on to the
; next; CONTROL ($12) last, as it starts the blit. Returns at once, busy.
blit:           jsr wait
                ldy #0
.reg:           cpy #$12
                beq .skip
                lda blits,x
                sta blt,y
.skip:          inx
                iny
                cpy #$15
                bne .reg
                lda blits-3,x           ; CONTROL
                sta bltCtl
                rts

wait:           lda bltCtl
                bmi wait
                rts

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

; the pixel address of (x, y) in the map: 2 * $010000 + 640y + x
; SRC (3), -, DST (3), -, SRC_STRIDE, DST_STRIDE, WIDTH, HEIGHT (2 each),
; OP, COLOUR, CONTROL, PAT_Y, BACKGROUND
blits:          data.b $00, $80, $01, 0, $83, $1B, $02, 0     ; (3, 11) up
                data.b $01, $00, $80, $FD, 5, 0, 12, 0, 3, $0C, $11, 0, 5
                data.b $10, $80, $01, 0, $0A, $00, $02, 0     ; (10, 0) down
                data.b $02, $00, $80, $02, 13, 0, 8, 0, 3, $07, $15, 0, 0
                data.b $2A, $80, $01, 0, $1D, $14, $02, 0     ; (29, 8) up, src up
                data.b $FE, $FF, $80, $FD, 16, 0, 6, 0, 6, $0F, $11, 0, 3
                data.b $31, $80, $01, 0, $30, $0F, $02, 0     ; (48, 6), odd byte
                data.b $03, $00, $80, $02, 7, 0, 5, 0, 7, $0A, $15, 0, 0
                data.b $00, $80, $01, 0, $BA, $02, $02, 0     ; (58, 1), fill wins
                data.b $01, $00, $80, $02, 4, 0, 3, 0, 3, $09, $13, 0, 2

glyphs:         data.b $70, $88, $98, $A8, $C8, $88, $70, $00
                data.b $F8, $20, $50, $D8, $1E, $9C, $35, $A9
                data.b $90, $47, $C2, $D8, $6B, $F0, $29, $83
                data.b $5A, $E9, $07, $B4, $99, $12, $7D, $C6
                data.b $48, $A3, $F9, $0E, $D1, $69, $8F, $24
                data.b $B7, $5C, $E3, $9A, $FF, $01, $80, $3C
                data.b $C3, $66, $18, $E7, $81, $5A, $A5, $0F
                data.b $F0, $33, $CC, $55, $AA, $96, $69, $00

s_ctl:          text.0 "ctl "
s_done:         text.0 "expand: done", 13, 10

                fill $FFFC-pc, $FF
                data.w reset, reset
