# Build CACHEOFF.COM and CACHEON.COM from cacheoff.S with GNU as/ld (16-bit, org 100h)
# usage: python3 cacheoff_build.py [OUTDIR]
import os
import subprocess
import sys
import tempfile

here = os.path.dirname(os.path.abspath(__file__))
out = sys.argv[1] if len(sys.argv) > 1 else here
src = os.path.join(here, 'cacheoff.S')
for name, defs in (('CACHEOFF.COM', []), ('CACHEON.COM', ['--defsym', 'CACHE_ON=1'])):
    with tempfile.TemporaryDirectory() as t:
        obj = os.path.join(t, 'c.o')
        subprocess.run(['as', '--32'] + defs + ['-o', obj, src], check=True)
        dst = os.path.join(out, name)
        subprocess.run(['ld', '-m', 'elf_i386', '-Ttext', '0x100', '--oformat', 'binary',
                        '-e', '_start', '-o', dst, obj], check=True)
    print(name, os.path.getsize(dst), 'bytes')
