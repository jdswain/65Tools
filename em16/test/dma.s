; dma.s - a boot ROM for em16 -fpga that moves sectors by DMA (EmDMA, the
; SoC's engine at $0400) between memory and the carrier's 82077AA and
; 53C80, and by pseudo-DMA (the CPU at the /DACK slots), and prints what
; the chips answer on the serial port. test/dma.sh runs it on images whose
; sectors hold their own numbers, compares the output with
; test/dma.expected, and checks the sectors it writes.

                cpu = "65C816"
                org = $E000

fdc_dor         = $0802
fdc_msr         = $0804
fdc_fifo        = $0805
fdc_ccr         = $0807
fdc_dack        = $0810         ; slot 1: the 82077AA's /DACK
ext_ctl         = $0340         ; bit 0: a card asserts IRQ#
sc_data         = $0830
sc_icr          = $0831
sc_mode         = $0832
sc_tcr          = $0833
sc_bus          = $0834
sc_bsr          = $0835         ; read: bus and status; write: start DMA send
sc_rpi          = $0837         ; read: reset interrupt; write: start DMA initiator receive
sc_dack         = $0840         ; slot 4: the 53C80's /DACK
scc_ctl         = $0822
scc_data        = $0823
dma0            = $0400         ; channel 0 (SCSI): ADDR +0, COUNT +4, CTRL +8, STATUS +9
dma1            = $0410         ; channel 1 (floppy)

ptr             = $10
cnt             = $12
phase           = $14
status          = $15
cdbi            = $16
outi            = $18
xmode           = $1A           ; data phases: 0 by the CPU, 1 by DMA, 2 pseudo-DMA
dbsr            = $1B           ; the bus and status register when DMA ended
dtcr            = $1C
cdb             = $20
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
                lda #$68
                sta scc_ctl

; --- the floppy -----------------------------------------------------------

                lda #$1C                ; motor A, DMA gate, out of reset
                sta fdc_dor
                ldy #4
.sense:         lda #$08
                jsr fout
                jsr fin
                jsr fin
                dey
                bne .sense
                lda #$03                ; SPECIFY: 3 ms steps, DMA (ND = 0)
                jsr fout
                lda #$DF
                jsr fout
                lda #$02
                jsr fout
                stz fdc_ccr             ; 500 kbit/s, for 1.44M
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
                jsr fwait

                ldx #s_fread            ; C5 H0 R3-4 by DMA, TC on the last byte
                jsr puts
                ldx #inbuf
                ldy #1024
                lda #$0D                ; IE, TC, device to memory, EN
                jsr dma1go
                lda dma1+9              ; BUSY, DRQ not yet (the sector is not found)
                jsr hex
                lda #$46
                ldx #rd_cmd
                jsr fcmd
                lda fdc_msr             ; execution, DMA: busy only
                jsr hex
                jsr fresult
                jsr dma1show
                ldx #inbuf
                jsr show2
                ldx #inbuf+512
                jsr show2
                ldx #inbuf+1023
                jsr show1
                lda #$01                ; clear DONE
                sta dma1+9
                lda dma1+9
                jsr hex
                jsr crlf

                ldx #s_fwrite           ; C5 H1 R1 by DMA, $A5
                jsr puts
                ldx #0
                lda #$A5
.ffill:         sta outbuf,x
                inx
                cpx #512
                bne .ffill
                ldx #outbuf
                ldy #512
                lda #$07                ; TC, memory to device, EN
                jsr dma1go
                lda #$45
                ldx #wr_cmd
                jsr fcmd
                jsr fresult
                jsr dma1show
                jsr crlf

                ldx #s_overrun          ; C5 H0 R3, the channel not started
                jsr puts
                lda #$46
                ldx #rd_one
                jsr fcmd
                jsr fresult
                jsr crlf

                ldx #s_fpseudo          ; C5 H0 R5 by the CPU at $0810
                jsr puts
                lda #$46
                ldx #rd_r5
                jsr fcmd
                ldx #0
.fp:            lda dma1+9              ; channel 1's DRQ
                and #$40
                beq .fp
                lda fdc_dack
                sta inbuf,x
                inx
                cpx #512
                bne .fp
                jsr fresult             ; no TC: the end of the cylinder
                ldx #inbuf
                jsr show2
                jsr crlf

; --- SCSI -----------------------------------------------------------------

                lda sc_rpi
                stz xmode
                ldx #s_sense            ; clears the power-on UNIT ATTENTION
                jsr puts
                ldx #c_sense
                jsr scmd
                jsr crlf

                ldx #s_sread            ; blocks 100-101 by DMA
                jsr puts
                lda #1
                sta xmode
                ldx #inbuf
                ldy #1024
                lda #$05                ; TC, device to memory, EN
                jsr dma0go
                ldx #c_read10
                jsr scmd
                ldx #inbuf
                jsr show2
                ldx #inbuf+512
                jsr show2
                ldx #inbuf+1023
                jsr show1
                jsr crlf

                ldx #s_swrite           ; block 7 := $5A by DMA
                jsr puts
                ldx #0
                lda #$5A
.sfill:         sta outbuf,x
                inx
                cpx #512
                bne .sfill
                ldx #outbuf
                ldy #512
                lda #$07                ; TC, memory to device, EN
                jsr dma0go
                ldx #c_write6
                jsr scmd
                jsr crlf

                ldx #s_sshort           ; block 9, with 600 bytes asked for
                jsr puts
                ldx #inbuf
                ldy #600
                lda #$05
                jsr dma0go
                ldx #c_read9
                jsr scmd
                ldx #inbuf
                jsr show2
                jsr crlf

                ldx #s_spseudo          ; block 7 by the CPU at $0840
                jsr puts
                lda #2
                sta xmode
                ldx #c_read6
                jsr scmd
                ldx #inbuf
                jsr show2
                ldx #inbuf+511
                jsr show1
                jsr crlf
                stp

; --- DMA ------------------------------------------------------------------

; channel 1 (dma1go) or 0 (dma0go): ADDR = X in bank 0, COUNT = Y, CTRL = A
dma1go:         pha
                rep #$20
                txa
                sta dma1
                tya
                sta dma1+4
                sep #$20
                stz dma1+2
                stz dma1+6
                pla
                sta dma1+8
                rts

dma0go:         pha
                rep #$20
                txa
                sta dma0
                tya
                sta dma0+4
                sep #$20
                stz dma0+2
                stz dma0+6
                pla
                sta dma0+8
                rts

; channel 1's STATUS, and its COUNT and ADDR, printed
dma1show:       ldx #s_dma
                jsr puts
                lda dma1+9
                jsr hex
                lda dma1+5
                jsr hex
                lda dma1+4
                jsr hex
                lda dma1+1
                jsr hex
                lda dma1
                jsr hex
                rts

dma0show:       ldx #s_dma
                jsr puts
                lda dma0+9
                jsr hex
                lda dma0+5
                jsr hex
                lda dma0+4
                jsr hex
                lda dma0+1
                jsr hex
                lda dma0
                jsr hex
                rts

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

fcmd:           jsr fout
                ldy #8
.n:             lda 0,x
                jsr fout
                inx
                dey
                bne .n
                rts

fwait:          lda ext_ctl
                lsr a
                bcc fwait
                lda #$08
                jsr fout
                jsr fin
                jsr fin
                rts

; the result bytes, printed
fresult:        lda fdc_msr
                and #$C0
                cmp #$C0
                bne fresult
.next:          lda fdc_msr
                and #$D0
                cmp #$D0
                bne .done
                lda fdc_fifo
                jsr hex
                bra .next
.done:          rts

; --- SCSI -----------------------------------------------------------------

; Run the command whose length and bytes are at X, as test/disks.s does,
; with the data phases as xmode says: by the CPU (0), by DMA with channel 0
; already set up (1), or by the CPU at the /DACK slot (2, reads only). The
; status is printed, and after DMA the bus and status register as it was
; when the transfer ended, the target command register, and channel 0.
scmd:           lda 0,x
                sta cdbi
                stz cdbi+1
                ldy #0
.copy:          lda 1,x
                sta cdb,y
                inx
                iny
                cpy cdbi
                bne .copy
                lda #$80
                sta sc_data
                lda #$01
                sta sc_mode
.arb:           lda sc_icr
                and #$40
                beq .arb
                lda #$0C
                sta sc_icr
                lda #$81
                sta sc_data
                lda #$0F
                sta sc_icr
                stz sc_mode
                lda #$07
                sta sc_icr
.sel:           lda sc_bus
                and #$40
                beq .sel
                lda #$02
                sta sc_icr
                ldx #0
                stx cdbi
                stx outi
                stx cnt
                stz dbsr
                stz dtcr
.phase:         lda sc_bus
                and #$40
                bne .busy
                jmp .free
.busy:          lda sc_bus
                and #$20
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
                cmp #3
                beq .status
                cmp #2
                bcs .msgin
                lda xmode               ; data in or out
                beq .bycpu
                cmp #1
                bne .bypseudo
                jmp .bydma
.bypseudo:        jmp .pdma
.bycpu:           lda phase
                beq .dataout
                bra .datain
.msgin:         lda sc_data
                bra .ackin
.msgout:        lda #$80
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
.ack:           sta sc_icr
.unreq:         lda sc_bus
                and #$20
                bne .unreq
                stz sc_icr
                jmp .phase

; by DMA: until channel 0 is DONE or the chip interrupts (EOP, or the
; target in another phase)
.bydma:           lda #$0A                ; DMA mode, EOP interrupt
                sta sc_mode
                lda phase
                beq .send
                sta sc_rpi              ; start DMA initiator receive
                bra .dwait
.send:          sta sc_bsr              ; start DMA send
.dwait:         lda dma0+9
                lsr a
                bcs .dend
                lda sc_bsr
                and #$10
                beq .dwait
.dend:          lda sc_bsr
                sta dbsr
                lda sc_tcr
                sta dtcr
                stz dma0+8              ; stop the channel
                stz sc_mode             ; DMA off
                lda sc_rpi              ; and its interrupt
                jmp .phase

; pseudo-DMA: the CPU at $0840 while the chip asks, until it interrupts
.pdma:          lda #$02                ; DMA mode
                sta sc_mode
                sta sc_rpi              ; start DMA initiator receive
                ldx cnt
.pw:            lda sc_bsr
                bit #$10
                bne .pend
                and #$40                ; DMA request
                beq .pw
                lda sc_dack
                sta inbuf,x
                inx
                bra .pw
.pend:          stx cnt
                lda sc_bsr
                sta dbsr
                stz sc_mode
                lda sc_rpi
                jmp .phase

.free:          ldx #s_status
                jsr puts
                lda status
                jsr hex
                lda xmode
                beq .done
                ldx #s_bsr
                jsr puts
                lda dbsr
                jsr hex
                lda dtcr
                jsr hex
                lda xmode
                cmp #1
                bne .pcount
                jsr dma0show
                bra .done
.pcount:        rep #$20
                lda cnt
                sep #$20
                xba
                jsr hex
                xba
                jsr hex
.done:          rts

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

show2:          lda 0,x
                jsr hex
                lda 1,x
                jsr hex
                rts

show1:          lda 0,x
                jmp hex

crlf:           lda #13
                jsr putc
                lda #10
                jmp putc

; --- data -----------------------------------------------------------------

rd_cmd:         data.b $00, 5, 0, 3, 2, 4, $1B, $FF
rd_one:         data.b $00, 5, 0, 3, 2, 3, $1B, $FF
rd_r5:          data.b $00, 5, 0, 5, 2, 5, $1B, $FF
wr_cmd:         data.b $04, 5, 1, 1, 2, 1, $1B, $FF

c_sense:        data.b 6, $03, 0, 0, 0, 18, 0
c_read10:       data.b 10, $28, 0, 0, 0, 0, 100, 0, 0, 2, 0
c_write6:       data.b 6, $0A, 0, 0, 7, 1, 0
c_read6:        data.b 6, $08, 0, 0, 7, 1, 0
c_read9:        data.b 10, $28, 0, 0, 0, 0, 9, 0, 0, 1, 0

s_fread:        text.0 "floppy read C5 H0 R3-4 by DMA: "
s_fwrite:       text.0 "floppy write C5 H1 R1 by DMA: "
s_overrun:      text.0 "floppy read, no DMA: "
s_fpseudo:      text.0 "floppy read C5 H0 R5 at $0810: "
s_sense:        text.0 "request sense: "
s_sread:        text.0 "read(10) 100-101 by DMA: "
s_swrite:       text.0 "write(6) 7 by DMA: "
s_sshort:       text.0 "read(10) 9, 600 asked: "
s_spseudo:      text.0 "read(6) 7 at $0840: "
s_status:       text.0 "status "
s_bsr:          text.0 "bsr tcr "
s_dma:          text.0 "dma "

                fill $FFFC-pc, $FF
                data.w reset, reset
