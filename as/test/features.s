	cpu = "65C02"
	org = $1000
	include "simple_include.s"
count	= 3
	let K = 10
	var v = K * 2 + -1
	v += 5
twice	macro val, dst {
	lda #val * 2
	sta dst
.skip:	nop
}
start*:	twice 4, $20
	twice child, $1234
	if count == 3 {
	lda #1
	} else if count == 4 {
	lda #2
	} else {
	lda #3
	}
	if DEBUG { brk } else { nop }
.loop:	dex
	bne .loop
	bra fwd
	text.l "hi\n", 65
	text.7 "AB"
	text.0 "z"
	word fwd, $1234
	long $12345678
	float 1.5, -2.0
	fill 3, $aa, $55
	fill 2
	align 8
	data.w ~0 & $ff00, 1 << 4, 7 / 2, -7 / 2, 7 mod 4, <$1234, >$1234, ^$123456
	byte v, K >= 10, K != 10, !0, 1 && 0, 1 || 0
	{
priv:	nop
	jmp priv
	}
	message "v=", v, " file ", __FILE__, " line ", __LINE__, " cpu ", cpu
	errorif v != 24, "v is wrong: ", v
fwd:	rts
	end
	garbage here
