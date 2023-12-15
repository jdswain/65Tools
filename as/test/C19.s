	cpu = "RC19"
	org = $0300

	zp1 = $10
	abs1 = $1011
	
start:	
	
	/*
	We test all instructions and can compare to expected values in comments
	*/

	;; ADC
t_adc:	adc #$0f		;69 0f
	adc 01			;65 01
	adc 02,x		;75 02
	adc $1122		;6d 22 11
	adc $0011		;65 11
	adc.b $0011 		;6d 11 00
	adc $1122,X		;7d 22 11
	adc $3344,Y		;79 44 33
	adc ($10)		;61 e0
	adc ($e0),x 		;71 e0

	;; ADD
	add #$2a		;89 2a
	add $33			;64 33
	add $d0,X		;74 d0

	;; AND
	and #11			;29 0b
	and $ab 		;25 ab
	and $12,x		;35 12
	and $2233		;2d 33 22
	and $2233,x		;3d 33 22
	and $2233,y		;39 33 22
	and ($ffff)		;21 ff
	and ($fe),x		;31 fe

	;; ASL
	asl			;0a
	asl a			;0a
	asl 15			;06 0f
	asl 01,x		;16 01
	asl $1122		;0e 22 11
	asl.a $11,x		;1e 11 00

	;; ASR
t_asr:	asr			;3a

	;; BAR
t_bar:	bar start,$0f,t_asr	;e2 00 03 0f fe

	;; BAS
	bas start,$f0,t_asr	;f2 00 03 f0 f9

	;; BBR
	bbr 0,01,t_bbs		;0f 01 15
	bbr 1,01,t_bbs		;1f 01 12
	bbr 2,01,t_bbs		;2f 01 0f
	bbr 3,01,t_bbs		;3f 01 0c
	bbr 4,01,t_bbs		;4f 01 09
	bbr 5,01,t_bbs		;5f 01 06
	bbr 6,01,t_bbs		;6f 01 03
	bbr 7,01,t_bbs		;7f 01 00


t_bbs:		;; BBS	
	bbs 0,01,t_bbs		;8f 01 fd
	bbs 1,01,t_bbs		;9f 01 fa
	bbs 2,01,t_bbs		;af 01 f7
	bbs 3,01,t_bbs		;bf 01 f4
	bbs 4,01,t_bbs		;cf 01 f1
	bbs 5,01,t_bbs		;df 01 ee
	bbs 6,01,t_bbs		;ef 01 eb
	bbs 7,01,t_bbs		;ff 01 e8

	;; BCC
	bcc start		;90 87

	;; BCS
	bcs start		;b0 85

	;; BEQ
	beq start		;f0 83

	;; BIT
	bit zp1			;24 10
	bit abs1		;2c 11 10

	;; BMI
	bmi t_bbs		;30 db

	;; BPL
	bpl t_bbs		;10 d9

	;; BRA
	bra t_bbs		;80 d7

	;; BRK
	brk			;00
	byte $ea		;ea
	brk #$ea		;00 ea

	;; BVC
	bvc t_bbs		;50 d1

	;; BVS

	;; CLC
	clc			;18

	;; CLD
	cld			;D8

	;; CLI
	cli			;58

	;; CLV
	clv			;b8

	;; CLW
	clw			;52

	;; CMP

	;; CPX

	;; CPY

	;; DEC

	;; DEX

	;; DEY

	;; EOR

	;; EXC
	exc zp1,x		;d4 10

	;; INC

	;; INI
	ini			;BB

	;; INX

	;; INY

	;; JMP
	jmp abs1		;4c 11 10
	jmp (abs1)		;6c 11 10
	jmp (abs1,x)		;7c 11 10

	;; JPI
	jpi (abs1)		;0c 11 10
	
	;; JSB
	jsb 0 			;0b
	jsb 1			;1b
	jsb 2			;2b
	jsb 3			;3b
	jsb 4			;4b
	jsb 5			;5b
	jsb 6			;6b
	jsb 7			;7b

	;; JSR
	jsr start		;20 00 03

	;; LAB
	lab			;13
	LAB a			;13

	;; LAI
	lai			;eb

	;; LAN
	lan			;ab

	;; LDA

	;; LDX

	;; LDY

	;; LII
	lii			;9b

	;; LSR

	;; MPA
	mpa			;12

	;; MPY
	mpy			;02

	;; NEG
	neg a			;1a

	;; NOP
	nop			;ea

	;; NXT
	nxt			;8b

	;; ORA

	;; PHA
	pha			;48

	;; PHI
	phi			;cb

	;; PHP
	php			;08

	;; PHW
	phw			;23

	;; PHX
	phx			;da

	;; PHY
	phy			;5a

	;; PIA
	pia			;fb

	;; PLA
	pla			;68

	;; PLI
	pli			;db

	;; ...

	;; RBA
	rba #$07,abs1		;c2 07 11 10

	;; RMB
	rmb 0,zp1		;07 10
	rmb 1,zp1		;17 10
	rmb 2,zp1		;27 10
	rmb 3,zp1		;37 10
	rmb 4,zp1		;47 10
	rmb 5,zp1		;57 10
	rmb 6,zp1		;67 10
	rmb 7,zp1		;77 10

	;; RND
	rnd			;42

	;; ROL

	;; ROR

	;; RTI
	rti			;40

	;; RTS
	rts			;60

	;; SBA
	sba #$f0,abs1		;d2 f0 11 10

	;; SBC

	;; SEC
	sec			;38

	;; SED
	sed			;f8

	;; SEI
	sei			;78

	;; SMB
	smb 0,zp1		;87 10
	smb 1,zp1		;97 10
	smb 2,zp1		;a7 10
	smb 3,zp1		;b7 10
	smb 4,zp1		;c7 10
	smb 5,zp1		;d7 10
	smb 6,zp1		;e7 10
	smb 7,zp1		;f7 10

	;; STA

	;; STI
	sti #$ff,zp1		;b2 ff 10

	;; STX

	;; STY

	;; TAW
	taw			;62

	;; TAX
	tax			;aa

	;; TAY
	tay			;a8

	;; TIP
	tip 			;03

	;; TSX
	tsx			;ba

	;; TWA
	twa			;72

	;; TXA
	txa			;8a

	;; TXS
	txs			;9a

	;; TYA
	tya			;98

	
	sta $0E
	lii
	RTS
