; CPU self-test for the in-house Game Boy core. Our own program.
; Each numbered test checks results and flags; the first failure stops the run.
; Result protocol (cartridge RAM, MBC1+RAM+battery): $A000 = $80 while running, $00 on pass,
; the test number on failure; $A001-$A003 = $DE $B0 $61 once started.
; Also drawn on screen as PASS or FAIL nn with our own font.

P1   = $FF00
DIV  = $FF04
TIMA = $FF05
TMA  = $FF06
TAC  = $FF07
IF   = $FF0F
LCDC = $FF40
STAT = $FF41
LY   = $FF44
LYC  = $FF45
BGP  = $FF47
IE   = $FFFF

test_num = $C000
flag     = $C001
flag2    = $C002
scratch  = $C010

;---------------------------------------------------------------- restarts and interrupt vectors
.org $0028
    ld a,$A5
    ret
.org $0040
    push af
    ld a,$40
    jp isr_common
.org $0048
    push af
    ld a,$48
    jp isr_common
.org $0050
    push af
    ld a,$50
    jp isr_common
.org $0058
    push af
    ld a,$58
    jp isr_common
.org $0060
    push af
    ld a,$60
    jp isr_common

isr_common:
    ld (flag),a
    ld a,b
    ld (flag2),a
    pop af
    reti

;---------------------------------------------------------------- entry point
.org $0100
    nop
    jp start

.org $0150
start:
    di
    ld sp,$FFFE
    ld a,$0A            ; enable cartridge RAM
    ld ($0000),a
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
    ld hl,$9800+32*2+2
    ld de,str_title
    call print
    ld a,$E4
    ldh (BGP),a
    ld a,$91
    ldh (LCDC),a
    jp run_tests

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

; DE = zero-terminated string, HL = map address
print:
    ld a,(de)
    or a
    ret z
    ld (hl+),a
    inc de
    jr print

; A = value, HL = map address
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

; A and F must equal D and E. Clobbers HL.
check_af:
    push af
    pop hl
    ld a,h
    cp d
    jp nz,fail
    ld a,l
    cp e
    jp nz,fail
    ret

; HL must equal DE and F must equal B.
check_hlf:
    push af
    ld a,h
    cp d
    jp nz,fail
    ld a,l
    cp e
    jp nz,fail
    pop hl
    ld a,l
    cp b
    jp nz,fail
    ret

sub_inc:
    inc a
    ret

sub_retc:
    scf
    ret c
    ld a,$55
    ret

fail:
    di
    ld sp,$FFFE
    ld a,(test_num)
    ld ($A000),a
    call lcd_off
    ld hl,$9800+32*8+6
    ld de,str_fail
    call print
    ld a,(test_num)
    call print_hex
    ld a,$91
    ldh (LCDC),a
@hang:
    jr @hang

pass:
    di
    xor a
    ld ($A000),a
    call lcd_off
    ld hl,$9800+32*8+8
    ld de,str_pass
    call print
    ld a,$91
    ldh (LCDC),a
@hang:
    jr @hang

str_title: .db "GB CPU SELF TEST",0
str_fail:  .db "FAIL ",0
str_pass:  .db "PASS",0

run_tests:
;---------------------------------------------------------------- 1 ADD
    ld a,1
    ld (test_num),a
    ld de,$00B0
    ld a,$3A
    add a,$C6
    call check_af
    ld de,$3B30
    ld a,$3C
    ld b,$FF
    add a,b
    call check_af
    ld de,$4E00
    ld a,$3C
    add a,$12
    call check_af
;---------------------------------------------------------------- 2 ADC
    ld a,2
    ld (test_num),a
    ld de,$F120
    ld a,$E1
    scf
    adc a,$0F
    call check_af
    ld de,$1D10
    ld a,$E1
    scf
    adc a,$3B
    call check_af
    ld de,$00B0
    ld a,$E1
    scf
    adc a,$1E
    call check_af
    ld de,$E200
    ld a,$E1
    and a
    adc a,$01
    call check_af
;---------------------------------------------------------------- 3 SUB / SBC
    ld a,3
    ld (test_num),a
    ld de,$00C0
    ld a,$3E
    sub a,$3E
    call check_af
    ld de,$2F60
    ld a,$3E
    sub a,$0F
    call check_af
    ld de,$FE50
    ld a,$3E
    sub a,$40
    call check_af
    ld de,$1040
    ld a,$3B
    scf
    sbc a,$2A
    call check_af
    ld de,$00C0
    ld a,$3B
    scf
    sbc a,$3A
    call check_af
    ld de,$EB70
    ld a,$3B
    scf
    sbc a,$4F
    call check_af
