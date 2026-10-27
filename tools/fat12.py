#!/usr/bin/env python3
"""Minimal FAT12 floppy-image editor (root directory only), to set up a boot
floppy for qemu_sbemu.sh without mtools.

usage: fat12.py IMG                      list the root directory
       fat12.py IMG put FILE [NAME]      add or replace a file (8.3 NAME)
       fat12.py IMG rm NAME              delete a file
"""
import struct,sys
class F:
  def __init__(s,p):
    s.p=p; s.d=bytearray(open(p,'rb').read())
    b=s.d; s.bps,s.spc,s.res,s.nf,s.nroot=struct.unpack_from('<HBHBH',b,11); s.spf=struct.unpack_from('<H',b,22)[0]
    s.fat=s.res*s.bps; s.root=s.fat+s.nf*s.spf*s.bps; s.data=s.root+s.nroot*32
  def ent(s,i):
    o=s.fat+i*3//2; v=struct.unpack_from('<H',s.d,o)[0]; return v>>4 if i&1 else v&0xfff
  def setent(s,i,v):
    for k in range(s.nf):
      o=s.fat+k*s.spf*s.bps+i*3//2; w=struct.unpack_from('<H',s.d,o)[0]
      w=(w&0xf)|(v<<4) if i&1 else (w&0xf000)|v
      struct.pack_into('<H',s.d,o,w)
  def ls(s):
    for i in range(s.nroot):
      e=s.d[s.root+i*32:s.root+i*32+32]
      if e[0] in (0,0xe5) or e[11]&8: continue
      yield i,e[:8].decode('latin1').strip()+'.'+e[8:11].decode('latin1').strip(),struct.unpack_from('<HI',e,26)
  def read(s,name):
    for i,n,(cl,sz) in s.ls():
      if n.rstrip('.')==name:
        out=b''; cs=s.spc*s.bps
        while 2<=cl<0xff8: out+=s.d[s.data+(cl-2)*cs:s.data+(cl-1)*cs]; cl=s.ent(cl)
        return out[:sz]
  def rm(s,name):
    for i,n,(cl,sz) in s.ls():
      if n.rstrip('.')==name:
        s.d[s.root+i*32]=0xe5
        while 2<=cl<0xff8: nx=s.ent(cl); s.setent(cl,0); cl=nx
  def write(s,name,data):
    s.rm(name); cs=s.spc*s.bps; n=(len(data)+cs-1)//cs; free=[]
    tot=(len(s.d)-s.data)//cs+2
    for c in range(2,tot):
      if s.ent(c)==0: free.append(c)
      if len(free)==n: break
    for k,c in enumerate(free):
      s.setent(c,free[k+1] if k+1<n else 0xfff)
      chunk=data[k*cs:(k+1)*cs]; s.d[s.data+(c-2)*cs:s.data+(c-2)*cs+len(chunk)]=chunk
    for i in range(s.nroot):
      if s.d[s.root+i*32] in (0,0xe5):
        b,e=(name.split('.')+[''])[:2]
        ent=b.ljust(8).encode()+e.ljust(3).encode()+bytes([0x20])+bytes(14)+struct.pack('<HI',free[0] if free else 0,len(data))
        s.d[s.root+i*32:s.root+i*32+32]=ent; break
  def save(s): open(s.p,'wb').write(s.d)
if __name__=='__main__':
  if len(sys.argv)<2: sys.exit(__doc__)
  f=F(sys.argv[1])
  if len(sys.argv)==2:
    for x in f.ls(): print(x)
  elif sys.argv[2]=='put':
    f.write((sys.argv[4] if len(sys.argv)>4 else sys.argv[3].split('/')[-1]).upper(),open(sys.argv[3],'rb').read()); f.save()
  elif sys.argv[2]=='rm':
    f.rm(sys.argv[3].upper()); f.save()
