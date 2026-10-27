#!/usr/bin/env python3
"""mk2_cmos.py CMOS OUT [card=8] [port=220] [irq=5] [dma=1]  -- edit Mortal Kombat II's settings file.

MK2.EXE keeps its settings (the arcade's "CMOS") in a 440-byte file named CMOS. Sound card fields are
32-bit words: +0BCh card (8 = Sound Blaster, SBL.BIN; 0 = no sound), +0C0h port (hex), +0C4h IRQ,
+0C8h DMA. The word at +1B6h must be the 16-bit sum of bytes 0..1B5h, or the game throws the whole
file away and uses its defaults. Without arguments it just prints the fields.
  e.g. mk2_cmos.py CMOS CMOS.I5 irq=5
"""
import struct, sys

FIELDS = {'card': 0xBC, 'port': 0xC0, 'irq': 0xC4, 'dma': 0xC8}

if len(sys.argv) < 2:
    sys.exit(__doc__)
d = bytearray(open(sys.argv[1], 'rb').read())
if len(d) != 440:
    sys.exit('%s: %d bytes, expected 440' % (sys.argv[1], len(d)))
ok = struct.unpack_from('<H', d, 0x1B6)[0] == sum(d[:0x1B6]) & 0xFFFF
for arg in sys.argv[3:]:
    k, v = arg.split('=')
    struct.pack_into('<I', d, FIELDS[k], int(v, 16 if k == 'port' else 10))
struct.pack_into('<H', d, 0x1B6, sum(d[:0x1B6]) & 0xFFFF)
f = {k: struct.unpack_from('<I', d, o)[0] for k, o in FIELDS.items()}
print('card %d  port %Xh  IRQ %d  DMA %d  (checksum of the input %s)'
      % (f['card'], f['port'], f['irq'], f['dma'], 'OK' if ok else 'WRONG'))
if len(sys.argv) > 2:
    open(sys.argv[2], 'wb').write(d)
    print('wrote', sys.argv[2])
