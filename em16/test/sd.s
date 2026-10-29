; sd.s - a boot ROM for em16 -fpga -sd that drives the microSD slot (EmSD,
; rtl/sd_spi.v) as a block driver would: the card's start-up at the slow
; clock (CMD0 with a bad CRC, then a good one, CMD8, CMD55 and ACMD41 until
; ready, CMD58), then at DIVIDER 0 the CSD, a block read with NEXT, a block
; written and read back, two blocks with CMD18 and CMD12, two written with
; CMD25, and the second read back. It prints what it got, a line a step;
; test/sd.sh checks it against a model of its own. A last line, "t17", is
; the cycles a block read takes, from CMD17 to the CRC (the tick timer at
; one tick a cycle).

                cpu = "65C816"
                org = $E000

sd_data         = $02C0
sd_next         = $02C1
sd_ctl          = $02C2
sd_div          = $02C3
tmr_reload      = $0450
tmr_ctrl        = $0452
tmr_ticks       = $0458
scc_ctl         = $0822
scc_data        = $0823

cmd             = $80           ; the command: index, argument (big-endian), CRC
seed            = $86           ; a block's pattern: byte i is seed * (i + 1)
sum             = $88           ; a block's checksum, 16 bits
t0              = $8A           ; the tick count at the start, 16 bits
tries           = $8C
crc             = $8E           ; a block's CRC, as it came
buf             = $2000         ; a block

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
                lda #1                  ; the timer: a tick a cycle
                sta tmr_reload
                stz tmr_reload+1
                sta tmr_ctrl

                ldx #0                  ; 80 clocks deselected
.wake:          lda #$FF
                jsr xfer
                inx
                cpx #10
                bne .wake
                lda #1
                sta sd_ctl              ; select

                lda #0                  ; CMD0, a bad CRC: $09
                ldx #0
                ldy #$00
                jsr command
                jsr hex
                lda #0                  ; CMD0: $01
                ldx #0
                ldy #$95
                jsr command
                jsr hex
                lda #8                  ; CMD8, $1AA: $01 00 00 01 AA
                ldx #$01AA
                ldy #$87
                jsr command
                jsr hex
                ldx #4
                jsr bytes
                jsr crlf

                stz tries               ; ACMD41 until ready
.acmd:          inc tries
                lda #55
                ldx #0
                ldy #$01
                jsr command
                lda #41
                ldx #0
                ldy #$01
                jsr command
                bne .acmd
                lda tries
                jsr hex
                lda #58                 ; CMD58: R1 and the OCR
                ldx #0
                ldy #$01
                jsr command
                jsr hex
                ldx #4
                jsr bytes
                jsr crlf

                stz sd_div              ; 12.6 MHz from here
                lda #9                  ; the CSD
                ldx #0
                ldy #$01
                jsr command
                jsr hex
                jsr token
                ldx #16
                jsr nexts
                jsr crlf

                rep #$20                ; a block read, timed
                longa = on
                lda tmr_ticks
                sta t0
                sep #$20
                longa = off
                lda #17
                ldx #1
                ldy #$01
                jsr command
                pha
                jsr rdraw
                rep #$20
                longa = on
                lda tmr_ticks
                sec
                sbc t0
                sta t0
                sep #$20
                longa = off
                pla
                jsr hex
                jsr prblk
                jsr crlf

                lda #24                 ; write block 2, read it back
                ldx #2
                ldy #$01
                jsr command
                jsr hex
                lda #$FE
                ldx #5
                jsr writeblk
                jsr crlf
                lda #17
                ldx #2
                ldy #$01
                jsr command
                jsr hex
                jsr readblk
                jsr crlf

                lda #18                 ; blocks 3 and 4, then CMD12
                ldx #3
                ldy #$01
                jsr command
                jsr hex
                jsr readblk
                jsr readblk
                lda #12
                ldx #0
                ldy #$01
                jsr command
                jsr hex
                jsr unbusy
                jsr crlf

                lda #25                 ; write blocks 6 and 7
                ldx #6
                ldy #$01
                jsr command
                jsr hex
                lda #$FC
                ldx #3
                jsr writeblk
                lda #$FC
                ldx #11
                jsr writeblk
                lda #$FD                ; stop tran
                jsr xfer
                lda #$FF
                jsr xfer
                jsr unbusy
                lda #17                 ; and block 7 back
                ldx #7
                ldy #$01
                jsr command
                jsr hex
                jsr readblk
                jsr crlf

                stz sd_ctl              ; deselect
                ldx #s_t17
                jsr puts
                lda t0+1
                jsr hex
                lda t0
                jsr hex
                jsr crlf
                ldx #s_done
                jsr puts
                stp

