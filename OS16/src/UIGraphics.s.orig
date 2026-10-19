; UIGraphics.s
    cpu="816"
    longa=on
    longi=on
    import Out

    .proc InitGraphics()
	.proc SetPixel(INTEGER, INTEGER, BYTE)
	.proc GetPixel(INTEGER, INTEGER): BYTE

	.proc FillRect(INTEGER, INTEGER, INTEGER, INTEGER, INTEGER)
	.proc DrawLine(INTEGER, INTEGER, INTEGER, INTEGER, BYTE, BYTE)
	.proc DrawGlyph(INTEGER, INTEGER, INTEGER, INTEGER, INTEGER, INTEGER): INTEGER

; SetPixel(x, y, c) - R[0]=x, R[1]=y, R[2]=c
; Video: bank 2, 320 bytes/row, 2 pixels/byte (4-bit color)
; addr = y * 320 + x DIV 2
SetPixel*:
    ; Save params to temp DP regs
    lda $02             ; x
    sta $08             ; R[3] = x
    lda $04             ; y
    sta $0A             ; R[4] = y
    lda $06             ; c
    and #$000F          ; c MOD 16
    sta $0C             ; R[5] = c (masked)

    ; Compute addr = y * 320 + x DIV 2
    ; y * 320 = y * 5 * 64
    lda $0A             ; y
    asl                 ; y*2
    asl                 ; y*4
    clc
    adc $0A             ; y*5
    asl                 ; y*10
    asl                 ; y*20
    asl                 ; y*40
    asl                 ; y*80
    asl                 ; y*160
    asl                 ; y*320, carry = overflow into bank
    sta $02             ; row_base low 16 bits
    lda #$02
    adc #$00            ; bank = 2 + carry
    sta $0E             ; temp bank

    ; x DIV 2
    lda $08             ; x
    lsr                 ; x / 2
    clc
    adc $02             ; addr = row_base + x/2
    bcc .sp_noc
    inc $0E             ; carry into bank
.sp_noc:
    sta $02             ; addr low
    lda $0E
    sta $04             ; bank

    ; Read byte at [bank:addr]
    ldy #0
    longa=off
    sep #$20            ; 8-bit to read one byte
    lda [$02],y         ; read pixel byte
    rep #$20
    longa=on
    and #$00FF          ; zero-extend
    sta $0E             ; val (current byte)

    ; Compute pos = x MOD 2
    lda $08             ; x
    and #$0001          ; pos = x MOD 2
    bne .sp_pos1

    ; pos 0 (even x): high nibble, clear mask=$0F
    lda $0E
    and #$000F          ; keep low nibble
    sta $0E
    lda $0C             ; c
    asl
    asl
    asl
    asl                 ; c << 4
    ora $0E
    sta $0E
    bra .sp_write

.sp_pos1:
    ; pos 1 (odd x): low nibble, clear mask=$F0
    lda $0E
    and #$00F0          ; keep high nibble
    ora $0C             ; | c
    sta $0E

.sp_write:
    ; Write byte back at [bank:addr]
    lda $0E
    ldy #0
    longa=off
    sep #$20            ; 8-bit store
    sta [$02],y
    rep #$20
    longa=on
    rtl

; GetPixel(x, y): BYTE - R[0]=x, R[1]=y, result in R[0]
; Returns the 4-bit color value at pixel (x, y)
GetPixel*:
    ; Save x
    lda $02
    sta $08             ; R[3] = x

    ; Compute addr = y * 320 + x DIV 2
    ; y * 320 = y * 5 * 64
    lda $04             ; y
    asl                 ; y*2
    asl                 ; y*4
    clc
    adc $04             ; y*5
    asl                 ; y*10
    asl                 ; y*20
    asl                 ; y*40
    asl                 ; y*80
    asl                 ; y*160
    asl                 ; y*320, carry = overflow
    sta $02             ; row_base
    lda #$02
    adc #$00            ; bank = 2 + carry
    sta $0E             ; temp bank

    ; x DIV 2
    lda $08             ; x
    lsr                 ; x / 2
    clc
    adc $02             ; addr = row_base + x/2
    bcc .gp_noc
    inc $0E
