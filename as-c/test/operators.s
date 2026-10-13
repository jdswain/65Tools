
out_lo:	data 0
out_hi:	data 0

	let println = $ffef
	
string:	text "Welcome to 65/OS", $33, "Ready."
	
end:

	lda #<(end-string)	;a9 17
	sta out_lo		;85 00
	lda #>(end-string)	;a9 00
	sta out_hi		;85 01
	jsr println		;20 ef ff
	

	
