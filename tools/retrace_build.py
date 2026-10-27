# RETRACE.COM - VGA retrace / PIT diagnostic for the 86Duino (repeats Civilization's timer calibration)
import sys
from keystone import *
ks=Ks(KS_ARCH_X86,KS_MODE_16)
labels=[("lt",  "3DAh in mode 13h, first read : "),
        ("lto", "Calibration timeouts (of 17)  : "),
        ("ld1", "Frame 1, PIT count difference : "),
        ("ld2", "Frame 2, PIT count difference : "),
        ("ld3", "Frame 3, PIT count difference : "),
        ("ld4", "Frame 4, PIT count difference : "),
        ("lck", "Average PIT clocks per frame  : "),
        ("lhz", "=> refresh rate (Hz)          : "),
        ("lrd", "3DAh reads in 1 second        : "),
        ("lvr", "Retrace starts (bit 3 0->1)/s : "),
        ("lvo", "Reads with bit 3 set          : "),
        ("lde", "Bit 0 toggles per second      : "),
        ("ltk", "BIOS ticks seen (should be 18): "),
        ("lr1", "DAC readback of (21,42,63), R : "),
        ("lr2", "                            G : "),
        ("lr3", "                            B : "),
        ("lcp", "Civ test: colours per frame   : "),
        ("lcc", "Civ test: hit safety cap (0/1): "),
        ("lmo", "BIOS counts down 0040:0040    : "),
        ("lk1", "Dissolve test, delay 1       : "),
        ("lk2", "Dissolve test, delay 17      : ")]
