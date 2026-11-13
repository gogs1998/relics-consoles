"""Mapper probe ROMs (our own): MMC1, UxROM, CNROM, MMC3, MMC2, MMC4, Color Dreams, GxROM and FME-7.
Imported by Tools/build_test_roms.py.

Each probe switches banks, checks signature bytes the build placed in every bank, and reports
PASS / FAIL nn on screen and in $6000 (0 = pass).
"""

FONT_INC = '\nfont_chr:\n'  # followed by .db lines of the 4 KB background table


def font_db(chr_bank):
    bg = chr_bank[:0x1000]
    lines = []
    for i in range(0, len(bg), 32):
        lines.append('.db ' + ', '.join(f'${b:02X}' for b in bg[i:i + 32]))
    return FONT_INC + '\n'.join(lines) + '\n'


MMC1 = r'''
; MMC1 probe: 128 KB PRG (8 x 16 KB), 8 KB CHR RAM.
reg_ptr = $40
finish_ctrl = $00
.org $C000
reset:
    sei
    cld
    ldx #$FF
    txs
    jsr init_system
    jsr start_report
    lda #$80            ; reset the shift register (and force PRG mode 3)
    sta $8000
    lda #%01110         ; control: PRG mode 3, CHR 8 KB, vertical mirroring
    ldx #$80
    jsr mmc1_write
;---- 1: each 16 KB bank at $8000
    lda #1
    sta test_num
    ldy #0
@bank:
    tya
    pha
    ldx #$E0
    jsr mmc1_write
    pla
    tay
    cpy $8000
    jsr ok
    tya
    eor #$A5
    cmp $8001
    jsr ok
    iny
    cpy #7
    bne @bank
;---- 2: the last bank stays fixed at $C000
    lda #2
    sta test_num
    lda sig_last
    cmp #$77
    jsr ok
;---- 3: CHR RAM is writable
    lda #3
    sta test_num
    lda #$00
    ldx #$10
    jsr ppu_addr
    lda #$C3
    sta PPUDATA
    lda #$00
    ldx #$10
    jsr ppu_addr
    lda PPUDATA
    lda PPUDATA
    cmp #$C3
    jsr ok
;---- 4: mirroring follows the control register
    lda #4
    sta test_num
    lda #$20            ; vertical: $2000 and $2800 are the same table
    ldx #$05
    jsr ppu_addr
    lda #$5A
    sta PPUDATA
    lda #$28
    ldx #$05
    jsr ppu_addr
    lda PPUDATA
    lda PPUDATA
    cmp #$5A
    jsr ok
    lda #%01111         ; horizontal: $2000 and $2400 are the same table
    ldx #$80
    jsr mmc1_write
    lda #$24
    ldx #$05
    jsr ppu_addr
    lda PPUDATA
    lda PPUDATA
    cmp #$5A
    jsr ok
;---- 5: PRG RAM
    lda #5
    sta test_num
    lda #$3C
    sta $6100
    lda $6100
    cmp #$3C
    jsr ok
    jsr upload_font
    jmp pass

; Write A to the MMC1 register whose high address byte is X (five serial writes).
mmc1_write:
    stx reg_ptr+1
    ldx #0
    stx reg_ptr
    ldy #0
    ldx #5
@bit:
    sta (reg_ptr),y
    lsr a
    dex
    bne @bit
    rts

msg_head: .db "MMC1 PROBE", 0
sig_last: .db $77
nmi:
irq:
    rti
'''

UXROM = r'''
; UxROM probe: 128 KB PRG, CHR RAM. Writes avoid bus conflicts via a table of bank numbers.
finish_ctrl = $00
.org $C000
reset:
    sei
    cld
    ldx #$FF
    txs
    jsr init_system
    jsr start_report
    lda #1
    sta test_num
    ldy #0
@bank:
    lda banks,y
    sta banks,y
    cpy $8000
    jsr ok
    tya
    eor #$A5
    cmp $8001
    jsr ok
    iny
    cpy #7
    bne @bank
    jsr upload_font
    jmp pass
banks: .db 0, 1, 2, 3, 4, 5, 6, 7
msg_head: .db "UXROM PROBE", 0
nmi:
irq:
    rti
'''

