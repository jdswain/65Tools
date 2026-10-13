; TestReloc.s - Test JSL relocation within a single module
    cpu="816"
    longa=on
    longi=on

Helper*:
    lda #42
    sta $00
    rtl

Test*:
    jsl Helper
    rtl

_init:
    jsl Test
    rtl