vals=["vfirst","vto","vd1","vd2","vd3","vd4","vck","vhz","vrd","vvr","vvo","vde","vtk","vr1","vr2","vr3","vcp","vcc","vmo","vk1","vk2","vmorig"]
src = """
 mov ax,0x13
 int 0x10
 mov dx,0x3da
 in al,dx
 mov byte ptr [vfirst],al
 cli
 mov cx,17
 xor bp,bp
 mov di,0
A1:
 push cx
 mov dx,0x3da
 xor bx,bx
A2:
 dec bx
 jz Ato
 in al,dx
 test al,8
 jnz A2
 xor bx,bx
A3:
 dec bx
 jz Ato
 in al,dx
 test al,8
 jz A3
 mov al,0
 out 0x43,al
 in al,0x40
 mov bl,al
 in al,0x40
 mov bh,al
 jmp Ast
Ato:
 add word ptr [vto],1
 xor bx,bx
Ast:
 cmp di,0
 je Afirst
 mov ax,bp
 sub ax,bx
 add word ptr [vsum],ax
 adc word ptr [vsum+2],0
 cmp di,4
 ja Askip
 mov si,di
 shl si,1
 shl si,1
 mov word ptr [vd1-4+si],ax
Askip:
Afirst:
 mov bp,bx
 inc di
 pop cx
 loop A1
 sti
 mov ax,word ptr [vsum]
 mov dx,word ptr [vsum+2]
 mov cx,32
 div cx
 mov word ptr [vck],ax
 or ax,ax
 jz Nohz
 mov cx,ax
 mov dx,0x12
 mov ax,0x34de
 cmp cx,0x13
 jb Nohz
 div cx
 mov word ptr [vhz],ax
Nohz:
 xor ax,ax
 mov es,ax
 mov si,word ptr es:[0x46c]
 mov di,si
 xor cx,cx
 mov bp,300
B0:
 dec cx
 jnz B0b
 dec bp
 jz Bdone
B0b:
 cmp si,word ptr es:[0x46c]
 je B0
 mov si,word ptr es:[0x46c]
 mov di,si
 add si,18
 mov dx,0x3da
 in al,dx
 mov ah,al
B1:
 in al,dx
 add word ptr [vrd],1
 adc word ptr [vrd+2],0
 mov bl,al
 xor bl,ah
 mov ah,al
 test al,8
 jz B1a
 add word ptr [vvo],1
 adc word ptr [vvo+2],0
 test bl,8
 jz B1a
 add word ptr [vvr],1
B1a:
 test bl,1
 jz B2
 add word ptr [vde],1
 adc word ptr [vde+2],0
B2:
 cmp word ptr [vrd+2],400
 ja Bdone
 cmp si,word ptr es:[0x46c]
 jne B1
Bdone:
 mov ax,word ptr es:[0x46c]
 sub ax,di
 mov word ptr [vtk],ax

 mov dx,0x3c8
 mov al,0
 out dx,al
 inc dx
 mov al,21
 out dx,al
 mov al,42
 out dx,al
 mov al,63
 out dx,al
 mov dx,0x3c7
 mov al,0
 out dx,al
 mov dx,0x3c9
 in al,dx
 mov byte ptr [vr1],al
 in al,dx
 mov byte ptr [vr2],al
 in al,dx
 mov byte ptr [vr3],al
 mov dx,0x3c8
 mov al,0
 out dx,al
 inc dx
 out dx,al
 out dx,al
 out dx,al
 cli
 mov dx,0x3da
 xor cx,cx
C1:
 dec cx
 jz Ccap
 in al,dx
 test al,8
 jz C1
 xor cx,cx
C2:
 dec cx
 jz Ccap
 in al,dx
 test al,8
 jnz C2
 xor bx,bx
 mov di,60000
C3:
 mov dl,0xc8
 mov al,0
 out dx,al
 mov dl,0xc9
 mov si,offset_zeros
 mov cx,30
 rep outsb
 add bx,10
 mov dl,0xda
 in al,dx
 test al,8
 jnz Cend
 dec di
 jnz C3
Ccap:
 mov byte ptr [vcc],1
Cend:
 sti
 mov word ptr [vcp],bx
 xor ax,ax
 mov es,ax
 mov al,byte ptr es:[0x440]
 mov byte ptr [vmorig],al
 mov byte ptr es:[0x440],2
 mov si,word ptr es:[0x46c]
 add si,40
M1:
 cmp byte ptr es:[0x440],2
 jne Mchg
 cmp si,word ptr es:[0x46c]
 jne M1
 jmp Mend
Mchg:
 mov byte ptr [vmo],1
Mend:
 mov al,byte ptr [vmorig]
 mov byte ptr es:[0x440],al
 mov ax,0xa000
 mov es,ax

 mov bx,1
 cli
 xor cx,cx
 mov si,1
 mov dx,0x3da
D1a:
 in al,dx
 test al,8
 jz D1a
D2a:
 in al,dx
 test al,8
 jnz D2a
D3a:
 shr si,1
 jae D4a
 xor si,0xb400
D4a:
 cmp si,0xfa00
 ja D3a
 dec si
 mov di,0xffff
 movsb
 mov ax,bx
D5a:
 dec ax
 jnz D5a
 inc cx
 in al,dx
 test al,8
 jz D3a
 sti
 mov word ptr [vk1],cx

 mov bx,17
 cli
 xor cx,cx
 mov si,1
 mov dx,0x3da
D1b:
 in al,dx
 test al,8
 jz D1b
D2b:
 in al,dx
 test al,8
 jnz D2b
D3b:
 shr si,1
 jae D4b
 xor si,0xb400
D4b:
 cmp si,0xfa00
 ja D3b
 dec si
 mov di,0xffff
 movsb
 mov ax,bx
D5b:
 dec ax
 jnz D5b
 inc cx
 in al,dx
 test al,8
 jz D3b
 sti
 mov word ptr [vk2],cx
 mov ax,3
 int 0x10
 mov dx,offset_title
 mov ah,9
 int 0x21
 mov si,offset_table
P1:
 mov dx,word ptr [si]
 or dx,dx
 jz Pdone
 mov ah,9
 int 0x21
 mov bx,word ptr [si+2]
 mov ax,word ptr [bx]
 mov dx,word ptr [bx+2]
 mov di,offset_numend
 mov cx,10
P2:
 push ax
 mov ax,dx
 xor dx,dx
 div cx
 mov bx,ax
 pop ax
 div cx
 add dl,0x30
 dec di
 mov byte ptr [di],dl
 mov dx,bx
 mov bp,ax
 or bp,dx
 jnz P2
 mov dx,di
 mov ah,9
 int 0x21
 mov dx,offset_crlf
 mov ah,9
 int 0x21
 add si,4
 jmp P1
Pdone:
 mov ax,0x4c00
 int 0x21
"""
def build(base_data):
    # data layout after code
    d=bytearray(); addr={}
    def put(name,b):
        addr[name]=base_data+len(d); d.extend(b)
    for v in vals+["vsum"]: put(v,bytes(4))
    put("title",b"RETRACE - VGA retrace / timer check (Civilization calibration)\r\n\r\n$")
    for l,t in labels: put(l,t.encode()+b"$")
    put("crlf",b"\r\n$")
    put("zeros",bytes(32))
    put("numbuf",b"           "); put("numend",b"$")
    tab=b""
    for (l,_),v in zip(labels,vals): tab+=addr[l].to_bytes(2,'little')+addr[v].to_bytes(2,'little')
    put("table",tab+b"\0\0\0\0")
    return d,addr
d,addr=build(0)
code_len=None
for it in range(3):
    base=0x100+(code_len or 0x300)
    d,addr=build(base)
    s=src
    for k,v in addr.items():
        s=s.replace("offset_"+k,str(v))
    for k in sorted(addr,key=len,reverse=True):
        s=s.replace("["+k+"-4+si]","[si+%d]"%(addr[k]-4)).replace("["+k+"+2]","[%d]"%(addr[k]+2)).replace("["+k+"]","[%d]"%addr[k])
    code=bytes(ks.asm(s,0x100)[0])
    code_len=len(code)
open(sys.argv[1],'wb').write(code+bytes(d))
print(len(code),len(d))
