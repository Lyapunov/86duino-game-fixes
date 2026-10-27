# Broken Record fix for GTA (see gta_build.py). Helper placed in gta8.exe's unused padding at 0x12AD40 (code object).
# Miles' DIG service (0x118EFB) used to read the driver's "playing half" flag, which only the
# SB IRQ handler flips. Here we derive the playing half from the 8237 DMA count instead, so
# the mixer keeps going even when IRQ 5 never reaches the real-mode driver.
#   in:  eax = DIG driver struct (Miles), [eax+0Ch] = linear address of the driver's DST
#        DST+0 buf0 offset, DST+4 buf1 offset (same segment), DST+8 flag (-1 = stopped)
#        driver offset 160h (= DST-3ADh) = 8-bit DMA channel
#   out: ebx = playing half (0/1) or -1; all other registers preserved. No cli/sti (HDPMI traps them).
        .code32
        .text
        .globl _start
_start:
        mov     0xc(%eax), %ebx         # DST
        push    %ecx
        push    %edx
        movswl  8(%ebx), %ecx           # driver's own flag
        cmp     $-1, %ecx
        je      done                    # stopped: keep Miles' old behaviour
        movzwl  -0x3ad(%ebx), %edx      # DMA channel
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
done:   mov     %ecx, %ebx
        pop     %edx
        pop     %ecx
        ret
