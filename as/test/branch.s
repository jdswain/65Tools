	cpu="RC19"
	org=$2200

start:	bra dest		;80 50

	org=$2252
	
dest:	nop

	org=$2200

	bcs dest2		;80 B0
	
	org=$21b2

dest2:	nop
	
