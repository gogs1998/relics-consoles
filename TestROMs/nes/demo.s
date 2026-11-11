; "Test Cart" demo for the in-house NES core. Our own program, art and tune.
; Exercises: NMI, OAM DMA, sprite-0 hit split scroll, horizontal scrolling across two
; nametables (vertical mirroring), attributes, all four sprite flips, controller reading,
; pulse/triangle/noise channels and the frame counter.

player_x  = $20
player_y  = $21
vel_y     = $22
on_ground = $23
facing    = $24      ; 0 right, $40 left (sprite H-flip bit)
pal_sel   = $25
scroll_x  = $26
scroll_nt = $27
mus_timer = $28
mus_step  = $29
spark_t   = $2A
spark_x   = $2B
spark_y   = $2C
GROUND_Y  = 175

.org $8000
reset:
    sei
    cld
    ldx #$FF
    txs
    jsr init_system

    lda #<palette
    sta ptr
    lda #>palette
    sta ptr+1
    jsr load_palette

    lda #$20
    jsr draw_scene
    lda #$24
    jsr draw_scene
    jsr draw_status

    ; sprite 0: invisible marker on the status rule, for the split
    lda #23
    sta OAM+0
    lda #$05
    sta OAM+1
    lda #$02            ; palette 2, in front
    sta OAM+2
    lda #200
    sta OAM+3

    lda #60
    sta player_x
    lda #GROUND_Y
    sta player_y
    lda #1
    sta on_ground

    ; audio on: pulse 1, pulse 2, triangle, noise
    lda #$0F
    sta APUSTATUS
    lda #1
    sta mus_timer

    lda #%10001000      ; NMI on, sprites from $1000, background from $0000
    sta PPUCTRL
    lda #%00011110
    sta PPUMASK

main:
    lda nmi_flag
    beq main
    lda #0
    sta nmi_flag

    ; split: wait for the end of the previous sprite-0 hit, then the new one
@wait_clear:
    bit PPUSTATUS
    bvs @wait_clear
@wait_hit:
    bit PPUSTATUS
    bvc @wait_hit
    lda scroll_x
    sta PPUSCROLL
    lda #0
    sta PPUSCROLL
    lda scroll_nt
    ora #%10001000
    sta PPUCTRL

    jsr read_pad
    jsr move_player
    jsr update_spark
    jsr music
    jsr build_oam

    ; scroll the scene one pixel every other frame
    lda frame
    and #1
    bne main
    inc scroll_x
    bne main
    lda scroll_nt
    eor #1
    sta scroll_nt
    jmp main

nmi:
    pha
    txa
    pha
    tya
    pha
    lda #0
    sta OAMADDR
    lda #>OAM
    sta OAMDMA
    jsr draw_pad_state
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL
    lda #%10001000
    sta PPUCTRL
    inc frame
    lda #1
    sta nmi_flag
    pla
    tay
    pla
    tax
    pla
irq:
    rti

; ---------------------------------------------------------------- player
move_player:
    lda buttons
    and #BTN_RIGHT
    beq @no_r
    inc player_x
    lda #0
    sta facing
@no_r:
    lda buttons
    and #BTN_LEFT
    beq @no_l
    dec player_x
    lda #$40
    sta facing
@no_l:
    lda pressed
    and #BTN_A
    beq @no_a
    lda on_ground
    beq @no_a
    lda #$FA            ; -6
    sta vel_y
    lda #0
    sta on_ground
    jsr sfx_jump
@no_a:
    lda pressed
    and #BTN_B
    beq @no_b
    lda pal_sel
    eor #1
    sta pal_sel
    jsr sfx_blip
    lda #12
    sta spark_t
    lda player_x
    clc
    adc #4
    sta spark_x
    lda player_y
    sec
    sbc #10
    sta spark_y
@no_b:
    lda on_ground
    bne @done
    lda player_y
    clc
    adc vel_y
    sta player_y
    lda frame
    and #1
    bne @no_grav
    inc vel_y
