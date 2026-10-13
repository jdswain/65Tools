	;; Disk Read

	cpu := "6502"
	
	org := $FD59


	NEXT := $F428 			

	POP1 := $F508
/*
POP1:	INX
	    INX
	    JMP NEXT
	*/

	PUSHA := $F874
	
	/*
F874:	STA $00,X
		LDY #$00
		STY #01,X
		JMP NEXT
	*/
	
	
	FD_STATUS = $0100
	FD_CMD = $0100
	FD_TRACK = $0101
	FD_SECTOR = $0102
	FD_DATA = $0103
	DRV_STAT = $0106
	DRV_CTL = $0106

	
	/*
	DRV_STAT
	7 nINTRQ
	6 n(INTREQ+DRQ)
	5 MOTOR 0 = ON, 1 = OFF

	DRV_CTL
	7 DENSITY 0 = DOUBLE, 1 = SINGLE
	5 MOTOR 0 = OFF, 1 = ON
	4 DRIVE SELECT 3
	3 DRIVE SELECT 2
	2 DRIVE SELECT 1
	1 DRIVE SELECT 0
	0 SIDE SELECT 0 = Side 0, 1 = Side 1
	*/
	
	;; DREAD ( addr n --- err )
	;; Reads 4 sectors starting at sector 4n + 1 of selected disk,
	;; current track to addr. Leaves error byte.
	
DREAD:		JSR CALC_SECT
.DSECT		JSR DSETUP
			LDA #$90			; Read sector, multiple records, compare for side 0, no 15ms delay, disable side select compare
			JSR D_CMD
			JSR RDSECT
			AND #$BF
			BEQ LOC2
			DEC $54
			BNE DSECT
.LOC2:		INX
			INX
			JMP PUSHA

CALC_SECT:	ASL 0,X				; X is top of stack = n
			ASL 0,X				; Calculate 4n + 1
			INC 0,X				; n is now sector number
			LDA #$05
			STA $54
			RTS

DSETUP:		LDA #$04
			STA $53				; Sectors remaining
			LDA $02,X			; Addr low
			STA $51
			LDA $03,X			; Addr high
			STA $52
			LDA $00,X			; Sector number
			STA FD_SECTOR
			JMP DINDEX 			; FDA8

RDSECT:		BIT DRV_STAT
			BVS RDSECT			; Branch if n(INTREQ+DRQ) set
			BPL INDLOOP			; Branch if nINTRQ not set
			LDA FD_DATA
			STA ($51),Y
			INY
			BNE RDSECT			; 256 byte sector
			INC $52				; Add $FF to addr
			DEC $53				; Dec sector remaining count
			BNE RDSECT

DINDEX:		LDA #$D4			; 1101 0100 = Force Interrupt on index pulse
			JSR D_CMD
.INDLOOP	LDA FD_STATUS
			LSR
			BCS INDLOOP			; FA
			ROL
			RTS

D_CMD:		STA FD_CMD
			LDY #$08
.DELLOOP	DEY
			BNE DELLOOP
			RTS

	;; 		DWRITE
	
DWRITE:	    JSR CALC_SECT
FDC3:	    JSR DSETUP
    		LDA #$B0			; Write sector, multiple records, compare for side 0, no 15ms delay, disable side select compare
			JSR $FDB5
			JSR WRITE_SEC
    		AND $FD
	
            BEQ 04
            DEC $54
            BNE ED
			JMP LOC2
	
WRITE_SEC   BIT $0106
            BVS FB
            BPL 13
            LDA (51),Y
            STA $0103
            INY
			BNE $F1
    		INC $52
    		DEC $53
    		BNE $EB
			JMP $FD90

