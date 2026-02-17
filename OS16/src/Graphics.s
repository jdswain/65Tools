; Graphics.s
    cpu="816"
    longa=on
    longi=on
    import Out

    .proc InitGraphics()
	.proc SetPixel(INTEGER, INTEGER, BYTE)
	.proc GetPixel(INTEGER, INTEGER): BYTE

	.proc FillRect(INTEGER, INTEGER, INTEGER, INTEGER, INTEGER)
	.proc DrawLine(INTEGER, INTEGER, INTEGER, INTEGER, BYTE, BYTE)

; SetPixel(x, y, c) - R[0]=x, R[1]=y, R[2]=c
; Video: bank 2, 160 bytes/row, 4 pixels/byte (2-bit color)
; addr = y * 160 + x DIV 4
SetPixel*:
    ; Save params to temp DP regs
    lda $02             ; x
    sta $08             ; R[3] = x
    lda $04             ; y
    sta $0A             ; R[4] = y
    lda $06             ; c
    and #$0003          ; c MOD 4
    sta $0C             ; R[5] = c (masked)

    ; Compute addr = y * 160 + x DIV 4
    ; y * 160 = y * 128 + y * 32 = y<<7 + y<<5
    lda $0A             ; y
    asl
    asl
    asl
    asl
    asl                 ; y * 32
    sta $02             ; temp = y*32
    asl
    asl                 ; y * 128
    clc
    adc $02             ; y*128 + y*32 = y*160
    sta $02             ; R[0] = y*160

    ; x DIV 4
    lda $08             ; x
    lsr
    lsr                 ; x / 4
    clc
    adc $02             ; addr = y*160 + x/4
    sta $0E             ; R[6] = addr (low 16 bits)

    ; Set up bank: 2 (video starts at bank 2)
    ; For y > 409: bank 3, else bank 2
    lda $0A             ; y
    cmp #410
    lda #$02            ; default bank 2
    bcc .bank_ok
    lda #$03            ; bank 3
.bank_ok:
    sta $10             ; bank byte at $10 (16-bit store, high byte=0)

    ; Read byte at [bank:addr]
    ldy #0
    longa=off
    sep #$20            ; 8-bit to read one byte
    lda [$0E],y         ; read pixel byte
    rep #$20
    longa=on
    and #$00FF          ; zero-extend
    sta $02             ; R[0] = val (current byte)

    ; Compute pos = x MOD 4
    lda $08             ; x
    and #$0003          ; pos = x MOD 4
    ; Branch on pos
    cmp #0
    beq .pos0
    cmp #1
    beq .pos1
    cmp #2
    beq .pos2
    bra .pos3

.pos0:
    ; val = val MOD $40 + c * $40
    lda $02
    and #$003F          ; val MOD $40
    sta $02
    lda $0C             ; c
    asl
    asl
    asl
    asl
    asl
    asl                 ; c * $40
    ora $02
    sta $02
    bra .write

.pos1:
    ; val = (val DIV $40) * $40 + c * $10 + val MOD $10
    lda $02
    and #$00C0          ; val DIV $40 * $40 (keep top 2 bits)
    sta $04             ; temp high
    lda $02
    and #$000F          ; val MOD $10
    ora $04             ; high + low
    sta $02
    lda $0C             ; c
    asl
    asl
    asl
    asl                 ; c * $10
    ora $02
    sta $02
    bra .write

.pos2:
    ; val = (val DIV $10) * $10 + c * 4 + val MOD 4
    lda $02
    and #$00F0          ; val DIV $10 * $10 (keep top 4 bits)
    sta $04             ; temp high
    lda $02
    and #$0003          ; val MOD 4
    ora $04             ; high + low
    sta $02
    lda $0C             ; c
    asl
    asl                 ; c * 4
    ora $02
    sta $02
    bra .write

.pos3:
    ; val = (val DIV 4) * 4 + c
    lda $02
    and #$00FC          ; val DIV 4 * 4 (keep top 6 bits)
    ora $0C             ; + c
    sta $02

.write:
    ; Write byte back at [bank:addr]
    lda $02
    ldy #0
    longa=off
    sep #$20            ; 8-bit store
    sta [$0E],y
    rep #$20
    longa=on
    rtl