.gp_noc:
    sta $02             ; addr
    lda $0E
    sta $04             ; bank

    ; Read byte
    ldy #0
    longa=off
    sep #$20            ; 8-bit
    lda [$02],y
    rep #$20
    longa=on
    and #$00FF
    sta $02             ; val

    ; Extract pixel at pos = x MOD 2
    lda $08             ; x
    and #$0001
    bne .gp_pos1

    ; pos 0 (even): high nibble >> 4
    lda $02
    lsr
    lsr
    lsr
    lsr                 ; val >> 4
    sta $02
    bra .gp_done

.gp_pos1:
    ; pos 1 (odd): low nibble
    lda $02
    and #$000F
    sta $02

.gp_done:
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
    and #$000F
    sta $24             ; color (4-bit)

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
    brl .dl_bres        ; Bresenham line

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

; ---- Bresenham line (no anti-aliasing) ----
.dl_bres:
    ; Compute sx = sign(end_x - cx)
    lda $16
    cmp $12
    bcc .bres_sxn
    beq .bres_sxn
    lda #1
    sta $1E             ; sx = +1
    bra .bres_sy
.bres_sxn:
    lda #$FFFF
    sta $1E             ; sx = -1

.bres_sy:
    ; Compute sy = sign(end_y - cy)
    lda $18
    cmp $14
    bcc .bres_syn
    beq .bres_syn
    lda #1
    sta $20             ; sy = +1
    bra .bres_major
.bres_syn:
    lda #$FFFF
    sta $20             ; sy = -1

.bres_major:
    ; Determine major axis: x-major if dx >= dy, else y-major
    lda $1A             ; dx
    cmp $1C             ; dy
    bcs .bres_xmajor
    brl .bres_ymajor

.bres_xmajor:
    ; major_steps = dx
    lda $1A
    sta $34

    ; Compute gradient = (dy * 256) / dx  (8-bit fixed-point)
    stz $22             ; gradient = 0
    lda $1C             ; remainder = dy
    sta $3C
    ldx #$0080          ; bit mask starting at bit 7

.bres_xdiv:
    asl $3C             ; rem *= 2
    lda $3C
    cmp $1A             ; rem >= dx?
    bcc .bres_xdnext
    sbc $1A             ; rem -= dx
    sta $3C
    txa
    ora $22
    sta $22             ; gradient |= bit
.bres_xdnext:
    txa
    lsr                 ; shift bit mask right
    tax
    bne .bres_xdiv

    ; minor_int = cy, minor_frac = 0
    lda $14
    sta $36
    stz $38

    ; Draw first endpoint
    lda $12
    sta $02             ; x = cx
    lda $36
    sta $04             ; y = minor_int
    lda $24
    sta $06             ; color
    jsl SetPixel

    lda $34
    beq .bres_xdone
    sta $34

.bres_xloop:
    ; Step major axis: cx += sx
    lda $12
    clc
    adc $1E
    sta $12

    ; Step minor axis fractionally
    lda $38
    clc
    adc $22             ; + gradient
    cmp #256
    bcc .bres_xnowrap
    sec
    sbc #256
    sta $38
    lda $36
    clc
    adc $20             ; += sy
    sta $36
    bra .bres_xdraw
.bres_xnowrap:
    sta $38

.bres_xdraw:
    lda $24
    sta $06             ; color
    lda $12
    sta $02             ; x = cx
    lda $36
    sta $04             ; y = minor_int
    jsl SetPixel

    lda $34
    dec a
    sta $34
    bne .bres_xloop

.bres_xdone:
    brl .dl_wnext

    ; ---- Y-MAJOR Bresenham ----
.bres_ymajor:
    ; major_steps = dy
    lda $1C
    sta $34

    ; Compute gradient = (dx * 256) / dy
    stz $22
    lda $1A             ; remainder = dx
    sta $3C
    ldx #$0080

.bres_ydiv:
    asl $3C
    lda $3C
    cmp $1C             ; rem >= dy?
    bcc .bres_ydnext
    sbc $1C
    sta $3C
    txa
    ora $22
    sta $22
.bres_ydnext:
    txa
    lsr
    tax
    bne .bres_ydiv

    ; minor_int = cx, minor_frac = 0
    lda $12
    sta $36
    stz $38

    ; Draw first endpoint
    lda $36
    sta $02             ; x = minor_int (cx)
    lda $14
    sta $04             ; y = cy
    lda $24
    sta $06             ; color
    jsl SetPixel

    lda $34
    beq .bres_ydone
    sta $34

