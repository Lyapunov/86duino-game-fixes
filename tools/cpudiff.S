# CPUDIFF.COM - differential CPU test: run instruction forms on fixed operands and hash the results
# Built by cpudiff_build.py. Run it on two machines (e.g. the 86Duino and a QEMU VM) with
#   CPUDIFF > CPU.TXT
# and compare the files line by line. Any line that differs points at an instruction that
# computes something different on one of the CPUs.
#
# Each test runs N times. The first 289 passes use every pair of 17 edge values
# (0, 1, -1, 0x80000000, 31, 32, ...) with the count/aux operand = pass number, the
# rest use xorshift32 random operands. The seed is fixed, so every CPU gets the
# same inputs. The flags going in are random too (only the arithmetic flags).
#   R = hash of the results (EAX and EDX after the instruction)
#   F = hash of the flags that x86 defines for the instruction
#   U = hash of the flags x86 leaves undefined (a difference here is legal, but a
#       game that relies on them will behave differently)
# Must run in real mode or V86 mode; needs a 386 or later with an FPU.

        .intel_syntax noprefix
        .code16
        .text
        .globl _start

        .equ N, 4096
        .equ NEDGE, 17

_start:
        mov     dx, offset s_title
        call    puts
        call    cpuinfo

        mov     cx, 256                 # translation table for XLAT: xtab[i] = i*7+3
        xor     bx, bx
        mov     al, 3
1:      mov     byte ptr [xtab+bx], al
        add     al, 7
        inc     bx
        loop    1b

        fninit
        mov     word ptr [tptr], offset tests

next_test:
        mov     si, word ptr [tptr]
        cmp     word ptr [si], 0
        jne     2f
        mov     ax, 0x4C00
        int     0x21
2:      mov     dword ptr [hr], 0x12345678
        mov     dword ptr [hf], 0
        mov     dword ptr [hu], 0
        mov     dword ptr [seed], 0x2545F491
        mov     dword ptr [iter], 0

pass:
        call    rnd
        mov     dword ptr [va], eax
        call    rnd
        mov     dword ptr [vb], eax
        call    rnd
        mov     dword ptr [vc], eax
        call    rnd
        mov     dword ptr [vd], eax
        call    rnd
        mov     dword ptr [vf], eax

        mov     eax, dword ptr [iter]   # edge passes: a = edge[i%17], b = edge[i/17], c = i
        cmp     eax, NEDGE*NEDGE
        jae     3f
        xor     edx, edx
        mov     ebx, NEDGE
        div     ebx
        mov     bx, dx
        shl     bx, 2
        mov     ecx, dword ptr [edge+bx]
        mov     dword ptr [va], ecx
        mov     bx, ax
        shl     bx, 2
        mov     ecx, dword ptr [edge+bx]
        mov     dword ptr [vb], ecx
        mov     ecx, dword ptr [iter]
        mov     dword ptr [vc], ecx
3:
        mov     eax, dword ptr [vf]     # random OF SF ZF AF PF CF, IF on, DF off
        and     eax, 0x8D5
        or      eax, 0x202
        mov     dword ptr [vf], eax

        mov     eax, dword ptr [va]
        mov     ebx, dword ptr [vb]
        mov     ecx, dword ptr [vc]
        mov     edx, dword ptr [vd]
        mov     si, word ptr [tptr]
        push    dword ptr [vf]
        popfd
        call    word ptr [si]
        pushfd
        pop     dword ptr [vfl]
        mov     dword ptr [r1], eax
        mov     dword ptr [r2], edx

        mov     eax, dword ptr [hr]
        mov     edx, dword ptr [r1]
        call    mix
        mov     edx, dword ptr [r2]
        call    mix
        mov     dword ptr [hr], eax

        mov     si, word ptr [tptr]
        mov     ecx, dword ptr [si+2]   # defined-flags mask
        mov     edx, dword ptr [vfl]
        and     edx, ecx
        mov     eax, dword ptr [hf]
        call    mix
        mov     dword ptr [hf], eax
        not     ecx
        mov     edx, dword ptr [vfl]
        and     edx, ecx
        and     edx, 0x8D5
        mov     eax, dword ptr [hu]
        call    mix
        mov     dword ptr [hu], eax

        inc     dword ptr [iter]
        cmp     dword ptr [iter], N
        jb      pass

        mov     si, word ptr [tptr]
        mov     dx, word ptr [si+6]
        call    puts
        mov     dx, offset s_r
        call    puts
        mov     eax, dword ptr [hr]
        call    puthex32
        mov     dx, offset s_f
        call    puts
        mov     eax, dword ptr [hf]
        call    puthex32
        mov     dx, offset s_u
        call    puts
        mov     eax, dword ptr [hu]
        call    puthex32
        mov     dx, offset s_crlf
        call    puts
        fninit
        add     word ptr [tptr], 8
        jmp     next_test

