#!/usr/bin/env python3
"""Send commands to the QEMU monitor started by qemu_sbemu.sh (run from its DIR).

usage: qemu_mon.py CMD [CMD ...]
  any monitor command, e.g.  'sendkey ret'  'sendkey down 600' (hold 600 ms)
                             'info irq'  'info registers'  'log int'  'log none'
  'sleep N'     wait N seconds
  'shot NAME'   save the screen as out/NAME.png (needs Pillow)
"""
import socket, sys, time


def cmd(c):
    s = socket.socket(socket.AF_UNIX)
    s.connect('mon.sock')
    s.recv(4096)
    s.send((c + '\n').encode())
    time.sleep(0.3)
    r = s.recv(65536)
    s.close()
    return r.decode(errors='replace')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for c in sys.argv[1:]:
        if c.startswith('sleep '):
            time.sleep(float(c[6:]))
        elif c.startswith('shot '):
            n = c[5:]
            cmd('screendump out/%s.ppm' % n)
            time.sleep(0.5)
            from PIL import Image
            Image.open('out/%s.ppm' % n).save('out/%s.png' % n)
        else:
            print(cmd(c))
