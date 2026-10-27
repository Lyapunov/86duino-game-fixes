# WHERE.COM 3 - where is the CPU when a game hangs, and what did it last print?
#
# A small TSR. It programs the real-time clock's periodic interrupt (IRQ 8,
# INT 70h, 16 Hz), which games almost never touch, and records the CS:IP and
# FLAGS that each interrupt lands on. It also hooks INT 10h (teletype, AH=0Eh;
# DOS console output ends up there too) and keeps the last 512 characters
# printed, because a game in a graphics mode can print an error message that
# nobody can see. Twice a second it shows, at the top left of the screen:
#   line 1   N=NNNN P=PPPP F=FFFF  sample counter, current DOS PSP, last FLAGS
#   line 2-5 CCCC:IIII BBBBBBBBBBBB  the last four interrupted addresses, newest
#            first, with the 6 bytes found there
#   line 6-15 the last 400 characters printed, 40 per line ('|' = line feed)
# In text modes it writes characters; in 320x200x256 (chained or unchained)
# it draws its own 3x5 font, scaled 2x, with palette colours 254/255 forced to
# dark red / white, redrawing only the characters that changed (all of them
# every 4 s). If the counter stops, interrupts are off (cli hang).
# The PSP is read from DOS's swappable data area: no DOS call in the ISR.
# A program's own address = (CS - (PSP + 10h)) * 16 + IP: the offset in its
# load image (file offset minus the MZ header size).
# Run WHERE once, then the game. Not removable; reboot afterwards.
# Build: python3 dosbuild.py where.S (GNU binutils).
        .code16
        .globl _start
_start: jmp   init

old70:  .word 0, 0
old10:  .word 0, 0
count:  .word 0
flags:  .word 0
samp:   .word 0,0, 0,0, 0,0, 0,0        # CS,IP pairs, newest first
cap:    .space 512                      # ring buffer of printed characters
capi:   .word 0                         # next write position
buf:    .space 40                       # one line of text

# INT 10h: keep teletype characters, then the BIOS
int10:  cmp   $0x0e, %ah
        jne   1f
        call  keep
1:      ljmp  *%cs:old10
# keep: al = character -> ring buffer (CR dropped, LF as '|', others below 20h dropped)
keep:   push  %bx
        cmp   $0x0d, %al
        je    9f
        mov   %al, %bl
        cmp   $0x0a, %al
        jne   1f
        mov   $'|', %bl
1:      cmp   $0x20, %bl
        jb    9f
        push  %si
        mov   %cs:capi, %si
        mov   %bl, %cs:cap(%si)
        inc   %si
        and   $511, %si
        mov   %si, %cs:capi
        pop   %si
9:      pop   %bx
        ret

# INT 70h: RTC interrupt
isr:    push  %ax
        push  %bx
        push  %cx
        push  %dx
        push  %si
        push  %di
        push  %bp
        push  %ds
        push  %es
        mov   %sp, %bp
        push  %cs
        pop   %ds
        mov   $0x0c, %al                # read RTC register C: acknowledges the interrupt
        out   %al, $0x70
        in    $0x71, %al
        test  $0x40, %al                # periodic?
        jz    9f
        incw  count
        mov   $samp+10, %si             # shift the history by one entry
        mov   $samp+14, %di
        std
        push  %cs
        pop   %es
        mov   $6, %cx
        rep   movsw
        cld
        mov   20(%bp), %ax              # interrupted CS
        mov   %ax, samp
        mov   18(%bp), %ax              # interrupted IP
        mov   %ax, samp+2
        mov   22(%bp), %ax              # interrupted FLAGS
        mov   %ax, flags
        testb $7, count
        jnz   9f
        call  show
9:      mov   $0x20, %al
        out   %al, $0xa0
        out   %al, $0x20
        pop   %es
        pop   %ds
        pop   %bp
        pop   %di
        pop   %si
        pop   %dx
        pop   %cx
        pop   %bx
        pop   %ax
        iret

