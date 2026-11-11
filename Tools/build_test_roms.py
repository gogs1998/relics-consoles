#!/usr/bin/env python3
"""Builds our own NES test ROMs from TestROMs/nes/*.s into TestROMs/build/.

Run from the repo root: python3 Tools/build_test_roms.py
Everything assembled here is our own code and art (Tools/chrart.py). No third-party ROMs.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from asm6502 import Assembler, ines  # noqa: E402
from chrart import nes_chr_bank      # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'TestROMs', 'nes')
OUT = os.path.join(ROOT, 'TestROMs', 'build')

NOTES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']


def freq(name):
    n, octv = name[:-1], int(name[-1])
    semis = NOTES.index(n) + 12 * (octv + 1) - 69  # MIDI A4 = 69
    return 440.0 * 2 ** (semis / 12)


NOTE_NAMES = [f'{n}{o}' for o in range(2, 7) for n in NOTES]


def period_table(div):
    words = ['$0000']
    for nm in NOTE_NAMES:
        p = round(1789773 / (div * freq(nm)) - 1)
        words.append(f'${min(p, 0x7FF):04X}')
    return ', '.join(words)


def song(names):
    return ', '.join('0' if n == '-' else str(NOTE_NAMES.index(n) + 1) for n in names.split())


MELODY = ('C5 E5 G5 E5 F5 A5 C6 A5 G5 B4 D5 G5 F5 E5 D5 - '
          'C5 E5 G5 C6 A5 F5 D5 F5 E5 G5 D5 B4 C5 - - -')
BASS = 'C3 C3 F3 F3 G2 G2 G2 G2 C3 C3 F3 D3 G2 G2 C3 C3'


def read(name):
    return open(os.path.join(SRC, name)).read()


def vectors():
    return '\n.org $FFFA\n.dw nmi, reset, irq\n'


def music_tables():
    return (f'\nnote_period: .dw {period_table(16)}\n'
            f'tri_period: .dw {period_table(32)}\n'
            f'melody: .db {song(MELODY)}\n'
            f'bass: .db {song(BASS)}\n')


def nrom(src_name, extra=''):
    src = read(src_name) + '\n' + read('common.s') + extra + vectors()
    prg = Assembler().assemble(src, 0x8000, 0x8000)
    return ines([prg[:0x4000], prg[0x4000:]], [nes_chr_bank()], mapper=0, vertical=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    roms = {
        'demo.nes': nrom('demo.s', music_tables()),
        'cpu_selftest.nes': nrom('cpu_selftest.s'),
    }
    sys.path.insert(0, SRC)
    try:
        import mappers  # noqa: E402  (TestROMs/nes/mappers.py)
        roms.update(mappers.build(Assembler, ines, nes_chr_bank, read, vectors))
    except ImportError:
        pass
    for name, data in roms.items():
        with open(os.path.join(OUT, name), 'wb') as f:
            f.write(data)
        print(f'{name}: {len(data)} bytes')


if __name__ == '__main__':
    main()
