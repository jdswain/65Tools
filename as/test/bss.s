	section "text"

	lda #$00
	sta $10
	rts
	
	section "bss"

	cld
	cli
	lda #$00
	sta $10
	rts
	
	fill $ff,00
	