# show: draw the fifteen lines
show:   incw  shows
        les   sda, %bx                  # current PSP = word at SDA+10h
        mov   %es:0x10(%bx), %ax
        mov   %ax, psp
        push  %ds
        pop   %es
        mov   $buf, %di                 # line 0: "N=NNNN P=PPPP F=FFFF"
        mov   $'N', %al
        call  label
        mov   count, %ax
        call  hex4
        mov   $'P', %al
        call  label2
        mov   psp, %ax
        call  hex4
        mov   $'F', %al
        call  label2
        mov   flags, %ax
        call  hex4
        xor   %dx, %dx
        call  line
        mov   $samp, %si                # lines 1-4: samples + 6 code bytes
        mov   $1, %dx
1:      push  %ds
        pop   %es
        mov   $buf, %di
        mov   (%si), %ax
        call  hex4
        mov   $':', %al
        stosb
        mov   2(%si), %ax
        call  hex4
        mov   $' ', %al
        stosb
        push  %si
        push  %ds
        mov   2(%si), %bx               # sampled IP
        mov   (%si), %ds                # sampled CS
        mov   $6, %cx
2:      mov   (%bx), %al
        push  %cx
        call  hex2
        pop   %cx
        inc   %bx
        loop  2b
        pop   %ds
        pop   %si
        push  %si
        push  %dx
        call  line
        pop   %dx
        pop   %si
        add   $4, %si
        inc   %dx
        cmp   $5, %dx
        jb    1b
        mov   capi, %si                 # lines 5-14: the last 400 printed characters
        sub   $400, %si
        and   $511, %si
        mov   $5, %dx
3:      push  %ds
        pop   %es
        mov   $buf, %di
        mov   $40, %cx
4:      mov   cap(%si), %al
        test  %al, %al
        jnz   5f
        mov   $' ', %al
5:      stosb
        inc   %si
        and   $511, %si
        loop  4b
        push  %si
        push  %dx
        call  line
        pop   %dx
        pop   %si
        inc   %dx
        cmp   $15, %dx
        jb    3b
        ret

label2: push  %ax
        mov   $' ', %al
        stosb
        pop   %ax
label:  stosb
        mov   $'=', %al
        stosb
        ret

# hex4: ax -> 4 hex chars at es:di; hex2: al -> 2 hex chars
hex4:   push  %ax
        mov   %ah, %al
        call  hex2
        pop   %ax
hex2:   push  %ax
        shr   $4, %al
        call  1f
        pop   %ax
1:      and   $15, %al
        add   $'0', %al
        cmp   $'9', %al
        jbe   2f
        add   $7, %al
2:      stosb
        ret

# line: draw buf[0..di) as screen line dx
line:   mov   %di, %cx
        sub   $buf, %cx                 # cx = length
        xor   %ax, %ax
        mov   %ax, %es
        mov   %es:0x449, %al            # BIOS video mode
        cmp   $3, %al
        jbe   txt
        cmp   $7, %al
        je    mono
        cmp   $0x13, %al
        je    gfx
        ret
mono:   mov   $0xb000, %ax
        jmp   1f
txt:    mov   $0xb800, %ax
1:      mov   %ax, %es
        mov   %dx, %ax                  # row dx, column 0 (80 columns)
        mov   $160, %bx
        mul   %bx
        mov   %ax, %di
        mov   $buf, %si
2:      lodsb
        mov   $0x4f, %ah                # white on red
        stosw
        loop  2b
        ret

# gfx: 320x200x256. Glyphs 3x5 scaled 2x in 8x12 cells; line dx at y = 12*dx.
gfx:    push  %cx
        mov   %dl, %al                  # shadow line = shadow + 40 * line
        mov   $40, %ah
        mul   %ah
        add   $shadow, %ax
        mov   %ax, shline
        mov   %dl, %al                  # ybase = 12 * line
        mov   $12, %ah
        mul   %ah
        mov   %ax, ybase
        call  vsave
        mov   $0x3c8, %dx               # palette 254 = dark red, 255 = white
        mov   $254, %al
        out   %al, %dx
        inc   %dx
        mov   $40, %al
        out   %al, %dx
        xor   %al, %al
        out   %al, %dx
        out   %al, %dx
        mov   $63, %al
        out   %al, %dx
        out   %al, %dx
        out   %al, %dx
        pop   %cx
        mov   $buf, %si
        xor   %bx, %bx                  # x of the cell
