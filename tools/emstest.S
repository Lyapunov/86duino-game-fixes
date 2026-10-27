# EMSTEST.COM - does EMS memory really work through the page frame?
#
# Asks the EMS driver for its page frame, allocates 32 pages (512 KB), writes
# a different word pattern into every page through the frame (cycling over the
# 4 physical pages), then maps each page again and checks it. A page frame
# that sits on memory that isn't really free (a ROM, shadow or firmware area)
# shows up as errors here. Run as  EMSTEST > EMS.TXT  to keep the result.
# Build: python3 dosbuild.py emstest.S (GNU binutils).
        .code16
        .set npages, 32
        .globl _start
_start: mov   $msg_title, %dx
        call  puts
        mov   $0x46, %ah                # version
        int   $0x67
        test  %ah, %ah
        jnz   noems
        mov   %al, %bl
        mov   $msg_ver, %dx
        call  puts
        mov   %bl, %al
        shr   $4, %al
        add   $'0', %al
        call  putc
        mov   $'.', %al
        call  putc
        mov   %bl, %al
        and   $15, %al
        add   $'0', %al
        call  putc
        mov   $0x41, %ah                # page frame segment
        int   $0x67
        test  %ah, %ah
        jnz   fail
        mov   %bx, frame
        mov   $msg_frame, %dx
        call  puts
        mov   frame, %ax
        call  hexword
        mov   $0x42, %ah                # free / total pages
        int   $0x67
        mov   %bx, freep
        mov   %dx, totalp
        mov   $msg_free, %dx
        call  puts
        mov   freep, %ax
        call  decword
        mov   $msg_of, %dx
        call  puts
        mov   totalp, %ax
        call  decword
        mov   $msg_pages, %dx
        call  puts
        mov   $0x43, %ah                # allocate
        mov   $npages, %bx
        int   $0x67
        test  %ah, %ah
        jnz   fail
        mov   %dx, handle
        cld
# pass 1: write
        xor   %bp, %bp
1:      call  map
        jc    fail2
        call  pattern
2:      stosw
        add   $0x9e37, %ax
        loop  2b
        inc   %bp
        cmp   $npages, %bp
        jb    1b
# pass 2: check
        xor   %bp, %bp
3:      call  map
        jc    fail2
        call  pattern
4:      scasw
        je    5f
        cmpw  $0xffff, errs             # saturate
        je    5f
        incw  errs
        cmpw  $1, errs
        jne   5f
        mov   %bp, errpage
        lea   -2(%di), %si
        mov   %si, erroff
        mov   %es:(%si), %si
        mov   %si, errgot
        mov   %ax, errwant
5:      add   $0x9e37, %ax
        loop  4b
        inc   %bp
        cmp   $npages, %bp
        jb    3b
        call  free
        mov   $msg_errs, %dx
        call  puts
        mov   errs, %ax
        call  decword
        cmpw  $0, errs
        jne   6f
        mov   $msg_ok, %dx
        call  puts
        jmp   exit
6:      mov   $msg_bad, %dx
        call  puts
        mov   errpage, %ax
        call  decword
        mov   $msg_phys, %dx
        call  puts
        mov   errpage, %ax
        and   $3, %ax
        call  decword
        mov   $msg_off, %dx
        call  puts
        mov   erroff, %ax
        call  hexword
        mov   $msg_want, %dx
        call  puts
        mov   errwant, %ax
        call  hexword
        mov   $msg_got, %dx
        call  puts
        mov   errgot, %ax
        call  hexword
        mov   $msg_crlf, %dx
        call  puts
        jmp   exit

# map: logical page bp -> physical page bp&3; es:di = start of it, cx = 8192 words
map:    mov   %bp, %bx
        mov   %bp, %ax
        and   $3, %al
        push  %ax
        mov   $0x44, %ah
        mov   handle, %dx
        int   $0x67
        pop   %bx
        test  %ah, %ah
        jnz   1f
        mov   frame, %ax
        mov   %bl, %bh
        xor   %bl, %bl
        shl   $2, %bh                   # 16 KB = 0x400 paragraphs per physical page
        add   %bx, %ax
        mov   %ax, %es
        xor   %di, %di
        mov   $8192, %cx
        clc
        ret
1:      stc
        ret

# pattern: ax = first word for logical page bp
pattern: mov  %bp, %ax
        imul  $0x5bd1, %ax, %ax
        xor   $0xa5c3, %ax
        ret

free:   mov   $0x45, %ah
        mov   handle, %dx
        int   $0x67
        ret

noems:  mov   $msg_noems, %dx
        call  puts
        jmp   exit
fail2:  call  free
fail:   push  %ax
        mov   $msg_fail, %dx
        call  puts
        pop   %ax
        mov   %ah, %al
        call  hexbyte
        mov   $msg_crlf, %dx
        call  puts
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

msg_title: .ascii "EMSTEST: EMS through the page frame (32 pages written, then checked)\r\n$"
msg_ver:   .ascii "EMS version $"
msg_frame: .ascii ", page frame at segment $"
msg_free:  .ascii "h\r\nFree pages: $"
msg_of:    .ascii " of $"
msg_pages: .ascii "\r\n$"
msg_errs:  .ascii "Words wrong: $"
msg_ok:    .ascii " = EMS works\r\n$"
msg_bad:   .ascii " = EMS BROKEN. First error in logical page $"
msg_phys:  .ascii ", physical page $"
msg_off:   .ascii ", offset $"
msg_want:  .ascii "h: wrote $"
msg_got:   .ascii "h, read back $"
msg_noems: .ascii "No EMS driver found.\r\n$"
msg_fail:  .ascii "EMS call failed, error $"
msg_crlf:  .ascii "h\r\n$"
frame:     .word 0
freep:     .word 0
totalp:    .word 0
handle:    .word 0
errs:      .word 0
errpage:   .word 0
erroff:    .word 0
errwant:   .word 0
errgot:    .word 0
