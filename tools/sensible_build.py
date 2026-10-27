#!/usr/bin/env python3
"""Build the Tick Starvation fix for Sensible Soccer v1.1 (SOC.EXE).

usage: sensible_build.py SOC.EXE OUT.EXE [--test]

SOC.EXE is PKLITE-compressed, so its bytes can't be patched in place. This script:
  1. runs the PKLITE stub in an emulator (unicorn) twice, at two load segments,
     until it jumps to the game's entry point, and dumps the unpacked image;
  2. diffs the two dumps to recover the relocation table and writes a plain MZ EXE;
  3. applies the patch to the timer handler:
       image E24F  EC 5D -> 8C 43   accumulator step = PIT divisor 438Ch, so the BIOS
                                    gets exactly 18.2 ticks/s (was 25.3/s in the menus)
       image E258  75 04 -> 90 90   call the BIOS (INT 62h = old INT 8) on every carry,
                                    not only while [5E43] = -1 (menus)
  --test also adds the test-only changes (NOT for the 86Duino):
       image 35481 74 03 -> EB 03   any word passes the manual-lookup protection
       image E0C9  74 13 -> 90 90   F1 alone exits to DOS, even during a match
       image E0D0  75 0C -> 90 90

Needs unicorn:  pip install unicorn
"""
import struct, sys
from unicorn import Uc, UcError, UC_ARCH_X86, UC_MODE_16, UC_HOOK_CODE
from unicorn.x86_const import UC_X86_REG_CS, UC_X86_REG_IP, UC_X86_REG_SS, UC_X86_REG_SP, \
    UC_X86_REG_DS, UC_X86_REG_ES

STUB_COPY = 0x3fe30          # the stub copies itself here (image offset); the game image ends before it


def unpack(f, psp):
    h = struct.unpack_from('<14H', f)
    size = h[2] * 512 - ((512 - h[1]) if h[1] else 0)
    load = psp + 0x10
    mu = Uc(UC_ARCH_X86, UC_MODE_16)
    mu.mem_map(0, 0x110000)
    mu.mem_write(psp * 16, b'\xcd\x20' + struct.pack('<H', 0x9fff))
    mu.mem_write(load * 16, f[h[4] * 16:size])
    for i in range(h[3]):
        o, s = struct.unpack_from('<HH', f, h[12] + 4 * i)
        a = (load + s) * 16 + o
        v = struct.unpack('<H', mu.mem_read(a, 2))[0]
        mu.mem_write(a, struct.pack('<H', (v + load) & 0xffff))
    cs0 = (load + h[11]) & 0xffff
    for r, v in ((UC_X86_REG_CS, cs0), (UC_X86_REG_IP, h[10]), (UC_X86_REG_SS, (load + h[7]) & 0xffff),
                 (UC_X86_REG_SP, h[8]), (UC_X86_REG_DS, psp), (UC_X86_REG_ES, psp)):
        mu.reg_write(r, v)
    st = {'cs': cs0, 'n': 0}

    def code(mu, addr, sz, ud):
        cs = mu.reg_read(UC_X86_REG_CS)
        if cs != st['cs']:
            st['cs'] = cs
            st['n'] += 1
            if st['n'] > 1 and load <= cs < load + 0x100:     # far jump back down into the image
                st['oep'] = (cs - load, mu.reg_read(UC_X86_REG_IP))
                mu.emu_stop()
    mu.hook_add(UC_HOOK_CODE, code)
    mu.emu_start(cs0 * 16 + h[10], 0xfffff, count=100_000_000)
    assert st.get('oep') == (0, 0), st
    return bytes(mu.mem_read(load * 16, STUB_COPY)), h


def build(f):
    a, h = unpack(f, 0x1000)
    b, _ = unpack(f, 0x2000)
    img = bytearray(a)
    rel = []
    i = 0
    while i < len(img) - 1:
        if a[i:i + 2] != b[i:i + 2]:
            va, vb = struct.unpack_from('<H', a, i)[0], struct.unpack_from('<H', b, i)[0]
            assert (vb - va) & 0xffff == 0x1000, hex(i)
            struct.pack_into('<H', img, i, (va - 0x1010) & 0xffff)
            rel.append(i)
            i += 2
        else:
            i += 1
    img = bytes(img).rstrip(b'\0')
    hdrpar = (0x1c + 4 * len(rel) + 15) // 16
    osize = h[2] * 512 - ((512 - h[1]) if h[1] else 0) - h[4] * 16
    ss, sp = 0x3e55, 0x0400                       # the stack PKLITE hands over
    minalloc = max((osize + 15) // 16 + h[5] - (len(img) + 15) // 16,
                   (ss * 16 + sp - len(img) + 15) // 16)
    tot = hdrpar * 16 + len(img)
    hdr = bytearray(hdrpar * 16)
    struct.pack_into('<14H', hdr, 0, 0x5a4d, tot % 512, (tot + 511) // 512, len(rel), hdrpar,
                     minalloc, 0xffff, ss, sp, 0, 0, 0, 0x1c, 0)
    for k, r in enumerate(rel):
        struct.pack_into('<HH', hdr, 0x1c + 4 * k, r & 15, r >> 4)
    return bytearray(hdr + img), hdrpar * 16


FIX = [(0xE24F, 'EC5D', '8C43'), (0xE258, '7504', '9090')]
TEST = [(0x35481, '7403', 'EB03'), (0xE0C9, '7413', '9090'), (0xE0D0, '750C', '9090')]

if __name__ == '__main__':
    exe, base = build(open(sys.argv[1], 'rb').read())
    for img_off, old, new in FIX + (TEST if '--test' in sys.argv else []):
        o = base + img_off
        assert exe[o:o + 2] == bytes.fromhex(old), 'wrong version? %X' % img_off
        exe[o:o + 2] = bytes.fromhex(new)
        print('file 0x%05X (image %05X): %s -> %s' % (o, img_off, old, new))
    open(sys.argv[2], 'wb').write(exe)
    print('wrote', sys.argv[2], len(exe), 'bytes')
