#!/usr/bin/env python3
"""Builds our own Game Boy Advance test ROM into TestROMs/build/gba_demo.gba.

Run from the repo root: python3 Tools/build_gba_roms.py
The program is our own ARM code, encoded by the tiny ARM (ARMv4) encoder below. No third-party
ROMs, no BIOS. The header's logo area (0x04-0x9F) is left zeroed: the emulator uses its HLE BIOS
and boots straight into the cartridge, so the logo is never checked.

What the ROM does (ARM state, running from cartridge ROM at 0x08000000):
  1. Sets WAITCNT, then mode 3 (240x160 direct colour, BG2 on).
  2. Bumps a boot counter in cartridge SRAM byte 1 (byte 0 = 0x42 marker), so battery saves
     can be checked.
  3. Starts a steady 50 % duty square tone on sound channel 1 (about 440 Hz).
  4. Fills the screen with a red/green gradient (red = x / 8, green = y / 8).
  5. Every frame (after the start of vertical blank) reads KEYINPUT and draws a 32x32 square in the
     middle of the screen: white with no key, red while A is held, green while B is held,
     blue while L is held. Holding R raises the tone an octave.
"""
import os
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'TestROMs', 'build')

COND = {'eq': 0, 'ne': 1, 'cs': 2, 'hs': 2, 'cc': 3, 'lo': 3, 'mi': 4, 'pl': 5,
        'hi': 8, 'ls': 9, 'ge': 10, 'lt': 11, 'gt': 12, 'le': 13, 'al': 14}
DP = {'and': 0, 'eor': 1, 'sub': 2, 'rsb': 3, 'add': 4, 'tst': 8, 'cmp': 10,
      'orr': 12, 'mov': 13, 'bic': 14, 'mvn': 15}
SHIFT = {'lsl': 0, 'lsr': 1, 'asr': 2, 'ror': 3}


def rot_imm(value):
    """ARM data-processing immediate: an 8-bit value rotated right by an even amount."""
    value &= 0xFFFFFFFF
    for rot in range(16):
        v = ((value << (2 * rot)) | (value >> (32 - 2 * rot))) & 0xFFFFFFFF if rot else value
        if v < 256:
            return (rot << 8) | v
    raise ValueError(f'immediate {value:#x} cannot be encoded')