;---------------------------------------------------------------- 4 AND OR XOR CP
    ld a,4
    ld (test_num),a
    ld de,$1A20
    ld a,$5A
    and a,$3F
    call check_af
    ld de,$00A0
    ld a,$5A
    and a,$A5
    call check_af
    ld de,$5F00
    ld a,$5A
    or a,$0F
    call check_af
    ld de,$0080
    xor a
    call check_af
    ld de,$F000
    ld a,$FF
    xor a,$0F
    call check_af
    ld de,$3C60
    ld a,$3C
    cp a,$2F
    call check_af
    ld de,$3CC0
    ld a,$3C
    cp a,$3C
    call check_af
    ld de,$3C50
    ld a,$3C
    cp a,$40
    call check_af
;---------------------------------------------------------------- 5 INC / DEC
    ld a,5
    ld (test_num),a
    ld de,$00B0
    ld a,$FF
    scf
    inc a
    call check_af
    ld de,$5100
    ld a,$50
    and a
    inc a
    call check_af
    ld de,$1020
    ld a,$0F
    and a
    inc a
    call check_af
    ld de,$00C0
    ld a,$01
    and a
    dec a
    call check_af
    ld de,$FF70
    ld a,$00
    scf
    dec a
    call check_af
    ld de,$0F60
    ld a,$10
    and a
    dec a
    call check_af
    ld hl,scratch
    ld (hl),$7F
    and a
    inc (hl)
    ld a,(hl)
    ld de,$8020
    call check_af
    ld hl,scratch
    dec (hl)
    ld a,(hl)
    ld de,$7F60
    call check_af
;---------------------------------------------------------------- 6 DAA CPL SCF CCF
    ld a,6
    ld (test_num),a
    ld de,$8300
    ld a,$45
    add a,$38
    daa
    call check_af
    ld de,$4540
    ld a,$83
    sub a,$38
    daa
    call check_af
    ld de,$0090
    ld a,$99
    add a,$01
    daa
    call check_af
    ld de,$1700
    ld a,$09
    add a,$08
    daa
    call check_af
    ld de,$9950
    ld a,$00
    sub a,$01
    daa
    call check_af
    ld bc,$3500
    push bc
    pop af
    cpl
    ld de,$CA60
    call check_af
    ld bc,$00E0
    push bc
    pop af
    scf
    ld de,$0090
    call check_af
    ld bc,$0030
    push bc
    pop af
    ccf
    ld de,$0000
    call check_af
    ld bc,$0080
    push bc
    pop af
    ccf
    ld de,$0090
    call check_af
;---------------------------------------------------------------- 7 16-bit arithmetic
    ld a,7
    ld (test_num),a
    xor a
    ld hl,$8A23
    ld bc,$0605
    add hl,bc
    ld de,$9028
    ld b,$A0
    call check_hlf
    ld bc,$0000
    push bc
    pop af
    ld hl,$8A23
    add hl,hl
    ld de,$1446
    ld b,$30
    call check_hlf
    ld bc,$0000
    push bc
    pop af
    scf
    ld hl,$FFFF
    inc hl
    ld de,$0000
    ld b,$10
    call check_hlf
    ld bc,$0000
    push bc
    pop af
    scf
    ld hl,$0000
    dec hl
    ld de,$FFFF
    ld b,$10
    call check_hlf
    ld sp,$FFF8
    ld hl,sp+2
    ld de,$FFFA
    ld b,$00
    call check_hlf
    ld hl,sp+8
    ld de,$0000
    ld b,$30
    call check_hlf
    ld hl,sp+-1
    ld de,$FFF7
    ld b,$30
    call check_hlf
    ld sp,$D0F8
    add sp,8
    push af
    pop bc
    ld hl,sp+0
    ld de,$D100
    ld b,c
    push bc
    pop af
    call check_hlf
    add sp,-1
    push af
    pop bc
    ld hl,sp+0
    ld de,$D0FF
    ld b,c
    push bc
    pop af
    call check_hlf
    ld sp,$1234
    ld (scratch),sp
    ld sp,$FFFE
    ld a,(scratch)
    cp $34
    jp nz,fail
    ld a,(scratch+1)
    cp $12
    jp nz,fail
    ld hl,$DFF0
    ld sp,hl
    ld hl,sp+0
    ld sp,$FFFE
    ld a,h
    cp $DF
    jp nz,fail
    ld a,l
    cp $F0
    jp nz,fail
