# Wacky Wheels (WW.EXE v1.1) keyboard diagnostic "kbdcells", built into a copy
# of the game by ww_kbdcells_build.py. See trap-storm.md, Step 6 and Step 7.
# It shows the state of the keyboard path as two rows of 8 cells at the top left
# of the displayed page, redrawn from the Apogee Sound System timer handler
# (0x40b65) every 64 ticks. It does no PIC or keyboard-controller port I/O at
# all: an `in 64h` is itself trapped by the 86Duino's USB keyboard emulation,
# and an earlier version that read it made the freeze worse. It watches the
# BIOS side through low memory instead (mapped 1:1 under DOS/4G).
# Cell tall = 1, short = 0. Row 1, left to right:
#   0 heartbeat (blinks while the timer runs)
#   1 BIOS tick counter 0:046C moved since the last redraw (BIOS timer alive)
#   2 the BIOS tick counter was ever seen stopped (sticky)
#   3 BIOS keyboard buffer not empty (0:041A != 0:041C)
#   4 BIOS shift flags 0:0417 say Ctrl or Alt is held (BIOS INT 9 gets keys)
#   5 the game's keyboard busy flag 0x88b30 set
#   6 the game's keyboard ISR read a key in the last ~1 s
#   7 the busy flag was ever seen set (sticky)
# Row 2: the last byte the game's ISR read from port 60h, bit 7 at the left.
        .code32
        .set link,      0x5be30
        .set ret_isr,   0x40b6b
        .set asm_ds,    0x41448
        .set kbd_ret,   0x4093a
        .set busyref,   0x40915 - link
        .globl _start
_start:
# variables first, so that every access is a short (disp8) one
tick:   .long 0
kseen:  .byte 0
lastsc: .byte 0
bsever: .byte 0
bstop:  .byte 0
btick:  .long 0
# hook 1: keyboard ISR, replaces in $0x60,%al; push %ax; in $0x61,%al at 0x40934
kread:  in    $0x60, %al
        push  %ebx
        call  1f
1:      pop   %ebx
        mov   %al, lastsc-1b(%ebx)
        movb  $4, kseen-1b(%ebx)
        pop   %ebx
        push  %ax
        in    $0x61, %al
        jmp   kbd_ret
# hook 2: ASS timer ISR entry (replaces cld; call asm_ds at 0x40b65)
isr:    cld
        call  asm_ds
        pushal
        call  1f
1:      pop   %esi
        add   $(tick-1b), %esi
        incl  tick-tick(%esi)
        testb $63, tick-tick(%esi)
        jnz   2f
        call  show
2:      popal
        jmp   ret_isr
# bit: shift (al & ah) != 0 into bl
bit:    test  %ah, %al
        setnz %cl
        add   %bl, %bl
        or    %cl, %bl
        ret
show:   mov   lastsc-tick(%esi), %bh
        mov   tick-tick(%esi), %eax
        shr   $6, %eax
        and   $1, %al
        mov   %al, %bl                 # 0 heartbeat
        mov   0x46c, %eax
        cmp   btick-tick(%esi), %eax
        mov   %eax, btick-tick(%esi)
        setne %al
        mov   $1, %ah
        call  bit                      # 1 BIOS tick moved
        xor   $1, %al
        or    %al, bstop-tick(%esi)
        mov   bstop-tick(%esi), %al
        call  bit                      # 2 BIOS tick ever stopped
        mov   0x41a, %ax
        cmp   0x41c, %ax
        setne %al
        mov   $1, %ah
        call  bit                      # 3 BIOS buffer not empty
        mov   0x417, %al
        mov   $0x0c, %ah
        call  bit                      # 4 BIOS sees Ctrl/Alt held
        mov   $0xff, %ah
        mov   busyref-(tick-_start)(%esi), %edx
        mov   (%edx), %al
        or    %al, bsever-tick(%esi)
        call  bit                      # 5 busy
        mov   kseen-tick(%esi), %al
        sub   $1, %al
        adc   $0, %al
        mov   %al, kseen-tick(%esi)
        call  bit                      # 6 ISR read a key recently
        mov   bsever-tick(%esi), %al
        call  bit                      # 7 busy ever