; GetPixel(x, y): BYTE - R[0]=x, R[1]=y, result in R[0]
; Returns the 2-bit color value at pixel (x, y)
GetPixel*:
    ; Compute addr = y * 160 + x DIV 4
    lda $02
    sta $08             ; R[3] = x
    lda $04             ; y
    asl
    asl
    asl
    asl
    asl                 ; y * 32
    sta $02             ; temp
    asl
    asl                 ; y * 128
    clc
    adc $02             ; y * 160
    sta $02
    lda $08             ; x
    lsr
    lsr                 ; x / 4
    clc
    adc $02             ; addr = y*160 + x/4
    sta $0E             ; R[6] = addr

    ; Bank
    lda $04             ; y
    cmp #410
    lda #$02            ; default bank 2
    bcc .gbank_ok
    lda #$03            ; bank 3
.gbank_ok:
    sta $10             ; 16-bit store, high byte=0

    ; Read byte
    ldy #0
    longa=off
    sep #$20            ; 8-bit to read one byte
    lda [$0E],y
    rep #$20
    longa=on
    and #$00FF
    sta $02             ; val

    ; Extract pixel at pos = x MOD 4
    lda $08             ; x
    and #$0003
    cmp #0
    beq .gpos0
    cmp #1
    beq .gpos1
    cmp #2
    beq .gpos2
    bra .gpos3

.gpos0:
    lda $02
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr                 ; val DIV $40
    sta $02
    bra .gdone

.gpos1:
    lda $02
    lsr
    lsr
    lsr
    lsr                 ; val DIV $10
    and #$0003          ; MOD 4
    sta $02
    bra .gdone

.gpos2:
    lda $02
    lsr
    lsr                 ; val DIV 4
    and #$0003          ; MOD 4
    sta $02
    bra .gdone

.gpos3:
    lda $02
    and #$0003          ; val MOD 4
    sta $02

.gdone:
    rtl

; DrawLine(x1, y1, x2, y2, width, color)
; R[0]=$02=x1, R[1]=$04=y1, R[2]=$06=x2, R[3]=$08=y2, R[4]=$0A=width, R[5]=$0C=color
;
; DP usage — uses compiler's free registers + FP workspace:
;   R[8]-R[14] ($12-$1E): not clobbered by SetPixel, caller saves via SaveRegs
;     $12=cx  $14=cy  $16=end_x  $18=end_y
;     $1A=dx  $1C=dy  $1E=sx
;   SB_TEMP + FP workspace ($20-$3C): safe during external JSL calls
;     $20=sy  $22=gradient  $24=color  $26=width
;     $28=orig_x1  $2A=orig_y1  $2C=orig_x2  $2E=orig_y2
;     $30=perp_is_y  $32=width_offset
;     $34=major_steps  $36=minor_int  $38=minor_frac
;     $3A=is_x_major  $3C=remainder
;   $00 (SB) is NOT touched.
;
DrawLine*:
    ; Save params to safe DP area
    lda $02
    sta $28             ; orig_x1
    lda $04
    sta $2A             ; orig_y1
    lda $06
    sta $2C             ; orig_x2
    lda $08
    sta $2E             ; orig_y2
    lda $0A
    sta $26             ; width
    lda $0C
    and #$0003
    sta $24             ; color (2-bit)

    ; Compute dx = abs(x2 - x1)
    lda $2C
    sec
    sbc $28
    bpl .dl_dxp
    eor #$FFFF
    inc a
.dl_dxp:
    sta $1A             ; dx

    ; Compute dy = abs(y2 - y1)
    lda $2E
    sec
    sbc $2A
    bpl .dl_dyp
    eor #$FFFF
    inc a
.dl_dyp:
    sta $1C             ; dy

    ; Perpendicular direction for width:
    ; if dx >= dy, width offsets y; else width offsets x
    lda $1A
    cmp $1C
    bcc .dl_perpx
    lda #1
    sta $30             ; perp_is_y = 1
    bra .dl_winit
.dl_perpx:
    stz $30             ; perp_is_y = 0

.dl_winit:
    stz $32             ; width_offset = 0

.dl_wloop:
    lda $32
    cmp $26
    bcc .dl_wok         ; offset < width, continue
    rtl                 ; done

