# Build CPUDIFF.COM from cpudiff.S with GNU as/ld (16-bit, org 100h)
# usage: python3 cpudiff_build.py [OUTDIR]
import os
import subprocess
import sys
import tempfile

here = os.path.dirname(os.path.abspath(__file__))
out = sys.argv[1] if len(sys.argv) > 1 else here
with tempfile.TemporaryDirectory() as t:
    obj = os.path.join(t, 'c.o')
    subprocess.run(['as', '--32', '-o', obj, os.path.join(here, 'cpudiff.S')], check=True)
    dst = os.path.join(out, 'CPUDIFF.COM')
    subprocess.run(['ld', '-m', 'elf_i386', '-Ttext', '0x100', '--oformat', 'binary',
                    '-e', '_start', '-o', dst, obj], check=True)
print('CPUDIFF.COM', os.path.getsize(dst), 'bytes')