1:      lodsb
        push  %di
        mov   shline, %di               # only draw cells that changed,
        testb $7, shows                 # except every 8th time (all of them)
        jz    2f
        cmp   %al, (%di)
        je    3f
2:      mov   %al, (%di)
        push  %cx
        push  %si
        call  glyph
        pop   %si
        pop   %cx
3:      incw  shline
        pop   %di
        add   $8, %bx
        loop  1b
        call  vrest
        ret

# glyph: al = char, bx = cell x; draws an 8x12 cell (background 254)
glyph:  cmp   $'a', %al                 # lower case -> upper case
        jb    1f
        cmp   $'z', %al
        ja    1f
        sub   $0x20, %al
1:      cmp   $0x20, %al
        jb    2f
        cmp   $0x5f, %al
        jbe   3f
2:      mov   $' ', %al
3:      sub   $0x20, %al
        mov   $5, %ah
        mul   %ah
        mov   $font, %si
        add   %ax, %si
        xor   %cx, %cx                  # cy = 0..11
6:      xor   %dx, %dx                  # cx = 0..7
7:      mov   $254, %al                 # background
        mov   %cx, %di
        sub   $1, %di                   # glyph row = (cy-1)/2 for cy 1..10
        js    8f
        shr   $1, %di
        cmp   $5, %di
        jae   8f
        mov   %dx, %ax
        sub   $1, %ax                   # glyph col = (cx-1)/2 for cx 1..6
        js    11f
        shr   $1, %ax
        cmp   $3, %ax
        jae   11f
        push  %cx
        mov   %al, %cl
        push  %bx
        mov   %si, %bx
        mov   (%bx,%di), %ah
        pop   %bx
        shl   %cl, %ah
        pop   %cx
        test  $4, %ah
        mov   $254, %al
        jz    8f
        mov   $255, %al
        jmp   8f
11:     mov   $254, %al
8:      push  %cx
        push  %dx
        add   %bx, %dx                  # x
        mov   %cx, %di
        add   ybase, %di                # y
        call  pixel
        pop   %dx
        pop   %cx
        inc   %dx
        cmp   $8, %dx
        jb    7b
        inc   %cx
        cmp   $12, %cx
        jb    6b
        ret

# pixel: al = colour, dx = x, di = y; chained or unchained 320x200
pixel:  push  %ax
        mov   $0xa000, %ax
        mov   %ax, %es
        cmpb  $0, chain
        jz    1f
        push  %dx                       # chained: y*320 + x
        mov   %di, %ax
        mov   $320, %cx
        mul   %cx
        pop   %dx
        add   %dx, %ax
        mov   %ax, %di
        pop   %ax
        mov   %al, %es:(%di)
        ret
1:      mov   %dx, %cx                  # unchained: plane x&3, start + y*width + x/4
        and   $3, %cl
        mov   $1, %ah
        shl   %cl, %ah
        mov   $0x02, %al
        push  %dx
        mov   $0x3c4, %dx
        out   %ax, %dx
        mov   %di, %ax
        mulw  width
        pop   %dx
        shr   $2, %dx
        add   %dx, %ax
        add   start, %ax
        mov   %ax, %di
        pop   %ax
        mov   %al, %es:(%di)
        ret

# vsave: save the VGA registers that are changed; detect chain-4, start, width
vsave:  mov   $0x3c4, %dx
        in    %dx, %al
        mov   %al, s_seqi
        mov   $4, %al
        out   %al, %dx
        inc   %dx
        in    %dx, %al
        and   $8, %al
        mov   %al, chain
        dec   %dx
        mov   $2, %al
        out   %al, %dx
        inc   %dx
        in    %dx, %al
        mov   %al, s_mask
        mov   $0x0f, %al
        out   %al, %dx
        mov   $0x3ce, %dx
        in    %dx, %al
        mov   %al, s_gci
        mov   $s_gc, %si
        mov   $gcregs, %bx
