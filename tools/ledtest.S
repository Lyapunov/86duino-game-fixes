# LEDTEST.COM - does this machine's keyboard controller answer the "set LEDs"
# command (EDh) the way 1990s games expect?
#
# It does exactly what Ultima Underworld's keyboard setup does, with interrupts
# off: wait until the controller can take a byte (64h bit 1 = 0), send EDh to
# port 60h, wait for the answer (64h bit 0 = 1), read it from 60h (should be
# FAh, ACK), then the same for the LED byte. Unlike the game, every wait gives
# up after a fixed number of polls, so the program always comes back.
# Run as  LEDTEST > LED.TXT  to keep the result.
# Needs a 386 (32-bit poll counters). Build: python3 dosbuild.py ledtest.S (GNU binutils).
        .code16
        .set limit, 2000000             # polls per wait before giving up
        .globl _start
_start: mov   $msg_title, %dx
        call  puts
        in    $0x64, %al
        mov   %al, st0
        mov   $0x40, %ax                # LED byte = BIOS lock flags (0:0417 bits 4-6)
        mov   %ax, %es
        mov   %es:0x17, %al
        shr   $4, %al
        and   $7, %al
        mov   %al, ledbyte
        cli
        mov   $0xed, %bl
        mov   $res1, %di
        call  send
        mov   ledbyte, %bl
        mov   $res2, %di
        call  send
        sti
# report
        mov   $msg_st0, %dx
        call  puts
        mov   st0, %al
        call  hexbyte
        mov   $msg_led, %dx
        call  puts
        mov   ledbyte, %al
        call  hexbyte
        mov   $msg_cmd1, %dx
        call  puts
        mov   $res1, %si
        call  report
        mov   $msg_cmd2, %dx
        call  puts
        mov   $res2, %si
        call  report
        mov   $msg_end, %dx
        call  puts
        mov   $0x4c00, %ax
        int   $0x21

# send: bl = byte for port 60h, di = result record
# record: +0 dword polls until 64h bit 1 = 0 (-1 = timeout)
#         +4 dword polls until 64h bit 0 = 1 (-1 = timeout)
#         +8 byte  status at that moment, +9 byte read from 60h
send:   xor   %ecx, %ecx
1:      in    $0x64, %al
        test  $2, %al
        jz    2f
        inc   %ecx
        cmp   $limit, %ecx
        jb    1b
        movl  $-1, (%di)
        movl  $-1, 4(%di)
        ret
2:      mov   %ecx, (%di)
        mov   %bl, %al
        out   %al, $0x60
        xor   %ecx, %ecx
3:      in    $0x64, %al
        test  $1, %al
        jnz   4f
        inc   %ecx
        cmp   $limit, %ecx
        jb    3b
        movl  $-1, 4(%di)
        mov   %al, 8(%di)
        ret
4:      mov   %ecx, 4(%di)
        mov   %al, 8(%di)
        in    $0x60, %al
        mov   %al, 9(%di)
        ret

# report: si = result record
report: mov   $msg_ibf, %dx
        call  puts
        mov   (%si), %eax
        call  count
        mov   $msg_obf, %dx
        call  puts
        mov   4(%si), %eax
        call  count
        cmpl  $-1, 4(%si)
        je    1f
        mov   $msg_got, %dx
        call  puts
        mov   9(%si), %al
        call  hexbyte
        mov   $msg_stat, %dx
        call  puts
        mov   8(%si), %al
        call  hexbyte
        mov   $msg_close, %dx
        call  puts
        mov   9(%si), %al
        mov   $msg_ack, %dx
        cmp   $0xfa, %al
        je    2f
        mov   $msg_noack, %dx
2:      call  puts
1:      ret

# count: eax = polls or -1 -> prints "TIMEOUT" or the decimal number
count:  cmp   $-1, %eax
        jne   1f
        mov   $msg_to, %dx
        jmp   puts
1:      mov   $10, %ebx
        xor   %cx, %cx
2:      xor   %edx, %edx
        div   %ebx
        push  %dx
        inc   %cx
        test  %eax, %eax
        jnz   2b
3:      pop   %dx
        add   $'0', %dl
        mov   $2, %ah
        int   $0x21
        loop  3b
        mov   $msg_polls, %dx
        jmp   puts

hexbyte: push %ax
        shr   $4, %al
        call  1f
        pop   %ax
1:      and   $15, %al
        add   $'0', %al
        cmp   $'9', %al
        jbe   2f
        add   $7, %al
2:      mov   %al, %dl
        mov   $2, %ah
        int   $0x21
        ret

puts:   mov   $9, %ah
        int   $0x21
        ret

msg_title: .ascii "LEDTEST: keyboard 'set LEDs' (EDh) handshake, as Ultima Underworld does it\r\n$"
msg_st0:   .ascii "Status 64h before: $"
msg_led:   .ascii "h   LED byte: $"
msg_cmd1:  .ascii "h\r\nCommand EDh:\r\n$"
msg_cmd2:  .ascii "LED byte:\r\n$"
msg_ibf:   .ascii "  wait for 'ready for input' (64h bit 1 = 0): $"
msg_obf:   .ascii "  wait for an answer (64h bit 0 = 1):        $"
msg_got:   .ascii "  answer: $"
msg_stat:  .ascii "h (status $"
msg_close: .ascii "h) $"
msg_ack:   .ascii "= ACK, as expected\r\n$"
msg_noack: .ascii "= NOT the expected ACK (FAh)\r\n$"
msg_to:    .ascii "TIMEOUT (a game without a time limit hangs here)\r\n$"
msg_polls: .ascii " polls\r\n$"
msg_end:   .ascii "Done.\r\n$"
st0:       .byte 0
ledbyte:   .byte 0
res1:      .space 10
res2:      .space 10
