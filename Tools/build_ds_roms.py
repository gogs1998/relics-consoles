#!/usr/bin/env python3
"""Builds our own Nintendo DS test cartridge into TestROMs/build/ds_demo.nds.

Run from the repo root: python3 Tools/build_ds_roms.py
Both programs are our own ARM code, encoded by the tiny ARM encoder in build_gba_roms.py (the ARM9
is ARMv5 but only ARMv4 instructions are used). No third-party ROMs, no BIOS, no firmware. The header's
logo area (0xC0-0x15B) is left zeroed: the emulator boots the cartridge directly with its free BIOS
replacement, so the logo is never checked.

Layout: header at 0, ARM9 binary at ROM 0x8000 (outside the secure area, so a "retail" cartridge
with the default 64 KiB EEPROM) loaded to 0x02000000, ARM7 binary at ROM 0x9000 loaded to
0x037F8000 (ARM7 WRAM). Game code "ZFDE" is not a real title.

ARM9 (graphics and keys):
  1. Engine A on the top screen in VRAM display mode (bank A at 0x06800000), engine B on the touch
     screen showing only its backdrop colour.
  2. Fills the top screen with a red/green gradient (red = x / 8, green = y / 8).
  3. Every frame (at the start of vertical blank) counts the frame at 0x027FF104, reads KEYINPUT and
     draws a 32x32 square in the middle of the top screen: white with no key, red while A is held,
     green while B is held, blue while L is held.
  4. Sets the touch screen's backdrop: a slow blue ramp from the frame counter, or solid green while
     the stylus is down (EXTKEYIN bit 6, which the ARM7 copies to 0x027FF100).

ARM7 (sound, save memory, touch):
  1. Starts a ~440 Hz square tone on PSG channel 8.
  2. Bumps a boot counter in the cartridge EEPROM over the slot's SPI bus (byte 0 = 0x42 marker,
     byte 1 = counter), so battery saves can be checked; publishes the counter at 0x027FF108.
  3. Copies EXTKEYIN (X, Y, pen down) to 0x027FF100 forever.
0x027FF100-0x027FF10B sits in the main RAM area the ARM9's protection unit leaves uncached.
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_gba_roms import ARM  # noqa: E402  (our own encoder)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'TestROMs', 'build')

IO = 0x04000000
LCDC_VRAM = 0x06800000
PAL_B = 0x05000400
SHARED_KEYS = 0x027FF100
SHARED_FRAME = 0x027FF104
SHARED_BOOTS = 0x027FF108
ARM9_ROM, ARM9_RAM = 0x8000, 0x02000000
ARM7_ROM, ARM7_RAM = 0x9000, 0x037F8000
PSG_TIMER = 0x10000 - round(16756991 / (8 * 440))   # PSG duty steps run at 16.76 MHz / 8 per step


def arm9_program():
    a = ARM()
    r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10 = range(11)
    a.mov(r0, imm=IO)
    a.ldr_const(r1, 0x820F)                    # POWCNT1: LCDs, 2D A + B, 3D; engine A on top
    a.add(r2, r0, imm=0x300)
    a.strh(r1, r2, 4)
    a.add(r2, r0, imm=0x240)
    a.mov(r1, imm=0x80)
    a.strb(r1, r2, 0)                          # VRAMCNT_A: bank A on, LCDC (0x06800000)
    a.mov(r1, imm=0x20000)
    a.str(r1, r0, 0)                           # DISPCNT_A: display mode 2 (VRAM bank A)
    a.add(r2, r0, imm=0x1000)
    a.mov(r1, imm=0x10000)
    a.str(r1, r2, 0)                           # DISPCNT_B: graphics mode, no layers (backdrop only)

    # gradient: pixel = (x >> 3) | ((y >> 3) << 5)
    a.mov(r5, imm=LCDC_VRAM)
    a.mov(r6, imm=0)
    a.label('yl')
    a.mov(r7, imm=0)
    a.mov(r9, rm=r6, shift='lsr', amount=3)
    a.mov(r9, rm=r9, shift='lsl', amount=5)
    a.label('xl')
    a.orr(r8, r9, rm=r7, shift='lsr', amount=3)
    a.strh_post(r8, r5, 2)
    a.add(r7, r7, imm=1)
    a.cmp(r7, imm=256)
    a.b('xl', cond='lt')
    a.add(r6, r6, imm=1)
    a.cmp(r6, imm=192)
    a.b('yl', cond='lt')

    a.mov(r10, imm=0)                          # frame counter
    a.label('frame')
    a.label('w1')                              # wait while in vertical blank
    a.ldrh(r2, r0, 6)
    a.cmp(r2, imm=192)
    a.b('w1', cond='ge')
    a.label('w2')                              # wait for vertical blank to start
    a.ldrh(r2, r0, 6)
    a.cmp(r2, imm=192)
    a.b('w2', cond='lt')
    a.add(r10, r10, imm=1)
    a.ldr_const(r2, SHARED_FRAME)
    a.str(r10, r2, 0)

    a.add(r3, r0, imm=0x130)
    a.ldrh(r3, r3, 0)                          # KEYINPUT (0 = pressed)
    a.ldr_const(r8, 0x7FFF)                    # white
    a.tst(r3, imm=1 << 9)
    a.ldr_const(r8, 0x7C00, cond='eq')         # L: blue
    a.tst(r3, imm=1 << 1)
    a.ldr_const(r8, 0x03E0, cond='eq')         # B: green
    a.tst(r3, imm=1 << 0)
    a.ldr_const(r8, 0x001F, cond='eq')         # A: red

    # 32x32 square at (112, 80)
    a.ldr_const(r5, LCDC_VRAM + (80 * 256 + 112) * 2)
    a.mov(r6, imm=32)
    a.label('ry')
    a.mov(r7, imm=32)
    a.mov(r9, rm=r5)
    a.label('rx')
    a.strh_post(r8, r9, 2)
    a.sub(r7, r7, imm=1, s=True)
    a.b('rx', cond='ne')
    a.add(r5, r5, imm=512)
    a.sub(r6, r6, imm=1, s=True)
    a.b('ry', cond='ne')

    # touch screen backdrop
    a.ldr_const(r4, SHARED_KEYS)
    a.ldrh(r4, r4, 0)                          # EXTKEYIN copy (bit 6 = 0 while the pen is down)
    a.mov(r1, rm=r10, shift='lsr', amount=2)
    a.dp('and', rd=r1, rn=r1, imm=31)
    a.mov(r1, rm=r1, shift='lsl', amount=10)   # blue ramp
    a.tst(r4, imm=1 << 6)
    a.ldr_const(r1, 0x03E0, cond='eq')         # pen down: green
    a.ldr_const(r2, PAL_B)
    a.strh(r1, r2, 0)
    a.b('frame')
    return a


def arm7_program():
    a = ARM()
    r0, r1, r2, r3, r4, r5 = range(6)
    lr, pc = 14, 15
    a.mov(r0, imm=IO)

    # sound: power, master enable at full volume, PSG channel 8 square wave
    a.mov(r1, imm=1)
    a.add(r2, r0, imm=0x300)
    a.strh(r1, r2, 4)                          # POWCNT2: sound on
    a.ldr_const(r1, 0x807F)
    a.add(r2, r0, imm=0x500)
    a.strh(r1, r2, 0)                          # SOUNDCNT: enable, master volume 127
    a.add(r2, r0, imm=0x400)
    a.ldr_const(r1, PSG_TIMER)
    a.strh(r1, r2, 0x88)                       # SOUND8TMR
    a.ldr_const(r1, 0x80000000 | 3 << 29 | 3 << 24 | 0x40 << 16 | 0x40)
    a.str(r1, r2, 0x80)                        # SOUND8CNT: start, PSG, 50 % duty, centre, volume 64

    # EEPROM boot counter. r3 = AUXSPICNT; xfer sends r1 and returns the reply in r0.
    a.ldr_const(r3, 0x040001A0)
    a.ldr_const(r1, 0xA040)                    # slot on, SPI mode, hold chip select
    a.strh(r1, r3, 0)
    for byte in (0x03, 0x00, 0x00):            # READ from address 0
        a.mov(r1, imm=byte)
        a.b('xfer', link=True)
    a.mov(r1, imm=0)
    a.b('xfer', link=True)
    a.mov(r4, rm=r0)                           # byte 0 (marker)
    a.ldr_const(r1, 0xA000)                    # release chip select after the next byte
    a.strh(r1, r3, 0)
    a.mov(r1, imm=0)
    a.b('xfer', link=True)
    a.mov(r5, rm=r0)                           # byte 1 (counter)
    a.cmp(r4, imm=0x42)
    a.mov(r5, imm=0, cond='ne')                # blank EEPROM: start from 0
    a.add(r5, r5, imm=1)
    a.dp('and', rd=r5, rn=r5, imm=0xFF)

    a.mov(r1, imm=0x06)                        # WREN (one byte, chip select released after)
    a.b('xfer', link=True)
    a.ldr_const(r1, 0xA040)
    a.strh(r1, r3, 0)
    for byte in (0x02, 0x00, 0x00, 0x42):      # WRITE at address 0: marker, then the counter
        a.mov(r1, imm=byte)
        a.b('xfer', link=True)
    a.ldr_const(r1, 0xA000)
    a.strh(r1, r3, 0)
    a.mov(r1, rm=r5)
    a.b('xfer', link=True)
    a.ldr_const(r2, SHARED_BOOTS)
    a.str(r5, r2, 0)

    a.ldr_const(r2, SHARED_KEYS)
    a.ldr_const(r3, IO + 0x100)                # (r0 was used by xfer)
    a.label('loop')
    a.ldrh(r1, r3, 0x36)                       # EXTKEYIN (0x04000136)
    a.strh(r1, r2, 0)
    a.b('loop')

    a.label('xfer')
    a.strh(r1, r3, 2)                          # AUXSPIDATA
    a.label('busy')
    a.ldrh(r2, r3, 0)
    a.tst(r2, imm=0x80)
    a.b('busy', cond='ne')
    a.ldrh(r0, r3, 2)
    a.mov(pc, rm=lr)
    return a


def crc16(data):
    """CRC-16/MODBUS, as used for the header checksum at 0x15E."""
    crc = 0xFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc


def build_demo():
    arm9 = arm9_program().assemble(ARM9_RAM)
    arm7 = arm7_program().assemble(ARM7_RAM)
    assert len(arm9) <= ARM7_ROM - ARM9_ROM
    arm9 += b'\0' * (-len(arm9) % 4)
    arm7 += b'\0' * (-len(arm7) % 4)
    size = 0x10000
    rom = bytearray(size)
    h = rom
    h[0x00:0x0C] = b'FOLDBACK DS'.ljust(12, b'\0')
    h[0x0C:0x10] = b'ZFDE'
    h[0x10:0x12] = b'00'
    h[0x12] = 0                                 # NDS only
    h[0x14] = 0                                 # chip capacity: 128 KiB
    struct.pack_into('<IIII', h, 0x20, ARM9_ROM, ARM9_RAM, ARM9_RAM, len(arm9))
    struct.pack_into('<IIII', h, 0x30, ARM7_ROM, ARM7_RAM, ARM7_RAM, len(arm7))
    struct.pack_into('<I', h, 0x60, 0x00586000)  # normal ROM control settings
    struct.pack_into('<I', h, 0x64, 0x001808F8)  # KEY1 command settings
    struct.pack_into('<I', h, 0x80, ARM7_ROM + len(arm7))  # used ROM size
    struct.pack_into('<I', h, 0x84, 0x4000)      # header size
    struct.pack_into('<H', h, 0x15E, crc16(h[0:0x15E]))
    rom[ARM9_ROM:ARM9_ROM + len(arm9)] = arm9
    rom[ARM7_ROM:ARM7_ROM + len(arm7)] = arm7
    return bytes(rom)


def main():
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, 'ds_demo.nds')
    rom = build_demo()
    with open(path, 'wb') as f:
        f.write(rom)
    print(f'wrote {path} ({len(rom)} bytes)')


if __name__ == '__main__':
    main()