mix:                                    # EAX = rol(EAX,5) ^ EDX + const
        rol     eax, 5
        xor     eax, edx
        add     eax, 0x7F4A7C15
        ret

rnd:                                    # xorshift32 -> EAX
        mov     eax, dword ptr [seed]
        mov     edx, eax
        shl     edx, 13
        xor     eax, edx
        mov     edx, eax
        shr     edx, 17
        xor     eax, edx
        mov     edx, eax
        shl     edx, 5
        xor     eax, edx
        mov     dword ptr [seed], eax
        ret

# print vendor and family/model/stepping if CPUID exists
cpuinfo:
        pushfd
        pop     eax
        mov     ecx, eax
        xor     eax, 0x200000
        push    eax
        popfd
        pushfd
        pop     eax
        push    ecx
        popfd
        xor     eax, ecx
        test    eax, 0x200000
        jnz     1f
        mov     dx, offset s_nocpuid
        jmp     puts
1:      xor     eax, eax
        cpuid
        mov     dword ptr [vendor], ebx
        mov     dword ptr [vendor+4], edx
        mov     dword ptr [vendor+8], ecx
        mov     dx, offset s_cpuid
        call    puts
        mov     dx, offset vendor
        call    puts
        mov     dx, offset s_sig
        call    puts
        mov     eax, 1
        cpuid
        call    puthex32
        mov     dx, offset s_crlf2
        jmp     puts

# ---- integer tests: in EAX=a EBX=b ECX=c EDX=d, flags random; out EAX, EDX, flags ----
t_add:  add     eax, ebx
        ret
t_adc:  adc     eax, ebx
        ret
t_sbb:  sbb     eax, ebx
        ret
t_neg:  neg     eax
        ret
t_inc:  inc     eax
        ret
t_imul1: imul   ebx
        ret
t_mul1: mul     ebx
        ret
t_imul2: imul   eax, ebx
        ret
t_imul3: imul   eax, ebx, 0x12345
        ret
t_mul8: mul     bl
        ret
t_imul16: imul  ax, bx
        ret
t_div:  or      ebx, ebx                # avoid #DE: b != 0 and d < b
        jnz     1f
        inc     ebx
1:      mov     edx, ecx
        cmp     edx, ebx
        jb      2f
        xor     edx, edx
2:      div     ebx
        ret
t_idiv: cmp     ebx, 0                  # avoid #DE: b != 0, b != -1, dividend = sign-extended a
        jne     1f
        mov     ebx, 1
1:      cmp     ebx, -1
        jne     2f
        mov     ebx, 3
2:      cdq
        idiv    ebx
        ret
t_shl:  shl     eax, cl
        ret
t_shr:  shr     eax, cl
        ret
t_sar:  sar     eax, cl
        ret
t_rol:  rol     eax, cl
        ret
t_ror:  ror     eax, cl
        ret
t_rcl:  rcl     eax, cl
        ret
t_rcr:  rcr     eax, cl
        ret
t_shl1: shl     eax, 1
        ret
t_rcr1: rcr     eax, 1
        ret
t_shld: shld    eax, edx, cl
        ret
t_shrd: shrd    eax, edx, cl
        ret
t_shld16: shld  edx, eax, 16
        ret
t_shrd16: shrd  eax, edx, 16
        ret
t_shrdw: shrd   ax, dx, cl              # 16-bit form, counts 16..31 have undefined results
        ret