CNROM = r'''
; CNROM probe: 32 KB PRG, 4 x 8 KB CHR ROM with the bank number at CHR $0FF0.
finish_ctrl = $00
.org $8000
reset:
    sei
    cld
    ldx #$FF
    txs
    jsr init_system
    jsr start_report
    lda #1
    sta test_num
    ldy #0
@bank:
    lda banks,y
    sta banks,y
    lda #$0F
    ldx #$F0
    jsr ppu_addr
    lda PPUDATA
    lda PPUDATA
    sta $00
    cpy $00
    jsr ok
    iny
    cpy #4
    bne @bank
    lda banks           ; back to bank 0 for the report
    sta banks
    jmp pass
banks: .db 0, 1, 2, 3
msg_head: .db "CNROM PROBE", 0
nmi:
irq:
    rti
'''

MMC3 = r'''
; MMC3 probe: 128 KB PRG (16 x 8 KB, bank number at the start of each), 64 KB CHR (64 x 1 KB,
; bank number at offset $3F0 of each). Then the scanline IRQ: one per frame at line 120.
irq_count = $41
frames = $42
finish_ctrl = $00
.org $E000
reset:
    sei
    cld
    ldx #$FF
    txs
    jsr init_system
    jsr start_report
    lda #$80
    sta $A001           ; PRG RAM on
;---- 1: R6 selects $8000 (PRG mode 0)
    lda #1
    sta test_num
    ldy #0
@r6:
    lda #6
    sta $8000
    sty $8001
    cpy $8000
    jsr ok
    iny
    cpy #14
    bne @r6
;---- 2: R7 selects $A000
    lda #2
    sta test_num
    ldy #0
@r7:
    lda #7
    sta $8000
    sty $8001
    cpy $A000
    jsr ok
    iny
    cpy #14
    bne @r7
;---- 3: $C000 is the second-last bank in mode 0, R6 in mode 1
    lda #3
    sta test_num
    lda $C000
    cmp #14
    jsr ok
    lda #$46            ; mode 1, select R6
    sta $8000
    lda #5
    sta $8001
    lda $C000
    cmp #5
    jsr ok
    lda $8000
    cmp #14
    jsr ok
    lda #$06            ; back to mode 0
    sta $8000
;---- 4: R2 (1 KB at $1000)
    lda #4
    sta test_num
    ldy #8
@r2:
    lda #2
    sta $8000
    sty $8001
    lda #$13
    ldx #$F0
    jsr ppu_addr
    lda PPUDATA
    lda PPUDATA
    sta $00
    cpy $00
    jsr ok
    iny
    cpy #64
    bne @r2
    ; standard layout for drawing: R0=0 R1=2 R2=4 R3=5 R4=6 R5=7
    ldx #0
@restore:
    stx $8000
    lda layout,x
    sta $8001
    inx
    cpx #6
    bne @restore
;---- 5: scanline IRQ fires once per frame
    lda #5
    sta test_num
    lda #$20
    ldx #$00
    jsr fill_nametable  ; blank screen with rendering on so the counter is clocked
    lda #120
    sta $C000
    sta $C001
    sta $E001
    lda #%10001000      ; NMI on, sprites at $1000
    sta PPUCTRL
    lda #%00011110
    sta PPUMASK
    cli
@wait:
    lda frames
    cmp #10
    bcc @wait
    sei
    lda #0
    sta PPUCTRL
    sta $E000
    lda irq_count
    cmp #9
    bcc @bad
    cmp #12
    bcs @bad
    jmp pass
@bad:
    jmp fail

irq:
    sta $E000           ; acknowledge and disable until the next frame
    inc irq_count
    rti
nmi:
    sta $C001           ; reload the counter and re-enable, as games do each frame
    sta $E001
    inc frames
    rti
layout: .db 0, 2, 4, 5, 6, 7
msg_head: .db "MMC3 PROBE", 0
'''


