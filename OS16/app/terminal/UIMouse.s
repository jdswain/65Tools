; UIMouse.s — Mouse cursor module
; Draws an 11×14 arrow cursor on the 640×400 4-bit framebuffer
; Background is saved/restored when cursor moves
    cpu="816"
    longa=on
    longi=on

    .proc Init(INTEGER, INTEGER)
    .proc Show()
    .proc Hide()
    .proc MoveTo(INTEGER, INTEGER)

; ============================================================
; Mutable state lives in bank 0 RAM ($0900-$0959)
; so writes are guaranteed to persist.
; Cursor shape data (read-only) stays inline in code section.
;
; Video layout: bank 2, 320 bytes/row, 2 pixels/byte (4-bit color)
; Pixel address = y * 320 + x DIV 2
; Even x: high nibble, odd x: low nibble
;
; Cursor: 11 wide × 14 tall, tip at (cur_x, cur_y)
; Body extends DOWN (decreasing y) and RIGHT (increasing x)
;
; DP usage:
;   $00       SB (NOT touched)
;   $02-$04   video pointer (3-byte: addr, bank)
;   $06-$08   save_buf pointer (3-byte: addr, bank=0)
;   $0A       color scratch
;   $0C       cur_x local copy
;   $0E       cur_y local copy
;   $10       mask_word
;   $12       image_word
;   $14       col counter
;   $16-$18   image_ptr (3-byte)
;   $1A-$1C   mask_ptr (3-byte)
;   $24       row counter
;   $26       screen_y
;   $28       video row_base low
;   $2A       video bank
;   $2C       byte_col
;   $30       new x (MoveTo safe storage)
;   $32       new y (MoveTo safe storage)
; ============================================================

; Bank 0 RAM addresses for mutable state
CUR_X    := $0900
CUR_Y    := $0902
VISIBLE  := $0904
SAVE_BUF := $0906
; SAVE_BUF is 84 bytes (14 rows × 6 bytes), ends at $0959
SAVE_X   := $095A
SAVE_Y   := $095C
; SAVE_X/SAVE_Y record where SaveBg captured from, so RestoreBg
; restores to exactly the right position

; ============================================================
; Init(x, y) — show cursor at initial position
; R[0]=$02=x, R[1]=$04=y
; ============================================================
Init*:
    lda $02
    sta CUR_X
    lda $04
    sta CUR_Y
    jsr ClampXY
    jsr SaveBg
    jsr DrawCursor
    lda #1
    sta VISIBLE
    rtl

; ============================================================
; Show() — show cursor if hidden
; ============================================================
Show*:
    lda VISIBLE
    bne .show_done
    jsr SaveBg
    jsr DrawCursor
    lda #1
    sta VISIBLE
.show_done:
    rtl

; ============================================================
; Hide() — hide cursor if visible
; ============================================================
Hide*:
    lda VISIBLE
    beq .hide_done
    jsr RestoreBg
    stz VISIBLE
.hide_done:
    rtl

; ============================================================
; MoveTo(x, y) — move cursor to new position
; R[0]=$02=x, R[1]=$04=y
; ============================================================
MoveTo*:
    lda $02
    sta $30                 ; new x (safe from all subroutines)
    lda $04
    sta $32                 ; new y (safe)

    lda VISIBLE
    beq .mt_hidden

    ; Visible: restore old bg, update pos, save new bg, draw
    jsr RestoreBg
    lda $30
    sta CUR_X
    lda $32
    sta CUR_Y
    jsr ClampXY
    jsr SaveBg
    jsr DrawCursor
    rtl

.mt_hidden:
    ; Hidden: just update position
    lda $30
    sta CUR_X
    lda $32
    sta CUR_Y
    jsr ClampXY
    rtl

; ============================================================
; ClampXY — clamp CUR_X to [0..629], CUR_Y to [13..399]
; ============================================================
ClampXY:
    lda CUR_X
    bpl .cx_notmin
    stz CUR_X
    bra .cx_ycheck
.cx_notmin:
    cmp #630
    bcc .cx_ycheck
    lda #629
    sta CUR_X
.cx_ycheck:
    lda CUR_Y
    cmp #14
    bcs .cy_notmin
    lda #13
    sta CUR_Y
    rts
.cy_notmin:
    cmp #400
    bcc .cy_done
    lda #399
    sta CUR_Y
.cy_done:
    rts

; ============================================================
; SaveBg — save 6 bytes × 14 rows from video to SAVE_BUF
;
; For each row r (0..13):
;   screen_y = cur_y - r
;   video_addr = screen_y * 320 + (cur_x DIV 2)
;   copy 6 bytes from video[addr] to SAVE_BUF[r*6]
; ============================================================
SaveBg:
    lda CUR_X
    sta $0C                 ; cur_x local
    sta SAVE_X              ; record where we saved from
    lda CUR_Y
    sta $0E                 ; cur_y local
    sta SAVE_Y              ; record where we saved from

    ; byte_col = cur_x DIV 2
    lda $0C
    lsr
    sta $2C                 ; byte_col

    ; Row counter
    stz $24                 ; row = 0

