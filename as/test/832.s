; 832.s - the 65C816X and the 65C832: the instructions after WDM, the
; widths of immediates, and where the new mnemonics are names
	cpu = "65C816"
	org = $1000
mul:	jsr udv			; names: the 65C816 has no such instructions
udv:	rts
	cpu = "65C816X"		; from here on they are mnemonics
	longa = on
	longi = on
	mul #$1234
	uml $12
	div $1234
	udv [$12],y
	mul $123456,x
	uml (1,s),y
	asl #3
	lsr #31
	asr #1
	rol #8
	ror #16
	bsw
	bsw a
	div #$10		; at the start of a statement an instruction,
.q:	div $10,x		; also after a label,
	lda #10 div 3		; but an operator in an expression
	wdm #$B1
	cpu = "65C832"
	xfe
	longa = 32
	longi = 32
	lda #$12345678
	ldx #-2
	cpy #$10000
	bit #$80000000
	mul #100000
	div.w #5		; .w: 16 bits
	lda.b #1		; .b: 8
	longa = off
	lda.l #$11223344	; .l: 32
	lda #longa		; off
	ldx #longi		; 32
	div #7
	longi = 8
	cpy #3
	lda #cpu == "65C832"
