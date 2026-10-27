# EMSWRITE.COM - does a DOS file WRITE from the EMS page frame store the right data?
#
# The mirror image of EMSREAD: a disk controller that moves data by DMA reads
# physical memory and bypasses the EMS mapping, so writing a file *from* the
# page frame can store whatever lies in the RAM behind the frame.
#   EMSWRITE W   fills the 4 frame pages (64 KB) with a known pattern, then writes
#                EMSW.TMP: 60 KB in ONE write from frame:0000, then the four
#                16 KB pages in four writes (124 KB in total)
#   EMSWRITE C   reads EMSW.TMP back into normal memory and checks the pattern,
#                per 16 KB block
# Run W, then empty the disk cache (Win9x SMARTDRV: SMARTDRV /R, which first writes
# everything to disk), then C - otherwise C may just read back the cache.
# Build: python3 dosbuild.py emswrite.S (GNU binutils).
        .code16
        .set chunk, 16384
        .set big, 61440
        .globl _start
_start: mov   $msg_title, %dx
        call  puts
        mov   $0x81, %si                # first non-blank argument character
1:      lodsb
        cmp   $' ', %al
        je    1b
        and   $0xdf, %al                # upper case
        cmp   $'W', %al
        je    dowrite
        cmp   $'C', %al
        je    docheck
        mov   $msg_usage, %dx
        jmp   fail

# ---- W: fill the frame and write the file
dowrite: mov  $0x41, %ah
        int   $0x67
        test  %ah, %ah
        jnz   eems
        mov   %bx, frame
        mov   $0x43, %ah
        mov   $4, %bx
        int   $0x67
        test  %ah, %ah
        jnz   eems
        mov   %dx, emsh
        xor   %bp, %bp
1:      mov   %bp, %bx
        mov   %bp, %ax
        mov   $0x44, %ah
        mov   emsh, %dx
        int   $0x67
        test  %ah, %ah
        jnz   eems2
        inc   %bp
        cmp   $4, %bp
        jb    1b
        xor   %bp, %bp                  # fill page by page: frame offset = bp*16K + di
2:      mov   %bp, %ax
        shl   $10, %ax
        add   frame, %ax
        mov   %ax, %es
        xor   %di, %di
3:      mov   %bp, %dx
        shl   $14, %dx
        add   %di, %dx
        call  pattern
        stosb
        cmp   $chunk, %di
        jb    3b
        inc   %bp
        cmp   $4, %bp
        jb    2b
        mov   $0x3c, %ah                # create EMSW.TMP
        xor   %cx, %cx
        mov   $tmpname, %dx
        int   $0x21
        jc    efile2
        mov   %ax, handle
        push  %ds                       # one 60 KB write from frame:0000
        mov   handle, %bx
        mov   $big, %cx
        mov   frame, %ds
        xor   %dx, %dx
        mov   $0x40, %ah
        int   $0x21
        pop   %ds
        jc    ewrite2
        xor   %bp, %bp                  # four 16 KB writes, one per page
4:      push  %ds
        mov   %bp, %ax
        shl   $10, %ax
        add   frame, %ax
        mov   handle, %bx
        mov   $chunk, %cx
        mov   %ax, %ds
        xor   %dx, %dx
        mov   $0x40, %ah
        int   $0x21
        pop   %ds
        jc    ewrite2
        inc   %bp
        cmp   $4, %bp
        jb    4b
        mov   $0x3e, %ah
        mov   handle, %bx
        int   $0x21
        call  free
        mov   $msg_wdone, %dx
        call  puts
        jmp   exit

# ---- C: read the file back into normal memory and check
docheck: mov  $0x4a, %ah                # shrink to 64 KB, get a 16 KB buffer
        mov   $0x1000, %bx
        push  %cs
        pop   %es
        int   $0x21
        mov   $0x48, %ah
        mov   $chunk/16, %bx
        int   $0x21
        jc    emem
        mov   %ax, bufseg
        mov   $0x3d00, %ax
        mov   $tmpname, %dx
        int   $0x21
        jc    efile
        mov   %ax, handle
        xor   %bp, %bp                  # block 0..7 (16 KB each, the last ones short)
