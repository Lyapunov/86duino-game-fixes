#!/usr/bin/env python3
"""Build the Broken Record fix for Mortal Kombat 3 (DOS, MK3.EXE of 1 Nov 1995, Miles AIL 3.02).

usage: mk3_build.py MK3.EXE OUT.EXE        (needs GNU as/ld)

Miles' digital service (address 0x611A7) reads the SB driver's "playing half" flag, which only the
driver's IRQ handler flips. The patch replaces that read with a call to mk3_dmapoll.S, written over
an unused C-library routine at 0x4C3B9 (nothing calls or references it), which derives the playing
half from the 8237 DMA count instead:
  file 0xE15FB  8B 78 34 0F BF 3F -> E8 0D B2 FE FF 90   call 0x4C3B9
  file 0xCC80D  70 bytes          -> mk3_dmapoll.S
Neither site carries a relocation (checked with le_load.py).
"""
import os, struct, subprocess, sys, tempfile
here = os.path.dirname(os.path.abspath(__file__))
HELPER, CALLSITE = 0x4C3B9, 0x611A7
F_CALL, F_HELPER = 0xE15FB, 0xCC80D
OLD_HELPER = bytes.fromhex('5351525683ec0489c6e8c34302000c4089c389f089dae80b440200f6c720743b89f3b000b444cd21d1d2d1ca89142485d27d0d31c0668b0424e82d430200eb1d8a142489f380')
if len(sys.argv) != 3:
    sys.exit(__doc__)
with tempfile.TemporaryDirectory() as t:
    o, b = os.path.join(t, 'h.o'), os.path.join(t, 'h.bin')
    subprocess.run(['as', '--32', '-o', o, os.path.join(here, 'mk3_dmapoll.S')], check=True)
    subprocess.run(['ld', '-m', 'elf_i386', '-Ttext', hex(HELPER), '--oformat', 'binary', '-e', '_start', '-o', b, o], check=True)
    helper = open(b, 'rb').read()
assert len(helper) <= len(OLD_HELPER)
d = bytearray(open(sys.argv[1], 'rb').read())
call = b'\xe8' + struct.pack('<i', HELPER - (CALLSITE + 5)) + b'\x90'
for off, old, new in ((F_CALL, bytes.fromhex('8b78340fbf3f'), call), (F_HELPER, OLD_HELPER[:len(helper)], helper)):
    if d[off:off + len(old)] != old:
        sys.exit('mismatch at 0x%X: not MK3.EXE of 1 Nov 1995 (md5 35a7b1f0981050d8cc7cbe2ab0c2a3bd)?' % off)
    d[off:off + len(new)] = new
open(sys.argv[2], 'wb').write(d)
print('wrote %s (helper %d bytes)' % (sys.argv[2], len(helper)))
