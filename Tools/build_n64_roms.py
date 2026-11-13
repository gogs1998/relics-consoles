#!/usr/bin/env python3
"""Builds our own Nintendo 64 test cartridge into TestROMs/build/n64_demo.z64.

Run from the repo root: python3 Tools/build_n64_roms.py
Everything is our own MIPS code, encoded by the tiny assembler below. No third-party ROMs, no
Nintendo IPL3/CIC boot code, no PIF ROM. The emulator's HLE boot stands in for the PIF ROM and then
runs whatever sits at cartridge 0x40-0xFFF (normally the IPL3): here that is our own 15-instruction
stub, the rest of the area is zero.

Layout (big-endian .z64):
  0x0000  header: PI config 0x80371240, entry 0x80000400, name "FOLDBACK N64 TEST", game code
          "NZFE" (not a real title), NTSC. The CRC fields are left zero (nothing checks them).
  0x0040  boot stub: PI DMA of the program image from cartridge 0x1000 to RDRAM 0x400, then jumps
          to 0x80000400.
  0x1000  program image (code, PIF command blocks, a square-wave audio buffer), padded to 1 MiB.

The program:
  1. Sets the VI to NTSC 320x240, 16-bit, framebuffer at RDRAM 0x100000.
  2. Reads EEPROM block 0 and Controller Pak bytes 0x7FE0-0x7FFF through the PIF. Markers "FB64" /
     "PAK!" found there set the flags at 0xA0000308 / 0xA000030C (battery saves can be checked).
  3. Every vertical interrupt: counts the frame (0xA0000300), reads controller 1 (buttons, stick:
     0xA0000304 = buttons << 16 | x << 8 | y), keeps the audio interface fed with a 400 Hz square
     wave at 32 kHz, fills the screen (dark blue, or dark green once the EEPROM marker was seen)
     and draws a 64x64 square: white, red while A is held, green while B, blue while Z, yellow while
     a C button is held, moved by the analog stick (x / 4, y / 4 pixels).
  4. The first time Start is pressed it writes "FB64OK!!" to EEPROM block 0 and "PAK!" + 28 bytes to
     the Controller Pak at 0x7FE0, and sets 0xA0000310 to 1.
"""
import os
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'TestROMs', 'build')

REGS = {n: i for i, n in enumerate(
    'zero at v0 v1 a0 a1 a2 a3 t0 t1 t2 t3 t4 t5 t6 t7 s0 s1 s2 s3 s4 s5 s6 s7 t8 t9 k0 k1 gp sp fp ra'.split())}