.dl_wok:
    ; Apply width offset to endpoints
    lda $30
    beq .dl_woffx

    ; Offset in y direction
    lda $28
    sta $12             ; cx = orig_x1
    lda $2A
    clc
    adc $32
    sta $14             ; cy = orig_y1 + offset
    lda $2C
    sta $16             ; end_x = orig_x2
    lda $2E
    clc
    adc $32
    sta $18             ; end_y = orig_y2 + offset
    bra .dl_dispatch

.dl_woffx:
    ; Offset in x direction
    lda $28
    clc
    adc $32
    sta $12             ; cx = orig_x1 + offset
    lda $2A
    sta $14             ; cy = orig_y1
    lda $2C
    clc
    adc $32
    sta $16             ; end_x = orig_x2 + offset
    lda $2E
    sta $18             ; end_y = orig_y2

.dl_dispatch:
    lda $14
    cmp $18
    beq .dl_horiz       ; cy == end_y: horizontal
    lda $12
    cmp $16
    beq .dl_vert        ; cx == end_x: vertical
    brl .dl_wu          ; Wu's antialiased line

; ---- Horizontal line (cy == end_y) ----
.dl_horiz:
    ; Ensure cx <= end_x (swap if needed)
    lda $12
    cmp $16
    bcc .dl_hloop       ; cx < end_x, ordered
    beq .dl_hloop       ; cx == end_x, single pixel
    ; Swap cx and end_x
    ldx $16
    sta $16
    stx $12
.dl_hloop:
    lda $12
    sta $02
    lda $14
    sta $04
    lda $24
    sta $06
    jsl SetPixel
    lda $12
    cmp $16
    beq .dl_hend        ; reached end_x
    inc a
    sta $12
    bra .dl_hloop
.dl_hend:
    brl .dl_wnext

; ---- Vertical line (cx == end_x) ----
.dl_vert:
    ; Ensure cy <= end_y (swap if needed)
    lda $14
    cmp $18
    bcc .dl_vloop       ; cy < end_y, ordered
    beq .dl_vloop       ; cy == end_y, single pixel
    ; Swap cy and end_y
    ldx $18
    sta $18
    stx $14
.dl_vloop:
    lda $12
    sta $02
    lda $14
    sta $04
    lda $24
    sta $06
    jsl SetPixel
    lda $14
    cmp $18
    beq .dl_vend        ; reached end_y
    inc a
    sta $14
    bra .dl_vloop
.dl_vend:
    brl .dl_wnext

; ---- Wu's Antialiased Line ----
; Wu's algorithm: step along major axis, draw 2 pixels per step
; with intensity based on fractional distance from ideal line.
;
; gradient = (minor_delta * 256) / major_delta  (0..255 fixed-point)
; For each major step:
;   main pixel  intensity = color * (256 - frac) / 256
;   secondary pixel intensity = color * frac / 256
;
; Intensity mapping for 2-bit color (0-3):
;   color * (256-frac)/256 rounded:
;     result = (color * coverage + 128) >> 8
;   With 4 levels we use: 0 -> draw nothing, 1/2/3 -> draw that color
;
.dl_wu:
    ; Compute sx = sign(end_x - cx)
    lda $16
    cmp $12
    bcc .wu_sxn
    beq .wu_sxn
    lda #1
    sta $1E             ; sx = +1
    bra .wu_sy
.wu_sxn:
    lda #$FFFF
    sta $1E             ; sx = -1

.wu_sy:
    ; Compute sy = sign(end_y - cy)
    lda $18
    cmp $14
    bcc .wu_syn
    beq .wu_syn
    lda #1
    sta $20             ; sy = +1
    bra .wu_major
.wu_syn:
    lda #$FFFF
    sta $20             ; sy = -1

.wu_major:
    ; Determine major axis: x-major if dx >= dy, else y-major
    lda $1A             ; dx
    cmp $1C             ; dy
    bcs .wu_xmajor
    brl .wu_ymajor
.wu_xmajor:
    ; ---- X-MAJOR Wu's line ----
    lda #1
    sta $3A             ; is_x_major = 1

    ; major_steps = dx
    lda $1A
    sta $34

    ; Compute gradient = (dy * 256) / dx  (8-bit fixed-point)
    ; Binary long division: gradient = 0, rem = dy
    ; for i = 7 downto 0: rem*=2; if rem>=dx: rem-=dx, gradient|=(1<<i)
    stz $22             ; gradient = 0
    lda $1C             ; remainder = dy
    sta $3C             ; remainder in DP (preserved across mask update)
    ldx #$0080          ; bit mask starting at bit 7

