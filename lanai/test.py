# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2022 Sergiusz Bazanski

# Run this manually to regenerate bram.bin.
# TODO: pipe this into Bazel, or just use a real assembler at some point.

import math
import struct

def serialize(l):
    bs = []
    for (nbits, val) in l:
        val = int(val)
        if val > 0 and math.log(val, 2) > nbits:
            raise Exception('too wide, {} bits, {}', nbits, val)
        bs.append(('{:0'+str(nbits)+'b}').format(val))
    return '_'.join(bs)

def op3bit(opcode):
    return {
        'add': 0, 'addc': 1, 'sub': 2, 'subb': 3, 'and': 4, 'or': 5, 'xor': 6,
        'sh': 7, 'sha': 7,
    }[opcode]

def op7bit(opcode):
    if opcode == 'sh':
        return 0b11110000
    if opcode == 'sha':
        return 0b11111000
    if opcode == 'sel':
        return 0b11100000
    return op3bit(opcode) << 5

def ri(opcode, rd, rs, flags, const):
    high = False
    if opcode in ['sh', 'sha']:
        if const > 31 or const < -31:
            raise Exception('invalid shift amount')
        const, = struct.unpack('>H', struct.pack('>h', const))
        high = opcode == 'sha'

    else:
        if (const & 0xffff) == 0:
            high = True
            const = const >> 16
        else:
            if (const >> 16) != 0:
                raise Exception("invalid constant {:032x}".format(const))
    return serialize([
        (1, 0),
        (3, op3bit(opcode)),
        (5, rd),
        (5, rs),
        (1, flags),
        (1, high),
        (16, const),
    ])

def rr(opcode, rd, rs1, flags, rs2, condition):
    return serialize([
        (4, 0b1100),
        (5, rd),
        (5, rs1),
        (1, flags),
        (1, condition & 1),
        (5, rs2),
        (8, op7bit(opcode)),
        (3, condition >> 1),
    ])

def rm(store, rd, rs1, p, q, constant):
    return serialize([
        (3, 0b100),
        (1, store),
        (5, rd),
        (5, rs1),
        (1, p),
        (1, q),
        (16, constant),
    ])

def regno(name):
    val = {
        'pc': 2, 'sw': 3, 'rv': 8, 'rr1': 10, 'rr2': 11,
    }.get(name)
    if val is not None:
        return val
    return int(name[1:])

def condno(name):
    return {
        't': 0, 'f': 1, 'hi': 2, 'ls': 3, 'cc': 4, 'cs': 5, 'ne': 6, 'eq': 7,
        'vc': 8, 'vs': 9, 'pl': 10, 'mi': 11, 'ge': 12, 'lt': 13, 'gt': 14,
        'le': 15
    }[name]

def asm(text):
    parts = text.split()
    opcode = parts[0]
    flags = opcode.endswith('.f')
    if flags:
        opcode = opcode[:-2]
    operands = [p.strip(',') for p in parts[1:]]
    registers = [regno(el[1:]) if el.startswith('%') else None for el in operands]
    imms = []
    for el in operands:
        try:
            val = int(el)
        except ValueError:
            try:
                val = int(el, 16)
            except ValueError:
                val = None
        imms.append(val)

    if opcode in ['add', 'addc', 'sub', 'subb', 'and', 'or', 'xor', 'sh', 'sha']:
        if len(operands) != 3:
            raise Exception('invalid operand count {}'.format(text))
        [src1, src2, dest] = registers
        if dest is None:
            raise Exception('destination must be register')
        if src1 is None:
            raise Exception('source must be register')
        if src2 is None:
            return ri(opcode, dest, src1, flags, imms[1])
        else:
            return rr(opcode, dest, src1, flags, src2, 0)

    if opcode.startswith('sel.'):
        cond = opcode.split('.')[1]
        [src1, src2, dest] = registers
        if dest is None:
            raise Exception('destination must be register')
        if src1 is None:
            raise Exception('source1 must be register')
        if src2 is None:
            raise Exception('source2 must be register')
        return rr('sel', dest, src1, flags, src2, condno(cond))

    if opcode in ['ld', 'st']:
        if len(operands) != 2:
            raise Exception('invalid operand count {}'.format(text))
        mo = 0
        ro = 1
        if opcode == 'st':
            mo = 1
            ro = 0

        parts = operands[mo].split('[')

        offs = None
        if len(parts) == 1:
            offs = 0
        else:
            offs = parts[0]
            parts = parts[1:]

        src = parts[0].split(']')[0]
        preincr = False
        postincr = False
        if src.endswith('++'):
            postincr = True
            offs = 4
            src = src[:-2]
        if src.endswith('*'):
            postincr = True
            src = src[:-1]
        if src.startswith('++'):
            preincr = True
            offs = 4
            src = src[2:]
        if src.startswith('*'):
            preincr = True
            src = src[1:]

        dest = registers[ro]
        offs = int(offs)
        src = regno(src[1:])

        p = False
        q = False
        if offs != 0:
            if preincr:
                p = True
                q = True
            elif postincr:
                q = True
            else:
                p = True

        return rm(opcode == 'st', dest, src, p, q, offs)


