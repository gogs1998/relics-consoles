#!/usr/bin/env python3
"""Builds our own SNES and Mega Drive test ROMs into TestROMs/build/ares_*.

Run from the repo root: python3 Tools/build_ares_roms.py
Both programs are our own machine code, hand-assembled below (65816 + SPC700 for the SNES,
68000 for the Mega Drive). No third-party ROMs, no BIOS, no boot logos.

ares_snes_demo.sfc (32 KiB LoROM, valid internal header with checksum/complement):
  1. Native mode, forced blank, then uploads a small SPC700 program to audio RAM $0200 through the
     standard boot-ROM upload protocol (ports $2140-$2143), and starts it. The SPC700 program
     sets up a 16-sample square-wave BRR sample and keys on voice 0: a steady ~2 kHz tone.
  2. Enables auto-joypad reading. Every frame (in vertical blank) it reads $4218/$4219 (after the auto-read finishes) and sets the
     backdrop colour (CGRAM 0): blue with no button held, red while any button is held.

ares_md_demo.md (8 KiB, "SEGA" at $100, 8 KiB save RAM; TMSS is not needed by the emulator):
  1. Sets the VDP to mode 5, H40 (320 wide), display on, backdrop = palette entry 0.
  2. Bumps a boot counter in battery save RAM (odd bytes at $200001: byte 0 = $42 marker,
     byte 1 = counter), so battery saves can be checked.
  3. Starts a ~440 Hz square tone on PSG channel 0 (the 68000 writes the PSG at $C00011).
  4. Every frame (in vertical blank) reads controller port 1 (TH high) and writes CRAM entry 0:
     blue with no button, red while B is held.
"""
import os
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'TestROMs', 'build')


class Asm:
    """Bytes with labels and fix-ups (relative branches resolved at the end)."""

    def __init__(self, origin):
        self.origin = origin
        self.code = bytearray()
        self.labels = {}
        self.fixups = []  # (offset, label, kind)

    @property
    def pc(self):
        return self.origin + len(self.code)

    def label(self, name):
        self.labels[name] = self.pc

    def b(self, *values):
        for v in values:
            self.code.append(v & 0xFF)

    def w16le(self, v):
        self.b(v, v >> 8)

    def w16be(self, v):
        self.b(v >> 8, v)

    def w32be(self, v):
        self.b(v >> 24, v >> 16, v >> 8, v)

    def rel8(self, name):
        """One-byte branch displacement from the end of the displacement byte (65816, SPC700)."""
        self.fixups.append((len(self.code), name, 'rel8'))
        self.b(0)

    def rel8_68k(self, opcode, name):
        """68000 Bcc.s: displacement from the address after the opcode word."""
        self.fixups.append((len(self.code), name, '68k'))
        self.b(opcode, 0)

    def abs16(self, name):
        self.fixups.append((len(self.code), name, 'abs16'))
        self.b(0, 0)

    def resolve(self):
        for offset, name, kind in self.fixups:
            target = self.labels[name]
            if kind == 'rel8':
                d = target - (self.origin + offset + 1)
                assert -128 <= d <= 127, name
                self.code[offset] = d & 0xFF
            elif kind == '68k':
                d = target - (self.origin + offset + 2)
                assert -128 <= d <= 127 and d != 0, name
                self.code[offset + 1] = d & 0xFF
            elif kind == 'abs16':
                self.code[offset] = target & 0xFF
                self.code[offset + 1] = (target >> 8) & 0xFF
        return bytes(self.code)


# ---------------------------------------------------------------- SNES

