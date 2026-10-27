#!/usr/bin/env python3
"""Load a DOS/4GW-bound LE executable (e.g. Command & Conquer's GAME.DAT).

usage:
  le_load.py FILE info                  header, objects, where the LE starts
  le_load.py FILE dump OUTDIR           write objN.bin per object, fixups applied
  le_load.py FILE off VA [VA ...]       file offset of a linear address (+ fixup check)
  le_load.py FILE patch OUT VA=HEX ...  copy FILE to OUT with bytes changed at linear
                                        addresses; refuses if a fixup touches them

The dumped objects can be disassembled with
  objdump -D -b binary -mi386 --adjust-vma=0x10000 obj1.bin
(use the object's base address from `info`). Fixups are applied, so absolute
addresses of strings and data show up as plain numbers in the listing.

Why the fixup check: the DOS/4GW loader writes the relocated address over the
fixup locations every time the program loads. A patch byte placed there is
silently overwritten, so patches must avoid them.
"""
import struct
import sys


def find_le(d):
    """Return (stub_offset, le_offset): the MZ stub whose e_lfanew points at 'LE'."""
    i = d.find(b'LE\0\0')
    while i >= 0:
        j = d.rfind(b'MZ', 0, i)
        while j >= 0:
            if struct.unpack_from('<I', d, j + 0x3C)[0] == i - j:
                return j, i
            j = d.rfind(b'MZ', 0, j)
        i = d.find(b'LE\0\0', i + 1)
    sys.exit('no LE header found')


def load(path):
    d = open(path, 'rb').read()
    stub, le = find_le(d)
    u = lambda o: struct.unpack_from('<I', d, le + o)[0]
    pagesz, npages, lastpg = u(0x28), u(0x14), u(0x2C)
    objtab, nobj = u(0x40), u(0x44)
    fixpg, fixrec = u(0x68), u(0x6C)
    datapg = u(0x80) + stub          # relative to the stub, not to the file
    objs = [struct.unpack_from('<6I', d, le + objtab + 24 * i) for i in range(nobj)]
    img, pagefile = [], {}
    for i, (vs, base, fl, pmi, pmc, _) in enumerate(objs):
        buf = bytearray(max(vs, pmc * pagesz))
        for p in range(pmc):
            pg = pmi + p
            off = datapg + (pg - 1) * pagesz
            sz = lastpg if pg == npages else pagesz
            buf[p * pagesz:p * pagesz + sz] = d[off:off + sz]
            pagefile[(i, p)] = off
        img.append(buf)
    pgtab = [u(fixpg + 4 * k) for k in range(npages + 1)]
    fixups = []                      # (obj index, offset in obj, type, target obj, target offset)
    for i, (vs, base, fl, pmi, pmc, _) in enumerate(objs):
        for p in range(pmc):
            pg = pmi + p - 1
            o, e = le + fixrec + pgtab[pg], le + fixrec + pgtab[pg + 1]
            while o < e:
                src, flg = d[o], d[o + 1]
                o += 2
                if src & 0x20:
                    cnt = d[o]
                    o += 1
                else:
                    offs = [struct.unpack_from('<h', d, o)[0]]
                    o += 2
                if flg & 0x40:
                    tobj = struct.unpack_from('<H', d, o)[0]
                    o += 2
                else:
                    tobj = d[o]
                    o += 1
                if (src & 0xF) == 2:
                    toff = 0
                elif flg & 0x10:
                    toff = struct.unpack_from('<I', d, o)[0]
                    o += 4
                else:
                    toff = struct.unpack_from('<H', d, o)[0]
                    o += 2
                if src & 0x20:
                    offs = [struct.unpack_from('<h', d, o + 2 * k)[0] for k in range(cnt)]
                    o += 2 * cnt
                for so in offs:
                    fixups.append((i, p * pagesz + so, src & 0xF, tobj, toff))
    for (i, so, t, tobj, toff) in fixups:
        tgt = objs[tobj - 1][1] + toff
        buf = img[i]
        if so < 0 or so >= len(buf):
            continue
        if t == 7:                   # 32-bit offset
            n = min(4, len(buf) - so)
            buf[so:so + n] = struct.pack('<I', tgt & 0xFFFFFFFF)[:n]   # some fixup targets overflow 32 bits (Daggerfall FALL.EXE)
        elif t == 8:                 # 32-bit self-relative
            buf[so:so + 4] = struct.pack('<i', tgt - (objs[i][1] + so + 4))
    return d, stub, le, objs, img, pagefile, fixups


def va_to_off(objs, pagefile, va):
    for i, (vs, base, fl, pmi, pmc, _) in enumerate(objs):
        if base <= va < base + vs:
            so = va - base
            if (i, so // 0x1000) not in pagefile:
                sys.exit('0x%X is in zero-filled memory, not in the file' % va)
            return i, so, pagefile[(i, so // 0x1000)] + so % 0x1000
    sys.exit('0x%X is not inside any object' % va)


def fixup_bytes(fixups, obj):
    s = set()
    for (i, so, t, tobj, toff) in fixups:
        if i == obj:
            s.update(range(so, so + (4 if t in (7, 8) else 2)))
    return s


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    d, stub, le, objs, img, pf, fx = load(sys.argv[1])
    cmd = sys.argv[2]
    if cmd == 'info':
        print('MZ stub at 0x%X, LE header at 0x%X, %d fixups' % (stub, le, len(fx)))
        for i, (vs, base, fl, pmi, pmc, _) in enumerate(objs):
            print('object %d: base 0x%X size 0x%X flags 0x%X pages %d..%d' % (i + 1, base, vs, fl, pmi, pmi + pmc - 1))
    elif cmd == 'dump':
        for i, b in enumerate(img):
            open('%s/obj%d.bin' % (sys.argv[3], i + 1), 'wb').write(b)
        print('wrote %d objects to %s' % (len(img), sys.argv[3]))
    elif cmd == 'off':
        for a in sys.argv[3:]:
            va = int(a, 16)
            i, so, fo = va_to_off(objs, pf, va)
            hit = so in fixup_bytes(fx, i)
            print('VA 0x%X -> object %d +0x%X -> file offset 0x%X%s' % (va, i + 1, so, fo, '  (FIXUP HERE)' if hit else ''))
    elif cmd == 'patch':
        out = bytearray(d)
        for spec in sys.argv[4:]:
            a, h = spec.split('=')
            va, b = int(a, 16), bytes.fromhex(h)
            i, so, fo = va_to_off(objs, pf, va)
            bad = fixup_bytes(fx, i) & set(range(so, so + len(b)))
            if bad:
                sys.exit('refused: fixup at VA 0x%X would overwrite the patch' % (objs[i][1] + min(bad)))
            if so // 0x1000 != (so + len(b) - 1) // 0x1000:
                sys.exit('refused: patch at 0x%X crosses a page boundary' % va)
            out[fo:fo + len(b)] = b
            print('VA 0x%X -> file 0x%X: %s -> %s' % (va, fo, d[fo:fo + len(b)].hex(), b.hex()))
        open(sys.argv[3], 'wb').write(out)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
