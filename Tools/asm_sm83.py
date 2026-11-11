#!/usr/bin/env python3
"""A small two-pass SM83 (Game Boy CPU) assembler, written in-repo for our own test ROMs.

Syntax (same flavour as asm6502.py):
    NAME = expr            constant
    label:                 label (local labels start with '@' and are scoped to the last global label)
    .org $0150             set the program counter
    .bank n                switch the output to 16 KB ROM bank n (n >= 1 assembles at $4000-$7FFF)
    .db 1, $02, "TEXT"     bytes (strings are ASCII)
    .dw label, $1234       little-endian words
    .res n [, fill]        reserve n bytes
    .align n               pad to a multiple of n
    Expressions: + - * / & | ^ << >> ~ ( ), $hex %bin decimal 'c', * for the current PC,
                 <expr / >expr for the low / high byte.
Operands: a b c d e h l (hl) bc de hl sp af, (bc) (de) (hl+) (hl-) (hli) (hld), (c) or ($ff00+c),
          (expr) for memory, conditions nz z nc c, sp+expr for `ld hl,sp+e`. [ ] work like ( ).
          A whole operand in parentheses is always a memory reference.
"""
import re
import sys

R8 = {'b': 0, 'c': 1, 'd': 2, 'e': 3, 'h': 4, 'l': 5, '(hl)': 6, 'a': 7}
R16 = {'bc': 0, 'de': 1, 'hl': 2, 'sp': 3}
R16S = {'bc': 0, 'de': 1, 'hl': 2, 'af': 3}
CC = {'nz': 0, 'z': 1, 'nc': 2, 'c': 3}
ALU = {'add': 0, 'adc': 1, 'sub': 2, 'sbc': 3, 'and': 4, 'xor': 5, 'or': 6, 'cp': 7}
SHIFTS = {'rlc': 0, 'rrc': 1, 'rl': 2, 'rr': 3, 'sla': 4, 'sra': 5, 'swap': 6, 'srl': 7}
IMPLIED = {'nop': [0x00], 'halt': [0x76], 'stop': [0x10, 0x00], 'di': [0xF3], 'ei': [0xFB],
           'daa': [0x27], 'cpl': [0x2F], 'scf': [0x37], 'ccf': [0x3F], 'rlca': [0x07], 'rrca': [0x0F],
           'rla': [0x17], 'rra': [0x1F], 'reti': [0xD9]}


class AsmError(Exception):
    pass


def strip_comment(s):
    q = False
    for i, ch in enumerate(s):
        if ch == '"':
            q = not q
        elif ch == ';' and not q:
            return s[:i].rstrip()
    return s.rstrip()


def split_args(s):
    out, cur, q, depth = [], '', False, 0
    for ch in s:
        if ch == '"':
            q = not q
        if not q:
            if ch in '([':
                depth += 1
            elif ch in ')]':
                depth -= 1
        if ch == ',' and not q and depth == 0:
            out.append(cur.strip()); cur = ''
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def wrapped(s):
    """True if the whole string is one parenthesised group."""
    if not (s.startswith('(') and s.endswith(')')):
        return False
    depth = 0
    for i, ch in enumerate(s):
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0 and i != len(s) - 1:
                return False
    return True


def classify(raw):
    """Returns (kind, value): reg8, reg16, ind (bc/de/hl+/hl-/c), mem (expr), imm (expr), spe (expr)."""
    s = raw.strip().replace('[', '(').replace(']', ')')
    k = s.lower().replace(' ', '')
    if k in R8:
        return 'r8', k
    if k in ('bc', 'de', 'hl', 'sp', 'af'):
        return 'r16', k
    if k in ('(bc)', '(de)'):
        return 'ind', k[1:3]
    if k in ('(hl+)', '(hli)'):
        return 'ind', 'hl+'
    if k in ('(hl-)', '(hld)'):
        return 'ind', 'hl-'
    if k in ('(c)', '($ff00+c)', '(0xff00+c)'):
        return 'ind', 'c'
    if k.startswith('sp+') or k.startswith('sp-'):
        e = s.strip()[2:].strip()
        return 'spe', e[1:] if e.startswith('+') else e
    if wrapped(s):
        return 'mem', s[1:-1]
    return 'imm', s


