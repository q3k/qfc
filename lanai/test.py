# Run this manually to regenerate bram.bin.
# TODO: pipe this into Bazel, or just use a real assembler at some point.


insns = {
    0:   '0_101_01000_00000_11_1011111011101111',   # or r8, r0, beef0000
    4:   '0_101_01001_00000_10_1101111010101101',   # or r9, r0, 0000dead
    8:   '0_000_01000_01000_11_1101111010101101',   # add r8, r8, dead0000
    12:  '0_001_01001_01001_10_1011111011101111',   # addc r9, r9, beef
    16:  '0_111_01010_01000_10_1111111111111000',   # srl r10, r8, 8
    20:  '0_111_01011_01000_11_1111111111111000',   # sra r11, r8, 8
    24:  '0_111_01010_01010_10_0000000000001000',   # sll r10, r10, 8
    28:  '0_111_01011_01011_11_0000000000001000',   # sla r11, r11, 8
    32:  '0_101_01000_00000_10_1011111011101111',   # or r8, r0, 0000beef
    36:  '0_101_01000_01000_11_1101111010101101',   # or r8, r8, dead0000
    40:  '0_101_01001_00000_10_0000000000000001',   # or r9, r0, 00000001

    64:  '0_000_00111_00111_10_0000000000000001',   # add r7, r7, 1
    68:  '0_101_00010_00000_10_0000000001000000',   # or pc, r0, 0x40
}

ram = [0 for i in range(2**15)]

for addr, ins in insns.items():
    ins = int(ins.replace('_', ''), 2)
    ram[addr+0] = (ins >> 24 ) & 0xff
    ram[addr+1] = (ins >> 16 ) & 0xff
    ram[addr+2] = (ins >> 8  ) & 0xff
    ram[addr+3] = (ins >> 0  ) & 0xff

with open('bram.bin', 'w') as f:
    for i in range(0, len(ram), 4):
        el =  ram[i+0] << 24
        el |= ram[i+1] << 16
        el |= ram[i+2] << 8
        el |= ram[i+3]
        f.write('{:08x}\n'.format(el))