class MIPS:
    """A tiny big-endian MIPS I assembler with labels (branch delay slots are the caller's job)."""

    def __init__(self, origin):
        self.origin = origin
        self.words = []
        self.labels = {}
        self.fixups = []   # (index, kind, label)

    def here(self):
        return self.origin + 4 * len(self.words)

    def label(self, name):
        self.labels[name] = self.here()

    def _r(self, op, rs, rt, rd, sh, fn):
        self.words.append((op << 26) | (REGS[rs] << 21) | (REGS[rt] << 16) | (REGS[rd] << 11) | (sh << 6) | fn)

    def _i(self, op, rs, rt, imm):
        self.words.append((op << 26) | (REGS[rs] << 21) | (REGS[rt] << 16) | (imm & 0xFFFF))

    # ALU
    def addu(self, d, s, t): self._r(0, s, t, d, 0, 0x21)
    def subu(self, d, s, t): self._r(0, s, t, d, 0, 0x23)
    def and_(self, d, s, t): self._r(0, s, t, d, 0, 0x24)
    def or_(self, d, s, t): self._r(0, s, t, d, 0, 0x25)
    def slt(self, d, s, t): self._r(0, s, t, d, 0, 0x2A)
    def sll(self, d, t, sh): self._r(0, 'zero', t, d, sh, 0x00)
    def srl(self, d, t, sh): self._r(0, 'zero', t, d, sh, 0x02)
    def sra(self, d, t, sh): self._r(0, 'zero', t, d, sh, 0x03)
    def jr(self, s): self._r(0, s, 'zero', 'zero', 0, 0x08)
    def nop(self): self.words.append(0)
    def addiu(self, t, s, imm): self._i(0x09, s, t, imm)
    def slti(self, t, s, imm): self._i(0x0A, s, t, imm)
    def andi(self, t, s, imm): self._i(0x0C, s, t, imm)
    def ori(self, t, s, imm): self._i(0x0D, s, t, imm)
    def lui(self, t, imm): self._i(0x0F, 'zero', t, imm)

    def li(self, t, value):
        value &= 0xFFFFFFFF
        if value >> 16:
            self.lui(t, value >> 16)
            if value & 0xFFFF:
                self.ori(t, t, value & 0xFFFF)
        else:
            self.ori(t, 'zero', value)

    def move(self, d, s): self.addu(d, s, 'zero')

    # memory
    def lb(self, t, off, s): self._i(0x20, s, t, off)
    def lbu(self, t, off, s): self._i(0x24, s, t, off)
    def lhu(self, t, off, s): self._i(0x25, s, t, off)
    def lw(self, t, off, s): self._i(0x23, s, t, off)
    def sb(self, t, off, s): self._i(0x28, s, t, off)
    def sh(self, t, off, s): self._i(0x29, s, t, off)
    def sw(self, t, off, s): self._i(0x2B, s, t, off)

    # control flow (each followed by a nop in the delay slot)
    def _branch(self, op, s, t, label):
        self.fixups.append((len(self.words), 'b', label))
        self._i(op, s, t, 0)
        self.nop()

    def beq(self, s, t, label): self._branch(0x04, s, t, label)
    def bne(self, s, t, label): self._branch(0x05, s, t, label)

    def _jump(self, op, label):
        self.fixups.append((len(self.words), 'j', label))
        self.words.append(op << 26)
        self.nop()

    def j(self, label): self._jump(0x02, label)
    def jal(self, label): self._jump(0x03, label)

    def assemble(self):
        for index, kind, label in self.fixups:
            target = self.labels[label]
            if kind == 'b':
                off = (target - (self.origin + 4 * index + 4)) >> 2
                assert -0x8000 <= off < 0x8000
                self.words[index] |= off & 0xFFFF
            else:
                self.words[index] |= (target >> 2) & 0x03FFFFFF
        return b''.join(struct.pack('>I', w) for w in self.words)


# RDRAM (physical) layout
CODE = 0x400
BLK_PAD = 0x8000        # controller read
BLK_EEP_RD = 0x8040
BLK_EEP_WR = 0x8080
BLK_PAK_RD = 0x80C0
BLK_PAK_WR = 0x8100
AUDIO = 0x9000
AUDIO_SAMPLES = 800     # 10 periods of 400 Hz at 32 kHz
FB = 0x100000
DEBUG = 0xA0000300

VI_CLOCK_NTSC = 48681812
AUDIO_RATE = 32000


def pif_blocks():
    """PIF RAM command blocks (64 bytes each, byte 63 = 1: process the commands)."""
    def block(cmds):
        b = bytearray(64)
        b[:len(cmds)] = cmds
        b[len(cmds)] = 0xFE
        b[63] = 0x01
        return bytes(b)
    pad = block(bytes([0x01, 0x04, 0x01]) + b'\xff' * 4)
    # channels 1-3 skipped (0x00), channel 4 = the cartridge's EEPROM
    eep_rd = block(bytes([0x01, 0x04, 0x01]) + b'\xff' * 4 + b'\x00\x00\x00'
                   + bytes([0x02, 0x08, 0x04, 0x00]) + b'\xff' * 8)
    eep_wr = block(bytes([0x01, 0x04, 0x01]) + b'\xff' * 4 + b'\x00\x00\x00'
                   + bytes([0x0A, 0x01, 0x05, 0x00]) + b'FB64OK!!' + b'\xff')
    addr = 0x7FE0   # address CRC bits left zero (the emulator ignores them)
    pak_rd = block(bytes([0x03, 0x21, 0x02, addr >> 8, addr & 0xE0]) + b'\xff' * 33)
    pak_wr = block(bytes([0x23, 0x01, 0x03, addr >> 8, addr & 0xE0]) + b'PAK!' + bytes(range(28)) + b'\xff')
    return pad, eep_rd, eep_wr, pak_rd, pak_wr


