#!/usr/bin/env python3
"""wavstat.py WAV [SEC]  -- RMS per 1/4 s of a QEMU wav recording (last SEC seconds, default all).
Works on a recording still in progress (header not yet final): assumes 44100 Hz stereo 16-bit."""
import sys, struct, math
d = open(sys.argv[1], 'rb').read()[44:]
fr, ch = 44100, 2
step = fr * ch // 4
vals = struct.unpack('<%dh' % (len(d) // 2), d[:len(d) // 2 * 2])
start = 0 if len(sys.argv) < 3 else max(0, len(vals) - int(float(sys.argv[2]) * step * 4))
print('total %.1f s' % (len(vals) / (fr * ch)))
for i in range(start, len(vals), step):
    blk = vals[i:i + step]
    print('%7.2f s rms %6d' % (i / (fr * ch), math.sqrt(sum(v * v for v in blk) / max(1, len(blk)))))