;---------------------------------------------------------------- 8 CB prefix
    ld a,8
    ld (test_num),a
    ld b,$85
    rlc b
    ld a,b
    ld de,$0B10
    call check_af
    and a
    ld c,$80
    rl c
    ld a,c
    ld de,$0090
    call check_af
    ld d,$01
    rrc d
    ld a,d
    ld de,$8010
    call check_af
    and a
    ld e,$01
    rr e
    ld a,e
    ld de,$0090
    call check_af
    ld h,$FF
    sla h
    ld a,h
    ld de,$FE10
    call check_af
    ld l,$8A
    sra l
    ld a,l
    ld de,$C500
    call check_af
    ld a,$01
    srl a
    ld de,$0090
    call check_af
    ld b,$F0
    swap b
    ld a,b
    ld de,$0F00
    call check_af
    ld a,0
    swap a
    ld de,$0080
    call check_af
    scf
    ld h,$80
    bit 7,h
    ld a,0
    ld de,$0030
    call check_af
    and a
    ld b,$EF
    bit 4,b
    ld a,0
    ld de,$00A0
    call check_af
    ld c,$00
    set 3,c
    set 7,c
    ld a,c
    cp $88
    jp nz,fail
    ld c,$FF
    res 0,c
    res 6,c
    ld a,c
    cp $BE
    jp nz,fail
    ld hl,scratch
    ld (hl),$81
    rlc (hl)
    ld a,(hl)
    ld de,$0310
    call check_af
    ld hl,scratch
    set 6,(hl)
    ld a,(hl)
    cp $43
    jp nz,fail
    bit 6,(hl)
    jp z,fail
    res 6,(hl)
    bit 6,(hl)
    jp nz,fail
    swap (hl)
    ld a,(hl)
    cp $30
    jp nz,fail
;---------------------------------------------------------------- 9 rotates on A
    ld a,9
    ld (test_num),a
    ld bc,$8580
    push bc
    pop af
    rlca
    ld de,$0B10
    call check_af
    ld bc,$9510
    push bc
    pop af
    rla
    ld de,$2B10
    call check_af
    ld bc,$3B00
    push bc
    pop af
    rrca
    ld de,$9D10
    call check_af
    ld bc,$8100
    push bc
    pop af
    rra
    ld de,$4010
    call check_af
    ld bc,$0000
    push bc
    pop af
    rla
    ld de,$0000
    call check_af
;---------------------------------------------------------------- 10 stack and control flow
    ld a,10
    ld (test_num),a
    ld bc,$12FF
    push bc
    pop af
    push af
    pop de
    ld a,e
    cp $F0
    jp nz,fail
    ld a,d
    cp $12
    jp nz,fail
    ld bc,$BEEF
    ld de,$CAFE
    push bc
    push de
    pop bc
    pop de
    ld a,b
    cp $CA
    jp nz,fail
    ld a,c
    cp $FE
    jp nz,fail
    ld a,d
    cp $BE
    jp nz,fail
    ld a,e
    cp $EF
    jp nz,fail
    ld a,0
    call sub_inc
    cp 1
    jp nz,fail
    xor a
    call nz,sub_inc
    or a
    jp nz,fail
    xor a
    call z,sub_inc
    cp 1
    jp nz,fail
    ld a,0
    call sub_retc
    cp 0
    jp nz,fail
    ld a,0
    rst $28
    cp $A5
    jp nz,fail
    ld hl,@target
    jp hl
    jp fail
@target:
    xor a
    jr nz,@bad
    jr z,@ok1
@bad:
    jp fail
@ok1:
    scf
    jr nc,@bad
    jr c,@ok2
    jp fail
@ok2:
    and a
    jp c,fail
    jp nc,@ok3
    jp fail
@ok3:
    ld hl,sp+0
    ld a,h
    cp $FF
    jp nz,fail
    ld a,l
    cp $FE
    jp nz,fail
;---------------------------------------------------------------- 11 memory addressing forms
    ld a,11
    ld (test_num),a
    ld hl,scratch
    ld a,$11
    ld (hl+),a
    ld a,$22
    ld (hl-),a
    ld a,l
    cp <scratch
    jp nz,fail
    ld a,(hl+)
    cp $11
    jp nz,fail
    ld a,(hl)
    cp $22
    jp nz,fail
    ld a,$10
    ld hl,scratch
    add a,(hl)
    cp $21
    jp nz,fail
    ld c,$F0
    ld a,$77
    ld (c),a
    ld a,0
    ld a,($FFF0)
    cp $77
    jp nz,fail
    ld a,$66
    ldh ($F1),a
    ld c,$F1
    ld a,(c)
    cp $66
    jp nz,fail
    ld bc,scratch+4
    ld a,$39
    ld (bc),a
    ld de,scratch+4
    ld a,0
    ld a,(de)
    cp $39
    jp nz,fail
