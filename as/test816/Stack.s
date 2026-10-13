; Stack.s - move the stack out of the way before the other modules run.
;
; em16 starts a module with the stack at $0845, and its floppy controller
; sits at $0800-$080F, so the stack is good for about 50 bytes. This
; module is loaded first: its body moves the stack to the top of bank 0,
; taking along the address it returns to.
    cpu = "65C816"
    longa = on
    longi = on

_init:
    pla                 ; return address
    sta $46
    sep #$20
    longa = off
    pla                 ; and its bank
    sta $48
    rep #$20
    longa = on
    lda #$FFFF
    tcs
    sep #$20
    longa = off
    lda $48
    pha
    rep #$20
    longa = on
    lda $46
    pha
    rtl
