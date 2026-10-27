# 86Duino game fixes

Some old DOS games don't run on the 86Duino, even though the 86Duino is a real
x86 PC. These pages explain why, game by game, and give small binary patches
that fix them. Every 86Duino fix has been tested on the real 86Duino.

There is also one page that isn't about an 86Duino problem: a
[no-CD patch for Command & Conquer](#no-cd-patch-command--conquer).

The diagnosis and the patches are by **Claude** (Anthropic's Claude Opus 5.5,
working in Claude Code). I tested them on my 86Duino.

## The issues

| Issue | Symptom | Cause in one line | Page |
|---|---|---|---|
| **Tick Starvation** | The keyboard stops working after a few seconds, while the game keeps running | The game stops passing timer ticks to the BIOS, and the 86Duino's USB keyboard emulation needs them | [tick-starvation.md](tick-starvation.md) |
| **Clock Mirage** | The game freezes completely, keys included | The game measures a clock in a way that only worked on 1991 PCs, and acts on a phantom result: a 140 Hz screen, a floppy motor that never ticks, a speed difference that comes out as zero, a delay that climbs one step per frame | [clock-mirage.md](clock-mirage.md) |
| **Wet Ink** | Garbage pixels ("mirage" barrels and walls), then a crash | The game writes into its own code and runs it right away; the 86Duino's CPU sometimes still runs the old bytes | [wet-ink.md](wet-ink.md) |
| **Borrowed Interrupt Flag** | Under SBEMU the game freezes at the first keypress, keys included, and never recovers | HDPMI32i, the DPMI host SBEMU needs, does every `sti` on the game's behalf, and crashes on the `sti` right before an interrupt handler's `iret` | [borrowed-interrupt-flag.md](borrowed-interrupt-flag.md) |
| **Trap Storm** | Under SBEMU the keyboard dies, typically at a screen change and only with music on, while the game keeps running | The game issues thousands of instructions HDPMI32i must trap (AdLib delay reads, `cli`/`sti` in palette code), and the storm kills the 86Duino's USB keyboard emulation | [trap-storm.md](trap-storm.md) |
| **Ghost Frame** | A game that uses EMS shows a black screen or garbage, crashes in its decoders, saves broken files, or plays whistles for sound effects | The 86Duino's BIOS moves disk data by DMA, which bypasses the EMS manager's paging: reads into the EMS page frame land in the RAM behind it, and writes from it store that RAM | [ghost-frame.md](ghost-frame.md) |
| **Broken Record** | All digital sound (music and effects) turns into the same quarter-second loop, "e-e-e-e", and every new sound gets stuck the same way (with FM music, only the effects) | Under SBEMU the game's Sound Blaster driver stops getting its IRQ after a few interrupts, so the sound library never refills the DMA buffer the emulated card keeps looping | [broken-record.md](broken-record.md) |
| **Sealed Gate** | Under SBEMU a DOS/4GW game shows the DOS/4GW banner and drops back to DOS (exit code 7) | The game calls its real-mode sound driver with a software interrupt straight from protected mode; under HDPMI32i that faults in a loop until DOS/4GW gives up | [sealed-gate.md](sealed-gate.md) |
| **Side Door** | Under SBEMU the game runs normally but makes no sound at all | The game's DOS extender uses the DPMI host only when Windows is running; on plain DOS it takes JEMMEX's VCPI and runs at ring 0, so its sound card I/O goes past HDPMI32i and SBEMU never hears it | [side-door.md](side-door.md) |
| **Sixteen-Bit Exile** | Under SBEMU a 16-bit protected-mode game (Borland RTM) stops with *"Loader error (0025)"* | SBEMU's DPMI host serves 32-bit programs only; the 16-bit host that can run the game won't install next to it, can't pass its sound I/O to SBEMU, and lets Borland's runtime trample its own exception frames | [sixteen-bit-exile.md](sixteen-bit-exile.md) |
| **Late Echo** | Under SBEMU the game's sound driver fails to start, and the game runs silent | The driver finds the card's IRQ by asking for an interrupt (DSP command `F2h`) and waiting briefly; SBEMU can only raise it at its next real sound interrupt, too late | [late-echo.md](late-echo.md) |

## Patched games

| Game | Year | Issue | Files patched | Details |
|---|---|---|---|---|
| California Games II | 1990 | Tick Starvation | `CGII.EXE` | [Case 4](tick-starvation.md#case-4-california-games-ii-1990) |
| Chasm: The Rift | 1997 | Sixteen-Bit Exile (all four faces): "Loader error (0025)" under SBEMU | none: `HDPMI16X.EXE` (HDPMI16i, 2 sites) + `SBFWD16.COM`, started by `CHASMSB.BAT` | [Case 1](sixteen-bit-exile.md#case-1-chasm-the-rift-1997) |
| Civilization | 1991 | Clock Mirage | `CIV.EXE`, `MGRAPHIC.EXE` | [Case 1](clock-mirage.md#case-1-civilization-1991) |
| Comanche 2.0 | 1995 | Side Door (The Silent Cockpit): runs under SBEMU but completely silent | `COMANCHE.EXE` (1 byte) | [Case 1](side-door.md#case-1-comanche-20-1995) |
| Command & Conquer | 1995 | DOS/4GW crashes with more than 64 MB of RAM; exit code 7 with HDPMI32i + SBEMU loaded | `GAME.DAT` (1 byte: skips the score screen), plus XMS capped below 64 MB | [command-and-conquer-on-86duino.md](command-and-conquer-on-86duino.md) |
| Disney's Aladdin | 1994 | Ghost Frame (The Phantom Whistle): music fine, sound effects only whistles | none: load `GHOSTFIX.COM` (tools) before the game, `GHOSTFIX /U` after | [Case 4](ghost-frame.md#case-4-disneys-aladdin-1994) |
| The Duel: Test Drive II | 1989 | Tick Starvation | `TD2EGA.EXE`, `TD2CGA.EXE` | [Case 3](tick-starvation.md#case-3-the-duel-test-drive-ii-1989) |
| The Elder Scrolls: Arena | 1994 | Ghost Frame: just exits at startup | none: load `GHOSTFIX.COM` (tools) before the game | [Case 2](ghost-frame.md#case-2-the-elder-scrolls-arena-1994) |
| The Elder Scrolls II: Daggerfall | 1996 | Wet Ink (Runaway Brush): "error 519" | `FALL.EXE` (v1.07.213) | [Case 1](wet-ink.md#case-1-the-elder-scrolls-ii-daggerfall-1996) |
| Grand Prix Circuit | 1988 | Tick Starvation | `GPEGA.EXE` | [Case 1](tick-starvation.md#case-1-grand-prix-circuit-1988) |
| Grand Theft Auto | 1997 | Broken Record (The Stuck Groove): music and effects loop a quarter of a second | `GTA8.EXE` (v11.5, 2 sites, 74 bytes) | [Case 1](broken-record.md#case-1-grand-theft-auto-1997) |
| Lemmings 3D | 1995 | Ghost Frame: garbage on screen, then unusable; then Late Echo (The Unanswered Doorbell) and Broken Record: no sound under SBEMU | `SBL0.BIN` (fixed port/IRQ/DMA + Broken Record fix); `L3D.EXE`, `SETUP.EXE` (settings in the game folder); load `GHOSTFIX.COM` before the game | [Ghost Frame Case 3](ghost-frame.md#case-3-lemmings-3d-1995), [Late Echo Case 1](late-echo.md#case-1-lemmings-3d-1995), [Broken Record Case 4](broken-record.md#case-4-lemmings-3d-1995) |
| Mortal Kombat II | 1994 | Sealed Gate (The Endless Knock): exits right after the DOS/4GW banner under SBEMU; then Broken Record (The Stutter Cavalcade): every sound effect a short "e-e-e" | `MK2.EXE` (extender swap + 18 sites), `SBL.BIN` (5 sites, 78 bytes), `CMOS` set to IRQ 5 | [Sealed Gate Case 1](sealed-gate.md#case-1-mortal-kombat-ii-1994), [Broken Record Case 3](broken-record.md#case-3-mortal-kombat-ii-1994) |
| Mortal Kombat 3 | 1995 | Broken Record (The Stuck Groove): "cannot detect sound hardware", then the same IRQ dependence as GTA | `MK3.EXE` (2 sites, 76 bytes), plus a ready-made `DIG.INI` | [Case 2](broken-record.md#case-2-mortal-kombat-3-1995) |
| Railroad Tycoon | 1990 | Clock Mirage (Endless Staircase) | `MGRAPHIC.EXE` (+ `EGRAPHIC`, `CGRAPHIC`, `TGRAPHIC`) | [Case 2](clock-mirage.md#case-2-railroad-tycoon-1990) |
| Sensible Soccer | 1993 | Tick Starvation | `SOC.EXE` | [Case 5](tick-starvation.md#case-5-sensible-soccer-1993) |
| Test Drive | 1987 | Tick Starvation (plus held keys) | `TDEGA.EXE` | [Case 2](tick-starvation.md#case-2-test-drive-1987) |
| Ultima Underworld: The Stygian Abyss | 1992 | Ghost Frame (The Lost Delivery, The Ghost Writer): black screen, then garbled menu and broken save files | none: load `GHOSTFIX.COM` (tools) before the game | [Case 1](ghost-frame.md#case-1-ultima-underworld-1992) |
| Wacky Wheels | 1994 | Borrowed Interrupt Flag (The Last-Second STI): freeze at the title under SBEMU; then Trap Storm (The Delay Drizzle, The Palette Blizzard): keyboard dies on the leaderboard | `WW.EXE` (v1.1, 19 sites, 24 bytes) | [BIF Case 1](borrowed-interrupt-flag.md#case-1-wacky-wheels-1994), [Trap Storm Case 1](trap-storm.md#case-1-wacky-wheels-1994) (full patch command) |

All of them except Command & Conquer are ✅ fixed and confirmed on the 86Duino (Grand Theft Auto:
music and sound effects play normally with the patched `GTA8.EXE`, the 8-bit
colour version, under SBEMU; Mortal Kombat 3: sound is perfect with the patched
`MK3.EXE` and the supplied `DIG.INI`, under SBEMU; Mortal Kombat II: with
`MK2FIX.EXE`, `SBLFIX.BIN` and IRQ 5 in its `CMOS` file, "the sound and the
music are perfect and the game is stable enough to play" under SBEMU;
Comanche 2.0: with the one-byte `C2DPMI.EXE`, "it works very well" under
SBEMU; Chasm: The Rift: with `HDPMI16X.EXE` and `SBFWD16.COM`, "it works very
well" under SBEMU). Wacky Wheels with
AdLib music under SBEMU was played through a whole season on the 86Duino (with
a test build whose races end at the first lap), back to the main menu and a
clean quit. Ultima Underworld needs no patch at all: with the resident
`GHOSTFIX.COM` loaded it runs perfectly on the 86Duino, with AdLib music under
SBEMU (which for this real-mode game also needs `JLOAD QPIEMU.DLL`, and about
545 KB of free conventional memory). The same `GHOSTFIX.COM` also gets two
more EMS games to start on the 86Duino, The Elder Scrolls: Arena and
Lemmings 3D; neither starts without it. Arena hasn't been investigated
further. Lemmings 3D also plays with sound under SBEMU with its fixed
`SBL0.BIN` driver. Disney's Aladdin plays its sound effects correctly with
`GHOSTFIX.COM` loaded (without it they are only whistles). Command & Conquer is
✅ playable with a partial solution: with sound and no score screen, or with
the score screen and no sound. With the score-screen skip and full sound,
missions 1 and 2 were completed on the 86Duino and mission 3 started without
problems. The cause of its exit-code-7 crash is still unknown;
[Sealed Gate](sealed-gate.md) is the first suspect.

## No-CD patch: Command & Conquer

Not an 86Duino issue, but needed on a machine without a CD drive, like the
86Duino. No-CD patches for this version of Command & Conquer are no longer
available online, so this one was worked out from scratch.

| Game | Year | What | Files patched | Details |
|---|---|---|---|---|
| Command & Conquer | 1995 | Run without the CD, movies still play | none (built-in `-CD` switch), or `GAME.DAT` (2 sites) | [command-and-conquer-no-cd.md](command-and-conquer-no-cd.md) |

Command & Conquer has been freeware since 2007, and the original CD images can
be downloaded from many places, the Internet Archive among them. **Anyone can
follow this page; no purchased copy is needed.** Tested in DOSBox and, with the
`-CD` switch, on the 86Duino.

> **Warning: more than 64 MB of RAM.** Independent of the CD, the original
> `GAME.DAT` crashes at startup (DOS/4GW error 2001) on machines with more than
> 64 MB of memory, which today means most real hardware. The cause is the
> game's DOS/4GW 1.97 extender. There are several ways around it, each with
> trade-offs; see
> [More than 64 MB of RAM](command-and-conquer-no-cd.md#more-than-64-mb-of-ram).

## Tools

Everything is in [`tools/`](tools/):

| File | What it does |
|---|---|
| `unexepack.py` | Unpacks an EXEPACK-compressed EXE (both header layouts) so it can be disassembled. |
| `exepack_map.py` | Translates an address in the unpacked image to a file offset in the packed original, so the original can be patched in place. |
| `dis16.py` | 16-bit disassembly of address ranges, plus a `--scan` for keyboard, timer and interrupt-vector code (`pip install capstone`). |
| `patch.py` | Applies `OFFSET:OLD:NEW` byte patches, checking the old bytes first. |
| `RETRACE.COM` | DOS diagnostic for the machine: VGA retrace, timer-chip mode, BIOS ticks, DAC readback, floppy-motor countdown. Run as `RETRACE > RT.TXT`. |
| `PITMODE2.COM` | Puts the timer chip into mode 2, to imitate the 86Duino BIOS in an emulator. |
| `retrace_build.py` | Builds `RETRACE.COM` (`pip install keystone-engine`). |
| `cgii_build.py` | Prints and disassembles the California Games II timer-handler patch. |
| `sensible_build.py` | Unpacks Sensible Soccer's PKLITE `SOC.EXE` by emulation (two runs, diffed for relocations) and applies the patch (`pip install unicorn`). |
| `rtycoon_build.py` | Assembles the Railroad Tycoon patches and prints the `patch.py` arguments (`pip install keystone-engine`). |
| `le_load.py` | Reads an LE executable bound to DOS/4G(W) or CauseWay (Command & Conquer's `GAME.DAT`, Daggerfall's `FALL.EXE`, Wacky Wheels' `WW.EXE`): lists objects, dumps them with fixups applied for disassembly, converts linear addresses to file offsets, patches while refusing to overwrite fixups. |
| `mixid.py` | Checks whether named files are inside a Command & Conquer `.MIX` archive. |
| `SMCTEST.COM` | Tests the CPU for [Wet Ink](wet-ink.md): plants a `ret` in code, calls it, counts how often the CPU misses it. Run as `SMCTEST > SMC.TXT`; built by `smctest_build.py` from `smctest.S`. |
| `CPUDIFF.COM` | Differential CPU test: 50 instruction forms, hashed results and flags, to compare two machines. Built by `cpudiff_build.py` from `cpudiff.S`; `CPUDIFF_DOSBOX.TXT` is a DOSBox reference. |
| `CACHEOFF.COM`, `CACHEON.COM` | Turn the CPU caches off and on again (built by `cacheoff_build.py`). |
| `RAMTEST.COM` | XMS memory test (built by `ramtest_build.py`). |
| `ww_kbdcells.S`, `ww_kbdcells_build.py` | A keyboard diagnostic built into a copy of Wacky Wheels' `WW.EXE`: two rows of cells on screen that show whether the BIOS timer runs and where key presses stop arriving, without touching the keyboard ports. See [Trap Storm](trap-storm.md#step-6-the-bios-side). |
| `qemu_sbemu.sh`, `qemu_mon.py`, `fat12.py` | A QEMU DOS test machine with an HD Audio card for testing games under JEMMEX + HDPMI32i + SBEMU, a monitor driver (keys, screenshots, interrupt tracing), and a FAT12 floppy editor for its boot disk. See [Borrowed Interrupt Flag](borrowed-interrupt-flag.md#tools). |
| `ghostfix.S`, `GHOSTFIX.COM` | The [Ghost Frame](ghost-frame.md) fix: a resident INT 13h hook that moves disk transfers to or from upper memory (the EMS page frame, UMBs) through a buffer in conventional memory. `GHOSTFIX /U` removes it. |
| `emsread.S`, `emswrite.S`, `emstest.S` (+ `.COM`) | Tests: DOS file reads into and writes from the EMS page frame, and EMS itself. See [Ghost Frame](ghost-frame.md#tools). |
| `where.S`, `font35.inc`, `WHERE.COM` | Black-screen diagnostic: shows where the CPU is (sampled by the real-time clock's interrupt) and the last text printed, even in 256-colour graphics modes. See [Ghost Frame](ghost-frame.md#step-4-where-is-the-cpu-where). |
| `ledtest.S`, `LEDTEST.COM` | Tests the keyboard's "set LEDs" handshake (the 86Duino's emulation answers "resend"). |
| `crclist.S`, `CRCLIST.COM`, `CRCALL.BAT`, `CRCDIR.BAT` | CRC-32 lists of a game's files, to compare a copy with a known-good one. |
| `i13test.S`, `I13TEST.COM` | QEMU test for GHOSTFIX on a scratch disk. |
| `gta_build.py`, `gta_dmapoll.S` | Builds the Grand Theft Auto fix: Miles reads the playing half of the DMA buffer from the DMA counter instead of waiting for the IRQ. See [Broken Record](broken-record.md#step-7-the-fix). |
| `mk3_build.py`, `mk3_dmapoll.S` | The same fix for Mortal Kombat 3 (Miles 3.02). See [Broken Record](broken-record.md#step-3-the-fix). |
| `sbdiag_build.py`, `sbdiag_stubs.S`, `gtadiag.S`, `GTADIAG.COM` | Counts a Miles Sound Blaster driver's IRQ handler calls and buffer flips (`GTADIAG Z` before, `GTADIAG` after the game). See [Broken Record](broken-record.md#step-6-counting-the-interrupts-on-the-86duino). |
| `mk2_build.py`, `mk2_int80.S`, `mk2_vec68.S`, `mk2_read.S`, `mk2_loader.S` | Builds the Mortal Kombat II fix `MK2FIX.EXE`: DOS/4GW 2.00 swapped in, the sound driver's `int 80h` opened up (DPMI `0300h`, `int 68h`), file reads split into 8 KB pieces. See [Sealed Gate](sealed-gate.md#step-8-building-and-installing). |
| `mk2_cmos.py` | Shows and edits the sound card settings in Mortal Kombat II's `CMOS` file and fixes its checksum. |
| `mk2_sbl_build.py`, `mk2_sbl_dmapoll.S` | Builds `SBLFIX.BIN`, Mortal Kombat II's Sound Blaster driver mixing from its timer tick and the DMA count. See [Broken Record](broken-record.md#case-3-mortal-kombat-ii-1994). |
| `loopcheck.py`, `wavstat.py` | Analyse QEMU sound recordings: the repeat period of a stuck buffer, and loudness over time. |
| `dosbuild.py` | Assembles the `.S` tools above into `.COM` files (GNU binutils). |
| `sbfwd16.S`, `SBFWD16.COM`, `hdpmi16x_build.py` | Run a 16-bit protected-mode game (Borland RTM) under SBEMU: `HDPMI16X.EXE` is HX's HDPMI16i patched to install next to SBEMU's HDPMI32i, `SBFWD16` forwards the game's sound-card I/O to SBEMU. See [Sixteen-Bit Exile](sixteen-bit-exile.md#step-5-building-and-installing). |
| `lem3d_sbl_build.py`, `lem3d_local.py` | Lemmings 3D: builds `SBL0FIX.BIN` (fixed port, IRQ and DMA instead of autodetection, plus the Broken Record fix from `mk2_sbl_dmapoll.S`, whose addresses are now symbols), and moves the settings and saved progress into the game folder. See [Late Echo](late-echo.md#step-6-building-and-installing). |
| `scrdump_build.py` | Builds `SCRDUMP.COM`, which saves the DOS text screen to a file, e.g. to read an error a program printed just before exiting. |

The patches are given as file offsets and bytes on each page, ready for
`patch.py`. No game files are included; you need your own copy of each game.
`patch.py` refuses to write anything if your copy differs from the one
described.
