# Ghost Frame: when the disk delivers to a ghost

Some DOS games keep their data in **EMS memory** (expanded memory). The EMS
manager (JEMM386, EMM386, ...) shows EMS pages through a 64 KB window in
upper memory, the **page frame**, at an address like D000h or DC00h. It
doesn't copy anything there: it changes the CPU's page tables, so that
the addresses of the frame point at whichever EMS pages are mapped in. Only
the CPU sees this remapping.

On the 86Duino, the BIOS moves disk data by **DMA**: the disk controller reads
and writes physical memory by itself, without the CPU. If a game reads a file
*straight into the page frame*, the controller writes the data to the real,
physical memory at that address: the RAM that sits **behind** the frame, the
frame's ghost. The EMS page the game looks at never receives it. And if the
game saves a file *from* the page frame, the controller stores the ghost's
contents instead of the game's data. I call this **Ghost Frame**.

| Face | What the game does | What happens on the 86Duino |
|---|---|---|
| **The Lost Delivery** | Loads a file straight into the EMS page frame | The data lands in the ghost; the game reads what was in the EMS page before (black screens, garbage, a decoder that runs off the rails) |
| **The Ghost Writer** | Saves a file straight from the EMS page frame | The disk gets the ghost's contents (a fill pattern, leftovers of earlier lost deliveries) instead of the game's data, and the saved game is broken |
| **The Phantom Whistle** | Loads its sound data straight into the EMS page frame | The Lost Delivery, heard instead of seen: the sound mixer plays whatever sits in the EMS pages, and the effects come out as whistles while everything else is fine |

