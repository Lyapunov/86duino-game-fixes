#!/usr/bin/env python3
"""Wacky Wheels (WW.EXE v1.1): build a copy with the "kbdcells" keyboard diagnostic.

Assembles ww_kbdcells.S (GNU binutils: as, ld, objcopy) and puts it into the
zero bytes at linear 0x5BE30 of WW.EXE, hooked into
  - the game's keyboard handler at 0x40934 (in al,60h / push ax / in al,61h),
    to record the last byte read and a "key seen recently" countdown;
  - the Apogee Sound System timer handler at 0x40B65 (cld / call 0x41448),
    which redraws the cells every 64 ticks.
0x5BE30..0x5BFFF is the tail of object 1's last page, just past its declared
size (0x5BE2E). It is stored in the file as zeros, and DOS/4G loads the whole
page, so 464 bytes are free there.
Diagnostic only: it fixes nothing. See trap-storm.md for how to read the cells.

usage: python3 ww_kbdcells_build.py IN.EXE OUT.EXE
  IN.EXE: WW.EXE v1.1, original or already patched (the hook sites must be untouched)
"""
import hashlib, os, struct, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from le_load import load, va_to_off

if len(sys.argv) != 3:
    sys.exit(__doc__)
here = os.path.dirname(os.path.abspath(__file__))
tmp = tempfile.mkdtemp()
o, elf, bin_ = (os.path.join(tmp, n) for n in ('k.o', 'k.elf', 'k.bin'))
subprocess.run(['as', '--32', os.path.join(here, 'ww_kbdcells.S'), '-o', o], check=True)
subprocess.run(['ld', '-m', 'elf_i386', '-Ttext=0x5be30', '-e', '_start', '-o', elf, o], check=True)
subprocess.run(['objcopy', '-O', 'binary', '-j', '.text', elf, bin_], check=True)
sym = {l.split()[2]: int(l.split()[0], 16) for l in
       subprocess.run(['nm', elf], capture_output=True, text=True).stdout.splitlines()}
stub = open(bin_, 'rb').read()
assert sym['_start'] == 0x5BE30 and 0x5BE30 + len(stub) <= 0x5C000, 'stub too big'

d, _, _, objs, _, pf, fx = load(sys.argv[1])
b = bytearray(d)
def off(va):
    if 0x5BE2E <= va < 0x5C000:          # page slack after object 1 (see above)
        so = va - 0x10000
        return pf[(0, so // 0x1000)] + so % 0x1000
    return va_to_off(objs, pf, va)[2]
def put(va, old, new):
    f = off(va)
    if b[f:f + len(old)] != old:
        sys.exit('unexpected bytes at 0x%X: not WW.EXE v1.1, or already hooked' % va)
    b[f:f + len(new)] = new
def jmp(va, old, to):
    old = bytes.fromhex(old)
    put(va, old, b'\xe9' + struct.pack('<i', sym[to] - (va + 5)) + b'\x90' * (len(old) - 5))
put(0x5BE30, bytes(len(stub)), stub)
jmp(0x40934, 'e4606650e461', 'kread')
jmp(0x40B65, 'fce8dd080000', 'isr')
open(sys.argv[2], 'wb').write(b)
print('%s (%d-byte stub)  MD5 %s' % (sys.argv[2], len(stub), hashlib.md5(b).hexdigest()))
