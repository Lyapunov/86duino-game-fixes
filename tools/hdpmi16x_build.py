#!/usr/bin/env python3
"""Build HDPMI16X.EXE: HDPMI16i (HX 2.23) that installs next to SBEMU's HDPMI32i.

usage: hdpmi16x_build.py HDPMI16i.EXE HDPMI16X.EXE
  HDPMI16i.EXE from HXRT223.zip (BIN/), github.com/Baron-von-Riedesel/HX/releases/tag/v2.23

Two patches (offsets in the file):
  0x0F7C  0F 85 5A 01 -> 0F 85 0A 00   A DPMI host that is HDPMI of another version (SBEMU's
          HDPMI32i is 3.20, this is 3.23) made HDPMI16i quit without installing. Now it installs
          as if no DPMI host were there (INIT.ASM: jnz initsvr_ex -> jnz nodpmi).
  0x2129  10 -> 50   An exception raised while the locked PM stack (LPMS) is in use gets its frame
          16 bytes below the client's SP on that same stack. Borland's RTM (16-bit) pushes FLAGS,
          CS, IP below the client's SP from its not-present handler and overwrote the frame. Now
          the frame sits 64 bytes lower (HDPMI.ASM lpms_call_exc: sub edi, sizeof DPMIEXC).
"""
import hashlib, sys
MD5 = '68d6a2714a0ddb538fad2d3dc3e7a782'
PATCHES = [(0x0F7C, '0f855a01', '0f850a00'), (0x2129, '10', '50')]
if len(sys.argv) != 3:
    sys.exit(__doc__)
d = bytearray(open(sys.argv[1], 'rb').read())
md5 = hashlib.md5(d).hexdigest()
if md5 != MD5:
    sys.exit('unexpected HDPMI16i.EXE (md5 %s), expected the one from HX 2.23' % md5)
for off, old, new in PATCHES:
    old, new = bytes.fromhex(old), bytes.fromhex(new)
    assert d[off:off + len(old)] == old, hex(off)
    d[off:off + len(new)] = new
open(sys.argv[2], 'wb').write(d)
print('wrote', sys.argv[2], hashlib.md5(d).hexdigest())