class Assembler:
    def __init__(self):
        self.symbols = {}
        self.pc = 0
        self.bank = 0
        self.scope = ''

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
        toks = re.findall(r"\$[0-9A-Fa-f]+|0x[0-9A-Fa-f]+|%[01]+|\d+|'.'|@?[A-Za-z_][A-Za-z0-9_]*|<<|>>|[-+*/&|^()~]", e)
        if ''.join(toks).replace(' ', '') != e.replace(' ', ''):
            raise AsmError(f'bad expression: {expr}')
        out = []
        prev_operand = False
        unknown = False
        for t in toks:
            if t[0] == '$':
                out.append(str(int(t[1:], 16))); prev_operand = True
            elif t.startswith('0x'):
                out.append(str(int(t[2:], 16))); prev_operand = True
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

    # -- encoding: returns a list of ints and ('n8'|'n16'|'rel'|'s8'|'hi8', expr) items
    def encode(self, m, args):
        ops = [classify(a) for a in args]
        kinds = tuple(o[0] for o in ops)
        vals = [o[1] for o in ops]

        def bad():
            raise AsmError(f'unsupported operands for {m}: {", ".join(args)}')

        if m in IMPLIED and not ops:
            return list(IMPLIED[m])
        if m == 'ret':
            if not ops:
                return [0xC9]
            if vals[0] in CC:
                return [0xC0 | CC[vals[0]] << 3]
            bad()
        if m == 'ld':
            if len(ops) != 2:
                bad()
            (k1, v1), (k2, v2) = ops
            if k1 == 'r8' and k2 == 'r8':
                if v1 == '(hl)' and v2 == '(hl)':
                    bad()
                return [0x40 | R8[v1] << 3 | R8[v2]]
            if k1 == 'r8' and k2 == 'imm':
                return [0x06 | R8[v1] << 3, ('n8', v2)]
            if k1 == 'r8' and v1 == 'a' and k2 == 'ind':
                return [{'bc': 0x0A, 'de': 0x1A, 'hl+': 0x2A, 'hl-': 0x3A, 'c': 0xF2}[v2]]
            if k1 == 'ind' and k2 == 'r8' and v2 == 'a':
                return [{'bc': 0x02, 'de': 0x12, 'hl+': 0x22, 'hl-': 0x32, 'c': 0xE2}[v1]]
            if k1 == 'r8' and v1 == 'a' and k2 == 'mem':
                return [0xFA, ('n16', v2)]
            if k1 == 'mem' and k2 == 'r8' and v2 == 'a':
                return [0xEA, ('n16', v1)]
            if k1 == 'r16' and v1 in R16 and k2 == 'imm':
                return [0x01 | R16[v1] << 4, ('n16', v2)]
            if k1 == 'mem' and k2 == 'r16' and v2 == 'sp':
                return [0x08, ('n16', v1)]
            if k1 == 'r16' and v1 == 'sp' and k2 == 'r16' and v2 == 'hl':
                return [0xF9]
            if k1 == 'r16' and v1 == 'hl' and k2 == 'spe':
                return [0xF8, ('s8', v2)]
            bad()
        if m == 'ldh':
            if kinds == ('mem', 'r8') and vals[1] == 'a':
                return [0xE0, ('hi8', vals[0])]
            if kinds == ('r8', 'mem') and vals[0] == 'a':
                return [0xF0, ('hi8', vals[1])]
            if kinds == ('ind', 'r8') and vals[0] == 'c':
                return [0xE2]
            if kinds == ('r8', 'ind') and vals[1] == 'c':
                return [0xF2]
            bad()
        if m in ('inc', 'dec'):
            if kinds == ('r8',):
                return [(0x04 if m == 'inc' else 0x05) | R8[vals[0]] << 3]
            if kinds == ('r16',) and vals[0] in R16:
                return [(0x03 if m == 'inc' else 0x0B) | R16[vals[0]] << 4]
            bad()
        if m == 'add' and kinds == ('r16', 'r16') and vals[0] == 'hl' and vals[1] in R16:
            return [0x09 | R16[vals[1]] << 4]
        if m == 'add' and kinds == ('r16', 'imm') and vals[0] == 'sp':
            return [0xE8, ('s8', vals[1])]
        if m in ALU:
            if len(ops) == 2 and kinds[0] == 'r8' and vals[0] == 'a':
                ops, kinds, vals = ops[1:], kinds[1:], vals[1:]
            if kinds == ('r8',):
                return [0x80 | ALU[m] << 3 | R8[vals[0]]]
            if kinds == ('imm',):
                return [0xC6 | ALU[m] << 3, ('n8', vals[0])]
            bad()
        if m == 'jp':
            if kinds == ('imm',):
                return [0xC3, ('n16', vals[0])]
            if kinds in (('r16',), ('r8',)) and vals[0] in ('hl', '(hl)'):
                return [0xE9]
            if len(ops) == 2 and args[0].strip().lower() in CC and kinds[1] == 'imm':
                return [0xC2 | CC[args[0].strip().lower()] << 3, ('n16', vals[1])]
            bad()
        if m == 'jr':
            if kinds == ('imm',):
                return [0x18, ('rel', vals[0])]
            if len(ops) == 2 and args[0].strip().lower() in CC and kinds[1] == 'imm':
                return [0x20 | CC[args[0].strip().lower()] << 3, ('rel', vals[1])]
            bad()
        if m == 'call':
            if kinds == ('imm',):
                return [0xCD, ('n16', vals[0])]
            if len(ops) == 2 and args[0].strip().lower() in CC and kinds[1] == 'imm':
                return [0xC4 | CC[args[0].strip().lower()] << 3, ('n16', vals[1])]
            bad()
        if m == 'rst' and kinds == ('imm',):
            return [('rst', vals[0])]
        if m in ('push', 'pop') and kinds == ('r16',) and vals[0] in R16S:
            return [(0xC5 if m == 'push' else 0xC1) | R16S[vals[0]] << 4]
        if m in SHIFTS and kinds == ('r8',):
            return [0xCB, SHIFTS[m] << 3 | R8[vals[0]]]
        if m in ('bit', 'res', 'set') and kinds == ('imm', 'r8'):
            base = {'bit': 0x40, 'res': 0x80, 'set': 0xC0}[m]
            return [0xCB, ('bit', (base, vals[0], R8[vals[1]]))]
        bad()

    @staticmethod
    def size_of(items):
        n = 0
        for it in items:
            n += 2 if isinstance(it, tuple) and it[0] == 'n16' else 1
        return n

    def assemble(self, source, size, fill=0xFF):
        """Assemble into a flat ROM image of `size` bytes (bank 0 at $0000, `.bank n` at $4000)."""
        lines = source.split('\n')
        out = None
        for pass_no in (1, 2):
            strict = pass_no == 2
            out = bytearray([fill] * size)
            written = set()
            self.pc = 0
            self.bank = 0
            self.scope = ''

            def emit(*bs):
                for bv in bs:
                    if self.bank == 0:
                        off = self.pc
                        ok = 0 <= self.pc < 0x8000
                    else:
                        off = self.bank * 0x4000 + self.pc - 0x4000
                        ok = 0x4000 <= self.pc < 0x8000
                    if not ok or not (0 <= off < size):
                        raise AsmError(f'address ${self.pc:04X} (bank {self.bank}) outside the ROM')
                    if off in written:
                        raise AsmError(f'address ${self.pc:04X} (bank {self.bank}) assembled twice (overlap)')
                    written.add(off)
                    out[off] = bv & 0xFF
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
                    elif op == '.bank':
                        self.bank = self.eval(arg, True)
                        self.pc = 0x4000 if self.bank > 0 else 0
                    elif op in ('.db', '.byte'):
                        for item in split_args(arg):
                            if item.startswith('"'):
                                for ch in item[1:-1]:
                                    emit(ord(ch))
                            else:
                                v = self.eval(item, strict)
                                emit(v if v is not None else 0)
                    elif op in ('.dw', '.word'):
                        for item in split_args(arg):
                            v = self.eval(item, strict) or 0
                            emit(v & 0xFF, (v >> 8) & 0xFF)
                    elif op == '.res':
                        ps = split_args(arg)
                        n = self.eval(ps[0], True)
                        fv = self.eval(ps[1], True) if len(ps) > 1 else fill
                        for _ in range(n):
                            emit(fv)
                    elif op == '.align':
                        n = self.eval(arg, True)
                        while self.pc % n:
                            emit(fill)
                    else:
                        items = self.encode(op, split_args(arg))
                        start = self.pc
                        for it in items:
                            if isinstance(it, int):
                                emit(it)
                                continue
                            kind, expr = it
                            if kind == 'bit':
                                base, nexpr, r = expr
                                n = self.eval(nexpr, True)
                                if not 0 <= n <= 7:
                                    raise AsmError(f'bit number {n} out of range')
                                emit(base | n << 3 | r)
                                continue
                            v = self.eval(expr, strict)
                            if kind == 'rst':
                                v = 0 if v is None else v
                                if v & ~0x38:
                                    raise AsmError(f'bad rst target {v:#x}')
                                emit(0xC7 | v)
                            elif kind == 'rel':
                                if v is None:
                                    emit(0)
                                else:
                                    dist = v - (start + 2)
                                    if strict and not -128 <= dist <= 127:
                                        raise AsmError(f'jr out of range ({dist})')
                                    emit(dist & 0xFF)
                            elif kind == 'n16':
                                v = 0 if v is None else v
                                emit(v & 0xFF, (v >> 8) & 0xFF)
                            elif kind == 'hi8':
                                v = 0 if v is None else v
                                if 0xFF00 <= v <= 0xFFFF:
                                    v -= 0xFF00
                                if strict and not 0 <= v <= 0xFF:
                                    raise AsmError(f'ldh address ${v:X} not in $FF00-$FFFF')
                                emit(v)
                            else:  # n8, s8
                                v = 0 if v is None else v
                                if strict and not -128 <= v <= 255:
                                    raise AsmError(f'operand ${v:X} does not fit in a byte')
                                emit(v & 0xFF)
                except AsmError as e:
                    raise AsmError(f'line {ln}: {raw.strip()}\n  {e}') from None
        return bytes(out)


