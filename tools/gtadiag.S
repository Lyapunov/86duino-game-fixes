# GTADIAG.COM - print (and with "Z" zero) the SBDIAG.DIG counters kept at 0000:04F0.
#   GTADIAG Z     zero the counters (run before GTA)
#   GTADIAG       print them (run after quitting GTA)
        .code16
        .text
        .globl _start
_start:
        xor     %ax, %ax
        mov     %ax, %es
        mov     0x80, %cl               # command tail: look for Z/z
        xor     %ch, %ch
        mov     $0x81, %si
1:      jcxz    show
        lodsb
        dec     %cx
        or      $0x20, %al
        cmp     $'z', %al
        jne     1b
        xor     %ax, %ax
        mov     $0x4f0, %di
        mov     $8, %cx
        rep stosw
        mov     $msg_zero, %dx
        call    puts
        jmp     done
show:
        mov     $msg_isr, %dx
        call    puts
        mov     %es:0x4f2, %ax
        call    dec32hi
        mov     $msg_flip, %dx
        call    puts
        mov     %es:0x4f6, %ax
        mov     %es:0x4f4, %bx
        call    dec32
        mov     $msg_start, %dx
        call    puts
        mov     %es:0x4fa, %ax
        mov     %es:0x4f8, %bx
        call    dec32
        mov     $msg_imr, %dx
        call    puts
        mov     %es:0x4fc, %al
        call    hex2
        mov     $msg_now, %dx
        call    puts
        in      $0x21, %al
        call    hex2
        mov     $crlf, %dx
        call    puts
done:   mov     $0x4c00, %ax
        int     $0x21

dec32hi: mov    %es:0x4f0, %bx          # ax:bx = 32-bit value -> decimal
dec32:  mov     %ax, %dx
        mov     %bx, %ax
        mov     $10, %cx
        xor     %bp, %bp                # digit count
2:      push    %ax                     # divide dx:ax by 10 (two steps)
        mov     %dx, %ax
        xor     %dx, %dx
        div     %cx
        mov     %ax, %bx                # high quotient
        pop     %ax
        div     %cx                     # dx = remainder
        push    %dx
        inc     %bp
        mov     %bx, %dx
        mov     %ax, %bx
        or      %dx, %bx
        jnz     2b
3:      pop     %dx
        add     $'0', %dl
        mov     $2, %ah
        int     $0x21
        dec     %bp
        jnz     3b
        ret

puts:   mov     $9, %ah
        int     $0x21
        ret
hex2:   push    %ax
        shr     $4, %al
        call    hex1
        pop     %ax
hex1:   and     $0x0f, %al
        add     $'0', %al
        cmp     $'9', %al
        jbe     4f
        add     $7, %al
4:      mov     %al, %dl
        mov     $2, %ah
        int     $0x21
        ret

msg_zero:  .ascii "GTADIAG: counters zeroed.\r\n$"
msg_isr:   .ascii "GTADIAG (SBDIAG.DIG counters)\r\n  IRQ handler calls:  $"
msg_flip:  .ascii "\r\n  half-buffer flips: $"
msg_start: .ascii "\r\n  playback starts:   $"
msg_imr:   .ascii "\r\n  PIC mask (21h) at last start: $"
msg_now:   .ascii "h, now: $"
crlf:      .ascii "h\r\n$"
