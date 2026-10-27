#!/usr/bin/env python3
"""Build MK2FIX.EXE: Mortal Kombat II (MK2.EXE, 861 133 bytes) that runs under HDPMI32i + SBEMU.
See sealed-gate.md.

usage: mk2_build.py MK2.EXE GTA8.EXE OUT.EXE        (needs GNU as/ld)

1. Rebind from DOS/4GW 1.97 to DOS/4GW Professional 2.00 (taken from GTA8.EXE).
2. DOS reads into conventional memory in pieces of at most 8 KB (readcap, mk2_read.S at 0x4EF40):
     0x10818 file loader (mk2_loader.S), 0x2F8AF / 0x2F99E music, 0x4C65A effects.
3. int386 (0x4C936) -> mk2_int80.S at 0x4EEA0: INT 80h (sound driver) via DPMI INT 31h/0300h.
4. The 11 direct protected-mode INT 80h (music code) -> INT 68h, and the set-real-mode-vector
   helper (0x102E4) -> mk2_vec68.S at 0x4EF80, which points vector 68h at the driver too.
   Object 1 is extended from 0x3EE98 to 0x3F000 bytes for the three helpers.
GTA8.EXE is Grand Theft Auto's 8-bit colour executable (freeware release, v11.5); only its
DOS/4GW Professional 2.00 extender (the first 0x38D64 bytes) is used.
"""
import hashlib, os, struct, subprocess, sys, tempfile
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import le_load
MK_MD5 = '98f1803e75b836fd9e62434e1ae6cd6d'
EXT_MD5 = '6812aac9926bb14d9df465b00b5c29f0'
INT80, READCAP, VEC = 0x4EEA0, 0x4EF40, 0x4EF80
SYMS = {'INT386_REST': 0x4C93D, 'READCAP': READCAP, 'FATAL': 0x101A0, 'SETVEC_REST': 0x102EC}
INT80_SITES = (0x2F871, 0x2F879, 0x2F87D, 0x2F881, 0x2F8C3, 0x2F966, 0x34ACB, 0x34AD1, 0x34AD7, 0x34ADD, 0x34AFA)

def asm(src, base):
    with tempfile.TemporaryDirectory() as t:
        o, b = os.path.join(t, 'a.o'), os.path.join(t, 'a.bin')
        defs = sum((['--defsym', '%s=%#x' % kv] for kv in SYMS.items()), [])
        subprocess.run(['as', '--32'] + defs + ['-o', o, os.path.join(here, src)], check=True)
        subprocess.run(['ld', '-m', 'elf_i386', '-Ttext', hex(base), '--oformat', 'binary', '-e', '_start', '-o', b, o], check=True)
        return open(b, 'rb').read()

if len(sys.argv) != 4:
    sys.exit(__doc__)
mk, gta = open(sys.argv[1], 'rb').read(), open(sys.argv[2], 'rb').read()
if hashlib.md5(mk).hexdigest() != MK_MD5:
    sys.exit('MK2.EXE: not the expected version (md5 %s)' % MK_MD5)
if hashlib.md5(gta[:0x38D64]).hexdigest() != EXT_MD5:
    sys.exit('GTA8.EXE: its first 0x38D64 bytes are not the expected DOS/4GW Professional 2.00')
d = bytearray(gta[:0x38D64] + mk[0x26654:])
open(sys.argv[3], 'wb').write(d)
_, stub, le, objs, img, pagefile, fixups = le_load.load(sys.argv[3])
fixed = set()
for f in fixups:
    if f[0] == 0:
        fixed.update(range(0x10000 + f[1], 0x10000 + f[1] + 4))
tail = lambda va: pagefile[(0, 62)] + (va - 0x4E000)

def patch(va, old, new):
    off = le_load.va_to_off(objs, pagefile, va)[2] if va < 0x4EE98 else tail(va)
    assert d[off:off + len(old)] == old, 'unexpected bytes at %#x' % va
    assert not fixed & set(range(va, va + len(new))), 'relocation inside %#x' % va
    d[off:off + len(new)] = new

call = lambda at, to: b'\xe8' + struct.pack('<i', to - (at + 5))
loader = asm('mk2_loader.S', 0x10818)
assert len(loader) <= 112
patch(0x10818, bytes.fromhex('53515683ec0c8d5c240489c6885424088b0031d2e8cec5030085c0753889e08cd98b5604508b5e108b442408e8c7c503008b442404e89ec503008b04243b46047426807c240800740cb8020000008b16e833f9ffff807c240800740cb8010000008b16e820f9ffff83c40c5e595bc390'),
      loader + b'\x90' * (112 - len(loader)))
patch(0x2F8AF, bytes.fromhex('6653b43fcd21665b720fb43ecd217209'),
      call(0x2F8AF, READCAP) + bytes([0x72, 0x2F8C8 - 0x2F8B6]) + bytes.fromhex('b43ecd21') + b'\x90' * 5)
patch(0x2F99E, bytes.fromhex('6653b43fcd21665b0f821cffffffb43ecd210f8212ffffff'),
      call(0x2F99E, READCAP) + b'\x0f\x82' + struct.pack('<i', 0x2F8C8 - 0x2F9A9) + bytes.fromhex('b43ecd21') + b'\x90' * 9)
patch(0x4C65A, bytes.fromhex('53b43ffacd21fb5b721f3bc1751bb43ecd217215'),
      call(0x4C65A, READCAP) + bytes([0x72, 0x4C683 - 0x4C661]) + bytes.fromhex('39c8') + bytes([0x75, 0x4C683 - 0x4C665]) + bytes.fromhex('b43ecd21') + b'\x90' * 5)
patch(0x4C936, bytes.fromhex('515589e583ec0c'), b'\xe9' + struct.pack('<i', INT80 - 0x4C93B) + b'\x90\x90')
for va in INT80_SITES:
    patch(va, b'\xcd\x80', b'\xcd\x68')
patch(0x102E4, bytes.fromhex('5183ec1c88442404'), b'\xe9' + struct.pack('<i', VEC - 0x102E9) + b'\x90' * 3)
ot = le + struct.unpack_from('<I', d, le + 0x40)[0]
assert struct.unpack_from('<I', d, ot)[0] == 0x3EE98
struct.pack_into('<I', d, ot, 0x3F000)
for va, src, end in ((INT80, 'mk2_int80.S', READCAP), (READCAP, 'mk2_read.S', VEC), (VEC, 'mk2_vec68.S', 0x4F000)):
    code = asm(src, va)
    off = tail(va)
    assert d[off:off + len(code)] == bytes(len(code)) and va + len(code) <= end
    d[off:off + len(code)] = code
open(sys.argv[3], 'wb').write(d)
print('wrote', sys.argv[3])