def gb_header(rom, title, cgb_flag=0x00, cart_type=0x00, ram_size=0x00):
    """Fills in the cartridge header (no boot logo: $0104-$0133 stay zero) and both checksums."""
    rom = bytearray(rom)
    for i in range(0x104, 0x134):
        rom[i] = 0
    t = title.encode('ascii')[:15 if cgb_flag else 16]
    for i in range(0x134, 0x144):
        rom[i] = 0
    rom[0x134:0x134 + len(t)] = t
    if cgb_flag:
        rom[0x143] = cgb_flag
    rom[0x144] = rom[0x145] = 0
    rom[0x146] = 0
    rom[0x147] = cart_type
    banks = len(rom) // 0x4000
    rom[0x148] = {2: 0, 4: 1, 8: 2, 16: 3, 32: 4, 64: 5, 128: 6, 256: 7, 512: 8}[banks]
    rom[0x149] = ram_size
    rom[0x14A] = 1       # non-Japanese
    rom[0x14B] = 0x33    # use the new licensee field
    rom[0x14C] = 0       # version
    s = 0
    for i in range(0x134, 0x14D):
        s = (s - rom[i] - 1) & 0xFF
    rom[0x14D] = s
    rom[0x14E] = rom[0x14F] = 0
    g = sum(rom) & 0xFFFF
    rom[0x14E] = g >> 8
    rom[0x14F] = g & 0xFF
    return bytes(rom)


if __name__ == '__main__':
    src = open(sys.argv[1]).read()
    sys.stdout.buffer.write(Assembler().assemble(src, 0x8000))