.wu_xdiv:
    asl $3C             ; rem *= 2 (memory-mode ASL)
    lda $3C             ; A = rem
    cmp $1A             ; rem >= dx?
    bcc .wu_xdnext
    sbc $1A             ; rem -= dx (carry already set from cmp)
    sta $3C             ; save updated remainder
    txa
    ora $22
    sta $22             ; gradient |= bit
.wu_xdnext:
    txa
    lsr                 ; shift bit mask right
    tax
    bne .wu_xdiv        ; loop while bits remain

    ; $22 = gradient (0..255), $12=cx, $14=cy=start y
    ; minor_int = cy, minor_frac = 0
    lda $14
    sta $36             ; minor_int = cy (y integer part)
    stz $38             ; minor_frac = 0

    ; Draw first endpoint at full intensity
    lda $12
    sta $02             ; x = cx
    lda $36
    sta $04             ; y = minor_int
    lda $24
    sta $06             ; color
    jsl SetPixel

    ; major_steps counter
    lda $34
    beq .wu_xdone       ; dx == 0, skip
    sta $34

.wu_xloop:
    ; Step major axis: cx += sx
    lda $12
    clc
    adc $1E
    sta $12

    ; Step minor axis fractionally: minor_frac += gradient
    lda $38             ; minor_frac
    clc
    adc $22             ; + gradient
    cmp #256
    bcc .wu_xnowrap
    ; Overflow: frac >= 256, step minor_int, wrap frac
    sec
    sbc #256
    sta $38
    lda $36             ; minor_int
    clc
    adc $20             ; += sy
    sta $36
    bra .wu_xdraw
.wu_xnowrap:
    sta $38

.wu_xdraw:
    ; Main pixel: always at full base color
    lda $24
    sta $06             ; color = base color
    lda $12
    sta $02             ; x = cx
    lda $36
    sta $04             ; y = minor_int
    jsl SetPixel

    ; Secondary (fringe) pixel: drawn at color-1 when frac > 64
    ; This gives smooth edges without dimming the main line
    lda $38             ; frac
    cmp #64
    bcc .wu_xskip2      ; frac too small, skip fringe
    lda $24             ; base color
    dec a               ; fringe = base_color - 1
    beq .wu_xskip2      ; if base was 1, fringe=0, skip
    sta $06             ; fringe color
    lda $12
    sta $02             ; x = cx
    lda $36
    clc
    adc $20             ; y = minor_int + sy
    sta $04
    jsl SetPixel
.wu_xskip2:

    ; Decrement step counter
    lda $34
    dec a
    sta $34
    bne .wu_xloop

.wu_xdone:
    brl .dl_wnext

    ; ---- Y-MAJOR Wu's line ----
.wu_ymajor:
    stz $3A             ; is_x_major = 0

    ; major_steps = dy
    lda $1C
    sta $34

    ; Compute gradient = (dx * 256) / dy
    ; Same 8-iteration binary division: gradient = 0, rem = dx
    stz $22             ; gradient = 0
    lda $1A             ; remainder = dx
    sta $3C             ; remainder in DP (preserved across mask update)
    ldx #$0080          ; bit mask

.wu_ydiv:
    asl $3C             ; rem *= 2 (memory-mode ASL)
    lda $3C             ; A = rem
    cmp $1C             ; rem >= dy?
    bcc .wu_ydnext
    sbc $1C             ; rem -= dy
    sta $3C             ; save updated remainder
    txa
    ora $22
    sta $22             ; gradient |= bit
.wu_ydnext:
    txa
    lsr
    tax
    bne .wu_ydiv

    ; $22 = gradient, $12=cx, $14=cy
    ; minor_int = cx (x integer part), minor_frac = 0
    lda $12
    sta $36             ; minor_int = cx
    stz $38             ; minor_frac = 0

    ; Draw first endpoint at full intensity
    lda $36
    sta $02             ; x = minor_int (cx)
    lda $14
    sta $04             ; y = cy
    lda $24
    sta $06             ; color
    jsl SetPixel

    ; major_steps counter
    lda $34
    beq .wu_ydone
    sta $34

