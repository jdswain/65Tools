; hd.s - a boot ROM for em16 -fpga -scsitiming: a 20 MB SCSI disk in a
; real drive's time. From power on it waits for the drive to answer a
; selection and to spin up, then times reads and a write by the tick timer
; (100 us ticks): a block under the heads, blocks already in the read-ahead
; buffer, seeks across the disk, 64 blocks in one command, a write that ends
; on the platters, and long seeks. It works the 53C80 by polling, as
; test/disks.s does. test/hd.sh runs it on an image whose blocks hold their
; own numbers, checks the times against the drive's, and prints them.
;
; Each timed line: what, the status, the block number read (the first and,
; of 64, the last block's), and the time in ticks (hex). The power on lines
; give the time from power on.

                cpu = "65C816"
                org = $E000

sc_data         = $0830         ; 53C80: current data / output data
sc_icr          = $0831
sc_mode         = $0832
sc_tcr          = $0833
sc_bus          = $0834         ; current bus status
scc_ctl         = $0822
scc_data        = $0823
tmr_reload      = $0450
tmr_ctrl        = $0452         ; bit 0 EN
tmr_ticks       = $0458         ; reading the low byte latches the rest

cnt             = $10           ; bytes moved in
status          = $12
cdbi            = $14
outi            = $16
t0              = $18           ; ticks at the start
dt              = $1A           ; ticks taken
tnow            = $1C           ; ticks
cdb             = $20           ; 12 bytes, to $2B
nr              = $30           ; not ready replies
ti              = $32           ; the timed table's index
key             = $34           ; the last sense: key, code, qualifier
asc             = $35
ascq            = $36
multi           = $37           ; the line reads 64 blocks
outbuf          = $2000
inbuf           = $3000         ; 32K, to $AFFF

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
                lda #<2520              ; a tick every 100 us (25.2 MHz counts)
                sta tmr_reload
                lda #>2520
                sta tmr_reload+1
                lda #1
                sta tmr_ctrl
                ldx #s_hello
                jsr puts

; --- power on: the drive answers, and spins up ----------------------------

                ldx #s_first            ; the first command waits for the selection
                jsr puts
                ldx #c_tur
                jsr cmd
                jsr pstatus
                ldx #s_at
                jsr puts
                jsr ticks
                ldx tnow
                jsr hex16
                jsr crlf
                ldx #s_sense            ; UNIT ATTENTION
                jsr puts
                jsr sense
                jsr psense
                jsr crlf

                ldx #0
                stx nr
.spin:          ldx #c_tur
                jsr cmd
                lda status
                beq .ready
                jsr sense
                ldx nr
                inx
                stx nr
                bra .spin
.ready:         ldx #s_spin
                jsr puts
                ldx nr
                jsr hex16
                ldx #s_nr
                jsr puts
                jsr psense
                ldx #s_at
                jsr puts
                jsr ticks
                ldx tnow
                jsr hex16
                jsr crlf

                ldx #s_inquiry
                jsr puts
                ldx #c_inquiry
                jsr cmd
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
                jsr cmd
                ldx #0
.cap:           lda inbuf,x
                jsr hex
                inx
                cpx #8
                bne .cap
                jsr crlf

; --- the timed commands ----------------------------------------------------

                ldx #0                  ; the block to write: $A5
                lda #$A5
.fill:          sta outbuf,x
                inx
                cpx #512
                bne .fill

                ldx #0
                stx ti
.next:          ldy ti
                ldx timed,y             ; the line's name
                beq .done
                lda timed+4,y
                sta multi
                jsr puts
                jsr ticks
                rep #$20
                lda tnow
                sta t0
                sep #$20
                ldy ti
                ldx timed+2,y           ; its command
                jsr cmd
                jsr ticks
                rep #$20
                lda tnow
                sec
                sbc t0
                sta dt
                sep #$20
                jsr pstatus
                lda inbuf               ; the first block's number
                jsr hex
                lda inbuf+1
                jsr hex
                lda multi               ; and the last's, of 64
                beq .one
                lda inbuf+$7E00
                jsr hex
                lda inbuf+$7E01
                jsr hex
.one:           ldx #s_took
                jsr puts
                ldx dt
                jsr hex16
                jsr crlf
                rep #$20
                longa = on
                lda ti
                clc
                adc #5
                sta ti
                sep #$20
                longa = off
                bra .next
.done:          ldx #s_done
                jsr puts
                stp

; --- routines --------------------------------------------------------------

; tnow := the tick count, its low 16 bits
ticks:          lda tmr_ticks           ; latches the rest
                sta tnow
                lda tmr_ticks+1
                sta tnow+1
                rts

; REQUEST SENSE into key, asc, ascq
sense:          ldx #c_sense
                jsr cmd
                lda inbuf+2
                and #$0F
                sta key
                lda inbuf+12
                sta asc
                lda inbuf+13
                sta ascq
                rts

psense:         lda key
                jsr hex
                lda asc
                jsr hex
                lda ascq
                jmp hex

pstatus:        ldx #s_status
                jsr puts
                lda status
                jmp hex

; Run the command whose length and bytes are at X: arbitrate, select ID 0
; with ATN (waiting for it to answer), IDENTIFY, then the phases the target
; asks for until it frees the bus. Data in to inbuf, data out from outbuf;
; the status in status.
cmd:            lda 0,x
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
.free:          rts

; --- output ----------------------------------------------------------------

putc:           pha
.wt:            lda scc_ctl
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

; A as two hex digits and a space
hex:            pha
                jsr hex2
                lda #$20
                jsr putc
                pla
                rts

; A as two hex digits
hex2:           pha
                lsr a
                lsr a
                lsr a
                lsr a
                jsr nib
                pla
nib:            and #$0F
                cmp #10
                bcc .dig
                adc #6
.dig:           adc #$30
                jmp putc

; X as four hex digits
hex16:          rep #$20
                txa
                sep #$20
                xba
                jsr hex2
                xba
                jmp hex2

crlf:           lda #13
                jsr putc
                lda #10
                jmp putc

; --- data ------------------------------------------------------------------

; the timed lines: the name, the command, 1 if it reads 64 blocks
timed:          data.w s_r0, c_r0
                data.b 0
                data.w s_r1, c_r1
                data.b 0
                data.w s_r100, c_r100
                data.b 0
                data.w s_far, c_far
                data.b 0
                data.w s_seq, c_seq
                data.b 1
                data.w s_write, c_write
                data.b 0
                data.w s_back, c_back
                data.b 0
                data.w s_home, c_r0
                data.b 0
                data.w s_last, c_last
                data.b 0
                data.w 0

c_tur:          data.b 6, $00, 0, 0, 0, 0, 0
c_sense:        data.b 6, $03, 0, 0, 0, 18, 0
c_inquiry:      data.b 6, $12, 0, 0, 0, 36, 0
c_capacity:     data.b 10, $25, 0, 0, 0, 0, 0, 0, 0, 0, 0
c_r0:           data.b 10, $28, 0, 0, 0, $00, $00, 0, 0, 1, 0      ; block 0
c_r1:           data.b 10, $28, 0, 0, 0, $00, $01, 0, 0, 1, 0      ; 1: in the buffer
c_r100:         data.b 10, $28, 0, 0, 0, $00, $64, 0, 0, 1, 0      ; 100: read ahead
c_far:          data.b 10, $28, 0, 0, 0, $4E, $20, 0, 0, 1, 0      ; 20000, cylinder 156
c_seq:          data.b 10, $28, 0, 0, 0, $4E, $21, 0, 0, 64, 0     ; 20001-20064
c_write:        data.b 10, $2A, 0, 0, 0, $9C, $40, 0, 0, 1, 0      ; 40000, cylinder 312
c_back:         data.b 10, $28, 0, 0, 0, $9C, $40, 0, 0, 1, 0
c_last:         data.b 10, $28, 0, 0, 0, $9F, $FF, 0, 0, 1, 0      ; 40959, cylinder 319

s_hello:        text.0 "hd: a 20 MB drive in its time", 13, 10
s_first:        text.0 "first answer: "
s_at:           text.0 "at "
s_sense:        text.0 "sense: "
s_spin:         text.0 "spin-up: "
s_nr:           text.0 " not ready, sense "
s_inquiry:      text.0 "inquiry: "
s_capacity:     text.0 "capacity: "
s_status:       text.0 "status "
s_took:         text.0 "took "
s_r0:           text.0 "read 0: "
s_r1:           text.0 "read 1: "
s_r100:         text.0 "read 100: "
s_far:          text.0 "read 20000: "
s_seq:          text.0 "read 20001 x64: "
s_write:        text.0 "write 40000: "
s_back:         text.0 "read 40000: "
s_home:         text.0 "read 0 again: "
s_last:         text.0 "read 40959: "
s_done:         text.0 "hd: done", 13, 10

                fill $FFFC-pc, $FF
                data.w reset, reset
