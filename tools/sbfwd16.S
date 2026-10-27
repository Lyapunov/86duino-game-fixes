# SBFWD16.COM - lets SBEMU hear a 16-bit protected-mode game (Borland Pascal
# RTM, ...) running under HDPMI16i.
#
# SBEMU catches protected-mode sound card I/O only through its own HDPMI32i,
# which serves 32-bit DPMI clients only. A 16-bit client needs HDPMI16i, whose
# port traps SBEMU knows nothing about. SBFWD16 becomes a 16-bit client of
# HDPMI16i, traps the ports SBEMU emulates (DMA, PIC, Sound Blaster, OPL, MPU)
# with the HDPMI vendor API (function 6), and runs the game as its child. Every
# trapped IN/OUT is replayed in real mode (DPMI 0301h), where JEMMEX + QPIEMU
# hand it to SBEMU's real-mode emulation. When the game ends, the traps go.
#
# usage: SBFWD16 PROGRAM.EXE [arguments]      (full file name, with extension)
# Needs: HDPMI16i resident (HDPMI16X.EXE when SBEMU's HDPMI32i is loaded).
# String I/O (INS/OUTS) is not forwarded, only counted.
# Build: python3 dosbuild.py sbfwd16.S (GNU binutils).
        .code16
        .globl _start
_start: jmp   init

        .ascii "SBFWD16"
dsel:   .word 0                         # our data selector (read via CS in the handlers)
rmseg:  .word 0                         # our real-mode segment
api:    .word 0, 0                      # HDPMI vendor API entry
fwdcnt: .long 0                         # IN/OUT forwarded
outcnt: .long 0                         # of which OUT
strcnt: .long 0                         # string I/O skipped

# DPMI real-mode call structure (int 31h, ax=0301h)
rmregs:
rm_edi: .long 0
rm_esi: .long 0
rm_ebp: .long 0
        .long 0
rm_ebx: .long 0
rm_edx: .long 0
rm_ecx: .long 0
rm_eax: .long 0
rm_fl:  .word 0
rm_es:  .word 0
rm_ds:  .word 0
rm_fs:  .word 0
rm_gs:  .word 0
rm_ip:  .word 0
rm_cs:  .word 0
rm_sp:  .word 0
rm_ss:  .word 0

# ---- trap handlers, called by HDPMI16i like exception handlers:
# [bp+2] ret IP, [bp+4] ret CS, [bp+6] error code, [bp+8] IP, [bp+10] CS ...
# error code: bits 0-2 instruction size, bit 3 string, bits 4-5 size
# (00 byte, 01 word, 11 dword), bit 6 port in bits 8-15 (else in DX).
trap_in:
        push  %bp
        mov   %sp, %bp
        push  %ds
        push  %es
        pushal
        mov   %cs:dsel, %ds
        xor   %bl, %bl                  # 0 = IN
        jmp   common
trap_out:
        push  %bp
        mov   %sp, %bp
        push  %ds
        push  %es
        pushal
        mov   %cs:dsel, %ds
        mov   $1, %bl                   # 1 = OUT
common:
        mov   %sp, %di                  # SS:DI -> saved client registers (pushal)
        mov   6(%bp), %cx
        test  $0x08, %cl
        jnz   is_string
        mov   %ss:20(%di), %dx          # client DX
        test  $0x40, %cl
        jz    1f
        movzbw %ch, %dx                 # port from the instruction
1:      movzwl %dx, %edx
        mov   %edx, rm_edx
        mov   %ss:28(%di), %eax         # client EAX
        mov   %eax, rm_eax
        mov   %cl, %al
        and   $0x30, %al
        or    %bl, %al
        movzbl %al, %eax
        mov   %eax, rm_ebx
        movw  $0, rm_fl
        movw  $rmstub, rm_ip
        mov   rmseg, %ax
        mov   %ax, rm_cs
        movw  $0, rm_sp
        movw  $0, rm_ss
        push  %ds
        pop   %es
        mov   $rmregs, %di
        mov   $0x0301, %ax
        xor   %bx, %bx
        xor   %cx, %cx
        int   $0x31
        mov   %sp, %di
        addl  $1, fwdcnt
        testb $1, rm_ebx
        jz    1f
        addl  $1, outcnt
        jmp   done                      # OUT: nothing to return