# VGA: save and set the registers we change, then page start and line width
        mov   $0x3c4, %dx
        mov   $0x02, %ah               # map mask = 0Fh
        mov   $0x0f, %cl
        call  setr
        push  %eax
        mov   $0x3ce, %dx
        mov   $0x01, %ah               # set/reset enable = 0
        mov   $0, %cl
        call  setr
        push  %eax
        mov   $0x03, %ah               # rotate/function = 0
        mov   $0, %cl
        call  setr
        push  %eax
        mov   $0x08, %ah               # bit mask = FFh
        mov   $0xff, %cl
        call  setr
        push  %eax
        mov   $0x05, %al               # mode: write mode 0, keep the rest
        out   %al, %dx
        inc   %dx
        in    %dx, %al
        mov   %al, %ch
        and   $0xfc, %al
        out   %al, %dx
        dec   %dx
        push  %ecx
        mov   $0x3d4, %dx
        in    %dx, %al
        push  %eax
        mov   $0x0c, %al
        out   %al, %dx
        inc   %dx
        in    %dx, %al
        mov   %al, %ah
        dec   %dx
        mov   $0x0d, %al
        out   %al, %dx
        inc   %dx
        in    %dx, %al
        movzwl %ax, %esi               # page start
        dec   %dx
        mov   $0x13, %al
        out   %al, %dx
        inc   %dx
        in    %dx, %al
        movzbl %al, %edi
        add   %edi, %edi               # bytes per line
        dec   %dx
        pop   %eax
        out   %al, %dx
        lea   0xa0002(%esi,%edi,4), %esi   # row 1 at y=4, x=8
        call  draw
        lea   -40(%esi,%edi,4), %esi   # row 2 at y=16
        lea   (%esi,%edi,8), %esi
        mov   %bh, %bl
        call  draw
        mov   $0x3ce, %dx
        pop   %ecx                     # restore mode, bit mask, rotate,
        mov   $0x05, %al               # set/reset enable, map mask, indices
        out   %al, %dx
        inc   %dx
        mov   %ch, %al
        out   %al, %dx
        dec   %dx
        pop   %eax
        call  rstr
        pop   %eax
        call  rstr
        pop   %eax
        call  rstr
        mov   $0x3c4, %dx
        pop   %eax
# rstr: eax = old index<<16 | reg<<8 | old value (from setr)
rstr:   push  %eax
        mov   %ah, %al
        out   %al, %dx
        inc   %dx
        pop   %eax
        out   %al, %dx
        dec   %dx
        shr   $16, %eax
        out   %al, %dx
        ret
# setr: dx = index port, ah = register, cl = new value -> eax as for rstr
setr:   in    %dx, %al
        movzbl %al, %edi
        mov   %ah, %al
        out   %al, %dx
        inc   %dx
        in    %dx, %al
        xchg  %al, %cl
        out   %al, %dx
        dec   %dx
        mov   %cl, %al
        shl   $16, %edi
        or    %edi, %eax
        ret
# draw: esi = top-left byte, edi = bytes per line, bl = bits (bit 7 first).
# 8 cells 16 pixels wide, 20 pixels apart: 1 = 10 rows of colour 15,
# 0 = 3 rows of colour 8 (the palette changes per screen, the height doesn't).
# Leaves esi 40 bytes to the right.
        .set on,  0x0f0f0f0f
        .set off, 0x08080808
draw:   mov   $8, %ecx
1:      mov   $off, %eax
        mov   $3, %dl
        add   %bl, %bl
        jnc   2f
        mov   $on, %eax
        mov   $10, %dl
2:      push  %ecx
        push  %esi
        movzbl %dl, %ecx
3:      mov   %eax, (%esi)
        add   %edi, %esi
        loop  3b
        pop   %esi
        pop   %ecx
        add   $5, %esi
        loop  1b
        ret
