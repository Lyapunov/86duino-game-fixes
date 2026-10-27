# Late Echo: when the game rings the doorbell and SBEMU answers too late

Many DOS sound drivers find the Sound Blaster's IRQ by themselves. They hook
each likely IRQ in turn, send the card DSP command `F2h` ("raise an interrupt
now"), and wait a moment to see which handler gets called. A real card
answers within microseconds.

SBEMU can't answer right away. It raises the emulated IRQ only from inside
its own interrupt from the real sound hardware, which comes along every few
milliseconds. To cover the gap it holds the CPU for a while after `F2h`,
hoping the hardware interrupt falls inside that time. A driver whose wait is
short, or that polls the wrong way, hears the echo too late or not at all.
It concludes there's no IRQ, and the sound is switched off. I call this
**Late Echo**.

| Face | What you see | What is really there |
|---|---|---|
| **The Unanswered Doorbell** | Under SBEMU the game says its sound driver failed (*"MUSIC DRIVER ERROR"*, *"EFFECTS DRIVER ERROR"*) and runs silent | The driver's IRQ autodetection sends `F2h` for IRQ 7, 5, 2 and 3 in turn and polls briefly for its test handler; SBEMU's emulated IRQ never arrives in time, so every IRQ fails the test |

The diagnosis and the patches on this page are by **Claude** (Anthropic's
Claude Opus 5.5, working in Claude Code). I tested them on the real 86Duino.

This is a sister page of [Tick Starvation](tick-starvation.md),
[Clock Mirage](clock-mirage.md), [Wet Ink](wet-ink.md),
[Borrowed Interrupt Flag](borrowed-interrupt-flag.md),
[Trap Storm](trap-storm.md), [Ghost Frame](ghost-frame.md),
[Broken Record](broken-record.md), [Sealed Gate](sealed-gate.md),
[Side Door](side-door.md) and [Sixteen-Bit Exile](sixteen-bit-exile.md); all
eleven are listed in the [overview of the game fixes](86duino-game-fixes.md). Like Side Door, this one
is a software-stack issue: it shows up in QEMU exactly as on the 86Duino.

## Games

| Game | Year | Files patched | Faces | Fix | Status on 86Duino |
|---|---|---|---|---|---|
| [Lemmings 3D](#case-1-lemmings-3d-1995) | 1995 | `SOUND\DRIVERS\SBL0.BIN` (plus `L3D.EXE` and `SETUP.EXE`, only to keep the settings in the game folder) | The Unanswered Doorbell | Fixed port, IRQ and DMA instead of autodetection; the [Broken Record](broken-record.md#case-4-lemmings-3d-1995) fix from Mortal Kombat II on top | ✅ "It works with sound" |
| *next game here* | | | | | |

**Suspects (not tested).** Any game whose sound driver autodetects the IRQ
with DSP command `F2h` and gives up quickly. Other games with the *Sound
Images Generation 2* drivers (Tony Williams, 1992–95; Mortal Kombat II's
`SBL.BIN` is one) do it whenever the game passes port 0. Drivers that read
the port, IRQ and DMA channel from the `BLASTER` variable or a setup file
instead never ring the doorbell.

**A related remark: drivers that test the IRQ they are given.** Some drivers
don't search, but check the IRQ from their settings with the same doorbell,
and switch the sound off if it doesn't ring. Under SBEMU that IRQ must be
SBEMU's. Dune (Cryo, 1992) is one: its driver plays a single byte by DMA and
waits briefly for the interrupt on the IRQ from the command line. Installed
with the usual `SDB2207` (port 220h, IRQ 7) it is silent under `SBEMU /i5`;
with `SDB2205` it plays. No patch needed, just the right setting.

---

## The original request

> Okay, look into directory LEM3D, when I first tried it it was very broken,
> but with GHOSTFIX it starts up and works very well. However, one thing is
> still a bit off, it has no sound, please, make it work with SBEMU.

The "very broken" part was [Ghost Frame](ghost-frame.md#case-3-lemmings-3d-1995).
On the way:

> using C:\LM3D.CD is rather clumsy. Isn't there a way to have a config file
> in the very same directory?

After the fix: *"it works with sound on x86Duino"*.

---

## Background

### How a driver finds the Sound Blaster's IRQ

The Sound Blaster's IRQ (2, 3, 5, 7 or 10) is set with jumpers or by its
setup program, and the game has to know it. Many drivers find it by
experiment: for each candidate IRQ, point the interrupt vector at a tiny
handler that sets a flag, unmask the IRQ, send DSP command `F2h`, and wait for
the flag. On real hardware the card raises its interrupt line immediately.

### Why SBEMU answers late

SBEMU emulates the card in software, inside the interrupt handler of the
86Duino's real sound hardware. It can only call a game's interrupt handler
from that context. So on `F2h` it notes "raise an IRQ", busy-waits for a
while, and raises the emulated IRQ at the next real sound interrupt
(`sbemu.c`, `SBEMU_DELAY_FOR_IRQ`; the source comment calls it a hack for
exactly this case). Whether the game's handler is still installed and
watching by then depends on how long the driver waits, and how it waits.

---

## Case 1: Lemmings 3D (1995)

Psygnosis / Clockwork Games, *3D Lemmings*, version 1.13 (26 July 1995).
`L3D.EXE` is a real-mode program that needs EMS. It needs
[GHOSTFIX](ghost-frame.md#case-3-lemmings-3d-1995) on the 86Duino, and a
mouse driver (without one it stops with *"Mouse NOT detected."*). Its sound
drivers are separate files in `SOUND\DRIVERS`; the Sound Blaster one,
`SBL0.BIN`, is *"Soundblaster multi-channel, Sound Images Generation 2 sound
drivers (c) 1992-94 Tony Williams/Sound Images v1.11x"*, the same family as
Mortal Kombat II's `SBL.BIN`.

| File | Size | MD5 |
|---|---|---|
| `L3D.EXE` (original) | 152 397 | `659821374a6f4d0ecf743bbfa10e27d6` |
| `L3D.EXE` (settings in the game folder) | 152 397 | `1103d8cb2eb90bb3a51bd6e239448364` |
| `SETUP.EXE` (original) | 28 692 | `6c196d40245d1744473518684da5c586` |
| `SETUP.EXE` (settings in the game folder) | 28 692 | `499f53aad14e2acd604e9af76e116f91` |
| `SOUND\DRIVERS\SBL0.BIN` (original) | 11 336 | `dee0bc63819bd0c139927771ebfa7a9b` |
| `SBL0FIX.BIN` (port 220h, IRQ 5, DMA 1) | 11 336 | `4e0e38d907d56bd0c0a69b9f7bc906d4` |

The 86Duino setup (boot menu entry *S*): `HIMEMX /MAX=32768`,
`JEMM386 EMX NOA20 NOHI I=TEST X=TEST`, `JLOAD QPIEMU.DLL`,
`HDPMI32I -r -x`, `SBEMU /i5`, `SET CAUSEWAY=DPMI`, `CTMOUSE /W`,
`86CRSBAR N`.

### Step 1: Sound "None"

The first reason for the silence wasn't technical. The game reads its
settings from a fixed path, **`C:\LM3D.CD\LM3D.CFG`**, the folder the CD
installer created, and `SETUP.EXE` writes them there. Without that file,
music and sound effects are both "None". SETUP doesn't ask for a port, IRQ or
DMA channel, and the 58-byte file doesn't hold any: it only says which card
plays the music and which the effects.

### Step 2: The Unanswered Doorbell

With Sound Blaster chosen for both, the game starts with:

```
MUSIC DRIVER ERROR - MUSIC DISABLED
EFFECTS DRIVER ERROR - EFFECTS DISABLED
```

`SBL0.BIN` is called through one entry point with a function number in `AH`;
function 0, init (`06A2h`), takes the port in `DX`, the IRQ in `CL` and the DMA
channel in `CH`. **The game always passes port 0**, which means "autodetect":

1. **The port** (`0790h`): for each of `220h`–`260h`, look for the OPL chip at
   base + 8. SBEMU emulates it, so `220h` is found.
2. **The IRQ** (`0931h`): for IRQ 7, 5, 2 and 3 in turn, hook the vector,
   unmask the IRQ, send `F2h`, then read port `228h` up to 65 535 times,
   waiting for the test handler (`0B36h`) to set a flag. If no IRQ answers,
   init returns error 2.

A memory dump after the failure showed port `220h` in the driver, IRQ 0 and
no DSP version: it had stopped at step 2. With GDB on QEMU's GDB stub, a
breakpoint after the polling loop (`0974h`) showed the IRQ 5 test ending with
the counter run out and the flag still 0. The test handler was never
called.

### Step 3: Skipping the doorbell

The game can't be told the IRQ, so the driver is told instead. Port 0 now
means "port 220h, IRQ 5, DMA 1", SBEMU's settings on the 86Duino:

| Offset | Original | New |
|---|---|---|
| `06AEh` | `call 0790h` / `call 0753h` / `call 0931h` (autodetect) | `mov dx,220h` / `mov cx,0105h` / `jmp 06C0h` (the "port given" path) |

`lem3d_sbl_build.py` takes other values if your SBEMU is set up differently
(8-bit DMA channels 0, 1 or 3; IRQ 2, 3, 5 or 7).

With that, the driver started, and in QEMU the title music played and the
game reached its menu with sound.

### Step 4: The Broken Record, before it breaks

This driver family has a second weakness on the 86Duino: it mixes the sound
effects only in its IRQ handler, and under SBEMU on the 86Duino those IRQs
stop coming after a few. Mortal Kombat II's effects turned into
"e‑e‑e" because of it ([Broken Record, Case 3](broken-record.md#case-3-mortal-kombat-ii-1994)).
`SBL0.BIN` is a slightly later build of the same code, with the same
structure at shifted addresses, so the MK2 fix was ported before the first
test on the hardware. See
[Broken Record, Case 4](broken-record.md#case-4-lemmings-3d-1995).

### Step 5: The settings in the game folder

The fixed path `C:\LM3D.CD` is clumsy on a machine without the CD install, and
the saved progress lives there too. Both programs carry the paths as plain
strings, so they were made relative (each string keeps its length, padded
with zeros):

| File | Offset | Original | New |
|---|---|---|---|
| `L3D.EXE` | `0x10B0E` | `C:\LM3D.CD\LM3D.CFG` | `LM3D.CFG` |
| `L3D.EXE` | `0x1DB20` | `C:\LM3D.CD\LM3D.SAV` | `LM3D.SAV` |
| `SETUP.EXE` | `0x6933` | `c:\lm3d.cd\lm3d.cfg` | `lm3d.cfg` |
| `SETUP.EXE` | `0x6928` | `c:\lm3d.cd` (the folder SETUP creates first) | `.` |

Start both from the game folder. An existing `C:\LM3D.CD\LM3D.SAV` can be
copied into the game folder to keep the progress.

### Step 6: Building and installing

```
python3 tools/lem3d_sbl_build.py SOUND/DRIVERS/SBL0.BIN SBL0FIX.BIN      (or ... SBL0FIX.BIN 220 5 1)
python3 tools/lem3d_local.py GAMEDIR OUTDIR
```

Both check the MD5 of the originals. Then, keeping the originals:

1. Copy `SBL0FIX.BIN` over `SOUND\DRIVERS\SBL0.BIN`.
2. Copy the new `L3D.EXE` and `SETUP.EXE` into the game folder.
3. Run `SETUP` from the game folder: Setup Hardware → Sound, Music Card and
   Sound Card both "SoundBlaster", and save on exit.
4. With CTMOUSE loaded:

```
GHOSTFIX
L3D
GHOSTFIX /U
```

### Step 7: Tests

| Where | Setup | Result |
|---|---|---|
| QEMU, boot *S* stack + GHOSTFIX | no settings file | Silent; SETUP shows Music "None", Effects "None" |
| QEMU | Sound Blaster chosen, original driver | *"MUSIC DRIVER ERROR"*, *"EFFECTS DRIVER ERROR"*; GDB: the IRQ test runs out, handler never called |
| QEMU | `SBL0FIX.BIN` | Title music, menu, practice level with sound; no stuck loop in the recording |
| QEMU | counting build, IRQ handler's call to the fix removed | About 25 mixes a second from the timer tick alone, one per buffer half |
| QEMU | relative paths, no `C:\LM3D.CD` | SETUP writes `LM3D.CFG` in the game folder and reads it back; the game reads it, and writes `LM3D.SAV` there on quitting |
| 86Duino, boot *S* | all of the above | ✅ "It works with sound" |

### Loose ends

- **Is the Broken Record part needed here?** The 86Duino test ran with both
  fixes together, so whether this game's IRQs would also have stopped wasn't
  seen. With the fix the tick does the mixing anyway, so it does no harm.
- **Other cards.** Only the Sound Blaster driver was changed.

---

## Recipe for the next game

1. **Is it Late Echo?** The game or its setup says the sound card or driver
   wasn't found or failed, under SBEMU only, though the port is right.
2. **Look for `F2h`** in the driver (`B4 F2` or `B0 F2` before a DSP-write
   routine), followed by a polling loop and a list of IRQs.
3. **Find what the game passes** to the driver's init. If there's a way to
   give the port, IRQ and DMA channel (a setup file, `BLASTER`, a command line
   option), use it. If not, make the driver take fixed values where it would
   autodetect, as in Step 3.
4. **Then check for Broken Record:** a driver that mixes only in its IRQ
   handler will also need the [timer-tick fix](broken-record.md#recipe-for-the-next-game).

---

## Tools

| File | What it does |
|---|---|
| `lem3d_sbl_build.py` | Builds `SBL0FIX.BIN`: fixed port, IRQ and DMA instead of autodetection, plus the Broken Record fix. |
| `mk2_sbl_dmapoll.S` | The Broken Record fix for this driver family; its addresses are symbols, MK2's by default. |
| `lem3d_local.py` | Makes `L3D.EXE` and `SETUP.EXE` keep the settings and saved progress in the game folder. |
| `qemu_sbemu.sh`, `qemu_mon.py`, `loopcheck.py` | Shared tools (see the [tools in the overview of the game fixes](86duino-game-fixes.md#tools)). |

## Sources

- Disassembly of `SBL0.BIN` (16-bit `objdump`): dispatcher `0231h`, init
  `06A2h`, port autodetect `0790h`, IRQ autodetect `0931h`, IRQ handler `0B57h`.
- SBEMU source code, [github.com/crazii/SBEMU](https://github.com/crazii/SBEMU):
  `sbemu/sbemu.c` (`SBEMU_CMD_TRIGGER_IRQ`, `SBEMU_DELAY_FOR_IRQ`), `main.c`
  (`MAIN_Interrupt`).
- QEMU memory dumps (`pmemsave`) and the GDB stub, under JEMMEX, HDPMI32i,
  SBEMU 1.0.0-beta.5 and GHOSTFIX.
