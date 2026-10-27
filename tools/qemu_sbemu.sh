#!/bin/bash
# Boot a DOS PC in QEMU with an HD Audio card, for testing games under
# JEMMEX + HDPMI32i + SBEMU (see borrowed-interrupt-flag.md).
#
# usage: qemu_sbemu.sh DIR NAME
#   DIR/boot.img  a bootable DOS floppy whose CONFIG.SYS loads C:\SBEMU\JEMMEX.EXE
#                 and whose AUTOEXEC.BAT ends with CALL C:\GO.BAT (fat12.py can write them)
#   DIR/c/        becomes drive C: (put SBEMU\ with the SBEMU.zip files, the game, GO.BAT)
#   NAME          the sound output is recorded to DIR/out/NAME.wav
# The QEMU monitor listens on DIR/mon.sock; drive it with qemu_mon.py.
# Optional: EXTRA="-icount shift=6,sleep=on" (slow CPU), EXTRA="-D DIR/out/int.log"
# (then `qemu_mon.py 'log int' ...` traces interrupts and exceptions).
# The AC97 card gave no audio in this setup; the HD Audio card works.
cd "$1" || exit 1
mkdir -p out
rm -f mon.sock
qemu-system-i386 -m 64 -cpu pentium $EXTRA -display none \
  -drive file=boot.img,format=raw,if=floppy -drive file=fat:rw:c,format=raw,if=ide,index=0 -boot a \
  -audiodev wav,id=snd,path=out/$2.wav -device ich9-intel-hda -device hda-output,audiodev=snd \
  -monitor unix:mon.sock,server,nowait -serial none -parallel none &
echo $! > qemu.pid