/*
	DREAD FD59
	DWRITE FDC0
	DISK F874

	DISK
	SWAP
	LIT
	031C 						; B/SIDE
	@
	/MOD

	;S
	POP-NEXT?
	
	DISK ( addr n f --- )
	Single point entry to kernel disk handlers.
	Perform disk operation, read if f=1, write if f=0,
	Disk block n and memory location addr.
	
F874  A5 4F     LDA $4F 		; Push IP
F876  48        PHA
F877  A5 4E     LDA $4E
F879  48        PHA
F87A  18        CLC
F87B  A5 4C     LDA $4C 		; W
F87D  69  2     ADC #$02
F87F  85 4E     STA $4E			; IP
F881  98        TYA
F882  65 4D     ADC $4D	
F884  85 4F     STA $4F
F886  4C 28 F4  JMP $F428
	

	A0  2 B1 4C 48 C8 B1 4C 4C 21 F4
 F894  18 A5 4C 69  2 48 98 65 4D 4C 21 F4 A0  2 18 B1
 F8A4  4C 65 48 48 A9  0 65 49 4C 21 F4 89 F8  0  0 89
 F8B4  F8  1  0 89 F8  2  0 89 F8  3  0 89 F8  4  0 89
 F8C4  F8 20  0 A0 F8  0 A0 F8  2 A0 F8  4 A0 F8  6 A0
 F8D4  F8  8 A0 F8  A A0 F8  C A0 F8  E A0 F8 10 A0 F8
 F8E4  12 A0 F8 14 74 F8 D0 F8 3B F8 17 F7 74 F8 D3 F8
 F8F4  3B F8 17 F7 FA F8 F6  0 D0  2 F6  1 4C 28 F4  5
 F904  F9 18 B5  0 69  2 95  0 90  2 F6  1 4C 28 F4 15
 F914  F9 B5  0 D0  2 D6  1 D6  0 4C 28 F4 22 F9 38 B5
 F924   0 E9  2 95  0 B0  2 D6  1 4C 28 F4 74 F8 A5 F7
 F934  78 F7 17 F7 74 F8 30 F9 5B F7 17 F7 42 F9 38 B5
 F944   2 F5  0 B5  3 F5  1 98 2A 49  1 E8 E8 4C 4F F8
 F954  56 F9 B5  2 D5  0 B5  3 F5  1 94  3 50  2 49 80
 F964  10  1 C8 94  2 4C  8 F5 74 F8 D3 F7 54 F9 17 F7


FD59 20 74 FD    DREAD JSR $FD74
FD5C 20 7F FD                  JSR $FD7F
FD5F A9 90                         LDA #$90
FD61 20 B5 FD                  JSR $FDB5
FD64 20 93 FD                   JSR $FD93
FD67 29 BF                         AND #$BF
FD69 F0 04                         BEQ loc1 ;04
FD6B C6 54                         DEC $54
FD6D D0 ED                        BNE ED
FD6F E8                  .loc1     INX
FD70 E8                                INX
FD71 4C 4F F8                    JMP $F84F

FD74 16 00                          ASL 0,X
FD76 16 00                          ASL 0,X
FD78 F6 00                          INC 0,X
FD7A A9 05                         LDA #$05
FD7C 85 54                          STA $54
FD7E 60                                RTS

FD7F A9 04                            LDA #$04
FD81 85 53                             STA $53
FD83 B5 02                            LDA $02,X
FD85 85 51                             STA $51
FD87 B5 03                            LDA $03,X
FD89 85 52                          STA $52
FD8B B5 00                         LDA $00,X
FD8D 8D 02 01                   STA $0102
FD90 4C A8 FD                   JMP $FDA8

FD93 2C 06 01                    BIT $0106
FD96 70 FB                         BVS FB
FD98 10 13                          BPL 13
FD9A AD 03 01                   LDA $0103
FD9D 91 51                         STA ($51),Y
FD9F C8                               INY
FDA0 D0 F1                         BNE F1
FDA2 E6 52                          INC $52
FDA4 C6 53                          DEC $53
FDA6 D0 EB                         BNE EB                   

FDA8 A9 D4                        LDA #$D4
FDAA 20 B5 FD                  JSR $FDB5
FDAD AD 00 01                  LDA $0100
FDB0 4A                              LSR A
FDB1 B0 FA                        BCS FA 
FDB3 2A                              ROL A
FDB4 60                               RTS

FDB5 8D 00 01                  STA $0102
FDB8 A0 08                       LDY #$08
FDBA 88                            DEY
FDBB D0 FD                     BNE FD
FDBD 60                            RTS

	DWRITE
	
FDC0    20 74 FD   JSR $FD74
FDC3 	20 7F FD   JSR $FD7F
FDC6	A9 B0      LDA #$B0
FDC8	20 B5 FD   JSR $FDB5
FDCB	20 D9 FD   JSR $FDD9
FDCE	29 FD      AND $FD
	
FDD0    F0  4      BEQ 04
FDD2	C6 54      DEC $54
FDD4	D0 ED      BNE ED
FDD6	4C 6F FD   JMP $FD6F
	
FDD9	2C  6  1   BIT $0106
FDDC    70 FB      BVS FB
FDDE    10 CD      BPL 13
FDE0    B1 51      LDA (51),Y
FDE2    8D  3  1   STA $0103
FDE5    C8         INY
FDE6    D0 F1      BNE $F1
FDE8	E6 52      INC $52
FDEA	C6 53      DEC $53
FDEC    D0 EB      BNE $EB
FDEE    4C 90 FD   JMP $FD90

FDF1    F3 FD AD  0  1 A9 FF A0  3 99 18  3 88 10 FA
 FE00  4C 28 F4 EA EA A8 A9  0 2A 19  D FE 60 22 24 28
 FE10  30 13 FE AC 16  3 B9 18  3 C9 50 90  7 A9  3 20
 FE20  AA FD A9  0 8D  1  1 B5  0 8D  3  1 AC 16  3 99
 FE30  18  3 A9 13 20 AA FD 4C  8 F5 74 F8 AF F8 6E FC
 FE40  A5 F9 97 F4  C  0 AF F8 F8 F4 9D F9 AF F4 FC FF
 FE50  17 F7 74 F8 F0 F8 E5 F8 58 F8 17 F7 74 F8 D1 F7
 FE60  E5 F8 3B F8 F0 F8 C5 F7 30 F9 17 F7 74 F8 74 F9
 FE70  6B F7 97 F4  7  0 58 F4 2D F4 FA 17 F7 74 F8 D9
 FE80  F8 3B F8 F2 FC 74 F9 58 F4  9 C5 F7 54 F9 97 F4
 FE90   7  0 58 F4  7 78 F7 58 F4 30 78 F7 F4 FA 17 F7
 FEA0  74 F8 7D FE EF F7 CE F6 5B F7 97 F4 F6 FF 17 F7
 FEB0  74 F8 34 F7 D3 F7 C5 F7 56 FC 52 FE A0 FE 6C FE

' INIT CFA @ 0 D. FDF3 OK
FDF3 FF DUMP 
 FDF3  AD  0  1 A9 FF A0  3 99 18  3 88 10 FA 4C 28 F4
 FE03  EA EA A8 A9  0 2A 19  D FE 60 22 24 28 30 13 FE
 FE13  AC 16  3 B9 18  3 C9 50 90  7 A9  3 20 AA FD A9
 FE23   0 8D  1  1 B5  0 8D  3  1 AC 16  3 99 18  3 A9
 FE33  13 20 AA FD 4C  8 F5 74 F8 AF F8 6E FC A5 F9 97
 FE43  F4  C  0 AF F8 F8 F4 9D F9 AF F4 FC FF 17 F7 74
 FE53  F8 F0 F8 E5 F8 58 F8 17 F7 74 F8 D1 F7 E5 F8 3B
 FE63  F8 F0 F8 C5 F7 30 F9 17 F7 74 F8 74 F9 6B F7 97
 FE73  F4  7  0 58 F4 2D F4 FA 17 F7 74 F8 D9 F8 3B F8
 FE83  F2 FC 74 F9 58 F4  9 C5 F7 54 F9 97 F4  7  0 58
 FE93  F4  7 78 F7 58 F4 30 78 F7 F4 FA 17 F7 74 F8 7D
 FEA3  FE EF F7 CE F6 5B F7 97 F4 F6 FF 17 F7 74 F8 34
 FEB3  F7 D3 F7 C5 F7 56 FC 52 FE A0 FE 6C FE 5C FE 3F
 FEC3  F7 C5 F7 30 F9 3A FE EF F9 17 F7 74 F8 AF F8 B0
 FED3  FE 9D F9 17 F7 74 F8 34 F7 2C FC 3F F7 B0 FE 17
 FEE3  F7 74 F8 2C FC CE FE 17 F7 74 F8 3B F8 E4 FE 17

' SEEK CFA @ FF DUMP 
 FE13  AC 16  3 LDY $0316
	B9 18  3 LDA $0318
	C9 50 CMP #$50
	90  7 BCC 07
	A9  3 LDA #$03
	20 AA FD JSR FDAA
FE22	A9  0 LDA #$00
	8D  1  1 STA $0101
	B5  0 LDA $00,X
	8D  3  1 STA $0103
	AC 16  3 LDY $0316
	99 18  3 STA $0318
FE32	A9 13 LDA #$13
	20 AA FD JSR $FDAA
	4C  8 F5 JMP POP1

	74 F8 AF F8 6E FC A5 F9 97
 FE43  F4  C  0 AF F8 F8 F4 9D F9 AF F4 FC FF 17 F7 74
 FE53  F8 F0 F8 E5 F8 58 F8 17 F7 74 F8 D1 F7 E5 F8 3B
 FE63  F8 F0 F8 C5 F7 30 F9 17 F7 74 F8 74 F9 6B F7 97
 FE73  F4  7  0 58 F4 2D F4 FA 17 F7 74 F8 D9 F8 3B F8
 FE83  F2 FC 74 F9 58 F4  9 C5 F7 54 F9 97 F4  7  0 58
 FE93  F4  7 78 F7 58 F4 30 78 F7 F4 FA 17 F7 74 F8 7D
 FEA3  FE EF F7 CE F6 5B F7 97 F4 F6 FF 17 F7 74 F8 34
 FEB3  F7 D3 F7 C5 F7 56 FC 52 FE A0 FE 6C FE 5C FE 3F
 FEC3  F7 C5 F7 30 F9 3A FE EF F9 17 F7 74 F8 AF F8 B0
 FED3  FE 9D F9 17 F7 74 F8 34 F7 2C FC 3F F7 B0 FE 17
 FEE3  F7 74 F8 2C FC CE FE 17 F7 74 F8 3B F8 E4 FE 17
 FEF3  F7 F6 FE A0  4 B5  3 6A 76  2 88 D0 FA B4  2 84
 FF03   3 6A 6A  8 4A 28 6A 38 6A 85  2 A9 60 85 14 B5

	*/
