	cpu="816"	

	longa=off
	longi=off

	org=$ff00
	
start:	lda #$ffff		;a9 ff
	pea $aabb		;f4 bb aa
	jsl start		;22 00 ff 00

	;; DPAGE test
	lda $10			;a5 10
	lda $0010		;a5 10
	lda $1000		;ad 00 10

	dpage = $1000

	lda $1000		;a5 00     

	lda $10			;a5 10
	lda.a $10		;ad 10 00
	
	
