# Mortal Kombat II: replacement for the file loader at 0x10818 in MK2.EXE (112 bytes, see mk2_build.py).
# The original did one DOS read of the whole file and called it "corrupt" if fewer bytes came back.
# Under DOS/4GW Professional 2.00 such reads must be split (readcap, mk2_read.S at 0x4EF40).
#   in:  eax = file record: +0 name, +4 size, +10h buffer (flat address)
#        dl  = nonzero: stop the game with "cannot find" / "is corrupt" on failure
#   calls fatal(code=eax, name=edx) at 0x101A0 like the original
        .code32
        .text
        .globl _start
_start:
        push    %ebx
        push    %ecx
        push    %esi
        push    %edx
        mov     %eax, %esi
        mov     (%esi), %edx            # file name
        mov     $0x3d00, %ax            # open, read-only
        int     $0x21
        jc      notfound
        xchg    %eax, %ebx              # bx = handle
        mov     0x10(%esi), %edx        # buffer
        mov     0x4(%esi), %ecx         # size
        call    READCAP                 # readcap (defsym)
        sbb     %edx, %edx              # edx = -1 on a read error
        mov     %eax, %ecx              # bytes read (close changes ax)
        mov     $0x3e, %ah              # close
        int     $0x21
        test    %edx, %edx
        jnz     corrupt
        cmp     0x4(%esi), %ecx
        je      ok
corrupt:
        push    $2                      # "file %s is corrupt!"
        pop     %eax
        jmp     fail
notfound:
        push    $1                      # "cannot find %s!!"
        pop     %eax
fail:   pop     %edx
        push    %edx
        test    %dl, %dl
        jz      ok
        mov     (%esi), %edx
        call    FATAL                   # (defsym)
ok:     pop     %edx
        pop     %esi
        pop     %ecx
        pop     %ebx
        ret
