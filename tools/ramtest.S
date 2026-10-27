# RAMTEST.COM - test extended memory (the XMS memory a DOS-extended game runs in)
# Built by ramtest_build.py. Run it in real mode with HIMEMX (or another XMS 3.0 driver)
# loaded and no EMM386/JEMM/DPMI host:
#   RAMTEST > RAM.TXT
# ESC between chunks aborts (the memory is still freed).
#
# It allocates and locks the largest free XMS block, switches to unreal mode (FS gets a
# 4 GB limit) and runs each pattern over the whole block: fill, WBINVD (so the
# verify reads come from the RAM chips, not the cache), verify. The last test waits
# 30 s between fill and verify, to catch cells that leak and stray writes from other
# hardware. The first errors of each test are listed with the physical address, the
# expected and read values and the differing bits (XOR).

        .intel_syntax noprefix
        .code16
        .text
        .globl _start

        .equ CHUNK, 0x40000             # dwords per chunk (1 MB), interrupts off during one
        .equ MAXREC, 16                 # errors listed per test
        .equ HOLD_TICKS, 546            # 30 s

_start:
        mov     dx, offset s_title
        call    puts

        smsw    ax
        test    al, 1
        jz      1f
        mov     dx, offset s_v86
        jmp     fail

1:      mov     ax, 0x4300              # XMS driver present?
        int     0x2F
        cmp     al, 0x80
        je      2f
        mov     dx, offset s_noxms
        jmp     fail
2:      mov     ax, 0x4310
        int     0x2F
        mov     word ptr [xms], bx
        mov     word ptr [xms+2], es
        push    cs
        pop     es

        xor     eax, eax                # GDT base for the unreal-mode switch
        mov     ax, cs
        shl     eax, 4
        add     eax, offset gdt
        mov     dword ptr [gdtr+2], eax

        mov     ah, 0x05                # local enable A20
        call    dword ptr [xms]

        mov     ah, 0x88                # XMS 3.0: largest free block (KB) in EAX
        xor     bl, bl
        call    dword ptr [xms]
        or      bl, bl
        jnz     3f
        mov     dword ptr [sizekb], eax
        mov     edx, eax
        mov     ah, 0x89                # allocate EDX KB
        call    dword ptr [xms]
        jmp     4f
3:      mov     ah, 0x08                # XMS 2.0 fallback (up to 64 MB)
        call    dword ptr [xms]
        movzx   eax, ax
        mov     dword ptr [sizekb], eax
        mov     dx, ax
        mov     ah, 0x09
        call    dword ptr [xms]
4:      cmp     ax, 1
        je      5f
        mov     dx, offset s_noalloc
        jmp     fail_a20
5:      mov     word ptr [handle], dx
        mov     ah, 0x0C                # lock: DX:BX = physical address
        call    dword ptr [xms]
        cmp     ax, 1
        je      6f
        mov     dx, offset s_nolock
        jmp     fail_free
6:      mov     word ptr [base], bx
        mov     word ptr [base+2], dx

        mov     dx, offset s_block
        call    puts
        mov     eax, dword ptr [base]
        call    puthex32
        mov     dx, offset s_dash
        call    puts
        mov     eax, dword ptr [sizekb]
        shl     eax, 10
        add     eax, dword ptr [base]
        dec     eax
        call    puthex32
        mov     dx, offset s_open
        call    puts
        mov     eax, dword ptr [sizekb]
        shr     eax, 10
        call    putdec32
        mov     dx, offset s_mb
        call    puts

        mov     word ptr [tptr], offset tests
next_test:
        mov     si, word ptr [tptr]
        mov     ax, word ptr [si]
        or      ax, ax
        jz      all_done
        mov     word ptr [gen], ax
        mov     dx, word ptr [si+2]
        call    puts
        mov     dword ptr [errs], 0

        call    fill
        jc      aborted
        mov     si, word ptr [tptr]
        cmp     word ptr [si+4], 0
        je      7f
        mov     dx, offset s_wait
        call    puts
        call    hold
7:      wbinvd
        call    verify
        jc      aborted
        call    report
        add     word ptr [tptr], 6
        jmp     next_test

all_done:
        mov     dx, offset s_sum
        call    puts
        mov     eax, dword ptr [total]
        call    putdec32
        mov     dx, offset s_sum2
        call    puts
        mov     byte ptr [rc], 0
        cmp     dword ptr [total], 0
        je      cleanup
        mov     byte ptr [rc], 2
        jmp     cleanup
aborted:
        mov     dx, offset s_abort
        call    puts
        mov     byte ptr [rc], 3
