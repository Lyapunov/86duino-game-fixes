#!/usr/bin/env python3
"""16-bit disassembly and pattern search for (unpacked) DOS .EXE files.

usage: dis16.py FILE.EXE START-END [START-END ...]   disassemble image ranges (hex)
       dis16.py FILE.EXE --scan                      list keyboard/timer related spots

Needs capstone:  pip install capstone
"""
import re, struct, sys
import capstone

f = open(sys.argv[1], 'rb').read()
img = f[struct.unpack_from('<H', f, 8)[0] * 16:]

if sys.argv[2] == '--scan':
    pats = {
        'in al,60h   (read scancode)':      b'\xe4\x60',
        'in al,64h   (KBC status)':         b'\xe4\x64',
        'out 64h,al  (KBC command)':        b'\xe6\x64',
        'out 60h,al  (KBC data)':           b'\xe6\x60',
        'in al,61h   (port B)':             b'\xe4\x61',
        'out 61h,al  (port B)':             b'\xe6\x61',
        'out 21h,al  (PIC mask)':           b'\xe6\x21',
        'out 43h,al  (PIT control)':        b'\xe6\x43',
        'out 40h,al  (PIT ch0 rate)':       b'\xe6\x40',
        'int 8       (call BIOS timer)':    b'\xcd\x08',
        'int 16h':                          b'\xcd\x16',
        'mov es:[20h],imm  (hook INT 8)':   b'\x26\xc7\x06\x20\x00',
        'mov es:[24h],imm  (hook INT 9)':   b'\x26\xc7\x06\x24\x00',
        'mov es:[58h],imm  (hook INT 16h)': b'\x26\xc7\x06\x58\x00',
        'mov es:[70h],imm  (hook INT 1Ch)': b'\x26\xc7\x06\x70\x00',
        'mov ah,25h  (DOS set vector)':     b'\xb4\x25',
    }
    for name, p in pats.items():
        hits = [hex(m.start()) for m in re.finditer(re.escape(p), img)]
        print('%-36s %3d  %s' % (name, len(hits), ' '.join(hits[:12])))
    sys.exit()

md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_16)
for r in sys.argv[2:]:
    s, e = (int(x, 16) for x in r.split('-'))
    for i in md.disasm(img[s:e], s):
        print('%05x: %-16s %s %s' % (i.address, i.bytes.hex(), i.mnemonic, i.op_str))
    print('-' * 40)