1:      mov   (%bx), %al
        out   %al, %dx
        inc   %dx
        in    %dx, %al
        mov   %al, (%si)
        and   1(%bx), %al               # "keep" mask...
        or    2(%bx), %al               # ...plus forced bits
        out   %al, %dx
        dec   %dx
        inc   %si
        add   $3, %bx
        cmpb  $0, (%bx)
        jne   1b
        mov   $0x3d4, %dx
        in    %dx, %al
        mov   %al, s_crti
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
        mov   %ax, start
        dec   %dx
        mov   $0x13, %al
        out   %al, %dx
        inc   %dx
        in    %dx, %al
        xor   %ah, %ah
        shl   $1, %ax
        mov   %ax, width
        dec   %dx
        mov   s_crti, %al
        out   %al, %dx
        ret
# gcregs: index, keep mask, forced bits; 0 ends
# 01 set/reset enable -> 0; 03 rotate/function -> 0; 05 mode -> write mode 0; 08 bit mask -> FF
gcregs: .byte 0x01, 0x00, 0x00
        .byte 0x03, 0x00, 0x00
        .byte 0x05, 0xfc, 0x00
        .byte 0x08, 0x00, 0xff
        .byte 0

vrest:  mov   $0x3ce, %dx
        mov   $s_gc, %si
        mov   $gcregs, %bx
1:      mov   (%bx), %al
        out   %al, %dx
        inc   %dx
        mov   (%si), %al
        out   %al, %dx
        dec   %dx
        inc   %si
        add   $3, %bx
        cmpb  $0, (%bx)
        jne   1b
        mov   s_gci, %al
        out   %al, %dx
        mov   $0x3c4, %dx
        mov   $2, %al
        out   %al, %dx
        inc   %dx
        mov   s_mask, %al
        out   %al, %dx
        dec   %dx
        mov   s_seqi, %al
        out   %al, %dx
        ret

psp:    .word 0
shows:  .word 0
shline: .word 0
shadow: .space 15*40                    # what each graphics line shows now
sda:    .word 0, 0                      # DOS swappable data area (INT 21h 5D06h)
ybase:  .word 0
chain:  .byte 0
s_seqi: .byte 0
s_mask: .byte 0
s_gci:  .byte 0
s_crti: .byte 0
s_gc:   .space 4
start:  .word 0
width:  .word 0
font:
        .include "font35.inc"
resend:

init:   push  %ds                       # find the SDA once, here
        mov   $0x5d06, %ax
        int   $0x21
        mov   %ds, %ax
        pop   %ds
        mov   %si, sda
        mov   %ax, sda+2
        mov   $0x3510, %ax              # hook INT 10h
        int   $0x21
        mov   %bx, old10
        mov   %es, old10+2
        mov   $0x2510, %ax
        mov   $int10, %dx
        int   $0x21
        mov   $0x3570, %ax              # save and replace INT 70h
        int   $0x21
        mov   %bx, old70
        mov   %es, old70+2
        mov   $0x2570, %ax
        mov   $isr, %dx
        int   $0x21
        cli
        mov   $0x8a, %al                # register A: rate 0Ch = 16 Hz (NMI off while programming)
        out   %al, $0x70
        in    $0x71, %al
        and   $0xf0, %al
        or    $0x0c, %al
        mov   %al, %ah
        mov   $0x8a, %al
        out   %al, $0x70
        mov   %ah, %al
        out   %al, $0x71
        mov   $0x8b, %al                # register B: periodic interrupt on
        out   %al, $0x70
        in    $0x71, %al
        or    $0x40, %al
        mov   %al, %ah
        mov   $0x8b, %al
        out   %al, $0x70
        mov   %ah, %al
        out   %al, $0x71
        mov   $0x0c, %al                # clear pending flags, NMI on again
        out   %al, $0x70
        in    $0x71, %al
        in    $0xa1, %al                # unmask IRQ 8 and the cascade IRQ 2
        and   $0xfe, %al
        out   %al, $0xa1
        in    $0x21, %al
        and   $0xfb, %al
        out   %al, $0x21
        sti
        mov   $msg, %dx
        mov   $9, %ah
        int   $0x21
        mov   $resend+15, %dx           # stay resident up to resend
        shr   $4, %dx
        mov   $0x3100, %ax
        int   $0x21

msg:    .ascii "WHERE 3 installed: RTC 16 Hz sampler + text capture, shown at the top left.\r\n$"