t_bsf:  bsf     eax, ebx
        ret
t_bsr:  bsr     eax, ebx
        ret
t_bswap: bswap  eax
        ret
t_xlat: push    bx
        mov     bx, offset xtab
        xlat
        pop     bx
        ret
t_aam:  aam
        ret
t_aam16: aam    16
        ret
t_aad:  aad
        ret
t_sahf: mov     ah, bl
        sahf
        lahf
        ret
t_setcc: seto   byte ptr [sc]
        setb    byte ptr [sc+1]
        sete    byte ptr [sc+2]
        setbe   byte ptr [sc+3]
        sets    byte ptr [sc+4]
        setp    byte ptr [sc+5]
        setl    byte ptr [sc+6]
        setle   byte ptr [sc+7]
        mov     eax, dword ptr [sc]
        mov     edx, dword ptr [sc+4]
        ret
t_cdq:  cdq
        ret
t_movsx: movsx  eax, bl
        movzx   edx, bh
        ret

# ---- FPU tests: flags not checked (mask 0); ECX bits 0-1 = rounding, 2-3 = precision ----
fpu_cw: mov     esi, ecx
        and     esi, 3
        shl     esi, 10
        mov     edi, ecx
        shr     edi, 2
        and     edi, 3
        cmp     edi, 1                  # precision 01 is reserved: use 11
        jne     1f
        mov     edi, 3
1:      shl     edi, 8
        or      esi, edi
        or      esi, 0x7F               # all exceptions masked
        mov     word ptr [cw], si
        fninit
        fldcw   word ptr [cw]
        mov     dword ptr [ta], eax
        or      ebx, ebx
        jnz     2f
        inc     ebx
2:      mov     dword ptr [tb], ebx
        ret

fpu_out32:                              # EAX = dword result, EDX = exception flags
        fnstsw  word ptr [tsw]
        mov     eax, dword ptr [tr]
        movzx   edx, word ptr [tsw]
        and     edx, 0x3F
        ret

f_rt:   call    fpu_cw                  # integer round trip (what the screen clear relies on)
        fild    dword ptr [ta]
        fistp   dword ptr [tr]
        jmp     fpu_out32
f_div32: call   fpu_cw
        fild    dword ptr [ta]
        fidiv   dword ptr [tb]
        fistp   dword ptr [tr]
        jmp     fpu_out32
f_div16: call   fpu_cw
        fild    dword ptr [ta]
        fidiv   dword ptr [tb]
        mov     dword ptr [tr], 0
        fistp   word ptr [tr]
        jmp     fpu_out32
f_divq: call    fpu_cw                  # quotient stored as a double
        fild    dword ptr [ta]
        fidiv   dword ptr [tb]
        fstp    qword ptr [tq]
        mov     eax, dword ptr [tq]
        mov     edx, dword ptr [tq+4]
        ret
f_mul32: call   fpu_cw                  # often overflows: Intel stores 0x80000000
        fild    dword ptr [ta]
        fimul   dword ptr [tb]
        fistp   dword ptr [tr]
        jmp     fpu_out32
f_mul64: call   fpu_cw
        fild    dword ptr [ta]
        fimul   dword ptr [tb]
        fistp   qword ptr [tq]
        mov     eax, dword ptr [tq]
        mov     edx, dword ptr [tq+4]
        ret
f_sqrt: call    fpu_cw
        fild    dword ptr [ta]
        fabs
        fsqrt
        fimul   dword ptr [k65536]
        fistp   dword ptr [tr]
        jmp     fpu_out32
f_rnd:  call    fpu_cw
        fild    dword ptr [ta]
        fidiv   dword ptr [tb]
        fld     st(0)
        frndint
        fistp   dword ptr [tr]
        fimul   dword ptr [k65536]
        fistp   dword ptr [trb]
        mov     eax, dword ptr [tr]
        mov     edx, dword ptr [trb]
        ret
f_prem: call    fpu_cw
        fild    dword ptr [tb]
        fild    dword ptr [ta]