@no_grav:
    lda vel_y
    bmi @done
    lda player_y
    cmp #GROUND_Y
    bcc @done
    lda #GROUND_Y
    sta player_y
    lda #1
    sta on_ground
    lda #0
    sta vel_y
@done:
    rts

update_spark:
    lda spark_t
    beq @off
    dec spark_t
    dec spark_y
@off:
    rts

; OAM entries 1..4: the mascot (flipped when facing left), 5: the spark.
build_oam:
    ldx #4
    lda facing
    ora pal_sel
    sta tmp             ; attributes
    ldy #0
@loop:
    lda player_y
    clc
    adc meta_dy,y
    sta OAM+0,x
    lda facing
    beq @right
    lda meta_tile_l,y
    jmp @tile
@right:
    lda meta_tile_r,y
@tile:
    sta OAM+1,x
    lda tmp
    sta OAM+2,x
    lda player_x
    clc
    adc meta_dx,y
    sta OAM+3,x
    inx
    inx
    inx
    inx
    iny
    cpy #4
    bne @loop
    lda spark_t
    bne @show
    lda #$F8
    sta OAM+20
    rts
@show:
    lda spark_y
    sta OAM+20
    lda #$06
    sta OAM+21
    lda frame
    and #%11000000      ; spin through all four flips
    ora #3
    sta OAM+22
    lda spark_x
    sta OAM+23
    rts

meta_dy:     .db 0, 0, 8, 8
meta_dx:     .db 0, 8, 0, 8
meta_tile_r: .db 1, 2, 3, 4
meta_tile_l: .db 2, 1, 4, 3

; ---------------------------------------------------------------- sound
sfx_jump:
    lda #%10011111      ; duty 2, length counter on, constant volume 15
    sta $4004
    lda #%10011010      ; sweep on, period 1, shift 2, negate: rising pitch
    sta $4005
    lda #$A0
    sta $4006
    lda #%00010001      ; length index 2 (1/6 s), period high bits 1
    sta $4007
    rts

sfx_blip:
    lda #%00010100      ; length counter on, constant volume 4
    sta $400C
    lda #$05
    sta $400E
    lda #%00100000      ; length index 4
    sta $400F
    rts

music:
    dec mus_timer
    bne @done
    lda #9
    sta mus_timer
    ldx mus_step
    lda melody,x
    beq @rest
    asl a
    tay
    lda #%10000110      ; duty 2, decaying envelope, period 6
    sta $4000
    lda #$08            ; sweep off
    sta $4001
    lda note_period,y
    sta $4002
    lda note_period+1,y
    ora #%00001000      ; length index 1
    sta $4003
@rest:
    txa
    and #1
    bne @next
    txa
    lsr a
    tay
    lda bass,y
    beq @next
    asl a
    tay
    lda #%00011000      ; linear counter 24 (staccato)
    sta $4008
    lda tri_period,y
    sta $400A
    lda tri_period+1,y
    ora #%00001000
    sta $400B
@next:
    inx
    txa
    and #31
    sta mus_step
@done:
    rts

; ---------------------------------------------------------------- drawing
; Draw a scene into the nametable at A ($20 or $24).
draw_scene:
    sta tmp2
    ldx #$00            ; sky
    jsr fill_nametable
    ; hills: row 20 is hill tops, rows 21-23 fill
    lda tmp2
    clc
    adc #2
    ldx #$80            ; $2280 = row 20
    jsr ppu_addr
    ldx #0
@hill_top:
    txa
    and #7
    tay
    lda hill_row,y
    sta PPUDATA
    inx
    cpx #32
    bne @hill_top
    ldx #0
@hill_fill:
    txa
    and #7
    tay
    lda hill_fill_row,y
    sta PPUDATA
    inx
    cpx #96
    bne @hill_fill
    ; ground: row 24 grass, rows 25-29 bricks
    lda #$08
    ldx #32
@grass:
    sta PPUDATA
    dex
    bne @grass
    lda #$09
    ldx #160
@brick:
    sta PPUDATA
    dex
    bne @brick
    ; clouds at a few spots (different per nametable)
    ldy #0
    lda tmp2
    cmp #$24
    bne @clouds
    ldy #8