def spc_program():
    """SPC700 code + BRR sample + sample directory, uploaded to $0200..$0403."""
    a = Asm(0x0200)

    def dsp(reg, val):  # mov $F2,#reg ; mov $F3,#val
        a.b(0x8F, reg, 0xF2, 0x8F, val, 0xF3)

    dsp(0x6C, 0x20)  # FLG: echo writes off, unmuted, noise clock 0
    dsp(0x5D, 0x04)  # DIR: sample directory at $0400
    dsp(0x04, 0x00)  # V0SRCN = sample 0
    dsp(0x00, 0x7F)  # V0VOLL
    dsp(0x01, 0x7F)  # V0VOLR
    dsp(0x02, 0x00)  # V0PITCHL
    dsp(0x03, 0x10)  # V0PITCHH: pitch $1000 = 32 kHz / 16 samples = 2 kHz
    dsp(0x05, 0x00)  # V0ADSR1: ADSR off, use GAIN
    dsp(0x07, 0x7F)  # V0GAIN: direct, maximum
    dsp(0x0C, 0x7F)  # MVOLL
    dsp(0x1C, 0x7F)  # MVOLR
    dsp(0x2C, 0x00)  # EVOLL
    dsp(0x3C, 0x00)  # EVOLR
    dsp(0x3D, 0x00)  # NON
    dsp(0x4D, 0x00)  # EON
    dsp(0x5C, 0x00)  # KOFF
    dsp(0x4C, 0x01)  # KON voice 0
    a.label('idle')
    a.b(0x2F)
    a.rel8('idle')   # bra idle
    code = a.resolve()
    blob = bytearray(0x0404 - 0x0200)
    blob[0:len(code)] = code
    # BRR block at $0300: range 11, filter 0, loop + end; 8 samples of +7, 8 of -8 (a square wave).
    blob[0x100:0x109] = bytes([0xB3, 0x77, 0x77, 0x77, 0x77, 0x88, 0x88, 0x88, 0x88])
    # Directory entry 0 at $0400: start $0300, loop $0300.
    blob[0x200:0x204] = bytes([0x00, 0x03, 0x00, 0x03])
    return bytes(blob)


