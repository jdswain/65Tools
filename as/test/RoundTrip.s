; RoundTrip.s - a module for the Oberon compiler to import.
; run_tests.sh assembles it, compiles RoundTripTest.Mod against the
; symbol file with oc816, and runs both under em16.
; Parameters are in R[0] ($02) and R[1] ($04), the result in R[0].
    cpu="816"
    longa=on
    longi=on
    .proc Twice(INTEGER): INTEGER
    .proc AddTwo(INTEGER, INTEGER): INTEGER

Twice*:
    lda $02
    asl
    sta $02
    rtl

AddTwo*:
    lda $02
    clc
    adc $04
    sta $02
    rtl

_init:
    rtl
