# Side Door: when a game slips past SBEMU without a word

SBEMU gives the 86Duino a Sound Blaster by **listening at the doors**: every
time a game talks to the sound card's ports, the DPMI host HDPMI32i (for
protected-mode games) or JEMMEX with QPIEMU (for real-mode games) catches the
access and hands it to SBEMU, which answers like a real card and plays the
sound through the 86Duino's own audio chip.

Some DOS extenders of 1994–1995 don't come in through that door. They look
for a DPMI host, find HDPMI32i, and **decide not to use it**, because no
Windows is running. Instead they take VCPI, the older interface JEMMEX
offers, build their own protected mode and run the game in it with full
rights. From there the game writes straight to the sound card's ports, and
nobody is listening: there is no real Sound Blaster in the 86Duino, and
SBEMU never hears a thing. The game runs perfectly, in complete silence. I
call this **Side Door**.

| Face | What you see | What is really there |
|---|---|---|
| **The Silent Cockpit** | Under SBEMU the game starts, flies and plays as usual, but there is no sound at all: no music, no effects, no error message | The game's DOS extender uses the DPMI host only when Windows is running; on plain DOS it prefers JEMMEX's VCPI, runs the game at the highest privilege level, and its sound card I/O goes past HDPMI32i, so SBEMU never sees it |

The diagnosis and the patch on this page are by **Claude** (Anthropic's Claude
Opus 5.5, working in Claude Code). I tested them on the real 86Duino.

This is a sister page of [Tick Starvation](tick-starvation.md),
[Clock Mirage](clock-mirage.md), [Wet Ink](wet-ink.md),
[Borrowed Interrupt Flag](borrowed-interrupt-flag.md),
[Trap Storm](trap-storm.md), [Ghost Frame](ghost-frame.md),
[Broken Record](broken-record.md),
[Sealed Gate](sealed-gate.md),
[Sixteen-Bit Exile](sixteen-bit-exile.md) and [Late Echo](late-echo.md); all eleven are listed in the [overview of the game fixes](86duino-game-fixes.md). Like Borrowed Interrupt
Flag and Sealed Gate, this one is a software-stack issue: it shows up in
QEMU just the same, as soon as SBEMU is loaded.

## Games

