#!/usr/bin/env python3
"""Builds our own heavy RDP/RSP benchmark cartridge for the N64 speed test (Mac CLI) (docs/n64-rdp-spike.md):
Spikes/N64RDP/rom-n64_rdpbench.z64 (for the Mac CLI bench, Spikes/N64RDP/build_mac.sh). Not shipped: the in-app
speed test was removed for release (build 7).

Run from the repo root: python3 Tools/build_n64_bench_rom.py
Everything is ours: the CPU program and the boot stub use the MIPS assembler from Tools/build_n64_roms.py, the RSP
microcode is assembled by the small RSP assembler below (scalar MIPS subset + COP2 vector unit + LWC2/SWC2), and
the RDP command lists are generated here from our own triangle setup. No Nintendo code or microcode.

What one frame does (NTSC, 60 VI/s):
  CPU   waits for the vertical interrupt, shows the frame rendered last time (double-buffered 320x240 RGBA5551),
        writes an OSTask (type 1 = graphics) into DMEM, starts the RSP and waits for it, then runs a game-like
        loop (loads/stores, integer and FPU arithmetic: ~245k instructions, most of the frame's CPU budget).
  RSP   our microcode: DMAs a constants block in, runs a vertex-transform + triangle-setup kernel (~167 RSP
        instructions, mostly vector multiply-accumulate, reciprocal, compare/merge and stores, modelled on what a
        real graphics microcode spends per triangle) once per triangle, then streams the frame's RDP command list
        from RDRAM through two 1 KB DMEM buffers to the RDP over the XBUS (like a real microcode's output buffer),
        and ends with SyncFull.
  RDP   clears Z and colour (fill mode), then draws N shaded, textured (32x32 RGBA16, bilinear, perspective on),
        Z-buffered, anti-aliased triangles with framebuffer read (the typical opaque-surface render mode).

Load levels (each runs 240 frames, then the next; the cycle repeats):
  1:  800 triangles, total area 1.0x the screen (a light 3D scene)
  2: 2000 triangles, 2.0x  (a busy N64 scene; more than most games push at 30 fps)
  3: 4000 triangles, 3.0x  (beyond the real console's worst case at 60 fps)
Debug words for the bench (RDRAM physical): 0x300 frame count, 0x304 level, 0x308 triangles per frame,
0x30C RSP kernel iterations per frame, 0x310 RSP instructions per kernel iteration.
"""
import math
import os
import random
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'Tools'))
from build_n64_roms import MIPS, REGS, boot_stub as _unused_boot_stub  # noqa: E402,F401

OUT = os.path.join(ROOT, 'Spikes', 'N64RDP', 'rom-n64_rdpbench.z64')

# RDRAM (physical) layout
CODE = 0x400
UCODE = 0x4000          # RSP microcode image (DMA'd to IMEM once)
CONSTS = 0x5000         # 512-byte constants block (DMA'd to DMEM by the microcode every task)
TABLE = 0x5400          # level table: (triangles, command bytes, kernel iterations) x 3
TEX = 0x6000            # 32x32 RGBA5551 texture
CMDLIST = 0x10000       # RDP command list: header + 4000 triangles
FB = [0x100000, 0x140000]
ZBUF = 0x180000
WORK = 0x200000         # CPU work area (64 KB)
DEBUG = 0xA0000300

LEVELS = [(800, 1.0), (2000, 2.0), (4000, 3.0)]
FRAMES_PER_LEVEL = 240
CPU_WORK_ITERATIONS = 9000
W, H = 320, 240


class CPU(MIPS):
    """Tools/build_n64_roms.py's assembler plus the few R4300 instructions the bench needs."""

    def xor(self, d, s, t): self._r(0, s, t, d, 0, 0x26)

    def mtc0(self, t, rd): self.words.append((0x10 << 26) | (4 << 21) | (REGS[t] << 16) | (rd << 11))

    def _fpu(self, fn, fd, fs, ft): self.words.append((0x11 << 26) | (16 << 21) | (ft << 16) | (fs << 11) | (fd << 6) | fn)

    def add_s(self, fd, fs, ft): self._fpu(0, fd, fs, ft)
    def sub_s(self, fd, fs, ft): self._fpu(1, fd, fs, ft)
    def mul_s(self, fd, fs, ft): self._fpu(2, fd, fs, ft)
    def lwc1(self, ft, off, s): self.words.append((0x31 << 26) | (REGS[s] << 21) | (ft << 16) | (off & 0xFFFF))
    def swc1(self, ft, off, s): self.words.append((0x39 << 26) | (REGS[s] << 21) | (ft << 16) | (off & 0xFFFF))