def audio_buffer():
    out = bytearray()
    for i in range(AUDIO_SAMPLES):
        s = 0x2000 if (i % 80) < 40 else -0x2000
        out += struct.pack('>hh', s, s)
    return bytes(out)


def boot_stub():
    a = MIPS(0xA4000040)
    image_len = 0xA000
    a.lui('t0', 0xA460)            # PI
    a.li('t1', CODE)
    a.sw('t1', 0x00, 't0')         # PI_DRAM_ADDR
    a.li('t1', 0x10001000)
    a.sw('t1', 0x04, 't0')         # PI_CART_ADDR
    a.li('t1', image_len - 1)
    a.sw('t1', 0x0C, 't0')         # PI_WR_LEN: cartridge → RDRAM
    a.label('wait')
    a.lw('t2', 0x10, 't0')         # PI_STATUS
    a.andi('t2', 't2', 3)
    a.bne('t2', 'zero', 'wait')
    a.li('t3', 0x80000000 | CODE)
    a.jr('t3')
    a.nop()
    return a.assemble(), image_len


def program():
    a = MIPS(0x80000000 | CODE)
    a.li('gp', DEBUG)
    a.sw('zero', 0x00, 'gp')
    a.sw('zero', 0x04, 'gp')
    a.sw('zero', 0x08, 'gp')
    a.sw('zero', 0x0C, 'gp')
    a.sw('zero', 0x10, 'gp')
    # VI: NTSC 320x240, 16-bit
    a.lui('s0', 0xA440)
    for reg, value in [(0x04, FB), (0x08, 320), (0x0C, 2), (0x14, 0x03E52239), (0x18, 0x20D),
                       (0x1C, 0xC15), (0x20, 0x0C150C15), (0x24, 0x006C02EC), (0x28, 0x002501FF),
                       (0x2C, 0x000E0204), (0x30, 0x200), (0x34, 0x400), (0x00, 0x320E)]:
        a.li('t0', value)
        a.sw('t0', reg, 's0')
    # AI: 32 kHz, 16-bit, DMA on
    a.lui('t0', 0xA450)
    a.li('t1', VI_CLOCK_NTSC // AUDIO_RATE - 1)
    a.sw('t1', 0x10, 't0')         # AI_DACRATE
    a.li('t1', 15)
    a.sw('t1', 0x14, 't0')         # AI_BITRATE
    a.li('t1', 1)
    a.sw('t1', 0x08, 't0')         # AI_CONTROL
    # saved markers
    a.li('a0', BLK_EEP_RD)
    a.jal('si_exchange')
    a.li('t0', 0xA0000000 | BLK_EEP_RD)
    # EEPROM read response: bytes 14..21 of the block (after 7 + 3 + 4 bytes); compare "FB64"
    a.move('s5', 'zero')
    for i, ch in enumerate(b'FB64'):
        a.lbu('t1', 14 + i, 't0')
        a.li('t2', ch)
        a.bne('t1', 't2', 'no_eep')
    a.li('s5', 1)
    a.label('no_eep')
    a.sw('s5', 0x08, 'gp')
    a.li('a0', BLK_PAK_RD)
    a.jal('si_exchange')
    a.li('t0', 0xA0000000 | BLK_PAK_RD)
    a.move('s7', 'zero')
    for i, ch in enumerate(b'PAK!'):
        a.lbu('t1', 5 + i, 't0')
        a.li('t2', ch)
        a.bne('t1', 't2', 'no_pak')
    a.li('s7', 1)
    a.label('no_pak')
    a.sw('s7', 0x0C, 'gp')
    a.move('s1', 'zero')
    a.move('s6', 'zero')

    a.label('frame')
    # wait for the vertical interrupt (MI_INTR bit 3), acknowledge it via VI_CURRENT
    a.lui('t0', 0xA430)
    a.label('wait_vi')
    a.lw('t1', 0x08, 't0')
    a.andi('t1', 't1', 0x08)
    a.beq('t1', 'zero', 'wait_vi')
    a.sw('zero', 0x10, 's0')
    a.addiu('s1', 's1', 1)
    a.sw('s1', 0x00, 'gp')
    # controller 1
    a.li('a0', BLK_PAD)
    a.jal('si_exchange')
    a.li('t0', 0xA0000000 | BLK_PAD)
    a.lbu('t1', 3, 't0')           # buttons (big-endian halfword at an odd offset: two bytes)
    a.lbu('t2', 4, 't0')
    a.sll('t1', 't1', 8)
    a.or_('s2', 't1', 't2')
    a.lb('s3', 5, 't0')            # stick x (signed)
    a.lb('s4', 6, 't0')            # stick y (signed, up positive)
    a.sll('t1', 's2', 16)
    a.andi('t2', 's3', 0xFF)
    a.sll('t2', 't2', 8)
    a.or_('t1', 't1', 't2')
    a.andi('t2', 's4', 0xFF)
    a.or_('t1', 't1', 't2')
    a.sw('t1', 0x04, 'gp')
    # Start (0x1000) the first time: write the save markers
    a.bne('s6', 'zero', 'saved')
    a.andi('t1', 's2', 0x1000)
    a.beq('t1', 'zero', 'saved')
    a.li('a0', BLK_EEP_WR)
    a.jal('si_exchange')
    a.li('a0', BLK_PAK_WR)
    a.jal('si_exchange')
    a.li('s6', 1)
    a.sw('s6', 0x10, 'gp')
    a.label('saved')
    # audio: queue the buffer whenever the AI FIFO isn't full
    a.lui('t0', 0xA450)
    a.lw('t1', 0x0C, 't0')         # AI_STATUS
    a.srl('t1', 't1', 31)
    a.bne('t1', 'zero', 'audio_full')
    a.li('t1', AUDIO)
    a.sw('t1', 0x00, 't0')         # AI_DRAM_ADDR
    a.li('t1', AUDIO_SAMPLES * 4)
    a.sw('t1', 0x04, 't0')         # AI_LEN starts the DMA
    a.label('audio_full')
    # background
    a.li('t3', 0x00150015)         # dark blue (5551)
    a.beq('s5', 'zero', 'bg')
    a.li('t3', 0x02810281)         # dark green once the EEPROM marker was seen
    a.label('bg')
    a.li('t0', 0xA0000000 | FB)
    a.li('t1', 0xA0000000 | FB + 320 * 240 * 2)
    a.label('fill')
    a.sw('t3', 0, 't0')
    a.sw('t3', 4, 't0')
    a.sw('t3', 8, 't0')
    a.sw('t3', 12, 't0')
    a.addiu('t0', 't0', 16)
    a.bne('t0', 't1', 'fill')
    # square colour from the buttons
    a.li('t4', 0xFFFF)             # white
    a.andi('t1', 's2', 0x8000)     # A
    a.beq('t1', 'zero', 'not_a')
    a.li('t4', 0xF801)
    a.label('not_a')
    a.andi('t1', 's2', 0x4000)     # B
    a.beq('t1', 'zero', 'not_b')
    a.li('t4', 0x07C1)
    a.label('not_b')
    a.andi('t1', 's2', 0x2000)     # Z
    a.beq('t1', 'zero', 'not_z')
    a.li('t4', 0x003F)
    a.label('not_z')
    a.andi('t1', 's2', 0x000F)     # any C button
    a.beq('t1', 'zero', 'not_c')
    a.li('t4', 0xFFC1)
    a.label('not_c')
    # position: x0 = 128 + x/4, y0 = 88 - y/4
    a.sra('t5', 's3', 2)
    a.addiu('t5', 't5', 128)
    a.sra('t6', 's4', 2)
    a.li('t7', 88)
    a.subu('t6', 't7', 't6')
    a.li('t8', 64)                 # rows left
    a.label('row')
    a.sll('t0', 't6', 9)           # y * 640 = y * 512 + y * 128
    a.sll('t1', 't6', 7)
    a.addu('t0', 't0', 't1')
    a.sll('t1', 't5', 1)
    a.addu('t0', 't0', 't1')
    a.li('t1', 0xA0000000 | FB)
    a.addu('t0', 't0', 't1')
    a.li('t9', 64)
    a.label('col')
    a.sh('t4', 0, 't0')
    a.addiu('t0', 't0', 2)
    a.addiu('t9', 't9', -1)
    a.bne('t9', 'zero', 'col')
    a.addiu('t6', 't6', 1)
    a.addiu('t8', 't8', -1)
    a.bne('t8', 'zero', 'row')
    a.j('frame')

    # si_exchange(a0 = physical address of a 64-byte PIF block): write it to PIF RAM, read it back
    a.label('si_exchange')
    a.li('t0', 0xA0000000)
    a.addu('t0', 't0', 'a0')
    a.li('t1', 1)
    a.sb('t1', 63, 't0')           # "process the commands"
    a.lui('t0', 0xA480)            # SI
    a.sw('a0', 0x00, 't0')         # SI_DRAM_ADDR
    a.li('t1', 0x1FC007C0)
    a.sw('t1', 0x10, 't0')         # SI_PIF_ADDR_WR64B
    a.label('si_wait1')
    a.lw('t2', 0x18, 't0')
    a.andi('t2', 't2', 3)
    a.bne('t2', 'zero', 'si_wait1')
    a.sw('zero', 0x18, 't0')       # clear the SI interrupt
    a.sw('a0', 0x00, 't0')
    a.sw('t1', 0x04, 't0')         # SI_PIF_ADDR_RD64B
    a.label('si_wait2')
    a.lw('t2', 0x18, 't0')
    a.andi('t2', 't2', 3)
    a.bne('t2', 'zero', 'si_wait2')
    a.sw('zero', 0x18, 't0')
    a.jr('ra')
    a.nop()
    return a.assemble()


def build():
    stub, image_len = boot_stub()
    code = program()
    image = bytearray(image_len)
    assert len(code) <= BLK_PAD - CODE, len(code)
    image[0:len(code)] = code
    for addr, blk in zip([BLK_PAD, BLK_EEP_RD, BLK_EEP_WR, BLK_PAK_RD, BLK_PAK_WR], pif_blocks()):
        image[addr - CODE:addr - CODE + 64] = blk
    audio = audio_buffer()
    image[AUDIO - CODE:AUDIO - CODE + len(audio)] = audio
    rom = bytearray(0x100000)
    header = struct.pack('>IIII', 0x80371240, 0x0000000F, 0x80000000 | CODE, 0x0000144B)
    rom[0:16] = header
    rom[0x20:0x34] = b'FOLDBACK N64 TEST'.ljust(20)
    rom[0x3B:0x3F] = b'NZFE'
    rom[0x40:0x40 + len(stub)] = stub
    rom[0x1000:0x1000 + len(image)] = image
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, 'n64_demo.z64')
    with open(path, 'wb') as f:
        f.write(rom)
    print(f'{path}: {len(rom)} bytes, program {len(code)} bytes')


if __name__ == '__main__':
    build()
