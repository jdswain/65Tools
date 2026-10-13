; sample.s - assembled both by the host assembler and by the one
; running under em16; the two outputs must agree.
        cpu = "65C816"
        longa = on
        longi = on
        org = $8000
count   = 3
twice   macro val, dst {
        lda #val * 2
        sta dst
}
start*: twice 4, $20
        twice count, $1234
        if count == 3 {
        ldx #>start
        } else {
        ldx #0
        }
.loop:  dex
        bne .loop
        jsl far
        bra done
        text.0 "Hi", 33
        word done, 1000 / 7, 1000 mod 7, 123 * 45
        long $12345678
        long 70000 * 300, -100000 / 7, 100000 mod 70001
        fill 6, 1, 2, 3
        align 4
done:   rts
far:    rtl