;---------------------------------------------------------------- 12 timer interrupt
    ld a,12
    ld (test_num),a
    di
    xor a
    ld (flag),a
    ldh (IF),a
    ld a,$04
    ldh (IE),a
    ld a,$F0
    ldh (TMA),a
    ldh (TIMA),a
    ld a,$05
    ldh (TAC),a
    ei
    halt
    nop
    di
    ld a,(flag)
    cp $50
    jp nz,fail
    ldh a,(IF)
    and 4
    jp nz,fail
    ldh a,(TIMA)
    cp $F0
    jp c,fail
;---------------------------------------------------------------- 13 HALT with IME off, halt bug
    ld a,13
    ld (test_num),a
    xor a
    ldh (IF),a
    ld (flag),a
    ld a,$F0
    ldh (TIMA),a
    halt
    nop
    ldh a,(IF)
    and 4
    jp z,fail
    ld a,(flag)
    or a
    jp nz,fail
    ld b,0
    halt
    inc b
    ld a,b
    cp 2
    jp nz,fail
;---------------------------------------------------------------- 14 EI delay
    ld a,14
    ld (test_num),a
    xor a
    ld (flag),a
    ei
    di
    ld a,(flag)
    or a
    jp nz,fail
    ld b,0
    ei
    inc b
    inc b
    di
    ld a,(flag2)
    cp 1
    jp nz,fail
    ld a,(flag)
    cp $50
    jp nz,fail
    ld a,b
    cp 2
    jp nz,fail
    xor a
    ldh (TAC),a
;---------------------------------------------------------------- 15 VBlank and LYC interrupts
    ld a,15
    ld (test_num),a
    xor a
    ldh (IF),a
    ld (flag),a
    ld a,$01
    ldh (IE),a
    ei
    halt
    nop
    di
    ld a,(flag)
    cp $40
    jp nz,fail
    ldh a,(LY)
    cp 144
    jp nz,fail
    xor a
    ld (flag),a
    ld a,$40
    ldh (LYC),a
    ldh (STAT),a
    ld a,$02
    ldh (IE),a
    xor a
    ldh (IF),a
    ei
    halt
    nop
    di
    ld a,(flag)
    cp $48
    jp nz,fail
    ldh a,(LY)
    cp $40
    jp nz,fail
    ldh a,(STAT)
    and 4
    jp z,fail
    xor a
    ldh (STAT),a
    ldh (IE),a
;---------------------------------------------------------------- 16 DIV
    ld a,16
    ld (test_num),a
    ldh a,(DIV)
    ld b,a
    ld c,0
@spin:
    dec c
    jr nz,@spin
    ldh a,(DIV)
    cp b
    jp z,fail
    ldh (DIV),a
    ldh a,(DIV)
    cp 2
    jp nc,fail
;---------------------------------------------------------------- 17 MBC1 ROM banks and RAM
    ld a,17
    ld (test_num),a
    ld a,($4000)
    cp 1
    jp nz,fail
    ld a,2
    ld ($2000),a
    ld a,($4000)
    cp 2
    jp nz,fail
    ld a,3
    ld ($2000),a
    ld a,($4000)
    cp 3
    jp nz,fail
    xor a
    ld ($2000),a
    ld a,($4000)
    cp 1
    jp nz,fail
    ld a,$5A
    ld ($A010),a
    ld a,($A010)
    cp $5A
    jp nz,fail
    xor a
    ld ($0000),a
    ld a,($A010)
    cp $FF
    jp nz,fail
    ld a,$0A
    ld ($0000),a
    ld a,($A010)
    cp $5A
    jp nz,fail
;---------------------------------------------------------------- 18 OAM DMA
    ld a,18
    ld (test_num),a
    ld hl,$C100
    ld b,160
    ld c,0
@fill:
    ld a,c
    xor $A5
    ld (hl+),a
    inc c
    dec b
    jr nz,@fill
    ld hl,dma_routine
    ld de,$FF80
    ld b,dma_end-dma_routine
@copy:
    ld a,(hl+)
    ld (de),a
    inc de
    dec b
    jr nz,@copy
    call lcd_off
    ld a,$C1
    call $FF80
    ld hl,$FE00
    ld c,0
@check:
    ld a,c
    xor $A5
    cp (hl)
    jp nz,fail
    inc hl
    inc c
    ld a,c
    cp 160
    jr nz,@check
    ld a,$91
    ldh (LCDC),a
;---------------------------------------------------------------- 19 joypad register
    ld a,19
    ld (test_num),a
    ld a,$30
    ldh (P1),a
    ldh a,(P1)
    and $0F
    cp $0F
    jp nz,fail
    jp pass

dma_routine:
    ldh ($46),a
    ld a,40
@wait:
    dec a
    jr nz,@wait
    ret
dma_end:

;---------------------------------------------------------------- ROM bank markers
.org $4000
    .db 1
.bank 2
    .db 2
.bank 3
    .db 3
.bank 0
