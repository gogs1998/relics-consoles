; Foldback demo for the in-house Game Boy core. Our own program, art and music.
; Runs on both Game Boy and Game Boy Color (CGB palettes, attribute map, GDMA and double speed
; when it finds itself on a CGB). D-pad moves the mascot, A jumps (channel 1 sweep), the
; window is a status bar showing the held buttons, and a melody loops on channel 2 + wave.
; Tables (tiles, maps, palettes, notes) are appended by Tools/build_gb_roms.py.

P1   = $FF00
IF   = $FF0F
NR10 = $FF10
NR11 = $FF11
NR12 = $FF12
NR13 = $FF13
NR14 = $FF14
NR21 = $FF16
NR22 = $FF17
NR23 = $FF18
NR24 = $FF19
NR30 = $FF1A
NR32 = $FF1C
NR33 = $FF1D
NR34 = $FF1E
NR50 = $FF24
NR51 = $FF25
NR52 = $FF26
LCDC = $FF40
SCX  = $FF43
LY   = $FF44
BGP  = $FF47
OBP0 = $FF48
OBP1 = $FF49
WY   = $FF4A
WX   = $FF4B
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
IE   = $FFFF

shadow_oam = $C000
is_cgb     = $C100
px         = $C101
py         = $C102
jump_idx   = $C103
frame      = $C104
pad        = $C105
pad_prev   = $C106
scroll     = $C107
note_idx   = $C108
note_timer = $C109
facing     = $C10A
tmp        = $C10B

GROUND_Y = 88
TEMPO    = 7

.org $0040
    reti

.org $0100
    nop
    jp start

.org $0150
start:
    di
    ld sp,$FFFE
    cp $11                  ; A = $11 after boot on a CGB
    ld a,0
    jr nz,@dmg
    inc a
@dmg:
    ld (is_cgb),a
    or a
    jr z,@normal_speed
    xor a                   ; switch to double speed (IE must be 0, P1 deselected)
    ldh (IE),a
    ld a,$30
    ldh (P1),a
    ld a,1
    ldh (KEY1),a
    stop
@normal_speed:
    call lcd_off
    call load_tiles
    call load_maps
    ld a,(is_cgb)
    or a
    call nz,load_cgb
    ; clear shadow OAM, copy the DMA routine to HRAM
    ld hl,shadow_oam
    ld b,160
    xor a
@clr:
    ld (hl+),a
    dec b
    jr nz,@clr
    ld hl,dma_routine
    ld de,$FF80
    ld b,dma_end-dma_routine
@copy:
    ld a,(hl+)
    ld (de),a
    inc de
    dec b
    jr nz,@copy
    ld a,>shadow_oam
    call $FF80
    ; variables
    ld a,72
    ld (px),a
    ld a,GROUND_Y
    ld (py),a
    xor a
    ld (jump_idx),a
    ld (frame),a
    ld (pad),a
    ld (pad_prev),a
    ld (scroll),a
    ld (note_idx),a
    ld (note_timer),a
    ld (facing),a
    call sound_init
    ; display
    ld a,$E4
    ldh (BGP),a
    ldh (OBP0),a
    ld a,$D0
    ldh (OBP1),a
    ld a,128
    ldh (WY),a
    ld a,7
    ldh (WX),a
    ld a,$F7                ; LCD, window map $9C00, window, tiles $8000, 8x16 sprites, sprites, BG
    ldh (LCDC),a
    xor a
    ldh (IF),a
    ld a,$01
    ldh (IE),a
    ei

main:
    halt
    nop
    ; ---- vertical blank: OAM, scroll, status bar
    ld a,>shadow_oam
    call $FF80
    ld a,(scroll)
    ldh (SCX),a
    call draw_status
    ; ---- game logic
    call read_pad
    call move_player
    call update_oam
    call music_tick
    ld hl,frame
    inc (hl)
    ld a,(hl)
    and 1
    jr nz,main
    ld hl,scroll
    inc (hl)
    jr main

;---------------------------------------------------------------- setup
lcd_off:
    ldh a,(LCDC)
    bit 7,a
    ret z
@wait:
    ldh a,(LY)
    cp 144
    jr nz,@wait
    xor a
    ldh (LCDC),a
    ret

