#!/usr/bin/env python3
"""Build SBDIAG.DIG: GTA's Miles SBPRO.DIG with interrupt counters (diagnostic only).

The stubs in sbdiag_stubs.S are appended at offset 0B20h; three patches route through them:
  IRQ vector install (detection 08D0h, playback 0987h)  -> count every IRQ handler call
  half-buffer flip 0753h (xor [515h],1)                   -> count flips
  playback start 0AADh (mov [5D3h],3)                     -> count starts, note the PIC mask
Counters: 0000:04F0 (BIOS inter-application area), read by GTADIAG.COM.
usage: sbdiag_build.py SBPRO.DIG OUT.DIG   (needs GNU as/ld/nm)"""
import os, struct, subprocess, sys, tempfile
here = os.path.dirname(os.path.abspath(__file__))
BASE = 0xB20
with tempfile.TemporaryDirectory() as t:
    o, b = os.path.join(t, 's.o'), os.path.join(t, 's.bin')
    subprocess.run(['as', '--32', '-o', o, os.path.join(here, 'sbdiag_stubs.S')], check=True)
    subprocess.run(['ld', '-m', 'elf_i386', '-Ttext', hex(BASE), '--oformat', 'binary', '-e', '_start', '-o', b, o], check=True)
    stubs = open(b, 'rb').read()
    sym = {l.split()[2]: int(l.split()[0], 16) + BASE for l in subprocess.run(['nm', o], capture_output=True, text=True).stdout.splitlines()}
d = bytearray(open(sys.argv[1], 'rb').read())
assert d[:7] == b'AIL3DIG' and len(d) <= BASE
d += bytes(BASE - len(d)) + stubs
rel16 = lambda nxt, dst: struct.pack('<h', dst - nxt)
def patch(off, old, new):
    assert d[off:off + len(old)] == old, hex(off); d[off:off + len(new)] = new
patch(0x8D0, b'\xba\xd3\x06', b'\xba' + struct.pack('<H', sym['isr']))
patch(0x987, b'\xba\xd3\x06', b'\xba' + struct.pack('<H', sym['isr']))
patch(0x753, b'\x83\x36\x15\x05\x01', b'\xe9' + rel16(0x756, sym['flip']) + b'\x90\x90')
patch(0xAAD, b'\xc7\x06\xd3\x05\x03\x00', b'\xe9' + rel16(0xAB0, sym['start']) + b'\x90\x90\x90')
open(sys.argv[2], 'wb').write(d)
print(sys.argv[2], len(d), 'bytes', {k: hex(v) for k, v in sym.items() if k in ('isr', 'flip', 'start')})