def snes_rom():
    spc = spc_program()
    a = Asm(0x8000)
    a.label('reset')
    a.b(0x78)              # sei
    a.b(0x18, 0xFB)        # clc ; xce   (native mode)
    a.b(0xE2, 0x20)        # sep #$20   (8-bit A)
    a.b(0xC2, 0x10)        # rep #$10   (16-bit X/Y)
    a.b(0xA2); a.w16le(0x01FF)  # ldx #$01FF
    a.b(0x9A)              # txs
    a.b(0xA9, 0x8F, 0x8D, 0x00, 0x21)  # lda #$8F ; sta $2100 (forced blank)
    a.b(0x9C, 0x00, 0x42)  # stz $4200
    a.b(0x9C, 0x2C, 0x21)  # stz $212C (no layers: only the backdrop shows)
    a.b(0x9C, 0x30, 0x21)  # stz $2130
    a.b(0x9C, 0x31, 0x21)  # stz $2131 (no colour math)

    # --- upload the SPC700 program (boot-ROM protocol) ---
    a.label('w1'); a.b(0xAD, 0x40, 0x21, 0xC9, 0xAA, 0xD0); a.rel8('w1')  # wait port0 = $AA
    a.label('w2'); a.b(0xAD, 0x41, 0x21, 0xC9, 0xBB, 0xD0); a.rel8('w2')  # wait port1 = $BB
    a.b(0xA9, 0x00, 0x8D, 0x42, 0x21)  # destination $0200
    a.b(0xA9, 0x02, 0x8D, 0x43, 0x21)
    a.b(0xA9, 0x01, 0x8D, 0x41, 0x21)  # command: transfer
    a.b(0xA9, 0xCC, 0x8D, 0x40, 0x21)  # kick
    a.label('w3'); a.b(0xAD, 0x40, 0x21, 0xC9, 0xCC, 0xD0); a.rel8('w3')
    a.b(0xA2); a.w16le(0x0000)         # ldx #0
    a.label('up')
    a.b(0xBD); a.abs16('spc')          # lda spc,x
    a.b(0x8D, 0x41, 0x21)              # sta $2141
    a.b(0x8A)                          # txa (low byte of the index)
    a.b(0x8D, 0x40, 0x21)              # sta $2140
    a.label('w4'); a.b(0xCD, 0x40, 0x21, 0xD0); a.rel8('w4')  # wait for the echo
    a.b(0xE8)                          # inx
    a.b(0xE0); a.w16le(len(spc))       # cpx #len
    a.b(0xD0); a.rel8('up')
    a.b(0xA9, 0x00, 0x8D, 0x42, 0x21)  # entry point $0200
    a.b(0xA9, 0x02, 0x8D, 0x43, 0x21)
    a.b(0x9C, 0x41, 0x21)              # command 0: jump
    a.b(0x8A, 0x1A)                    # txa ; inc a  (last index + 2)
    assert (len(spc) + 1) & 0xFF != 0
    a.b(0x8D, 0x40, 0x21)
    a.label('w5'); a.b(0xCD, 0x40, 0x21, 0xD0); a.rel8('w5')

    a.b(0xA9, 0x01, 0x8D, 0x00, 0x42)  # lda #$01 ; sta $4200 (auto-joypad on)

    # --- per frame ---
    a.label('frame')
    a.label('vb'); a.b(0xAD, 0x12, 0x42, 0x10); a.rel8('vb')        # wait vblank ($4212 bit 7)
    a.label('js'); a.b(0xAD, 0x12, 0x42, 0x29, 0x01, 0xF0); a.rel8('js')  # wait auto-read start
    a.label('jb'); a.b(0xAD, 0x12, 0x42, 0x29, 0x01, 0xD0); a.rel8('jb')  # wait auto-read done
    a.b(0x9C, 0x21, 0x21)              # stz $2121 (CGRAM address 0)
    a.b(0xAD, 0x19, 0x42)              # lda $4219
    a.b(0x0D, 0x18, 0x42)              # ora $4218
    a.b(0xF0); a.rel8('nobtn')         # beq nobtn
    a.b(0xA9, 0x1F, 0x8D, 0x22, 0x21)  # red: $001F
    a.b(0xA9, 0x00, 0x8D, 0x22, 0x21)
    a.b(0x80); a.rel8('show')          # bra show
    a.label('nobtn')
    a.b(0xA9, 0x00, 0x8D, 0x22, 0x21)  # blue: $7C00
    a.b(0xA9, 0x7C, 0x8D, 0x22, 0x21)
    a.label('show')
    a.b(0xA9, 0x0F, 0x8D, 0x00, 0x21)  # screen on, full brightness
    a.label('ve'); a.b(0xAD, 0x12, 0x42, 0x30); a.rel8('ve')        # wait for vblank to end
    a.b(0x80); a.rel8('frame')

    a.label('spc')
    a.code += spc
    code = a.resolve()

    rom = bytearray(0x8000)
    rom[0:len(code)] = code
    title = b'FOLDBACK SNES TEST'.ljust(21, b' ')
    rom[0x7FC0:0x7FD5] = title
    rom[0x7FD5] = 0x20   # LoROM, slow
    rom[0x7FD6] = 0x00   # ROM only
    rom[0x7FD7] = 0x05   # 32 KiB
    rom[0x7FD8] = 0x00   # no RAM
    rom[0x7FD9] = 0x01   # North America (NTSC)
    rom[0x7FDA] = 0x00
    rom[0x7FDB] = 0x00
    struct.pack_into('<HH', rom, 0x7FDC, 0xFFFF, 0x0000)
    struct.pack_into('<H', rom, 0x7FFC, 0x8000)  # emulation-mode reset vector
    for v in (0x7FEA, 0x7FEE, 0x7FFA, 0x7FFE):    # NMI/IRQ vectors (unused): point at reset
        struct.pack_into('<H', rom, v, 0x8000)
    checksum = sum(rom) & 0xFFFF
    struct.pack_into('<HH', rom, 0x7FDC, checksum ^ 0xFFFF, checksum)
    return bytes(rom)


# ---------------------------------------------------------------- Mega Drive