class ARM:
    """A two-pass ARM encoder: call the emitters, then `assemble(base)`."""

    def __init__(self):
        self.items = []      # (kind, payload)
        self.labels = {}
        self.literals = []   # values for the literal pool

    def label(self, name):
        self.items.append(('label', name))

    def _emit(self, fn):
        self.items.append(('insn', fn))

    # data processing ------------------------------------------------------------------------
    def dp(self, op, rd=0, rn=0, imm=None, rm=None, shift='lsl', amount=0, s=False, cond='al'):
        opc = DP[op]
        if op in ('tst', 'cmp'):
            s = True
        word = COND[cond] << 28 | opc << 21 | (1 << 20 if s else 0) | rn << 16 | rd << 12
        if imm is not None:
            word |= 1 << 25 | rot_imm(imm)
        else:
            word |= (amount & 31) << 7 | SHIFT[shift] << 5 | rm
        self._emit(lambda pc, w=word: w)

    def mov(self, rd, imm=None, rm=None, **kw): self.dp('mov', rd=rd, imm=imm, rm=rm, **kw)
    def add(self, rd, rn, imm=None, rm=None, **kw): self.dp('add', rd=rd, rn=rn, imm=imm, rm=rm, **kw)
    def sub(self, rd, rn, imm=None, rm=None, **kw): self.dp('sub', rd=rd, rn=rn, imm=imm, rm=rm, **kw)
    def orr(self, rd, rn, imm=None, rm=None, **kw): self.dp('orr', rd=rd, rn=rn, imm=imm, rm=rm, **kw)
    def cmp(self, rn, imm=None, rm=None, **kw): self.dp('cmp', rn=rn, imm=imm, rm=rm, **kw)
    def tst(self, rn, imm=None, rm=None, **kw): self.dp('tst', rn=rn, imm=imm, rm=rm, **kw)

    # memory ---------------------------------------------------------------------------------
    def _single(self, load, byte, rd, rn, offset, post, cond):
        u = 1 if offset >= 0 else 0
        off = abs(offset)
        assert off < 4096
        p = 0 if post else 1
        return (COND[cond] << 28 | 1 << 26 | p << 24 | u << 23 | byte << 22 | load << 20
                | rn << 16 | rd << 12 | off)

    def ldr(self, rd, rn, offset=0, cond='al'):
        self._emit(lambda pc, w=self._single(1, 0, rd, rn, offset, False, cond): w)

    def str(self, rd, rn, offset=0, cond='al'):
        self._emit(lambda pc, w=self._single(0, 0, rd, rn, offset, False, cond): w)

    def ldrb(self, rd, rn, offset=0, cond='al'):
        self._emit(lambda pc, w=self._single(1, 1, rd, rn, offset, False, cond): w)

    def strb(self, rd, rn, offset=0, cond='al'):
        self._emit(lambda pc, w=self._single(0, 1, rd, rn, offset, False, cond): w)

    def _half(self, load, rd, rn, offset, post, cond):
        u = 1 if offset >= 0 else 0
        off = abs(offset)
        assert off < 256
        p = 0 if post else 1
        return (COND[cond] << 28 | p << 24 | u << 23 | 1 << 22 | load << 20 | rn << 16 | rd << 12
                | (off >> 4) << 8 | 0xB << 4 | (off & 0xF))

    def ldrh(self, rd, rn, offset=0, cond='al'):
        self._emit(lambda pc, w=self._half(1, rd, rn, offset, False, cond): w)

    def strh(self, rd, rn, offset=0, cond='al'):
        self._emit(lambda pc, w=self._half(0, rd, rn, offset, False, cond): w)

    def strh_post(self, rd, rn, offset, cond='al'):
        """strh rd, [rn], #offset"""
        self._emit(lambda pc, w=self._half(0, rd, rn, offset, True, cond): w)

    def ldr_const(self, rd, value, cond='al'):
        """ldr rd, =value (PC-relative load from the literal pool)."""
        value &= 0xFFFFFFFF
        if value not in self.literals:
            self.literals.append(value)
        idx = self.literals.index(value)

        def enc(pc, rd=rd, idx=idx, cond=cond):
            target = self.labels['__pool'] + 4 * idx
            off = target - (pc + 8)
            return self._single(1, 0, rd, 15, off, False, cond)
        self._emit(enc)

    # branches -------------------------------------------------------------------------------
    def b(self, target, cond='al', link=False):
        def enc(pc, target=target, cond=cond, link=link):
            off = (self.labels[target] - (pc + 8)) >> 2
            return COND[cond] << 28 | 0b101 << 25 | (1 << 24 if link else 0) | (off & 0xFFFFFF)
        self._emit(enc)

    def assemble(self, base):
        pc = base
        for kind, payload in self.items:
            if kind == 'label':
                self.labels[payload] = pc
            else:
                pc += 4
        self.labels['__pool'] = pc
        out = bytearray()
        pc = base
        for kind, payload in self.items:
            if kind == 'insn':
                out += struct.pack('<I', payload(pc))
                pc += 4
        for v in self.literals:
            out += struct.pack('<I', v)
        return bytes(out)


def gba_header(title, code, maker=b'00'):
    """0xC0 bytes: branch to 0xC0, zeroed logo, title/code/maker, fixed 0x96 and the complement."""
    h = bytearray(0xC0)
    h[0:4] = struct.pack('<I', 0xEA000000 | ((0xC0 - 8) >> 2))   # b 0x080000C0
    h[0xA0:0xAC] = title.ljust(12, b'\0')[:12]
    h[0xAC:0xB0] = code
    h[0xB0:0xB2] = maker
    h[0xB2] = 0x96
    chk = 0
    for i in range(0xA0, 0xBD):
        chk = (chk - h[i]) & 0xFF
    h[0xBD] = (chk - 0x19) & 0xFF
    return h


REG = 0x04000000
VRAM = 0x06000000
SRAM = 0x0E000000
TONE_LOW = 2048 - 131072 // 440      # channel 1 rate value for ~440 Hz
TONE_HIGH = 2048 - 131072 // 880


