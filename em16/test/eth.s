; eth.s - a boot ROM for em16 -fpga -net udp:... that drives the
; ENC424J600 (EmEth, the external bus's slot 5 at $0850) as a driver
; would, with test/eth.sh's peer at the other end of the cable:
;   1. EUDAST written $1234 and read back, CLKRDY, ETHRST, EUDAST 0 again
;   2. EIDLED and the MAC address (-mac), the link up, PHSTAT3 through MII
;   3. a broadcast frame sent (padded to 60, the CRC added): ETXWIRE,
;      ETXSTAT
;   4. the peer's three frames: to us, to another address (filtered), and
;      broadcast; PKTCNT, the cards' IRQ# in $0440, each frame's next
;      pointer, status vector and text
;   5. the hash table's bit for 01:00:00:00:01:2C set and HTEN: of the
;      peer's two multicasts only that one comes in
;   6. the DMA: the checksum of 89 AB CD (A953), and a copy read back
;   7. the SoC's DMA channel 2 ($0420): 8 bytes into EGPDATA and back out,
;      ISTAT bit 6 at DONE
; It prints "eth: " lines, which test/eth.sh compares.

                cpu = "65C816"
                org = $E000

istat           = $0440
scc_ctl         = $0822
scc_data        = $0823
eth_al          = $0850         ; the address latch, 7E00h + byte
eth_ah          = $0852         ; the address latch, 7F00h + byte (Set, Clear)
eth_d           = $0851         ; the data at the latched address
dma2_addr       = $0420         ; the SoC's DMA channel 2
dma2_cnt        = $0424
dma2_ctrl       = $0428
dma2_stat       = $0429

tmpw            = $10           ; a word read or written
next            = $12           ; the next packet's address in the ring
len             = $14
cnt             = $16
hdr             = $20           ; a received record's 8 bytes

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

; --- 1. the interface, and a reset ---------------------------------------------

                lda #$16                ; EUDAST
                ldx #$1234
                jsr wreg
                lda #$16
                jsr rreg
                cpx #$1234
                bne bad1
.clk:           lda #$1A                ; ESTAT: CLKRDY
                jsr rreg
                rep #$20
                longa = on
                txa
                and #$1000
                sep #$20
                longa = off
                beq .clk
                lda #$6E                ; ECON2SET: ETHRST
                sta eth_ah
                lda #$10
                sta eth_d
                lda #$16
                jsr rreg
                cpx #0
                beq t2
bad1:           lda #1
                jmp fail

; --- 2. who it is, and the link ----------------------------------------------

t2:             ldx #s_id
                jsr puts
                lda #$74                ; EIDLEDL: DEVID, REVID
                sta eth_al
                lda eth_d
                jsr hex
                ldx #s_mac
                jsr puts
                lda #$64                ; MAADR1L, 1H, 2L, 2H, 3L, 3H
                jsr hexreg
                lda #$65
                jsr hexreg
                lda #$62
                jsr hexreg
                lda #$63
                jsr hexreg
                lda #$60
                jsr hexreg
                lda #$61
                jsr hexreg
                jsr crlf
                ldy #0
.link:          dey
                beq bad2
                lda #$1A                ; ESTAT: PHYLNK
                jsr rreg
                rep #$20
                longa = on
                txa
                and #$0100
                sep #$20
                longa = off
                beq .link
                ldx #s_estat
                jsr puts
                lda #$1A
                jsr rreg
                jsr hex16
                ldx #s_phy
                jsr puts
                lda #$54                ; MIREGADR: PHSTAT3
                ldx #$011F
                jsr wreg
                lda #$52                ; MICMD: MIIRD
                ldx #1
                jsr wreg
.busy:          lda #$6A                ; MISTAT: BUSY
                sta eth_al
                lda eth_d
                and #1
                bne .busy
                lda #$68                ; MIRD
                jsr rreg
                jsr hex16
                jsr crlf
                lda #$52
                ldx #0
                jsr wreg
                bra t3
bad2:           lda #2
                jmp fail

; --- 3. a frame sent ---------------------------------------------------------

t3:             lda #$04                ; ERXST: the ring from 4000h
                ldx #$4000
                jsr wreg
                lda #$06                ; ERXTAIL
                ldx #$5FFE
                jsr wreg
                ldx #$4000
                stx next
                lda #$72                ; EIE: INTIE, PKTIE
                ldx #$8040
                jsr wreg
                lda #$1E                ; ECON1SET: RXEN
                sta eth_ah
                lda #$01
                sta eth_d
                jsr send
                ldx #s_tx
                jsr puts
                lda #$14                ; ETXWIRE
                jsr rreg
                jsr hex16
                lda #' '
                jsr putc
                lda #$12                ; ETXSTAT
                jsr rreg
                jsr hex16
                jsr crlf

; --- 4. three frames back, two let in -------------------------------------------

                lda #2
                jsr waitpkt
                ldx #s_cnt
                jsr puts
                lda #$1A                ; ESTAT: PKTCNT, INT
                jsr rreg
                jsr hex16
                lda #' '
                jsr putc
                lda istat               ; the cards' IRQ#
                and #$08
                jsr hex
                jsr crlf
                jsr rxone
                jsr rxone
                ldx #s_cnt
                jsr puts
                lda #$1A
                jsr rreg
                jsr hex16
                lda #' '
                jsr putc
                lda istat
                and #$08
                jsr hex
                jsr crlf

; --- 5. the hash table ---------------------------------------------------------

                lda #$26                ; EHT4: bit 34h
                ldx #$0010
                jsr wreg
                lda #$34                ; ERXFCON: HTEN and the default
                ldx #$8059
                jsr wreg
                jsr send                ; the peer's cue
                lda #1
                jsr waitpkt
                ldx #0                  ; time for the other to come
.wait:          ldy #10
.pause:         dey
                bne .pause
                dex
                bne .wait
                jsr rxone
                ldx #s_cnt
                jsr puts
                lda #$1A
                jsr rreg
                jsr hex16
                jsr crlf

; --- 6. the DMA ------------------------------------------------------------------

                lda #$88                ; EGPWRPT
                ldx #$0100
                jsr wreg
                lda #$80                ; EGPDATA
                sta eth_al
                lda #$89
                sta eth_d
                lda #$AB
                sta eth_d
                lda #$CD
                sta eth_d
                lda #$0A                ; EDMAST
                ldx #$0100
                jsr wreg
                lda #$0C                ; EDMALEN
                ldx #3
                jsr wreg
                lda #$0E                ; EDMADST
                ldx #$0200
                jsr wreg
                lda #$9E                ; ECON1CLR: DMACPY, DMACSSD, DMANOCS
                sta eth_ah
                lda #$1C
                sta eth_d
                jsr dma
                ldx #s_cs
                jsr puts
                lda #$10                ; EDMACS
                jsr rreg
                jsr hex16
                lda #$1E                ; ECON1SET: DMACPY, DMANOCS
                sta eth_ah
                lda #$14
                sta eth_d
                jsr dma
                ldx #s_copy
                jsr puts
                lda #$86                ; EGPRDPT
                ldx #$0200
                jsr wreg
                lda #$80
                sta eth_al
                lda eth_d
                jsr hex
                lda eth_d
                jsr hex
                lda eth_d
                jsr hex
                jsr crlf
; --- 7. the SoC's DMA channel 2: memory to EGPDATA and back ----------------

                ldx #0
.fill:          txa
                inc a
                sta $2000,x             ; 01 02 ... 08
                inx
                cpx #8
                bne .fill
                lda #$88                ; EGPWRPT
                ldx #$0400
                jsr wreg
                lda #$80                ; the window latched: EGPDATA
                sta eth_al
                ldx #$2000
                lda #$0B                ; IE, memory to device, EN
                jsr dma2
                ldx #s_dma2
                jsr puts
                lda istat               ; DONE with IE: bit 6
                and #$40
                jsr hex
                lda #1
                sta dma2_stat
                lda #$86                ; EGPRDPT
                ldx #$0400
                jsr wreg
                lda #$80
                sta eth_al
                ldx #$2100
                lda #$09                ; IE, device to memory, EN
                jsr dma2
                lda #1
                sta dma2_stat
                lda #' '
                jsr putc
                ldx #0
.show:          lda $2100,x
                phx
                jsr hex
                plx
                inx
                cpx #8
                bne .show
                jsr crlf
                ldx #s_done
                jsr puts
                stp

; channel 2: 8 bytes from or to X (bank 0), CTRL A; until DONE
dma2:           pha
                stx dma2_addr
                stz dma2_addr+2
                lda #8
                sta dma2_cnt
                stz dma2_cnt+1
                stz dma2_cnt+2
                pla
                sta dma2_ctrl
.wait:          lda dma2_stat
                and #1
                beq .wait
                rts

; A holds the number of the check that failed
fail:           pha
                ldx #s_fail
                jsr puts
                pla
                jsr hex
                jsr crlf
                stp

; --- the chip ----------------------------------------------------------------

; the word X to the register at 7E00h + A
wreg:           sta eth_al
                pha
                stx tmpw
                lda tmpw
                sta eth_d
                pla
                inc a
                sta eth_al
                lda tmpw+1
                sta eth_d
                rts

; the word at 7E00h + A, in X
rreg:           sta eth_al
                pha
                lda eth_d
                sta tmpw
                pla
                inc a
                sta eth_al
                lda eth_d
                sta tmpw+1
                ldx tmpw
                rts

; the byte at 7E00h + A, printed
hexreg:         sta eth_al
                lda eth_d
                jmp hex

; the frame of tx_frame sent from 0000h, until TXIF
send:           lda #$88                ; EGPWRPT
                ldx #0
                jsr wreg
                lda #$80
                sta eth_al
                ldx #0
.copy:          lda tx_frame,x
                sta eth_d
                inx
                cpx #tx_end-tx_frame
                bne .copy
                lda #$00                ; ETXST
                ldx #0
                jsr wreg
                lda #$02                ; ETXLEN
                ldx #tx_end-tx_frame
                jsr wreg
                lda #$1E                ; ECON1SET: TXRTS
                sta eth_ah
                lda #$02
                sta eth_d
                ldy #0
.wait:          dey
                beq .late
                lda #$1C                ; EIR: TXIF
                sta eth_al
                lda eth_d
                and #$08
                beq .wait
                lda #$9C                ; EIRCLR: TXIF
                sta eth_ah
                lda #$08
                sta eth_d
                rts
.late:          lda #3
                jmp fail

; the DMA started, until DMAIF
dma:            lda #$1E                ; ECON1SET: DMAST
                sta eth_ah
                lda #$20
                sta eth_d
.wait:          lda #$1C
                sta eth_al
                lda eth_d
                and #$20
                beq .wait
                lda #$9C                ; EIRCLR: DMAIF
                sta eth_ah
                lda #$20
                sta eth_d
                rts

; until PKTCNT is A or more
waitpkt:        sta cnt
                ldx #0
.wait:          dex
                beq .late
                ldy #20
.pause:         dey
                bne .pause
                lda #$1A
                sta eth_al
                lda eth_d
                cmp cnt
                bcc .wait
                rts
.late:          lda #4
                jmp fail

; the frame at next read and printed: "eth: rx next len status: text"; the
; tail moved up to it and PKTDEC
rxone:          lda #$8A                ; ERXRDPT
                ldx next
                jsr wreg
                lda #$82                ; ERXDATA
                sta eth_al
                ldx #0
.hdr:           lda eth_d
                sta hdr,x
                inx
                cpx #8
                bne .hdr
                ldx #s_rx
                jsr puts
                ldx hdr
                stx next
                jsr hex16
                lda #' '
                jsr putc
                ldx hdr+2
                stx len
                jsr hex16
                lda #' '
                jsr putc
                lda hdr+4
                jsr hex
                lda hdr+5
                jsr hex
                lda hdr+6
                jsr hex
                lda hdr+7
                jsr hex
                lda #':'
                jsr putc
                lda #' '
                jsr putc
                ldx #0                  ; the header skipped, the text printed
.skip:          lda eth_d
                inx
                cpx #14
                bne .skip
.text:          lda eth_d
                beq .end
                jsr putc
                inx
                cpx len
                bne .text
.end:           jsr crlf
                rep #$20
                longa = on
                lda next
                cmp #$4000
                bne .back
                lda #$6000
.back:          sec
                sbc #2
                tax
                sep #$20
                longa = off
                lda #$06                ; ERXTAIL
                jsr wreg
                lda #$1F                ; ECON1SETH: PKTDEC
                sta eth_ah
                lda #$01
                sta eth_d
                rts

tx_frame:       data.b $FF, $FF, $FF, $FF, $FF, $FF
                data.b $02, $00, $00, $12, $34, $56
                data.b $88, $B5
                text.0 "hello from em16"
tx_end:

; --- the serial port -------------------------------------------------------------

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

crlf:           lda #13
                jsr putc
                lda #10
                jmp putc

hex16:          stx tmpw
                lda tmpw+1
                jsr hex
                lda tmpw
hex:            pha
                lsr a
                lsr a
                lsr a
                lsr a
                jsr .nib
                pla
.nib:           and #$0F
                cmp #10
                bcc .dig
                adc #6
.dig:           adc #$30
                jmp putc

s_id:           text.0 "eth: id "
s_mac:          text.0 " mac "
s_estat:        text.0 "eth: estat "
s_phy:          text.0 " phstat3 "
s_tx:           text.0 "eth: tx "
s_cnt:          text.0 "eth: pkts "
s_rx:           text.0 "eth: rx "
s_cs:           text.0 "eth: dma "
s_copy:         text.0 " copy "
s_dma2:         text.0 "eth: dma2 "
s_done:         text.0 "eth: done", 13, 10
s_fail:         text.0 "eth: fail "

                fill $FFFC-pc, $FF
                data.w reset, reset