def md_rom():
    a = Asm(0x200)
    a.label('start')
    a.b(0x46, 0xFC); a.w16be(0x2700)               # move.w #$2700,sr
    a.b(0x41, 0xF9); a.w32be(0xC00004)             # lea $C00004,a0 (VDP control)
    a.b(0x43, 0xF9); a.w32be(0xC00000)             # lea $C00000,a1 (VDP data)
    for reg in (0x8004, 0x8144, 0x8700, 0x8C81, 0x8F02):
        a.b(0x30, 0xBC); a.w16be(reg)              # move.w #reg,(a0)
    for psg in (0x8E, 0x0F, 0x90, 0xBF, 0xDF, 0xFF):  # ch0 period $0FE, ch0 max volume, ch1-3 off
        a.b(0x13, 0xFC); a.w16be(psg); a.w32be(0xC00011)  # move.b #psg,$C00011
    # Save RAM (odd bytes at $200001-$203FFF): byte 0 = $42 marker, byte 1 = boot counter.
    a.b(0x13, 0xFC); a.w16be(0x01); a.w32be(0xA130F1)    # move.b #1,$A130F1 (map save RAM)
    a.b(0x14, 0x39); a.w32be(0x200003)                   # move.b $200003,d2
    a.b(0x52, 0x02)                                      # addq.b #1,d2
    a.b(0x13, 0xC2); a.w32be(0x200003)                   # move.b d2,$200003
    a.b(0x13, 0xFC); a.w16be(0x42); a.w32be(0x200001)    # move.b #$42,$200001
    a.b(0x13, 0xFC); a.w16be(0x40); a.w32be(0xA10009)    # port 1 control: TH is an output
    a.b(0x13, 0xFC); a.w16be(0x40); a.w32be(0xA10003)    # TH high
    a.label('loop')
    a.label('vb1')
    a.b(0x30, 0x10)                                # move.w (a0),d0
    a.b(0x08, 0x00); a.w16be(3)                    # btst #3,d0 (vblank)
    a.rel8_68k(0x67, 'vb1')                        # beq vb1
    a.b(0x12, 0x39); a.w32be(0xA10003)             # move.b $A10003,d1
    a.b(0x20, 0xBC); a.w32be(0xC0000000)           # move.l #$C0000000,(a0)  (CRAM write, entry 0)
    a.b(0x08, 0x01); a.w16be(4)                    # btst #4,d1 (B, active low)
    a.rel8_68k(0x67, 'pressed')                    # beq pressed
    a.b(0x32, 0xBC); a.w16be(0x0E00)               # move.w #$0E00,(a1)  blue
    a.rel8_68k(0x60, 'vb2')                        # bra vb2
    a.label('pressed')
    a.b(0x32, 0xBC); a.w16be(0x000E)               # move.w #$000E,(a1)  red
    a.label('vb2')
    a.b(0x30, 0x10)                                # move.w (a0),d0
    a.b(0x08, 0x00); a.w16be(3)                    # btst #3,d0
    a.rel8_68k(0x66, 'vb2')                        # bne vb2
    a.rel8_68k(0x60, 'loop')                       # bra loop
    a.label('rte')
    a.b(0x4E, 0x73)                                # rte (all other exception vectors)
    code = a.resolve()
    rte = a.labels['rte']

    rom = bytearray(0x2000)
    rom[0x200:0x200 + len(code)] = code
    struct.pack_into('>II', rom, 0, 0x01000000, 0x200)  # initial SSP, initial PC
    for v in range(2, 64):
        struct.pack_into('>I', rom, v * 4, rte)

    def text(offset, s, length):
        rom[offset:offset + length] = s.encode('ascii').ljust(length, b' ')

    text(0x100, 'SEGA MEGA DRIVE', 16)   # the console's cartridge check string
    text(0x110, '(C)FOLDBACK 2026', 16)
    text(0x120, 'FOLDBACK MD TEST', 48)
    text(0x150, 'FOLDBACK MD TEST', 48)
    text(0x180, 'GM 00000000-00', 14)
    text(0x190, 'J6', 16)
    struct.pack_into('>IIII', rom, 0x1A0, 0, len(rom) - 1, 0xFF0000, 0xFFFFFF)
    rom[0x1B0:0x1B4] = b'RA\xF8\x20'      # battery save RAM, odd bytes
    struct.pack_into('>II', rom, 0x1B4, 0x200001, 0x203FFF)
    text(0x1F0, 'JUE', 16)
    checksum = sum(struct.unpack_from('>%dH' % ((len(rom) - 0x200) // 2), rom, 0x200)) & 0xFFFF
    struct.pack_into('>H', rom, 0x18E, checksum)
    return bytes(rom)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, data in (('ares_snes_demo.sfc', snes_rom()), ('ares_md_demo.md', md_rom())):
        with open(os.path.join(OUT, name), 'wb') as f:
            f.write(data)
        print(f'wrote TestROMs/build/{name} ({len(data)} bytes)')


if __name__ == '__main__':
    main()
