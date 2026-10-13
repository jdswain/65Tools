; MathLib.s - Assembly module with typed procedure exports
    cpu="816"
    longa=on
    longi=on
    .proc Twice(INTEGER): INTEGER
    .proc AddTwo(INTEGER, INTEGER): INTEGER

; Twice(x) = x * 2
; Param in R[0], result in R[0]
Twice*:
    lda $00
    asl
    sta $00
    rtl

; AddTwo(a, b) = a + b
; Params: a in R[0], b in R[2], result in R[0]
AddTwo*:
    lda $00
    clc
    adc $02
    sta $00
    rtl

_init:
    rtl