1:
        mov   6(%bp), %cx
        test  $0x30, %cl
        jnz   2f
        mov   rm_eax, %al
        mov   %al, %ss:28(%di)
        jmp   done
2:      test  $0x20, %cl
        jnz   3f
        mov   rm_eax, %ax
        mov   %ax, %ss:28(%di)
        jmp   done
3:      mov   rm_eax, %eax
        mov   %eax, %ss:28(%di)
        jmp   done
is_string:
        addl  $1, strcnt
done:   mov   6(%bp), %ax
        and   $7, %ax
        add   %ax, 8(%bp)               # skip the instruction
        popal
        pop   %es
        pop   %ds
        pop   %bp
        lret

# ---- real mode: do the I/O (BL bit 0 = OUT, bits 4-5 = size), QPIEMU traps it
rmstub: test  $1, %bl
        jnz   1f
        test  $0x20, %bl
        jnz   2f
        test  $0x10, %bl
        jnz   3f
        in    %dx, %al
        lret
3:      in    %dx, %ax
        lret
2:      in    %dx, %eax
        lret
1:      test  $0x20, %bl
        jnz   4f
        test  $0x10, %bl
        jnz   5f
        out   %al, %dx
        lret
5:      out   %ax, %dx
        lret
4:      out   %eax, %dx
        lret

trapprocs:
tp_in:  .word trap_in, 0
tp_out: .word trap_out, 0

# port ranges: start, count, handle
ranges: .word 0x0000, 16
        .long 0
        .word 0x0020, 2                 # master PIC (SBEMU's virtual IRQ)
        .long 0
        .word 0x0081, 15                # DMA page registers
        .long 0
        .word 0x00A0, 2                 # slave PIC
        .long 0
        .word 0x00C0, 32                # 16-bit DMA
        .long 0
        .word 0x0220, 16                # Sound Blaster
        .long 0
        .word 0x0330, 2                 # MPU-401
        .long 0
        .word 0x0388, 4                 # OPL
        .long 0
        .word 0, 0

hdpmistr: .asciz "HDPMI"
dpmient:  .word 0, 0
exitcode: .byte 0
pblock:   .word 0                       # environment: inherit
pb_tail:  .word childtail, 0
pb_fcb1:  .word fcb, 0
pb_fcb2:  .word fcb, 0
fcb:      .fill 37, 1, 0
progname: .fill 80, 1, 0
childtail: .fill 130, 1, 0

m_usage:  .ascii "usage: SBFWD16 PROGRAM.EXE [arguments]\r\n"
          .ascii "Runs a 16-bit protected-mode game under HDPMI16i so that SBEMU hears its sound.\r\n$"
m_nodpmi: .ascii "SBFWD16: no DPMI host (load HDPMI16X.EXE first)\r\n$"
m_mem:    .ascii "SBFWD16: out of DOS memory\r\n$"
m_switch: .ascii "SBFWD16: switch to protected mode failed (is HDPMI16i loaded?)\r\n$"
m_vendor: .ascii "SBFWD16: no HDPMI vendor API (needs HDPMI16i)\r\n$"
m_trap:   .ascii "SBFWD16: cannot trap ports (HDPMI16i, not HDPMI16?)\r\n$"
m_exec:   .ascii "SBFWD16: cannot run the program\r\n$"
m_stat1:  .ascii "SBFWD16: $"
m_stat2:  .ascii " port accesses forwarded (OUT: $"
m_stat2b: .ascii "), $"
m_stat3:  .ascii " string I/O skipped\r\n$"

# ---- print the unsigned number in EAX (DS = our data)
printnum:
        mov   $numbuf+10, %di
        movb  $'$', (%di)
        mov   $10, %ecx
1:      xor   %edx, %edx
        div   %ecx
        add   $'0', %dl
        dec   %di
        mov   %dl, (%di)
        test  %eax, %eax
        jnz   1b
        mov   %di, %dx
        mov   $9, %ah
        int   $0x21
        ret
numbuf: .fill 11, 1, 0

puts:   mov   $9, %ah
        int   $0x21
        ret

# ---- start (real mode)
init:   mov   $stacktop, %sp
        mov   %cs, rmseg
# parse "PROGRAM rest" from the command tail
        mov   $0x81, %si
        movzbw 0x80, %cx
        add   %si, %cx                  # CX = end of tail