.sb_rowloop:
    ; screen_y = cur_y - row
    lda $0E                 ; cur_y
    sec
    sbc $24                 ; - row
    sta $26                 ; screen_y

    ; Skip if screen_y < 0 or >= 400
    bmi .sb_nextrow
    cmp #400
    bcs .sb_nextrow

    ; Compute video row_base = screen_y * 320
    lda $26
    asl                     ; y*2
    asl                     ; y*4
    clc
    adc $26                 ; y*5
    asl                     ; y*10
    asl                     ; y*20
    asl                     ; y*40
    asl                     ; y*80
    asl                     ; y*160
    asl                     ; y*320
    sta $28                 ; row_base low
    lda #$02
    adc #$00                ; bank = 2 + carry
    sta $2A                 ; bank

    ; video_addr = row_base + byte_col
    lda $28
    clc
    adc $2C
    sta $02                 ; video ptr addr
    lda $2A
    adc #0
    sta $04                 ; video ptr bank

    ; save_dest = SAVE_BUF + row * 6
    lda $24                 ; row
    asl                     ; row*2
    clc
    adc $24                 ; row*3
    asl                     ; row*6
    clc
    adc #SAVE_BUF           ; + base address
    sta $06                 ; dest addr (bank 0)
    stz $08                 ; bank = 0

    ; Copy 6 bytes from [$02] (video) to [$06] (save_buf)
    ldy #0
    longa=off
    sep #$20
.sb_copy:
    lda [$02],y
    sta [$06],y
    iny
    cpy #6
    bcc .sb_copy
    rep #$20
    longa=on

.sb_nextrow:
    lda $24
    inc a
    sta $24
    cmp #14
    bcc .sb_rowloop
    rts

; ============================================================
; RestoreBg — restore 6 bytes × 14 rows from SAVE_BUF to video
; ============================================================
RestoreBg:
    lda SAVE_X
    sta $0C                 ; restore to where we saved from
    lda SAVE_Y
    sta $0E

    ; byte_col = cur_x DIV 2
    lda $0C
    lsr
    sta $2C

    stz $24                 ; row = 0

.rb_rowloop:
    lda $0E
    sec
    sbc $24
    sta $26                 ; screen_y = cur_y - row

    bmi .rb_nextrow
    cmp #400
    bcs .rb_nextrow

    ; Compute video row_base
    lda $26
    asl
    asl
    clc
    adc $26
    asl
    asl
    asl
    asl
    asl
    asl
    sta $28
    lda #$02
    adc #$00
    sta $2A

    ; video_addr
    lda $28
    clc
    adc $2C
    sta $02
    lda $2A
    adc #0
    sta $04

    ; save_src = SAVE_BUF + row * 6
    lda $24
    asl
    clc
    adc $24
    asl
    clc
    adc #SAVE_BUF
    sta $06
    stz $08                 ; bank = 0

    ; Copy 6 bytes from [$06] (save_buf) to [$02] (video)
    ldy #0
    longa=off
    sep #$20
.rb_copy:
    lda [$06],y
    sta [$02],y
    iny
    cpy #6
    bcc .rb_copy
    rep #$20
    longa=on

.rb_nextrow:
    lda $24
    inc a
    sta $24
    cmp #14
    bcc .rb_rowloop
    rts

; ============================================================
; DrawCursor — draw the 11×14 arrow cursor at (cur_x, cur_y)
;
; For each row r (0..13):
;   screen_y = cur_y - r
;   For each col c (0..10):
;     screen_x = cur_x + c
;     if mask[r] bit (15-c) is set:
;       if image[r] bit (15-c) is set: plot black (0)
;       else: plot white (15)
; ============================================================
DrawCursor:
    lda CUR_X
    sta $0C                 ; cur_x
    lda CUR_Y
    sta $0E                 ; cur_y

    ; Get cursor_mask pointer (read-only data in code bank)
    per cursor_mask
    pla
    sta $1A                 ; mask_ptr addr
    longa=off
    sep #$20
    phk                     ; code bank
    pla
    rep #$20
    longa=on
    and #$00FF
    sta $1C                 ; mask_ptr bank

    ; Get cursor_image pointer
    per cursor_image
    pla
    sta $16                 ; image_ptr addr
    longa=off
    sep #$20
    phk
    pla
    rep #$20
    longa=on
    and #$00FF
    sta $18                 ; image_ptr bank

    stz $24                 ; row = 0

.dc_rowloop:
    ; screen_y = cur_y - row
    lda $0E
    sec
    sbc $24
    sta $26                 ; screen_y

    ; Bounds check (long branch for out-of-range)
    bpl .dc_ynotminus
    brl .dc_nextrow
.dc_ynotminus:
    cmp #400
    bcc .dc_yinrange
    brl .dc_nextrow
