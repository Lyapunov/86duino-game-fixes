# CRCLIST.COM - name, size and CRC-32 (the zip/PNG one) of every file in the
# current directory, to compare a copy of a game with a known-good one.
#   usage: CRCLIST [pattern]     default *.*      e.g.  CRCLIST > C:\LIST.TXT
# Needs a 386 (32-bit registers). Build: python3 dosbuild.py crclist.S (GNU binutils).
        .code16
        .set bufsz, 0x8000
        .globl _start
_start: mov   $0x80, %si                # pattern from the command line
        mov   (%si), %cl
        xor   %ch, %ch
        inc   %si
1:      jcxz  2f
        cmpb  $' ', (%si)
        jne   3f
        inc   %si
        dec   %cx
        jmp   1b
2:      mov   $defpat, %dx
        jmp   4f
3:      mov   %si, %dx
        add   %cx, %si
        movb  $0, (%si)
4:      mov   %dx, pat
        mov   $0x4a, %ah                # shrink to 64 KB, get a 32 KB buffer
        mov   $0x1000, %bx
        push  %cs
        pop   %es
        int   $0x21
        mov   $0x48, %ah
        mov   $bufsz/16, %bx
        int   $0x21
        jc    nomem
        mov   %ax, bufseg
        mov   $0x1a, %ah                # our own DTA
        mov   $dta, %dx
        int   $0x21
        mov   $0x4e, %ah                # find first (normal files)
        xor   %cx, %cx
        mov   pat, %dx
        int   $0x21
        jc    done
next:   call  onefile
        mov   $0x4f, %ah
        int   $0x21
        jnc   next
done:   mov   $0x4c00, %ax
        int   $0x21
nomem:  mov   $msg_mem, %dx
        mov   $9, %ah
        int   $0x21
        jmp   done

# onefile: print "NAME.EXT     size  crc" for the file in the DTA
onefile: mov  $dta+30, %si              # name, padded to 13
        xor   %cx, %cx
1:      lodsb
        test  %al, %al
        jz    2f
        call  putc
        inc   %cx
        jmp   1b
2:      cmp   $13, %cx
        jae   3f
        mov   $' ', %al
        call  putc
        inc   %cx
        jmp   2b
3:      mov   dta+26, %eax              # size
        call  dec32
        mov   $' ', %al
        call  putc
        mov   $0x3d00, %ax              # CRC over the contents
        mov   $dta+30, %dx
        int   $0x21
        jc    9f
        mov   %ax, %bx
        mov   $0xffffffff, %edx
4:      push  %ds
        push  %dx
        mov   $0x3f, %ah
        mov   $bufsz, %cx
        mov   bufseg, %ds
        xor   %dx, %dx
        int   $0x21
        pop   %dx
        pop   %ds
        jc    8f
        test  %ax, %ax
        jz    7f
        mov   %ax, %cx
        push  %ds
        mov   bufseg, %ds
        xor   %si, %si
5:      lodsb                           # bitwise CRC-32, poly EDB88320
        xor   %al, %dl
        push  %cx
        mov   $8, %cx
6:      shr   $1, %edx
        jnc   61f
        xor   $0xedb88320, %edx
61:     loop  6b
        pop   %cx
        loop  5b
        pop   %ds
        jmp   4b
7:      not   %edx
        mov   %edx, %eax
        call  hex32
8:      mov   $0x3e, %ah
        int   $0x21
9:      mov   $msg_crlf, %dx
        mov   $9, %ah
        int   $0x21
        ret

dec32:  mov   $10, %ebx                 # eax decimal, right-aligned in 8
        xor   %cx, %cx
1:      xor   %edx, %edx
        div   %ebx
        push  %dx
        inc   %cx
        test  %eax, %eax
        jnz   1b
        mov   %cx, %bx
2:      cmp   $8, %bx
        jae   3f
        mov   $' ', %al
        call  putc
        inc   %bx
        jmp   2b
3:      pop   %ax
        add   $'0', %al
        call  putc
        loop  3b
        ret
hex32:  mov   $8, %cx
1:      rol   $4, %eax
        push  %eax
        and   $15, %al
        add   $'0', %al
        cmp   $'9', %al
        jbe   2f
        add   $7, %al
2:      call  putc
        pop   %eax
        loop  1b
        ret
putc:   push  %ax
        push  %dx
        mov   %al, %dl
        mov   $2, %ah
        int   $0x21
        pop   %dx
        pop   %ax
        ret

msg_crlf: .ascii "\r\n$"
msg_mem:  .ascii "Not enough memory.\r\n$"
defpat:   .asciz "*.*"
pat:      .word 0
bufseg:   .word 0
dta:      .space 43
