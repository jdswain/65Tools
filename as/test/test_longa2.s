; test_longa2.s
    cpu="816"
    longa=on
    longi=on

Test*:
    lda #$1234
    sep #$20
    lda #$02
    rep #$20
    rtl

_init:
    rtl
