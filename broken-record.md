# Broken Record: when the sound card's interrupt goes missing and the sound gets stuck

A Sound Blaster plays sound from a small buffer in memory, over and over, with
DMA. The buffer has two halves. When the card finishes one half it raises an
interrupt, the game's sound driver notes that the other half is now playing,
and the sound library writes fresh sound into the half that just finished.
That way the music and the effects keep flowing.

On the 86Duino, under SBEMU, a game's sound driver can stop getting those
interrupts after the first few. The emulated card keeps playing the buffer,
but nothing ever writes into it again. You hear the same fraction of a second
**over and over, like a needle stuck in the groove of a record**: "e‑e‑e‑e‑e".
Every new sound gets stuck the same way. I call this **Broken Record**.

| Face | What you hear | What is really there |
|---|---|---|
| **The Stuck Groove** | The music, the engines, the doors: everything turns into the same quarter-second repeated without end. A new sound changes the loop, but that one gets stuck too | A 4 KB DMA buffer (0.18 s) that the emulated card loops correctly, but that the sound library stopped refilling, because its "the other half is playing now" signal comes from an interrupt that no longer arrives |
| **The Stutter Cavalcade** | The music plays fine, but every sound effect, every punch, hit and scream, comes out as its own short "e‑e‑e", one after another | The same, in a game whose FM music doesn't use the buffer at all: only the digital effects stick, in a 57 ms loop |

The diagnosis and the patch on this page are by **Claude** (Anthropic's Claude
Opus 5.5, working in Claude Code). I tested them on the real 86Duino.

This is a sister page of [Tick Starvation](tick-starvation.md),
[Clock Mirage](clock-mirage.md), [Wet Ink](wet-ink.md),
[Borrowed Interrupt Flag](borrowed-interrupt-flag.md),
[Trap Storm](trap-storm.md), [Ghost Frame](ghost-frame.md),
[Sealed Gate](sealed-gate.md),
[Side Door](side-door.md),
[Sixteen-Bit Exile](sixteen-bit-exile.md) and [Late Echo](late-echo.md); all eleven are
listed in the [overview of the game fixes](86duino-game-fixes.md). Like Trap Storm, this one shows up
only on the real 86Duino: the same game under the same DOS setup in QEMU
plays its sound perfectly.

## Games