; Tiles: GDMA on a CGB (two transfers), a plain copy otherwise.
load_tiles:
    ld a,(is_cgb)
    or a
    jr z,@copy
    ld a,>demo_tiles
    ldh (HDMA1),a
    ld a,<demo_tiles
    ldh (HDMA2),a
    ld a,$80
    ldh (HDMA3),a
    xor a
    ldh (HDMA4),a
    ld a,$7F                ; 128 blocks of 16 bytes
    ldh (HDMA5),a
    ld a,>(demo_tiles+$800)
    ldh (HDMA1),a
    ld a,<(demo_tiles+$800)
    ldh (HDMA2),a
    ld a,$88
    ldh (HDMA3),a
    xor a
    ldh (HDMA4),a
    ld a,(DEMO_TILE_BYTES-$800)/16-1
    ldh (HDMA5),a
    ret
@copy:
    ld hl,demo_tiles
    ld de,$8000
    ld bc,DEMO_TILE_BYTES
@loop:
    ld a,(hl+)
    ld (de),a
    inc de
    dec bc
    ld a,b
    or c
    jr nz,@loop
    ret

load_maps:
    ld hl,demo_map
    ld de,$9800
    ld bc,32*18
@loop:
    ld a,(hl+)
    ld (de),a
    inc de
    dec bc
    ld a,b
    or c
    jr nz,@loop
    ; window: title row and a row of dashes
    ld hl,$9C00
    ld b,64
    ld a,' '
@fill:
    ld (hl+),a
    dec b
    jr nz,@fill
    ld hl,$9C00+1
    ld de,str_title
@title:
    ld a,(de)
    or a
    ret z
    ld (hl+),a
    inc de
    jr @title

load_cgb:
    ld a,1
    ldh (VBK),a
    ld hl,demo_attr
    ld de,$9800
    ld bc,32*18
@loop:
    ld a,(hl+)
    ld (de),a
    inc de
    dec bc
    ld a,b
    or c
    jr nz,@loop
    ld hl,$9C00
    ld b,64
    ld a,4
@win:
    ld (hl+),a
    dec b
    jr nz,@win
    xor a
    ldh (VBK),a
    ld a,$80
    ldh (BCPS),a
    ld hl,bg_palettes
    ld b,40
@bg:
    ld a,(hl+)
    ldh (BCPD),a
    dec b
    jr nz,@bg
    ld a,$80
    ldh (OCPS),a
    ld hl,obj_palettes
    ld b,8
@obj:
    ld a,(hl+)
    ldh (OCPD),a
    dec b
    jr nz,@obj
    ret

sound_init:
    ld a,$80
    ldh (NR52),a
    ld a,$77
    ldh (NR50),a
    ld a,$FF
    ldh (NR51),a
    ld a,$80
    ldh (NR21),a
    xor a
    ldh (NR30),a
    ld hl,wave_table
    ld c,$30
    ld b,16
@wave:
    ld a,(hl+)
    ld (c),a
    inc c
    dec b
    jr nz,@wave
    ld a,$80
    ldh (NR30),a
    ret

dma_routine:
    ldh ($46),a
    ld a,40
@wait:
    dec a
    jr nz,@wait
    ret
dma_end:

str_title: .db "FOLDBACK DEMO",0

;---------------------------------------------------------------- per frame
read_pad:
    ld a,$20
    ldh (P1),a
    ldh a,(P1)
    ldh a,(P1)
    cpl
    and $0F
    swap a
    ld b,a
    ld a,$10
    ldh (P1),a
    ldh a,(P1)
    ldh a,(P1)
    ldh a,(P1)
    ldh a,(P1)
    cpl
    and $0F
    or b
    ld b,a
    ld a,$30
    ldh (P1),a
    ld a,(pad)
    ld (pad_prev),a
    ld a,b
    ld (pad),a
    ret

move_player:
    ld a,(pad)
    ld b,a
    bit 4,b
    jr z,@not_right
    xor a
    ld (facing),a
    ld a,(px)
    cp 150
    jr nc,@not_right
    inc a
    ld (px),a
@not_right:
    bit 5,b
    jr z,@not_left
    ld a,$20
    ld (facing),a
    ld a,(px)
    cp 3
    jr c,@not_left
    dec a
    ld (px),a
@not_left:
    bit 6,b
    jr z,@not_up
    ld a,(py)
    cp 40
    jr c,@not_up
    dec a
    ld (py),a
