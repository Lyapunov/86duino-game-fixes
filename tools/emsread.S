# EMSREAD.COM - does a DOS file read land correctly in the EMS page frame?
#
# EMS pages appear in the page frame through the CPU's paging. A disk
# controller that moves data by DMA writes to physical addresses and bypasses
# that mapping, so a read *into* the page frame can silently miss. This test
# first reads 60 KB in ONE call (file offset 64 KB) straight into the page
# frame, like a game loading a full-screen picture, then the same 60 KB into
# normal memory, and compares. Then the same for four 16 KB chunks (offset 0).
# The frame (pre-filled with the marker byte A5h) is always read FIRST, so a
# disk cache can't serve that read from data it just fetched for the normal-
# memory read. With a cache, empty it first (Win9x SMARTDRV: SMARTDRV /R).
#   usage: EMSREAD [file]      default: DATA\LEV.ARK (needs >= 124 KB)
# Per chunk it prints how many bytes differ, and how many of those still hold
# the marker (= the data never arrived there). Run as  EMSREAD > ER.TXT
# Build: python3 dosbuild.py emsread.S (GNU binutils).
        .code16
        .set chunk, 16384
        .set big, 61440
        .globl _start
_start: mov   $msg_title, %dx
        call  puts
        mov   $0x80, %si                # file name from the command line
        mov   (%si), %cl
        xor   %ch, %ch
        inc   %si
1:      jcxz  2f                        # skip leading blanks
        cmpb  $' ', (%si)
        jne   3f
        inc   %si
        dec   %cx
        jmp   1b
2:      mov   $defname, %dx             # no argument
        jmp   4f
3:      mov   %si, %dx                  # terminate the argument with 0
        add   %cx, %si
        movb  $0, (%si)
4:      mov   %dx, fname
        mov   $0x3d00, %ax              # open for reading
        int   $0x21
        jc    efile
        mov   %ax, handle
        mov   $0x4a, %ah                # shrink to 64 KB, then get a 60 KB buffer
        mov   $0x1000, %bx
        push  %cs
        pop   %es
        int   $0x21
        mov   $0x48, %ah
        mov   $big/16, %bx
        int   $0x21
        jc    emem
        mov   %ax, bufseg
        mov   $0x41, %ah                # EMS page frame
        int   $0x67
        test  %ah, %ah
        jnz   eems
        mov   %bx, frame
        mov   $msg_frame, %dx
        call  puts
        mov   frame, %ax
        call  hexword
        mov   $msg_crlf, %dx
        call  puts
        mov   $0x43, %ah                # 4 pages
        mov   $4, %bx
        int   $0x67
        test  %ah, %ah
        jnz   eems
        mov   %dx, emsh
        xor   %bp, %bp                  # map logical page n -> physical n
5:      mov   %bp, %bx
        mov   %bp, %ax
        mov   $0x44, %ah
        mov   emsh, %dx
        int   $0x67
        test  %ah, %ah
        jnz   eems2
        inc   %bp
        cmp   $4, %bp
        jb    5b
        call  bigtest
        xor   %bp, %bp                  # chunk loop
6:      mov   %bp, %ax                  # page seg = frame + n*400h
        shl   $10, %ax
        add   frame, %ax
        mov   %ax, %es
        xor   %di, %di
        mov   $chunk, %cx
        mov   $0xa5, %al
        cld
        rep   stosb                     # fill with the marker
        mov   %es, %ax
        call  readat                    # read the chunk into the frame first
        jc    eread
        mov   bufseg, %ax               # then into normal memory
        call  readat
        jc    eread
        push  %ds                       # compare
        mov   bufseg, %ds
        xor   %si, %si
        xor   %di, %di
        xor   %bx, %bx                  # bytes that differ
        xor   %dx, %dx                  # ...of which still the marker
        mov   $chunk, %cx
7:      mov   (%si), %al
        cmp   %es:(%di), %al
        je    8f
        inc   %bx
        cmpb  $0xa5, %es:(%di)
        jne   8f
        inc   %dx
8:      inc   %si
        inc   %di
        loop  7b
        pop   %ds
        mov   %bx, diff
        mov   %dx, mark
        mov   $msg_chunk, %dx
        call  puts
        mov   %bp, %ax
        add   $'0', %al
        call  putc
        mov   $msg_diff, %dx
        call  puts
        mov   diff, %ax
        call  decword
        mov   $msg_mark, %dx
        call  puts
        mov   mark, %ax
        call  decword
        mov   $msg_close, %dx
        call  puts
        mov   diff, %ax
        or    %ax, total
        inc   %bp
        cmp   $4, %bp
        jb    6b
        call  free
        mov   $msg_ok, %dx
        cmpw  $0, total
        je    9f
        mov   $msg_bad, %dx
9:      call  puts
        jmp   exit

