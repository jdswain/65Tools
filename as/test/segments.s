/* This is a comment */

	include "simple_include.s" 

	var test = 11
	message "Starting ", test, " End"
	if test == 11 {
	  error "Test is 11"
	}
	var expr = test + 32	
	var label = "Label"
	let label2 = child
	error "Test error"
	
init:	lda #02
	sta $00
	sta test-2
	inx
	dex

	cli
	cld
	lda <start_msg
	sta print_lo
	lda >start_msg
	sta print_hi
	jsr print
	rts

print:	ldx #00
loop:	//lda (print_lo),x
	//sta acia_data
	bne done
	inx
	bra loop
done:	rts
		
	
start_msg:	//data "Welcome to TMON\n",0
