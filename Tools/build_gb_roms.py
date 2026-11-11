#!/usr/bin/env python3
"""Builds our own Game Boy test ROMs from TestROMs/gb/*.s into TestROMs/build/.

Run from the repo root: python3 Tools/build_gb_roms.py
Everything assembled here is our own code, art (Tools/chrart.py) and music. No third-party ROMs,
no boot ROM, and the header's logo area ($0104-$0133) is left zeroed.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from asm_sm83 import Assembler, gb_header       # noqa: E402
from chrart import SCENE, SPRITES, glyph_rows  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'TestROMs', 'gb')
OUT = os.path.join(ROOT, 'TestROMs', 'build')

NOTES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
NOTE_NAMES = [f'{n}{o}' for o in range(2, 7) for n in NOTES]
MELODY = ('C5 E5 G5 E5 F5 A5 C6 A5 G5 B4 D5 G5 F5 E5 D5 - '
          'C5 E5 G5 C6 A5 F5 D5 F5 E5 G5 D5 B4 C5 - - -')
BASS = 'C3 C3 F3 F3 G2 G2 G2 G2 C3 C3 F3 D3 G2 G2 C3 C3'


def freq(name):
    n, octv = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((NOTES.index(n) + 12 * (octv + 1) - 69) / 12)


def gb_tile(rows):
    """8 strings of 8 chars ('.', '1'..'3') -> 16 bytes of Game Boy 2bpp (row-interleaved planes)."""
    out = []
    for r in rows:
        lo = hi = 0
        for x, ch in enumerate(r):
            v = 0 if ch == '.' else int(ch)
            lo |= (v & 1) << (7 - x)
            hi |= ((v >> 1) & 1) << (7 - x)
        out += [lo, hi]
    return out


def db_lines(label, data, per_line=16):
    lines = [f'{label}:']
    for i in range(0, len(data), per_line):
        lines.append('    .db ' + ', '.join(f'${b:02X}' for b in data[i:i + per_line]))
    return '\n'.join(lines) + '\n'


def font_tiles(fg, bg):
    """Tiles for ASCII $20-$5F, in tile order."""
    data = []
    for code in range(0x20, 0x60):
        data += gb_tile(glyph_rows(chr(code), fg, bg))
    return data


def rgb555(r, g, b):
    w = (r >> 3) | ((g >> 3) << 5) | ((b >> 3) << 10)
    return [w & 0xFF, w >> 8]


def read(name):
    return open(os.path.join(SRC, name)).read()


# ---------------------------------------------------------------- self test

def build_selftest():
    src = read('gb_selftest.s')
    src += '\n.bank 0\n.org $3800\n' + db_lines('font_tiles', font_tiles('3', '.'))
    rom = Assembler().assemble(src, 0x10000)
    # MBC1 + RAM + battery, 8 KB RAM
    return gb_header(rom, 'FOLDBACK SELFTST', cgb_flag=0, cart_type=0x03, ram_size=0x02)


def build_cgbtest():
    src = read('gb_cgbtest.s')
    src += '\n.bank 0\n.org $3800\n' + db_lines('font_tiles', font_tiles('3', '.'))
    rom = Assembler().assemble(src, 0x10000)
    # MBC5 + RAM + battery, 32 KB RAM, CGB-enhanced
    return gb_header(rom, 'FOLDBACK CGBTST', cgb_flag=0x80, cart_type=0x1B, ram_size=0x03)


# ---------------------------------------------------------------- demo

def demo_tiles():
    tiles = [[0] * 16 for _ in range(0x84)]
    for idx, rows in SCENE.items():
        tiles[idx] = gb_tile(rows)
    for code in range(0x20, 0x60):        # status-bar font: light text on the dark bar colour
        tiles[code] = gb_tile(glyph_rows(chr(code), '1', '3'))
    # mascot, arranged for 8x16 sprites: left column $80/$81, right column $82/$83
    tiles[0x80] = gb_tile(SPRITES[0x01])
    tiles[0x81] = gb_tile(SPRITES[0x03])
    tiles[0x82] = gb_tile(SPRITES[0x02])
    tiles[0x83] = gb_tile(SPRITES[0x04])
    return [b for t in tiles for b in t]


def demo_maps():
    tmap = [[0] * 32 for _ in range(18)]
    attr = [[0] * 32 for _ in range(18)]
    for (row, col) in [(2, 3), (2, 14), (2, 25), (5, 9), (5, 20), (6, 29)]:
        for i, t in enumerate([0x05, 0x06, 0x07]):
            tmap[row][(col + i) % 32] = t
        for i, t in enumerate([0x0D, 0x0E, 0x0F]):
            tmap[row + 1][(col + i) % 32] = t
    # hills: rows 10-12, palette 1
    for start in (1, 12, 22):
        tmap[10][start + 2] = 0x0A; tmap[10][start + 3] = 0x0B; tmap[10][start + 4] = 0x0C
        tmap[11][start + 1] = 0x0A
        for c in range(start + 2, start + 5):
            tmap[11][c] = 0x10
        tmap[11][start + 5] = 0x0C
        for c in range(start, start + 7):
            if c < 32:
                tmap[12][c] = 0x10
                attr[11][c] = attr[10][c] = attr[12][c] = 1
    for c in range(32):
        if tmap[12][c] == 0:
            tmap[12][c] = 0x0A if c % 2 == 0 else 0x0C
            attr[12][c] = 1
    for c in range(32):
        tmap[13][c] = 0x08
        attr[13][c] = 2
        for r in range(14, 18):
            tmap[r][c] = 0x09
            attr[r][c] = 3
    # a few cloud tiles get the bright palette 0; hills the green palette
    return [b for row in tmap for b in row], [b for row in attr for b in row]


def demo_palettes():
    sky = (120, 184, 248)
    pals = [
        [sky, (255, 255, 255), (208, 228, 248), (96, 128, 200)],          # 0 sky, clouds
        [sky, (32, 104, 56), (88, 176, 80), (56, 136, 64)],               # 1 hills
        [sky, (72, 168, 56), sky, (24, 88, 32)],                          # 2 grass
        [sky, (200, 96, 48), (168, 72, 40), (88, 40, 24)],                # 3 bricks
        [(40, 32, 64), (255, 236, 184), (120, 96, 160), (40, 32, 64)],    # 4 status bar
    ]
    bg = [b for p in pals for c in p for b in rgb555(*c)]
    obj = [b for c in [(0, 0, 0), (255, 136, 32), (255, 255, 255), (72, 24, 8)] for b in rgb555(*c)]
    return bg, obj


def demo_tables():
    tiles = demo_tiles()
    tmap, attr = demo_maps()
    bg, obj = demo_palettes()
    jump_len = 32
    jump = [round(4 * 30 * t * (jump_len - t) / jump_len ** 2) for t in range(jump_len)]
    sq = [0, 0] + [b for nm in NOTE_NAMES for b in
                   ((2048 - round(131072 / freq(nm))) & 0xFF, (2048 - round(131072 / freq(nm))) >> 8)]
    wv = [0, 0] + [b for nm in NOTE_NAMES for b in
                   ((2048 - round(65536 / freq(nm))) & 0xFF, (2048 - round(65536 / freq(nm))) >> 8)]

    def song(names):
        return [0 if n == '-' else NOTE_NAMES.index(n) + 1 for n in names.split()]
    melody, bass = song(MELODY), song(BASS)
    out = f'\nDEMO_TILE_BYTES = {len(tiles)}\nJUMP_LEN = {jump_len}\nMELODY_LEN = {len(melody)}\n'
    out += db_lines('jump_tab', jump)
    out += db_lines('sq_freq', sq)
    out += db_lines('wave_freq', wv)
    out += db_lines('melody', melody)
    out += db_lines('bass', bass)
    out += db_lines('bg_palettes', bg)
    out += db_lines('obj_palettes', obj)
    out += db_lines('demo_map', tmap)
    out += db_lines('demo_attr', attr)
    out += '\n.org $4000\n' + db_lines('demo_tiles', tiles)
    return out


def build_demo(cgb):
    src = read('gb_demo.s') + demo_tables()
    rom = Assembler().assemble(src, 0x8000)
    return gb_header(rom, 'FOLDBACK DEMO', cgb_flag=0x80 if cgb else 0, cart_type=0x00, ram_size=0)


def main():
    os.makedirs(OUT, exist_ok=True)
    roms = {
        'gb_selftest.gb': build_selftest(),
        'gb_cgbtest.gbc': build_cgbtest(),
        'gb_demo.gbc': build_demo(True),
        'gb_demo_dmg.gb': build_demo(False),
    }
    for name, data in roms.items():
        with open(os.path.join(OUT, name), 'wb') as f:
            f.write(data)
        print(f'{name}: {len(data)} bytes')


if __name__ == '__main__':
    main()
