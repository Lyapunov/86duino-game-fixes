# Mortal Kombat II (MK2.EXE): point real-mode vector 68h at the sound driver as well.
# MK2.EXE calls its sound driver with INT 80h straight from protected mode (music code, 11 places).
# Under HDPMI32i a protected-mode INT 80h ends in a fault loop and DOS/4GW exits with code 7;
# INT 68h is passed down to real mode normally (placed at 0x4EF80, see mk2_build.py).
# So those INT 80h become INT 68h, and the game's "set real-mode vector" helper (0x102E4,
# al = vector, dx = segment, bx = offset) also sets 68h whenever the game sets 80h.
# On uninstall (dx = bx = 0) vector 68h gets its old value back.
#   0x102E4 starts with  push ecx; sub esp,1Ch; mov [esp+4],al  (8 bytes) -> jmp vec; nop x3
        .code32
        .text
        .globl _start
_start:
vec:    cmp     $0x80, %al
        jne     body
        pusha
        call    1f
1:      pop     %esi                    # esi -> label 1 (position independent)
        mov     %edx, %ecx              # CX = segment
        mov     %ebx, %edx              # DX = offset
        mov     $0x68, %ebx
        test    %cx, %cx
        jz      2f
        push    %ecx
        push    %edx
        mov     $0x200, %eax
        int     $0x31                   # old real-mode vector 68h -> CX:DX
        mov     %dx, saved-1b(%esi)
        mov     %cx, saved-1b+2(%esi)
        pop     %edx
        pop     %ecx
        jmp     3f
2:      mov     saved-1b(%esi), %dx     # uninstall: the saved vector
        mov     saved-1b+2(%esi), %cx
3:      mov     $0x201, %eax
        int     $0x31                   # set real-mode vector 68h = CX:DX
        popa
body:   push    %ecx                    # the 8 replaced bytes
        sub     $0x1c, %esp
        mov     %al, 4(%esp)
        jmp     SETVEC_REST             # rest of the helper (defsym)
saved:  .long   0