class RSP(MIPS):
    """RSP assembler: scalar MIPS subset (from MIPS above) + COP0, COP2 vector ops, LWC2/SWC2. Origin = IMEM 0."""
    VOPS = {'vmulf': 0x00, 'vmudl': 0x04, 'vmudm': 0x05, 'vmudn': 0x06, 'vmudh': 0x07, 'vmacf': 0x08,
            'vmadl': 0x0C, 'vmadm': 0x0D, 'vmadn': 0x0E, 'vmadh': 0x0F, 'vadd': 0x10, 'vsub': 0x11,
            'vsar': 0x1D, 'vlt': 0x20, 'vge': 0x23, 'vcl': 0x24, 'vch': 0x25, 'vmrg': 0x27, 'vand': 0x28,
            'vor': 0x2A, 'vxor': 0x2C, 'vrcp': 0x30, 'vrcpl': 0x31, 'vrcph': 0x32}
    LOPS = {'lsv': (1, 2), 'llv': (2, 4), 'ldv': (3, 8), 'lqv': (4, 16)}
    SOPS = {'ssv': (1, 2), 'slv': (2, 4), 'sdv': (3, 8), 'sqv': (4, 16)}

    def xori(self, t, s, imm): self._i(0x0E, s, t, imm)
    def mtc0(self, t, rd): self.words.append((0x10 << 26) | (4 << 21) | (REGS[t] << 16) | (rd << 11))
    def mfc0(self, t, rd): self.words.append((0x10 << 26) | (0 << 21) | (REGS[t] << 16) | (rd << 11))
    def brk(self): self.words.append(0x0000000D)

    def v(self, op, vd, vs, vt, e=0):
        """vd = op(vs, vt[e]); for vrcp* vs is the destination element."""
        assert 0 <= vd < 32 and 0 <= vs < 32 and 0 <= vt < 32 and 0 <= e < 16
        self.words.append((0x12 << 26) | (1 << 25) | (e << 21) | (vt << 16) | (vs << 11) | (vd << 6) | self.VOPS[op])

    def lv(self, op, vt, e, off, base):
        code, scale = self.LOPS[op]
        assert off % scale == 0 and -64 <= off // scale < 64
        self.words.append((0x32 << 26) | (REGS[base] << 21) | (vt << 16) | (code << 11) | (e << 7) | ((off // scale) & 0x7F))

    def sv(self, op, vt, e, off, base):
        code, scale = self.SOPS[op]
        assert off % scale == 0 and -64 <= off // scale < 64
        self.words.append((0x3A << 26) | (REGS[base] << 21) | (vt << 16) | (code << 11) | (e << 7) | ((off // scale) & 0x7F))


# MARK: RSP microcode

def kernel(a):
    """One triangle's worth of RSP work (s5 = constants at DMEM 0, s6 = scratch at DMEM 0x200)."""
    v = a.v
    # A. transform + light two vertices (matrix rows int v24-v27, frac v28-v31)
    a.lv('ldv', 1, 0, 0x00, 's5'); a.lv('ldv', 1, 8, 0x08, 's5')
    for vd, src in ((2, 1), (4, 1)):
        a.lv('ldv', src + 4, 0, 0x10, 's5') if vd == 4 else None
        a.lv('ldv', src + 4, 8, 0x18, 's5') if vd == 4 else None
        v('vmudn', vd, 28, src, 4); v('vmadh', vd, 24, src, 4)
        v('vmadn', vd, 29, src, 5); v('vmadh', vd, 25, src, 5)
        v('vmadn', vd, 30, src, 6); v('vmadh', vd, 26, src, 6)
        v('vmadn', vd, 31, src, 7); v('vmadh', vd + 1, 27, src, 7)
        v('vmadn', vd, 0, 0, 8)
    v('vmulf', 6, 4, 20); v('vmacf', 6, 5, 21); v('vmacf', 6, 2, 22)
    v('vmudh', 7, 6, 23, 8); v('vadd', 7, 7, 19); v('vlt', 8, 7, 18); v('vmrg', 8, 7, 18)
    v('vch', 9, 3, 3, 7); v('vcl', 9, 2, 2, 7); v('vch', 10, 3, 17); v('vcl', 10, 2, 16)
    v('vrcph', 11, 0, 3, 11); v('vrcpl', 12, 0, 2, 11); v('vrcph', 11, 0, 0, 8)
    v('vrcph', 11, 4, 3, 15); v('vrcpl', 12, 4, 2, 15); v('vrcph', 11, 4, 0, 8)
    v('vmudl', 13, 2, 12, 7); v('vmadm', 13, 3, 12, 7); v('vmadn', 13, 2, 11, 7); v('vmadh', 14, 3, 11, 7)
    v('vmudn', 13, 13, 15); v('vmadh', 13, 14, 15); v('vmadn', 13, 29, 0, 8); v('vadd', 14, 14, 17)
    v('vmudh', 6, 1, 26, 9); v('vmadn', 6, 0, 0, 8)
    a.sv('sdv', 13, 0, 0x00, 's6'); a.sv('sdv', 13, 8, 0x08, 's6'); a.sv('sdv', 14, 0, 0x10, 's6')
    a.sv('sdv', 14, 8, 0x18, 's6'); a.sv('ssv', 9, 0, 0x20, 's6'); a.sv('slv', 8, 0, 0x24, 's6')
    # B. triangle setup
    for r, off in ((1, 0x00), (2, 0x10), (3, 0x28)):
        a.lv('ldv', r, 0, off, 's6'); a.lv('ldv', r, 8, off + 8, 's6')
    v('vlt', 4, 1, 2); v('vmrg', 5, 2, 1); v('vge', 6, 1, 2); v('vmrg', 7, 1, 2)
    v('vlt', 4, 5, 3); v('vmrg', 5, 3, 5); v('vge', 6, 7, 3); v('vmrg', 7, 7, 3)
    v('vsub', 8, 3, 1); v('vsub', 9, 2, 1); v('vsub', 10, 3, 2)
    v('vsub', 11, 7, 5); v('vsub', 12, 6, 4); v('vsub', 13, 7, 6)
    for src in (8, 9, 10):
        v('vrcph', 14, 1, src, 9); v('vrcpl', 15, 1, src, 9); v('vrcph', 14, 1, 0, 8)
    for src in (8, 9, 10):
        v('vmudl', 16, src, 15, 9); v('vmadm', 16, src, 14, 9); v('vmadn', 16, src, 15, 9); v('vmadh', 17, src, 14, 9)
    v('vmudh', 12, 8, 9, 9); v('vmadh', 12, 9, 8, 9); v('vsar', 13, 0, 0, 9); v('vsub', 12, 0, 12)
    v('vrcph', 14, 0, 12, 8); v('vrcpl', 15, 0, 13, 8); v('vrcph', 14, 0, 0, 8)
    for d1, d2 in ((11, 9), (13, 8)):
        v('vmudh', 18, d1, d2, 9); v('vmadh', 18, d2, d1, 9)
        v('vmudl', 19, 18, 15, 8); v('vmadm', 19, 18, 14, 8); v('vmadn', 19, 18, 15, 8); v('vmadh', 20, 18, 14, 8)
    v('vmudl', 21, 19, 17, 10); v('vmadm', 21, 20, 17, 10); v('vmadn', 21, 19, 16, 10); v('vmadh', 22, 20, 16, 10)
    v('vadd', 22, 22, 20)
    v('vmudn', 23, 22, 15, 8); v('vmadh', 23, 22, 14, 8); v('vmadn', 23, 0, 0, 8); v('vadd', 23, 23, 1)
    for r in (19, 20, 21, 22):
        v('vand', r, r, 30); v('vmudn', r, r, 31, 8)
    for i in range(22):   # the 176-byte triangle command
        a.sv('sdv', 16 + (i % 8), 0 if i % 2 == 0 else 8, 0x40 + 8 * i, 's6')
    a.lw('t0', 0x24, 's6'); a.addiu('t1', 't0', 1); a.slt('t2', 't1', 't0'); a.andi('t3', 't1', 0xFF)
    a.sw('t3', 0x28, 's6'); a.addiu('t4', 't4', 1)
    a.bne('t2', 't2', 'never')   # never taken (+ delay slot nop)
    a.or_('t5', 't3', 't4')


def microcode():
    a = RSP(0)
    a.lw('s0', 0xFF0, 'zero')     # RDP command list (RDRAM)
    a.lw('s1', 0xFF4, 'zero')     # its length in bytes
    a.lw('s2', 0xFE0, 'zero')     # kernel iterations
    a.lw('s3', 0xFE4, 'zero')     # constants block (RDRAM)
    a.mtc0('zero', 0)             # SP_MEM_ADDR = DMEM 0
    a.mtc0('s3', 1)               # SP_DRAM_ADDR
    a.li('t0', 511)
    a.mtc0('t0', 2)               # SP_RD_LEN: start the DMA
    a.jal('dma_wait')
    a.li('s5', 0)
    a.li('s6', 0x200)
    for i in range(24, 32):
        a.lv('lqv', i, 0, (i - 24) * 16, 's5')
    a.li('s7', 0x80)
    for i in range(15, 24):
        a.lv('lqv', i, 0, (i - 15) * 16, 's7')
    a.v('vxor', 0, 0, 0)
    a.beq('s2', 'zero', 'stream')
    a.label('kloop')
    start = len(a.words)
    kernel(a)
    a.label('never')
    a.addiu('s2', 's2', -1)
    a.bne('s2', 'zero', 'kloop')
    per_iteration = len(a.words) - start
    a.label('stream')
    a.li('t0', 2)
    a.mtc0('t0', 11)              # DPC_STATUS: set XBUS (the RDP reads commands from DMEM)
    a.li('s4', 0x400)
    a.label('sloop')
    a.beq('s1', 'zero', 'done')
    a.li('t1', 1024)
    a.slt('t2', 's1', 't1')
    a.beq('t2', 'zero', 'full')
    a.move('t1', 's1')
    a.label('full')
    a.mtc0('s4', 0)
    a.mtc0('s0', 1)
    a.addiu('t3', 't1', -1)
    a.mtc0('t3', 2)               # RDRAM → DMEM buffer
    a.jal('dma_wait')
    a.mtc0('s4', 8)               # DPC_START
    a.addu('t3', 's4', 't1')
    a.mtc0('t3', 9)               # DPC_END: the RDP takes the chunk
    a.addu('s0', 's0', 't1')
    a.subu('s1', 's1', 't1')
    a.xori('s4', 's4', 0xC00)     # 0x400 <-> 0x800
    a.j('sloop')
    a.label('done')
    a.li('t0', 0x1F8)             # SyncFull, kept in the constants block
    a.mtc0('t0', 8)
    a.li('t0', 0x200)
    a.mtc0('t0', 9)
    a.brk()
    a.nop()
    a.label('dma_wait')
    a.mfc0('t0', 6)               # SP_DMA_BUSY
    a.bne('t0', 'zero', 'dma_wait')
    a.jr('ra')
    a.nop()
    code = a.assemble()
    assert len(code) <= 0x1000, len(code)
    return code, per_iteration


def constants():
    rnd = random.Random(64)
    b = bytearray(512)
    for i in range(0, 0x1F8, 2):
        struct.pack_into('>h', b, i, rnd.randint(-0x4000, 0x4000) | 1)
    struct.pack_into('>II', b, 0x1F8, 0x29000000, 0)   # SyncFull
    return bytes(b)


# MARK: RDP command list

def fx16(v): return int(round(v * 65536.0)) & 0xFFFFFFFF


def attr_block(vals, dx, de, dy):
    """Shade / texture coefficient block: 4 attributes, each s15.16, split into int and frac halves."""
    def ints(a): return [(fx16(x) >> 16) & 0xFFFF for x in a]
    def fracs(a): return [fx16(x) & 0xFFFF for x in a]
    out = []
    for group in (ints(vals), ints(dx), fracs(vals), fracs(dx), ints(de), ints(dy), fracs(de), fracs(dy)):
        out += [(group[0] << 16) | group[1], (group[2] << 16) | group[3]]
    return out


def triangle(verts):
    """Shade + texture + Z-buffer triangle (RDP command 0x0F, 22 doublewords). verts: (x, y, z, r, g, b, a, s, t)."""
    v1, v2, v3 = sorted(verts, key=lambda p: p[1])
    x1, y1 = v1[0], math.floor(v1[1] * 4) / 4
    x2, y2 = v2[0], math.floor(v2[1] * 4) / 4
    x3, y3 = v3[0], math.floor(v3[1] * 4) / 4
    hx, hy, mx, my, lx, ly = x3 - x1, y3 - y1, x2 - x1, y2 - y1, x3 - x2, y3 - y2
    nz = hx * my - hy * mx
    lft = 1 if nz < 0 else 0
    ish = hx / hy if abs(hy) > 1e-9 else 0.0
    ism = mx / my if abs(my) > 1e-9 else 0.0
    isl = lx / ly if abs(ly) > 1e-9 else 0.0
    fy = math.floor(y1) - y1
    cy = math.ceil(4 * y2)
    xh = x1 + fy * ish
    xm = x1 + fy * ism
    xl = x2 + (cy / 4 - y2) * isl
    words = [(0x0F << 24) | (lft << 23) | (int(y3 * 4) & 0x3FFF),
             ((int(y2 * 4) & 0x3FFF) << 16) | (int(y1 * 4) & 0x3FFF),
             fx16(xl), fx16(isl), fx16(xh), fx16(ish), fx16(xm), fx16(ism)]
    det = mx * hy - my * hx

    def plane(i):
        a1, a2, a3 = v1[i], v2[i], v3[i]
        if abs(det) < 1e-9:
            return a1, 0.0, 0.0, 0.0
        dadx = ((a2 - a1) * hy - (a3 - a1) * my) / det
        dady = ((a3 - a1) * mx - (a2 - a1) * hx) / det
        dade = dady + dadx * ish
        return a1 + fy * dade, dadx, dade, dady

    shade = [plane(i) for i in (3, 4, 5, 6)]
    words += attr_block([p[0] for p in shade], [p[1] for p in shade], [p[2] for p in shade], [p[3] for p in shade])
    tex = [plane(i) for i in (7, 8)]
    tex = [(p[0] * 32, p[1] * 32, p[2] * 32, p[3] * 32) for p in tex]   # s10.5 texel coordinates
    tex += [(0x7FFF, 0.0, 0.0, 0.0), (0.0, 0.0, 0.0, 0.0)]                 # W = 1.0 (perspective path, no warp)
    words += attr_block([p[0] for p in tex], [p[1] for p in tex], [p[2] for p in tex], [p[3] for p in tex])
    z = plane(2)
    words += [fx16(z[0]), fx16(z[1]), fx16(z[2]), fx16(z[3])]
    assert len(words) == 44
    return words


def header_commands(fb_patch):
    """Clear Z and colour, set the 3D render state, load the texture. Returns words and the colour-image patch index."""
    w = []

    def cmd(a, b=0): w.extend([a & 0xFFFFFFFF, b & 0xFFFFFFFF])
    cmd(0x2D000000, ((W * 4) << 12) | (H * 4))                    # Set Scissor 0,0-320,240
    cmd(0x2F000000 | (3 << 20), 0)                                  # Set Other Modes: fill
    cmd(0x3F000000 | (2 << 19) | (W - 1), ZBUF)                     # Set Color Image = Z buffer
    cmd(0x37000000, 0xFFFCFFFC)                                     # Set Fill Color = max Z
    cmd(0x36000000 | (((W - 1) * 4) << 12) | ((H - 1) * 4), 0)      # Fill Rectangle
    cmd(0x27000000)                                                 # Sync Pipe
    fb_patch.append(len(w) + 1)
    cmd(0x3F000000 | (2 << 19) | (W - 1), FB[0])                    # Set Color Image = framebuffer (patched)
    cmd(0x37000000, 0x10A510A5)                                     # Set Fill Color: dark blue-grey
    cmd(0x36000000 | (((W - 1) * 4) << 12) | ((H - 1) * 4), 0)
    cmd(0x27000000)
    cmd(0x3E000000, ZBUF)                                           # Set Z Image
    # 1-cycle, perspective, bilinear; AA + Z compare/update + image read; blender: pixel x alpha + memory
    hi = (0 << 20) | (1 << 19) | (1 << 13) | (1 << 11) | (1 << 10) | (0 << 6) | (3 << 4)
    lo = (0 << 30) | (0 << 28) | (0 << 26) | (0 << 24) | (1 << 22) | (1 << 20) | (1 << 18) | (1 << 16) \
        | (1 << 13) | (0 << 10) | (1 << 8) | (1 << 6) | (1 << 5) | (1 << 4) | (1 << 3)
    cmd(0x2F000000 | hi, lo)
    # combiner: (TEXEL0 - 0) * SHADE + 0 for colour and alpha, both cycles
    hi = (1 << 20) | (4 << 15) | (1 << 12) | (4 << 9) | (1 << 5) | 4
    lo = (8 << 28) | (8 << 24) | (1 << 21) | (4 << 18) | (7 << 15) | (7 << 12) | (7 << 9) | (7 << 6) | (7 << 3) | 7
    cmd(0x3C000000 | hi, lo)
    cmd(0x3D000000 | (0 << 21) | (2 << 19) | (32 - 1), TEX)         # Set Texture Image RGBA16, 32 wide
    cmd(0x35000000 | (2 << 19) | (8 << 9) | 0, 7 << 24)             # Set Tile 7 (load)
    cmd(0x31000000)                                                 # Sync Load
    cmd(0x34000000, (7 << 24) | ((31 * 4) << 12) | (31 * 4))        # Load Tile 32x32
    cmd(0x28000000)                                                 # Sync Tile
    cmd(0x35000000 | (2 << 19) | (8 << 9) | 0, (0 << 24) | (5 << 14) | (5 << 4))   # Tile 0: wrap 32x32
    cmd(0x32000000, (0 << 24) | ((31 * 4) << 12) | (31 * 4))        # Set Tile Size
    return w


def scene():
    rnd = random.Random(1964)
    tris = []
    counts = [LEVELS[0][0]] + [LEVELS[i][0] - LEVELS[i - 1][0] for i in range(1, len(LEVELS))]
    fills = [LEVELS[0][1]] + [LEVELS[i][1] - LEVELS[i - 1][1] for i in range(1, len(LEVELS))]
    for count, fill in zip(counts, fills):
        area = fill * W * H / count
        side = math.sqrt(4 * area / math.sqrt(3))
        r = side / math.sqrt(3)
        for _ in range(count):
            cx = rnd.uniform(r + 1, W - r - 1)
            cy = rnd.uniform(r + 1, H - r - 1)
            rot = rnd.uniform(0, 2 * math.pi)
            z = rnd.uniform(0x20, 0xF0)
            toff = rnd.uniform(0, 32)
            verts = []
            for k in range(3):
                ang = rot + k * 2 * math.pi / 3
                x = min(max(cx + r * math.cos(ang), 0.0), W - 0.25)
                y = min(max(cy + r * math.sin(ang), 0.0), H - 0.25)
                verts.append((x, y, z + rnd.uniform(-4, 4),
                              rnd.uniform(60, 255), rnd.uniform(60, 255), rnd.uniform(60, 255), 255.0,
                              x * 0.75 + toff, y * 0.75 + toff))   # ~1 texel per pixel, like real surfaces
            tris.append(triangle(verts))
    return tris


def texture():
    out = bytearray()
    for y in range(32):
        for x in range(32):
            on = ((x >> 2) ^ (y >> 2)) & 1
            r, g, b = (31, 28, 20) if on else (12, 18, 30)
            out += struct.pack('>H', (r << 11) | (g << 6) | (b << 1) | 1)
    return bytes(out)


# MARK: CPU program

def program(fb_patch_word, per_iteration):
    a = CPU(0x80000000 | CODE)
    a.li('t0', 0x34000000)
    a.mtc0('t0', 12)               # Status: CU0 | CU1 | FR (FPU usable), interrupts off
    a.li('gp', DEBUG)
    for off in range(0, 0x14, 4):
        a.sw('zero', off, 'gp')
    a.li('t0', per_iteration)
    a.sw('t0', 0x10, 'gp')
    # VI: NTSC 320x240, 16-bit (same timing values as Tools/build_n64_roms.py), AA + resample filter
    a.lui('s0', 0xA440)
    for reg, value in [(0x04, FB[1]), (0x08, 320), (0x0C, 2), (0x14, 0x03E52239), (0x18, 0x20D),
                       (0x1C, 0xC15), (0x20, 0x0C150C15), (0x24, 0x006C02EC), (0x28, 0x002501FF),
                       (0x2C, 0x000E0204), (0x30, 0x200), (0x34, 0x400), (0x00, 0x320E)]:
        a.li('t0', value)
        a.sw('t0', reg, 's0')
    # microcode → IMEM (the SP is halted after boot)
    a.lui('t0', 0xA404)
    a.li('t1', 0x1000)
    a.sw('t1', 0x00, 't0')         # SP_MEM_ADDR = IMEM
    a.li('t1', UCODE)
    a.sw('t1', 0x04, 't0')         # SP_DRAM_ADDR
    a.li('t1', 0x1000 - 1)
    a.sw('t1', 0x08, 't0')         # SP_RD_LEN
    a.label('imem_wait')
    a.lw('t2', 0x18, 't0')         # SP_DMA_BUSY
    a.bne('t2', 'zero', 'imem_wait')
    # CPU work area: 1.5f / small integers
    a.li('t0', 0x80000000 | WORK)
    a.li('t1', 0x80000000 | WORK + 0x10000)
    a.li('t2', 0x3FC00000)
    a.label('winit')
    a.sw('t2', 8, 't0')
    a.sw('t2', 12, 't0')
    a.sw('t0', 0, 't0')
    a.addiu('t0', 't0', 32)
    a.bne('t0', 't1', 'winit')
    a.move('s1', 'zero')           # frame
    a.li('s2', FRAMES_PER_LEVEL)   # frames left in this level
    a.li('s3', 1)                  # level
    a.move('s7', 'zero')           # framebuffer index rendered next

    a.label('frame')
    a.lui('t0', 0xA430)
    a.label('wait_vi')
    a.lw('t1', 0x08, 't0')         # MI_INTR: VI
    a.andi('t1', 't1', 0x08)
    a.beq('t1', 'zero', 'wait_vi')
    a.sw('zero', 0x10, 's0')       # acknowledge (VI_CURRENT)
    a.addiu('s1', 's1', 1)
    a.sw('s1', 0x00, 'gp')
    a.addiu('s2', 's2', -1)
    a.bne('s2', 'zero', 'same_level')
    a.li('s2', FRAMES_PER_LEVEL)
    a.addiu('s3', 's3', 1)
    a.slti('t1', 's3', len(LEVELS) + 1)
    a.bne('t1', 'zero', 'same_level')
    a.li('s3', 1)
    a.label('same_level')
    # level parameters: TABLE + (level - 1) * 12
    a.addiu('t1', 's3', -1)
    a.sll('t2', 't1', 3)
    a.sll('t1', 't1', 2)
    a.addu('t1', 't1', 't2')
    a.li('t2', 0xA0000000 | TABLE)
    a.addu('t1', 't1', 't2')
    a.lw('s4', 0, 't1')            # triangles
    a.lw('s5', 4, 't1')            # command bytes
    a.lw('s6', 8, 't1')            # kernel iterations
    a.sw('s3', 0x04, 'gp')
    a.sw('s4', 0x08, 'gp')
    a.sw('s6', 0x0C, 'gp')
    # show what was rendered last frame, render into the other buffer
    a.li('t3', FB[1])
    a.beq('s7', 'zero', 'show')
    a.li('t3', FB[0])
    a.label('show')
    a.sw('t3', 0x04, 's0')         # VI_ORIGIN
    a.li('t4', FB[0])
    a.beq('s7', 'zero', 'target')
    a.li('t4', FB[1])
    a.label('target')
    a.li('t1', 0xA0000000 | CMDLIST + 4 * fb_patch_word)
    a.sw('t4', 0, 't1')            # Set Color Image address in the command list
    a.li('t1', 1)
    a.xor('s7', 's7', 't1')
    # OSTask in DMEM: type 1 (graphics), our fields
    a.lui('t0', 0xA400)
    a.li('t1', 1)
    a.sw('t1', 0xFC0, 't0')
    a.li('t1', CMDLIST)
    a.sw('t1', 0xFF0, 't0')
    a.sw('s5', 0xFF4, 't0')
    a.sw('s6', 0xFE0, 't0')
    a.li('t1', CONSTS)
    a.sw('t1', 0xFE4, 't0')
    a.lui('t0', 0xA408)
    a.sw('zero', 0x00, 't0')       # SP_PC = 0
    a.lui('t0', 0xA404)
    a.li('t1', 0x10D)              # clear halt, clear broke, clear intr, set interrupt-on-break
    a.sw('t1', 0x10, 't0')         # SP_STATUS: the RSP runs
    a.label('rsp_wait')
    a.lw('t1', 0x10, 't0')
    a.andi('t1', 't1', 1)
    a.beq('t1', 'zero', 'rsp_wait')
    a.li('t1', 0x08)
    a.sw('t1', 0x10, 't0')         # clear the SP interrupt
    a.lui('t0', 0xA430)
    a.li('t1', 0x800)
    a.sw('t1', 0x00, 't0')         # MI_MODE: clear the DP interrupt
    # game-like CPU work
    a.li('t9', CPU_WORK_ITERATIONS)
    a.li('a0', 0x80000000 | WORK)
    a.lui('v1', 0x8000 | (WORK >> 16))
    a.label('work')
    a.lw('t0', 0, 'a0')
    a.lw('t1', 4, 'a0')
    a.lwc1(0, 8, 'a0')
    a.lwc1(2, 12, 'a0')
    a.mul_s(4, 0, 2)
    a.add_s(6, 6, 4)
    a.mul_s(8, 4, 0)
    a.sub_s(10, 8, 2)
    a.swc1(10, 16, 'a0')
    a.addu('t2', 't0', 't1')
    a.sll('t3', 't2', 3)
    a.xor('t4', 't3', 't0')
    a.and_('t5', 't4', 't1')
    a.sw('t5', 20, 'a0')
    a.slt('t6', 't5', 't2')
    a.sh('t6', 24, 'a0')
    a.lbu('t7', 26, 'a0')
    a.addu('t8', 't8', 't7')
    a.addiu('a0', 'a0', 32)
    a.andi('v0', 'a0', 0xFFFF)
    a.or_('a0', 'v1', 'v0')
    a.addiu('t9', 't9', -1)
    a.bne('t9', 'zero', 'work')
    a.j('frame')
    return a.assemble()


def boot_stub(image_len):
    a = MIPS(0xA4000040)
    a.lui('t0', 0xA460)
    a.li('t1', CODE)
    a.sw('t1', 0x00, 't0')
    a.li('t1', 0x10001000)
    a.sw('t1', 0x04, 't0')
    a.li('t1', image_len - 1)
    a.sw('t1', 0x0C, 't0')
    a.label('wait')
    a.lw('t2', 0x10, 't0')
    a.andi('t2', 't2', 3)
    a.bne('t2', 'zero', 'wait')
    a.li('t3', 0x80000000 | CODE)
    a.jr('t3')
    a.nop()
    return a.assemble()


def build():
    ucode, per_iteration = microcode()
    patch = []
    header = header_commands(patch)
    tris = scene()
    cmd = list(header)
    for t in tris:
        cmd += t
    cmdbytes = b''.join(struct.pack('>I', x) for x in cmd)
    code = program(patch[0], per_iteration)
    image_len = (CMDLIST - CODE) + len(cmdbytes)
    image_len = (image_len + 0xFFF) & ~0xFFF
    image = bytearray(image_len)

    def put(addr, data):
        image[addr - CODE:addr - CODE + len(data)] = data
    assert len(code) <= UCODE - CODE
    put(CODE, code)
    put(UCODE, ucode)
    put(CONSTS, constants())
    table = b''
    for n, _ in LEVELS:
        table += struct.pack('>III', n, len(header) * 4 + n * 176, n)
    put(TABLE, table)
    put(TEX, texture())
    put(CMDLIST, cmdbytes)
    assert CMDLIST + len(cmdbytes) <= FB[0]
    rom = bytearray(max(0x100000, (0x1000 + image_len + 0xFFFFF) & ~0xFFFFF))
    rom[0:16] = struct.pack('>IIII', 0x80371240, 0x0000000F, 0x80000000 | CODE, 0x0000144B)
    rom[0x20:0x34] = b'RELICS RDP BENCH'.ljust(20)
    rom[0x3B:0x3F] = b'NZRE'
    stub = boot_stub(image_len)
    rom[0x40:0x40 + len(stub)] = stub
    rom[0x1000:0x1000 + image_len] = image
    with open(OUT, 'wb') as f:
        f.write(rom)
    print(f'{OUT}: {len(rom)} bytes; CPU {len(code)} B, microcode {len(ucode)} B '
          f'({per_iteration} RSP instructions per kernel iteration), command list {len(cmdbytes)} B')


if __name__ == '__main__':
    build()
