; Game Boy Color hardware self-test for the in-house core. Our own program.
; Cartridge: MBC5 + 32 KB RAM + battery, 64 KB ROM. Same result protocol as gb_selftest:
; $A000 (RAM bank 0) = $80 while running, $00 on pass, the test number on failure;
; $A001-$A003 = $DE $B0 $61. Drawn on screen as PASS or FAIL nn.

DIV  = $FF04
IF   = $FF0F
LCDC = $FF40
STAT = $FF41
LY   = $FF44
KEY1 = $FF4D
VBK  = $FF4F
HDMA1 = $FF51
HDMA2 = $FF52
HDMA3 = $FF53
HDMA4 = $FF54
HDMA5 = $FF55
BCPS = $FF68
BCPD = $FF69
OCPS = $FF6A
OCPD = $FF6B
SVBK = $FF70
IE   = $FFFF

test_num = $C000
boot_a   = $C001
count    = $C002

.org $0000
    .db $B0                 ; marker read back through MBC5 bank 0 at $4000

.org $0100
    nop
    jp start

.org $0150
start:
    di
    ld sp,$FFFE
    ld (boot_a),a
    ld a,$0A
    ld ($0000),a
    xor a
    ld ($4000),a            ; RAM bank 0
    ld a,$80
    ld ($A000),a
    ld a,$DE
    ld ($A001),a
    ld a,$B0
    ld ($A002),a
    ld a,$61
    ld ($A003),a
    xor a
    ldh (IF),a
    ldh (IE),a
    call lcd_off
    call load_font
    call clear_map
    ; BG palette 0: white, light, dark, black
    ld a,$80
    ldh (BCPS),a
    ld hl,pal0
    ld b,8
@pal:
    ld a,(hl+)
    ldh (BCPD),a
    dec b
    jr nz,@pal
    ld hl,$9800+32*2+2
    ld de,str_title
    call print
    jp run_tests

pal0: .dw $7FFF, $56B5, $294A, $0000

lcd_off:
    ldh a,(LCDC)
    bit 7,a
    ret z
@wait:
    ldh a,(LY)
    cp 144
    jr nz,@wait
    ldh a,(LCDC)
    res 7,a
    ldh (LCDC),a
    ret

lcd_on:
    ld a,$91
    ldh (LCDC),a
    ret

load_font:
    ld hl,font_tiles
    ld de,$8200
    ld bc,1024
@loop:
    ld a,(hl+)
    ld (de),a
    inc de
    dec bc
    ld a,b
    or c
    jr nz,@loop
    ret

clear_map:
    ld hl,$9800
    ld bc,$400
@loop:
    ld a,$20
    ld (hl+),a
    dec bc
    ld a,b
    or c
    jr nz,@loop
    ret

print:
    ld a,(de)
    or a
    ret z
    ld (hl+),a
    inc de
    jr print

print_hex:
    push af
    swap a
    call @nib
    pop af
@nib:
    and $0F
    cp 10
    jr c,@digit
    add a,'A'-'0'-10
@digit:
    add a,'0'
    ld (hl+),a
    ret

; wait until LY = B
wait_ly:
    ldh a,(LY)
    cp b
    jr nz,wait_ly
    ret

fail:
    di
    ld sp,$FFFE
    xor a
    ld ($4000),a
    ld a,(test_num)
    ld ($A000),a
    call lcd_off
    ld hl,$9800+32*8+6
    ld de,str_fail
    call print
    ld a,(test_num)
    call print_hex
    call lcd_on
@hang:
    jr @hang

pass:
    di
    xor a
    ld ($4000),a
    ld ($A000),a
    call lcd_off
    ld hl,$9800+32*8+8
    ld de,str_pass
    call print
    call lcd_on
@hang:
    jr @hang

str_title: .db "GBC HARDWARE TEST",0
str_fail:  .db "FAIL ",0
str_pass:  .db "PASS",0