.wu_yloop:
    ; Step major axis: cy += sy
    lda $14
    clc
    adc $20
    sta $14

    ; Step minor axis fractionally: minor_frac += gradient
    lda $38
    clc
    adc $22             ; + gradient
    cmp #256
    bcc .wu_ynowrap
    sec
    sbc #256
    sta $38
    lda $36
    clc
    adc $1E             ; minor_int += sx
    sta $36
    bra .wu_ydraw
.wu_ynowrap:
    sta $38

.wu_ydraw:
    ; Main pixel: always at full base color
    lda $24
    sta $06             ; color = base color
    lda $36
    sta $02             ; x = minor_int
    lda $14
    sta $04             ; y = cy
    jsl SetPixel

    ; Secondary (fringe) pixel: drawn at color-1 when frac > 64
    lda $38             ; frac
    cmp #64
    bcc .wu_yskip2      ; frac too small, skip fringe
    lda $24             ; base color
    dec a               ; fringe = base_color - 1
    beq .wu_yskip2      ; if base was 1, fringe=0, skip
    sta $06             ; fringe color
    lda $36
    clc
    adc $1E             ; x = minor_int + sx
    sta $02
    lda $14
    sta $04             ; y = cy
    jsl SetPixel
.wu_yskip2:

    lda $34
    dec a
    sta $34
    bne .wu_yloop

.wu_ydone:
    brl .dl_wnext

; ---- Width loop continuation ----
.dl_wnext:
    lda $32
    inc a
    sta $32
    brl .dl_wloop

; ============================================================
; FillRect(x, y, w, h, color) — fill a w×h rectangle at (x,y)
; R[0]=$02=x, R[1]=$04=y, R[2]=$06=w, R[3]=$08=h, R[4]=$0A=color
;
; DP working storage ($0C-$28):
;   $0C  fill_byte       $0E  left_col      $10  right_col
;   $12  mid_count       $14  left_fill     $16  left_mask
;   $18  right_fill      $1A  right_mask    $1C  row_base
;   $1E  bank            $20  rows_left     $22  same_byte
;   $24  cur_y           $26  saved_x       $28  saved_w
;   SB ($00) is NOT touched.
; ============================================================
FillRect*:
    ; Early exit if w <= 0 or h <= 0
    lda $06             ; w
    beq .fr_exit
    bmi .fr_exit
    lda $08             ; h
    beq .fr_exit
    bmi .fr_exit
    bra .fr_start
.fr_exit:
    rtl
.fr_start:

    ; Save params
    lda $02
    sta $26             ; saved_x
    lda $06
    sta $28             ; saved_w
    lda $04
    sta $24             ; cur_y
    lda $08
    sta $20             ; rows_left

    ; Build fill_byte: c | (c<<2) | (c<<4) | (c<<6)
    lda $0A
    and #$0003
    sta $0C
    asl
    asl
    ora $0C
    sta $0C
    asl
    asl
    asl
    asl
    ora $0C
    sta $0C             ; fill_byte

    ; left_col = x DIV 4
    lda $26
    lsr
    lsr
    sta $0E

    ; right_col = (x + w - 1) DIV 4
    lda $26
    clc
    adc $28
    dec a
    sta $02             ; temp = x+w-1
    lsr
    lsr
    sta $10

    ; Left mask: bits to KEEP for left_pos = x MOD 4
    ; pos 0: $00, pos 1: $C0, pos 2: $F0, pos 3: $FC
    lda $26
    and #$0003
    beq .fr_lm0
    cmp #1
    beq .fr_lm1
    cmp #2
    beq .fr_lm2
    lda #$00FC
    bra .fr_lmd
.fr_lm0:
    lda #$0000
    bra .fr_lmd
.fr_lm1:
    lda #$00C0
    bra .fr_lmd
.fr_lm2:
    lda #$00F0
.fr_lmd:
    sta $16             ; left_mask

    ; Right mask: bits to KEEP for right_pos = (x+w-1) MOD 4
    ; pos 0: $3F, pos 1: $0F, pos 2: $03, pos 3: $00
    lda $02
    and #$0003
    cmp #3
    beq .fr_rm3
    cmp #2
    beq .fr_rm2
    cmp #1
    beq .fr_rm1
    lda #$003F
    bra .fr_rmd
.fr_rm3:
    lda #$0000
    bra .fr_rmd
