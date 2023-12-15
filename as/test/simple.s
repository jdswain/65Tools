/* This is a comment */

	section "text"
	
	include "simple_include.s" 

	var test = 11
	message "Starting ", test, " End"
	if test == 11 {
	  lda #$00
	  error "Test is ", (test + 2) * 2
	} else {
	  lda #$ff
	  error "Test is not 11"
	}
	var expr = test + 32	
	var label = "Label"
	let label2 = child
	error "Test error"

	var start_msg = $abcd
init:	lda.l #02
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

	fill $11, $aa, $55	
	
print:	ldx #00
loop:	//lda (print_lo),x
	//sta acia_data
	bne done
	inx
	bra loop
done:	rts

	section "dp"
	
	var aa = 2
	var bb = 10

//start_msg:	//data "Welcome to TMON\n",0
