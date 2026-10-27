# Borrowed Interrupt Flag: when SBEMU's DOS extender trips over a game's last instruction

On the 86Duino, music and sound in DOS games come from **SBEMU**. SBEMU
pretends to be a Sound Blaster and an AdLib card, and plays their sound
through the 86Duino's real sound chip. To catch a protected-mode game talking
to the "card", SBEMU needs the DPMI host **HDPMI32i** underneath it. HDPMI32i
runs programs **without the right to switch interrupts on and off
themselves**. Every `cli` and `sti` the game executes is trapped, and HDPMI32i
does it on the game's behalf. The game only *borrows* the interrupt flag.

Usually nobody notices. But HDPMI32i doesn't handle every borrowed `sti`
correctly. If an interrupt handler switches interrupts back on **one
instruction before it returns**, HDPMI32i can crash while doing that `sti`.
The game freezes, the keyboard is dead, and it never comes back. I call this
**Borrowed Interrupt Flag**.

This isn't a fault of the 86Duino's hardware. It happens on any PC that runs
the game under HDPMI32i, and it can be reproduced in QEMU. It gets its own
page because SBEMU is the best way to get music on the 86Duino, so the
HDPMI32i setup is part of daily life here.

| Face | What the program does | What HDPMI32i does |
|---|---|---|
| **The Last-Second STI** | Its interrupt handler ends with `sti` followed directly by `iret` | Faults inside its own ring-0 code while doing the `sti`; the machine ends up waiting forever in the BIOS for a key that never comes |

The diagnosis and the patch on this page are by **Claude** (Anthropic's Claude
Opus 5.5, working in Claude Code). I tested the patched game on the real
86Duino.

This is a sister page of [Tick Starvation](tick-starvation.md),
[Clock Mirage](clock-mirage.md), [Wet Ink](wet-ink.md),
[Trap Storm](trap-storm.md),
[Ghost Frame](ghost-frame.md), [Broken Record](broken-record.md),
[Sealed Gate](sealed-gate.md),
[Side Door](side-door.md),
[Sixteen-Bit Exile](sixteen-bit-exile.md) and [Late Echo](late-echo.md); all eleven are
listed in the [overview of the game fixes](86duino-game-fixes.md). The first three are about the 86Duino's BIOS,
timer and CPU. This one is about the software stack that gives the 86Duino its
sound. Trap Storm is where the two meet: the same software stack, overloading
the 86Duino's keyboard emulation.

## Games

