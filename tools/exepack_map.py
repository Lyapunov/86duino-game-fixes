#!/usr/bin/env python3
"""Translate offsets in the unpacked image to file offsets in the packed .EXE.

usage: exepack_map.py PACKED.EXE IMAGE_OFFSET_HEX [...]

"Image offset" is the address as shown by dis16.py (segment*16 + offset,
counted from the start of the load image).  If a byte came from a fill run it
cannot be patched in place and the script says so.
"""
import sys
from unexepack import unpack

if len(sys.argv) < 3:
    sys.exit(__doc__)
f = open(sys.argv[1], 'rb').read()
u = unpack(f)
for a in sys.argv[2:]:
    o = int(a, 16)
    p = o if o <= u['lead'] else u['origin'].get(o)
    if p is None:
        print('%s  -> inside a fill run, cannot patch in place' % a)
    else:
        fo = p + u['hp']
        print('%s  -> file offset 0x%X   bytes there: %s' % (a, fo, f[fo:fo + 8].hex(' ')))