@not_up:
    bit 7,b
    jr z,@not_down
    ld a,(py)
    cp GROUND_Y
    jr nc,@not_down
    inc a
    ld (py),a
@not_down:
    ld a,(pad_prev)
    cpl
    and b
    bit 0,a
    jr z,@no_jump
    ld a,(jump_idx)
    or a
    jr nz,@no_jump
    ld a,1
    ld (jump_idx),a
    call sfx_jump
@no_jump:
    ld a,(jump_idx)
    or a
    ret z
    inc a
    cp JUMP_LEN
    jr c,@store
    xor a
@store:
    ld (jump_idx),a
    ret

update_oam:
    ld a,(jump_idx)
    ld e,a
    ld d,0
    ld hl,jump_tab
    add hl,de
    ld c,(hl)
    ld a,(py)
    sub c
    add a,16
    ld b,a                  ; sprite Y
    ld a,(px)
    add a,8
    ld c,a                  ; sprite X
    ld a,(facing)
    ld d,a
    or a
    ld a,$80
    jr z,@right
    ld a,$82
@right:
    ld e,a                  ; left-hand tile
    ld hl,shadow_oam
    ld a,b
    ld (hl+),a
    ld a,c
    ld (hl+),a
    ld a,e
    ld (hl+),a
    ld a,d
    ld (hl+),a
    ld a,b
    ld (hl+),a
    ld a,c
    add a,8
    ld (hl+),a
    ld a,e
    xor 2
    ld (hl+),a
    ld a,d
    ld (hl+),a
    ret

; Window row 1: each button's label when held, dashes when not.
draw_status:
    ld a,(pad)
    ld b,a
    ld hl,status_tab
    ld c,8
@loop:
    ld a,(hl+)
    and b
    ld (tmp),a
    ld a,(hl+)
    add a,$20
    ld e,a
    ld d,$9C
    ld a,(tmp)
    or a
    jr z,@up
    ld a,(hl+)
    ld (de),a
    inc de
    ld a,(hl+)
    or a
    jr z,@next
    ld (de),a
    jr @next
@up:
    ld a,'-'
    ld (de),a
    inc de
    inc hl
    ld a,(hl+)
    or a
    jr z,@next
    ld a,'-'
    ld (de),a
@next:
    dec c
    jr nz,@loop
    ret

status_tab:
    .db $40, 1, 'U', 0
    .db $80, 3, 'D', 0
    .db $20, 5, 'L', 0
    .db $10, 7, 'R', 0
    .db $01, 9, 'A', 0
    .db $02, 11, 'B', 0
    .db $04, 13, 'S', 'E'
    .db $08, 16, 'S', 'T'

sfx_jump:
    ld a,$15
    ldh (NR10),a
    ld a,$80
    ldh (NR11),a
    ld a,$F2
    ldh (NR12),a
    xor a
    ldh (NR13),a
    ld a,$86
    ldh (NR14),a
    ret

music_tick:
    ld a,(note_timer)
    or a
    jr z,@next
    dec a
    ld (note_timer),a
    ret
@next:
    ld a,TEMPO
    ld (note_timer),a
    ld a,(note_idx)
    ld c,a
    ld b,0
    ld hl,melody
    add hl,bc
    ld a,(hl)
    or a
    jr z,@bass
    add a,a
    ld e,a
    ld d,0
    ld hl,sq_freq
    add hl,de
    ld a,$A3
    ldh (NR22),a
    ld a,(hl+)
    ldh (NR23),a
    ld a,(hl)
    or $80
    ldh (NR24),a
@bass:
    ld a,(note_idx)
    and 1
    jr nz,@advance
    ld a,(note_idx)
    srl a
    ld c,a
    ld b,0
    ld hl,bass
    add hl,bc
    ld a,(hl)
    or a
    jr z,@advance
    add a,a
    ld e,a
    ld d,0
    ld hl,wave_freq
    add hl,de
    ld a,$20
    ldh (NR32),a
    ld a,(hl+)
    ldh (NR33),a
    ld a,(hl)
    or $80
    ldh (NR34),a
@advance:
    ld a,(note_idx)
    inc a
    cp MELODY_LEN
    jr c,@store
    xor a
@store:
    ld (note_idx),a
    ret

wave_table:
    .db $01, $23, $45, $67, $89, $AB, $CD, $EF, $FE, $DC, $BA, $98, $76, $54, $32, $10