# Shared by the MMC2 (mapper 9) and MMC4 (mapper 10) probes: the CHR latches, which flip after
# the PPU reads tile $FD or $FE, and the mirroring register. CHR: 8 x 4 KB, bank number at $0FF0.
# Reads go through PPUDATA: its buffered read is a real PPU fetch, so it trips the latch too.
LATCH_TESTS = r"""
;---- 3: latch 0 ($0000-$0FFF): starts on FE
    lda #3
    sta test_num
    lda #1
    sta $B000           ; FD bank for $0000
    lda #2
    sta $C000           ; FE bank for $0000
    lda #$0F
    ldx #$F0
    jsr chr_read
    cmp #2
    jsr ok
    lda #$0F
    ldx #$D8
    jsr chr_read        ; fetch $0FD8: latch 0 -> FD
    lda #$0F
    ldx #$F0
    jsr chr_read
    cmp #1
    jsr ok
    lda #$0F
    ldx #$E8
    jsr chr_read        ; fetch $0FE8: latch 0 -> FE
    lda #$0F
    ldx #$F0
    jsr chr_read
    cmp #2
    jsr ok
;---- 4: $0FD9 trips latch 0 on MMC4 only (MMC2 watches $0FD8 exactly)
    lda #4
    sta test_num
    lda #$0F
    ldx #$D9
    jsr chr_read
    lda #$0F
    ldx #$F0
    jsr chr_read
    cmp #FD9_EXPECT
    jsr ok
    lda #$0F
    ldx #$E8
    jsr chr_read        ; back to FE
;---- 5: latch 1 ($1000-$1FFF) watches $1FD8-$1FDF and $1FE8-$1FEF on both
    lda #5
    sta test_num
    lda #3
    sta $D000
    lda #4
    sta $E000
    lda #$1F
    ldx #$F0
    jsr chr_read
    cmp #4
    jsr ok
    lda #$1F
    ldx #$DA
    jsr chr_read
    lda #$1F
    ldx #$F0
    jsr chr_read
    cmp #3
    jsr ok
    lda #$1F
    ldx #$EF
    jsr chr_read
    lda #$1F
    ldx #$F0
    jsr chr_read
    cmp #4
    jsr ok
;---- 6: mirroring ($F000: 0 vertical, 1 horizontal)
    lda #6
    sta test_num
    lda #0
    sta $F000
    lda #$20
    ldx #$05
    jsr ppu_addr
    lda #$5A
    sta PPUDATA
    lda #$28
    ldx #$05
    jsr nt_read
    cmp #$5A
    jsr ok
    lda #1
    sta $F000
    lda #$24
    ldx #$05
    jsr nt_read
    cmp #$5A
    jsr ok
;---- back to bank 0 everywhere for the report
    lda #0
    sta $B000
    sta $C000
    sta $D000
    sta $E000
    jmp pass

; A = high byte, X = low byte of a CHR address. Fetches it (tripping any latch), then returns the
; byte read with the banks as they are afterwards (PPUDATA reads are one behind).
chr_read:
    sta tmp2
    stx tmp
    jsr ppu_addr        ; this fetch is the one that trips the latch
    lda PPUDATA
    lda tmp2
    ldx tmp
    jsr ppu_addr
    lda PPUDATA         ; buffered: fetches again with the new bank
    lda PPUDATA
    rts
nt_read:
    jsr ppu_addr
    lda PPUDATA
    lda PPUDATA
    rts
"""

MMC2 = r"""
; MMC2 probe: 128 KB PRG (16 x 8 KB, number at the start of each), code in the last 8 KB.
finish_ctrl = $00
.org $E000
reset:
    sei
    cld
    ldx #$FF
    txs
    jsr init_system
    jsr start_report
;---- 1: $A000 selects the 8 KB bank at $8000
    lda #1
    sta test_num
    ldy #0
@bank:
    sty $A000
    cpy $8000
    jsr ok
    iny
    cpy #13
    bne @bank
;---- 2: $A000-$FFFF are the last three banks
    lda #2
    sta test_num
    lda $A000
    cmp #13
    jsr ok
    lda $C000
    cmp #14
    jsr ok
""" + LATCH_TESTS + r"""
msg_head: .db "MMC2 PROBE", 0
nmi:
irq:
    rti
"""

