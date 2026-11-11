; Shared PASS / FAIL reporting for our mapper probes. Needs `test_num` and `msg_head`.
; $6000 = 0 on pass, the failing test number otherwise. $6001-$6003 = $DE $B0 $61.

test_num = $30

start_report:
    lda #$80
    sta $6000
    lda #$DE
    sta $6001
    lda #$B0
    sta $6002
    lda #$61
    sta $6003
    rts

; Z set = OK.
ok:
    beq @fine
    jmp fail
@fine:
    rts

pass:
    lda #0
    sta $6000
    lda #<msg_pass
    sta ptr
    lda #>msg_pass
    sta ptr+1
    jsr show
    lda #$1A
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
    lda #$16
finish:
    pha
    lda #$3F
    ldx #$00
    jsr ppu_addr
    pla
    sta PPUDATA
    lda #$30
    sta PPUDATA
    lda #$0F
    sta PPUDATA
    sta PPUDATA
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL
    lda #finish_ctrl
    sta PPUCTRL
    lda #%00011110
    sta PPUMASK
@forever:
    jmp @forever

show:
    lda ptr
    pha
    lda ptr+1
    pha
    lda #0
    sta PPUMASK
    lda #$20
    ldx #$00
    jsr fill_nametable
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
    ldx #$88
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

; Copy the 4 KB background pattern table from `font_chr` in PRG to CHR RAM $0000.
upload_font:
    lda #$00
    ldx #$00
    jsr ppu_addr
    lda #<font_chr
    sta ptr
    lda #>font_chr
    sta ptr+1
    ldx #16
    ldy #0
@loop:
    lda (ptr),y
    sta PPUDATA
    iny
    bne @loop
    inc ptr+1
    dex
    bne @loop
    rts

msg_pass: .db "PASS", 0
msg_fail: .db "FAIL ", 0