.bres_yloop:
    ; Step major axis: cy += sy
    lda $14
    clc
    adc $20
    sta $14

    ; Step minor axis fractionally
    lda $38
    clc
    adc $22
    cmp #256
    bcc .bres_ynowrap
    sec
    sbc #256
    sta $38
    lda $36
    clc
    adc $1E             ; minor_int += sx
    sta $36
    bra .bres_ydraw
.bres_ynowrap:
    sta $38

.bres_ydraw:
    lda $24
    sta $06             ; color
    lda $36
    sta $02             ; x = minor_int
    lda $14
    sta $04             ; y = cy
    jsl SetPixel

    lda $34
    dec a
    sta $34
    bne .bres_yloop

.bres_ydone:
    brl .dl_wnext

; ---- Width loop continuation ----
.dl_wnext:
    lda $32
    inc a
    sta $32
    brl .dl_wloop

; ============================================================
; FillRect(x, y, w, h, color) — fill a w*h rectangle at (x,y)
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

    ; Build fill_byte: c | (c<<4)
    lda $0A
    and #$000F
    sta $0C
    asl
    asl
    asl
    asl
    ora $0C
    sta $0C             ; fill_byte

    ; left_col = x DIV 2
    lda $26
    lsr
    sta $0E

    ; right_col = (x + w - 1) DIV 2
    lda $26
    clc
    adc $28
    dec a
    sta $02             ; temp = x+w-1
    lsr
    sta $10

    ; Left mask: bits to KEEP for left_pos = x MOD 2
    ; pos 0: $00, pos 1: $F0
    lda $26
    and #$0001
    beq .fr_lm0
    lda #$00F0
    bra .fr_lmd
.fr_lm0:
    lda #$0000
.fr_lmd:
    sta $16             ; left_mask

    ; Right mask: bits to KEEP for right_pos = (x+w-1) MOD 2
    ; pos 0: $0F, pos 1: $00
    lda $02
    and #$0001
    bne .fr_rm1
    lda #$000F
    bra .fr_rmd
.fr_rm1:
    lda #$0000
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
    ; row_base = cur_y * 320 = cur_y * 5 * 64
    lda $24             ; cur_y
    asl                 ; y*2
    asl                 ; y*4
    clc
    adc $24             ; y*5
    asl                 ; y*10
    asl                 ; y*20
    asl                 ; y*40
    asl                 ; y*80
    asl                 ; y*160
    asl                 ; y*320, carry = overflow
    sta $1C             ; row_base
    lda #$02
    adc #$00            ; bank = 2 + carry
    sta $1E

    ; Set pointer: [row_base + left_col, bank]
    lda $1C
    clc
    adc $0E
    bcc .fr_bok
    inc $1E
.fr_bok:
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

; ============================================================
; DrawGlyph(fontAddr, fontBank, ch, x, y, color): INTEGER
; R[0]=$02=fontAddr, R[1]=$04=fontBank, R[2]=$06=ch,
; R[3]=$08=x, R[4]=$0A=y (baseline), R[5]=$0C=color
; Returns advance width (dx) in R[0]=$02
;
; Font layout:
;   T[0..255] = ARRAY OF INTEGER at fontAddr (512 bytes)
;   raster at fontAddr+512: per-glyph [dx,xoff,yoff,w,h] + bitmap
;
; DP workspace ($20-$40):
;   $20-$22  font_ptr (3-byte: addr_lo, addr_hi, bank)
;   $24      ch
;   $26      draw_x
;   $28      draw_y (baseline)
;   $2A      color
;   $2C      T[ch] raster offset
;   $2E-$30  raster_ptr (3-byte)
;   $32      dx (advance width)
;   $34      xoff (sign-extended)
;   $36      yoff (sign-extended)
;   $38      glyph_w
;   $3A      glyph_h
;   $3C      bytes_per_row
;   $3E      base_screen_y
;   $40      cur_row
; Per-pixel temps:
;   $02-$04  video ptr (3-byte)
;   $06      cur_screen_y
;   $08      bitmap_byte
;   $0A      bit_x
;   $0C      cur_screen_x
;   $0E      video_addr / row_base
;   $10      row_base (persistent within row)
;   $12      pixel temp / pos / bank
;   $14      bit_mask (persistent within byte)
;   $16      byte_counter
;   $18      raster_y_offset
; ============================================================
DrawGlyph*:
    ; 1. Save params to safe DP area
    lda $02
    sta $20             ; font_ptr low (fontAddr)
    lda $04
    sta $22             ; font_ptr bank (fontBank)
    lda $06
    sta $24             ; ch
    lda $08
    sta $26             ; draw_x
    lda $0A
    sta $28             ; draw_y (baseline)
    lda $0C
    and #$000F
    sta $2A             ; color (4-bit)

    ; 2. Read T[ch]: Y = ch * 2, LDA [$20],Y
    lda $24             ; ch
    asl                 ; ch * 2 (word index)
    tay
    lda [$20],y         ; T[ch] - read 16-bit from font_ptr + ch*2
    sta $2C             ; T[ch] = raster offset

    ; 3. If T[ch] == 0: null glyph, return dx=0
    bne .dg_valid
    stz $02             ; return 0
    rtl