MMC4 = r"""
; MMC4 probe: 128 KB PRG (8 x 16 KB, number at the start of each), code in the last 16 KB.
finish_ctrl = $00
.org $C000
reset:
    sei
    cld
    ldx #$FF
    txs
    jsr init_system
    jsr start_report
;---- 1: $A000 selects the 16 KB bank at $8000
    lda #1
    sta test_num
    ldy #0
@bank:
    sty $A000
    cpy $8000
    jsr ok
    iny
    cpy #7
    bne @bank
;---- 2: PRG RAM at $6000
    lda #2
    sta test_num
    lda #$3C
    sta $6100
    lda $6100
    cmp #$3C
    jsr ok
""" + LATCH_TESTS + r"""
msg_head: .db "MMC4 PROBE", 0
nmi:
irq:
    rti
"""

# Color Dreams (11) and GxROM (66) switch all 32 KB at once, so every bank holds the same code;
# the build stamps each bank's number at $FFF0. Writes use a table of equal values (bus conflicts).
DISCRETE32 = r"""
finish_ctrl = $00
.org $8000
reset:
    sei
    cld
    ldx #$FF
    txs
    jsr init_system
    jsr start_report
;---- 1: each 32 KB PRG bank
    lda #1
    sta test_num
    ldy #0
@prg:
    lda prg_values,y
    sta prg_values,y
    cpy sig
    jsr ok
    iny
    cpy #4
    bne @prg
    lda prg_values
    sta prg_values
;---- 2: each 8 KB CHR bank (number at $0FF0)
    lda #2
    sta test_num
    ldy #0
@chr:
    lda chr_values,y
    sta chr_values,y
    lda #$0F
    ldx #$F0
    jsr ppu_addr
    lda PPUDATA
    lda PPUDATA
    sta tmp
    cpy tmp
    jsr ok
    iny
    cpy #4
    bne @chr
    lda chr_values
    sta chr_values
    jmp pass
nmi:
irq:
    rti
"""

COLOR_DREAMS = DISCRETE32 + r"""
prg_values: .db $00, $01, $02, $03
chr_values: .db $00, $10, $20, $30
msg_head: .db "COLOR DREAMS PROBE", 0
"""

GXROM = DISCRETE32 + r"""
prg_values: .db $00, $10, $20, $30
chr_values: .db $00, $01, $02, $03
msg_head: .db "GXROM PROBE", 0
"""