def demo_program():
    a = ARM()
    r0, r1, r2, r3, r4, r5, r6, r7, r8, r9 = range(10)
    # r0 = I/O base
    a.mov(r0, imm=REG)
    a.ldr_const(r1, 0x4317)                    # WAITCNT: faster ROM waits + prefetch
    a.add(r2, r0, imm=0x200)
    a.strh(r1, r2, 4)
    a.ldr_const(r1, 0x0403)                    # DISPCNT: mode 3, BG2 on
    a.strh(r1, r0, 0)

    # SRAM: byte 0 = 0x42 marker, byte 1 = boot counter
    a.mov(r1, imm=SRAM)
    a.mov(r2, imm=0x42)
    a.strb(r2, r1, 0)
    a.ldrb(r2, r1, 1)
    a.add(r2, r2, imm=1)
    a.strb(r2, r1, 1)

    # sound: master on, PSG at 100 %, channel 1 to both sides at full volume
    a.mov(r1, imm=0x80)
    a.strh(r1, r0, 0x84)                       # SOUNDCNT_X
    a.ldr_const(r1, 0x1177)
    a.strh(r1, r0, 0x80)                       # SOUNDCNT_L
    a.mov(r1, imm=2)
    a.strh(r1, r0, 0x82)                       # SOUNDCNT_H
    a.mov(r1, imm=0)
    a.strh(r1, r0, 0x60)                       # SOUND1CNT_L: no sweep
    a.ldr_const(r1, 0xF080)
    a.strh(r1, r0, 0x62)                       # SOUND1CNT_H: volume 15, no envelope, 50 % duty
    a.ldr_const(r1, 0x8000 | TONE_LOW)
    a.strh(r1, r0, 0x64)                       # SOUND1CNT_X: restart, continuous

    # gradient: pixel = (x >> 3) | ((y >> 3) << 5)
    a.mov(r5, imm=VRAM)
    a.mov(r6, imm=0)
    a.label('yl')
    a.mov(r7, imm=0)
    a.mov(r9, rm=r6, shift='lsr', amount=3)
    a.mov(r9, rm=r9, shift='lsl', amount=5)
    a.label('xl')
    a.orr(r8, r9, rm=r7, shift='lsr', amount=3)
    a.strh_post(r8, r5, 2)
    a.add(r7, r7, imm=1)
    a.cmp(r7, imm=240)
    a.b('xl', cond='lt')
    a.add(r6, r6, imm=1)
    a.cmp(r6, imm=160)
    a.b('yl', cond='lt')

    a.mov(r4, imm=0)                           # previous R state (0 = released)
    a.label('frame')
    a.label('w1')                              # wait while in vblank
    a.ldrh(r2, r0, 6)
    a.cmp(r2, imm=160)
    a.b('w1', cond='ge')
    a.label('w2')                              # wait for vblank to start
    a.ldrh(r2, r0, 6)
    a.cmp(r2, imm=160)
    a.b('w2', cond='lt')

    a.add(r3, r0, imm=0x130)
    a.ldrh(r3, r3, 0)                          # KEYINPUT (0 = pressed)
    a.ldr_const(r8, 0x7FFF)                    # white
    a.tst(r3, imm=1 << 9)
    a.ldr_const(r8, 0x7C00, cond='eq')         # L: blue
    a.tst(r3, imm=1 << 1)
    a.ldr_const(r8, 0x03E0, cond='eq')         # B: green
    a.tst(r3, imm=1 << 0)
    a.ldr_const(r8, 0x001F, cond='eq')         # A: red

    # R held -> high tone. Only rewrite the frequency when R changes.
    a.mov(r1, rm=r3, shift='lsr', amount=8)
    a.dp('and', rd=r1, rn=r1, imm=1)
    a.dp('eor', rd=r1, rn=r1, imm=1)           # r1 = 1 while R is held
    a.cmp(r1, rm=r4)
    a.b('nochange', cond='eq')
    a.mov(r4, rm=r1)
    a.ldr_const(r2, 0x8000 | TONE_LOW)         # SOUND1CNT_X with restart (mGBA only retunes on restart)
    a.cmp(r1, imm=0)
    a.ldr_const(r2, 0x8000 | TONE_HIGH, cond="ne")
    a.strh(r2, r0, 0x64)
    a.label('nochange')

    # 32x32 square at (104, 64)
    a.ldr_const(r5, VRAM + (64 * 240 + 104) * 2)
    a.mov(r6, imm=32)
    a.label('ry')
    a.mov(r7, imm=32)
    a.mov(r9, rm=r5)
    a.label('rx')
    a.strh_post(r8, r9, 2)
    a.sub(r7, r7, imm=1, s=True)
    a.b('rx', cond='ne')
    a.add(r5, r5, imm=480)
    a.sub(r6, r6, imm=1, s=True)
    a.b('ry', cond='ne')
    a.b('frame')
    return a


def build_demo():
    code = demo_program().assemble(0x080000C0)
    rom = gba_header(b'DUO DEMO', b'ZDUO') + code
    rom += b'\0' * (-len(rom) % 0x1000)          # pad to 4 KB
    return bytes(rom)


def main():
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, 'gba_demo.gba')
    rom = build_demo()
    with open(path, 'wb') as f:
        f.write(rom)
    print(f'wrote {path} ({len(rom)} bytes)')


if __name__ == '__main__':
    main()
