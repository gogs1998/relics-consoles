; Shared definitions and routines for our own NES test ROMs. Written for this project.
PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
OAMADDR   = $2003
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007
OAMDMA    = $4014
APUSTATUS = $4015
JOY1      = $4016
APUFRAME  = $4017

tmp       = $00
tmp2      = $01
ptr       = $02        ; and $03
frame     = $10
nmi_flag  = $11
buttons   = $12
prev_btn  = $13
pressed   = $14
OAM       = $0200

BTN_A      = $80
BTN_B      = $40
BTN_SELECT = $20
BTN_START  = $10
BTN_UP     = $08
BTN_DOWN   = $04
BTN_LEFT   = $02
BTN_RIGHT  = $01

; Standard power-up: interrupts off, stack, PPU off, two vblanks, RAM cleared.
init_system:
    ; called with JMP-style from reset (stack already set by caller)
    lda #0
    sta PPUCTRL
    sta PPUMASK
    sta $4010
    lda #$40
    sta APUFRAME
    bit PPUSTATUS
@vb1:
    bit PPUSTATUS
    bpl @vb1
    lda #0
    ldx #0
@clr:
    sta $0000,x
    sta $0300,x
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    inx
    bne @clr
    lda #$F8            ; park every sprite off-screen
@oam:
    sta $0200,x
    inx
    bne @oam
@vb2:
    bit PPUSTATUS
    bpl @vb2
    rts

; Set PPU address to (A = hi, X = lo).
ppu_addr:
    bit PPUSTATUS
    sta PPUADDR
    stx PPUADDR
    rts

; Print the zero-terminated string at (ptr) to the current PPU address.
print:
    ldy #0
@loop:
    lda (ptr),y
    beq @done
    sta PPUDATA
    iny
    bne @loop
@done:
    rts

; Write A as two hex digits to the current PPU address.
print_hex:
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr @digit
    pla
    and #$0F
@digit:
    cmp #10
    bcc @num
    adc #6              ; carry is set: +7 maps 10..15 to 'A'..'F'
@num:
    adc #'0'
    sta PPUDATA
    rts

; Fill the 1 KB nametable at (A = hi byte) with tile X (attributes included; rewrite them after).
fill_nametable:
    stx tmp
    ldx #0
    jsr ppu_addr
    ldx #0
    ldy #4
    lda tmp
@loop:
    sta PPUDATA
    inx
    bne @loop
    dey
    bne @loop
    rts

; Read controller 1 into `buttons` (A B Select Start Up Down Left Right, bit 7..0)
; and the newly pressed buttons into `pressed`.
read_pad:
    lda buttons
    sta prev_btn
    lda #1
    sta JOY1
    sta buttons         ; the 1 falls out after eight shifts: loop terminator
    lsr a
    sta JOY1
@loop:
    lda JOY1
    lsr a
    rol buttons
    bcc @loop
    lda prev_btn
    eor #$FF
    and buttons
    sta pressed
    rts

; Load 32 palette bytes from (ptr).
load_palette:
    lda #$3F
    ldx #$00
    jsr ppu_addr
    ldy #0
@loop:
    lda (ptr),y
    sta PPUDATA
    iny
    cpy #32
    bne @loop
    rts