1:      cmp   %cx, %si
        jae   usage
        cmpb  $' ', (%si)
        jne   2f
        inc   %si
        jmp   1b
2:      mov   $progname, %di
3:      cmp   %cx, %si
        jae   4f
        mov   (%si), %al
        cmp   $' ', %al
        je    4f
        cmp   $0x0d, %al
        je    4f
        mov   %al, (%di)
        inc   %si
        inc   %di
        jmp   3b
4:      movb  $0, (%di)
        mov   $childtail+1, %di
5:      cmp   %cx, %si
        jae   6f
        mov   (%si), %al
        cmp   $0x0d, %al
        je    6f
        mov   %al, (%di)
        inc   %si
        inc   %di
        jmp   5b
6:      movb  $0x0d, (%di)
        mov   %di, %ax
        sub   $childtail+1, %ax
        mov   %al, childtail
# give back the memory we don't need (the game needs it)
        mov   $end_all, %bx
        add   $15, %bx
        shr   $4, %bx
        mov   $0x4a, %ah
        int   $0x21
# enter protected mode as a 16-bit client
        mov   $0x1687, %ax
        int   $0x2f
        test  %ax, %ax
        jnz   e_nodpmi
        mov   %di, dpmient
        mov   %es, dpmient+2
        test  %si, %si
        jz    7f
        mov   %si, %bx
        mov   $0x48, %ah
        int   $0x21
        jc    e_mem
        mov   %ax, %es
7:      xor   %ax, %ax
        lcall *dpmient
        jc    e_switch
# ---- protected mode
        mov   %ds, dsel
        mov   $hdpmistr, %si
        mov   $0x168a, %ax
        int   $0x2f
        cmp   $0, %al
        jne   e_vendor
        mov   %di, api
        mov   %es, api+2
        mov   %cs, tp_in+2
        mov   %cs, tp_out+2
        mov   $ranges, %bx
8:      mov   (%bx), %dx
        mov   2(%bx), %cx
        jcxz  9f
        push  %bx
        mov   $trapprocs, %si
        mov   $6, %ax
        lcall *api
        pop   %bx
        jc    e_trap
        mov   %eax, 4(%bx)
        add   $8, %bx
        jmp   8b
# run the game
9:      mov   %ds, pb_tail+2
        mov   %ds, pb_fcb1+2
        mov   %ds, pb_fcb2+2
        push  %ds
        pop   %es
        mov   $pblock, %bx
        mov   $progname, %dx
        mov   $0x4b00, %ax
        int   $0x21
        jc    e_exec
        mov   $0x4d, %ah
        int   $0x21
        mov   %al, exitcode
        jmp   untrap
e_exec: mov   $m_exec, %dx
        call  puts
        movb  $1, exitcode
untrap: mov   $ranges, %bx
10:     cmpw  $0, 2(%bx)
        je    11f
        mov   4(%bx), %edx
        test  %edx, %edx
        jz    12f
        push  %bx
        mov   $7, %ax
        lcall *api
        pop   %bx
12:     add   $8, %bx
        jmp   10b
11:     mov   $3, %ax                   # text mode, in case the game left graphics on
        int   $0x10
        mov   $m_stat1, %dx
        call  puts
        mov   fwdcnt, %eax
        call  printnum
        mov   $m_stat2, %dx
        call  puts
        mov   outcnt, %eax
        call  printnum
        mov   $m_stat2b, %dx
        call  puts
        mov   strcnt, %eax
        call  printnum
        mov   $m_stat3, %dx
        call  puts
        mov   exitcode, %al
        mov   $0x4c, %ah
        int   $0x21

e_trap: mov   $m_trap, %dx
        call  puts
        movb  $1, exitcode
        jmp   untrap
e_vendor:
        mov   $m_vendor, %dx
        jmp   e_pm
e_pm:   call  puts
        mov   $0x4c01, %ax
        int   $0x21
usage:  mov   $m_usage, %dx
        jmp   e_rm
e_nodpmi:
        mov   $m_nodpmi, %dx
        jmp   e_rm
e_mem:  mov   $m_mem, %dx
        jmp   e_rm
e_switch:
        mov   $m_switch, %dx
e_rm:   call  puts
        mov   $0x4c01, %ax
        int   $0x21

        .p2align 4
stack:  .fill 1024, 1, 0
stacktop:
end_all:
