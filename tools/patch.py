#!/usr/bin/env python3
"""Apply byte patches to a file, checking the original bytes first.

usage: patch.py IN.EXE OUT.EXE OFFSET:OLDHEX:NEWHEX [...]
  e.g. patch.py GPEGA.EXE GPEGA_A.EXE 0x7106:01:00 0x718E:01:00

Refuses to write anything if any OLD bytes don't match (wrong version of the game).
"""
import sys

if len(sys.argv) < 4:
    sys.exit(__doc__)
d = bytearray(open(sys.argv[1], 'rb').read())
for spec in sys.argv[3:]:
    off, old, new = spec.split(':')
    off, old, new = int(off, 0), bytes.fromhex(old), bytes.fromhex(new)
    if d[off:off + len(old)] != old:
        sys.exit('mismatch at 0x%X: expected %s, found %s' % (off, old.hex(), d[off:off + len(old)].hex()))
    d[off:off + len(new)] = new
open(sys.argv[2], 'wb').write(d)
print('patched %d site(s) -> %s' % (len(sys.argv) - 3, sys.argv[2]))