run_tests:
;---------------------------------------------------------------- 1 booted as a CGB
    ld a,1
    ld (test_num),a
    ld a,(boot_a)
    cp $11
    jp nz,fail
;---------------------------------------------------------------- 2 WRAM banks
    ld a,2
    ld (test_num),a
    ld b,1
@wr:
    ld a,b
    ldh (SVBK),a
    ld ($D000),a
    inc b
    ld a,b
    cp 8
    jr nz,@wr
    ld b,1
@rd:
    ld a,b
    ldh (SVBK),a
    ld a,($D000)
    cp b
    jp nz,fail
    inc b
    ld a,b
    cp 8
    jr nz,@rd
    xor a                   ; bank 0 selects bank 1
    ldh (SVBK),a
    ld a,($D000)
    cp 1
    jp nz,fail
    ld a,3
    ldh (SVBK),a
    ld a,($F000)            ; echo of $D000
    cp 3
    jp nz,fail
    ldh a,(SVBK)
    and 7
    cp 3
    jp nz,fail
    ld a,1
    ldh (SVBK),a
;---------------------------------------------------------------- 3 VRAM banks
    ld a,3
    ld (test_num),a
    xor a
    ldh (VBK),a
    ld a,$11
    ld ($8000),a
    ld a,1
    ldh (VBK),a
    ld a,$22
    ld ($8000),a
    ldh a,(VBK)
    cp $FF
    jp nz,fail
    ld a,($8000)
    cp $22
    jp nz,fail
    xor a
    ldh (VBK),a
    ld a,($8000)
    cp $11
    jp nz,fail
;---------------------------------------------------------------- 4 palette RAM
    ld a,4
    ld (test_num),a
    ld a,$88                ; palette 1, auto-increment
    ldh (BCPS),a
    ld a,$12
    ldh (BCPD),a
    ld a,$34
    ldh (BCPD),a
    ldh a,(BCPS)
    cp $CA                  ; index advanced to $0A, bit 6 reads 1
    jp nz,fail
    ld a,$08
    ldh (BCPS),a
    ldh a,(BCPD)
    cp $12
    jp nz,fail
    ldh a,(BCPD)            ; reads do not advance
    cp $12
    jp nz,fail
    ld a,$09
    ldh (BCPS),a
    ldh a,(BCPD)
    cp $34
    jp nz,fail
    ld a,$85
    ldh (OCPS),a
    ld a,$5A
    ldh (OCPD),a
    ld a,$05
    ldh (OCPS),a
    ldh a,(OCPD)
    cp $5A
    jp nz,fail
;---------------------------------------------------------------- 5 general-purpose DMA into VRAM bank 1
    ld a,5
    ld (test_num),a
    ld a,1
    ldh (VBK),a
    ld a,>dma_src
    ldh (HDMA1),a
    ld a,<dma_src
    ldh (HDMA2),a
    ld a,$01
    ldh (HDMA3),a
    ld a,$00
    ldh (HDMA4),a           ; destination $8100
    ld a,$01                ; 2 blocks
    ldh (HDMA5),a
    ldh a,(HDMA5)
    cp $FF
    jp nz,fail
    ld hl,$8100
    ld de,dma_src
    ld b,32
@chk:
    ld a,(de)
    cp (hl)
    jp nz,fail
    inc hl
    inc de
    dec b
    jr nz,@chk
    xor a
    ldh (VBK),a
    ld a,($8100)            ; bank 0 untouched
    or a
    jp nz,fail
;---------------------------------------------------------------- 6 HBlank DMA (LCD on)
    ld a,6
    ld (test_num),a
    ld hl,$C200
    ld b,64
    ld c,$40
@fill6:
    ld a,c
    ld (hl+),a
    inc c
    dec b
    jr nz,@fill6
    call lcd_on
    ld b,0
    call wait_ly
    ld a,$C2
    ldh (HDMA1),a
    xor a
    ldh (HDMA2),a
    ld a,$08
    ldh (HDMA3),a
    xor a
    ldh (HDMA4),a           ; destination $8800
    ld a,$83                ; 4 blocks, one per HBlank
    ldh (HDMA5),a
    ldh a,(HDMA5)
    bit 7,a                 ; active right after the start
    jp nz,fail