cleanup:
        mov     dx, word ptr [handle]
        mov     ah, 0x0D                # unlock
        call    dword ptr [xms]
        mov     dx, word ptr [handle]
        mov     ah, 0x0A                # free
        call    dword ptr [xms]
        mov     ah, 0x06                # local disable A20
        call    dword ptr [xms]
        mov     ah, 0x4C
        mov     al, byte ptr [rc]
        int     0x21

fail_free:
        push    dx
        mov     dx, word ptr [handle]
        mov     ah, 0x0A
        call    dword ptr [xms]
        pop     dx
fail_a20:
        push    dx
        mov     ah, 0x06
        call    dword ptr [xms]
        pop     dx
fail:   call    puts
        mov     ax, 0x4C01
        int     0x21

# FS = flat 4 GB data segment, still in real mode. Call with interrupts off.
unreal:
        lgdt    [gdtr]
        mov     eax, cr0
        or      al, 1
        mov     cr0, eax
        jmp     1f
1:      mov     bx, 8
        mov     fs, bx
        and     al, 0xFE
        mov     cr0, eax
        jmp     2f
2:      xor     bx, bx
        mov     fs, bx
        ret

# start a pass over the block: ESI = base, [left] = dwords
pass_start:
        mov     esi, dword ptr [base]
        mov     eax, dword ptr [sizekb]
        shl     eax, 8
        mov     dword ptr [left], eax
        mov     byte ptr [dots], 0
        ret

# ECX = dwords in the next chunk (0 = done)
next_chunk:
        mov     ecx, dword ptr [left]
        cmp     ecx, CHUNK
        jbe     1f
        mov     ecx, CHUNK
1:      sub     dword ptr [left], ecx
        ret

# after a chunk: progress dot every 8 MB, ESC check. CF=1 = abort.
chunk_end:
        inc     byte ptr [dots]
        test    byte ptr [dots], 7
        jnz     1f
        mov     dl, '.'
        call    putc
1:      mov     ah, 1
        int     0x16
        jz      2f
        xor     ah, ah
        int     0x16
        cmp     al, 27
        jne     2f
        stc
        ret
2:      clc
        ret

fill:   call    pass_start
1:      call    next_chunk
        jecxz   3f
        push    esi
        cli
        call    unreal
        pop     esi
2:      call    word ptr [gen]
        mov     dword ptr fs:[esi], eax
        add     esi, 4
        dec     ecx
        jnz     2b
        sti
        call    chunk_end
        jnc     1b
        ret
3:      clc
        ret

verify: call    pass_start
1:      call    next_chunk
        jecxz   5f
        push    esi
        cli
        call    unreal
        pop     esi
2:      call    word ptr [gen]
        mov     edx, dword ptr fs:[esi]
        cmp     edx, eax
        jne     4f
3:      add     esi, 4
        dec     ecx
        jnz     2b
        sti
        call    chunk_end
        jnc     1b
        ret
4:      inc     dword ptr [errs]        # record: address, expected, read
        cmp     dword ptr [errs], MAXREC
        ja      3b
        mov     bx, word ptr [errs]
        dec     bx
        imul    bx, bx, 12
        mov     dword ptr [errbuf+bx], esi
        mov     dword ptr [errbuf+bx+4], eax
        mov     dword ptr [errbuf+bx+8], edx
        jmp     3b
5:      clc
        ret

hold:   push    es
        mov     ax, 0x40
        mov     es, ax
        mov     ebx, dword ptr es:[0x6C]
1:      mov     eax, dword ptr es:[0x6C]
        sub     eax, ebx
        cmp     eax, HOLD_TICKS
        jb      1b
        pop     es
        ret

report: mov     eax, dword ptr [errs]
        add     dword ptr [total], eax
        or      eax, eax
        jnz     1f
        mov     dx, offset s_ok
        jmp     puts
1:      mov     dx, offset s_errs
        call    puts
        mov     eax, dword ptr [errs]
        call    putdec32
        mov     dx, offset s_errs2
        call    puts
        mov     ecx, dword ptr [errs]
        cmp     ecx, MAXREC
        jbe     2f
        mov     ecx, MAXREC
2:      xor     di, di
3:      push    ecx
        mov     dx, offset s_at
        call    puts
        mov     eax, dword ptr [errbuf+di]
        call    puthex32
        mov     dx, offset s_exp
        call    puts
        mov     eax, dword ptr [errbuf+di+4]
        call    puthex32
        mov     dx, offset s_got
        call    puts
        mov     eax, dword ptr [errbuf+di+8]
        call    puthex32
        mov     dx, offset s_xor
        call    puts
        mov     eax, dword ptr [errbuf+di+4]
        xor     eax, dword ptr [errbuf+di+8]
        call    puthex32
        mov     dx, offset s_crlf
        call    puts
        add     di, 12
        pop     ecx
        dec     ecx
        jnz     3b
        ret

