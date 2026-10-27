#!/usr/bin/env python3
"""Make Lemmings 3D keep its settings and saved games in the game folder instead of C:\\LM3D.CD.

usage: lem3d_local.py GAMEDIR OUTDIR      writes OUTDIR/L3D.EXE and OUTDIR/SETUP.EXE

The CD installer created C:\\LM3D.CD; L3D.EXE and SETUP.EXE use these fixed paths:
  L3D.EXE    C:\\LM3D.CD\\LM3D.CFG  ->  LM3D.CFG     (settings, written by SETUP)
  L3D.EXE    C:\\LM3D.CD\\LM3D.SAV  ->  LM3D.SAV     (saved progress)
  SETUP.EXE  c:\\lm3d.cd\\lm3d.cfg  ->  lm3d.cfg
  SETUP.EXE  c:\\lm3d.cd            ->  .            (the folder it creates first)
The new names are relative, so start both programs from the game folder. Each string keeps its length
(padded with zeros).
"""
import hashlib, os, sys

FILES = {
    'L3D.EXE': ('659821374a6f4d0ecf743bbfa10e27d6', [(b'C:\\LM3D.CD\\LM3D.CFG', b'LM3D.CFG'),
                                                   (b'C:\\LM3D.CD\\LM3D.SAV', b'LM3D.SAV')]),
    'SETUP.EXE': ('6c196d40245d1744473518684da5c586', [(b'c:\\lm3d.cd\\lm3d.cfg', b'lm3d.cfg'), (b'c:\\lm3d.cd', b'.')]),
}
if len(sys.argv) != 3:
    sys.exit(__doc__)
for name, (md5, pairs) in FILES.items():
    d = bytearray(open(os.path.join(sys.argv[1], name), 'rb').read())
    if hashlib.md5(d).hexdigest() != md5:
        sys.exit('%s: not the expected version (md5 %s)' % (name, md5))
    for old, new in pairs:
        old += b'\0'
        assert d.count(old) == 1, (name, old)
        i = d.find(old)
        d[i:i + len(old)] = new + b'\0' * (len(old) - len(new))
    open(os.path.join(sys.argv[2], name), 'wb').write(d)
    print('wrote', os.path.join(sys.argv[2], name))
