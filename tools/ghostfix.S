# GHOSTFIX.COM - "Ghost Frame" fix: disk transfers to/from upper memory go
# through a buffer in conventional memory.
#
# On the 86Duino the BIOS moves disk data by DMA, i.e. to and from physical
# addresses. Under an EMS manager (JEMM386, EMM386) the EMS page frame (and any
# UMB) is remapped by the CPU's paging, so a disk read *into* the page frame
# lands in the RAM behind it ("the ghost"), and a write *from* it stores the
# ghost's contents. Games that load files straight into EMS (Ultima Underworld)
# then see garbage and save garbage.
#
# GHOSTFIX hooks INT 13h. Read/write calls (02h/03h CHS, 42h/43h LBA) whose
# buffer lies at or above linear A0000h are done one sector at a time through
# a 512-byte buffer in its own (conventional, unmapped) memory, copied by the
# CPU, which sees the EMS mapping. All other calls go straight to the BIOS.
# Load it before the game (AUTOEXEC.BAT is fine); about 1.8 KB resident.
# GHOSTFIX /U removes it again (unless another program has hooked INT 13h since).
# Build: python3 dosbuild.py ghostfix.S (GNU binutils).
        .code16
        .globl _start
_start: jmp   init

sig:    .ascii "GHOSTFIX"
old13:  .word 0, 0
bounced: .word 0                        # sectors moved through the buffer (diagnostics)
geodrv: .byte 0xff                      # drive whose geometry is cached
spt:    .byte 0                         # sectors per track
heads:  .byte 0                         # number of heads
lowbuf: .word 0                         # offset of the 512-byte buffer (512-aligned in memory)

# ---- INT 13h entry
int13:  cmp   $0x02, %ah
        je    chs
        cmp   $0x03, %ah
        je    chs
        cmp   $0x42, %ah
        je    lba
        cmp   $0x43, %ah
        je    lba
pass:   ljmp  *%cs:old13

# far call to the original handler (flags as if INT)
bios:   pushf
        lcall *%cs:old13
        ret

# high: dx:ax = linear address of seg:off in (es, bx); returns CF=1 if >= A0000h
# (and stays there for n bytes - we only test the start; a buffer that starts
# below A0000h and runs into it is impossible for DOS sector buffers)
islow:  push  %ax
        push  %dx
        mov   %es, %ax
        mov   $16, %dx
        mul   %dx                       # dx:ax = es*16
        add   %bx, %ax
        adc   $0, %dx
        cmp   $0x000a, %dx              # A0000h = 000A:0000
        pop   %dx
        pop   %ax
        ret                             # CF=1 (below) if dx < 0Ah

# ---- 02h/03h: AL sectors, CH/CL cylinder+sector, DH head, DL drive, ES:BX buffer
chs:    call  islow
        jc    pass                      # buffer below A0000h: untouched
        test  %al, %al
        jz    pass
        push  %bp
        push  %si
        push  %di
        push  %ds
        push  %es
        push  %bx
        push  %cx
        push  %dx
        mov   %sp, %bp
        push  %ax                       # [bp-2] = original AX
        call  geom
        jc    7f
        xor   %si, %si                  # si = sectors done
1:      mov   -2(%bp), %ax              # done all AL sectors?
        xor   %ah, %ah
        cmp   %ax, %si
        jae   6f
        mov   -2(%bp), %ax              # AH = 02h or 03h
        cmp   $0x03, %ah
        jne   2f
        call  tolow                     # write: user buffer -> lowbuf
2:      push  %es
        push  %bx
        push  %cs
        pop   %es
        mov   %cs:lowbuf, %bx
        mov   -2(%bp), %ax
        mov   $1, %al
        mov   0(%bp), %dx               # DH head, DL drive (current)
        mov   2(%bp), %cx               # CX cylinder/sector (current)
        call  bios
        pop   %bx
        pop   %es
        jc    8f
        mov   -2(%bp), %ax
        cmp   $0x02, %ah
        jne   3f
        call  fromlow                   # read: lowbuf -> user buffer
3:      incw  %cs:bounced
        inc   %si
        add   $512, %bx                 # next user address; renormalize
        jnc   4f
        mov   %es, %ax
        add   $0x1000, %ax
        mov   %ax, %es
4:      call  nextchs
        jmp   1b
6:      mov   -2(%bp), %ax              # success: AH=0, AL=count, CF=0
        xor   %ah, %ah
        add   $2, %sp
        clc
        jmp   9f
