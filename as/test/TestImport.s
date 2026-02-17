; TestImport.s - Test importing an Oberon module
    cpu="816"
    longa=on
    longi=on
    import Out

_init:
    ; Out.Int(42, 0)
    lda #42
    sta $00          ; R[0] = 42
    lda #0
    sta $02          ; R[1] = 0 (width)
    jsl Out.Int
    ; Out.Ln
    jsl Out.Ln
    rtl