The diagnosis, the tools and the fix on this page are by **Claude**
(Anthropic's Claude Opus 5.5, working in Claude Code). I tested everything on
the real 86Duino.

This is a sister page of [Tick Starvation](tick-starvation.md),
[Clock Mirage](clock-mirage.md), [Wet Ink](wet-ink.md),
[Borrowed Interrupt Flag](borrowed-interrupt-flag.md),
[Trap Storm](trap-storm.md), [Broken Record](broken-record.md),
[Sealed Gate](sealed-gate.md),
[Side Door](side-door.md),
[Sixteen-Bit Exile](sixteen-bit-exile.md) and [Late Echo](late-echo.md); all eleven are listed in the
[overview of the game fixes](86duino-game-fixes.md). This one is about the 86Duino's disk, and it
needs no change to the game at all: a small resident program fixes it for
every program at once.

## Games

| Game | Year | Files patched | Faces | Fix | Status on 86Duino |
|---|---|---|---|---|---|
| [Ultima Underworld: The Stygian Abyss](#case-1-ultima-underworld-1992) | 1992 | none | The Lost Delivery, The Ghost Writer | `GHOSTFIX.COM` loaded before the game | ✅ Works perfectly, with AdLib music under SBEMU |
| [The Elder Scrolls: Arena](#case-2-the-elder-scrolls-arena-1994) | 1994 | none | probably The Lost Delivery (not investigated) | `GHOSTFIX.COM` loaded before the game | ✅ Starts with GHOSTFIX; without it, it just exits |
| [Lemmings 3D](#case-3-lemmings-3d-1995) | 1995 | none (for its sound: see [Late Echo](late-echo.md#case-1-lemmings-3d-1995)) | The Lost Delivery (not investigated) | `GHOSTFIX.COM` loaded before the game | ✅ Starts and plays well with GHOSTFIX; without it, garbage on screen and unusable |
| [Disney's Aladdin](#case-4-disneys-aladdin-1994) | 1994 | none | The Phantom Whistle | `GHOSTFIX.COM` loaded before the game | ✅ Sound effects right with GHOSTFIX; without it, whistles |
| *next game here* | | | | | |

**Suspects (not tested).** Any real-mode game that loads or saves files
straight into the EMS page frame. *Ultima Underworld II* (1993) uses the same
engine. Arena and Lemmings 3D, two more games known for needing EMS, were
suspects too, until GHOSTFIX got them running (Cases 2 and 3). The same goes for any program whose disk buffers sit in
upper memory blocks (UMBs) created by an EMS manager, because they are
remapped the same way. GHOSTFIX covers those too. See
[Recipe for the next game](#recipe-for-the-next-game).

---

## The original request

> I think it is time to move to Ultima Underworld, which is in UUNDER1. I
> configured it to use PC Speaker only on X86Duino ... and only what it
> produced was a black, blank screen, no reaction for keys. Could you figure
> out how to make it work on X86Duino?

Along the way:

> okay, the plot is thickening. ... when I started smartdrv up manually ...
> then it suddenly actually fixed EMSREAD and UW started up in both modes. I
> was suddenly in the main menu and even the mouse was working, but
> nevertheless the screen was full with artefacts.

After the fix:

> this was a particularly beautiful fix, it seems running GHOSTFIX in the
> background fixes everything, I even can start up a game and then walk in
> the labyrinth, everything is fawless, no artifacts.

With music:

> You won, after removing SMARTDRV and adding the JLOAD line, now Ultima
> Underworld works perfectly, exactly I wanted.

---

## Background

### The EMS page frame

Real-mode DOS programs can only address the first megabyte. EMS (the Lotus,
Intel and Microsoft "LIM" Expanded Memory Specification) lets them use more:
the EMS manager owns a pool of memory, split into 16 KB pages, and shows up
to four of them at a time in the page frame. INT 67h function 44h maps
"logical page n of my handle" into "physical page 0–3 of the frame".

On a 386 and later, EMM386 and its free successor JEMM386 do this with the
CPU's **paging**: DOS runs in virtual-8086 mode, and the page table entries
for the frame's 64 KB point at the EMS pages, wherever they are in extended
memory. For the CPU, and therefore for every program, the frame *is* the
mapped EMS memory.

### DMA doesn't know about paging

Paging is done by the CPU. A DMA transfer bypasses the CPU: the disk
controller gets a *physical* address and moves the data on its own. If that
address lies in the page frame (DC000h on the 86Duino of this page), the
data goes to the physical RAM at DC000h, not to the EMS page the CPU sees
there.

In the early 1990s this was a known problem with bus-mastering SCSI and IDE
controllers. The remedies were:

- **VDS** (Virtual DMA Services, INT 4Bh): a DMA-aware driver asks the EMS
  manager for the physical address of a buffer, or for a temporary bounce
  buffer. The 86Duino BIOS evidently doesn't ask.
- **Double buffering**: route every transfer through a buffer in low memory,
  where linear address = physical address. That's what MS-DOS 6's
  `SMARTDRV.EXE /DOUBLE_BUFFER` and Windows 9x's `DBLBUFF.SYS` were for.

---

## Case 1: Ultima Underworld (1992)

Blue Sky Productions / Origin, *Ultima Underworld: The Stygian Abyss*. `UW.EXE`
is a 16-bit real-mode program (Borland Turbo C++, with overlays). It needs
EMS, and uses the Miles AIL sound drivers in `SOUND\*.ADV`. The copy here is
from a German compilation.

| File | Size | MD5 |
|---|---|---|
| `UW.EXE` (unchanged) | 561 744 | `0f58c92a45b8d8d5bba498c59eb111c2` |

The 86Duino's boot menu entry for this game ("S"): HIMEMX,
`JEMM386 EMX NOA20 NOHI I=TEST X=TEST` (EMS page frame at **DC00h**), the SBEMU
stack and CuteMouse. DOS is the one from Windows 9x.

All tools mentioned here are in [`tools/`](tools/). Image offsets below are
offsets in `UW.EXE`'s load image (file offset minus the 3200h-byte header).

### Step 1: Black screen, dead keys

The game started, the screen went black, and no key did anything, even with
sound set to "none" (`DATA\UW.CFG`, first number 0).

### Step 2: A false lead, the keyboard LEDs

Right after hooking INT 9, the game sets the keyboard LEDs (`0x20989`): with
interrupts off, it sends `EDh` to port 60h and waits for the keyboard's
acknowledgement, with no time limit. A first theory was that the 86Duino's
keyboard emulation never answers.
[`LEDTEST.COM`](tools/ledtest.S) runs the same handshake with time limits:

```
Command EDh:  answer: FEh (status 53h) = NOT the expected ACK (FAh)
LED byte:     answer: FEh (status 53h) = NOT the expected ACK (FAh)
```

The 86Duino's keyboard emulation does answer, but with `FEh`, "resend": it
doesn't support the LED command. The game retries three times, gives up and
carries on, so this was not the hang. A patched copy without the LED code
failed in the same way. (Worth knowing for other games: on the 86Duino, the
keyboard's `EDh` command fails.)

### Step 3: QEMU says: it works

The [QEMU test machine](borrowed-interrupt-flag.md#tools), rebuilt with an
MS-DOS 6.22 boot floppy and JEMMEX, ran the game: title screen, intro, music.
Two lessons on the way:

- JEMMEX found no free page frame in QEMU until the network card's boot ROM
  was removed (`-nic none`) and the frame was given explicitly
  (`FRAME=D000 I=D000-DFFF`).
- A page frame forced onto memory that isn't free (E000h, where SeaBIOS lives)
  gives a scrambled screen and a JEMM exception: a reminder that the frame's
  placement matters. On the 86Duino, though, [`EMSTEST.COM`](tools/emstest.S)
  passed: frame at DC00h, 32 pages written and read back through the frame,
  0 errors. EMS itself works.

### Step 4: Where is the CPU? WHERE

A black screen with dead keys gives no clue. [`WHERE.COM`](tools/where.S) is a
small resident sampler: it programs the real-time clock's periodic interrupt
(IRQ 8, 16 Hz), which games practically never touch, and records the address
the CPU was interrupted at. Twice a second it draws the last addresses at the
top left of the screen, in text modes and in 320×200×256 (chained or mode X),
with its own 3×5 font.

On the 86Duino: the counter ran (interrupts on), and every sample was
`0201:0016`. `MEM /D` showed that segment 0201 lies **inside DOS's own low
memory**, and at the DOS prompt that address held data, not code. So the game
hadn't hung; it had crashed, and the CPU was somewhere it never should be.

### Step 5: The message nobody could see

Version 2 of WHERE also captures the last characters printed through the
BIOS (INT 10h teletype, where DOS console output ends up too). That caught a
message that JEMM386 had printed into the black graphics screen:

```
JEMM386: exception 0D occured at CS:EIP=0DE3:0000006E, ERRC=00000000
ESI=00007BA0 EDI=00003FFF ECX=00000B36 DS=DC00 ES=75AA
[CS:IP]=F3 A5 2A ED EB B4 F3 A5      Press ESC to abort program
```

JEMM386 had caught a general-protection fault and was waiting for Esc, which
never arrived because the game's own keyboard handler swallows every key. The
faulting `rep movsw` is in the game's animation decoder (`0x86A`, the
"LPF/ANM" run-length format of the cutscenes in `CUTS\`). The copy itself was
legal (5 740 bytes from DC00:7BA0 to 75AA:3FFF, nowhere near a segment end),
and a second crash hit a different `rep movsw`. In another boot setup without
HDPMI32i and SBEMU, the game didn't crash, but sat in the same decoder forever
behind a black screen. Both point at the same thing: **the decoder was fed
garbage**. And its input came from the EMS frame (DS=DC00h).

### Step 6: The Lost Delivery

How does the game fill the frame? A logging resident program in QEMU
(`doslog.S`, kept in the working folder) recorded every DOS file read: the
game loads graphics and animations **straight into the page frame**: many small
reads, and full-screen pictures with one 64 000-byte read to the frame's start.

[`EMSREAD.COM`](tools/emsread.S) does the same and checks the result: it fills
the frame with a marker byte (A5h), reads file data into the frame, reads the
same data into normal memory, and compares. On the 86Duino:

```
EMSREAD: DOS file reads into normal memory vs. into the EMS page frame
Page frame at segment DC00h
16 KB chunk 0: 16374 bytes differ (16374 of them never written)
16 KB chunk 1: 16354 bytes differ (16354 of them never written)
16 KB chunk 2: 16372 bytes differ (16372 of them never written)
16 KB chunk 3: 16362 bytes differ (16362 of them never written)
= Reads into the page frame are WRONG (DMA bypassing the EMS mapping?)
```

Almost nothing arrived: the few "matching" bytes are file bytes that happen
to be A5h. The disk data went to the ghost behind the frame. EMSTEST had
passed because it never involves the disk; QEMU had worked because its
emulated disk doesn't use DMA.

### Step 7: Half a cure, and the Ghost Writer

Windows 9x's `SMARTDRV.EXE`, a disk cache, reads disk data into its own
buffer and copies it on with the CPU, which respects the paging. With it
loaded, EMSREAD passed and the game reached its main menu, with a working
mouse, but:

- The menu background was partly garbage. Within a run it stayed the same
  (leaving the menu and coming back redrew the same garbage), but **between
  runs it was very different**, in the colours of the title logo. So the
  64 000-byte read of the background still didn't arrive, and the frame kept
  whatever the intro had left in it. SMARTDRV evidently passes some reads
  directly to the disk.
- [`CRCLIST.COM`](tools/crclist.S) showed that all 306 game files on the
  86Duino were intact, except one the game itself had written:
  `SAVE0\LEV.ARK`, the working copy of the dungeon. Compared with
  `DATA\LEV.ARK`, it had three blocks of 48, 48 and 32 KB filled with the
  repeating pattern `A5 5A 5A A5`, and two more blocks of real level data in the
  wrong places, all in 16 KB steps. That's **the Ghost Writer**: the game saved
  the level from the frame, and the disk controller took the ghost's
  contents, a fill pattern plus leftovers of earlier lost deliveries.
  Starting the game proper with that file threw the player back to DOS.

Windows 9x's double-buffer driver (`DoubleBuffer=2` in `MSDOS.SYS`) didn't
change anything; why was not investigated.

### Step 8: The fix: GHOSTFIX

Instead of relying on a cache, [`GHOSTFIX.COM`](tools/ghostfix.S) fixes the
problem at the BIOS level. It's a resident program of about 1.8 KB that hooks
INT 13h, the BIOS disk services:

- Reads and writes, both the classic CHS calls (02h/03h) and the LBA calls
  (42h/43h) that DOS 7 uses, are checked: if the buffer lies at or above
  linear address A0000h (the page frame, UMBs, the HMA), the transfer is done
  **one sector at a time through a 512-byte buffer in GHOSTFIX's own
  conventional memory**, and copied by the CPU.
- Everything else, including all transfers into normal memory, goes to the
  BIOS untouched, at full speed.
- Errors are passed back the way the BIOS reports them, with the number of
  sectors done.

`GHOSTFIX /U` removes it from memory again (added for Case 4), and a second
`GHOSTFIX` without `/U` says it's already installed instead of loading twice.
`/U` refuses if another program has hooked INT 13h after GHOSTFIX, because
unhooking then would cut that program off.

The 512-byte buffer is aligned to 512 bytes, so it never crosses a 64 KB DMA
boundary. It counts the sectors it handles (the word after the old INT 13h
vector, right behind the signature `GHOSTFIX`), which made it testable.

Tests in QEMU, before it went near the real SD card:

| Test | Result |
|---|---|
| [`I13TEST.COM`](tools/i13test.S): INT 13h writes and reads of 64 sectors with the buffer in the frame, LBA and CHS, on a separate scratch disk | Correct with and without GHOSTFIX; with it, exactly 256 sectors through the buffer |
| EMSREAD, then [`EMSWRITE.COM`](tools/emswrite.S) (the mirror image: writes a pattern file from the frame, reads it back into normal memory) | Correct; exactly 496 sectors through the buffer (the ones touching the frame), none of the others |
| The game, with HDPMI32i + SBEMU loaded | Runs |

On the 86Duino, with GHOSTFIX loaded: the menu clean in every run, a new
character, the game started, walking in the labyrinth, no artifacts.

### Step 9: Music

`DATA\UW.CFG` has three lines: `driver port irq dma sound`, the same for
speech, and `cuts`. The music driver numbers follow the driver table in
`UW.EXE`: 0 none, 1 PC speaker, **2 AdLib**, 3 Sound Blaster FM, 4 Sound
Blaster Pro FM, 5 Pro Audio Spectrum FM, 6 Roland MT-32. For AdLib under
SBEMU:

```
2 -1 -1 -1 sound
0 5 -1 -1 speech
0 cuts
```

Two more things were needed:

- **`JLOAD QPIEMU.DLL`** before SBEMU. Ultima Underworld runs in real mode
  (V86 mode under JEMM386), and SBEMU sees a real-mode game's AdLib port
  accesses only through the QPIEMU module. Without it, the game was silent
  in QEMU.
- **Enough conventional memory.** The game loads the sound driver into
  conventional memory (`farmalloc`, `0x1D1C1`); if that fails it says *"Sound
  system initialization failed."* and runs without sound. Measured in QEMU
  with MEM's "Largest executable program size" before starting the game:

  | Free | AdLib | PC speaker |
  |---|---|---|
  | 547 KB | ✅ | |
  | 542 KB | ❌ | |
  | 539 KB | | ✅ |
  | 529 KB | | ✅ |
  | 519 KB | | ❌ |

  SMARTDRV, loaded low from AUTOEXEC.BAT, had pushed the 86Duino under the
  line. GHOSTFIX makes it unnecessary.

### The working setup

Boot entry "S" on the 86Duino, AUTOEXEC.BAT part (CONFIG.SYS: HIMEMX and
JEMM386 as above):

```
C:\SBEMU\JLOAD.EXE C:\SBEMU\QPIEMU.DLL      (paths as on your machine)
C:\SBEMU\HDPMI32I.EXE -r -x
C:\SBEMU\SBEMU.EXE /i5
GHOSTFIX
```

plus `UW.CFG` as in Step 9, and no SMARTDRV. Then `UW`.

### Loose ends

- **How the 86Duino moves disk data.** That its BIOS uses DMA (or bus
  mastering) for the SD card is inferred from EMSREAD's result, not read from
  the BIOS or the datasheet.
- **Why DBLBUFF.SYS didn't help**, and **which reads SMARTDRV passes through**,
  were not investigated. GHOSTFIX made both moot.
- **Not covered by GHOSTFIX:** a program that talks to a disk controller
  directly instead of through INT 13h, and the 64-bit flat-buffer form of
  INT 13h 42h/43h (buffer FFFF:FFFF). Neither is used by DOS or this game.
- **Speed:** transfers into upper memory go one sector at a time. In this game
  that isn't noticeable.

---

## Case 2: The Elder Scrolls: Arena (1994)

Bethesda Softworks, *The Elder Scrolls: Arena*. It needs EMS, and was
notorious in its day for its memory requirements.

On the 86Duino it **does not start** without GHOSTFIX: it just exits to DOS,
without a word, no error message at all.
With `GHOSTFIX.COM` loaded before the game, **it starts**. I found this myself, by trying GHOSTFIX
on other games that use EMS. No change to the game is needed.

The game itself wasn't investigated, so a few things are still open:

- **Which face.** That the game exits right away suggests The Lost Delivery:
  something it loaded didn't arrive, and it gave up. Whether saving is
  affected too (The Ghost Writer) isn't known. GHOSTFIX covers both
  directions, so saved games should be safe with it loaded, but that hasn't
  been checked separately.
- **How far it has been played**, and with which sound setup.

## Case 3: Lemmings 3D (1995)

Psygnosis / Clockwork Games, *Lemmings 3D*. It needs EMS.

Without GHOSTFIX, on the 86Duino it starts to **display garbage** and is
then basically unusable: the classic Lost Delivery picture, like Ultima
Underworld's garbled menu. With `GHOSTFIX.COM` loaded before the game, **it
starts** normally and plays well. No change to the game is needed for that.
Its sound under SBEMU needed a fixed driver: see
[Late Echo](late-echo.md#case-1-lemmings-3d-1995), which also moves its
settings and saved progress from `C:\LM3D.CD` into the game folder. Which
files it loads into the page frame wasn't investigated.

---

## Case 4: Disney's Aladdin (1994)

Virgin Interactive's PC version of *Disney's Aladdin*. `ALADDIN.EXE` is a
real-mode Borland C++ program that needs 1 MB of XMS and 1 MB of EMS. Its
sound comes from Otto Chrons' **DSMI** library, set up with `SETSND.EXE`
(written to `SOUND.CFG`). With "enhanced music" on, the music is digital
too, mixed by DSMI together with the effects into one Sound Blaster DMA
buffer.

### The report

> Look into the directory ALADDIN. I feel it is a variant of the Broken
> Record problem we had with GTA and MK3. The music plays very well, but the
> sound effects are just whistles, and I find it very odd, I think in an
> original game they were different - I suspect they are e-e-e-e-e-s with a
> very small buffer size.

### Step 1: Not a Broken Record

The suspicion was reasonable, but DSMI's Sound Blaster driver doesn't need
the IRQ to keep the sound flowing. As set up on this machine (Sound Blaster
Pro, stereo, about 41.7 kHz):

- it programs the 8237 for an **auto-init loop over a 5 344-byte buffer**
  (0.13 s) and starts the DSP in high-speed auto-init mode (commands `48h`,
  `90h`) with a block length of `FFFFh`, far longer than the buffer;
- its IRQ handler only acknowledges the card (`ALADDIN.EXE` image offset
  `20859h`);
- the mixer follows the **8237 count register**, read twice until two
  readings agree (`21AB:01DB`), and refills whatever the card has played.

A lost IRQ changes nothing here, and a stuck mixer would give a 0.13 s loop,
an "e‑e‑e" at 8 Hz rather than a whistle. And the music, which goes through
the same mixer and the same buffer, was fine.

A detour on the way: in QEMU with 64 MB the game stopped at once with
*"XMS allocation error.."*; with 32 MB it runs. The 86Duino's setup caps XMS
at 32 MB (`HIMEMX /MAX=32768`), so it never sees this. Why (probably the free
XMS read as a signed 16-bit count of kilobytes) wasn't checked.

### Step 2: The ghost's fingerprints

The game needs EMS, so I loaded `GHOSTFIX` in QEMU and watched its sector
counter. It stayed at **0** through the intro and the menus, and jumped to
**368 sectors** (184 KB) as level 1 loaded: Aladdin reads level data straight
into upper memory, the EMS page frame. In QEMU that's harmless, as in
[Case 1](#step-3-qemu-says-it-works). On the 86Duino those
sectors land in the ghost.

Which files those 368 sectors are wasn't traced; the test below made it
unnecessary. The fit with the symptom: sound effect samples that DSMI mixes
from EMS would be played from whatever the EMS pages held before. Why the
music isn't affected wasn't checked either; presumably its samples are
loaded elsewhere.

### Step 3: Test

On the 86Duino, with `GHOSTFIX.COM` loaded before the game: *"ghostfix.com
fixed aladdin to me."* No change to the game is needed.

To unload GHOSTFIX after playing, it got a `/U` switch (see
[Step 8 of Case 1](#step-8-the-fix-ghostfix)):

```
GHOSTFIX
ALADDIN
GHOSTFIX /U
```

Tested in QEMU: install, a second install (refused), `/U` (removed: free
memory back from 636 016 to 638 032 bytes), a second `/U` (refused), and disk
reads afterwards.

---

## Recipe for the next game

1. **The symptom.** A game that uses EMS shows a black screen, garbage,
   crashes in its decoders, writes broken save files, or plays broken sound
   effects, on the 86Duino only. In an emulator it works.
2. **Run [`EMSREAD`](tools/emsread.S) and [`EMSWRITE`](tools/emswrite.S).** If
   they report wrong reads or writes, it's Ghost Frame. (With a disk cache
   loaded, empty it first with `SMARTDRV /R`, or the test may read the cache.)
3. **Load [`GHOSTFIX`](tools/ghostfix.S)** before the game, run the two tests
   again, then the game. No change to the game is needed. `GHOSTFIX /U`
   removes it afterwards. Its sector counter (the word right after the old
   INT 13h vector, behind the signature `GHOSTFIX`) shows whether a game
   reads into upper memory at all: in QEMU, read it with `qemu_mon.py 'xp'`
   at the segment the INT 13h vector points to.
4. **If the screen just goes black,** load [`WHERE`](tools/where.S) first.
   It shows where the CPU is and the last text printed, including
   error messages that a game or the memory manager printed into a graphics
   screen.
5. **If sound fails to start**, check `MEM`: many games need well over
   500 KB of free conventional memory for their sound drivers. Real-mode games
   under SBEMU also need `JLOAD QPIEMU.DLL`.

## Tools

In [`tools/`](tools/). Build any of the `.S` files with
`python3 dosbuild.py NAME.S` (GNU binutils).

| File | What it does |
|---|---|
| `ghostfix.S`, `GHOSTFIX.COM` | **The fix.** Resident INT 13h hook: disk transfers to or from memory at A0000h and above go through a buffer in conventional memory. About 1.8 KB resident; `GHOSTFIX /U` removes it. |
| `emsread.S`, `EMSREAD.COM` | Tests DOS file reads into the EMS page frame against reads into normal memory (one 60 KB read, then four 16 KB reads; the frame is always read first, so a disk cache can't hide the problem). `EMSREAD [file]`, default `DATA\LEV.ARK`. |
| `emswrite.S`, `EMSWRITE.COM` | Tests DOS file writes from the EMS page frame: `EMSWRITE W` writes `EMSW.TMP`, `EMSWRITE C` checks it. |
| `emstest.S`, `EMSTEST.COM` | Tests EMS itself: 32 pages written and read back through the frame (no disk involved). |
| `where.S`, `font35.inc`, `WHERE.COM` | Black-screen diagnostic: RTC-driven (IRQ 8) sampler of the interrupted address, plus the last 400 characters printed through the BIOS, drawn at the top left in text and 256-colour modes. Not removable; reboot afterwards. |
| `ledtest.S`, `LEDTEST.COM` | The keyboard "set LEDs" handshake with time limits; prints what the keyboard (emulation) answers. |
| `crclist.S`, `CRCLIST.COM`, `CRCALL.BAT`, `CRCDIR.BAT` | CRC-32 (the zip one) of every file in a folder; `CRCALL` lists a game's folders into `CRC.TXT`, to compare a copy with a known-good one. |
| `i13test.S`, `I13TEST.COM` | QEMU test for GHOSTFIX: INT 13h writes and reads with the buffer in the EMS frame on a **scratch** disk (drive 81h). Never run it on a real disk. |
| `dosbuild.py` | Assembles any of the `.S` files above into a `.COM`. |

No game files are included in this repository.

## Sources

- Lotus/Intel/Microsoft, *Expanded Memory Specification* 4.0 (1987): INT 67h,
  page frame, mapping functions.
- Microsoft, *Virtual DMA Services Specification* (1990): INT 4Bh, why DMA and
  paging don't mix.
- [Ralf Brown's Interrupt List](https://www.ctyme.com/rbrown.htm): INT 13h
  (02h, 03h, 08h, 42h, 43h), INT 67h, INT 21h, RTC registers A–C (IRQ 8,
  INT 70h), CMOS port 70h/71h.
- [JEMM](https://github.com/Baron-von-Riedesel/Jemm) by Japheth: JEMM386 /
  JEMMEX, JLOAD.
- [SBEMU](https://github.com/crazii/SBEMU), release 1.0.0-beta.5: SBEMU,
  HDPMI32i, QPIEMU.DLL.
- [Vortex86EX datasheet](https://www.86duino.com/wp-content/uploads/2013/11/Vortex86EX_A9123_V14_86duino.pdf):
  the 86Duino's chip.
