# (Build: python3 dosbuild.py i13test.S)
# I13TEST.COM - QEMU test for GHOSTFIX: INT 13h reads/writes on a SCRATCH disk
# (drive 81h) with the buffer in the EMS page frame, LBA (42h/43h) and CHS
# (02h/03h). Writes 64 sectors at LBA 100 (LBA test) and 64 sectors at
# C/H/S 1/0/1 (CHS test) - only ever use it on a disposable disk.
# Each test: fill the frame with a pattern, write from the frame, clear the
# frame, read back into the frame, and also read into normal memory; both
# must match the pattern.
        .code16
        .set drv, 0x81
        .set nsec, 64
        .globl _start
_start: mov   $0x41, %ah                # frame + 4 pages mapped 0..3
        int   $0x67
        mov   %bx, frame
        mov   $0x43, %ah
        mov   $4, %bx
        int   $0x67
        mov   %dx, emsh
        xor   %bp, %bp
1:      mov   %bp, %bx
        mov   %bp, %ax
        mov   $0x44, %ah
        mov   emsh, %dx
        int   $0x67
        inc   %bp
        cmp   $4, %bp
        jb    1b
        mov   $0x4a, %ah                # 32 KB normal buffer
        mov   $0x1000, %bx
        push  %cs
        pop   %es
        int   $0x21
        mov   $0x48, %ah
        mov   $0x800, %bx
        int   $0x21
        mov   %ax, lowseg
        movb  $0, mode                  # 0 = LBA, 1 = CHS
test:   mov   $msg_lba, %dx
        cmpb  $0, mode
        je    1f
        mov   $msg_chs, %dx
1:      call  puts
        mov   frame, %es                # fill frame with the pattern
        xor   %di, %di
        mov   $nsec*256, %cx
        mov   mode, %al
        add   $0x31, %al
        mov   %al, %ah
        add   $0x10, %ah
2:      stosw
        add   $0x0703, %ax
        loop  2b
        mov   $3, %ah                   # write from the frame
        mov   frame, %es
        call  xfer
        jc    bad
        mov   frame, %es                # clear the frame
        xor   %di, %di
        mov   $nsec*256, %cx
        xor   %ax, %ax
        rep   stosw
        mov   $2, %ah                   # read back into the frame
        mov   frame, %es
        call  xfer
        jc    bad
        mov   $2, %ah                   # and into normal memory
        mov   lowseg, %es
        call  xfer
        jc    bad
        mov   frame, %es                # compare both with the pattern
        mov   lowseg, %ds
        xor   %si, %si
        xor   %di, %di
        mov   $nsec*256, %cx
        mov   %cs:mode, %al
        add   $0x31, %al
        mov   %al, %ah
        add   $0x10, %ah
        xor   %bx, %bx
3:      cmp   %es:(%di), %ax
        je    4f
        inc   %bx
4:      cmp   (%si), %ax
        je    5f
        inc   %bx
5:      add   $2, %si
        add   $2, %di
        add   $0x0703, %ax
        loop  3b
        push  %cs
        pop   %ds
        test  %bx, %bx
        jnz   bad
        mov   $msg_ok, %dx
        call  puts
        jmp   next
bad:    push  %cs
        pop   %ds
        mov   $msg_bad, %dx
        call  puts
next:   incb  mode
        cmpb  $2, mode
        jb    test
        mov   $0x45, %ah
        mov   emsh, %dx
        int   $0x67
        mov   $0x4c00, %ax
        int   $0x21

# xfer: ah = 2 (read) / 3 (write), es:0000 = buffer; LBA or CHS by mode
xfer:   cmpb  $0, mode
        jne   1f
        add   $0x40, %ah                # 42h/43h
        movw  $16, dap
        movw  $nsec, dap+2
        movw  $0, dap+4
        mov   %es, dap+6
        movw  $100, dap+8
        movw  $0, dap+10
        movw  $0, dap+12
        movw  $0, dap+14
        xor   %al, %al
        mov   $dap, %si
        mov   $drv, %dl
        int   $0x13
        ret
1:      mov   $nsec, %al                # CHS: cylinder 1, head 0, sector 1
        mov   $1, %ch
        mov   $1, %cl
        xor   %dh, %dh
        mov   $drv, %dl
        xor   %bx, %bx
        int   $0x13
        ret

puts:   mov   $9, %ah
        int   $0x21
        ret
msg_lba: .ascii "LBA 42h/43h: $"
msg_chs: .ascii "CHS 02h/03h: $"
msg_ok:  .ascii "OK\r\n$"
msg_bad: .ascii "FAILED\r\n$"
frame:  .word 0
emsh:   .word 0
lowseg: .word 0
mode:   .byte 0
dap:    .space 16
