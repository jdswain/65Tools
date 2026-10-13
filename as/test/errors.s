aa:	lda #1
	jmp nowhere
aa: nop
	bne far
	fill 200
far:
	lda #"AB"
 let c = 1
 c = 2
	stz $10
	lda #1/0
	on = 3
