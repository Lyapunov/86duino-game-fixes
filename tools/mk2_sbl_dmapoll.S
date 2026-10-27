# Broken Record fix for Mortal Kombat II's Sound Blaster driver SBL.BIN (11408 bytes, see mk2_sbl_build.py).
# The driver plays its sound effects with 8-bit auto-init DMA: one 912-byte buffer, two halves of 456
# bytes (about 28 ms each at 16 kHz), described by 8-byte entries at 1C54h (first half) and 1C5Ch.
# [1C64h] = entry of the half now playing, [1C66h] = entry of the half to fill. Only the IRQ handler
# (0B40h) swapped them and called the mixer ([107Ch]). On the 86Duino under SBEMU the IRQs stop
# coming after a few, so the card loops the same 57 ms forever: "e-e-e-e".
# Here poll derives the playing half from the 8237 DMA count instead, and mixes when it changed.
# It is called from the driver's timer tick (function 3, about 55 times a second from RM.DRV's
# INT 8) and from the IRQ handler, whichever comes first; a busy byte stops them nesting.
# Placed over the IRQ autodetect routine 0935h..098Ch (88 bytes), used only when the game passes
# port 0; the patch makes that path skip it (0x6AF jne -> jmp).
# The same driver family is in Lemmings 3D (SBL0.BIN, lem3d_sbl_build.py), with other addresses: they are
# symbols here, MK2's values by default, set with --defsym for other builds.
.ifndef TICKFLAG
        .set TICKFLAG, 0x217            # byte the tick tests first ("cmp byte [217h],0")
.endif
.ifndef DMACH
        .set DMACH, 0x14e7              # DMA channel
.endif
.ifndef HALF1
        .set HALF1, 0x1c54              # entry of the first half
.endif
.ifndef HALF2
        .set HALF2, 0x1c5c              # entry of the second half
.endif
.ifndef PLAYING
        .set PLAYING, 0x1c64            # -> entry of the half playing
.endif
.ifndef TOFILL
        .set TOFILL, 0x1c66             # -> entry of the half to fill
.endif
.ifndef MIXER
        .set MIXER, 0x107c              # pointer to the mixer
.endif
.ifndef HALFSIZE
        .set HALFSIZE, 0x1c8            # bytes per half
.endif
        .code16
        .text
        .globl _start
_start:
tick:   call    poll                    # 0295h: call tick; nop; nop
        cmpb    $0, TICKFLAG               # the replaced instruction (flags go back to the caller)
        ret
poll:   pusha
        cmpb    $0, busy
        jne     9f
        incb    busy
        xor     %al, %al
        out     %al, $0x0c              # clear the 8237 byte flip-flop
        mov     DMACH, %dl             # DMA channel (0..3, 8-bit)
        xor     %dh, %dh
        shl     $1, %dl
        inc     %dx                     # its count register
        in      %dx, %al
        mov     %al, %ah
        in      %dx, %al
        xchg    %al, %ah                # ax = bytes left - 1 in the 912-byte buffer
        mov     $HALF1, %bx
        cmp     $HALFSIZE, %ax
        jae     1f                      # more than 456 left: first half playing
        mov     $HALF2, %bx
1:      cmp     PLAYING, %bx
        je      2f                      # the driver already knows
        mov     PLAYING, %ax
        mov     %ax, TOFILL             # the half that just finished is the one to fill
        mov     %bx, PLAYING
        call    *MIXER                 # mixer: fills [1C66h]
.ifdef COUNT                            # test builds: count the mixes at 0000:04F0
        push    %ds
        xor     %ax, %ax
        mov     %ax, %ds
        incw    0x4f0
        pop     %ds
.endif
2:      decb    busy
9:      popa
        ret
busy:   .byte   0
