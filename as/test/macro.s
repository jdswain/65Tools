/* This is a comment */

	org = $1000
init:	lda #02
	rts
	
longax	macro va, vb, vc {
	  message "a = ", va, "b = ", vb, "c = ", vc
	  lda #va
	  longa=on
	  longi=on
	  lda #vb
	  sta vc
	}

	sep #%00110000

	longax 1, 2, 3

	longax $10, $11, $12
	
	;; Bugs
	;; Macro call should be before macro listing
	
	
