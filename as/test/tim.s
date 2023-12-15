(*
TIM Monitor functions.

*)

	;; WRT
	;; Type a character
	;; Arg: A
	;; Result: None
	;; A,X cleared, Y preserved
	WRT = $72c6

	;; RDT
	;; Read a character
	;; Arg: None
	;; Result: A
	;; X cleared, Y not preserved
	RDT = $72e9

	;; CRLF
	;; Type CR-LF and delay
	;; Arg: None
	;; Result: None
	;; A, X cleared, Y preserved
	CRLF = $728a

	;; SPACE
	;; Type a space character
	;; Arg: None
	;; Result: None
	;; A,X,Y preserved 
	SPACE = $7377

	;; WROB
	;; Type a byte in hex
	;; Arg: A
	;; Result: None
	;; A,X cleared, Y preserved
	WROB = $72B1

	;; RDHSR
	;; Read a character from high-speed paper tape reader
	;; Arg: None
	;; Result: X--char read
	;;         A--char trimmed to 7 bits
	;;   	  Y preserved
	RDHSR = $733D

	start_address = $f6	; Set with hex tape on load ($f6,$f7)
	CR-LF_Delay=$E3		; Set on load or with user program (in bit times,
				; minimum of 1.  Zero means 256 bits-time delay).

	UINT=$FFF8		; User IRQ vector
	NMI_Vector=$FFFA	; Hardware NMI vector
	RESET_Vector=$FFFC	; Hardware RESET vector
	IRQ_Vector=$FFFE	; Hardware IRQ vector
                                       
                                       
