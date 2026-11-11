; CPU self-test for the in-house NES core. Our own program.
; Each numbered test checks results and flags; the first failure stops the run.
; Result protocol: $6000 = $80 while running, $00 on pass, test number on fail;
; $6001-$6003 = $DE $B0 $61 once started. Also drawn on screen as PASS or FAIL nn.

test_num = $30
counter  = $31
zp_ptr   = $40     ; pointer scratch
MASK     = $C3     ; N V . . . . Z C

.org $8000
reset:
    sei
    cld
    ldx #$FF
    txs
    jsr init_system
    lda #$80
    sta $6000
    lda #$DE
    sta $6001
    lda #$B0
    sta $6002
    lda #$61
    sta $6003
    jmp run_tests

; Z flag set means OK.
ok:
    beq @fine
    jmp fail
@fine:
    rts

; Compare flags (masked) with A after PHP. Usage: php / pla / and #MASK / cmp #x / jsr ok
run_tests:
;---------------------------------------------------------------- 1 load flags
    lda #1
    sta test_num
    lda #0
    php
    pla
    and #MASK
    cmp #$02
    jsr ok
    clc
    lda #$80
    php
    pla
    and #MASK
    cmp #$80
    jsr ok
;---------------------------------------------------------------- 2 ADC overflow
    lda #2
    sta test_num
    clc
    lda #$50
    adc #$50
    php
    cmp #$A0
    jsr ok
    pla
    and #MASK
    cmp #$C0            ; N V, no carry
    jsr ok
    sec
    lda #$FF
    adc #$00
    php
    cmp #$00
    jsr ok
    pla
    and #MASK
    cmp #$03            ; Z C
    jsr ok
;---------------------------------------------------------------- 3 SBC
    lda #3
    sta test_num
    sec
    lda #$50
    sbc #$F0
    php
    cmp #$60
    jsr ok
    pla
    and #MASK
    cmp #$00
    jsr ok
    sec
    lda #$D0
    sbc #$70
    php
    cmp #$60
    jsr ok
    pla
    and #MASK
    cmp #$41            ; V C
    jsr ok
    clc                 ; borrow
    lda #$10
    sbc #$05
    cmp #$0A
    jsr ok
;---------------------------------------------------------------- 4 no decimal mode on the 2A03
    lda #4
    sta test_num
    sed
    clc
    lda #$09
    adc #$01
    cld
    cmp #$0A
    jsr ok
;---------------------------------------------------------------- 5 compares
    lda #5
    sta test_num
    lda #$40
    cmp #$40
    php
    pla
    and #MASK
    cmp #$03
    jsr ok
    ldx #$10
    cpx #$20
    php
    pla
    and #MASK
    cmp #$80            ; N, no carry
    jsr ok
    ldy #$20
    cpy #$10
    php
    pla
    and #MASK
    cmp #$01
    jsr ok
;---------------------------------------------------------------- 6 logic
    lda #6
    sta test_num
    lda #$F0
    and #$3C
    cmp #$30
    jsr ok
    lda #$F0
    ora #$0F
    cmp #$FF
    jsr ok
    lda #$FF
    eor #$0F
    cmp #$F0
    jsr ok
;---------------------------------------------------------------- 7 shifts and rotates
    lda #7
    sta test_num
    lda #$81
    asl a
    php
    cmp #$02
    jsr ok
    pla
    and #$01
    cmp #$01
    jsr ok
    lda #$01
    lsr a
    php
    cmp #$00
    jsr ok
    pla
    and #MASK
    cmp #$03
    jsr ok
    sec
    lda #$80
    rol a               ; -> $01, C=1
    cmp #$01
    jsr ok
    lda #$01
    ror a               ; C was 1 -> $80, C=1
    php
    cmp #$80
    jsr ok
    pla
    and #MASK
    cmp #$81
    jsr ok
    lda #$55
    sta $50
    asl $50
    lda $50
    cmp #$AA
    jsr ok
    lsr $50
    ror $50
    lda $50
    cmp #$2A
    jsr ok
    lda #$40
    sta $0350
    ldx #$10
    rol $0340,x
    lda $0350
    cmp #$81            ; carry from the previous ROR came in
    jsr ok
;---------------------------------------------------------------- 8 inc and dec wrap
    lda #8
    sta test_num
    lda #$FF
    sta $51
    clc
    inc $51
    php
    lda $51
    jsr ok_zero
    pla
    and #MASK
    cmp #$02
    jsr ok
    dec $51
    lda $51
    cmp #$FF
    jsr ok
    ldx #0
    dex
    cpx #$FF
    jsr ok
    ldy #$FF
    iny
    cpy #0
    jsr ok
;---------------------------------------------------------------- 9 transfers and stack pointer
    lda #9
    sta test_num
    lda #$42
    tax
    tay
    cpx #$42
    jsr ok
    cpy #$42
    jsr ok
    tsx
    stx counter
    ldx #$80
    txs
    tsx
    cpx #$80
    jsr ok
    ldx counter
    txs
    lda #0
    ldx #$99
    txa
    cmp #$99
    jsr ok
    ldy #$77
    tya
    cmp #$77
    jsr ok
