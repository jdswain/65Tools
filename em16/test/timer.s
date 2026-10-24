; timer.s - a boot ROM for em16 -fpga that checks the tick timer
; (EmTimer, $0450) and the interrupt status and mask ($0440, $0441), as
; fpga/rom/timertest.asm of the Verilog repository does on the RTL:
;   1. ISTAT reads 0 and IMASK $FF after reset.
;   2. A 1000-cycle period, polled: PENDING and ISTAT bit 0 at the tick,
;      both clear after writing 1 to STATUS; NOW and TICKS, latched
;      together, agree with a second snapshot taken a known time later.
;   3. On IRQ: the handler counts ticks and clears PENDING; after 10 of
;      them TICKS is 11 to 15.
;   4. IMASK bit 0 clear: the tick is pending (ISTAT shows it) but no IRQ;
;      setting the bit takes the IRQ at once.
;   5. DMA channel 1 started with COUNT = 0 and IE: DONE at once, ISTAT
;      bit 2 only, gone after DONE is cleared.
;   6. EN = 0 stops TICKS and NOW.
; It prints "timer: ok", or "timer: fail" and the number of the check.
; test/timer.sh runs it.

                cpu = "65C816"
                org = $E000

istat           = $0440         ; 0 timer, 1 DMA 0, 2 DMA 1, 3 cards, 4 SCC
imask           = $0441
tmr_reload      = $0450
tmr_ctrl        = $0452         ; bit 0 EN
tmr_stat        = $0453         ; bit 0 PENDING (write 1 to clear)
tmr_now         = $0454
tmr_ticks       = $0458         ; reading the low byte latches the rest
dma1_ctrl       = $0418
dma1_stat       = $0419
scc_ctl         = $0822
scc_data        = $0823

count           = $10           ; ticks the IRQ handler has seen
snap            = $12           ; a snapshot's time

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
                ldx #s_hello
                jsr puts

; --- 1. after reset ---------------------------------------------------------

                lda istat
                bne bad1
                lda imask
                cmp #$FF
                beq t2
bad1:           lda #1
                jmp fail

; --- 2. polled ----------------------------------------------------------------

t2:             lda #<1000
                sta tmr_reload
                lda #>1000
                sta tmr_reload+1
                lda #1
                sta tmr_ctrl
                jsr waitset
                lda istat
                cmp #$01
                bne bad2
                lda #1
                sta tmr_stat
                lda tmr_stat
                ora istat
                bne bad2
                jsr snapshot
                ldx tmp
                stx snap
                ldx #50                 ; a wait of some hundreds of cycles
.wait:          dex
                bne .wait
                jsr snapshot
                rep #$20
                longa = on
                lda tmp
                sec
                sbc snap
                cmp #200
                bcc .bad
                cmp #2000
.bad:           sep #$20
                longa = off
                bcc t3
bad2:           lda #2
                jmp fail

; --- 3. on IRQ ------------------------------------------------------------------

t3:             stz count
                cli
                ldy #0
.wait:          lda count
                cmp #10
                bcs .done
                dey
                bne .wait
                sei
                bra bad3
.done:          sei
                lda tmr_ticks
                cmp #11
                bcc bad3
                cmp #16
                bcs bad3
                lda tmr_ticks+1
                ora tmr_ticks+2
                ora tmr_ticks+3
                beq t4
bad3:           lda #3
                jmp fail

; --- 4. masked ------------------------------------------------------------------

t4:             lda #$FE
                sta imask
                lda #1
                sta tmr_stat
                stz count
                cli
                jsr waitpend
                jsr waitset             ; a whole period, then left pending
                lda count
                bne bad4
                lda istat
                cmp #$01
                bne bad4
                lda #$FF
                sta imask               ; the IRQ now
                nop
                nop
                sei
                lda count
                cmp #1
                beq t5
bad4:           lda #4
                jmp fail

; --- 5. DMA channel 1 done ---------------------------------------------------

t5:             lda #1
                sta tmr_stat
                sta dma1_stat
                lda #$09                ; IE, EN; COUNT is 0 from reset
                sta dma1_ctrl
                lda istat
                cmp #$04
                bne bad5
                lda #1
                sta dma1_stat
                lda istat
                beq t6
bad5:           lda #5
                jmp fail

; --- 6. stopped -------------------------------------------------------------------

t6:             stz tmr_ctrl
                jsr snapshot
                ldx tmp
                stx snap
                ldx #2000
.wait:          dex
                bne .wait
                jsr snapshot
                ldx tmp
                cpx snap
                bne bad6
                lda tmr_stat
                beq ok
bad6:           lda #6
                jmp fail

ok:             ldx #s_ok
                jsr puts
                stp

; A holds the number of the check that failed
fail:           pha
                ldx #s_fail
                jsr puts
                pla
                jsr hex
                lda #13
                jsr putc
                lda #10
                jsr putc
                stp

; the time since the first period began, modulo 65536, from TICKS and NOW
; latched together: TICKS*1000 + 999 - NOW, in tmp (16 bits)
tmp             = $16
snapshot:       lda tmr_ticks           ; latches TICKS and NOW
                sta tmp
                stz tmp+1
                rep #$20
                longa = on
                lda tmp                 ; TICKS low * 1000 = *1024 - *16 - *8
                asl a
                asl a
                asl a
                sta tmp+2               ; *8
                asl a
                clc
                adc tmp+2               ; *24
                sta tmp+2
                lda tmp
                xba                     ; *256
                and #$FF00
                asl a
                asl a                   ; *1024
                sec
                sbc tmp+2               ; *1000
                clc
                adc #999
                sec
                sbc tmr_now
                sta tmp
                sep #$20
                longa = off
                rts

; until PENDING, and clear it, so the next call waits a whole period
waitpend:       jsr waitset
                lda #1
                sta tmr_stat
                rts

; until PENDING, leaving it set; check 7 if it never comes
waitset:        ldy #0
.wait:          lda tmr_stat
                and #1
                bne .done
                dey
                bne .wait
                pla
                pla
                lda #7
                jmp fail
.done:          rts

; the IRQ handler, native mode: count a tick and clear it
irq:            pha
                lda tmr_stat
                and #1
                beq .done
                sta tmr_stat
                inc count
.done:          pla
                rti

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

s_hello:        text.0 "timer test", 13, 10
s_ok:           text.0 "timer: ok", 13, 10
s_fail:         text.0 "timer: fail "

                fill $FFEE-pc, $FF
                data.w irq
                fill $FFFC-pc, $FF
                data.w reset, reset