@wait6:
    ldh a,(HDMA5)
    cp $FF
    jr nz,@wait6
    ldh a,(LY)              ; four HBlanks: done within a few lines
    cp 8
    jp nc,fail
    call lcd_off
    ld hl,$8800
    ld c,$40
@chk6:
    ld a,c
    cp (hl)
    jp nz,fail
    inc hl
    inc c
    ld a,c
    cp $80
    jr nz,@chk6
;---------------------------------------------------------------- 7 HBlank DMA cancel
    ld a,7
    ld (test_num),a
    call lcd_on
    ld b,10
    call wait_ly
    ld a,$C2
    ldh (HDMA1),a
    xor a
    ldh (HDMA2),a
    ld a,$09
    ldh (HDMA3),a
    xor a
    ldh (HDMA4),a
    ld a,$87                ; 8 blocks
    ldh (HDMA5),a
    ld b,13
    call wait_ly
    xor a
    ldh (HDMA5),a           ; cancel
    ldh a,(HDMA5)
    bit 7,a
    jp z,fail
    and $7F
    cp 7                    ; some blocks done, some left
    jp nc,fail
    cp 2
    jp c,fail
;---------------------------------------------------------------- 8 double speed
    ld a,8
    ld (test_num),a
    ldh a,(KEY1)
    bit 7,a
    jp nz,fail
    call measure_div
    cp 80
    jp c,fail
    cp 100
    jp nc,fail
    ld a,$30
    ldh ($00),a
    ld a,1
    ldh (KEY1),a
    stop
    ldh a,(KEY1)
    bit 7,a
    jp z,fail
    bit 0,a
    jp nz,fail
    call measure_div        ; DIV runs twice as fast against the LCD
    cp 165
    jp c,fail
    cp 195
    jp nc,fail
    ld a,1
    ldh (KEY1),a
    stop
    ldh a,(KEY1)
    bit 7,a
    jp nz,fail
;---------------------------------------------------------------- 9 MBC5
    ld a,9
    ld (test_num),a
    ld a,($4000)
    cp 1
    jp nz,fail
    xor a
    ld ($2000),a            ; MBC5 maps bank 0 when asked
    ld a,($4000)
    cp $B0
    jp nz,fail
    ld a,3
    ld ($2000),a
    ld a,($4000)
    cp 3
    jp nz,fail
    ld a,2
    ld ($2000),a
    xor a
    ld ($3000),a
    ld a,($4000)
    cp 2
    jp nz,fail
    ld a,1
    ld ($2000),a
    ld a,$66
    ld ($A100),a
    ld a,1
    ld ($4000),a            ; RAM bank 1
    ld a,$77
    ld ($A100),a
    xor a
    ld ($4000),a
    ld a,($A100)
    cp $66
    jp nz,fail
    ld a,1
    ld ($4000),a
    ld a,($A100)
    cp $77
    jp nz,fail
    xor a
    ld ($4000),a
    jp pass

; DIV ticks over 50 LCD lines (LCD on): ~89 at normal speed, ~178 at double speed.
measure_div:
    call lcd_on
    ld b,0
    call wait_ly
    ldh (DIV),a
    ld b,50
    call wait_ly
    ldh a,(DIV)
    ld c,a
    call lcd_off
    ld a,c
    ret

.align 16
dma_src:
    .db $01, $02, $03, $04, $05, $06, $07, $08, $09, $0A, $0B, $0C, $0D, $0E, $0F, $10
    .db $F1, $E2, $D3, $C4, $B5, $A6, $97, $88, $79, $6A, $5B, $4C, $3D, $2E, $1F, $00

.org $4000
    .db 1
.bank 2
    .db 2
.bank 3
    .db 3
.bank 0
