# Broken Record fix for Mortal Kombat 3 (see mk3_build.py). Helper placed over an unused C-library
# routine at 0x4C3B9 in MK3.EXE (nothing calls it; no relocations in these bytes).
# Miles 3.02's DIG service (0x611A7) used to read the SB driver's "playing half" flag, which only the
# driver's IRQ handler flips. Here we derive the playing half from the 8237 DMA count instead.
#   in:  eax = DIG driver struct (Miles), [eax+8] = linear address of the driver's buffer table (DST)
#        DST+0 buf0 offset, DST+4 buf1 offset (same segment), DST+8 flag (-1 = stopped)
#        driver offset 160h (= DST-39Ch in this driver build) = 8-bit DMA channel
#   out: edi = playing half (0/1) or -1; all other registers preserved. No cli/sti (HDPMI traps them).
        .code32
        .text
        .globl _start
_start:
        push    %ebx
        push    %ecx
        push    %edx
        mov     0x8(%eax), %ebx         # DST
        movswl  8(%ebx), %ecx           # driver's own flag
        cmp     $-1, %ecx
        je      done                    # stopped: keep Miles' old behaviour
        movzwl  -0x39c(%ebx), %edx      # DMA channel
        cmp     $3, %edx
        ja      done                    # 16-bit channel: not handled, use the flag
        push    %eax
        movzwl  4(%ebx), %eax
        sub     (%ebx), %ax             # half-buffer size in bytes
        movzwl  %ax, %ebx
        xor     %al, %al
        out     %al, $0x0c              # clear the 8237 byte flip-flop
        lea     1(%edx,%edx), %edx      # count register of channel 0..3
        in      (%dx), %al
        mov     %al, %ah
        in      (%dx), %al
        xchg    %al, %ah                # ax = remaining count - 1
        movzwl  %ax, %eax
        inc     %eax                    # bytes left in the whole buffer
        xor     %ecx, %ecx
        cmp     %ebx, %eax
        ja      1f                      # more than half left: first half playing
        inc     %ecx
1:      pop     %eax
done:   mov     %ecx, %edi
        pop     %edx
        pop     %ecx
        pop     %ebx
        ret
