; mini816b.s - a boot ROM for em16 -mini816 with -sccb tcp:PORT: the
; SCC's channel B at 9600 baud echoes what it receives, a character
; at a time, until a "." (echoed too); then it prints "mini816b: done"
; on channel A and stops. test/mini816b.sh is the client at the other
; end of the socket.

                cpu = "65C816"
                org = $F000

scc_bctl        = $C010
scc_bdat        = $C011
scc_actl        = $C012
scc_adat        = $C013

reset:          clc
                xce
                sep #$20
                rep #$10
                longa = off
                longi = on
                ldx #$01FF
                txs
                ldx #init_a
                jsr regs_a
                ldx #init_b
                jsr regs_b
.loop:          lda scc_bctl            ; RR0 B: a character?
                and #$01
                beq .loop
                lda scc_bdat
                pha
.wt:            lda scc_bctl            ; Tx buffer empty?
                and #$04
                beq .wt
                pla
                sta scc_bdat
                cmp #'.'
                bne .loop
.sent:          lda #1                  ; RR1 B: all sent?
                sta scc_bctl
                lda scc_bctl
                and #$01
                beq .sent
                ldx #s_done
.puts:          lda 0,x
                beq .stop
                pha
.wa:            lda scc_actl
                and #$04
                beq .wa
                pla
                sta scc_adat
                inx
                bra .puts
.stop:          stp

regs_a:         lda 0,x
                cmp #$FF
                beq .done
                sta scc_actl
                inx
                bra regs_a
.done:          rts

regs_b:         lda 0,x
                cmp #$FF
                beq .done
                sta scc_bctl
                inx
                bra regs_b
.done:          rts

; 8N1 x16 from the BRG: TC 0 115200 baud (A), TC 22 9600 baud (B)
init_a:         data.b 9, $C0, 4, $44, 3, $C1, 5, $6A, 11, $50, 12, 0, 13, 0, 14, $03, $FF
init_b:         data.b 4, $44, 3, $C1, 5, $6A, 11, $50, 12, 22, 13, 0, 14, $03, $FF
s_done:         text.0 "mini816b: done", 13, 10

                fill $FFFC-pc, $FF
                data.w reset, reset
