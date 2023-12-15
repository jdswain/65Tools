	cpu = "6502"
	
	lcd_base = $0800
	lcd_inst = lcd_base + 0
	lcd_data = lcd_base + 1

		org = $0200

lcd_reset:	jsr wait_16	; Wait at least 15ms after power up

		lda $#3f	; Write function set
		sta lcd_inst
		jsr wait_4

		lda #$3f
		sta lcd_inst
		jsr wait_32

		lda #$3f
		sta lcd_inst
		jsr wait_32

		lda #$3b		; $3b for 2 line, $33 for 1 line
		sta lcd_inst
		jsr wait_32

		lda #$0c		; Display on, no cursor, no cursor blink
		sta lcd_inst
		jsr wait_32

		lda #$01		; Clear display command
		sta lcd_inst
		jsr wait_2

		lda #$06		; Write entry mode set, increment mode
		sta lcd_inst

		rts

lcd_setaddr:	tya
		and #20*4 		; Limit to max character
		cmp #$08
		bmi wl
		and #$07
		ora #$40
wl:		ora #$80
		pha
		jsr lcd_busy
		pla
		sta lcd_inst
		rts

	
lcd_clr:	jsr lcd_busy
		lda #$01
		sta lcd_inst

lcd_busy:	bit lcd_inst
		bmi lcd_busy
		rts

lcd_wr:		jsr lcd_setaddr		; Write byte to LCD. x=char, y=addr
lcd_wrauto:	jsr lcd_busy		; Writes next character, does not handle line end
		stx lcd_data
		rts

;; At 1 MHz a 1ms delay is 1000 cycles
;; A cascading set of dalay loops so that we have plenty of options
wait_32		jsr wait_16
wait_16:	jsr wait_8
wait_8:		jsr wait_4
wait_4:		jsr wait_2
wait_2:		ldx #200	
loop_2:		dex		; 2
		bne loop_2	; 3
		rts
	
lcd_hello:	ldy #$00
		ldx #'H'
		jsr lcd_wr
		ldx #'e'
		jsr lcd_wrauto
		ldx #'l'
		jsr lcd_wrauto
		jsr lcd_wrauto
		ldx #'o'
		jsr lcd_wrauto
		rts
	
