#!/usr/bin/env python3
"""Check which files a Command & Conquer (1995) .MIX archive contains.

usage: mixid.py FILE.MIX NAME [NAME ...]
  e.g. mixid.py MOVIES.MIX GDI1.VQA NOD1PRE.VQA

A Tiberian Dawn MIX stores no file names, only a 32-bit ID per file, so the
names to look for have to be supplied. The ID is computed from the upper-case
name, padded with zero bytes to a multiple of 4: for each little-endian dword,
id = rol(id, 1) + dword.
"""
import struct
import sys


def mix_id(name):
    b = name.upper().encode()
    b += b'\0' * (-len(b) % 4)
    i = 0
    for k in range(0, len(b), 4):
        i = ((i << 1) | (i >> 31)) & 0xFFFFFFFF
        i = (i + struct.unpack_from('<I', b, k)[0]) & 0xFFFFFFFF
    return i


def index(path):
    with open(path, 'rb') as f:
        n, size = struct.unpack('<HI', f.read(6))
        return {struct.unpack('<III', f.read(12))[0] for _ in range(n)}


if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    ids = index(sys.argv[1])
    print('%s: %d entries' % (sys.argv[1], len(ids)))
    for name in sys.argv[2:]:
        print('  %-14s %s' % (name, 'present' if mix_id(name) in ids else 'missing'))
