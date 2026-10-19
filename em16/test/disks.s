; disks.s - a boot ROM for em16 -fpga that works the carrier's 82077AA and
; 53C80 by polling, as drivers would, and prints what they answer on the
; serial port. test/disks.sh runs it on images whose sectors hold their
; own numbers and compares the output with test/disks.expected.

                cpu = "65C816"
                org = $E000

fdc_dor         = $0802
fdc_msr         = $0804
fdc_fifo        = $0805
fdc_ccr         = $0807
ext_ctl         = $0340         ; bit 0: a card asserts IRQ#
sc_data         = $0830         ; 53C80: current data / output data
sc_icr          = $0831
sc_mode         = $0832
sc_tcr          = $0833
sc_bus          = $0834         ; current bus status
sc_bsr          = $0835         ; bus and status
sc_rpi          = $0837         ; reset parity/interrupt
scc_ctl         = $0822
scc_data        = $0823

ptr             = $10           ; string pointer
cnt             = $12           ; bytes moved
phase           = $14
status          = $15
cdbi            = $16
outi            = $18
cdb             = $20           ; 12 bytes
inbuf           = $3000
outbuf          = $5000

reset:          clc
                xce
                sep #$20
                rep #$10
                longa = off
                longi = on
                ldx #$01FF
                txs
                lda scc_ctl
                lda #5
                sta scc_ctl
                lda #$68                ; WR5: transmit on
                sta scc_ctl

; --- the floppy ---------------------------------------------------------

                ldx #s_fdc
                jsr puts
                lda ext_ctl             ; nothing yet: the 82077AA is in reset
                jsr hex
                lda #$1C                ; motor A, DMA gate (INT on), out of reset
                sta fdc_dor
                lda ext_ctl             ; INT for the reset
                jsr hex
                lda fdc_msr
                jsr hex
                jsr crlf
                ldx #s_sense            ; the four drives' ready change
                jsr puts
                ldy #4
.sense:         lda #$08
                jsr fout
                jsr fin
                jsr hex
                jsr fin
                dey
                bne .sense
                lda ext_ctl
                jsr hex
                jsr crlf

                lda #$10                ; VERSION
                jsr fout
                ldx #s_version
                jsr puts
                jsr fin
                jsr hex
                jsr crlf

                lda #$03                ; SPECIFY: 3 ms steps, non-DMA
                jsr fout
                lda #$DF
                jsr fout
                lda #$03
                jsr fout
                stz fdc_ccr             ; 500 kbit/s, for 1.44M

                ldx #s_recal
                jsr puts
                lda #$07                ; RECALIBRATE drive 0
                jsr fout
                lda #$00
                jsr fout
                jsr fwait
                lda #$0F                ; SEEK to 5
                jsr fout
                lda #$00
                jsr fout
                lda #$05
                jsr fout
                lda fdc_msr             ; drive 0 busy seeking
                jsr hex
                jsr fwait
                jsr crlf

                ldx #s_read             ; READ DATA C5 H0 R3, to EOT 4
                jsr puts
                lda #$46
                ldx #rd_cmd
                jsr fcmd
                jsr fread
                jsr fresult
                ldx #inbuf              ; each sector's first bytes: its LBA
                jsr show2
                ldx #inbuf+512
                jsr show2
                jsr crlf

                ldx #s_write            ; WRITE DATA C5 H1 R1, one sector of $A5
                jsr puts
                lda #$45
                ldx #wr_cmd
                jsr fcmd
.wloop:         lda fdc_msr
                bpl .wloop
                and #$20
                beq .wdone
                lda #$A5
                sta fdc_fifo
                bra .wloop
.wdone:         jsr fresult
                jsr crlf

                ldx #s_density          ; the same read at 250 kbit/s
                jsr puts
                lda #2
                sta fdc_ccr
                lda #$46
                ldx #rd_cmd
                jsr fcmd
                jsr fread
                jsr fresult
                jsr crlf
                stz fdc_ccr

                ldx #s_wrongcyl         ; C4 while the head is on 5
                jsr puts
                lda #$46
                ldx #rd_c4
                jsr fcmd
                jsr fread
                jsr fresult
                jsr crlf

                ldx #s_readid
                jsr puts
                lda #$4A
                jsr fout
                lda #$04                ; head 1
                jsr fout
                jsr fresult
                jsr crlf

; --- SCSI ---------------------------------------------------------------

                ldx #s_scsi
                jsr puts
                lda sc_rpi
                lda sc_bus
                jsr hex
                jsr crlf

                ldx #s_tur              ; UNIT ATTENTION first
                jsr puts
                ldx #c_tur
                jsr scmd
                ldx #s_sense2
                jsr puts
                ldx #c_sense
                jsr scmd
                lda inbuf+2             ; key
                jsr hex
                lda inbuf+12            ; code
                jsr hex
                jsr crlf
                ldx #s_tur
                jsr puts
                ldx #c_tur
                jsr scmd

                ldx #s_inquiry
                jsr puts
                ldx #c_inquiry
                jsr scmd
                ldx #8
