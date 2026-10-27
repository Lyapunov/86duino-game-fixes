# SMCTEST.COM - does the CPU see a RET that was just written into code it then calls?
# Built by smctest_build.py. Run it on two machines (e.g. the 86Duino and a QEMU VM) with
#   SMCTEST > SMC.TXT
# and run it again after CACHEOFF to see the cache-off case.
#
# Copies what Daggerfall's shading pass does (FALL.EXE 0x1500e3): an unrolled block of
# 18-byte entries, a RET planted at entry n with one byte store, a CALL to the block start,
# then the original byte put back. Each entry increments SI, so after the call SI must
# equal n. A run where SI != n means the CPU executed the old byte instead of the RET.
#
# Two orders of n:
#   A = random 0..127
#   B = alternating: a long run (n = 127), then a short one (n = 0..7)
# Five ways of planting the RET (what goes between the store and the call):
#   V0 nothing (what the game does)
#   V1 jmp $+2
#   V2 read the byte back
#   V3 store with xchg (locked)
#   V4 cpuid (serializing on Intel)
# Each line prints: bad = runs where SI != n, n<4 / n<16 = how many of those had a short n,
# worst = the largest SI - n seen.
# Runs in real mode or V86 mode; needs a 386 or later (V4 needs CPUID).

        .intel_syntax noprefix
        .code16
        .text
        .globl _start

        .equ M, 160                     # entries in the block
        .equ ESZ, 18                    # bytes per entry, as in FALL.EXE
        .equ ITER, 50000                # calls per line
        .equ block, 0x4000              # generated at run time, inside the COM segment
        .equ buf, 0x7000                # scratch the entries read and write
        .equ FIRST, 0x66                # first byte of an entry (put back after each call)

_start:
        mov     dx, offset s_title
        call    puts
        call    cpuinfo

        mov     di, block               # build the block: M copies of the entry, then RET
        mov     cx, M
1:      push    cx
        mov     si, offset tmpl
        mov     cx, ESZ
        rep     movsb
        pop     cx
        loop    1b
        mov     byte ptr [di], 0xC3
        jmp     2f                      # flush the prefetch queue after building it
2:
        mov     word ptr [mode], 0
next_mode:
        mov     word ptr [vptr], offset variants
next_var:
        mov     si, word ptr [vptr]
        cmp     word ptr [si], 0
        je      done_mode
        mov     dword ptr [seed], 0x2545F491
        mov     dword ptr [cnt], ITER
        mov     dword ptr [bad], 0
        mov     dword ptr [bad4], 0
        mov     dword ptr [bad16], 0
        mov     word ptr [worst], 0
        mov     word ptr [flip], 0

one:
        cmp     word ptr [mode], 0
        jne     3f
        call    rnd                     # mode A: n = 0..127
        and     ax, 127
        jmp     4f
3:      xor     word ptr [flip], 1      # mode B: 127, short, 127, short, ...
        mov     ax, 127
        jnz     4f
        call    rnd
        and     ax, 7
4:      mov     word ptr [n], ax
        imul    bx, ax, ESZ
        xor     si, si
        xor     ecx, ecx
        xor     edx, edx
        mov     di, buf
        mov     bp, word ptr [vptr]
        call    word ptr [bp]           # plant RET at entry n, call the block, restore
        mov     ax, si
        sub     ax, word ptr [n]
        jz      5f
        inc     dword ptr [bad]
        cmp     word ptr [n], 4
        jae     6f
        inc     dword ptr [bad4]
6:      cmp     word ptr [n], 16
        jae     7f
        inc     dword ptr [bad16]
7:      cmp     ax, word ptr [worst]
        jbe     5f
        mov     word ptr [worst], ax
5:      dec     dword ptr [cnt]
        jnz     one

        mov     al, 'A'                 # print the line
        add     al, byte ptr [mode]
        mov     dl, al
        call    putc
        mov     dl, ' '
        call    putc
        mov     si, word ptr [vptr]
        mov     dx, word ptr [si+2]
        call    puts
        mov     dx, offset s_bad
        call    puts
        mov     eax, dword ptr [bad]
        call    putdec
        mov     dx, offset s_n4
        call    puts
        mov     eax, dword ptr [bad4]
        call    putdec
        mov     dx, offset s_n16
        call    puts
        mov     eax, dword ptr [bad16]
        call    putdec
        mov     dx, offset s_worst
        call    puts
        movzx   eax, word ptr [worst]
        call    putdec
        mov     dx, offset s_crlf
        call    puts
        add     word ptr [vptr], 4
        jmp     next_var

done_mode:
        inc     word ptr [mode]
        cmp     word ptr [mode], 2
        jb      next_mode
        mov     ax, 0x4C00
        int     0x21