1:      fprem
        fnstsw  word ptr [tsw]
        test    byte ptr [tsw+1], 4     # C2 set = reduction incomplete
        jnz     1b
        fistp   dword ptr [tr]
        fstp    st(0)
        mov     eax, dword ptr [tr]
        movzx   edx, word ptr [tsw]
        and     edx, 0x4300             # C0 C1 C3 = low quotient bits
        ret
f_yl2x: call    fpu_cw                  # log2(|a|+1) * 65536
        fld1
        fild    dword ptr [ta]
        fabs
        fld1
        faddp
        fyl2x
        fimul   dword ptr [k65536]
        fistp   dword ptr [tr]
        jmp     fpu_out32
f_2xm1: call    fpu_cw                  # (2^(a/-2^31) - 1) * 2^30
        fild    dword ptr [ta]
        fidiv   dword ptr [k2_31]
        f2xm1
        fimul   dword ptr [k2_30]
        fistp   dword ptr [tr]
        jmp     fpu_out32
f_scale: call   fpu_cw                  # a * 2^(signed low byte of d), as a double
        movsx   esi, dl
        mov     dword ptr [tc], esi
        fild    dword ptr [tc]
        fild    dword ptr [ta]
        fscale
        fstp    qword ptr [tq]
        fstp    st(0)
        mov     eax, dword ptr [tq]
        mov     edx, dword ptr [tq+4]
        ret

# ---- output ----
puts:   mov     ah, 9
        int     0x21
        ret
putc:   mov     ah, 2
        int     0x21
        ret
puthex32:
        mov     cx, 8
1:      rol     eax, 4
        push    eax
        and     al, 0x0F
        add     al, '0'
        cmp     al, '9'
        jbe     2f
        add     al, 7
2:      mov     dl, al
        call    putc
        pop     eax
        loop    1b
        ret

# ---- data ----
        .p2align 2
edge:   .long   0, 1, 2, 3, 0x7FFFFFFF, 0x80000000, 0x80000001, 0xFFFFFFFF, 0xFFFFFFFE
        .long   0x0000FFFF, 0x00010000, 0x00008000, 0xFFFF8000, 0x55555555, 0xAAAAAAAA, 31, 32
k65536: .long   65536
k2_31:  .long   0x80000000
k2_30:  .long   0x40000000

        .macro  T fn, mask, name
        .word   \fn
        .long   \mask
        .word   \name
        .endm
tests:
        T t_add,    0x8D5, n01
        T t_adc,    0x8D5, n02
        T t_sbb,    0x8D5, n03
        T t_neg,    0x8D5, n04
        T t_inc,    0x8D5, n05
        T t_imul1,  0x801, n06
        T t_mul1,   0x801, n07
        T t_imul2,  0x801, n08
        T t_imul3,  0x801, n09
        T t_mul8,   0x801, n10
        T t_imul16, 0x801, n11
        T t_div,    0,     n12
        T t_idiv,   0,     n13
        T t_shl,    0x0C5, n14
        T t_shr,    0x0C5, n15
        T t_sar,    0x0C5, n16
        T t_rol,    0x001, n17
        T t_ror,    0x001, n18
        T t_rcl,    0x001, n19
        T t_rcr,    0x001, n20
        T t_shl1,   0x8C5, n21
        T t_rcr1,   0x801, n22
        T t_shld,   0x0C5, n23
        T t_shrd,   0x0C5, n24
        T t_shld16, 0x0C5, n25
        T t_shrd16, 0x0C5, n26
        T t_shrdw,  0,     n27
        T t_bsf,    0x040, n28
        T t_bsr,    0x040, n29
        T t_bswap,  0x8D5, n30
        T t_xlat,   0x8D5, n31
        T t_aam,    0x0C4, n32
        T t_aam16,  0x0C4, n33
        T t_aad,    0x0C4, n34
        T t_sahf,   0x0D5, n35
        T t_setcc,  0x8D5, n36
        T t_cdq,    0x8D5, n37
        T t_movsx,  0x8D5, n38
        T f_rt,     0,     n39
        T f_div32,  0,     n40
        T f_div16,  0,     n41
        T f_divq,   0,     n42
        T f_mul32,  0,     n43
        T f_mul64,  0,     n44
        T f_sqrt,   0,     n45
        T f_rnd,    0,     n46
        T f_prem,   0,     n47
        T f_yl2x,   0,     n48
        T f_2xm1,   0,     n49
        T f_scale,  0,     n50
        .word   0