.dg_valid:
    ; 4. Compute raster_ptr = fontAddr + 512 + T[ch]
    lda $20             ; fontAddr
    clc
    adc #512            ; + 512 (past T table)
    clc
    adc $2C             ; + T[ch]
    sta $2E             ; raster_ptr low
    lda $22             ; fontBank
    sta $30             ; raster_ptr bank

    ; 5. Read 5 metric bytes via [$2E],Y (8-bit)
    ldy #0
    longa=off
    sep #$20            ; 8-bit accumulator

    lda [$2E],y         ; byte 0: dx
    rep #$20
    longa=on
    and #$00FF
    sta $32             ; dx

    longa=off
    sep #$20
    iny
    lda [$2E],y         ; byte 1: xoff (signed)
    rep #$20
    longa=on
    and #$00FF
    cmp #$0080          ; sign-extend if >= 128
    bcc .dg_xpos
    ora #$FF00
.dg_xpos:
    sta $34             ; xoff (sign-extended)

    longa=off
    sep #$20
    iny
    lda [$2E],y         ; byte 2: yoff (signed)
    rep #$20
    longa=on
    and #$00FF
    cmp #$0080
    bcc .dg_ypos
    ora #$FF00
.dg_ypos:
    sta $36             ; yoff (sign-extended)

    longa=off
    sep #$20
    iny
    lda [$2E],y         ; byte 3: w
    rep #$20
    longa=on
    and #$00FF
    sta $38             ; glyph_w

    longa=off
    sep #$20
    iny
    lda [$2E],y         ; byte 4: h
    rep #$20
    longa=on
    and #$00FF
    sta $3A             ; glyph_h

    ; 6. bytes_per_row = (w + 7) >> 3
    lda $38             ; w
    clc
    adc #7
    lsr
    lsr
    lsr                 ; / 8
    sta $3C             ; bytes_per_row

    ; 7. Advance raster_ptr += 5 (past metrics)
    lda $2E
    clc
    adc #5
    sta $2E             ; raster_ptr now points to bitmap data

    ; 8. base_screen_y = y + yoff
    ;    (bottom of glyph; font data is stored bottom-to-top)
    lda $28             ; y (baseline)
    clc
    adc $36             ; + yoff (signed: 0=at baseline, neg=below)
    sta $3E             ; base_screen_y

    ; 9. If glyph_h == 0: return dx
    lda $3A
    bne .dg_start
    brl .dg_done        ; long branch to exit
.dg_start:

    ; 10. cur_row = 0
    stz $40

; ---- Row loop ----
.dg_rowloop:
    ; screen_y = base_screen_y + cur_row
    lda $3E
    clc
    adc $40
    sta $06             ; cur_screen_y

    ; Skip if screen_y < 0 or >= 400
    bpl .dg_ynotminus
    brl .dg_nextrow     ; negative -> skip row
.dg_ynotminus:
    cmp #400
    bcc .dg_yinrange
    brl .dg_nextrow     ; >= 400 -> skip row
.dg_yinrange:

    ; row_base = screen_y * 320 = screen_y * 5 * 64
    lda $06
    asl                 ; *2
    asl                 ; *4
    clc
    adc $06             ; *5
    asl                 ; *10
    asl                 ; *20
    asl                 ; *40
    asl                 ; *80
    asl                 ; *160
    asl                 ; *320, carry = overflow
    sta $10             ; row_base
    lda #$02
    adc #$00
    sta $12             ; bank for this row

    ; Compute raster byte offset for this row = cur_row * bytes_per_row
    lda $40             ; cur_row
    ldx $3C             ; bytes_per_row
    cpx #1
    beq .dg_bpr_done
    cpx #2
    beq .dg_bpr2
    ; General: repeated addition
    sta $0E             ; temp = cur_row
    lda #0
