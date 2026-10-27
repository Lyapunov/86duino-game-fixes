#!/usr/bin/env python3
"""Build SBL0FIX.BIN, Lemmings 3D's Sound Blaster driver (SOUND\\DRIVERS\\SBL0.BIN, Sound Images v1.11x,
11336 bytes) fixed for SBEMU. Same size as the original.

usage: lem3d_sbl_build.py SBL0.BIN SBL0FIX.BIN [PORT IRQ DMA]      (default 220 5 1; needs GNU as/ld)

1. The game always calls the driver's init with port 0, which makes the driver autodetect the card. Its IRQ
   test (DSP command F2h, then a short wait for the IRQ) fails under SBEMU, which raises the IRQ only at its
   next sound-card interrupt: "MUSIC DRIVER ERROR", "EFFECTS DRIVER ERROR". Now port 0 means the given
   port, IRQ and DMA channel instead:
     0x06AE  call 790h; call 753h; call 931h  ->  mov dx,PORT; mov cx,DMA*256+IRQ; jmp 06C0h
2. Broken Record (as in Mortal Kombat II's SBL.BIN, the same driver family): the effects are mixed only in
   the IRQ handler. mk2_sbl_dmapoll.S, built with this driver's addresses, goes over the IRQ autodetect code
   (0931h..0988h, unreachable after 1.) and is called from the timer tick and the IRQ handler:
     0x0295  tick: cmp byte [217h],0         ->  call tick; nop; nop
     0x0931  poll (88 bytes free)
     0x0B6D  IRQ: swap [1C1Ah]/[1C1Ch]        ->  nops
     0x0B85  IRQ: call [1077h] (mixer)        ->  call poll; nop
"""
import hashlib, os, struct, subprocess, sys, tempfile
here = os.path.dirname(os.path.abspath(__file__))
MD5 = 'dee0bc63819bd0c139927771ebfa7a9b'
BASE, END = 0x931, 0x989
SYMS = dict(TICKFLAG=0x217, DMACH=0x149e, HALF1=0x1c0a, HALF2=0x1c12, PLAYING=0x1c1a, TOFILL=0x1c1c,
            MIXER=0x1077, HALFSIZE=0x1c8)

if len(sys.argv) not in (3, 6):
    sys.exit(__doc__)
port, irq, dma = (int(sys.argv[3], 16), int(sys.argv[4]), int(sys.argv[5])) if len(sys.argv) == 6 else (0x220, 5, 1)
assert irq in (2, 3, 5, 7) and dma in (0, 1, 3), 'IRQ 2/3/5/7 and DMA 0/1/3 (8-bit) only'
d = bytearray(open(sys.argv[1], 'rb').read())
if hashlib.md5(d).hexdigest() != MD5:
    sys.exit('SBL0.BIN: not the expected version (md5 %s)' % MD5)
with tempfile.TemporaryDirectory() as t:
    o, b = os.path.join(t, 'a.o'), os.path.join(t, 'a.bin')
    defs = sum((['--defsym', '%s=%#x' % kv] for kv in SYMS.items()), [])
    subprocess.run(['as', '--32'] + defs + ['-o', o, os.path.join(here, 'mk2_sbl_dmapoll.S')], check=True)
    subprocess.run(['ld', '-m', 'elf_i386', '-Ttext', hex(BASE), '--oformat', 'binary', '-e', '_start',
                    '-o', b, o], check=True)
    code = open(b, 'rb').read()
assert len(code) <= END - BASE, len(code)
tick, poll = BASE, BASE + 9     # poll follows "call poll; cmp byte [217h],0; ret" (3 + 5 + 1 bytes)
assert code[9:10] == b'\x60', 'poll must start with pusha at +9'

def patch(at, old, new):
    assert d[at:at + len(old)] == old, 'unexpected bytes at %#x' % at
    d[at:at + len(new)] = new

call = lambda at, to: b'\xe8' + struct.pack('<h', to - (at + 3))
patch(0x6AE, bytes.fromhex('e8df00e89f00e87a'),
      b'\xba' + struct.pack('<H', port) + b'\xb9' + bytes([irq, dma]) + b'\xeb\x0a')
patch(0x295, bytes.fromhex('803e170200'), call(0x295, tick) + b'\x90\x90')
patch(BASE, d[BASE:BASE + len(code)], code)
patch(0xB6D, bytes.fromhex('a11a1c87061c1ca31a1c'), b'\x90' * 10)
patch(0xB85, bytes.fromhex('ff167710'), call(0xB85, poll) + b'\x90')
open(sys.argv[2], 'wb').write(d)
print('wrote', sys.argv[2], '(port %X, IRQ %d, DMA %d; %d bytes of code at %#x)' % (port, irq, dma, len(code), BASE))