| Game | Year | Files patched | Faces | Fix | Status on 86Duino |
|---|---|---|---|---|---|
| [Comanche 2.0](#case-1-comanche-20-1995) | 1995 | `COMANCHE.EXE` (10 Aug 1995) | The Silent Cockpit | 1 byte | ✅ "It works very well" |
| *next game here* | | | | | |

**Suspects (not tested).** Other NovaLogic games of the same years that
carry the same DOS extender (its copyright line: *"DOS extender Copyright
1991-1994 by Doug Huffman"*). Werewolf, the companion game sold on the same
CD as Comanche 2.0, very likely does; Armored Fist and Comanche: Maximum
Overkill may. The giveaway: the game runs fine under SBEMU but makes no
sound at all, and it would have sound in a Windows 95 DOS box.

---

## The original request

> please get back to the X86Duino project and work on the game in directory
> COMANCH2. I didn't experience a failure, it starts up, however, I could not
> make it work with SBEMU.

After the fix: *"I've tested it in x86Duino and I confirm it works very
well."*

---

## Background

### How SBEMU hears a game

The 86Duino has no Sound Blaster. SBEMU makes one up: it asks to be told
whenever a program touches the Sound Blaster's ports (`220h`–`22Fh`), the
AdLib ports (`388h`–`38Bh`) and the DMA controller, answers the way a real
card would, and mixes the sound out through the 86Duino's audio hardware.

Being told depends on where the program runs:

- **Real-mode programs** run in virtual-8086 mode under JEMMEX. With
  `JLOAD QPIEMU.DLL`, JEMMEX traps their port accesses and passes them on.
- **Protected-mode programs** run as clients of the DPMI host HDPMI32i.
  HDPMI32i runs its clients at the lowest privilege level (ring 3, IOPL 0),
  where every port access in the I/O permission map raises a trap, and
  passes the trapped ones to SBEMU.

Either way, someone with more privileges than the game stands at the door.

### Three ways into protected mode

A 1995 DOS extender has three ways to get a game into 32-bit protected mode:

| Way | When | Who is in charge |
|---|---|---|
| **DPMI** | A DPMI host is running (Windows, HDPMI32i, CWSDPMI) | The host; the game is its client, at ring 3 |
| **VCPI** | A memory manager with VCPI is running (EMM386, JEMMEX, QEMM) | The extender itself: VCPI only lends it the switch into protected mode, then the extender sets up its own tables and runs at ring 0 |
| **Raw** | Plain DOS with at most HIMEM.SYS | The extender itself |

Under SBEMU the machine has both: JEMMEX offers VCPI (HDPMI32i itself sits
on top of it), and HDPMI32i offers DPMI. Most extenders try DPMI first.
SBEMU depends on that.

---

## Case 1: Comanche 2.0 (1995)

NovaLogic's helicopter simulator, from the *Werewolf vs. Comanche 2.0* CD.
`COMANCHE.EXE` is a 32-bit program with NovaLogic's own DOS extender by Doug
Huffman bound to its front. Sound is set up with `GAMESET.EXE`, which writes
`GAMESET.CFG`; on the 86Duino it is set to a Sound Blaster at `220h`, IRQ 5,
DMA 1, the same as SBEMU.

| File | Size | MD5 |
|---|---|---|
| `COMANCHE.EXE` (original, 10 Aug 1995) | 551 754 | `75bee27901add2f0b76faad612db7c90` |
| `COMANCHE.EXE` fixed (`C2DPMI.EXE`) | 551 754 | `22a5cbebc0e25ae80ab80fda1a8b5d10` |

The 86Duino setup (boot menu entry *S*): `HIMEMX /MAX=32768`,
`JEMM386 EMX NOA20 NOHI I=TEST X=TEST`, `JLOAD QPIEMU.DLL`,
`HDPMI32I -r -x`, `SBEMU /i5`, `SET CAUSEWAY=DPMI`, `CTMOUSE /W`,
`86CRSBAR N`.

### Step 1: The symptom

The game starts, the menus work, it flies. There is no error and no
complaint about the sound card. There is just no sound.

In QEMU with the same driver stack (JEMMEX, QPIEMU, HDPMI32i, SBEMU with an
emulated HD Audio card, see [`qemu_sbemu.sh`](tools/qemu_sbemu.sh)) and the
user's own `GAMESET.CFG`, the original game ran through its intro and menus
into the flight demo while QEMU recorded the sound card's output: **74 seconds
of digital zero**.

### Step 2: The extender's choice

The extender's real-mode start-up code is short, and sits at the very front
of the file (file offsets `0x182`–`0x2A9`). It decides like this:

| Offset | Code | Question | If yes | If no |
|---|---|---|---|---|
| `0x1A1` | `INT 2Fh`, `AX=1687h` | Is a DPMI host installed? | next question | VCPI or raw |
| `0x1AA` | `INT 2Fh`, `AX=1600h`, `test al,7Fh` | Is **Windows** running in enhanced mode? | **DPMI** (jump to `0x1BA`) | VCPI or raw |
| `0x207` | `EMMXXXX0`, `INT 67h`, `AX=DE00h` | Is there VCPI? | **VCPI** | DPMI if the CPU is in V86 mode, raw if not |

So a DPMI host is used in only two situations: under Windows, or in V86
mode without any VCPI. Under SBEMU neither is true. HDPMI32i is found and
ignored, and the extender goes in through VCPI.

That was a sensible choice in 1995. Under plain DOS with EMM386, VCPI gave
the game the whole machine at ring 0, which is faster than running as a DPMI
client. Windows was the one place where VCPI wasn't available, so that was
the case it had to handle.

### Step 3: Why VCPI means silence

Through VCPI, the extender builds its own descriptor tables, interrupt table
and page tables, and runs the game at **ring 0**. At ring 0 every `in` and
`out` goes straight to the hardware. HDPMI32i is never involved, so its
I/O traps never fire. QPIEMU only watches code running in V86 mode, and the
game no longer runs there. The game's writes to port `22Ch` go to an empty
bus, and the sound is lost without any error.

### Step 4: The fix

The Windows test ends in a conditional jump: "if Windows is running, go to
the DPMI path". Making the jump unconditional sends the extender down the
DPMI path whenever a DPMI host is installed:

| File offset | Original | New |
|---|---|---|
| `0x1B1` | `75 07` (`jne 0x1BA`) | `EB 07` (`jmp 0x1BA`) |

```
python3 tools/patch.py COMANCHE.EXE C2DPMI.EXE 0x1B1:75:EB
```

Nothing else changes. Without a DPMI host the first question still sends the
extender to VCPI or raw mode as before, so `C2DPMI.EXE` also runs without
SBEMU. Under HDPMI32i the game now runs as an ordinary DPMI client at
ring 3, its sound card I/O is trapped, and SBEMU plays it.

Start `C2DPMI.EXE` in place of `COMANCHE.EXE`, under the boot *S* setup.

### Step 5: Tests

| Where | Build | Result |
|---|---|---|
| QEMU, boot *S* stack | `COMANCHE.EXE` | Intro, menus, flight demo; silent (74 s of zero samples) |
| QEMU, boot *S* stack | `C2DPMI.EXE` | Intro, *Select Pilot*, main menu, flight demo, training mission *Battle Sight Zero*, Hellfire missiles fired; sound throughout, keyboard fine |
| 86Duino, boot *S* | `COMANCHE.EXE` | Runs, no sound |
| 86Duino, boot *S* | `C2DPMI.EXE` | ✅ "It works very well" |

### Loose ends

- **Multiplayer** (network, modem and serial-cable play) wasn't tested; not
  needed for now.
- **Werewolf**, the other game on the CD, isn't in this copy. If it has the
  same extender, the same byte (at whatever offset it lands) should fix it.

---

## Recipe for the next game

1. **Is it Side Door?** The game runs normally under SBEMU but is completely
   silent, without complaining about the sound card. Check that it's a
   protected-mode game and that its sound settings match SBEMU's.
2. **Look at the extender's start-up code** (the first few KB of the EXE,
   16-bit `objdump -D -b binary -mi8086`). Look for `INT 2Fh` with
   `AX=1687h` (DPMI present?) and `AX=1600h` (Windows running?), and for
   `INT 67h` with `AX=DE00h` (VCPI present?). If the DPMI path is taken
   only when Windows answers, it's the Side Door.
3. **Patch the decision**, so that a DPMI host is used whenever one is
   installed. For this extender the byte sequence to look for is
   `B8 00 16 CD 2F A8 7F 75`; change the last byte, `75`, to `EB`.
4. **Test under SBEMU** in QEMU with [`qemu_sbemu.sh`](tools/qemu_sbemu.sh):
   the recorded WAV file goes from zeros to sound. Then on the 86Duino.
   Now that the game runs under HDPMI32i for the first time, watch for the
   problems that brings: [Borrowed Interrupt Flag](borrowed-interrupt-flag.md),
   [Trap Storm](trap-storm.md), [Sealed Gate](sealed-gate.md).

---

## Tools

| File | What it does |
|---|---|
| `patch.py` | Applies the one-byte patch, checking the original byte first. |
| `qemu_sbemu.sh`, `qemu_mon.py`, `wavstat.py` | The QEMU test machine, its monitor driver, and loudness over time of its sound recording (see the [tools in the overview of the game fixes](86duino-game-fixes.md#tools)). |

## Sources

- Disassembly of the extender's real-mode start-up code in `COMANCHE.EXE`
  (16-bit `objdump`).
- QEMU sound recordings of the original and the patched game under JEMMEX,
  HDPMI32i and SBEMU 1.0.0-beta.5.
- DPMI 0.9 specification: `INT 2Fh` function `1687h` (get mode switch entry
  point); Windows `INT 2Fh` function `1600h` (enhanced mode installation
  check).
- VCPI specification: `INT 67h` function `DE00h` (VCPI presence check).