.dg_bpr_mul:
    clc
    adc $0E
    dex
    bne .dg_bpr_mul
    bra .dg_bpr_done
.dg_bpr2:
    asl                 ; cur_row * 2
.dg_bpr_done:
    sta $18             ; raster_y_offset

    ; bit_x = 0
    stz $0A
    ; byte_counter = bytes_per_row
    lda $3C
    sta $16

; ---- Byte loop ----
.dg_byteloop:
    ; Read bitmap byte at raster_ptr + raster_y_offset
    ldy $18             ; Y = raster offset (16-bit index ok)
    longa=off
    sep #$20
    lda [$2E],y         ; read bitmap byte
    rep #$20
    longa=on
    and #$00FF
    sta $08             ; bitmap_byte

    ; Advance raster_y_offset for next byte
    inc $18

    ; If byte == 0: skip 8 bits
    lda $08
    bne .dg_hasbits
    brl .dg_skipbyte
.dg_hasbits:

    ; Bit loop: process 8 bits MSB-first
    lda #$0080
    sta $14             ; bit_mask = $80

.dg_bitloop:
    ; Check if bit_x >= glyph_w: done with bits
    lda $0A             ; bit_x
    cmp $38             ; glyph_w
    bcc .dg_bitinrange
    brl .dg_bytenext
.dg_bitinrange:

    ; Test if bit is set
    lda $08             ; bitmap_byte
    and $14             ; & bit_mask
    bne .dg_bitset
    brl .dg_nextbit     ; bit not set
.dg_bitset:

    ; Compute screen_x = draw_x + xoff + bit_x
    lda $26             ; draw_x
    clc
    adc $34             ; + xoff
    clc
    adc $0A             ; + bit_x
    sta $0C             ; cur_screen_x

    ; Bounds check: 0 <= screen_x < 640
    bpl .dg_xnotminus
    brl .dg_nextbit     ; negative
.dg_xnotminus:
    cmp #640
    bcc .dg_xinrange
    brl .dg_nextbit     ; >= 640
.dg_xinrange:

    ; ---- Inline pixel write at ($0C, $06) ----
    ; video_addr = row_base + screen_x / 2
    lda $0C             ; screen_x
    lsr                 ; / 2
    clc
    adc $10             ; + row_base
    sta $02             ; video ptr addr
    lda $12             ; bank (from row calc)
    bcc .dg_bok
    inc a               ; carry from column add
.dg_bok:
    sta $04             ; video ptr bank

    ; Read current video byte
    ldy #0
    longa=off
    sep #$20
    lda [$02],y         ; read pixel byte
    rep #$20
    longa=on
    and #$00FF
    sta $0E             ; save current byte

    ; pixel pos = screen_x MOD 2
    lda $0C
    and #$0001
    bne .dg_pp1

    ; pos 0 (even x): high nibble
    lda $0E
    and #$000F          ; keep low nibble
    sta $0E
    lda $2A             ; color
    asl
    asl
    asl
    asl                 ; << 4
    ora $0E
    bra .dg_pwrite

.dg_pp1:
    ; pos 1 (odd x): low nibble
    lda $0E
    and #$00F0          ; keep high nibble
    ora $2A             ; | color

.dg_pwrite:
    ldy #0
    longa=off
    sep #$20
    sta [$02],y         ; write pixel byte
    rep #$20
    longa=on
    ; ---- End pixel write ----

.dg_nextbit:
    ; Advance bit_x, shift bit_mask
    inc $0A             ; bit_x++
    lsr $14             ; bit_mask >>= 1
    lda $14
    beq .dg_bytenext    ; byte exhausted (mask went to 0)
    brl .dg_bitloop     ; more bits in this byte

.dg_skipbyte:
    ; Skip 8 bits
    lda $0A
    clc
    adc #8
    sta $0A

.dg_bytenext:
    ; Next byte
    dec $16             ; byte_counter--
    beq .dg_nextrow     ; no more bytes
    brl .dg_byteloop    ; next byte

.dg_nextrow:
    lda $40
    inc a
    sta $40
    cmp $3A             ; glyph_h
    bcs .dg_done        ; cur_row >= glyph_h
    brl .dg_rowloop

.dg_done:
    ; Return dx in R[0]
    lda $32
    sta $02
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
    lda #23             ; length incl. null terminator
    sta $06             ; R[2] = length
    jsl Out.String
    jsl Out.Ln
    rtl

msg:
    text "UIGraphics Initialised"
    byte 0

_init:
    rtl