.inq:           lda inbuf,x
                jsr putc
                inx
                cpx #32
                bne .inq
                jsr crlf

                ldx #s_capacity
                jsr puts
                ldx #c_capacity
                jsr scmd
                ldx #0
.cap:           lda inbuf,x
                jsr hex
                inx
                cpx #8
                bne .cap
                jsr crlf

                ldx #s_read10           ; blocks 100 and 101
                jsr puts
                ldx #c_read10
                jsr scmd
                ldx #inbuf
                jsr show2
                ldx #inbuf+512
                jsr show2
                rep #$20
                lda cnt
                sep #$20
                xba
                jsr hex
                xba
                jsr hex
                jsr crlf

                ldx #0                  ; block 7 := $5A
                lda #$5A
.fill:          sta outbuf,x
                inx
                cpx #512
                bne .fill
                ldx #s_write6
                jsr puts
                ldx #c_write6
                jsr scmd
                ldx #s_read6
                jsr puts
                ldx #c_read6
                jsr scmd
                ldx #inbuf
                jsr show2
                ldx #inbuf+510
                jsr show2
                jsr crlf

                ldx #s_bad              ; an unknown command, then its sense
                jsr puts
                ldx #c_bad
                jsr scmd
                ldx #s_sense2
                jsr puts
                ldx #c_sense
                jsr scmd
                lda inbuf+2
                jsr hex
                lda inbuf+12
                jsr hex
                jsr crlf

                ldx #s_range            ; past the end
                jsr puts
                ldx #c_range
                jsr scmd

                ldx #s_noone            ; select ID 1: nobody answers
                jsr puts
                lda #$82
                sta sc_data
                lda #$05                ; data bus, SEL
                sta sc_icr
                ldx #200
.wait1:         lda sc_bus
                and #$40
                bne .ans
                dex
                bne .wait1
                stz sc_icr
                ldx #s_timeout
                jsr puts
                bra .rst
.ans:           ldx #s_answered
                jsr puts
.rst:           ldx #s_busreset         ; RST: the interrupt, then UNIT ATTENTION
                jsr puts
                lda #$80
                sta sc_icr
                stz sc_icr
                lda sc_bsr
                jsr hex
                lda ext_ctl
                jsr hex
                lda sc_rpi
                lda sc_bsr
                jsr hex
                lda ext_ctl
                jsr hex
                jsr crlf
                ldx #s_tur
                jsr puts
                ldx #c_tur
                jsr scmd
                stp

; --- floppy routines ------------------------------------------------------

fout:           pha
.wt:             lda fdc_msr
                and #$C0
                cmp #$80
                bne .wt
                pla
                sta fdc_fifo
                rts

fin:            lda fdc_msr
                and #$C0
                cmp #$C0
                bne fin
                lda fdc_fifo
                rts

; a command: A, then the 8 bytes at X
fcmd:           jsr fout
                ldy #8
.n:             lda 0,x
                jsr fout
                inx
                dey
                bne .n
                rts

; wait for INT, then SENSE INTERRUPT STATUS, printed
fwait:          lda ext_ctl
                lsr a
                bcc fwait
                lda #$08
                jsr fout
                jsr fin
                jsr hex
                jsr fin
                jsr hex
                rts

; the execution phase of a read, into inbuf
fread:          ldx #0
.lp:             lda fdc_msr
                bpl .lp
                and #$20                ; non-DMA execution still?
                beq .done
                lda fdc_fifo
                sta inbuf,x
                inx
                bra .lp
.done:          stx cnt
                rts

; the result bytes, printed
fresult:        lda fdc_msr             ; wait for the result phase
                bpl fresult
.next:          lda fdc_msr
                and #$D0
                cmp #$D0
                bne .done
                lda fdc_fifo
                jsr hex
                bra .next
.done:          rts

; --- SCSI routines --------------------------------------------------------

; Run the command whose length and bytes are at X: arbitrate, select ID 0
; with ATN, IDENTIFY, then the phases the target asks for until it frees
; the bus. Data in goes to inbuf, data out comes from outbuf; the status
; is printed.
scmd:           lda 0,x                 ; the length, before the bytes
                sta cdbi
                stz cdbi+1
                ldy #0
.copy:          lda 1,x
                sta cdb,y
                inx
                iny
                cpy cdbi
                bne .copy
                lda #$80                ; arbitrate as ID 7
                sta sc_data
                lda #$01
                sta sc_mode
.arb:           lda sc_icr
                and #$40                ; AIP
                beq .arb
                lda #$0C                ; BSY, SEL
                sta sc_icr
                lda #$81                ; IDs 7 and 0
                sta sc_data
                lda #$0F                ; ATN, data bus
                sta sc_icr
                stz sc_mode
                lda #$07                ; release BSY
                sta sc_icr
