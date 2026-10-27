# CACHEOFF.COM / CACHEON.COM - switch the CPU caches off or on (CR0.CD) for testing
# Built by cacheoff_build.py: assemble with --defsym CACHE_ON=1 for CACHEON.COM.
#
# CACHEOFF sets CR0.CD (bit 30), clears CR0.NW (bit 29) and flushes the caches with
# WBINVD, so from then on nothing is cached: code and data both come from RAM.
# CACHEON clears both bits again. A reboot also restores the cache.
# Both print CR0 and a loop count per BIOS tick before and after, so the change is
# visible (expect the count to drop many times over with the cache off).
# Must run in real mode: with EMM386/JEMM loaded the CPU is in V86 mode and
# MOV CR0 would fault, so the program refuses and changes nothing.

        .intel_syntax noprefix
        .code16
        .text
        .globl _start
_start:
        mov     dx, offset s_title
        call    puts

        smsw    ax                      # PE bit set = V86/protected mode
        test    al, 1
        jz      real_mode
        mov     dx, offset s_v86
        call    puts
        mov     ax, 0x4C01
        int     0x21

real_mode:
        mov     dx, offset s_before
        call    puts
        call    report

        cli
        mov     eax, cr0
.ifdef CACHE_ON
        and     eax, 0x9FFFFFFF         # CD=0, NW=0: normal write-back caching
        mov     cr0, eax
        wbinvd
.else
        or      eax, 0x40000000         # CD=1
        and     eax, 0xDFFFFFFF         # NW=0
        mov     cr0, eax
        wbinvd                          # empty the caches so no old line still hits
.endif
        sti

        mov     dx, offset s_after
        call    puts
        call    report
        mov     ax, 0x4C00
        int     0x21

# print "CR0 = xxxxxxxx  loops per tick = n"
report:
        mov     dx, offset s_cr0
        call    puts
        mov     eax, cr0
        call    puthex32
        mov     dx, offset s_cd
        call    puts
        mov     eax, cr0
        mov     dl, '0'
        test    eax, 0x40000000
        jz      1f
        mov     dl, '1'
1:      call    putc
        mov     dx, offset s_loops
        call    puts
        call    bench
        call    putdec32
        mov     dx, offset s_crlf
        call    puts
        ret

# count loop passes during one BIOS tick (0040:006C), result in EAX
bench:
        push    es
        mov     ax, 0x40
        mov     es, ax
        mov     bx, es:[0x6C]
1:      cmp     bx, es:[0x6C]           # wait for the start of a fresh tick
        je      1b
        mov     bx, es:[0x6C]
        xor     ecx, ecx
2:      inc     ecx
        cmp     bx, es:[0x6C]
        je      2b
        mov     eax, ecx
        pop     es
        ret

puts:                                   # DX = '$'-terminated string
        mov     ah, 9
        int     0x21
        ret

putc:                                   # DL = character
        mov     ah, 2
        int     0x21
        ret

puthex32:                               # EAX
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

putdec32:                               # EAX, unsigned
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
        ret

s_title:
.ifdef CACHE_ON
        .ascii  "CACHEON - turn the CPU caches back on (CR0.CD=0)\r\n\r\n$"
.else
        .ascii  "CACHEOFF - turn the CPU caches off (CR0.CD=1, WBINVD)\r\n\r\n$"
.endif
s_v86:  .ascii  "The CPU is in V86 or protected mode (EMM386, JEMM or a DPMI host loaded?).\r\n"
        .ascii  "Boot without it and run again. Nothing was changed.\r\n$"
s_before: .ascii "Before: $"
s_after:  .ascii "After : $"
s_cr0:  .ascii  "CR0 = $"
s_cd:   .ascii  "  CD = $"
s_loops: .ascii "  loops per tick = $"
s_crlf: .ascii  "\r\n$"