FME7 = r"""
; FME-7 probe: 128 KB PRG (16 x 8 KB, number at the start of each), 32 KB CHR (32 x 1 KB, number
; at $3F0 of each), PRG RAM or ROM at $6000, and the CPU-cycle IRQ counter.
irq_flag = $41
finish_ctrl = $00
.org $E000
reset:
    sei
    cld
    ldx #$FF
    txs
    jsr init_system
    lda #8
    sta $8000
    lda #$C0            ; $6000: RAM, enabled
    sta $A000
    jsr start_report
;---- 1: command 9 selects $8000
    lda #1
    sta test_num
    ldy #0
@c9:
    lda #9
    sta $8000
    sty $A000
    cpy $8000
    jsr ok
    iny
    cpy #15
    bne @c9
;---- 2: commands A and B select $A000 and $C000
    lda #2
    sta test_num
    lda #$0A
    sta $8000
    lda #6
    sta $A000
    lda $A000
    cmp #6
    jsr ok
    lda #$0B
    sta $8000
    lda #11
    sta $A000
    lda $C000
    cmp #11
    jsr ok
;---- 3: command 8 maps ROM at $6000, then RAM again with its contents intact
    lda #3
    sta test_num
    lda #$3C
    sta $6100
    lda #8
    sta $8000
    lda #5
    sta $A000           ; ROM bank 5
    lda $6000
    cmp #5
    jsr ok
    lda #$77
    sta $6100           ; ignored: it's ROM
    lda #8
    sta $8000
    lda #$C0
    sta $A000
    lda $6100
    cmp #$3C
    jsr ok
;---- 4: command 4 (1 KB at $1000)
    lda #4
    sta test_num
    ldy #8
@c4:
    lda #4
    sta $8000
    sty $A000
    lda #$13
    ldx #$F0
    jsr ppu_addr
    lda PPUDATA
    lda PPUDATA
    sta tmp
    cpy tmp
    jsr ok
    iny
    cpy #32
    bne @c4
    ldy #0
@restore:
    sty $8000
    sty $A000
    iny
    cpy #8
    bne @restore
;---- 5: command C mirroring (0 vertical, 1 horizontal)
    lda #5
    sta test_num
    lda #$0C
    sta $8000
    lda #0
    sta $A000
    lda #$20
    ldx #$05
    jsr ppu_addr
    lda #$5A
    sta PPUDATA
    lda #$28
    ldx #$05
    jsr ppu_addr
    lda PPUDATA
    lda PPUDATA
    cmp #$5A
    jsr ok
    lda #$0C
    sta $8000
    lda #1
    sta $A000
    lda #$24
    ldx #$05
    jsr ppu_addr
    lda PPUDATA
    lda PPUDATA
    cmp #$5A
    jsr ok
;---- 6: the IRQ counter fires once it counts down through zero (2,000 CPU cycles here)
    lda #6
    sta test_num
    lda #$0E
    sta $8000
    lda #<2000
    sta $A000
    lda #$0F
    sta $8000
    lda #>2000
    sta $A000
    lda #$0D
    sta $8000
    lda #$81            ; counter on, IRQ on
    sta $A000
    ldx #0
    ldy #0
    cli
@wait:                  ; 10 cycles a turn
    lda irq_flag
    bne @fired
    inx
    bne @wait
    iny
    bne @wait
    jmp fail
@fired:
    sei
    cpy #0
    jsr ok
    cpx #150            ; ~200 turns expected
    bcc @bad
    cpx #250
    bcs @bad
    jmp pass
@bad:
    jmp fail

irq:
    pha
    lda #$0D
    sta $8000
    lda #0
    sta $A000           ; acknowledge, IRQ and counter off
    inc irq_flag
    pla
    rti
nmi:
    rti
msg_head: .db "FME-7 PROBE", 0
"""


