#!/usr/bin/env python3
"""Build DOS .COM tools from their GNU-as sources (16-bit, org 100h).

usage: python3 dosbuild.py NAME.S [NAME.S ...] [-o OUTDIR]
  e.g. python3 dosbuild.py ghostfix.S where.S      -> GHOSTFIX.COM, WHERE.COM
Needs GNU binutils (as, ld). where.S includes font35.inc from this folder.
"""
import os, subprocess, sys, tempfile

here = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[1:]
out = here
if '-o' in args:
    i = args.index('-o'); out = args[i + 1]; del args[i:i + 2]
if not args:
    sys.exit(__doc__)
for src in args:
    path = src if os.path.isabs(src) else os.path.join(here, src)
    name = os.path.splitext(os.path.basename(path))[0].upper() + '.COM'
    with tempfile.TemporaryDirectory() as t:
        obj = os.path.join(t, 'x.o')
        subprocess.run(['as', '--32', '-I', here, '-o', obj, path], check=True)
        dst = os.path.join(out, name)
        subprocess.run(['ld', '-m', 'elf_i386', '-Ttext', '0x100', '--oformat', 'binary',
                        '-e', '_start', '-o', dst, obj], check=True)
    print(name, os.path.getsize(dst), 'bytes')
