#!/usr/bin/env python3
"""Unpack a Microsoft EXEPACK-compressed DOS .EXE so it can be disassembled.

usage: unexepack.py PACKED.EXE UNPACKED.EXE

The unpacked file is for analysis.  Patch the original packed file instead
(see exepack_map.py), so the game stays byte-for-byte what it was.
"""
import struct, sys

def unpack(f):
    hp = struct.unpack_from('<H', f, 8)[0] * 16            # header size
    img = f[hp:]
    cs = struct.unpack_from('<H', f, 0x16)[0]               # stub segment
    hb = cs * 16
    ip, rcs, _, _, sp, ss, dlen, sig = struct.unpack_from('<8H', img, hb)
    if sig != 0x4252:                                       # 18-byte header has
        ip, rcs, _, _, sp, ss, dlen, _, sig = struct.unpack_from('<9H', img, hb)
    if sig != 0x4252:                                       # an extra skip_len
        sys.exit('not an EXEPACK file (no "RB" signature)')
    src = img[:hb]
    dst = bytearray(dlen * 16)
    dst[:len(src)] = src
    s = len(src) - 1
    while src[s] == 0xFF:                                   # skip padding
        s -= 1
    d = dlen * 16 - 1
    origin = {}                                             # dest -> packed offset
    while True:                                             # runs go backwards
        cmd = src[s]; s -= 1
        n = src[s] << 8 | src[s - 1]; s -= 2
        if cmd & 0xFE == 0xB0:                              # fill run
            b = src[s]; s -= 1
            for _ in range(n):
                dst[d] = b; origin[d] = None; d -= 1
        elif cmd & 0xFE == 0xB2:                            # literal copy
            for _ in range(n):
                dst[d] = src[s]; origin[d] = s; d -= 1; s -= 1
        else:
            sys.exit('bad EXEPACK command %02x' % cmd)
        if cmd & 1:
            break
    lead = d                                                # dst[0..lead] == src[0..lead]
    m = img.find(b'Packed file is corrupt', hb) + 22
    relocs, p = [], m
    for seg in range(16):
        n = struct.unpack_from('<H', img, p)[0]; p += 2
        for _ in range(n):
            relocs.append((seg * 0x1000, struct.unpack_from('<H', img, p)[0])); p += 2
    return dict(hp=hp, ip=ip, cs=rcs, sp=sp, ss=ss, body=bytes(dst),
                origin=origin, lead=lead, relocs=relocs, hdr=f[:28])

def write_exe(u, path):
    relocs = u['relocs']
    hs = ((28 + 4 * len(relocs) + 511) // 512) * 512
    total = hs + len(u['body'])
    minalloc, maxalloc = struct.unpack_from('<HH', u['hdr'], 10)
    h = struct.pack('<14H', 0x5A4D, total % 512, (total + 511) // 512, len(relocs),
                    hs // 16, minalloc, maxalloc, u['ss'], u['sp'], 0,
                    u['ip'], u['cs'], 28, 0)
    h += b''.join(struct.pack('<HH', o, s) for s, o in relocs)
    open(path, 'wb').write(h + bytes(hs - len(h)) + u['body'])

if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    u = unpack(open(sys.argv[1], 'rb').read())
    write_exe(u, sys.argv[2])
    print('entry %04x:%04x  stack %04x:%04x  %d relocations  %d bytes of code/data'
          % (u['cs'], u['ip'], u['ss'], u['sp'], len(u['relocs']), len(u['body'])))
