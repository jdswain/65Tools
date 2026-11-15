; Reloc832.s - relocated addresses in 32-bit immediates: a variable's
; with two bytes of 0 (bank 0), a procedure's in three bytes and a 0
    cpu="65C832"
    longa=32
    longi=32
    section "bss"
count: data.w 0
    section "text"
Get*:
    ldx #count
    lda #Get
    ldy.w #count
    lda.a #Get
    mul count
    rtl