.dc_yinrange:

    ; Compute video row_base = screen_y * 320
    lda $26
    asl
    asl
    clc
    adc $26
    asl
    asl
    asl
    asl
    asl
    asl
    sta $28                 ; row_base
    lda #$02
    adc #$00
    sta $2A                 ; bank

    ; Load mask word for this row
    lda $24                 ; row
    asl                     ; row * 2
    tay
    lda [$1A],y             ; mask[row]
    sta $10                 ; mask_word

    ; Load image word for this row
    lda [$16],y             ; image[row]
    sta $12                 ; image_word

    ; Column loop: c = 0..10
    stz $14                 ; col = 0

.dc_colloop:
    ; screen_x = cur_x + col
    lda $0C                 ; cur_x
    clc
    adc $14                 ; + col
    sta $06                 ; screen_x

    ; Bounds check: 0 <= screen_x < 640
    bmi .dc_nextcol
    cmp #640
    bcs .dc_nextcol

    ; Test mask bit: bit (15 - col)
    ; bit_mask = $8000 >> col
    lda #$8000
    ldx $14                 ; col
    beq .dc_maskready
.dc_shift:
    lsr
    dex
    bne .dc_shift
.dc_maskready:
    sta $08                 ; bit_mask

    ; Test mask
    and $10                 ; mask_word & bit_mask
    beq .dc_nextcol         ; mask bit not set, skip

    ; Determine color: image bit set -> black (0), clear -> white (15)
    lda $08                 ; bit_mask
    and $12                 ; image_word & bit_mask
    bne .dc_black
    lda #15                 ; white
    bra .dc_plot
.dc_black:
    lda #0                  ; black

.dc_plot:
    sta $0A                 ; color

    ; Inline pixel write at (screen_x=$06, screen_y=$26)
    ; video_addr = row_base + screen_x / 2
    lda $06                 ; screen_x
    lsr                     ; / 2
    clc
    adc $28                 ; + row_base
    sta $02                 ; video ptr addr
    lda $2A                 ; bank
    adc #0                  ; + carry
    sta $04                 ; video ptr bank

    ; Read current byte
    ldy #0
    longa=off
    sep #$20
    lda [$02],y
    rep #$20
    longa=on
    and #$00FF
    sta $08                 ; current_byte

    ; pixel pos = screen_x MOD 2
    lda $06
    and #$0001
    bne .dc_odd

    ; Even x: high nibble
    lda $08
    and #$000F              ; keep low nibble
    sta $08
    lda $0A                 ; color
    asl
    asl
    asl
    asl                     ; << 4
    ora $08
    bra .dc_write

.dc_odd:
    ; Odd x: low nibble
    lda $08
    and #$00F0              ; keep high nibble
    ora $0A                 ; | color
    ; fall through

.dc_write:
    ldy #0
    longa=off
    sep #$20
    sta [$02],y
    rep #$20
    longa=on

.dc_nextcol:
    lda $14
    inc a
    sta $14
    cmp #11                 ; 11 columns
    bcc .dc_colloop

.dc_nextrow:
    lda $24
    inc a
    sta $24
    cmp #14                 ; 14 rows
    bcs .dc_done
    brl .dc_rowloop
.dc_done:
    rts

; ============================================================
; Module init
; ============================================================
_init:
    stz VISIBLE
    rtl

; ============================================================
; Read-only cursor shape data (inline in code section)
; Accessed via PER/PHK in DrawCursor only
; ============================================================

; Cursor mask: 14 words (bit=1 means draw pixel)
; Row 0 = tip of arrow (drawn at cur_y), row 13 = bottom (cur_y-13)
cursor_mask:
    word $8000              ; row 0:  B
    word $C000              ; row 1:  BB
    word $E000              ; row 2:  BWB
    word $F000              ; row 3:  BWWB
    word $F800              ; row 4:  BWWWB
    word $FC00              ; row 5:  BWWWWB
    word $FE00              ; row 6:  BWWWWWB
    word $FF00              ; row 7:  BWWWWWWB
    word $FF80              ; row 8:  BWWWWWWWB
    word $FFC0              ; row 9:  BWWWWWWWWB
    word $FFE0              ; row 10: BWWWWWWWWWB
    word $FFE0              ; row 11: BWWWWBBBBBB
    word $E000              ; row 12: BWB
    word $C000              ; row 13: BB

; Cursor image: 14 words (bit=1 means black, bit=0 means white)
; Only meaningful where mask bit is also set
cursor_image:
    word $8000              ; row 0:  B
    word $C000              ; row 1:  BB
    word $A000              ; row 2:  BWB
    word $9000              ; row 3:  BWWB
    word $8800              ; row 4:  BWWWB
    word $8400              ; row 5:  BWWWWB
    word $8200              ; row 6:  BWWWWWB
    word $8100              ; row 7:  BWWWWWWB
    word $8080              ; row 8:  BWWWWWWWB
    word $8040              ; row 9:  BWWWWWWWWB
    word $8020              ; row 10: BWWWWWWWWWB
    word $83E0              ; row 11: BWWWWBBBBBB
    word $A000              ; row 12: BWB
    word $C000              ; row 13: BB