# readat: read chunk bp of the file into ax:0000; CF on error
readat: push  %ds
        push  %ax
        mov   %bp, %dx                  # lseek to bp*16384
        mov   %dx, %cx
        shr   $2, %cx                   # high word = bp >> 2
        shl   $14, %dx                  # low word = bp << 14
        mov   handle, %bx
        mov   $0x4200, %ax
        int   $0x21
        pop   %ax
        jc    1f
        mov   handle, %bx
        mov   $chunk, %cx
        mov   %ax, %ds
        xor   %dx, %dx
        mov   $0x3f, %ah
        int   $0x21
        jc    1f
        cmp   $chunk, %ax               # need a full chunk
        jne   2f
        clc
        jmp   1f
2:      stc
1:      pop   %ds
        ret


# bigtest: read 60 KB from file offset 64 KB in one call, into frame:0000 (all
# four pages, pre-filled with A5h) first, then into normal memory; report per page
bigtest: mov  $msg_big, %dx
        call  puts
        mov   frame, %es
        xor   %di, %di
        mov   $big, %cx
        mov   $0xa5, %al
        cld
        rep   stosb
        mov   frame, %ax
        call  readbig
        jc    9f
        mov   bufseg, %ax
        call  readbig
        jc    9f
        mov   frame, %es
        xor   %bp, %bp
1:      push  %ds
        mov   bufseg, %ds
        mov   %bp, %si
        shl   $14, %si
        mov   %si, %di
        xor   %bx, %bx
        xor   %dx, %dx
        mov   $chunk, %cx
        cmp   $3, %bp                   # the last page holds only 12 KB of the 60
        jne   2f
        mov   $big-3*chunk, %cx
2:      mov   (%si), %al
        cmp   %es:(%di), %al
        je    3f
        inc   %bx
        cmpb  $0xa5, %es:(%di)
        jne   3f
        inc   %dx
3:      inc   %si
        inc   %di
        loop  2b
        pop   %ds
        mov   %bx, diff
        mov   %dx, mark
        mov   $msg_page, %dx
        call  puts
        mov   %bp, %ax
        add   $'0', %al
        call  putc
        mov   $msg_diff, %dx
        call  puts
        mov   diff, %ax
        call  decword
        mov   $msg_mark, %dx
        call  puts
        mov   mark, %ax
        call  decword
        mov   $msg_close, %dx
        call  puts
        mov   diff, %ax
        or    %ax, total
        inc   %bp
        cmp   $4, %bp
        jb    1b
        ret
9:      mov   $msg_eread, %dx
        call  puts
        orw   $1, total
        ret

# readbig: read 60 KB from file offset 64 KB into ax:0000; CF on error
readbig: push %ds
        push  %ax
        mov   handle, %bx
        mov   $0x4200, %ax
        mov   $1, %cx                   # offset 1:0000 = 64 KB
        xor   %dx, %dx
        int   $0x21
        pop   %ax
        jc    1f
        mov   handle, %bx
        mov   $big, %cx
        mov   %ax, %ds
        xor   %dx, %dx
        mov   $0x3f, %ah
        int   $0x21
        jc    1f
        cmp   $big, %ax
        je    1f
        stc
1:      pop   %ds
        ret

free:   mov   $0x45, %ah
        mov   emsh, %dx
        int   $0x67
        ret

efile:  mov   $msg_efile, %dx
        jmp   fail
emem:   mov   $msg_emem, %dx
        jmp   fail
eems2:  call  free
eems:   mov   $msg_eems, %dx
        jmp   fail
eread:  call  free
        mov   $msg_eread, %dx
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
hexword: push %ax
        mov   %ah, %al
        call  hexbyte
        pop   %ax
hexbyte: push %ax
        shr   $4, %al
        call  1f
        pop   %ax
1:      and   $15, %al
        add   $'0', %al
        cmp   $'9', %al
        jbe   putc
        add   $7, %al
putc:   push  %dx
        mov   %al, %dl
        mov   $2, %ah
        int   $0x21
        pop   %dx
        ret
puts:   mov   $9, %ah
        int   $0x21
        ret

msg_title: .ascii "EMSREAD: DOS file reads into normal memory vs. into the EMS page frame\r\n$"
msg_frame: .ascii "Page frame at segment $"
msg_crlf:  .ascii "h\r\n$"
msg_chunk: .ascii "16 KB chunk $"
msg_diff:  .ascii ": $"
msg_mark:  .ascii " bytes differ ($"
msg_close: .ascii " of them never written)\r\n$"
msg_big:   .ascii "One 60 KB read (file offset 64 KB) into the whole page frame:\r\n$"
msg_page:  .ascii "  frame page $"
msg_ok:    .ascii "= Reads into the page frame are correct.\r\n$"
msg_bad:   .ascii "= Reads into the page frame are WRONG (DMA bypassing the EMS mapping?)\r\n$"
msg_efile: .ascii "Cannot open the file (default DATA\\LEV.ARK; give a file of >= 124 KB).\r\n$"
msg_emem:  .ascii "Not enough memory.\r\n$"
msg_eems:  .ascii "EMS error (no EMS driver, or no free pages).\r\n$"
msg_eread: .ascii "Read error (file shorter than 124 KB?).\r\n$"
defname:   .asciz "DATA\\LEV.ARK"
fname:     .word 0
handle:    .word 0
bufseg:    .word 0
frame:     .word 0
emsh:      .word 0
diff:      .word 0
mark:      .word 0
total:     .word 0