n01:    .ascii  "01 add r32        $"
n02:    .ascii  "02 adc r32        $"
n03:    .ascii  "03 sbb r32        $"
n04:    .ascii  "04 neg r32        $"
n05:    .ascii  "05 inc r32        $"
n06:    .ascii  "06 imul r32 (1op) $"
n07:    .ascii  "07 mul r32        $"
n08:    .ascii  "08 imul r32,r32   $"
n09:    .ascii  "09 imul r,r,imm   $"
n10:    .ascii  "10 mul r8         $"
n11:    .ascii  "11 imul r16,r16   $"
n12:    .ascii  "12 div r32        $"
n13:    .ascii  "13 idiv r32       $"
n14:    .ascii  "14 shl r32,cl     $"
n15:    .ascii  "15 shr r32,cl     $"
n16:    .ascii  "16 sar r32,cl     $"
n17:    .ascii  "17 rol r32,cl     $"
n18:    .ascii  "18 ror r32,cl     $"
n19:    .ascii  "19 rcl r32,cl     $"
n20:    .ascii  "20 rcr r32,cl     $"
n21:    .ascii  "21 shl r32,1      $"
n22:    .ascii  "22 rcr r32,1      $"
n23:    .ascii  "23 shld r32,cl    $"
n24:    .ascii  "24 shrd r32,cl    $"
n25:    .ascii  "25 shld r32,16    $"
n26:    .ascii  "26 shrd r32,16    $"
n27:    .ascii  "27 shrd r16,cl    $"
n28:    .ascii  "28 bsf r32        $"
n29:    .ascii  "29 bsr r32        $"
n30:    .ascii  "30 bswap          $"
n31:    .ascii  "31 xlat           $"
n32:    .ascii  "32 aam            $"
n33:    .ascii  "33 aam 16         $"
n34:    .ascii  "34 aad            $"
n35:    .ascii  "35 sahf/lahf      $"
n36:    .ascii  "36 setcc (8 cond) $"
n37:    .ascii  "37 cdq            $"
n38:    .ascii  "38 movsx/movzx    $"
n39:    .ascii  "39 fild/fistp     $"
n40:    .ascii  "40 fidiv>fistp32  $"
n41:    .ascii  "41 fidiv>fistp16  $"
n42:    .ascii  "42 fidiv>fstp64   $"
n43:    .ascii  "43 fimul>fistp32  $"
n44:    .ascii  "44 fimul>fistp64  $"
n45:    .ascii  "45 fsqrt          $"
n46:    .ascii  "46 frndint        $"
n47:    .ascii  "47 fprem          $"
n48:    .ascii  "48 fyl2x          $"
n49:    .ascii  "49 f2xm1          $"
n50:    .ascii  "50 fscale         $"

s_title: .ascii "CPUDIFF - differential CPU test (compare the output of two machines)\r\n$"
s_nocpuid: .ascii "CPUID: not supported\r\n\r\n$"
s_cpuid: .ascii "CPUID: $"
s_sig:  .ascii  "  signature $"
s_r:    .ascii  "R=$"
s_f:    .ascii  " F=$"
s_u:    .ascii  " U=$"
s_crlf2: .ascii "\r\n"
s_crlf: .ascii  "\r\n$"
vendor: .ascii  "            $"

        .p2align 2
seed:   .long   0
iter:   .long   0
hr:     .long   0
hf:     .long   0
hu:     .long   0
va:     .long   0
vb:     .long   0
vc:     .long   0
vd:     .long   0
vf:     .long   0
vfl:    .long   0
r1:     .long   0
r2:     .long   0
ta:     .long   0
tb:     .long   0
tc:     .long   0
tr:     .long   0
trb:    .long   0
tq:     .quad   0
sc:     .quad   0
tsw:    .word   0
cw:     .word   0
tptr:   .word   0
xtab:   .fill   256, 1, 0
