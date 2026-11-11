#!/usr/bin/env python3
"""A small two-pass 6502 assembler, written in-repo for our own test ROMs.

Syntax (ca65-flavoured subset):
    NAME = expr            constant
    label:                 label (local labels start with '@' and are scoped to the last global label)
    .org $8000             set the program counter (pads with $FF if moving forward inside a bank)
    .db 1, $02, "TEXT"     bytes (strings are ASCII)
    .dw label, $1234       little-endian words
    .res n [, fill]        reserve n bytes
    .align n               pad to a multiple of n
    lda #<label  lda #>label   low / high byte
    Expressions: + - * / & | ^ << >> ( ), $hex %bin decimal 'c', and * for the current PC.
Addressing: #imm, zp, zp,x, zp,y, abs, abs,x, abs,y, (ind,x), (ind),y, (ind), A / implied, relative.
"""
import re
import sys

# mnemonic -> {mode: opcode}
OPS = {}
def _op(m, **modes):
    OPS[m] = modes

_op('adc', imm=0x69, zp=0x65, zpx=0x75, abs=0x6D, abx=0x7D, aby=0x79, izx=0x61, izy=0x71)
_op('and', imm=0x29, zp=0x25, zpx=0x35, abs=0x2D, abx=0x3D, aby=0x39, izx=0x21, izy=0x31)
_op('asl', acc=0x0A, zp=0x06, zpx=0x16, abs=0x0E, abx=0x1E)
_op('bit', zp=0x24, abs=0x2C)
for m, o in [('bpl', 0x10), ('bmi', 0x30), ('bvc', 0x50), ('bvs', 0x70), ('bcc', 0x90), ('bcs', 0xB0), ('bne', 0xD0), ('beq', 0xF0)]:
    _op(m, rel=o)
_op('brk', imp=0x00)
_op('cmp', imm=0xC9, zp=0xC5, zpx=0xD5, abs=0xCD, abx=0xDD, aby=0xD9, izx=0xC1, izy=0xD1)
_op('cpx', imm=0xE0, zp=0xE4, abs=0xEC)
_op('cpy', imm=0xC0, zp=0xC4, abs=0xCC)
_op('dec', zp=0xC6, zpx=0xD6, abs=0xCE, abx=0xDE)
_op('eor', imm=0x49, zp=0x45, zpx=0x55, abs=0x4D, abx=0x5D, aby=0x59, izx=0x41, izy=0x51)
for m, o in [('clc', 0x18), ('sec', 0x38), ('cli', 0x58), ('sei', 0x78), ('clv', 0xB8), ('cld', 0xD8), ('sed', 0xF8),
             ('dex', 0xCA), ('dey', 0x88), ('inx', 0xE8), ('iny', 0xC8), ('nop', 0xEA), ('pha', 0x48), ('php', 0x08),
             ('pla', 0x68), ('plp', 0x28), ('rti', 0x40), ('rts', 0x60), ('tax', 0xAA), ('tay', 0xA8), ('tsx', 0xBA),
             ('txa', 0x8A), ('txs', 0x9A), ('tya', 0x98)]:
    _op(m, imp=o)
_op('inc', zp=0xE6, zpx=0xF6, abs=0xEE, abx=0xFE)
_op('jmp', abs=0x4C, ind=0x6C)
_op('jsr', abs=0x20)
_op('lda', imm=0xA9, zp=0xA5, zpx=0xB5, abs=0xAD, abx=0xBD, aby=0xB9, izx=0xA1, izy=0xB1)
_op('ldx', imm=0xA2, zp=0xA6, zpy=0xB6, abs=0xAE, aby=0xBE)
_op('ldy', imm=0xA0, zp=0xA4, zpx=0xB4, abs=0xAC, abx=0xBC)
_op('lsr', acc=0x4A, zp=0x46, zpx=0x56, abs=0x4E, abx=0x5E)
_op('ora', imm=0x09, zp=0x05, zpx=0x15, abs=0x0D, abx=0x1D, aby=0x19, izx=0x01, izy=0x11)
_op('rol', acc=0x2A, zp=0x26, zpx=0x36, abs=0x2E, abx=0x3E)
_op('ror', acc=0x6A, zp=0x66, zpx=0x76, abs=0x6E, abx=0x7E)
_op('sbc', imm=0xE9, zp=0xE5, zpx=0xF5, abs=0xED, abx=0xFD, aby=0xF9, izx=0xE1, izy=0xF1)
_op('sta', zp=0x85, zpx=0x95, abs=0x8D, abx=0x9D, aby=0x99, izx=0x81, izy=0x91)
_op('stx', zp=0x86, zpy=0x96, abs=0x8E)
_op('sty', zp=0x84, zpx=0x94, abs=0x8C)

