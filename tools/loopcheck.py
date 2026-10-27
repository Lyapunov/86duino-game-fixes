#!/usr/bin/env python3
"""loopcheck.py REC.wav START_S LEN_S -- is the audio a short loop? Prints the best repeat periods
(normalised autocorrelation of the waveform, mono, 44.1 kHz) between 0.05 s and 2 s."""
import sys, numpy as np
d = np.frombuffer(open(sys.argv[1], 'rb').read()[44:], '<i2')
d = d[:len(d) // 2 * 2].reshape(-1, 2).mean(1)
s, n = int(float(sys.argv[2]) * 44100), int(float(sys.argv[3]) * 44100)
x = d[s:s + n] - d[s:s + n].mean()
L = 1 << int(np.ceil(np.log2(2 * len(x))))
f = np.fft.rfft(x, L); ac = np.fft.irfft(f * np.conj(f), L)[:len(x)]
ac /= ac[0] + 1e-9
lo, hi = int(0.05 * 44100), int(2 * 44100)
idx = np.argsort(ac[lo:hi])[::-1][:5] + lo
for i in idx: print('period %.4f s  corr %.3f' % (i / 44100, ac[i]))