;---------------------------------------------------------------- 10 push and pull
    lda #10
    sta test_num
    lda #$12
    pha
    lda #$34
    pha
    lda #0
    pla
    cmp #$34
    jsr ok
    pla
    cmp #$12
    jsr ok
    lda #$FF            ; PLP ignores B and bit 5; PHP sets both
    pha
    plp
    php
    pla
    cmp #$FF
    jsr ok
    lda #$00
    pha
    plp
    php
    pla
    cmp #$30
    jsr ok
;---------------------------------------------------------------- 11 JSR pushes return-1
    lda #11
    sta test_num
    jsr sub_peek
ret_point:
    lda counter
    cmp #<(ret_point-1)
    jsr ok
    lda counter+1
    cmp #>(ret_point-1)
    jsr ok
;---------------------------------------------------------------- 12 zero page indexed wraps
    lda #12
    sta test_num
    lda #$5A
    sta $7F
    ldx #$FF
    lda $80,x
    cmp #$5A
    jsr ok
    lda #$A5
    sta $0F
    ldy #$10
    ldx $FF,y           ; LDX zp,Y wraps too
    cpx #$A5
    jsr ok
;---------------------------------------------------------------- 13 (zp,X) and pointer wrap at $FF
    lda #13
    sta test_num
    lda #$34
    sta $0634
    lda #$34
    sta $FF
    lda #$06
    sta $00
    ldx #$00
    lda ($FF,x)         ; pointer from $FF and $00
    cmp #$34
    jsr ok
    lda #$00
    sta zp_ptr
    lda #$06
    sta zp_ptr+1
    lda #$77
    sta $0600
    ldx #4
    lda (zp_ptr-4,x)
    cmp #$77
    jsr ok
;---------------------------------------------------------------- 14 (zp),Y crossing a page
    lda #14
    sta test_num
    lda #$F0
    sta zp_ptr
    lda #$05
    sta zp_ptr+1
    lda #$C3
    sta $0610
    ldy #$20
    lda (zp_ptr),y      ; $05F0 + $20 = $0610
    cmp #$C3
    jsr ok
    lda #$3C
    sta (zp_ptr),y
    lda $0610
    cmp #$3C
    jsr ok
;---------------------------------------------------------------- 15 absolute indexed crossing a page
    lda #15
    sta test_num
    lda #$9D
    sta $0705
    ldx #$15
    lda $06F0,x
    cmp #$9D
    jsr ok
    ldy #$06
    lda $06FF,y
    cmp #$9D
    jsr ok
    lda #$11
    sta $06FF,y
    lda $0705
    cmp #$11
    jsr ok
;---------------------------------------------------------------- 16 JMP indirect page bug
    lda #16
    sta test_num
    lda #<jmp_ok
    sta $02FF
    lda #>jmp_ok
    sta $0200
    lda #>fail
    sta $0300
    jmp ($02FF)
jmp_ok:
    lda #$F8            ; restore the OAM byte we borrowed
    sta $0200
;---------------------------------------------------------------- 17 BIT
    lda #17
    sta test_num
    lda #$C0
    sta $52
    clc
    lda #$01
    bit $52
    php
    pla
    and #MASK
    cmp #$C2            ; N V from memory, Z from A AND M
    jsr ok
    lda #$01
    sta $0352
    clc
    bit $0352
    php
    pla
    and #MASK
    cmp #$00
    jsr ok
;---------------------------------------------------------------- 18 branches
    lda #18
    sta test_num
    ldx #5
    lda #0
@count:
    clc
    adc #3
    dex
    bne @count
    cmp #15
    jsr ok
    clv
    bvc @v1
    jmp fail
@v1:
    sec
    bcs @c1
    jmp fail
@c1:
    lda #$80
    bmi @n1
    jmp fail
@n1:
    lda #$01
    bpl @n2
    jmp fail
@n2:
    bne @z1
    jmp fail
@z1:
    lda #0
    beq @z2
    jmp fail
@z2:
    clc
    bcc @c2
    jmp fail
@c2:
    lda #$7F
    adc #1
    bvs @v2
    jmp fail
@v2:
;---------------------------------------------------------------- 19 BRK and RTI
    lda #19
    sta test_num
    lda #0
    sta counter
    cli
    brk
    .db $EA             ; padding byte skipped by RTI
    lda counter
    cmp #$01
    jsr ok
    lda counter+1       ; B flag seen by the handler
    and #$30
    cmp #$30
    jsr ok
    sei
;---------------------------------------------------------------- 20 RTI restores flags and address
    lda #20
    sta test_num
    lda #>rti_ok
    pha
    lda #<rti_ok
    pha
    lda #$C3            ; N V Z C
    pha
    rti
