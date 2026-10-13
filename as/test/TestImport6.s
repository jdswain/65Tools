; TestImport6.s - import a module with a version 6 symbol file
    cpu="816"
    longa=on
    longi=on
    import Out6

_init:
    ; Out6.Int(42, 0)
    lda #42
    sta $00          ; R[0] = 42
    lda #0
    sta $02          ; R[1] = 0 (width)
    jsl Out6.Int
    ; Out6.Ln
    jsl Out6.Ln
    rtl
