"""Mapper probe ROMs (our own): MMC1, UxROM, CNROM, MMC3. Imported by Tools/build_test_roms.py.

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
    return out
