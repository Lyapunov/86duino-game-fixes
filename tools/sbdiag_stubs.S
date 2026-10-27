# Stubs appended to SBPRO.DIG at offset 0B20h (see sbdiag_build.py). Counters live in the BIOS
# inter-application area 0000:04F0 so they survive GTA reloading the driver:
#   04F0 dd IRQ handler calls, 04F4 dd half-buffer flips, 04F8 dd playback starts, 04FC db PIC mask at last start
        .code16
        .text
        .globl _start
_start:
isr:    push    %ds                     # IRQ entry (vector points here)
        push    %ax
        xor     %ax, %ax
        mov     %ax, %ds
        addw    $1, 0x4f0
        adcw    $0, 0x4f2
        pop     %ax
        pop     %ds
        jmp     0x6d3
flip:   xorw    $1, 0x515               # replaced instruction (ds = driver)
        push    %ds
        push    %ax
        xor     %ax, %ax
        mov     %ax, %ds
        addw    $1, 0x4f4
        adcw    $0, 0x4f6
        pop     %ax
        pop     %ds
        jmp     0x758
start:  movw    $3, 0x5d3               # replaced instruction (ds = driver)
        push    %ds
        push    %ax
        xor     %ax, %ax
        mov     %ax, %ds
        addw    $1, 0x4f8
        adcw    $0, 0x4fa
        in      $0x21, %al
        mov     %al, 0x4fc
        pop     %ax
        pop     %ds
        jmp     0xab3
