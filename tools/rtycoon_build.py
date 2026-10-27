#!/usr/bin/env python3
"""Assemble the Railroad Tycoon dissolve-calibration fix and print patch strings.

usage: python3 rtycoon_build.py [DIR-WITH-ORIGINALS]   (pip install keystone-engine)
       prints one patch.py argument list per driver file
"""
import keystone

ks = keystone.Ks(keystone.KS_ARCH_X86, keystone.KS_MODE_16)

def asm(src, addr):
    enc, _ = ks.asm(src, addr)
    return bytes(enc)

# MGRAPHIC.EXE (VGA/MCGA): calibration at image 05FB..0635, result in cs:[05D6]
MG = """
start:  mov ax, bx
        mov cl, 3
        shr ax, cl
        inc ax
        add bx, ax
again:  mov dx, 0x3da
w1:     in al, dx
        test al, 8
        jz w1
w2:     in al, dx
        test al, 8
        jnz w2
        xor cx, cx
lp:     shr si, 1
        jnc n
        xor si, 0xb400
n:      dec si
        mov di, 0xffff
        movsb
        mov ax, bx
d:      dec ax
        jnz d
        inc cx
        in al, dx
        test al, 8
        jz lp
        cmp cx, 0x215
        ja start
        mov word ptr cs:[0x5d6], bx
"""


# EGRAPHIC.EXE (EGA): calibration at image 0CDC..0D11, delay in cs:[0C9E];
# the loop-back jump at 0D8D must follow lp (0CFF -> 0D05)
EG = """
start:  mov ax, word ptr cs:[0xc9e]
        mov cl, 3
        shr ax, cl
        inc ax
        add word ptr cs:[0xc9e], ax
        mov dx, 0x3da
w1:     in al, dx
        test al, 8
        jz w1
w2:     in al, dx
        test al, 8
        jnz w2
        xor cx, cx
        mov dx, 0x3ce
        mov ax, 0x205
        mov byte ptr cs:[0x25d6], ah
        out dx, ax
lp:     shr bp, 1
        jnc n
        xor bp, 0xb400
n:      mov si, 0xfffe
        mov di, si
"""

# CGRAPHIC.EXE (CGA): calibration at image 098E..09AD, delay in bx;
# the loop-back jump at 09E3 must follow lp (09A1 -> 09A6)
CG = """
start:  mov ax, bx
        mov cl, 3
        shr ax, cl
        inc ax
        add bx, ax
        mov dx, 0x3da
w1:     in al, dx
        test al, 8
        jz w1
w2:     in al, dx
        test al, 8
        jnz w2
        xor cx, cx
lp:     shr bp, 1
        jnc n
        xor bp, 0xb400
n:
"""

# TGRAPHIC.EXE (Tandy): calibration at image 0B03..0B2D, delay in bp;
# the loop-back jumps at 0B59 and 0B77 must follow lp (0B21 -> 0B26)
TG = """
start:  mov ax, bp
        mov cl, 3
        shr ax, cl
        inc ax
        add bp, ax
        mov dx, 0x3da
w1:     in al, dx
        test al, 8
        jz w1
w2:     in al, dx
        test al, 8
        jnz w2
        mov dx, 0x3df
        xor cx, cx
        cmp word ptr cs:[0x1e7c], 0
        jne 0xacf
lp:     shr si, 1
        jnc n
        xor si, 0xb400
n:
"""

def sites():
    """(file, file offset, new bytes) for every site; file offset = image + 0x200."""
    def jrel(op, at, to):           # short jump at image 'at' to image 'to'
        return bytes([op, (to - at - 2) & 0xff])
    def nearjmp(at, to):
        r = (to - at - 3) & 0xffff
        return bytes([0xe9, r & 0xff, r >> 8])
    return [
        ('MGRAPHIC.EXE', 0x200 + 0x5fb, asm(MG, 0x5fb)),
        ('EGRAPHIC.EXE', 0x200 + 0xcdc, asm(EG, 0xcdc)),
        ('EGRAPHIC.EXE', 0x200 + 0xd8d, nearjmp(0xd8d, 0xd05)),
        ('CGRAPHIC.EXE', 0x200 + 0x98e, asm(CG, 0x98e)),
        ('CGRAPHIC.EXE', 0x200 + 0x9e3, jrel(0x74, 0x9e3, 0x9a6)),
        ('TGRAPHIC.EXE', 0x200 + 0xb03, asm(TG, 0xb03)),
        ('TGRAPHIC.EXE', 0x200 + 0xb59, jrel(0x74, 0xb59, 0xb26)),
        ('TGRAPHIC.EXE', 0x200 + 0xb77, jrel(0x74, 0xb77, 0xb26)),
    ]

if __name__ == '__main__':
    # prints one patch.py command per file: OFFSET:OLD:NEW with OLD read from the original
    import os, sys
    src = sys.argv[1] if len(sys.argv) > 1 else '..'
    byfile = {}
    for f, off, new in sites():
        old = open(os.path.join(src, f), 'rb').read()[off:off + len(new)]
        byfile.setdefault(f, []).append('0x%x:%s:%s' % (off, old.hex(), new.hex()))
    for f, args in byfile.items():
        print(f, ' '.join(args))