SIZE = dict(imp=1, acc=1, imm=2, zp=2, zpx=2, zpy=2, izx=2, izy=2, rel=2, abs=3, abx=3, aby=3, ind=3)


class AsmError(Exception):
    pass


class Assembler:
    def __init__(self):
        self.symbols = {}
        self.pc = 0
        self.scope = ''

    # -- expressions -------------------------------------------------------
    def _name(self, n):
        return self.scope + n if n.startswith('@') else n

    def eval(self, expr, strict):
        e = expr.strip()
        if e.startswith('<'):
            v = self.eval(e[1:], strict)
            return None if v is None else v & 0xFF
        if e.startswith('>'):
            v = self.eval(e[1:], strict)
            return None if v is None else (v >> 8) & 0xFF
        toks = re.findall(r"\$[0-9A-Fa-f]+|%[01]+|\d+|'.'|@?[A-Za-z_][A-Za-z0-9_]*|<<|>>|[-+*/&|^()~]", e)
        if ''.join(toks).replace(' ', '') != e.replace(' ', ''):
            raise AsmError(f'bad expression: {expr}')
        out = []
        prev_operand = False
        unknown = False
        for t in toks:
            if t[0] == '$':
                out.append(str(int(t[1:], 16))); prev_operand = True
            elif t[0] == '%':
                out.append(str(int(t[1:], 2))); prev_operand = True
            elif t[0].isdigit():
                out.append(t); prev_operand = True
            elif t[0] == "'":
                out.append(str(ord(t[1]))); prev_operand = True
            elif t[0] == '@' or t[0].isalpha() or t[0] == '_':
                n = self._name(t)
                if n in self.symbols:
                    out.append(str(self.symbols[n]))
                else:
                    if strict:
                        raise AsmError(f'undefined symbol: {t}')
                    unknown = True
                    out.append('0')
                prev_operand = True
            elif t == '*' and not prev_operand:
                out.append(str(self.pc)); prev_operand = True
            else:
                out.append('//' if t == '/' else t); prev_operand = (t == ')')
        if unknown:
            return None
        return int(eval(' '.join(out), {'__builtins__': {}}))

    # -- operands ----------------------------------------------------------
    def parse_operand(self, m, arg, strict, line_key, decisions):
        modes = OPS[m]
        a = arg.strip()
        if a == '' or a.lower() == 'a':
            if 'acc' in modes:
                return 'acc', None
            if 'imp' in modes:
                return 'imp', None
            raise AsmError(f'{m} needs an operand')
        if 'rel' in modes:
            return 'rel', a
        if a.startswith('#'):
            return 'imm', a[1:]
        mm = re.match(r'^\((.*),\s*[xX]\s*\)$', a)
        if mm:
            return 'izx', mm.group(1)
        mm = re.match(r'^\((.*)\)\s*,\s*[yY]$', a)
        if mm:
            return 'izy', mm.group(1)
        mm = re.match(r'^\((.*)\)$', a)
        if mm and 'ind' in modes:
            return 'ind', mm.group(1)
        idx = None
        mm = re.match(r'^(.*),\s*([xXyY])$', a)
        if mm:
            a, idx = mm.group(1), mm.group(2).lower()
        # zero page or absolute: decided in pass 1 and remembered
        if line_key in decisions:
            zp = decisions[line_key]
        else:
            v = self.eval(a, False)
            zp = v is not None and 0 <= v < 0x100
            decisions[line_key] = zp
        if idx is None:
            mode = 'zp' if zp and 'zp' in modes else 'abs'
        elif idx == 'x':
            mode = 'zpx' if zp and 'zpx' in modes else 'abx'
        else:
            mode = 'zpy' if zp and 'zpy' in modes else 'aby'
        if mode not in modes:
            raise AsmError(f'{m} does not support mode {mode}')
        return mode, a

    # -- assembly ----------------------------------------------------------
    def assemble(self, source, base, size, fill=0xFF):
        """Assemble `source` into a bank of `size` bytes starting at address `base`."""
        lines = source.split('\n')
        decisions = {}
        out = None
        for pass_no in (1, 2):
            strict = pass_no == 2
            out = bytearray([fill] * size)
            self.pc = base
            self.scope = ''

            def emit(*bs):
                for b in bs:
                    off = self.pc - base
                    if not (0 <= off < size):
                        raise AsmError(f'address ${self.pc:04X} outside bank ${base:04X}+{size:#x}')
                    out[off] = b & 0xFF
                    self.pc += 1

            for ln, raw in enumerate(lines, 1):
                try:
                    line = strip_comment(raw)
                    if not line.strip():
                        continue
                    mm = re.match(r'^\s*(@?[A-Za-z_][A-Za-z0-9_]*):(.*)$', line)
                    if mm:
                        name = mm.group(1)
                        if not name.startswith('@'):
                            self.scope = name
                        full = self._name(name)
                        if pass_no == 1 and full in self.symbols and self.symbols[full] != self.pc:
                            raise AsmError(f'duplicate label {name}')
                        self.symbols[full] = self.pc
                        line = mm.group(2)
                        if not line.strip():
                            continue
                    mm = re.match(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$', line)
                    if mm:
                        v = self.eval(mm.group(2), strict)
                        if v is not None:
                            self.symbols[mm.group(1)] = v
                        continue
                    parts = line.strip().split(None, 1)
                    op = parts[0].lower()
                    arg = parts[1] if len(parts) > 1 else ''
                    if op == '.org':
                        self.pc = self.eval(arg, True)
                    elif op == '.db' or op == '.byte':
                        for item in split_args(arg):
                            if item.startswith('"'):
                                for ch in item[1:-1]:
                                    emit(ord(ch))
                            else:
                                v = self.eval(item, strict)
                                emit(v if v is not None else 0)
                    elif op == '.dw' or op == '.word':
                        for item in split_args(arg):
                            v = self.eval(item, strict) or 0
                            emit(v & 0xFF, v >> 8)
                    elif op == '.res':
                        ps = split_args(arg)
                        n = self.eval(ps[0], True)
                        f = self.eval(ps[1], True) if len(ps) > 1 else fill
                        for _ in range(n):
                            emit(f)
                    elif op == '.align':
                        n = self.eval(arg, True)
                        while self.pc % n:
                            emit(fill)
                    elif op in OPS:
                        mode, expr = self.parse_operand(op, arg, strict, ln, decisions)
                        opcode = OPS[op][mode]
                        if mode in ('imp', 'acc'):
                            emit(opcode)
                        elif mode == 'rel':
                            target = self.eval(expr, strict)
                            if target is None:
                                emit(opcode, 0)
                            else:
                                d = target - (self.pc + 2)
                                if strict and not -128 <= d <= 127:
                                    raise AsmError(f'branch out of range ({d})')
                                emit(opcode, d & 0xFF)
                        else:
                            v = self.eval(expr, strict)
                            v = 0 if v is None else v
                            if SIZE[mode] == 2:
                                if strict and not -128 <= v <= 255:
                                    raise AsmError(f'operand ${v:X} does not fit in a byte')
                                emit(opcode, v & 0xFF)
                            else:
                                emit(opcode, v & 0xFF, (v >> 8) & 0xFF)
                    else:
                        raise AsmError(f'unknown instruction {op}')
                except AsmError as e:
                    raise AsmError(f'line {ln}: {raw.strip()}\n  {e}') from None
        return bytes(out)


def strip_comment(s):
    q = False
    for i, ch in enumerate(s):
        if ch == '"':
            q = not q
        elif ch == ';' and not q:
            return s[:i].rstrip()
    return s.rstrip()


def split_args(s):
    out, cur, q = [], '', False
    for ch in s:
        if ch == '"':
            q = not q
        if ch == ',' and not q:
            out.append(cur.strip()); cur = ''
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def ines(prg_banks, chr_banks, mapper=0, vertical=False, battery=False):
    """Build an iNES 1.0 image from 16 KB PRG banks and 8 KB CHR banks."""
    prg = b''.join(prg_banks)
    chr_ = b''.join(chr_banks)
    assert len(prg) % 0x4000 == 0 and len(chr_) % 0x2000 == 0
    flags6 = (1 if vertical else 0) | (2 if battery else 0) | ((mapper & 0x0F) << 4)
    flags7 = mapper & 0xF0
    header = b'NES\x1a' + bytes([len(prg) // 0x4000, len(chr_) // 0x2000, flags6, flags7]) + bytes(8)
    return header + prg + chr_


if __name__ == '__main__':
    src = open(sys.argv[1]).read()
    data = Assembler().assemble(src, 0x8000, 0x8000)
    sys.stdout.buffer.write(data)