| Game | Year | Files patched | Face | Fix | Status on 86Duino |
|---|---|---|---|---|---|
| [Wacky Wheels](#case-1-wacky-wheels-1994) | 1994 | `WW.EXE` (v1.1 shareware) | The Last-Second STI | 1 byte | ✅ Playable: a full race with AdLib music. The later keyboard freeze on the leaderboard was a second, separate issue, [Trap Storm](trap-storm.md#case-1-wacky-wheels-1994); with both fixes a whole season plays. |
| *next game here* | | | | | |

**Suspects (not tested).** Any protected-mode game whose own interrupt
handlers end with `sti` + `iret`. Wacky Wheels' keyboard handler is
hand-written assembly. Its sound code is the Apogee Sound System, which is
also in *Rise of the Triad*, *Duke Nukem 3D* and *Shadow Warrior*. The faulty
handler belongs to the game, though, not to the sound library. See
[Recipe for the next game](#recipe-for-the-next-game) for how to look.

---

## The original request

> please look into the directory WACKY ... for this one, I want to configure
> SBEMU and in the setup everything works well, the adlib music plays very
> well but WW.EXE dies during the startup... it works well without music, so I
> want you to look at WW.EXE and figure out why it dies.

> it starts up then it freezes and it is not reactive for keys.

After the first (wrong) patch:

> it dies in a very similar error. I hear no music, it stops being reactive
> and when I am tapping the enter the top of the screen is filled with
> artifacts

After the fix:

> I was able to play a full race, and although the keyboard freezed again at
> the result screen, I still consider it success.

---

## Background

### Why SBEMU needs HDPMI32i

A DOS game talks to a sound card through I/O ports: `388h`–`389h` for the
AdLib FM chip, `220h`–`22Fh` for the Sound Blaster. SBEMU has to see every one
of those port accesses. How it catches them depends on the kind of program:

- **Real-mode games** run in V86 mode under JEMMEX. The `QPIEMU.DLL` module
  traps their port accesses.
- **Protected-mode games** (DOS/4G, DOS/4GW, DOS/32A and other DOS extenders)
  run as clients of a DPMI host. With **HDPMI32i** as the host, their port
  accesses are trapped too. That's what SBEMU's start-up line "Protected mode
  support: enabled" means.

SBEMU is itself a 32-bit protected-mode program, and it stays resident as a
client of HDPMI32i. Without HDPMI32i it doesn't load at all. Plain HDPMI32
(without the "i") isn't enough, because it doesn't trap the ports. And a game
whose extender bypasses HDPMI gets no sound: CauseWay in Daggerfall did that
until `SET CAUSEWAY=DPMI`.

### The borrowed flag

The `i` in HDPMI32i stands for its I/O mode. It runs its clients with **IOPL
0** (the CPU's I/O privilege level). At IOPL 0 a ring-3 program may not
execute `in` or `out` on ports listed in the trap bitmap, nor `cli` or `sti`.
Each of those instructions raises a general-protection fault (#GP). HDPMI32i
catches the fault and then:

- for a trapped port, calls SBEMU's handler;
- for `cli` or `sti`, changes the interrupt flag on the program's behalf and
  continues after the instruction.

This happens hundreds of times a second in a game with music. For example, a
sound library that writes to the AdLib chip does `pushf / cli … popf` around
every register write.

### The Last-Second STI

A typical 1990s keyboard handler ends like this:

```
        mov  al, 20h
        out  20h, al        ; end of interrupt to the PIC
        pop  ...            ; restore registers
        sti                 ; interrupts back on
        iret                ; return
```

The `sti` is redundant. `iret` restores the interrupt flag that was saved when
the interrupt arrived, and that flag was on. On a normal PC the pair is
harmless. Under HDPMI32i the `sti` is a borrowed flag, and it is the last
instruction before the handler leaves the interrupt. In Wacky Wheels,
HDPMI32i crashes at exactly that point.

---

## Case 1: Wacky Wheels (1994)

Beavis Soft / Apogee, version 1.1 shareware. `WW.EXE` is a Watcom C program
bound to the DOS/4G Professional extender, with the Apogee Sound System for
sound. The setup was music: AdLib, sound effects: PC speaker, run under
JEMMEX + HDPMI32i + SBEMU.

| File | Size | MD5 |
|---|---|---|
| `WW.EXE` (original, v1.1) | 650 437 | `c8232cbd3b985cac9c9a748d9e305ec9` |
| `WW.EXE` (fixed, `WW_NOSTI.EXE`) | 650 437 | `93be7fb9f53d7e5846e5c5cc03c0b826` |

All tools mentioned here are in [`tools/`](tools/).

### Step 1: A wrong first guess

`SETUP.EXE` played the AdLib music fine under SBEMU, and the game only froze
with music on. So the music code was the first suspect. In the Apogee Sound
System:

- the timer handler runs all its tasks with interrupts off;
- each AdLib register write costs 43 port accesses (2 writes plus 41 dummy
  reads used as a delay), and SBEMU traps every one of them.

That looked like [Tick Starvation](tick-starvation.md) in a new form: the timer
handler eating the whole CPU. A patch that removed the dummy reads
(`WW_NODLY.EXE`) **made no difference** on the 86Duino. The theory was wrong.

### Step 2: The photo

The second report came with a photo. The title screen ("WACKY WHEELS VERSION
1.1 / PRESS FIRE") had rows of yellow vertical dashes over its top half. They
appeared when Enter was tapped. That made the title screen the place to look.

### Step 3: Reproducing it in QEMU

[`qemu_sbemu.sh`](tools/qemu_sbemu.sh) boots a DOS floppy in QEMU with an
emulated Intel HD Audio card. It loads JEMMEX, `JLOAD QPIEMU.DLL`,
`HDPMI32i -x` and SBEMU (all from SBEMU 1.0.0-beta.5's `SBEMU.zip`), then
starts the game with the user's own `WACKY.CFG`.
[`qemu_mon.py`](tools/qemu_mon.py) sends keys and takes screenshots. The sound
goes to a WAV file, so you can check whether music plays.

- Left alone, the game ran its attract loop with music.
- **One press of Enter on the title screen gave exactly the photo**: the
  yellow dashes, and then nothing.
- The same happened **with music switched off**, and even with **HDPMI32i
  alone, without SBEMU**.
- Slowing the emulated CPU down (`-icount`) didn't matter.

So the freeze needs only two things: HDPMI32i and a keypress. Music turned
out not to be the cause, at least in QEMU.

### Step 4: Where the machine is

`info registers` in the QEMU monitor, sampled many times, found the CPU almost
always idle:

- JEMMEX was emulating a `hlt` that came from BIOS code in V86 mode: the
  BIOS's "wait for an interrupt" loop.
- It was reached through DOS, so something was waiting for a key in the BIOS
  keyboard buffer.
- The game has its own keyboard handler, which never passes keys on to the
  BIOS. So that key never comes.

The yellow dashes are a side effect: the screen transition after Enter
starts, and the wait cuts it off.

### Step 5: Catching the crash

The QEMU monitor's `log int` records every interrupt and exception. I turned
it on just before pressing Enter:

```
v=09 cpl=3  IP=027f:003447ae                 keyboard IRQ; game code running
v=0d cpl=3  IP=027f:0034d946  (out 20h)      trapped port write: normal
v=0d cpl=3  IP=027f:0034d9e9  (sti)          trapped sti: normal so far
v=0d e=6830 cpl=0  IP=0020:000010fd          #GP inside HDPMI32i's own ring-0 code
v=16 cpl=3  IP=0453:00000852                 an INT 16h from real mode follows
v=0e cpl=3  IP=f000:71d03246                 jump to a garbage address
… then the BIOS wait loop forever
```

After subtracting the load offset, the addresses map to the game's keyboard
handler at linear `0x40907`. Its last instructions are:

```
409DB  66 C7 05 .. .. .. ..  mov  word [busy flag], 0
409E4  59                    pop  ecx
409E5  5F                    pop  edi
409E6  1F                    pop  ds
409E7  66 61                 popa (16-bit)
409E9  FB                    sti                   <- HDPMI32i faults here
409EA  CF                    iretd
```

While doing the borrowed `sti`, HDPMI32i raised a #GP in its own ring-0 code.
The error code `6830h` is the low word of the game's stack pointer at that
moment (`ESP = 6830h`), used as if it were a selector. From there the system
derails. I didn't trace the bug inside HDPMI32i further. It is enough to know
that this `sti` is the trigger.

### Step 6: The fix

The `sti` isn't needed: `iretd` restores the interrupt flag from the stack.
Replace it with a `nop`:

| Linear | File offset | Original | Patched |
|---|---|---|---|
| `0x409E9` | `0x7E63D` | `FB` (`sti`) | `90` (`nop`) |

```
python3 tools/patch.py WW.EXE WW_NOSTI.EXE 0x7E63D:FB:90
```

`le_load.py WW.EXE off 0x409e9` confirms the offset and that no fixup touches
the byte. This is the only `sti` + `iret` pair in the whole program.

### Step 7: Tests

| Build | QEMU, HDPMI32i only | QEMU, HDPMI32i + SBEMU + AdLib music | 86Duino, SBEMU + AdLib music |
|---|---|---|---|
| Original | Freeze on the first key | Freeze on the first key | Freeze at the title, no music |
| `WW_NODLY.EXE` (Step 1) | — | — | Same freeze |
| `WW_NOSTI.EXE` | ✅ Enter on the title works | ✅ Music plays; title, intro, menu and vehicle choice react to keys | ✅ A full race with music; the keyboard froze at the result screen |

### Loose ends

- **Why "works without music" on the 86Duino?** In QEMU the original freezes
  on the first key even with music off. On the 86Duino it doesn't. My guess,
  **not verified**: the crash only happens when another interrupt is already
  waiting at the moment of the borrowed `sti`. With music the timer runs at
  280 Hz instead of 140 Hz, and every AdLib write is trapped, so that
  coincidence becomes much more likely.
- **The result screen.** After a full race, the keyboard froze again, on the
  leaderboard. That turned out to be a different issue:
  [Trap Storm](trap-storm.md#case-1-wacky-wheels-1994). The game issues so
  many trapped instructions (AdLib delay reads, `cli`/`sti` in its palette
  code) that the 86Duino's USB keyboard emulation dies. Its fix goes on top of
  this one, and the full patch command is on that page.
- **The HDPMI32i version.** The QEMU tests used the HDPMI32i from SBEMU
  1.0.0-beta.5's `SBEMU.zip`. Whether newer HDPMI versions have the same bug
  hasn't been checked.

---

## Recipe for the next game

1. **The symptom.** A protected-mode game freezes under HDPMI32i + SBEMU, the
   keyboard is dead, and it doesn't recover. Without HDPMI32i (and therefore
   without SBEMU) it runs.
2. **Reproduce it in QEMU.** Use [`qemu_sbemu.sh`](tools/qemu_sbemu.sh). If it
   freezes there too, it is the software stack, not the 86Duino. Try
   HDPMI32i alone, without SBEMU, to narrow it down.
3. **Trace it.** Use `qemu_mon.py 'log int' 'sendkey ret' 'sleep 3' 'log none'`
   with `EXTRA="-D DIR/out/int.log"`. Look for a `v=0d` with **`cpl=0`**: a
   fault inside the DPMI host itself. The `v=0d cpl=3` line just before it
   points at the game instruction HDPMI32i was emulating.
4. **Look for the pattern in the game.** Search the code for `FB CF`
   (`sti; iret`). More generally, check any `sti`, `cli` or `popf` right
   before an interrupt handler returns.
5. **Fix:** if the `sti` directly precedes `iret`, replace it with `90`. The
   `iret` restores the flag anyway. Use `le_load.py off` to get the file
   offset and to make sure no fixup touches the byte.
6. **Test** in QEMU first, then on the 86Duino with music on. Press keys
   early and often: the first keypress is what triggers it.

## Tools

In [`tools/`](tools/):

| File | What it does |
|---|---|
| `qemu_sbemu.sh` | Boots a DOS floppy in QEMU with an HD Audio card and a host folder as drive C:, for testing games under JEMMEX + HDPMI32i + SBEMU. Records the sound to a WAV file. You supply the DOS boot floppy and `SBEMU.zip`. |
| `qemu_mon.py` | Drives the QEMU monitor: keys (with hold time), screenshots, `info irq`, `info registers`, `log int`. |
| `fat12.py` | Lists, adds and deletes files on a FAT12 floppy image, to write the boot floppy's `CONFIG.SYS` and `AUTOEXEC.BAT` without mtools. |
| `le_load.py` | Reads LE executables (DOS/4G, DOS/4GW, CauseWay): object list, object dumps with relocations applied, VA → file offset, fixup check. |
| `patch.py` | Applies `OFFSET:OLD:NEW` byte patches, checking the old bytes first. |

Notes for the QEMU setup:

- The AC97 card gave no audio in QEMU; the HD Audio card works.
- QEMU's `fat:rw:` folder drive can lose files a DOS program writes (Wacky
  Wheels' `SETUP.EXE` lost `WACKY.CFG`). Prepare configuration files on the
  host instead. In Wacky Wheels' `WACKY.CFG`, the sound-effects device is the
  dword at `0x786` (7 = PC speaker) and the music device is the dword at
  `0x78A` (2 = AdLib, −1 = none).
- Key presses need a hold time (`sendkey down 600`) when the game polls the
  keys slowly.

No game files are included in this repository. Wacky Wheels v1.1 is shareware.

## Sources

- [SBEMU](https://github.com/crazii/SBEMU), release 1.0.0-beta.5: `SBEMU.zip`
  with JEMMEX, JLOAD, `QPIEMU.DLL`, HDPMI32i and SBEMU.
- [HX DOS Extender / HDPMI](https://github.com/Baron-von-Riedesel/HX), by
  Japheth: the DPMI host HDPMI32 and its I/O-trapping variant HDPMI32i.
- [Intel 64 and IA-32 Architectures Software Developer's Manuals](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html):
  Vol. 1, "I/O Privilege Level", and Vol. 2, `STI`, `CLI` and `IRET` (which
  instructions fault at IOPL 0).
- [Ralf Brown's Interrupt List](https://www.ctyme.com/rbrown.htm): DPMI
  services.