rti_ok:
    php
    pla
    and #MASK
    cmp #$C3
    jsr ok
;---------------------------------------------------------------- 21 stack wraps in page 1
    lda #21
    sta test_num
    tsx
    stx counter
    ldx #$00
    txs
    lda #$AB
    pha                 ; writes $0100, S -> $FF
    tsx
    cpx #$FF
    jsr ok
    lda $0100
    cmp #$AB
    jsr ok
    pla                 ; S -> $00
    cmp #$AB
    jsr ok
    ldx counter
    txs
;---------------------------------------------------------------- 22 memory-mode arithmetic
    lda #22
    sta test_num
    lda #$20
    sta $60
    lda #$05
    sta $65
    ldx #$05
    clc
    lda #$01
    adc $60             ; $21
    adc $60,x           ; $26
    sec
    sbc $65             ; $21
    cmp #$21
    jsr ok
    lda #$0F
    sta $0466
    ldy #$66
    lda #$F0
    ora $0400,y
    cmp #$FF
    jsr ok
    eor $0400,y
    cmp #$F0
    jsr ok
;---------------------------------------------------------------- 23 common unofficial opcodes
test23:
    lda #23
    sta test_num
    lda #$5E
    sta $70
    .db $A7, $70        ; LAX $70
    cpx #$5E
    jsr ok
    cmp #$5E
    jsr ok
    lda #$F0
    ldx #$3C
    .db $87, $71        ; SAX $71 = A & X
    lda $71
    cmp #$30
    jsr ok
    lda #$10
    sta $72
    lda #$0F
    .db $C7, $72        ; DCP $72: dec then compare
    php
    lda $72
    cmp #$0F
    jsr ok
    pla
    and #$03
    cmp #$03            ; equal -> Z C
    jsr ok
    .db $1A             ; NOP (implied)
    .db $04, $00        ; NOP zp
    .db $0C, $00, $00   ; NOP abs
;---------------------------------------------------------------- 24 PPU and controller sanity
    lda #24
    sta test_num
    lda #$21            ; write and read back VRAM through the buffer
    ldx #$00
    jsr ppu_addr
    lda #$A5
    sta PPUDATA
    lda #$5A
    sta PPUDATA
    lda #$21
    ldx #$00
    jsr ppu_addr
    lda PPUDATA         ; stale buffer
    lda PPUDATA
    cmp #$A5
    jsr ok
    lda PPUDATA
    cmp #$5A
    jsr ok
    lda #$3F            ; palette reads are immediate
    ldx #$01
    jsr ppu_addr
    lda #$2A
    sta PPUDATA
    lda #$3F
    ldx #$01
    jsr ppu_addr
    lda PPUDATA
    and #$3F
    cmp #$2A
    jsr ok

;---------------------------------------------------------------- all passed
pass:
    lda #0
    sta $6000
    lda #<msg_pass
    sta ptr
    lda #>msg_pass
    sta ptr+1
    jsr show
    lda #$1A            ; green
    jmp finish

fail:
    lda test_num
    sta $6000
    lda #<msg_fail
    sta ptr
    lda #>msg_fail
    sta ptr+1
    jsr show
    lda test_num
    jsr print_hex
    lda #$16            ; red
finish:
    pha
    lda #$3F
    ldx #$00
    jsr ppu_addr
    pla
    sta PPUDATA         ; backdrop
    lda #$30
    sta PPUDATA
    lda #$0F
    sta PPUDATA
    lda #$0F
    sta PPUDATA
    lda #$00
    sta PPUSCROLL
    sta PPUSCROLL
    lda #%00000000
    sta PPUCTRL
    lda #%00001010
    sta PPUMASK
@forever:
    jmp @forever

; Clear the screen and print the header, then (ptr) at row 14.
show:
    lda ptr
    pha
    lda ptr+1
    pha
    lda #0
    sta PPUMASK
    lda #$20
    ldx #$00
    jsr fill_nametable  ; X = tile 0 (blank)
    lda #$23
    ldx #$C0
    jsr ppu_addr
    lda #0
    ldx #64
@attr:
    sta PPUDATA
    dex
    bne @attr
    lda #$21
    ldx #$89
    jsr ppu_addr
    lda #<msg_head
    sta ptr
    lda #>msg_head
    sta ptr+1
    jsr print
    lda #$21
    ldx #$CC
    jsr ppu_addr
    pla
    sta ptr+1
    pla
    sta ptr
    jsr print
    rts

ok_zero:
    cmp #0
    jmp ok

sub_peek:
    tsx
    lda $0101,x
    sta counter
    lda $0102,x
    sta counter+1
    rts

irq:
    inc counter
    tsx
    lda $0101,x         ; pushed status
    sta counter+1
    rti

nmi:
    rti

msg_head: .db "CPU SELF TEST", 0
msg_pass: .db "PASS", 0
msg_fail: .db "FAIL ", 0