@clouds:
    lda cloud_pos+1,y
    beq @attr
    tax
    lda cloud_pos,y
    sta tmp
    lda tmp2
    clc
    adc tmp
    jsr ppu_addr
    lda #$05
    sta PPUDATA
    lda #$06
    sta PPUDATA
    sta PPUDATA
    lda #$07
    sta PPUDATA
    txa
    clc
    adc #32
    tax
    lda tmp2
    clc
    adc tmp
    jsr ppu_addr
    lda #$0D
    sta PPUDATA
    lda #$0E
    sta PPUDATA
    sta PPUDATA
    lda #$0F
    sta PPUDATA
    iny
    iny
    jmp @clouds
@attr:
    lda tmp2
    clc
    adc #3
    ldx #$C0
    jsr ppu_addr
    ldx #0
@attr_loop:
    lda attr_table,x
    sta PPUDATA
    inx
    cpx #64
    bne @attr_loop
    rts

; (hi offset, lo) pairs; 0 terminates. Four clouds per nametable.
cloud_pos:
    .db $00, $A3, $00, $D2, $01, $0A, $00, $00
    .db $00, $C8, $01, $14, $00, $9B, $00, $00
hill_row:      .db $00, $0A, $0B, $0B, $0C, $00, $00, $00
hill_fill_row: .db $0A, $10, $0B, $10, $0B, $0C, $00, $00
attr_table:
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $55, $55, $55, $55, $55, $55, $55, $55
    .db $55, $55, $55, $55, $55, $55, $55, $55
    .db $55, $55, $55, $55, $55, $55, $55, $55
    .db $55, $55, $55, $55, $55, $55, $55, $55
    .db $AA, $AA, $AA, $AA, $AA, $AA, $AA, $AA
    .db $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .db $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF

; Status bar on rows 0-3 of nametable 0.
draw_status:
    lda #$20
    ldx #$00
    jsr ppu_addr
    lda #$20            ; space tile (dark background)
    ldx #96
@fill:
    sta PPUDATA
    dex
    bne @fill
    lda #$04
    ldx #32
@rule:
    sta PPUDATA
    dex
    bne @rule
    lda #$24            ; the same dark band and rule on nametable 1
    ldx #$00
    jsr ppu_addr
    lda #$20
    ldx #96
@fill2:
    sta PPUDATA
    dex
    bne @fill2
    lda #$04
    ldx #32
@rule2:
    sta PPUDATA
    dex
    bne @rule2
    lda #$20
    ldx #$22
    jsr ppu_addr
    lda #<title
    sta ptr
    lda #>title
    sta ptr+1
    jsr print
    lda #$20
    ldx #$42
    jsr ppu_addr
    lda #<pad_label
    sta ptr
    lda #>pad_label
    sta ptr+1
    jsr print
    rts

; Eight indicators at $2047: lit letter when held, '-' otherwise.
draw_pad_state:
    lda #$20
    ldx #$47
    jsr ppu_addr
    lda buttons
    sta tmp
    ldx #0
@loop:
    asl tmp
    bcc @off
    lda pad_letters,x
    jmp @put
@off:
    lda #'-'
@put:
    sta PPUDATA
    lda #' '
    sta PPUDATA
    inx
    cpx #8
    bne @loop
    rts

title:       .db "FOLDBACK TEST CART  NES CORE", 0
pad_label:   .db "PAD:", 0
pad_letters: .db "ABETUDLR"

palette:
    .db $21, $30, $01, $27   ; status: white on navy, orange rule
    .db $21, $30, $21, $10   ; sky: white clouds, grey shade
    .db $21, $1A, $2A, $0A   ; hills
    .db $21, $17, $27, $07   ; ground
    .db $21, $27, $37, $0F   ; mascot (ember)
    .db $21, $2C, $3C, $0F   ; mascot (teal)
    .db $21, $27, $27, $27   ; sprite-0 marker
    .db $21, $30, $28, $16   ; spark