# ---- the five ways of planting the RET; BX = n * ESZ, SI counts entries ----
v0:     mov     byte ptr [bx+block], 0xC3
        call    block
        mov     byte ptr [bx+block], FIRST
        ret
v1:     mov     byte ptr [bx+block], 0xC3
        jmp     1f
1:      call    block
        mov     byte ptr [bx+block], FIRST
        ret
v2:     mov     byte ptr [bx+block], 0xC3
        mov     al, byte ptr [bx+block]
        call    block
        mov     byte ptr [bx+block], FIRST
        ret
v3:     mov     al, 0xC3
        xchg    byte ptr [bx+block], al
        call    block
        mov     byte ptr [bx+block], FIRST
        ret
v4:     mov     byte ptr [bx+block], 0xC3
        push    bx
        xor     eax, eax
        cpuid
        pop     bx
        call    block
        mov     byte ptr [bx+block], FIRST
        ret

# one entry: the same instruction mix as FALL.EXE 0x14d320 (in 16-bit form) plus INC SI
tmpl:   .byte   0x66, 0x8B, 0xC1        # mov eax, ecx
        .byte   0x8A, 0x85, 0x00, 0x01  # mov al, [di+0x100]
        .byte   0x66, 0x03, 0xCA        # add ecx, edx
        .byte   0x8A, 0x05              # mov al, [di]
        .byte   0x88, 0x85, 0x00, 0x01  # mov [di+0x100], al
        .byte   0x46                    # inc si
        .byte   0x90                    # nop

rnd:                                    # xorshift32 -> EAX
        mov     eax, dword ptr [seed]
        mov     edx, eax
        shl     edx, 13
        xor     eax, edx
        mov     edx, eax
        shr     edx, 17
        xor     eax, edx
        mov     edx, eax
        shl     edx, 5
        xor     eax, edx
        mov     dword ptr [seed], eax
        ret

cpuinfo:                                # print "CPUID: vendor  signature xxxxxxxx"
        mov     dx, offset s_cpuid
        call    puts
        xor     eax, eax
        cpuid
        mov     dword ptr [vend], ebx
        mov     dword ptr [vend+4], edx
        mov     dword ptr [vend+8], ecx
        mov     byte ptr [vend+12], '$'
        mov     dx, offset vend
        call    puts
        mov     dx, offset s_sig
        call    puts
        mov     eax, 1
        cpuid
        call    puthex32
        mov     dx, offset s_crlf
        jmp     puts

puts:   mov     ah, 9
        int     0x21
        ret
putc:   mov     ah, 2
        int     0x21
        ret
puthex32:
        mov     cx, 8
1:      rol     eax, 4
        push    eax
        and     al, 0x0F
        add     al, '0'
        cmp     al, '9'
        jbe     2f
        add     al, 7
2:      mov     dl, al
        call    putc
        pop     eax
        loop    1b
        ret
putdec:                                 # EAX as decimal, right-aligned in 6 columns
        mov     di, offset decbuf+6
        mov     ecx, 10
1:      xor     edx, edx
        div     ecx
        add     dl, '0'
        dec     di
        mov     byte ptr [di], dl
        test    eax, eax
        jnz     1b
2:      cmp     di, offset decbuf
        je      3f
        dec     di
        mov     byte ptr [di], ' '
        jmp     2b
3:      mov     dx, offset decbuf
        jmp     puts

# ---- data ----
variants:
        .word   v0, n_v0
        .word   v1, n_v1
        .word   v2, n_v2
        .word   v3, n_v3
        .word   v4, n_v4
        .word   0

s_title: .ascii "SMCTEST 1.0 - RET planted in code, then called (Daggerfall shading pass)\r\n$"
s_cpuid: .ascii "CPUID: $"
s_sig:   .ascii "  signature $"
s_bad:   .ascii "  bad$"
s_n4:    .ascii "  n<4$"
s_n16:   .ascii "  n<16$"
s_worst: .ascii "  worst$"
s_crlf:  .ascii "\r\n$"
n_v0:    .ascii "V0 store,call      $"
n_v1:    .ascii "V1 store,jmp,call  $"
n_v2:    .ascii "V2 store,read,call $"
n_v3:    .ascii "V3 xchg,call       $"
n_v4:    .ascii "V4 store,cpuid,call$"

        .p2align 2
seed:   .long   0
cnt:    .long   0
bad:    .long   0
bad4:   .long   0
bad16:  .long   0
vend:   .space  13
decbuf: .ascii  "      $"
        .p2align 1
mode:   .word   0
vptr:   .word   0
n:      .word   0
worst:  .word   0
flip:   .word   0
