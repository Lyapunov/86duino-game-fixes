#!/usr/bin/env python3
"""California Games II (CGII.EXE): Tick Starvation fix, hand-assembled.

The 60 Hz timer ISR at 1A0E never calls the BIOS INT 8. The new ISR (same
69 bytes) adds the PIT divisor 4DAEh to a 16-bit accumulator each tick and
calls the old INT 8 (saved at [3BA4]) on every carry, i.e. at 18.2 Hz; the
BIOS then sends the EOI.  The accumulator is the game's own tick counter
[3E04], which was only used to fix the DOS clock up afterwards; that fix-up
(5FAC) becomes a plain RET because the BIOS clock now runs by itself.
usage: python3 cgii_build.py CGII_unp.EXE [-v]   (needs capstone for -v)
Prints image offset, old and new bytes; file offsets come from exepack_map.py.
"""
import struct, sys, capstone

ISR = bytes.fromhex(
    'fa'                    # 1A0E cli
    '50 53 51 52 56 57 55 1e 06'  # push ax bx cx dx si di bp ds es
    '2e 8e 1e 2e 5e'        # mov ds,cs:[5E2E]
    'ff 1e 10 0c'           # call far [0C10]       (sound hook, as before)
    '2e 8e 1e 2e 5e'        # mov ds,cs:[5E2E]
    'a1 30 0c'              # mov ax,[0C30]
    'ff d0'                 # call ax               (per-tick game routine)
    '83 3e 18 3e 00'        # cmp word [3E18],0
    '7d 04'                 # jge +4
    'ff 0e 62 38'           # dec word [3862]
    '81 06 04 3e ae 4d'     # add word [3E04],4DAEh
    '72 0e'                 # jc chain
    'b0 20 e6 20'           # mov al,20h / out 20h,al   (EOI)
    '07 1f 5d 5f 5e 5a 59 5b 58'  # x: pop es ds bp di si dx cx bx ax
    'cf'                    # iret
    '9c'                    # chain: pushf
    'ff 1e a4 3b'           # call far [3BA4]      (BIOS INT 8, sends EOI)
    'eb ef'                 # jmp x
)
SITES = [(0x1a0e, ISR), (0x5fac, b'\xc3')]

f = open(sys.argv[1], 'rb').read()
img = f[struct.unpack_from('<H', f, 8)[0] * 16:]
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_16)
for at, new in SITES:
    old = img[at:at + len(new)]
    print('%04x %d %s:%s' % (at, len(new), old.hex(), new.hex()))
    if '-v' in sys.argv:
        for i in md.disasm(new, at):
            print('   %05x: %-14s %s %s' % (i.address, i.bytes.hex(), i.mnemonic, i.op_str))