7:      pop   %ax                       # no geometry: let the BIOS try it directly
        pop   %dx
        pop   %cx
        pop   %bx
        pop   %es
        pop   %ds
        pop   %di
        pop   %si
        pop   %bp
        jmp   pass
8:      add   $2, %sp                   # error: AH = BIOS error, AL = sectors done
        mov   %si, %dx
        mov   %dl, %al
        stc
9:      pop   %dx
        pop   %cx
        pop   %bx
        pop   %es
        pop   %ds
        pop   %di
        pop   %si
        pop   %bp
        sti                             # (the INT cleared IF; the BIOS runs with it on too)
        retf  $2                        # return with our CF in the flags

# nextchs: advance the CHS in [bp+2] (CX) / [bp+1] (DH) by one sector
nextchs: mov  2(%bp), %cx
        mov   %cl, %al
        and   $0x3f, %al
        inc   %al
        cmp   %cs:spt, %al
        jbe   1f
        mov   $1, %al                   # sector 1 of the next head
        mov   1(%bp), %ah               # DH
        inc   %ah
        cmp   %cs:heads, %ah
        jb    2f
        xor   %ah, %ah                  # head 0 of the next cylinder
        push  %ax
        mov   %cl, %al                  # cylinder = CH | (CL & C0h) << 2
        shr   $6, %al
        mov   %al, %ah
        mov   %ch, %al
        inc   %ax
        mov   %al, %ch
        shl   $6, %ah
        and   $0x3f, %cl
        or    %ah, %cl
        pop   %ax
2:      mov   %ah, 1(%bp)
1:      and   $0xc0, %cl
        or    %al, %cl
        mov   %cx, 2(%bp)
        ret

# geom: cache spt/heads for drive [bp+0] (DL); CF on failure
geom:   mov   0(%bp), %dx
        cmp   %cs:geodrv, %dl
        je    1f
        push  %es
        push  %di
        push  %bx
        push  %cx
        mov   $0x08, %ah
        call  bios
        mov   %cl, %al
        pop   %cx
        pop   %bx
        pop   %di
        pop   %es
        jc    2f
        and   $0x3f, %al
        mov   %al, %cs:spt
        inc   %dh
        mov   %dh, %cs:heads
        mov   0(%bp), %dx
        mov   %dl, %cs:geodrv
1:      clc
2:      ret

# tolow / fromlow: copy 512 bytes between es:bx (user) and cs:lowbuf
tolow:  push  %ds
        push  %es
        push  %si
        push  %di
        push  %cx
        push  %es
        pop   %ds
        mov   %bx, %si
        push  %cs
        pop   %es
        mov   %cs:lowbuf, %di
        jmp   1f
fromlow: push %ds
        push  %es
        push  %si
        push  %di
        push  %cx
        push  %cs
        pop   %ds
        mov   lowbuf, %si
        mov   %bx, %di
1:      cld
        mov   $256, %cx
        rep   movsw
        pop   %cx
        pop   %di
        pop   %si
        pop   %es
        pop   %ds
        ret

# ---- 42h/43h: DS:SI -> DAP {size, 0, count, offset, segment, LBA(8)}
lba:    push  %es
        push  %bx
        les   4(%si), %bx               # DAP buffer (offset at +4, segment at +6)
        call  islow
        pop   %bx
        pop   %es
        jc    pass                      # buffer below A0000h: untouched
        cmpw  $0xffff, 4(%si)           # FFFF:FFFF = 64-bit flat buffer form
        jne   1f
        cmpw  $0xffff, 6(%si)
        je    pass
1:      push  %bp
        push  %di
        push  %es
        push  %bx
        push  %cx
        push  %dx
        push  %ax
        mov   %sp, %bp                  # [bp+0] = AX (AH 42h/43h), [bp+2] = DX (DL drive)
        les   4(%si), %bx               # es:bx = user buffer
        mov   2(%si), %cx               # sectors requested
        xor   %di, %di                  # sectors done
2:      cmp   %cx, %di
        jae   6f
        mov   0(%bp), %ax
        cmp   $0x43, %ah
        jne   3f
        call  tolow                     # write: user buffer -> lowbuf
