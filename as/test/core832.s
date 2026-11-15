; core832.s - the instructions the assembler has for the 65C832 and the
; 65C816X, run on the core they are for (Verilog65C816: tb_cpu.v, and
; em16 -bench): MUL, UML, DIV and UDV in each of their fifteen addressing
; modes, ASL/LSR/ASR/ROL/ROR #n and BSW, at 16 and 8 bits and, with
; -DC832=1 on the 65C832, at 32 after XFE. Each operand is put where its
; mode should read it and cleared after, so that an opcode of another mode
; reads 0. The result goes to $00F000, as tb_cpu.v has it: 0 if all
; passed, else the number of the test that failed. Assembled to a .mem
; file from $0000, the image of the core's RAM.
;
; (The checks are a subroutine because a macro called from a macro gets
; the same labels at each expansion of the outer one.)

	if C832 {
	cpu = "65C832"
	} else {
	cpu = "65C816X"
	}

testno = $40			; the test running
wantA = $44			; the A and X it expects
wantX = $48

	org = 0
	data.b 0
	org = $20
	data.w $2010		; $20: (dp) and (dp),Y
	data.w 0
	data.b $10, $20, $01	; $24: [dp], at $012010
	data.b 0
	data.b $20, $20, $01	; $28: [dp],Y, at $012020 + Y
	org = $34
	data.w $2030		; $34: (dp,X) with X = 4

; test n begins
num	macro n {
	lda #n
	sta testno
}

; the A and X the tests that follow expect
want	macro ea, ex {
	lda #ea
	sta wantA
	ldx #ex
	stx wantX
}

; the operand v at the long address p, and 0 there
put	macro p, v {
	lda #v
	sta.l p
}
clear	macro p {
	lda #0
	sta.l p
}

; v on the stack, as wide as A (2 bytes at 8 bits)
push	macro v {
	if longa == 32 {
	pea v >> 16
	}
	pea v & $FFFF
}

; what push pushed, into Y, and Y back to 6
pull	macro {
	ply
	if longi == 0 {
	ply
	}
	ldy #6
}

; The fifteen modes of each: A = a0 and the operand v give A = ea and
; X = ex. X is 4 for the indexed modes, Y 6 throughout.
tmul	macro n, a0, v, ea, ex {
	want ea, ex
	num n
	lda #a0
	mul #v
	jsr check
	num n+1
	put $2000, v
	lda #a0
	mul $2000
	jsr check
	clear $2000
	num n+2
	put $012000, v
	lda #a0
	mul.l $012000
	jsr check
	clear $012000
	num n+3
	put $10, v
	lda #a0
	mul $10
	jsr check
	clear $10
	num n+4
	put $2010, v
	lda #a0
	mul ($20)
	jsr check
	clear $2010
	num n+5
	put $012010, v
	lda #a0
	mul [$24]
	jsr check
	clear $012010
	num n+6
	put $2004, v
	ldx #4
	lda #a0
	mul $2000,x
	jsr check
	clear $2004
	num n+7
	put $012004, v
	ldx #4
	lda #a0
	mul $012000,x
	jsr check
	clear $012004
	num n+8
	put $2006, v
	lda #a0
	mul $2000,y
	jsr check
	clear $2006
	num n+9
	put $14, v
	ldx #4
	lda #a0
	mul $10,x
	jsr check
	clear $14
	num n+10
	put $2030, v
	ldx #4
	lda #a0
	mul ($30,x)
	jsr check
	clear $2030
	num n+11
	put $2016, v
	lda #a0
	mul ($20),y
	jsr check
	clear $2016
	num n+12
	put $012026, v
	lda #a0
	mul [$28],y
	jsr check
	clear $012026
	num n+13
	push v
	lda #a0
	mul 1,s
	jsr check
	pull
	num n+14
	push $2040
	put $2046, v
	lda #a0
	mul (1,s),y
	jsr check
	pull
	clear $2046
}

tuml	macro n, a0, v, ea, ex {
	want ea, ex
	num n
	lda #a0
	uml #v
	jsr check
	num n+1
	put $2000, v
	lda #a0
	uml $2000
	jsr check
	clear $2000
	num n+2
	put $012000, v
	lda #a0
	uml.l $012000
	jsr check
	clear $012000
	num n+3
	put $10, v
	lda #a0
	uml $10
	jsr check
	clear $10
	num n+4
	put $2010, v
	lda #a0
	uml ($20)
	jsr check
	clear $2010
	num n+5
	put $012010, v
	lda #a0
	uml [$24]
	jsr check
	clear $012010
	num n+6
	put $2004, v
	ldx #4
	lda #a0
	uml $2000,x
	jsr check
	clear $2004
	num n+7
	put $012004, v
	ldx #4
	lda #a0
	uml $012000,x
	jsr check
	clear $012004
	num n+8
	put $2006, v
	lda #a0
	uml $2000,y
	jsr check
	clear $2006
	num n+9
	put $14, v
	ldx #4
	lda #a0
	uml $10,x
	jsr check
	clear $14
	num n+10
	put $2030, v
	ldx #4
	lda #a0
	uml ($30,x)
	jsr check
	clear $2030
	num n+11
	put $2016, v
	lda #a0
	uml ($20),y
	jsr check
	clear $2016
	num n+12
	put $012026, v
	lda #a0
	uml [$28],y
	jsr check
	clear $012026
	num n+13
	push v
	lda #a0
	uml 1,s
	jsr check
	pull
	num n+14
	push $2040
	put $2046, v
	lda #a0
	uml (1,s),y
	jsr check
	pull
	clear $2046
}

tdiv	macro n, a0, v, ea, ex {
	want ea, ex
	num n
	lda #a0
	div #v
	jsr check
	num n+1
	put $2000, v
	lda #a0
	div $2000
	jsr check
	clear $2000
	num n+2
	put $012000, v
	lda #a0
	div.l $012000
	jsr check
	clear $012000
	num n+3
	put $10, v
	lda #a0
	div $10
	jsr check
	clear $10
	num n+4
	put $2010, v
	lda #a0
	div ($20)
	jsr check
	clear $2010
	num n+5
	put $012010, v
	lda #a0
	div [$24]
	jsr check
	clear $012010
	num n+6
	put $2004, v
	ldx #4
	lda #a0
	div $2000,x
	jsr check
	clear $2004
	num n+7
	put $012004, v
	ldx #4
	lda #a0
	div $012000,x
	jsr check
	clear $012004
	num n+8
	put $2006, v
	lda #a0
	div $2000,y
	jsr check
	clear $2006
	num n+9
	put $14, v
	ldx #4
	lda #a0
	div $10,x
	jsr check
	clear $14
	num n+10
	put $2030, v
	ldx #4
	lda #a0
	div ($30,x)
	jsr check
	clear $2030
	num n+11
	put $2016, v
	lda #a0
	div ($20),y
	jsr check
	clear $2016
	num n+12
	put $012026, v
	lda #a0
	div [$28],y
	jsr check
	clear $012026
	num n+13
	push v
	lda #a0
	div 1,s
	jsr check
	pull
	num n+14
	push $2040
	put $2046, v
	lda #a0
	div (1,s),y
	jsr check
	pull
	clear $2046
}

tudv	macro n, a0, v, ea, ex {
	want ea, ex
	num n
	lda #a0
	udv #v
	jsr check
	num n+1
	put $2000, v
	lda #a0
	udv $2000
	jsr check
	clear $2000
	num n+2
	put $012000, v
	lda #a0
	udv.l $012000
	jsr check
	clear $012000
	num n+3
	put $10, v
	lda #a0
	udv $10
	jsr check
	clear $10
	num n+4
	put $2010, v
	lda #a0
	udv ($20)
	jsr check
	clear $2010
	num n+5
	put $012010, v
	lda #a0
	udv [$24]
	jsr check
	clear $012010
	num n+6
	put $2004, v
	ldx #4
	lda #a0
	udv $2000,x
	jsr check
	clear $2004
	num n+7
	put $012004, v
	ldx #4
	lda #a0
	udv $012000,x
	jsr check
	clear $012004
	num n+8
	put $2006, v
	lda #a0
	udv $2000,y
	jsr check
	clear $2006
	num n+9
	put $14, v
	ldx #4
	lda #a0
	udv $10,x
	jsr check
	clear $14
	num n+10
	put $2030, v
	ldx #4
	lda #a0
	udv ($30,x)
	jsr check
	clear $2030
	num n+11
	put $2016, v
	lda #a0
	udv ($20),y
	jsr check
	clear $2016
	num n+12
	put $012026, v
	lda #a0
	udv [$28],y
	jsr check
	clear $012026
	num n+13
	push v
	lda #a0
	udv 1,s
	jsr check
	pull
	num n+14
	push $2040
	put $2046, v
	lda #a0
	udv (1,s),y
	jsr check
	pull
	clear $2046
}

; the shifts by k and BSW of a0, giving e1 to e6
tshift	macro n, a0, k, e1, e2, e3, e4, e5, e6 {
	num n
	want e1, 0
	lda #a0
	asl #k
	jsr checka
	num n+1
	want e2, 0
	lda #a0
	lsr #k
	jsr checka
	num n+2
	want e3, 0
	lda #a0
	asr #k
	jsr checka
	num n+3
	want e4, 0
	lda #a0
	rol #k
	jsr checka
	num n+4
	want e5, 0
	lda #a0
	ror #k
	jsr checka
	num n+5
	want e6, 0
	lda #a0
	bsw
	jsr checka
	num n+6
	lda #a0
	bsw a
	jsr checka
}

	org = $0200
start:	inc $3000		; tb_cpu.v wants to see MLB, on a read-modify-write
	dec $3000
	clc
	xce			; 65C816 native mode
	rep #$30
	longa = on
	longi = on
	ldy #6
	; -2 and 291
	tmul 1, $FFFE, $0123, $FDBA, $FFFF
	tuml 16, $FFFE, $0123, $FDBA, $0122
	tdiv 31, $FFFE, $0123, $FFFF, $0121
	tudv 46, $FFFE, $0123, $00E1, $003B
	tshift 61, $8421, 4, $4210, $0842, $F842, $4218, $1842, $2184

	sep #$30
	longa = off
	longi = off
	ldy #6
	; -2 and 19
	tmul 68, $FE, $13, $DA, $FF
	tuml 83, $FE, $13, $DA, $12
	tdiv 98, $FE, $13, $FF, $11
	tudv 113, $FE, $13, $0D, $07
	tshift 128, $81, 3, $08, $10, $F0, $0C, $30, $81

	if C832 {
	rep #$30
	sec
	clv
	xfe			; 65C832 native mode, A and X 32 bits
	longa = 32
	longi = 32
	num 135			; C the old E8 (0), V the old E16 (1)
	bcs .xfe
	bvs .xfe1
.xfe:	jmp fail
.xfe1:	ldy #6
	; -2 and 74565
	tmul 136, $FFFFFFFE, $00012345, $FFFDB976, $FFFFFFFF
	tuml 151, $FFFFFFFE, $00012345, $FFFDB976, $00012344
	tdiv 166, $FFFFFFFE, $00012345, $FFFFFFFF, $00012343
	tudv 181, $FFFFFFFE, $00012345, $0000E100, $00005AFE
	tshift 196, $84218421, 4, $42184210, $08421842, $F8421842, $42184218, $18421842, $21842184
	num 203			; back: C the old E8 (1), V the old E16 (0)
	clc
	sep #$40
	xfe
	longa = on
	longi = on
	bcc .back
	bvc .back1
.back:	jmp fail
.back1:	num 204
	want $3412, 0
	lda #$1234
	bsw
	jsr checka
	}

	sep #$20
	longa = off
	lda #0
	sta.l $00F000		; passed
.halt:	bra .halt

; A and X are what the test expects, or it fails
check:	cpx wantX
	bne fail
checka:	cmp wantA
	bne fail
	rts

fail:	sep #$20
	lda testno
	sta.l $00F000		; the number of the test
.halt:	bra .halt

	org = $FFFC
	data.w start