| Game | Year | Files patched | Faces | Fix | Status on 86Duino |
|---|---|---|---|---|---|
| [Grand Theft Auto](#case-1-grand-theft-auto-1997) | 1997 | `GTA8.EXE` (v11.5, the 8-bit colour version) | The Stuck Groove | 2 sites, 74 bytes | ✅ Music and sound effects play normally |
| [Mortal Kombat 3](#case-2-mortal-kombat-3-1995) | 1995 | `MK3.EXE` (1 Nov 1995), plus a ready-made `DIG.INI` | The Stuck Groove (shown in QEMU) | 2 sites, 76 bytes | ✅ "Sound is perfect now" |
| [Mortal Kombat II](#case-3-mortal-kombat-ii-1994) | 1994 | `SBL.BIN` (the game's own Sound Blaster driver), with `MK2.EXE` from [Sealed Gate](sealed-gate.md#case-1-mortal-kombat-ii-1994) | The Stutter Cavalcade | 5 sites in the driver, 78 bytes | ✅ "The sound and the music are perfect" |
| [Lemmings 3D](#case-4-lemmings-3d-1995) | 1995 | `SOUND\DRIVERS\SBL0.BIN`, with the [Late Echo](late-echo.md#case-1-lemmings-3d-1995) fix | The Stutter Cavalcade (expected; fixed before it was heard) | 4 sites in the driver, 78 bytes | ✅ "It works with sound" |
| *next game here* | | | | | |

**Suspects (not tested).** Any game that uses the **Miles Sound System 3.x**
with a real-mode `.DIG` Sound Blaster driver, run under SBEMU on the 86Duino.
Miles was licensed by hundreds of DOS games from 1994 to 1997. The giveaway:
*all* digital sound (music and effects, not just one of them) turns into a
short loop, while AdLib/MIDI music, if any, is fine. Games with their own
Sound Blaster driver that mixes only in its IRQ handler, like Mortal Kombat
II's, fall into the same groove. See
[Recipe for the next game](#recipe-for-the-next-game).

---

## The original request

> I have a new game to fix in our 86duino project. It's GTA, see it in the
> directory GTA. It almost works, it starts up with no errors, no artifact, I
> even can play through a mission, but it has an interesting issue. When it
> starts playing music It is unable to play the entire sample from the
> beginning to the end, it just keeps repeating the first second of the sample
> or so - I cannot measure it's length accurately it can be a half or a quarter
> of a second, I don't know. But instead of having the full music I just
> experience a sound like e-e-e-e-e. Could you find out what the problem is?

Then, after a few tests asked for on the way:

> Unless I set both to zero I still keep hearing the e-e-e-e-e in the menu
> [...] I've also tried music=0 and sound>0 during the game and no, the sound
> effects were not correct, the e-e-e-e-e just kept repeating, when I did
> something like opening a door or bumping into an other car then that
> triggered a never ending e-e-e-e-e. [...] I feel a quarter of a second is a
> better guess.

After the fix: *"gta8dma.exe worked very well"*.

---

## Background

### How a Sound Blaster plays digital sound

The game puts a buffer in conventional memory and programs the DMA
controller (the Intel 8237, ports `00h`–`0Fh`) to feed it to the card in
**auto-init** mode: when the DMA controller reaches the end, it starts again
at the beginning, forever. The card is told to raise an interrupt (here
IRQ 5) after every **half** of the buffer. The sound software must write the
next block of sound into the half that just finished, before the card comes
back to it.

If nobody writes, the card doesn't stop. It just plays the old contents
again: a loop as long as the buffer.

### SBEMU on the 86Duino

The 86Duino has no Sound Blaster. SBEMU emulates one on the 86Duino's own
sound hardware: it traps the game's accesses to the Sound Blaster and DMA
ports, plays the buffer itself, and raises the emulated IRQ 5 at the right
moments. For protected-mode games it relies on the DPMI host HDPMI32i; for
real-mode code (including a real-mode sound driver inside a protected-mode
game) it also needs `JLOAD QPIEMU.DLL`.

### Miles Sound System 3.x

The Miles Sound System (from RAD Game Tools) does its mixing in protected
mode, inside the game. The actual card is driven by a small **real-mode
driver** file chosen at setup time, here `SBPRO.DIG` (Sound Blaster Pro).
The driver's interrupt handler does almost nothing: it flips a word in the
driver's memory, the **"playing half" flag** (0 or 1). Miles checks that flag
from its timer interrupt. When the flag changes, Miles mixes all active
sounds into the other half. As long as the flag doesn't change, Miles does
nothing.

So the whole sound system hangs on one thing: the driver's IRQ handler being
called once per half buffer.

---

## Case 1: Grand Theft Auto (1997)

DMA Design / BMG Interactive, the freeware DOS release (version 11.5).
`GTA8.EXE` is the 8-bit colour version, the one that runs fast enough on the
86Duino. It is a Watcom C program bound to DOS/4GW, with the Miles Sound
System 3.50D and the `SBPRO.DIG` driver (`DIG.INI`: port 220h, IRQ 5,
DMA 1).

| File | Size | MD5 |
|---|---|---|
| `GTA8.EXE` (original, v11.5) | 1 935 083 | `b1ed709d9a847f5a6565af3279543eeb` |
| `GTA8.EXE` fixed (`GTA8DMA.EXE`) | 1 935 083 | `18475ef126adb56c2876b85c2737adbb` |
| `SBPRO.DIG` (Miles driver, not patched) | 2 801 | |

The 86Duino setup (boot menu entry *S*): `HIMEMX /MAX=32768`,
`JEMM386 EMX NOA20 NOHI I=TEST X=TEST`, `JLOAD QPIEMU.DLL`,
`HDPMI32I -r -x`, `SBEMU /i5`, `CTMOUSE /W`, `86CRSBAR N`.

All tools mentioned here are in [`tools/`](tools/). Addresses are linear
addresses in the loaded program; `le_load.py GTA8.EXE off ADDRESS` converts
them to file offsets.

### Step 1: First suspect, the music stream

GTA's music comes from WAV files (`GTADATA\AUDIO\0.WAV`–`5.WAV`, 22 kHz
16-bit stereo), streamed with Miles' streaming API: three 0.25 s file
buffers, refilled from the game's main loop. A stream that keeps replaying
its first buffers would sound just like the report, so I took the stream
code apart first. Nothing in it looked machine-dependent.

### Step 2: QEMU plays it fine

I set up GTA in QEMU with the same driver stack (JEMMEX, QPIEMU, HDPMI32i,
SBEMU with an emulated HD Audio card), recording the sound output to a WAV
file. Two QEMU-only obstacles first:

- DOS/4GW stopped with *"transfer stack overflow on interrupt 08h"*: KVM
  delivered missed timer ticks in a burst. Fixed with
  `-global kvm-pit.lost_tick_policy=discard`.
- Without `JLOAD QPIEMU.DLL` there was no sound at all: Miles' real-mode
  driver couldn't find the emulated card.

After that, the sound effects were clean, and the music was simply absent: in
the default *Music Mode: Radio* the game plays CD audio tracks, and there was
no CD. The WAV stream is only used on one front-end screen. So whatever
looped on the 86Duino in the main menu couldn't be the music stream.

### Step 3: The tests on the 86Duino

Three questions settled it:

| Test | Result on the 86Duino |
|---|---|
| Music 0, Sound > 0 | Still "e‑e‑e" |
| Sound effects | Also stuck: a door or a bump starts a never-ending loop |
| Music 0 and Sound 0 | The loop stops, but only after a while, once a new (now silent) sound has played |

So it's **all** digital output, not the music. The last line was the best
clue. Silencing the volume doesn't silence a loop that's already playing; it
only takes effect when something new is written into the buffer. Then the
silence gets stuck instead, which nobody can hear.

### Step 4: Reading the driver

`SBPRO.DIG` is 2 801 bytes of real-mode code. The interesting parts:

- **Playback start** (`0A57h`): DMA buffer 2 × 800h bytes (here at
  `1800:0000`), DSP commands `40h` (time constant `D3h`, about 22 kHz), `48h`
  (block size = half buffer), `1Ch` (8-bit auto-init). Flag (`[515h]`) = 0.
- **IRQ handler** (`06D3h`): acknowledges the card, sends the end-of-interrupt,
  and in the playing state does `xor word [515h],1` (`0753h`). That is the
  only place that ever flips the flag.
- **Miles' side** (`0x118EFB` in `GTA8.EXE`): the timer service reads the
  flag (`mov ebx,[eax+38h]; movsx ebx,word [ebx]`), compares it with the last
  value, and mixes into the other half only when it changed.

4 KB at about 22 000 bytes a second is **0.18 s**: the reported "quarter of a
second".

### Step 5: Proof by simulation

In QEMU I replaced the flip at `0753h` with `NOP`s, as if the IRQ never
arrived. The recording turned into an exact **0.178 s loop** (normalised
autocorrelation 0.94 at that period, measured with `loopcheck.py`), and
every new sound changed the loop without unsticking it. That is the
86Duino's symptom, made to order.

### Step 6: Counting the interrupts on the 86Duino

To confirm it on the hardware, `SBDIAG.DIG` (built by `sbdiag_build.py` from
`SBPRO.DIG`) counts the IRQ handler calls, the flag flips and the playback
starts in the BIOS inter-application area (`0000:04F0`), which survives GTA
loading and unloading the driver between the menus and the game.
`GTADIAG.COM` zeroes (`GTADIAG Z`) and prints the counters.

| Machine | Play time | IRQ handler calls | Flips | Playback starts | PIC mask at start |
|---|---|---|---|---|---|
| QEMU | ≈ 40 s | 418 | 408 (≈ 10 a second, as expected) | 6 | `98h` |
| 86Duino | ≈ 1 min | **13** | **9** | 3 | `58h` |

IRQ 5 is unmasked (bit 5 of the mask is clear), and it does arrive: the
driver's card detection needs one, and each playback start gets about three
flips. **Then the interrupts stop.** Why SBEMU's emulated IRQ stops reaching
the real-mode handler on the 86Duino, but not in QEMU, is still open (see
[Loose ends](#loose-ends)). The fix doesn't need to know.

### Step 7: The fix

Instead of the flag, Miles can ask the DMA controller where it is. SBEMU
emulates the 8237 too, so the count register of the driver's DMA channel
always says how much of the buffer is left. More than half left means the
first half is playing; otherwise the second.

The patch replaces Miles' 6-byte flag read with a call to a 68-byte helper
([`gta_dmapoll.S`](tools/gta_dmapoll.S)) placed in an unused run of zero bytes
in the code object (`0x12AD40`; nothing references it, and no relocation
covers either site):

1. Read the driver's own flag. If it is −1 (driver stopped), return that, as
   before.
2. Read the driver's DMA channel (driver offset `160h`) and the half size from
   the driver's buffer table. A 16-bit channel isn't handled: use the flag.
3. Clear the 8237 byte flip-flop (`out 0Ch`), read the channel's count
   register (two `in`s), and return 0 or 1.

No `cli`/`sti`, since HDPMI32i traps them (see [Trap Storm](trap-storm.md)).
The three port accesses per Miles timer tick are trapped too, but that's far
below a storm, and no keyboard trouble showed up in play.

Stopping still works without the IRQ. Before it stops the card, Miles mixes
two halves of silence, so if the driver's "pause at the next IRQ" never
happens, the card just loops silence. When the next sound starts, the
driver sees it was never paused and simply carries on.

```
python3 tools/gta_build.py GTA8.EXE GTA8DMA.EXE
```

or with `patch.py` (the old bytes at `0x1C1CA4` are 68 zeros):

```
python3 tools/patch.py GTA8.EXE GTA8DMA.EXE \
  0x1AFE5F:8b58380fbf1b:e8401e010090 \
  0x1C1CA4:$(python3 -c "print('00'*68)"):8b580c51520fbf4b0883f9ff74310fb79353fcffff83fa037725500fb74304662b030fb7d830c0e60c8d541201ec88c4ec86c40fb7c04031c939d87701415889cb5a59c3
```

Then start `GTA8DMA.EXE` from the `GTADOS` folder (the launcher's
`DINO.BAT` starts `GTA8.EXE`, so either rename the files or edit it).

### Step 8: Tests

| Where | Driver | Result |
|---|---|---|
| QEMU | `SBPRO.DIG` (IRQs fine) | Same as the original game: sounds play through and end in silence |
| QEMU | flip `NOP`ped (no IRQ flips at all) | Normal sound, the 1.9 s city-ambience loop instead of a 0.18 s one, clean silence between menu sounds |
| 86Duino | `SBPRO.DIG` | ✅ "Worked very well": music and sound effects normal |

Only `GTA8.EXE` is patched. `GTA24.EXE` and `GTAFX.EXE` (high colour) were
not patched: they run too slowly on the 86Duino to be worth it. They most
likely contain the same Miles code, so the same patch should fit at different
addresses.

### Loose ends

- **Why the IRQs stop.** About three flips per playback start, then nothing,
  only on the 86Duino. Candidates: the emulated IRQ's path from SBEMU through
  HDPMI32i (`-r`) and DOS/4GW down to a real-mode handler, or something in the
  86Duino's firmware interfering with interrupt delivery. Not investigated
  further: the fix works without them.
- **Music Mode.** In *Radio* mode the in-game music is CD audio (Miles'
  "Redbook" functions). The WAV music plays only on one front-end screen.

---

## Case 2: Mortal Kombat 3 (1995)

Midway / GT Interactive, DOS version (`MK3.EXE` dated 1 November 1995). A
Watcom C program bound to DOS/4GW, with an older Miles Sound System, the
Audio Interface Library **V3.02** of 18 January 1995. Its drivers are in
`DRIVERS\`, and its setup program `SETSOUND.EXE` writes the choice to
`DIG.INI`.

| File | Size | MD5 |
|---|---|---|
| `MK3.EXE` (original) | 1 496 497 | `35a7b1f0981050d8cc7cbe2ab0c2a3bd` |
| `MK3.EXE` fixed (`MK3DMA.EXE`) | 1 496 497 | `38577d345af96e99347cf55208ae0429` |
| `DRIVERS\SBPRO.DIG` (Miles 3.02 driver, not patched) | 2 763 | `b0fe50da778c24cc4066e960a3d1a7c3` |

Same 86Duino setup as Case 1 (boot menu entry *S*).

### The request

> Alright, let's move on and please work on an another game. It is in the
> directory MK3. I want to enjoy it with SBEMU but whatever I do it just says
> it cannot detect sound hardware so it starts up in no sound mode. Is it
> something you could fix and patch?

After the fix: *"MK3DMA.EXE worked very well, sound is perfect now"*.

### Step 1: No `DIG.INI`

The game reads its sound setup from `DIG.INI` and expects the driver file
next to `MK3.EXE`. Without a working setup it prints
*"InitSound: Sound Card Not Detected. Run SETSOUND."* and starts with sound
off. The game folder had no `DIG.INI` at all.

In QEMU, with the same driver stack as on the 86Duino, both `SETSOUND`'s
automatic detection (*"Device detected successfully"*) and the game itself
found the emulated Sound Blaster Pro, and the game played its sound. So the
fix package starts with a ready-made `DIG.INI` (Sound Blaster Pro, port 220h,
IRQ 5, DMA 1, `DRIVER SBPRO.DIG`) and a copy of `DRIVERS\SBPRO.DIG` next to
`MK3.EXE`.

### Step 2: The same groove, waiting to be hit

Once detection works, the sound would run into Case 1's problem. The 3.02
driver has the same design as GTA's 3.50D, only at different offsets:

| | GTA, Miles 3.50D | MK3, Miles 3.02 |
|---|---|---|
| IRQ handler | `06D3h` | `06C2h` |
| Flag flip (`xor [flag],1`) | `0753h`, flag `[515h]` | `0742h`, flag `[504h]` |
| Buffer table returned by function `301h` | `050Dh` | `04FCh` |
| DMA channel variable | `[160h]` = table − 3ADh | `[160h]` = table − 39Ch |
| Miles' flag read in the game | `0x118EFB`: pointer at DIG + 38h, result in `ebx` | `0x611A7`: pointer at DIG + 34h, result in `edi` |
| Pointer to the buffer table | DIG + 0Ch | DIG + 08h |

In QEMU, with the flip at `0742h` replaced by `NOP`s, the original `MK3.EXE`
looped its intro sound at exactly **0.178 s**, without end, like GTA.

The 3.02 driver's card detection also relies on an IRQ. It resets the DSP,
plays a 4-byte sample and waits up to 35 vertical retraces (about 0.5 s) for
the interrupt. So as a fallback, `SBNOIRQ.DIG` (a copy of `SBPRO.DIG` with
`0x93B` changed from `75` to `EB`) skips that wait; the DSP must still answer
the reset. It was only offered as a fallback, to be tried if the plain
driver still wasn't detected; the success report didn't mention needing it.

### Step 3: The fix

Same idea as Case 1, adapted to Miles 3.02:
[`mk3_dmapoll.S`](tools/mk3_dmapoll.S) (70 bytes) returns the playing half
from the 8237 count in `edi`. This game has no unused run of zero bytes in
its code, so the helper overwrites an unused C-library routine at
`0x4C3B9`: nothing calls it, no relocation points to it, and none sits inside
the overwritten bytes.

```
python3 tools/mk3_build.py MK3.EXE MK3DMA.EXE
```

### Step 4: Tests

| Where | Game | Driver | Result |
|---|---|---|---|
| QEMU | `MK3.EXE` | `SBPRO.DIG` | Intro sound about 5 s, then silence |
| QEMU | `MK3.EXE` | flip `NOP`ped | **0.178 s loop** that never ends |
| QEMU | `MK3DMA.EXE` | flip `NOP`ped | Same as the first line |
| QEMU | `MK3DMA.EXE` | `SBPRO.DIG`, `SBNOIRQ.DIG` | Same as the first line, menu shows *SOUND ON* |
| 86Duino | `MK3DMA.EXE` + `DIG.INI` | `SBPRO.DIG` (first step of the test plan) | ✅ "Sound is perfect now" |

### Loose ends

- **Why the game said "not detected" on the 86Duino.** The missing `DIG.INI`
  explains it. Whether `SETSOUND` itself fails on the 86Duino wasn't tested.
- **Was the original `MK3.EXE` stuck too?** Not tried on the 86Duino; only
  the patched game was. QEMU shows that it has the same weakness, and the
  86Duino lost its IRQs in Case 1.

---

## Case 3: Mortal Kombat II (1994)

Midway / Acclaim, the DOS version ported by Probe. To start at all under
SBEMU it first needs the [Sealed Gate](sealed-gate.md#case-1-mortal-kombat-ii-1994)
fix (`MK2FIX.EXE`); this case is about its sound once it runs. It doesn't use
Miles. Its Sound Blaster driver is its own: `SBL.BIN`, a real-mode file
("Soundblaster multi-channel", *Sound Images Generation 2 sound drivers*,
1992–94) that does all the mixing itself. The music is FM synthesis on the
OPL chip, which SBEMU emulates separately; only the sound effects go through
digital playback.

| File | Size | MD5 |
|---|---|---|
| `SBL.BIN` (original, 16 Jan 1995) | 11 408 | `0251aa45903c415ec705ddf28d1f1ac9` |
| `SBL.BIN` fixed (`SBLFIX.BIN`) | 11 408 | `3970c29bc9e64e6cde349ad75678646c` |

Same 86Duino setup as Case 1 (boot menu entry *S*), with the game's `CMOS`
file set to IRQ 5 (see [Sealed Gate](sealed-gate.md#step-7-irq-5-and-the-cmos-file)).

### The report

> Music also plays well, but the sound effects are like e-e-e-e-e-e just in
> the case of the GTA. The only difference is that the program usually
> doesn't hold them for so long, since sound effects are changing rapidly it
> is a cavalcade of different e-e-e-e-e-e-s.

After the fix: *"the sound and the music are perfect and the game is stable
enough to play."*

### Step 1: The driver mixes in its interrupt

`SBL.BIN` is called through one entry point with a function number in `AH`.
Reading it:

- **Playback start** (`0991h`, used when the DSP is version 2 or later, as
  SBEMU's is): one DMA buffer of **912 bytes**, 8237 mode `58h` (auto-init),
  DSP commands `40h` (time constant `C2h`, about 16 kHz), `48h` (block =
  **456 bytes**, half the buffer), `1Ch` (8-bit auto-init). The two halves
  are described by 8-byte entries at `1C54h` and `1C5Ch` (physical address,
  offset, segment). `[1C64h]` points at the entry of the half playing,
  `[1C66h]` at the one to fill.
- **IRQ handler** (`0B40h`): acknowledges the card, swaps `[1C64h]` and
  `[1C66h]`, sends the end-of-interrupt, enables interrupts, and calls the
  **mixer** (`call [107Ch]`), which mixes all active effects into the half at
  `[1C66h]`. This is the only place that ever mixes.
- **Timer tick** (function 3, `0295h`): music sequencing and volume ramps.
  The game's `RM.DRV` calls it from its own `INT 8` handler, which runs at
  three times the BIOS rate, about **55 times a second**.

456 bytes at about 16 kHz is 28 ms. Without the interrupt, the card loops the
whole buffer, 57 ms: every new effect starts, then sticks in its first
fraction of a second until the next one replaces it. The cavalcade.

### Step 2: Reproduced in QEMU

In QEMU the IRQs arrive and the effects play cleanly. With the swap and the
mixer call removed from the IRQ handler (as if the IRQ were lost), the
recording picks up a **0.06 s repeat** during fights (normalised
autocorrelation 0.49–0.60 in three windows, with the FM music still on top;
the unmodified driver, 0.26–0.48 for the same windows).

### Step 3: The fix

The timer tick runs twice per buffer half, so it can do the IRQ's job. The
new routine *poll* ([`mk2_sbl_dmapoll.S`](tools/mk2_sbl_dmapoll.S)) asks the
8237 how many bytes of the 912 are left: more than 456 means the first half
is playing. If the playing half isn't the one `[1C64h]` names, the driver
has missed a turn: poll swaps the two entries and calls the mixer. Both the
tick and the IRQ handler call poll, so whichever comes first does the work
and the other finds nothing to do; a busy byte stops them nesting.

There was no spare room in the driver, and making it longer would move the
song data, which the game places right behind it. So poll (78 bytes)
overwrites the driver's **IRQ autodetection** (`0935h`–`098Ch`, 88 bytes),
which only runs when the game passes port 0. The game passes the port from
its `CMOS` file, and the patch turns the "port 0 → autodetect" jump into a
plain jump past it. With port 0 in `CMOS` there is now simply no sound.

| Offset | Original | New |
|---|---|---|
| `0295h` | `cmp byte [217h],0` (tick start) | `call 0935h` (poll, then the same compare); 2 × `nop` |
| `06AFh` | `jne 06C3h` (port given) | `jmp 06C3h` |
| `0935h` | IRQ autodetection | tick entry + poll (78 bytes) |
| `0B56h` | swap `[1C64h]`/`[1C66h]` (10 bytes) | `nop`s |
| `0B6Fh` | `call [107Ch]` (mixer) | `call 093Eh` (poll); `nop` |

```
python3 tools/mk2_sbl_build.py SBL.BIN SBLFIX.BIN
```

or with `patch.py`:

```
python3 tools/patch.py SBL.BIN SBLFIX.BIN \
  0x295:803e170200:e89d069090 \
  0x6AF:75:eb \
  0x935:b007e81a007513b005e81300750cb002e80c007505b003e805008a0ee514c3505152579ca2e614e82701b4f2e8db00b9ffff8b16de1432e48826e514ec3a26e514e1f9e843019d803ee514007505:e80600803e170200c360803e820900753afe06820930c0e60c8a16e71430f6d0e242ec88c4ec86c4bb541c3dc8017303bb5c1c3b1e641c740ea1641ca3661c891e641cff167c10fe0e820961c300 \
  0xB56:a1641c8706661ca3641c:90909090909090909090 \
  0xB6F:ff167c10:e8ccfd90
```

Then copy `SBLFIX.BIN` over `SBL.BIN` in the game folder (keep the original).
The game checks only the driver's size, which is unchanged.

### Step 4: Tests

A test build of poll (assembled with `--defsym COUNT=1`) counts its mixes in
the BIOS inter-application area (`0000:04F0`), read from the QEMU monitor
(`xp /1hx 0x4f0`) ten seconds apart:

| Where | Driver | Result |
|---|---|---|
| QEMU | `SBL.BIN` | Clean effects (the IRQs arrive in QEMU) |
| QEMU | `SBL.BIN`, IRQ mixing removed | 0.06 s loop |
| QEMU | `SBLFIX.BIN` (counting build) | **37 mixes a second**: one per buffer half |
| QEMU | `SBLFIX.BIN` (counting build), IRQ's call to poll removed | **37 mixes a second**: the tick alone keeps up |
| 86Duino | `SBL.BIN` | The Stutter Cavalcade |
| 86Duino | `SBLFIX.BIN` | ✅ "The sound and the music are perfect" |

### Loose ends

- **DSP 1.x.** On a Sound Blaster with a DSP older than 2.0 the driver uses
  single-cycle DMA and restarts it from the IRQ handler (`09CAh`). Poll
  doesn't handle that mode; SBEMU reports DSP 3.02, so it never comes up.
  On such a card, use the original `SBL.BIN`.
- **A paused game** (the tick stops while `RM.DRV` pauses) mixes only from
  the IRQ, as before. Nothing plays during a pause anyway.

---

## Case 4: Lemmings 3D (1995)

Lemmings 3D's Sound Blaster driver `SBL0.BIN` (*Sound Images v1.11x*) is a
slightly later build of Mortal Kombat II's `SBL.BIN`: the same code, shifted
by a few bytes here and there. It first needed the
[Late Echo](late-echo.md#case-1-lemmings-3d-1995) fix to start at all. Like
MK2's, it mixes the sound effects only in its IRQ handler, so the MK2 fix was
ported straight away, before the game was tried on the 86Duino.

`mk2_sbl_dmapoll.S` now takes the driver's addresses as symbols (MK2's are the
defaults, and MK2's `SBLFIX.BIN` still builds byte for byte). For `SBL0.BIN`:

| | Mortal Kombat II `SBL.BIN` | Lemmings 3D `SBL0.BIN` |
|---|---|---|
| DMA channel | `[14E7h]` | `[149Eh]` |
| half entries | `1C54h`, `1C5Ch` | `1C0Ah`, `1C12h` |
| playing / to fill | `[1C64h]` / `[1C66h]` | `[1C1Ah]` / `[1C1Ch]` |
| mixer | `[107Ch]` | `[1077h]` |
| timer tick | `0295h` | `0295h` |
| IRQ swap / mixer call | `0B56h` / `0B6Fh` | `0B6Dh` / `0B85h` |
| room for the fix | IRQ autodetect, `0935h`–`098Ch` | IRQ autodetect, `0931h`–`0988h` |

The IRQ autodetection is dead code once the Late Echo fix gives the driver
fixed values, so the fix goes there again. In QEMU, a counting build with the
IRQ handler's call to the fix removed mixed about **25 times a second** from
the timer tick alone: one mix per 456-byte buffer half at about 11 kHz. The
recording in a practice level showed no stuck loop (normalised
autocorrelation 0.21–0.41). On the 86Duino, with both fixes: *"it works with
sound"*. Whether this game's IRQs would really have stopped wasn't tested
separately.

```
python3 tools/lem3d_sbl_build.py SOUND/DRIVERS/SBL0.BIN SBL0FIX.BIN
```

---

## Recipe for the next game

0. **Does the game use EMS?** If only the effects go wrong (whistles, noise)
   while the music through the same mixer is fine, try
   [Ghost Frame](ghost-frame.md#case-4-disneys-aladdin-1994) first: load
   `GHOSTFIX` and see whether it goes away.
1. **Is it Broken Record?** All digital sound turns into a short loop
   (0.1–0.5 s), music and effects alike, and a new sound changes the loop
   without unsticking it. Turning the volume down takes effect only with the
   next sound.
2. **Is it Miles?** Look for `AIL_` strings in the EXE and `*.DIG` files with
   an `AIL3DIG` header next to it.
3. **Count the interrupts.** `sbdiag_build.py` works for this `SBPRO.DIG`
   build (Miles 3.50D); other driver versions need the three patch offsets
   checked. Few handler calls (a dozen a minute instead of ten a second) means
   Broken Record.
4. **Find Miles' flag read** in the game: the driver's function `301h` returns
   the buffer table; Miles stores a pointer to its flag (table + 8) in its
   driver structure (`+38h` in 3.50D, `+34h` in 3.02). Search for
   `push 301h` in the Miles code, see where the pointer is stored, then look
   for a load of it followed by `movsx reg,word [reg]`. See the
   [comparison table](#step-2-the-same-groove-waiting-to-be-hit).
5. **Patch it** to call a copy of `gta_dmapoll.S` or `mk3_dmapoll.S`
   (whichever matches the Miles version; check the result register and the
   channel offset). Put it in a run of unused bytes, or over a routine that
   nothing calls, that no relocation touches (`le_load.py` checks the patched
   bytes; for the target, check that no relocation points into it).
6. **If the game says the card isn't detected,** first make sure `DIG.INI`
   exists and the `.DIG` file sits next to the EXE (see
   [Case 2](#step-1-no-digini)).
7. **No Miles?** If the game's own driver mixes only in its IRQ handler (as
   in [Case 3](#case-3-mortal-kombat-ii-1994)), find a routine that runs
   regularly in the same driver, usually a timer tick for the music, and let
   it check the DMA count and do the IRQ's mixing when the playing half has
   changed. The tick must run at least once per buffer half.

---

## Tools

| File | What it does |
|---|---|
| `gta_build.py`, `gta_dmapoll.S` | Builds the GTA fix: assembles the DMA-polling helper and patches `GTA8.EXE` (checks the original bytes first). |
| `mk3_build.py`, `mk3_dmapoll.S` | The same for `MK3.EXE` (Miles 3.02). |
| `mk2_sbl_build.py`, `mk2_sbl_dmapoll.S` (addresses as symbols), `lem3d_sbl_build.py` | The fix for Mortal Kombat II's own driver `SBL.BIN`, and for Lemmings 3D's `SBL0.BIN` of the same family: mixing driven from the timer tick and the DMA count. The rest of MK2's fix is on [Sealed Gate](sealed-gate.md#tools), the rest of Lemmings 3D's on [Late Echo](late-echo.md#tools). |
| `sbdiag_build.py`, `sbdiag_stubs.S` | Builds `SBDIAG.DIG` from your `SBPRO.DIG` (Miles 3.50D): counts IRQ handler calls, flag flips and playback starts at `0000:04F0`. Diagnostic only. The `.DIG` itself isn't included. |
| `gtadiag.S`, `GTADIAG.COM` | `GTADIAG Z` zeroes the counters, `GTADIAG` prints them (run before and after the game). |
| `loopcheck.py` | Finds the repeat period of a recorded WAV (autocorrelation): a stuck buffer shows up as a period of a fraction of a second with a correlation near 1. |
| `wavstat.py` | Loudness per quarter second of a QEMU recording, even while QEMU is still writing it. |
| `le_load.py`, `patch.py`, `qemu_sbemu.sh`, `qemu_mon.py` | Shared tools (see the [tools in the overview of the game fixes](86duino-game-fixes.md#tools)). For GTA, `qemu_sbemu.sh` needs `EXTRA="-accel kvm -global kvm-pit.lost_tick_policy=discard"`, and `GO.BAT` needs `JLOAD QPIEMU.DLL`. |

## Sources

- Disassembly of `GTA8.EXE` (via `le_load.py`) and of `SBPRO.DIG` (16-bit
  `objdump`), Miles Sound System V3.50D of 14 September 1996 (from `DIG.INI`).
- Disassembly of `MK3.EXE` and its `DRIVERS\SBPRO.DIG`, Miles Design Audio
  Interface Library V3.02 of 18 January 1995 (from `SETSOUND.EXE`).
- Disassembly of Mortal Kombat II's `SBL.BIN` and `RM.DRV` (16-bit `objdump`).
- Sound Blaster DSP commands `40h`, `48h`, `1Ch`, `D0h`, `D4h` and the 8237
  DMA controller registers: Creative Labs, *Sound Blaster Series Hardware
  Programming Guide*; Intel 8237A data sheet.
- SBEMU 1.0.0-beta.5 (crazii/SBEMU) command-line help and release notes.
