# Command & Conquer (1995): running without the CD

This page explains how to run the DOS version of **Command & Conquer** (Westwood
Studios, 1995) from the hard disk, without the CD in the drive, and still get
the full-motion video (FMV) cutscenes. There are two ways to do it. One uses a
command-line switch already built into the game and needs no patch. The other
is a 2-site binary patch for players who don't want to type the switch.

> **Warning: more than 64 MB of RAM.** Even with no CD involved, the original
> `GAME.DAT` crashes at startup on a PC with more than 64 MB of memory. The
> crash is in its DOS extender, not in the game. PCs from 1995 had 8–16 MB, but
> most machines that run DOS today (late-1990s PCs, retro boards like the
> 86Duino) have more, so most people running the original disc on real hardware
> will hit it. See [More than 64 MB of RAM](#more-than-64-mb-of-ram).

This is ordinary no-CD work of the kind that has been done for many games. It
isn't specific to the 86Duino; it's here because the 86Duino has no CD drive
and because the steps may be useful to others. It is kept apart from the
86Duino issue pages ([Tick Starvation](tick-starvation.md),
[Clock Mirage](clock-mirage.md)).

The analysis, the patch and the tests are by **Claude** (Anthropic's Claude
Opus 5.5, working in Claude Code).

**Anyone can do this.** In 2007 Electronic Arts released Command & Conquer as
freeware, and the original CD images (the GDI disc and the Nod disc) can still
be downloaded from many places, the Internet Archive among them. You don't need
to own the boxed game.

## Contents

- [Summary](#summary)
- [The original request](#the-original-request)
- [The files](#the-files)
- [How the CD check works](#how-the-cd-check-works)
- [Option A: the built-in -CD switch (no patch)](#option-a-the-built-in--cd-switch-no-patch)
- [Option B: patched GAME.DAT (no switch)](#option-b-patched-gamedat-no-switch)
- [Pitfall: SCORES.MIX in the game directory](#pitfall-scoresmix-in-the-game-directory)
- [More than 64 MB of RAM](#more-than-64-mb-of-ram)
- [How it was tested](#how-it-was-tested)
- [Limitations](#limitations)
- [Tools](#tools)

---

## Summary

| | Option A: `-CD` switch | Option B: patched `GAME.DAT` |
|---|---|---|
| Changes to game files | none | 2 patch sites, 10 bytes, in `GAME.DAT` |
| Where the CD files go | anywhere, e.g. `C:\CNCCD\` | in the game directory |
| How to start | `C&C -CDC:\CNCCD\` (e.g. from `START.BAT`) | `C&C` |
| Movies | play (tested) | play (tested) |
| Tested in | DOSBox 0.74-3, DOSBox-X | DOSBox 0.74-3 |
| Tested on the 86Duino | ✅ yes, with the memory and sound caveats on [Command & Conquer on the 86Duino](command-and-conquer-on-86duino.md) | patch 1 only |

Either way, the CD files have to be on the hard disk; the movies alone
(`MOVIES.MIX`) are 425 MB. And either way, mind the
[64 MB limit](#more-than-64-mb-of-ram).

---

## The original request

The first message, unedited:

> okay, this will be one of our dos game projects, but this isn't strictly
> related to the previous X86Duino project, so this is off-record. There is the
> now freeware old MSDOS game Command and Conquere, the content of the original
> install CD is in cnccd while the installed version is in a subdirectory within
> cnc. In this particular case, I want you to patch the executable in a way that
> it runs without CD while it still able to play back the original fmv
> animations.

During the work Claude found the built-in `-CD` switch. The user stopped
Claude to try it (*"stop for a moment, I want to try -CD"*). The user then
wrote a `START.BAT` for it and came back with:

> I've a bit restructured the directories so now cnc has cnccd too and I also
> added a START.BAT that tries to utilitize the -CD trick. However, I cannot
> start up CNC in dosbox, when the cnc dir is mounted as a root for C:. Can you
> review START.BAT and debug why dosbox is failing to me?

The cause turned out to be a file Claude had copied into the game directory
earlier; see [Pitfall](#pitfall-scoresmix-in-the-game-directory).

---

## The files

The copy used here is the **GDI disc**, version 1.07 according to its
`README.TXT`. It was installed to the hard disk with the CD's own installer.

**On the CD:**

| File | Size | Contents |
|---|---|---|
| `MOVIES.MIX` | 425 MB | the FMV cutscenes (`.VQA` files) |
| `SCORES.MIX` | 56 MB | music |
| `GENERAL.MIX` | 3.4 MB | missions (scenario `.INI` and `.BIN` files) |
| `CONQUER.MIX`, `SOUNDS.MIX`, `ZOUNDS.MIX` | 1–2 MB each | graphics and sound effects |
| `DESERT.MIX`, `TEMPERAT.MIX`, `WINTER.MIX` | ~0.7 MB each | map theaters |
| `AUD.MIX`, `SETUP.MIX`, `INSTALL\`, `AUD1\` | | used by the installer |

**Installed to the hard disk:** `C&C.EXE`, `GAME.DAT`, `CONQUER.INI`,
`LOCAL.MIX`, `SPEECH.MIX`, `TRANSIT.MIX`, the sound drivers and the setup
programs. Everything else is read from the CD while the game runs.

**`C&C.EXE`** (1,519 bytes) is only a launcher. It checks that at least about
400 KB of conventional memory and 8 MB of disk space are free, changes to its
own directory, deletes old `*.SWP` swap files, and runs `GAME.DAT`, passing
its command line through unchanged.

**`GAME.DAT`** (1,206,037 bytes, MD5 `9698b64a7ab10901a3a25b61db4d64fc`) is the
real game: a 32-bit protected-mode program in the **LE** format, bound to the
DOS/4GW Professional extender. The LE part starts at file offset `0x352A4`
(its MZ stub) / `0x384AC` (the `LE` header). It has three objects:

| Object | Linear base | Contents |
|---|---|---|
| 1 | `0x10000` | code |
| 2 | `0xC0000` | 12 bytes |
| 3 | `0xD0000` | data and strings |

All addresses below are linear addresses as the program sees them. To patch the
file they have to be converted to file offsets, which
[`le_load.py`](tools/le_load.py) does.

One LE detail matters for patching. Every absolute address in the code (a
string address in a `push`, a variable in a `mov`) is a **fixup**: the loader
rewrites those 4 bytes every time the program starts. A patch byte that lands
on a fixup is overwritten at load time. All patches here were checked to stay
clear of fixups.

---

## How the CD check works

Electronic Arts released the source code of Tiberian Dawn in 2020, and the
function names below are taken from it. The disassembly of this DOS build follows the
same logic.

**`RequiredCD`** (variable at `0xDD25C`, starts at -1) says which disc the game
needs right now:

| Value | Meaning |
|---|---|
| -2 | no CD needed |
| -1 | any C&C disc (GDI or Nod) |
| 0 | GDI disc |
| 1 | Nod disc |

**`Force_CD_Available(cd)`** (at `0x29268`) makes sure that disc is in the
drive:

1. If `cd` is -2, return "OK" at once.
2. Ask MSCDEX for the CD-ROM drive letter (`0x23AA0`). No drive: return "fail".
3. Read the disc's volume label (`findfirst("X:*.*", volume label)`) and check
   that `X:movies.mix` can be opened.
4. Compare the label with `GDI` / `NOD`. If it isn't the wanted disc, show
   the "insert disc" dialog and try again.
5. If the disc changed, close the old `MOVIES.MIX` and `GENERAL.MIX` and open
   the ones from the new disc.

It is called when the game starts, when a mission starts (each side's
missions need its own disc), and inside the MIX-file loader
(`MixFileClass`, `0x59F90`), which calls `exit(255)` if the check fails.

**The search path.** All game files are opened through a list of search
directories. At startup the game sets it to `?:\`, where `?` means "find the
CD-ROM drive", unless the list already has entries. If the list already has
entries, the startup code (`0x47A96`) skips CD detection and sets
`RequiredCD = -2`. After that, every later CD check passes. The mission-start
code only changes `RequiredCD` when it isn't -2.

The only way the list gets entries before that point is the command-line switch
**`-CD<path>`**, parsed at `0x4883D`. It isn't listed in the game's `-?` help
text. Several directories can be given, separated by `;`, and a missing
trailing `\` is added.

---

## Option A: the built-in -CD switch (no patch)

No game file is changed.

1. Install the game from the CD as usual (the CD's `INSTALL.EXE` /
   `SETUP.EXE`).
2. Copy the whole CD to a directory on the hard disk, for example `C:\CNCCD\`.
3. Start the game with the switch. The setup tested here:

```
C:\
├── START.BAT
├── C&C\        the installed game (original files only)
└── CNCCD\      the CD contents
```

`START.BAT` (DOS line endings, CR LF):

```bat
@echo off
c:
cd \C&C
C&C -CDC:\CNCCD\
cd \
```

In DOSBox, mount the directory that holds `START.BAT` as C: and run
`START.BAT`.

**Don't** copy the CD's MIX files into `C&C\` for this option. They aren't
needed there, and one of them stops the game from starting; see
[Pitfall](#pitfall-scoresmix-in-the-game-directory).

---

## Option B: patched GAME.DAT (no switch)

For starting the game with plain `C&C`, with all files in one directory.

1. Install the game from the CD.
2. Copy all `.MIX` files from the CD root into the game directory:
   `CONQUER`, `GENERAL`, `MOVIES`, `SCORES`, `SOUNDS`, `ZOUNDS`, `DESERT`,
   `TEMPERAT`, `WINTER`.
3. Patch `GAME.DAT`:

| # | Linear address | File offset | Old bytes | New bytes | What it does |
|---|---|---|---|---|---|
| 1 | `0x47AA5` | `0x9D349` | `0F 85` | `90 E9` | Turns "if a search path was given, skip the CD (`jne`)" into an unconditional `jmp`. The game always takes the `-CD` branch: `RequiredCD = -2`, no CD detection, files opened from the current directory. |
| 2 | `0xD26D8` | `0x112F7C` | `SC*.MIX\0` | `SC-*.*\0\0` | Changes the file pattern of the expansion-scenario scan so it no longer matches `SCORES.MIX` (see [Pitfall](#pitfall-scoresmix-in-the-game-directory)). Same length, 8 bytes. |

With [`patch.py`](tools/patch.py):

```
patch.py GAME.DAT GAME.NEW 0x9D349:0f85:90e9 0x112F7C:53432a2e4d495800:53432d2a2e2a0000
```

Then rename `GAME.DAT` to `GAME.ORG` and `GAME.NEW` to `GAME.DAT`. The result
has MD5 `d08c4d7b3eff570729b7bbd5d75c89af`.

Notes on patch 1:
- The check it replaces is a `cmp` / `setne` / `and` / `jne` sequence. The
  obvious place for a `jmp`, the `cmp` at `0x47A96`, holds a fixup at
  `0x47A98`, so the patch goes on the `jne`, which has none. The `90` fills
  the extra byte so the `jmp` keeps the `jne`'s target, `0x47B8D`.
- A patched `GAME.DAT` still accepts `-CD`, so it also works with Option A.

Notes on patch 2:
- Westwood's own expansion files (the Covert Ops add-on) are, as far as we
  know, named `SC-000.MIX` and `SC-001.MIX`. The new pattern `SC-*.*` would
  still find them. This wasn't tested, because the add-on isn't part of this
  copy.
- Patch 1 alone is **not** enough when `SCORES.MIX` is in the game directory:
  the game exits silently about a second after starting.

---

## Pitfall: SCORES.MIX in the game directory

This is what went wrong with the user's `START.BAT`. The batch file was fine.
At that point Claude had already copied the CD's MIX files into `C&C\` as part
of Option B. DOSBox ran the game, the screen went black for about a second,
and the prompt came back with no message.

Early in startup, before the CD logic and before `-CD` takes effect, the game
looks for expansion scenario packs with `findfirst("SC*.MIX")` in its own
directory (`0x476F3`). It opens every match as a MIX file. **`SCORES.MIX`
matches `SC*.MIX`.**

- **Original `GAME.DAT`:** `RequiredCD` is still -1 at that point. Opening the
  MIX file calls `Force_CD_Available(-1)`, which finds no CD drive and fails.
  The loader then calls `exit(255)` (`0x5A00E`) with no message. The `-CD`
  switch can't prevent this, because it is applied later.
- **With `RequiredCD` forced to -2 from the start:** the CD check passes. The
  game then tries to load the matched "scenario pack" into memory and stops
  with `Unable to load "SCORES.MIX".` The file is 56 MB, far more than the
  memory available.

On the original CD install `SCORES.MIX` stays on the CD, so the scan never
meets it. Removing the copies from `C&C\` fixed Option A. Patch 2 fixes
Option B.

---

## More than 64 MB of RAM

This has nothing to do with the CD. It concerns everyone who runs the original
`GAME.DAT`, with or without the patches on this page.

`GAME.DAT` is bound to **DOS/4GW Professional 1.97**. When no other DPMI host
is loaded, DOS/4GW manages protected mode and extended memory itself, and in
that mode it fails if the machine has **more than 64 MB** of extended memory.
The failure is in the extender's own 16-bit code, before the game's first
instruction runs.

**What it looks like.**

On a real PC (the 86Duino, 128 MB, FreeDOS with an XMS driver), right after
starting:

```
DOS/4GW Professional Protected Mode Run-time  Version 1.97
Copyright (c) Rational Systems, Inc. 1990-1994
DOS/4GW Professional error (2001): exception 0Dh (general protection fault) at 3E58:000024D7
```

followed by a register dump (`CS= 3E58, USE16, ...`) and the DOS prompt.

In DOSBox-X, the emulator itself quits with:

```
E_Exit: Illegal descriptor type 0 for int 31
```

**Where the line is.** In DOSBox-X, with everything else unchanged:

| `memsize` | Result |
|---|---|
| 16 (DOSBox default) | runs |
| 63 | runs |
| 65 | crashes at start |
| 128 | crashes at start |

Plain DOSBox users with the default 16 MB never see this. Almost every real
machine that runs DOS today has more than 64 MB, so anyone installing the
original disc on real hardware is likely to meet it.

**Ways around it.** Each one has trade-offs, and which suits you depends on
your machine. Here is what was tried:

| Approach | How | Result here |
|---|---|---|
| Show DOS less memory | Cap the extended memory DOS hands out below 64 MB. Most XMS drivers have an option for this (for example `/MAX=` in HIMEMX); in an emulator, set the RAM size to 63 MB or less. Other programs then also see less memory, so a separate boot-menu entry may be handy. | ✅ Works in DOSBox-X and on the 86Duino. |
| Load a DPMI host first | Start a DPMI host such as HDPMI32 before the game. DOS/4GW then runs as a client of that host and doesn't manage the memory itself. | ✅ Starts and plays at 128 MB on the 86Duino. That machine had a separate crash under this setup; see [Command & Conquer on the 86Duino](command-and-conquer-on-86duino.md). |
| Replace the extender | Rebind `GAME.DAT` to DOS/32A with its `SB /R` tool (DOS/32A 9.1.2). | ✅ Runs at 128 MB in DOSBox-X, through the end of a mission (test scenario) and the score screen. ❌ Froze at start on the 86Duino; not investigated further. |

All three keep the game files intact except the third, which produces a new
`GAME.DAT`. Keep the original.

**How it was found.** In a scratch copy of `GAME.DAT`, an infinite loop
(`EB FE`, `jmp $`) was placed at one suspect location per run. A run that
then hung until the timeout showed that the location was reached:

| Trap at | Meaning | Hung? |
|---|---|---|
| inside `exit()` | the game calls `exit()` | yes |
| end of `main` | the game returns normally | no |
| RAM check, disk check, mouse check failure paths | | no |
| each of the 19 calls to `exit()`, one per run | | only `0x5A00E` (MIX loader, CD check failed) |

For the -2 variant the same search led to `0x4D01B` inside `Fatal()`, which
prints a message and exits. The message itself was read with
[`SCRDUMP.COM`](tools/scrdump_build.py), a 47-byte program run after the game
that saves the text screen to a file. The game writes the message to the
screen, so redirecting its output (`C&C > LOG.TXT`) caught nothing.

---

## How it was tested

All tests ran in **DOSBox 0.74-3** with no window (`SDL_VIDEODRIVER=dummy`),
because the screen wasn't visible in the environment Claude worked in.
Settings: 16 MB RAM, `cycles=max`, sound on, `cnc` mounted as C:. Results
were read from whether DOSBox exited or was still running after 20–25 seconds,
using the traps described above.

To prove that a **movie** was actually opened, two changes were made, in
scratch copies only:
- `PlayIntro=Yes` in a copy of `CONQUER.INI`, so the intro movie plays at
  startup. With `No`, as in the installed `CONQUER.INI`, the game goes
  straight to the menu.
- A trap right after `VQA_Open` succeeds in `Play_Movie` (`0x28482`). The trap
  jumps to the game's own "restore screen, then `exit(255)`" sequence at
  `0x5A004`. A quick exit means a movie file was found and opened. A plain
  `exit(0)` from there hangs DOSBox, because the game expects its shutdown
  routine to run first.

| Setup | Trap | Expected | Result |
|---|---|---|---|
| Option A (`START.BAT`) | none | keeps running | ✅ keeps running |
| Option A | `Play_Movie` entry | exits | ✅ exits |
| Option A | after `VQA_Open` succeeded | exits | ✅ exits: a movie opened from `C:\CNCCD\MOVIES.MIX` |
| Option A, `MOVIES.MIX` removed from `CNCCD` (control) | after `VQA_Open` succeeded | keeps running | ✅ keeps running: no movie opened |
| Option B (both patches, all files local, plain `C&C`) | none | keeps running | ✅ keeps running |
| Option B | after `VQA_Open` succeeded | exits | ✅ exits |
| Option B, `MOVIES.MIX` removed (control) | after `VQA_Open` succeeded | keeps running | ✅ keeps running |
| Patch 1 only, all files local | none | (the bug) | exits within ~1 s |
| Original files, MIX copies in `C&C\`, `START.BAT` | none | (the bug) | exits within ~1 s |

One trap in the test harness itself: if DOSBox's `autoexec` runs `START.BAT`
without `CALL`, control never comes back to the `exit` line after it. DOSBox
then stays open whether the game is running or not. The table above uses
`call START.BAT`.

What wasn't checked in these first tests: the picture and sound of the movies,
and playing through a mission. Later, in DOSBox-X with screenshots, the intro
and briefing movies were seen playing, and a mission ran to its end (using a
modified test scenario that is won at once). Option A was also
used on the 86Duino; see
[Command & Conquer on the 86Duino](command-and-conquer-on-86duino.md).

---

## Limitations

- **One disc, one side.** The GDI disc's `MOVIES.MIX` has the GDI and shared
  movies (the intro, `GDI1.VQA`, `GDIEND1.VQA`, …) but not the Nod ones
  (`NOD1PRE.VQA`, `NODEND1.VQA` and others are missing; checked with
  [`mixid.py`](tools/mixid.py)). `GENERAL.MIX` on this disc holds the missions
  of both sides. So with no CD needed, Nod missions should run from the GDI
  files, but the Nod movies would be skipped. This wasn't tested in play. For
  the Nod movies, use the Nod disc's `MOVIES.MIX` and `GENERAL.MIX` instead.
  Option A could keep both discs in two directories, but the game would then
  load files from whichever directory comes first in the list, so that hasn't
  been worked out.
- The patch offsets are for this `GAME.DAT` (MD5
  `9698b64a7ab10901a3a25b61db4d64fc`). `patch.py` refuses to write if the
  bytes differ.
- Machines with more than 64 MB of RAM need one of the
  [workarounds above](#more-than-64-mb-of-ram), whichever option is used.

---

## Tools

New for this page, in [`tools/`](tools/):

| File | What it does |
|---|---|
| [`le_load.py`](tools/le_load.py) | Reads a DOS/4GW-bound LE executable. `info` lists the objects, `dump` writes them with fixups applied (ready for `objdump -D -b binary -mi386 --adjust-vma=…`), `off` converts linear addresses to file offsets, `patch` writes bytes at linear addresses and refuses if a fixup would overwrite them. |
| [`mixid.py`](tools/mixid.py) | Checks whether named files are in a Tiberian Dawn `.MIX` archive (the archive stores only name hashes). |
| [`scrdump_build.py`](tools/scrdump_build.py) | Builds `SCRDUMP.COM`, which saves the DOS text screen to `D:\SCR.BIN`, and prints such a dump as text. |

[`patch.py`](tools/patch.py) applies Option B's patch.

Disassembly steps used:

```
le_load.py GAME.DAT dump out/
objdump -D -b binary -mi386 --adjust-vma=0x10000 out/obj1.bin > obj1.asm
```

Strings were then located in `obj3.bin` (base `0xD0000`), and their addresses
searched for in `obj1.asm`: `%c:movies.mix` led to `Force_CD_Available`,
`?:\` to the startup code, and `-CD` to the command-line parser.
