# Mortal Kombat II: int386(0x80, in, out) via DPMI "simulate real-mode interrupt" (see mk2_build.py).
# The game loads its sound driver (SBL.BIN etc.) into conventional memory, points the real-mode
# vector 80h at it and calls it with int386(0x80, ...), i.e. a protected-mode INT 80h. DOS/4GW
# without a DPMI host passes that down to real mode; under HDPMI32i it is a general protection
# fault, and DOS/4GW gives up with exit code 7. INT 31h/0300h works under every DPMI host.
# Placed at 0x4EEA0, in the unused tail of object 1's last page (object size raised to 0x3F000).
#   int386 (0x4C936) starts with  push ecx; push ebp; mov ebp,esp; sub esp,0Ch  (7 bytes),
#   replaced by  jmp hook; nop; nop
#   in: eax = vector, edx = in REGS, ebx = out REGS (Watcom: eax,ebx,ecx,edx,esi,edi,cflag)
        .code32
        .text
        .globl _start
_start:
hook:   cmp     $0x80, %eax
        je      rm80
        push    %ecx                    # the 7 replaced bytes
        push    %ebp
        mov     %esp, %ebp
        sub     $0xc, %esp
        jmp     INT386_REST             # rest of int386 (defsym)
rm80:   push    %ecx
        push    %esi
        push    %edi
        push    %es
        sub     $0x34, %esp             # DPMI real-mode call structure
        mov     %esp, %edi
        push    %ds
        pop     %es
        push    %edi
        xor     %eax, %eax
        mov     $13, %ecx
        rep stosl                       # all zero: flags, segments, SS:SP (host stack)
        pop     %edi
        mov     0x00(%edx), %eax
        mov     %eax, 0x1c(%edi)        # EAX
        mov     0x04(%edx), %eax
        mov     %eax, 0x10(%edi)        # EBX
        mov     0x08(%edx), %eax
        mov     %eax, 0x18(%edi)        # ECX
        mov     0x0c(%edx), %eax
        mov     %eax, 0x14(%edi)        # EDX
        mov     0x10(%edx), %eax
        mov     %eax, 0x04(%edi)        # ESI
        mov     0x14(%edx), %eax
        mov     %eax, 0x00(%edi)        # EDI
        push    %ebx
        mov     $0x300, %eax
        mov     $0x80, %ebx             # BL = 80h, BH = 0
        xor     %ecx, %ecx              # no stack words to copy
        int     $0x31
        pop     %ebx
        mov     0x1c(%edi), %eax
        mov     %eax, 0x00(%ebx)
        mov     0x10(%edi), %eax
        mov     %eax, 0x04(%ebx)
        mov     0x18(%edi), %eax
        mov     %eax, 0x08(%ebx)
        mov     0x14(%edi), %eax
        mov     %eax, 0x0c(%ebx)
        mov     0x04(%edi), %eax
        mov     %eax, 0x10(%ebx)
        mov     0x00(%edi), %eax
        mov     %eax, 0x14(%ebx)
        movzwl  0x20(%edi), %eax
        and     $1, %eax
        mov     %eax, 0x18(%ebx)        # cflag
        mov     0x00(%ebx), %eax        # int386 returns EAX
        add     $0x34, %esp
        pop     %es
        pop     %edi
        pop     %esi
        pop     %ecx
        ret