max_counter = int(25e6/7)
#max_counter = 5

insns = {
    #0:   'add %r0, {}, %r16'.format(max_counter & 0xffff),
    #4:   'or %r16, {}, %r16'.format(max_counter & 0xffff0000),
    #8:   'add %r0, 0, %r7',
    #12:  'add %r0, 0, %r4',
    ##16:  'add %r0, 0xf000, %r9',

    ##32:  'ld 0[%r9], %r14',
    ##36:  'ld [%r9++], %r14',
    ##40:  'ld 4[%r9], %r14',
    ##44:  'ld [++%r9], %r14',

    ##64:  'st %r14, 0[%r9]',
    ##68:  'st %r14, [%r9++]',
    ##72:  'st %r14, 4[%r9]',
    ##76:  'st %r14, [++%r9]',

    #16:  'add %r4, 1, %r4',
    #20:  'add %r7, 1, %r17',
    #24:  'sub.f %r4, %r16, %r10',

    #28:  'sel.pl %r17, %r7, %r7',
    #32:  'sel.pl %r0, %r4, %r4',
    #36:  'add %r0, 0x10, %pc',

    #0:   'add %r0, {}, %r16'.format(max_counter & 0xffff),
    #4:   'or %r16, {}, %r16'.format(max_counter & 0xffff0000),
    #8:   'add %r0, 0, %r7',
    #12:  'add %r0, 0, %r4',

    #16:  'add %r4, 1, %r4',
    #20:  'add %r7, 1, %r17',
    #24:  'sub.f %r4, %r16, %r0',

    #28:  'sel.eq %r17, %r7, %r7',
    #32:  'sel.eq %r0, %r4, %r4',
    #36:  'add %r0, 0x10, %pc',

    0:  'add %r0, 0xbee0, %r10',
    4:  'add %r0, 256, %r9',
    8:  'st %r10, 0[%r9]',
    12: 'ld 0[%r9++], %r11',
    16: 'add %r11, 1, %r7',
    20: 'add %r11, 2, %r7',
    24: 'add %r11, 3, %r7',
    28: 'add %r11, 4, %r7',

    60: 'add %r0, 0, %r11',
    64: 'add %r0, 512, %r9',
    68: 'st %r10, 0[%r9]',
    72: 'ld 0[%r9++], %r11',
    76: 'add %r11, 1, %r7',
    80: 'add %r11, 2, %r7',
    84: 'add %r11, 3, %r7',
    88: 'add %r11, 4, %r7',

    256: 'add %r0, 128, %pc',
}

ram = [0 for i in range(2**15)]

for addr, ins in insns.items():
    ins = int(asm(ins).replace('_', ''), 2)
    ram[addr+0] = (ins >> 24 ) & 0xff
    ram[addr+1] = (ins >> 16 ) & 0xff
    ram[addr+2] = (ins >> 8  ) & 0xff
    ram[addr+3] = (ins >> 0  ) & 0xff

with open('boards/ulx3s/bram.bin', 'w') as f:
    for i in range(0, len(ram), 4):
        el =  ram[i+0] << 24
        el |= ram[i+1] << 16
        el |= ram[i+2] << 8
        el |= ram[i+3]
        f.write('{:08x}\n'.format(el))
with open('lanai/bram.bin', 'w') as f:
    for i in range(0, len(ram), 4):
        el =  ram[i+0] << 24
        el |= ram[i+1] << 16
        el |= ram[i+2] << 8
        el |= ram[i+3]
        f.write('{:08x}\n'.format(el))
with open('bram.bin', 'wb') as f:
    for i in range(0, len(ram)):
        f.write(bytes([ram[i]]))