.sel:           lda sc_bus
                and #$40
                beq .sel
                lda #$02                ; release SEL and the data bus, keep ATN
                sta sc_icr
                ldx #0
                stx cdbi
                stx outi
                stx cnt
.phase:         lda sc_bus
                and #$40
                beq .free
                lda sc_bus
                and #$20                ; REQ
                beq .phase
                lda sc_bus
                lsr a
                lsr a
                and #7
                sta phase
                sta sc_tcr
                cmp #6
                beq .msgout
                cmp #2
                beq .command
                cmp #1
                beq .datain
                cmp #0
                beq .dataout
                cmp #3
                beq .status
                lda sc_data             ; message in
                bra .ackin
.msgout:        lda #$80                ; IDENTIFY, LUN 0; ATN off with the last byte
                sta sc_data
                lda #$11
                bra .ack
.command:       ldx cdbi
                lda cdb,x
                inx
                stx cdbi
                sta sc_data
                lda #$11
                bra .ack
.dataout:       ldx outi
                lda outbuf,x
                inx
                stx outi
                sta sc_data
                lda #$11
                bra .ack
.datain:        ldx cnt
                lda sc_data
                sta inbuf,x
                inx
                stx cnt
                lda #$10
                bra .ack
.status:        lda sc_data
                sta status
.ackin:         lda #$10
.ack:           sta sc_icr              ; ACK
.unreq:         lda sc_bus
                and #$20
                bne .unreq
                stz sc_icr
                bra .phase
.free:          ldx #s_status
                jsr puts
                lda status
                jsr hex
                jsr crlf
                rts

; --- output ---------------------------------------------------------------

putc:           pha
.wt:             lda scc_ctl
                and #$04
                beq .wt
                pla
                sta scc_data
                rts

puts:           lda 0,x
                beq .done
                jsr putc
                inx
                bra puts
.done:          rts

hex:            pha
                lsr a
                lsr a
                lsr a
                lsr a
                jsr .nib
                pla
                pha
                jsr .nib
                lda #$20
                jsr putc
                pla
                rts
.nib:           and #$0F
                cmp #10
                bcc .dig
                adc #6
.dig:           adc #$30
                jmp putc

; the two bytes at X
show2:          lda 0,x
                jsr hex
                lda 1,x
                jsr hex
                rts

crlf:           lda #13
                jsr putc
                lda #10
                jmp putc

; --- data -----------------------------------------------------------------

rd_cmd:         data.b $00, 5, 0, 3, 2, 4, $1B, $FF
rd_c4:          data.b $00, 4, 0, 3, 2, 4, $1B, $FF
wr_cmd:         data.b $04, 5, 1, 1, 2, 1, $1B, $FF

c_tur:          data.b 6, $00, 0, 0, 0, 0, 0
c_sense:        data.b 6, $03, 0, 0, 0, 18, 0
c_inquiry:      data.b 6, $12, 0, 0, 0, 36, 0
c_capacity:     data.b 10, $25, 0, 0, 0, 0, 0, 0, 0, 0, 0
c_read10:       data.b 10, $28, 0, 0, 0, 0, 100, 0, 0, 2, 0
c_write6:       data.b 6, $0A, 0, 0, 7, 1, 0
c_read6:        data.b 6, $08, 0, 0, 7, 1, 0
c_bad:          data.b 6, $1F, 0, 0, 0, 0, 0
c_range:        data.b 10, $28, 0, 0, 0, $28, 0, 0, 0, 1, 0

s_fdc:          text.0 "82077AA: $0340, DOR on, MSR: "
s_sense:        text.0 "sense interrupt x4: "
s_version:      text.0 "version: "
s_recal:        text.0 "recalibrate, seek 5: "
s_read:         text.0 "read C5 H0 R3-4: "
s_write:        text.0 "write C5 H1 R1: "
s_density:      text.0 "read at 250K: "
s_wrongcyl:     text.0 "read C4: "
s_readid:       text.0 "read ID head 1: "
s_scsi:         text.0 "53C80: bus "
s_tur:          text.0 "test unit ready: "
s_sense2:       text.0 "request sense: "
s_inquiry:      text.0 "inquiry: "
s_capacity:     text.0 "read capacity: "
s_read10:       text.0 "read(10) 100-101: "
s_write6:       text.0 "write(6) 7: "
s_read6:        text.0 "read(6) 7: "
s_bad:          text.0 "command $1F: "
s_range:        text.0 "read(10) $280000: "
s_noone:        text.0 "select ID 1: "
s_timeout:      text.0 "no answer"
s_answered:     text.0 "answered!"
s_busreset:     text.0 $0D, $0A, "bus reset: "
s_status:       text.0 "status "

                fill $FFFC-pc, $FF
                data.w reset, reset
