#!/usr/bin/env python3
"""Build SBLFIX.BIN, Mortal Kombat II's Sound Blaster driver with the Broken Record fix (mk2_sbl_dmapoll.S):
the playing half of the DMA buffer is read from the 8237 count, from the timer tick and the IRQ handler,
so the sound effects keep flowing when SBEMU's IRQs stop arriving. Same size as the original.

usage: mk2_sbl_build.py SBL.BIN SBLFIX.BIN        (needs GNU as/ld)
  0x0295  tick (function 3): cmp byte [217h],0  -> call tick; nop; nop
  0x06AF  init: port 0 -> autodetect   jne -> jmp (the autodetect code is overwritten)
  0x0935  sbl_dmapoll.S (88 bytes free)
  0x0B56  IRQ handler: swap [1C64h]/[1C66h]  -> nops
  0x0B6F  IRQ handler: call [107Ch] (mixer)  -> call poll; nop
"""
import hashlib, os, struct, subprocess, sys, tempfile
here = os.path.dirname(os.path.abspath(__file__))
MD5 = '0251aa45903c415ec705ddf28d1f1ac9'
BASE, END = 0x935, 0x98D

if len(sys.argv) != 3:
    sys.exit(__doc__)
d = bytearray(open(sys.argv[1], 'rb').read())
if hashlib.md5(d).hexdigest() != MD5:
    sys.exit('SBL.BIN: not the expected version (md5 %s)' % MD5)
with tempfile.TemporaryDirectory() as t:
    o, b = os.path.join(t, 'a.o'), os.path.join(t, 'a.bin')
    subprocess.run(['as', '--32', '-o', o, os.path.join(here, 'mk2_sbl_dmapoll.S')], check=True)
    subprocess.run(['ld', '-m', 'elf_i386', '-Ttext', hex(BASE), '--oformat', 'binary', '-e', '_start',
                    '-o', b, o], check=True)
    code = open(b, 'rb').read()
assert len(code) <= END - BASE, len(code)
tick, poll = BASE, BASE + 9     # poll follows "call poll; cmp byte [217h],0; ret" (3 + 5 + 1 bytes)

def patch(at, old, new):
    assert d[at:at + len(old)] == old, 'unexpected bytes at %#x' % at
    d[at:at + len(new)] = new

call = lambda at, to: b'\xe8' + struct.pack('<h', to - (at + 3))
patch(0x295, bytes.fromhex('803e170200'), call(0x295, tick) + b'\x90\x90')
patch(0x6AF, b'\x75\x12', b'\xeb\x12')
patch(BASE, d[BASE:BASE + len(code)], code)
patch(0xB56, bytes.fromhex('a1641c8706661ca3641c'), b'\x90' * 10)
patch(0xB6F, bytes.fromhex('ff167c10'), call(0xB6F, poll) + b'\x90')
assert code[9:10] == b'\x60', 'poll must start with pusha at +9'
open(sys.argv[2], 'wb').write(d)
print('wrote', sys.argv[2], '(%d bytes of code at %#x)' % (len(code), BASE))