# ---- patterns: ESI = address -> EAX; may use EBX ----
g_addr: mov     eax, esi
        ret
g_naddr: mov    eax, esi
        not     eax
        ret
g_zero: xor     eax, eax
        ret
g_ones: mov     eax, 0xFFFFFFFF
        ret
g_chk:  mov     eax, 0xAAAAAAAA
        test    esi, 4
        jz      1f
        not     eax
1:      ret
g_nchk: call    g_chk
        not     eax
        ret
g_walk1: mov    ebx, ecx
        mov     ecx, esi
        shr     ecx, 2
        mov     eax, 1
        shl     eax, cl
        mov     ecx, ebx
        ret
g_walk0: call   g_walk1
        not     eax
        ret
g_rand: mov     eax, esi                # integer hash of the address
        imul    eax, eax, 0x9E3779B1
        mov     ebx, eax
        shr     ebx, 15
        xor     eax, ebx
        imul    eax, eax, 0x85EBCA77
        mov     ebx, eax
        shr     ebx, 13
        xor     eax, ebx
        ret
g_rand2: push   esi
        xor     esi, 0x5A5A5A5A
        call    g_rand
        pop     esi
        ret

# ---- output ----
puts:   mov     ah, 9
        int     0x21
        ret
putc:   mov     ah, 2
        int     0x21
        ret
puthex32:
        push    cx
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
        pop     cx
        ret
putdec32:
        push    cx
        mov     ebx, 10
        xor     cx, cx
1:      xor     edx, edx
        div     ebx
        push    dx
        inc     cx
        test    eax, eax
        jnz     1b
2:      pop     dx
        add     dl, '0'
        call    putc
        loop    2b
        pop     cx
        ret

# ---- data ----
        .p2align 3
gdt:    .quad   0
        .word   0xFFFF, 0               # flat data: base 0, limit 4 GB, 32-bit
        .byte   0, 0x92, 0xCF, 0
gdtr:   .word   15
        .long   0

tests:  # pattern, name, hold flag
        .word   g_addr,  n1, 0
        .word   g_naddr, n2, 0
        .word   g_zero,  n3, 0
        .word   g_ones,  n4, 0
        .word   g_chk,   n5, 0
        .word   g_nchk,  n6, 0
        .word   g_walk1, n7, 0
        .word   g_walk0, n8, 0
        .word   g_rand,  n9, 0
        .word   g_rand2, n10, 1
        .word   0

n1:     .ascii  " 1 own address      $"
n2:     .ascii  " 2 inverted address $"
n3:     .ascii  " 3 all zeros        $"
n4:     .ascii  " 4 all ones         $"
n5:     .ascii  " 5 checkerboard     $"
n6:     .ascii  " 6 checkerboard inv $"
n7:     .ascii  " 7 walking one      $"
n8:     .ascii  " 8 walking zero     $"
n9:     .ascii  " 9 random           $"
n10:    .ascii  "10 random, 30 s hold$"

s_title: .ascii "RAMTEST - extended memory test (ESC aborts)\r\n\r\n$"
s_v86:  .ascii  "The CPU is in V86 or protected mode (EMM386, JEMM or a DPMI host loaded?).\r\n"
        .ascii  "Boot with only HIMEMX and run again.\r\n$"
s_noxms: .ascii "No XMS driver found. Load HIMEMX first.\r\n$"
s_noalloc: .ascii "Could not allocate XMS memory.\r\n$"
s_nolock: .ascii "Could not lock the XMS block.\r\n$"
s_block: .ascii "Testing physical $"
s_dash: .ascii  "-$"
s_open: .ascii  " ($"
s_mb:   .ascii  " MB)\r\n\r\n$"
s_wait: .ascii  " (waiting 30 s) $"
s_ok:   .ascii  " OK\r\n$"
s_errs: .ascii  " ERRORS: $"
s_errs2: .ascii "\r\n$"
s_at:   .ascii  "   at $"
s_exp:  .ascii  "  expected $"
s_got:  .ascii  "  read $"
s_xor:  .ascii  "  bits $"
s_sum:  .ascii  "\r\nTotal errors: $"
s_sum2: .ascii  "\r\n$"
s_abort: .ascii "\r\nAborted.\r\n$"
s_crlf: .ascii  "\r\n$"

        .p2align 2
xms:    .long   0
base:   .long   0
sizekb: .long   0
left:   .long   0
errs:   .long   0
total:  .long   0
handle: .word   0
gen:    .word   0
tptr:   .word   0
dots:   .byte   0
rc:     .byte   0
        .p2align 2
errbuf: .fill   MAXREC*12, 1, 0