3:      mov   8(%si), %ax               # our DAP: LBA + di (64-bit), 1 sector, lowbuf
        add   %di, %ax
        mov   %ax, %cs:mydap+8
        mov   10(%si), %ax
        adc   $0, %ax
        mov   %ax, %cs:mydap+10
        mov   12(%si), %ax
        adc   $0, %ax
        mov   %ax, %cs:mydap+12
        mov   14(%si), %ax
        adc   $0, %ax
        mov   %ax, %cs:mydap+14
        movw  $16, %cs:mydap
        movw  $1, %cs:mydap+2
        mov   %cs:lowbuf, %ax
        mov   %ax, %cs:mydap+4
        mov   %cs, %cs:mydap+6
        push  %ds
        push  %si
        push  %cs
        pop   %ds
        mov   $mydap, %si
        mov   0(%bp), %ax
        mov   2(%bp), %dx
        call  bios
        pop   %si
        pop   %ds
        jc    8f
        mov   0(%bp), %ax
        cmp   $0x42, %ah
        jne   4f
        call  fromlow                   # read: lowbuf -> user buffer
4:      incw  %cs:bounced
        inc   %di
        add   $512, %bx
        jnc   2b
        mov   %es, %ax
        add   $0x1000, %ax
        mov   %ax, %es
        jmp   2b
6:      pop   %ax                       # success: AH = 0, CF = 0
        xor   %ah, %ah
        clc
        jmp   9f
8:      add   $2, %sp                   # error: AH = BIOS error, DAP count = sectors done
        mov   %di, 2(%si)
        stc
9:      pop   %dx
        pop   %cx
        pop   %bx
        pop   %es
        pop   %di
        pop   %bp
        sti
        retf  $2

mydap:  .space 16
        .balign 16
bufarea: .space 1024                    # a 512-aligned 512-byte window lies in here
resend:

init:   mov   $0x81, %si                # "/U" or "-U" on the command line: uninstall
1:      lodsb
        cmp   $0x0d, %al
        je    2f
        cmp   $'/', %al
        je    3f
        cmp   $'-', %al
        jne   1b
3:      lodsb
        or    $0x20, %al
        cmp   $'u', %al
        je    uninst
        jmp   1b
2:      call  findres                   # already installed?
        jc    install
        mov   $msg_twice, %dx
        jmp   errout

# findres: is INT 13h pointing at a resident GHOSTFIX? -> NC, ES = its segment
findres: mov  $0x3513, %ax
        int   $0x21
        cmp   $int13, %bx
        jne   1f
        mov   $sig, %si
        mov   %si, %di
        mov   $8, %cx
        cld
        repe  cmpsb
        jne   1f
        clc
        ret
1:      stc
        ret

uninst: call  findres
        jnc   1f
        mov   $msg_notres, %dx
        jmp   errout
1:      push  %ds
        lds   %es:old13, %dx            # give INT 13h back to its previous owner
        mov   $0x2513, %ax
        int   $0x21
        pop   %ds
        push  %es
        mov   %es:0x2c, %ax             # free its environment, then the program itself
        mov   %ax, %es
        mov   $0x49, %ah
        int   $0x21
        pop   %es
        mov   $0x49, %ah
        int   $0x21
        mov   $msg_removed, %dx
        mov   $9, %ah
        int   $0x21
        mov   $0x4c00, %ax
        int   $0x21

errout: mov   $9, %ah
        int   $0x21
        mov   $0x4c01, %ax
        int   $0x21

install: mov  %cs, %ax                  # lowbuf = first 512-aligned linear address in bufarea
        mov   $16, %dx
        mul   %dx
        add   $bufarea, %ax
        adc   $0, %dx
        mov   %ax, %cx
        add   $511, %ax
        and   $0xfe00, %ax
        sub   %cx, %ax                  # bytes to skip
        add   $bufarea, %ax
        mov   %ax, lowbuf
        mov   $0x3513, %ax
        int   $0x21
        mov   %bx, old13
        mov   %es, old13+2
        mov   $0x2513, %ax
        mov   $int13, %dx
        int   $0x21
        mov   $msg, %dx
        mov   $9, %ah
        int   $0x21
        mov   $resend+15, %dx
        shr   $4, %dx
        mov   $0x3100, %ax
        int   $0x21

msg:    .ascii "GHOSTFIX installed: disk transfers to/from upper memory go through low memory.\r\n$"
msg_twice: .ascii "GHOSTFIX is already installed.\r\n$"
msg_notres: .ascii "GHOSTFIX is not installed, or another program has hooked INT 13h after it.\r\n$"
msg_removed: .ascii "GHOSTFIX removed from memory.\r\n$"