5:      push  %ds
        mov   handle, %bx
        mov   $chunk, %cx
        mov   bufseg, %ds
        xor   %dx, %dx
        mov   $0x3f, %ah
        int   $0x21
        pop   %ds
        jc    eread
        test  %ax, %ax
        jz    9f
        mov   %ax, %cx                  # cx = bytes in this block
        mov   bufseg, %es
        xor   %di, %di
        xor   %bx, %bx                  # wrong bytes
6:      push  %cx                       # file offset -> frame offset
        mov   %bp, %ax                  # file offset = bp*16K + di (32-bit)
        xor   %dx, %dx
        mov   $chunk, %cx
        mul   %cx                       # dx:ax = bp*16K
        add   %di, %ax
        adc   $0, %dx
        sub   $big, %ax                 # part B starts at file offset 61440
        sbb   $0, %dx
        jns   7f
        add   $big, %ax                 # part A: frame offset = file offset
7:      mov   %ax, %dx
        call  pattern
        pop   %cx
        cmp   %es:(%di), %al
        je    8f
        inc   %bx
8:      inc   %di
        loop  6b
        mov   %bx, diff
        mov   $msg_block, %dx
        call  puts
        mov   %bp, %ax
        add   $'0', %al
        call  putc
        mov   $msg_diff, %dx
        call  puts
        mov   diff, %ax
        call  decword
        mov   $msg_wrong, %dx
        call  puts
        mov   diff, %ax
        or    %ax, total
        inc   %bp
        jmp   5b
9:      mov   $0x3e, %ah
        mov   handle, %bx
        int   $0x21
        mov   $msg_ok, %dx
        cmpw  $0, total
        je    1f
        mov   $msg_bad, %dx
1:      call  puts
        jmp   exit

# pattern: dx = frame offset -> al = expected byte
pattern: mov  %dl, %al
        push  %dx
        mov   %dh, %dl
        mov   $31, %ah
        xchg  %al, %dl
        mul   %ah                       # ax = (offset>>8)*31
        add   %dl, %al
        add   $0x5a, %al
        pop   %dx
        ret

free:   mov   $0x45, %ah
        mov   emsh, %dx
        int   $0x67
        ret

eems2:  call  free
eems:   mov   $msg_eems, %dx
        jmp   fail
efile2: call  free
efile:  mov   $msg_efile, %dx
        jmp   fail
ewrite2: call free
        mov   $msg_ewrite, %dx
        jmp   fail
emem:   mov   $msg_emem, %dx
        jmp   fail
eread:  mov   $msg_eread, %dx
fail:   call  puts
exit:   mov   $0x4c00, %ax
        int   $0x21

decword: xor  %cx, %cx
        mov   $10, %bx
1:      xor   %dx, %dx
        div   %bx
        push  %dx
        inc   %cx
        test  %ax, %ax
        jnz   1b
2:      pop   %ax
        add   $'0', %al
        call  putc
        loop  2b
        ret
putc:   push  %dx
        mov   %al, %dl
        mov   $2, %ah
        int   $0x21
        pop   %dx
        ret
puts:   mov   $9, %ah
        int   $0x21
        ret

msg_title: .ascii "EMSWRITE: DOS file writes from the EMS page frame\r\n$"
msg_usage: .ascii "usage: EMSWRITE W   (write EMSW.TMP from the frame)\r\n       SMARTDRV /R  (if a cache is loaded)\r\n       EMSWRITE C   (check EMSW.TMP)\r\n$"
msg_wdone: .ascii "EMSW.TMP written (124 KB). Now empty the cache (SMARTDRV /R), then run EMSWRITE C.\r\n$"
msg_block: .ascii "16 KB block $"
msg_diff:  .ascii ": $"
msg_wrong: .ascii " bytes wrong\r\n$"
msg_ok:    .ascii "= Writes from the page frame are correct.\r\n$"
msg_bad:   .ascii "= Writes from the page frame are WRONG (blocks 0-3: one 60 KB write; 3-7: four 16 KB writes)\r\n$"
msg_eems:  .ascii "EMS error (no EMS driver, or no free pages).\r\n$"
msg_efile: .ascii "Cannot create/open EMSW.TMP.\r\n$"
msg_ewrite: .ascii "Write error (disk full?).\r\n$"
msg_emem:  .ascii "Not enough memory.\r\n$"
msg_eread: .ascii "Read error.\r\n$"
tmpname:   .asciz "EMSW.TMP"
frame:     .word 0
emsh:      .word 0
handle:    .word 0
bufseg:    .word 0
diff:      .word 0
total:     .word 0
