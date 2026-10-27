# Mortal Kombat II: readcap, at 0x4EF40 in the unused tail of object 1 (see mk2_build.py).
# DOS/4GW Professional 2.00 mishandles a DOS read of more than 8 KB into conventional memory:
# it returns 2000h bytes but the file position has moved further (the rest never arrives).
# readcap reads in pieces of at most 2000h bytes until ecx bytes have arrived or the file ends.
#   in:  ebx = handle, edx = buffer (flat), ecx = bytes wanted
#   out: eax = bytes read, CF = 1 on a DOS error (eax = error code); other registers preserved
        .code32
        .text
        .globl _start
_start:
        push    %ecx
        push    %edx
        push    %esi
        push    %edi
        mov     %ecx, %edi                      # bytes still wanted
        xor     %esi, %esi                      # bytes read
1:      test    %edi, %edi
        jz      3f
        mov     %edi, %ecx
        cmp     $0x2000, %ecx
        jbe     2f
        mov     $0x2000, %ecx
2:      mov     $0x3f, %ah
        int     $0x21
        jc      4f
        movzwl  %ax, %eax
        add     %eax, %esi
        add     %eax, %edx
        sub     %eax, %edi
        test    %eax, %eax                      # end of file
        jnz     1b
3:      mov     %esi, %eax
        clc
4:      pop     %edi
        pop     %esi
        pop     %edx
        pop     %ecx
        ret