.fr_rm2:
    lda #$0003
    bra .fr_rmd
.fr_rm1:
    lda #$000F
.fr_rmd:
    sta $1A             ; right_mask

    ; Same-byte check: left_col == right_col
    lda $0E
    cmp $10
    bne .fr_notsame
    lda $16
    ora $1A             ; combine both masks
    sta $16             ; store combined in left_mask
    lda #1
    sta $22             ; same_byte = 1
    bra .fr_masks_done
.fr_notsame:
    stz $22
.fr_masks_done:

    ; left_fill = fill_byte AND NOT left_mask
    lda $16
    eor #$00FF
    and $0C
    sta $14

    ; right_fill = fill_byte AND NOT right_mask
    lda $1A
    eor #$00FF
    and $0C
    sta $18

    ; mid_count = right_col - left_col - 1
    lda $10
    sec
    sbc $0E
    dec a
    bpl .fr_midok
    lda #0
.fr_midok:
    sta $12

; ---- Row loop ----
.fr_rowloop:
    ; row_base = cur_y * 160 (y<<5 + y<<7)
    lda $24
    asl
    asl
    asl
    asl
    asl                 ; y*32
    sta $1C
    asl
    asl                 ; y*128
    clc
    adc $1C
    sta $1C             ; row_base

    ; Bank: 2 if y<410, else 3
    lda $24
    cmp #410
    lda #$02
    bcc .fr_bok
    lda #$03
.fr_bok:
    sta $1E

    ; Set pointer: [row_base + left_col, bank]
    lda $1C
    clc
    adc $0E
    sta $02
    lda $1E
    sta $04

    ; ---- Same-byte case ----
    lda $22
    beq .fr_left
    ldy #0
    longa=off
    sep #$20
    lda [$02],y
    and $16
    ora $14
    sta [$02],y
    rep #$20
    longa=on
    bra .fr_next

    ; ---- Left edge ----
.fr_left:
    lda $16
    beq .fr_lfull
    ; Partial left byte
    ldy #0
    longa=off
    sep #$20
    lda [$02],y
    and $16
    ora $14
    sta [$02],y
    rep #$20
    longa=on
    inc $02
    bne .fr_nw1
    inc $04
.fr_nw1:
    bra .fr_mid
.fr_lfull:
    ; Full left byte
    ldy #0
    longa=off
    sep #$20
    lda $0C
    sta [$02],y
    rep #$20
    longa=on
    inc $02
    bne .fr_nw2
    inc $04
.fr_nw2:

    ; ---- Middle bytes ----
.fr_mid:
    lda $12
    beq .fr_right
    tax
    ldy #0
    longa=off
    sep #$20
.fr_mloop:
    lda $0C
    sta [$02],y
    rep #$20
    longa=on
    inc $02
    bne .fr_nw3
    inc $04
.fr_nw3:
    dex
    beq .fr_right
    longa=off
    sep #$20
    bra .fr_mloop

    ; ---- Right edge ----
.fr_right:
    lda $1A
    beq .fr_rfull
    ; Partial right byte
    ldy #0
    longa=off
    sep #$20
    lda [$02],y
    and $1A
    ora $18
    sta [$02],y
    rep #$20
    longa=on
    bra .fr_next
.fr_rfull:
    ; Full right byte
    ldy #0
    longa=off
    sep #$20
    lda $0C
    sta [$02],y
    rep #$20
    longa=on

    ; ---- Next row ----
.fr_next:
    lda $24
    inc a
    sta $24
    lda $20
    dec a
    sta $20
    beq .fr_done
    brl .fr_rowloop
.fr_done:
    rtl

InitGraphics*:
    ; Out.String(msg): R[0]=addr, R[1]=bank, R[2]=length
    per msg             ; push 16-bit address of msg (PC-relative)
    pla
    sta $02             ; R[0] = address
    longa=off
    sep #$20
    phk                 ; push program bank (1 byte)
    pla
    rep #$20
    longa=on
    and #$00FF          ; zero-extend bank to 16-bit
    sta $04             ; R[1] = bank
    lda #21             ; length incl. null terminator
    sta $06             ; R[2] = length
    jsl Out.String
    jsl Out.Ln
    rtl

msg:
    text "Graphics Initialised"
    byte 0

_init:
    rtl