; A out, A back: an exchange (DATA waits for it).
xfer:           sta sd_data
                lda sd_data
                rts

; Command A, argument X (16 bits; the high 16 are 0), CRC Y. Returns R1 in
; A, the first byte that is not $FF, with the flags set from it.
command:        ora #$40
                sta cmd
                stz cmd+1
                stz cmd+2
                rep #$20
                longa = on
                txa
                xba
                sta cmd+3
                sep #$20
                longa = off
                tya
                sta cmd+5
                lda #$FF
                jsr xfer
                ldx #0
.out:           lda cmd,x
                jsr xfer
                inx
                cpx #6
                bne .out
                ldx #10
.r1:            lda #$FF
                jsr xfer
                cmp #$FF
                bne .got
                dex
                bne .r1
.got:           cmp #0
                rts

; Wait for a data token, with NEXT.
token:          lda sd_next
                cmp #$FE
                bne token
                rts

; X bytes with DATA, printed.
bytes:          lda #$FF
                jsr xfer
                jsr hex
                dex
                bne bytes
                rts

; X bytes with NEXT, printed.
nexts:          lda sd_next
                jsr hex
                dex
                bne nexts
                rts

; A block into buf with NEXT, after its token, and its CRC into crc; then
; prints a space, its first four bytes, its checksum and its CRC.
readblk:        jsr rdraw
                ; fall through

prblk:          lda #' '
                jsr putc
                ldx #0
.first:         lda buf,x
                jsr hex
                inx
                cpx #4
                bne .first
                jsr checksum
                lda crc
                jsr hex
                lda crc+1
                jsr hex
                rts

rdraw:          jsr token
                ldx #0
.rd:            lda sd_next
                sta buf,x
                inx
                cpx #512
                bne .rd
                lda sd_next             ; the CRC, high byte first
                sta crc
                lda sd_next
                sta crc+1
                rts

; Sum of buf's bytes, printed after a space.
checksum:       rep #$20
                longa = on
                stz sum
                ldx #0
.sum:           lda buf,x
                and #$00FF
                clc
                adc sum
                sta sum
                inx
                cpx #512
                bne .sum
                sep #$20
                longa = off
                lda #' '
                jsr putc
                lda sum+1
                jsr hex
                lda sum
                jsr hex
                lda #' '
                jsr putc
                rts

; Write a block after token A, byte i X * (i + 1); prints the data
; response, after a space, and waits out the busy bytes.
writeblk:       pha
                stx seed
                lda #$FF
                jsr xfer
                pla
                jsr xfer
                ldx #0
                lda seed
.wr:            pha
                jsr xfer
                pla
                clc
                adc seed
                inx
                cpx #512
                bne .wr
                lda #0                  ; the CRC, not checked
                jsr xfer
                lda #0
                jsr xfer
                lda #' '
                jsr putc
                lda #$FF
                jsr xfer
                and #$1F
                jsr hex
                ; fall through

; Exchange $FF until the card is no longer busy.
unbusy:         lda #$FF
                jsr xfer
                cmp #$FF
                bne unbusy
                rts

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

s_t17:          text.0 "t17 "
s_done:         text.0 "sd: done", 13, 10

                fill $FFFC-pc, $FF
                data.w reset, reset