def build(Assembler, ines, nes_chr_bank, read, vectors):
    common = read('common.s')
    report = read('report.s')
    chr8 = nes_chr_bank()
    out = {}

    # MMC1 and UxROM: 8 switchable 16 KB banks with signatures, code in the last one.
    for name, src, mapper in (('mmc1_probe.nes', MMC1, 1), ('uxrom_probe.nes', UXROM, 2)):
        fixed = Assembler().assemble(src + common + report + font_db(chr8) + vectors(), 0xC000, 0x4000)
        banks = []
        for b in range(7):
            data = bytearray([0xFF] * 0x4000)
            data[0] = b
            data[1] = b ^ 0xA5
            banks.append(bytes(data))
        out[name] = ines(banks + [fixed], [], mapper=mapper, vertical=True)

    # CNROM: four CHR banks, each the standard tiles plus a signature at $0FF0.
    prg = Assembler().assemble(CNROM + common + report + '\nfont_chr:\n' + vectors(), 0x8000, 0x8000)
    chrs = []
    for b in range(4):
        c = bytearray(chr8)
        c[0x0FF0] = b
        chrs.append(bytes(c))
    out['cnrom_probe.nes'] = ines([prg[:0x4000], prg[0x4000:]], chrs, mapper=3, vertical=True)

    # MMC3: 16 x 8 KB PRG (last one holds the code), 64 x 1 KB CHR.
    code = Assembler().assemble(MMC3 + common + report + '\nfont_chr:\n' + vectors(), 0xE000, 0x2000)
    prg8 = []
    for b in range(15):
        d = bytearray([0xFF] * 0x2000)
        d[0] = b
        prg8.append(bytes(d))
    prg8.append(code)
    chr1k = []
    for b in range(64):
        if b < 8:
            c = bytearray(chr8[b * 0x400:(b + 1) * 0x400])
        else:
            c = bytearray(0x400)
        c[0x3F0] = b
        chr1k.append(bytes(c))
    prg16 = [prg8[i] + prg8[i + 1] for i in range(0, 16, 2)]
    chr8k = [b''.join(chr1k[i:i + 8]) for i in range(0, 64, 8)]
    out['mmc3_probe.nes'] = ines(prg16, chr8k, mapper=4, vertical=True)

    # MMC2 / MMC4: 8 x 4 KB CHR, each the standard background tiles plus its number at $0FF0.
    chr4k = []
    for b in range(8):
        c = bytearray(chr8[:0x1000])
        c[0x0FF0] = b
        chr4k.append(bytes(c))
    chr_latch = [chr4k[i] + chr4k[i + 1] for i in range(0, 8, 2)]
    src = MMC2.replace('FD9_EXPECT', '2')
    code = Assembler().assemble(src + common + report + '\nfont_chr:\n' + vectors(), 0xE000, 0x2000)
    prg8 = []
    for b in range(15):
        d = bytearray([0xFF] * 0x2000)
        d[0] = b
        prg8.append(bytes(d))
    prg8.append(code)
    out['mmc2_probe.nes'] = ines([prg8[i] + prg8[i + 1] for i in range(0, 16, 2)], chr_latch, mapper=9, vertical=True)

    src = MMC4.replace('FD9_EXPECT', '1')
    fixed = Assembler().assemble(src + common + report + '\nfont_chr:\n' + vectors(), 0xC000, 0x4000)
    banks = []
    for b in range(7):
        d = bytearray([0xFF] * 0x4000)
        d[0] = b
        banks.append(bytes(d))
    out['mmc4_probe.nes'] = ines(banks + [fixed], chr_latch, mapper=10, vertical=True, battery=True)

    # Color Dreams / GxROM: 4 x 32 KB PRG (same code, number at $FFF0), 4 x 8 KB CHR.
    chrs = []
    for b in range(4):
        c = bytearray(chr8)
        c[0x0FF0] = b
        chrs.append(bytes(c))
    for name, src, mapper in (('colordreams_probe.nes', COLOR_DREAMS, 11), ('gxrom_probe.nes', GXROM, 66)):
        code = Assembler().assemble(src + common + report + '\nfont_chr:\n.org $FFF0\nsig: .db $00\n' + vectors(),
                                    0x8000, 0x8000)
        prg16 = []
        for b in range(4):
            d = bytearray(code)
            d[0x7FF0] = b
            prg16 += [bytes(d[:0x4000]), bytes(d[0x4000:])]
        out[name] = ines(prg16, chrs, mapper=mapper, vertical=True)

    # FME-7: 16 x 8 KB PRG (code in the last), 32 x 1 KB CHR.
    code = Assembler().assemble(FME7 + common + report + '\nfont_chr:\n' + vectors(), 0xE000, 0x2000)
    prg8 = []
    for b in range(15):
        d = bytearray([0xFF] * 0x2000)
        d[0] = b
        prg8.append(bytes(d))
    prg8.append(code)
    chr1k = []
    for b in range(32):
        c = bytearray(chr8[b * 0x400:(b + 1) * 0x400]) if b < 8 else bytearray(0x400)
        c[0x3F0] = b
        chr1k.append(bytes(c))
    out['fme7_probe.nes'] = ines([prg8[i] + prg8[i + 1] for i in range(0, 16, 2)],
                                 [b''.join(chr1k[i:i + 8]) for i in range(0, 32, 8)], mapper=69, vertical=True,
                                 battery=True)
    return out
