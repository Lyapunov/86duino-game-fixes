#!/usr/bin/env python3
"""Build SCRDUMP.COM: writes the 80x25 text screen (B800:0000, 4000 bytes) to D:\\SCR.BIN.

usage: scrdump_build.py [OUT.COM]        (default: SCRDUMP.COM)
       scrdump_build.py --show SCR.BIN   print the dumped screen as text

Run it in DOSBox right after a program exits, to read a message the program
wrote straight to video memory (where redirecting stdout catches nothing).
Change the drive letter in NAME if D: is not your log drive.
"""
import sys

NAME = b'D:\\SCR.BIN\0'
CODE = bytes.fromhex(
    'B43C'        # mov ah,3Ch        create file
    '31C9'        # xor cx,cx
    'BA2401'      # mov dx,0124h      -> NAME
    'CD21'        # int 21h
    '89C3'        # mov bx,ax         handle
    '1E'          # push ds
    'B800B8'      # mov ax,0B800h
    '8ED8'        # mov ds,ax
    '31D2'        # xor dx,dx
    'B9A00F'      # mov cx,4000
    'B440'        # mov ah,40h        write
    'CD21'        # int 21h
    '1F'          # pop ds
    'B43E'        # mov ah,3Eh        close
    'CD21'        # int 21h
    'B8004C'      # mov ax,4C00h      exit
    'CD21'        # int 21h
)
assert len(CODE) == 0x24          # NAME follows at 0100h + 24h

if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--show':
        d = open(sys.argv[2], 'rb').read()
        for r in range(25):
            line = bytes(d[r * 160 + c * 2] for c in range(80)).decode('cp437').rstrip()
            if line:
                print(line)
    else:
        out = sys.argv[1] if len(sys.argv) > 1 else 'SCRDUMP.COM'
        open(out, 'wb').write(CODE + NAME)
        print('wrote', out)
