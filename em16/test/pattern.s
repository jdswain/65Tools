; pattern.s - a boot ROM for em16 -fpga that draws with the blitter's
; patterns (EmBlit: CONTROL bit 3, PAT_Y, PATTERN at $03E0), as OS16's
; GraphicsCore does on the 640-pixel screen: five blits into a 64 x 12
; pixel corner of a 640-wide pixel map at $01:0000, with odd left and right
; edges, every pattern row first, the four transfer modes (copy, OR, XOR,
; BIC), fill set as well (the pattern wins) and a transparent colour. Then
; a sixth, a no-op (OP 5, D), with a PATTERN write while it is busy, which
; must be ignored. It prints CONTROL, PAT_Y and two pattern bytes read
; back, then the corner's bytes, a row a line; test/pattern.sh checks them
; against a model of its own.

                cpu = "65C816"
                org = $E000

blt             = $03C0
bltDst          = blt+$04
bltSStr         = blt+$08
bltDStr         = blt+$0A
bltW            = blt+$0C
bltH            = blt+$0E
bltOp           = blt+$10
bltCol          = blt+$11
bltCtl          = blt+$12
bltPatY         = blt+$13
bltPat          = blt+$20
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

                ldx #0                  ; the pattern
.pat:           lda pattern,x
                sta bltPat,x
                inx
                cpx #32
                bne .pat
                lda #<640
                sta bltDStr
                lda #>640
                sta bltDStr+1

                ldx #0                  ; the blits
.next:          jsr blit
                txa
                cmp #6*11
                bne .next

                lda #$EE                ; ignored: the sixth is still busy
                sta bltPat
                jsr wait

                ldx #s_ctl
                jsr puts
                lda bltCtl
                jsr hex
                lda bltPatY
                jsr hex
                lda bltPat
                jsr hex
                lda bltPat+31
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

; the blit at blits+X, X moved on to the next; returns at once, busy
blit:           jsr wait
                lda blits,x             ; DST, a pixel address
                sta bltDst
                lda blits+1,x
                sta bltDst+1
                lda blits+2,x
                sta bltDst+2
                lda blits+3,x
                sta bltW
                lda blits+4,x
                sta bltW+1
                lda blits+5,x
                sta bltH
                lda blits+6,x
                sta bltH+1
                lda blits+7,x
                sta bltOp
                lda blits+8,x
                sta bltCol
                lda blits+9,x
                sta bltPatY
                lda blits+10,x
                sta bltCtl
                rep #$20
                longa = on
                txa
                clc
                adc #11
                tax
                sep #$20
                longa = off
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
; DST (3), WIDTH (2), HEIGHT (2), OP, COLOUR, PAT_Y, CONTROL
blits:          data.b $03, $00, $02, 21, 0, 3, 0, 3, $00, 5, $09     ; copy
                data.b $81, $07, $02, 6, 0, 2, 0, 7, $0F, 0, $0B      ; OR, fill too
                data.b $87, $0C, $02, 50, 0, 4, 0, 6, $00, 3, $09     ; XOR
                data.b $82, $16, $02, 33, 0, 3, 0, 4, $00, 7, $09     ; BIC
                data.b $28, $00, $02, 17, 0, 12, 0, 3, $90, 2, $0D    ; copy, 9 transparent
                data.b $00, $00, $02, 64, 0, 12, 0, 5, $00, 6, $09    ; D: a no-op

pattern:        data.b $1E, $9C, $35, $A9, $90, $47, $C2, $D8
                data.b $6B, $F0, $29, $83, $5A, $E9, $07, $B4
                data.b $99, $12, $7D, $C6, $48, $A3, $F9, $0E
                data.b $D1, $69, $8F, $24, $B7, $5C, $E3, $9A

s_ctl:          text.0 "ctl "
s_done:         text.0 "pattern: done", 13, 10

                fill $FFFC-pc, $FF
                data.w reset, reset
