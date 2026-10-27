#!/usr/bin/env python3
"""Build the Broken Record fix for Grand Theft Auto (DOS, 8-bit version GTA8.EXE v11.5).

usage: gta_build.py GTA8.EXE OUT.EXE        (needs GNU as/ld)

Miles' digital service (address 0x118EFB) reads the SB driver's "playing half" flag, which only
the driver's IRQ handler flips. The patch replaces that read with a call to gta_dmapoll.S,
placed in 68 bytes of unused zero padding at 0x12AD40, which derives the playing half from
the 8237 DMA count instead:
  file 0x1AFE5F  8B 58 38 0F BF 1B -> E8 40 1E 01 00 90   call 0x12AD40
  file 0x1C1CA4  68 x 00           -> gta_dmapoll.S
Neither site carries a relocation (checked with le_load.py).
"""
import os, struct, subprocess, sys, tempfile
here = os.path.dirname(os.path.abspath(__file__))
HELPER, CALLSITE = 0x12AD40, 0x118EFB
F_CALL, F_HELPER = 0x1AFE5F, 0x1C1CA4
if len(sys.argv) != 3:
    sys.exit(__doc__)
with tempfile.TemporaryDirectory() as t:
    o, b = os.path.join(t, 'h.o'), os.path.join(t, 'h.bin')
    subprocess.run(['as', '--32', '-o', o, os.path.join(here, 'gta_dmapoll.S')], check=True)
    subprocess.run(['ld', '-m', 'elf_i386', '-Ttext', hex(HELPER), '--oformat', 'binary', '-e', '_start', '-o', b, o], check=True)
    helper = open(b, 'rb').read()
d = bytearray(open(sys.argv[1], 'rb').read())
call = b'\xe8' + struct.pack('<i', HELPER - (CALLSITE + 5)) + b'\x90'
for off, old, new in ((F_CALL, bytes.fromhex('8b58380fbf1b'), call), (F_HELPER, bytes(len(helper)), helper)):
    if d[off:off + len(old)] != old:
        sys.exit('mismatch at 0x%X: not GTA8.EXE v11.5 (md5 b1ed709d9a847f5a6565af3279543eeb)?' % off)
    d[off:off + len(new)] = new
open(sys.argv[2], 'wb').write(d)
print('wrote %s (helper %d bytes)' % (sys.argv[2], len(helper)))
