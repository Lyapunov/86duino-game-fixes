# Trap Storm: when too many trapped instructions kill the 86Duino's keyboard

Under SBEMU, a protected-mode game runs as a client of the DPMI host
**HDPMI32i**. HDPMI32i doesn't let the game do certain instructions itself:
sound-card port accesses, `cli` and `sti`. Each one is trapped, and HDPMI32i
carries it out on the game's behalf (see
[Borrowed Interrupt Flag](borrowed-interrupt-flag.md#the-borrowed-flag)). Each
trap is a trip into ring 0 and back, many times slower than the instruction
itself.

Some games issue these instructions by the thousand: a few hundred a second
are normal, but this game issued about **4,400 a second** with music playing
and **well over a thousand for every palette change** during a fade. On the
86Duino, a storm like that sooner or later **kills the USB keyboard
emulation**. The game keeps running and its animations keep moving, but no key
ever arrives again: not at the game, not at the BIOS, not even in the keyboard
controller. I call this **Trap Storm**.

Unlike [Borrowed Interrupt Flag](borrowed-interrupt-flag.md), this one is
specific to the 86Duino. The same game under the same software in QEMU never
loses its keyboard, because QEMU's keyboard is an emulated 8042 chip, not a
USB keyboard handled by firmware.

| Face | What the program does | Trapped instructions |
|---|---|---|
| **The Delay Drizzle** | Its AdLib driver follows every register write with dummy reads of the AdLib port, as a delay | 43 port accesses + 1 `cli` per register write; about 4,400 a second while music plays |
| **The Palette Blizzard** | Its palette code does `cli`, waits for the screen's horizontal retrace, then `sti`, for each of the 768 colour components | About 1,500 per palette change, repeated for every step of every fade |

The diagnosis and the patch on this page are by **Claude** (Anthropic's Claude
Opus 5.5, working in Claude Code). I tested them on the real 86Duino.

This is a sister page of [Tick Starvation](tick-starvation.md),
[Clock Mirage](clock-mirage.md), [Wet Ink](wet-ink.md),
[Borrowed Interrupt Flag](borrowed-interrupt-flag.md),
[Ghost Frame](ghost-frame.md), [Broken Record](broken-record.md),
[Sealed Gate](sealed-gate.md),
[Side Door](side-door.md),
[Sixteen-Bit Exile](sixteen-bit-exile.md) and [Late Echo](late-echo.md); all eleven are listed in the
[overview of the game fixes](86duino-game-fixes.md). Tick Starvation also kills the 86Duino's
keyboard emulation, but by starving the BIOS of timer ticks. Here the BIOS
ticks run normally the whole time.

## Games

| Game | Year | Files patched | Faces | Fix | Status on 86Duino |
|---|---|---|---|---|---|
| [Wacky Wheels](#case-1-wacky-wheels-1994) | 1994 | `WW.EXE` (v1.1 shareware) | The Delay Drizzle, The Palette Blizzard | 18 sites, 23 bytes (plus the 1-byte [Borrowed Interrupt Flag](borrowed-interrupt-flag.md#case-1-wacky-wheels-1994) fix) | ✅ A whole season with AdLib music, all animations, back to the main menu and a clean quit |
| *next game here* | | | | | |

**Suspects (not tested).** Any protected-mode game run under HDPMI32i +
SBEMU on the 86Duino whose keyboard dies at screen changes, or only with music
on. Other games with the Apogee Sound System (*Rise of the Triad*, *Duke Nukem
3D*, *Shadow Warrior*) may have the same AdLib delay loop. Per-colour
`cli`/`sti` around retrace waits was a common trick in early-1990s palette
code. See [Recipe for the next game](#recipe-for-the-next-game).

---

## The original request

After the [Borrowed Interrupt Flag](borrowed-interrupt-flag.md) fix, the game
was playable, but:

> I was able to play a full race, and although the keyboard freezed again at
> the result screen, I still consider it success.

During the hunt, about the first keyboard diagnostic:

> when I run this version on Vortex86, the keyboard freezes almost
> immediately when the bars show up, I cannot even navigate in the menu to
> start a new race any more.

After the AdLib delay fix:

> in all of these four runs I was able to pass the leaderboard screen after
> the first race, so I feel there is an improvement. However, as a bad news,
> in the three runs of WW_NDQ.EXE, twice the keyboard freezed after the second
> race and once after the third race

After the palette fix:

> I've tested WW_NPQ.EXE and it worked perfectly, I was able to blitz over the
> entire season, watch all the animations and then I went back to the main
> menu where I could properly quit.

---

## Background: what a trap costs

HDPMI32i runs its clients at **IOPL 0**. At IOPL 0, `cli`, `sti`, and `in`/`out`
on ports in HDPMI32i's trap list raise a general-protection fault (#GP). For
each one, the CPU:

1. saves the game's state and switches to ring 0, into HDPMI32i;
2. HDPMI32i decodes the instruction;
3. for a port, it calls SBEMU's handler; for `cli` or `sti`, it changes the
   interrupt flag;
4. it returns to the game, one instruction further on.

An `out` that takes well under a microsecond on real hardware becomes a trip
of many microseconds. A few hundred a second is fine. Thousands a second, in
bursts, is a storm.

How the storm kills the 86Duino's USB keyboard emulation is **not known**. That
emulation runs as firmware in System Management Mode (see
[Tick Starvation](tick-starvation.md#background-how-dos-gets-a-keyboard-on-the-86duino)),
and its code hasn't been examined. What's measured is the effect: the more
trapped instructions, the sooner the keyboard dies, and removing them fixes it.

---

## Case 1: Wacky Wheels (1994)

Beavis Soft / Apogee, version 1.1 shareware. `WW.EXE` is a Watcom C program
bound to the DOS/4G Professional extender, with the Apogee Sound System for
sound. The setup: music AdLib, sound effects PC speaker, under
JEMMEX + `JLOAD QPIEMU.DLL` + `HDPMI32i -x` + SBEMU.

This game has **both** SBEMU problems. The
[Borrowed Interrupt Flag](borrowed-interrupt-flag.md#case-1-wacky-wheels-1994)
fix comes first: without it the game freezes at the title screen. This page
starts where that one ended.

| File | Size | MD5 |
|---|---|---|
| `WW.EXE` (original, v1.1) | 650 437 | `c8232cbd3b985cac9c9a748d9e305ec9` |
| `WW.EXE` with the Borrowed Interrupt Flag fix only (`WW_NOSTI.EXE`) | 650 437 | `93be7fb9f53d7e5846e5c5cc03c0b826` |
| `WW.EXE` fully fixed (`WW_NP.EXE`) | 650 437 | `ce66ad5c7f195cace92341528a4dbd51` |

All tools mentioned here are in [`tools/`](tools/). Addresses are linear
addresses in the loaded program; `le_load.py WW.EXE off ADDRESS` converts them
to file offsets.

### Step 1: The symptom

After a full six-lap race, on the screen "LEADER BOARD AFTER RACE 1", the
karts kept animating but no key did anything. The leaderboard loop
(`0x2C316`–`0x2C59B`) animates on the game's timer ticks and leaves only when
the flag at `0x88B40` is set. Enter or the accelerate key (Alt) sets it, and
only the game's own keyboard handler writes it. So the timer was alive, but
key presses were no longer reaching the game.

### Step 2: Not reproducible in QEMU

In the [QEMU test machine](borrowed-interrupt-flag.md#tools), with the same
JEMMEX + HDPMI32i + SBEMU setup and the user's own `WACKY.CFG`, the leaderboard
always worked. The measurements found nothing wrong:

- The timer interrupt ran at 280 Hz in the race, after the finish and on the
  leaderboard.
- The sound timer handler passes ticks on to the BIOS at about 18.2 Hz.
- The keyboard handler never interrupted itself (checked with 14 key events in
  a row).

### Step 3: Narrowing it down on the 86Duino

A test build that ends the race at the first crossing of the line made each
test take seconds instead of minutes. It is for testing only: the race counts
1 lap, without checkpoints:

```
python3 tools/patch.py WW.EXE WW_QUICK.EXE 0x7E63D:FB:90 \
    0x507FB:0F854B010000:909090909090 0x50812:74:EB 0x57EA1:06:01 0x57F33:06:01
```

(The first patch is the Borrowed Interrupt Flag fix. Hold Alt from the start on
track 1 for about 10 seconds.) The 86Duino results:

- The freeze needed **AdLib music**. With music off, or with no sound at all,
  the leaderboard worked.
- With AdLib it froze about **19 times out of 20**.

### Step 4: A watchdog that changed nothing

The usual suspects for a dead keyboard are the PIC (IRQ 1 masked, or stuck "in
service" after a lost end-of-interrupt) and the keyboard controller (a byte
nobody reads). A test build hooked the sound timer handler to repair all three
every 64 ticks: unmask IRQ 1, send a specific EOI, read the stuck byte. It
**didn't help**, and its markers never appeared on screen.

It later turned out the markers could never have shown. They were drawn with an
`inc` on VGA memory in planar mode, which reads back only one plane, and +1 on
a colour index is often invisible. A lesson for later diagnostics: write whole
bytes, with the map mask set to all planes, and check in QEMU that they show up
on the screen in question.

### Step 5: Diagnostic cells

The next build only *looked*: two rows of eight cells at the top left of the
screen, redrawn from the timer handler. A tall cell meant 1. Row 1 showed IRQ 1
masked, in service and requested, the keyboard controller's output buffer, the
game's keyboard handler (busy, and "read a key in the last second"). Row 2 showed
the last byte the game read from port `60h`. The photos of the frozen
leaderboard read:

| Cell | Value | Meaning |
|---|---|---|
| heartbeat | blinking | the timer runs |
| IRQ 1 masked / in service / requested | 0 / 0 / 0 | the PIC is fine |
| keyboard controller buffer full | 0 | **no byte is waiting** |
| game handler busy / key seen recently | 0 / 0 | the game is fine and idle |
| last byte | `9C` | the release of Enter, the key that led to the leaderboard |

The PIC and the game were fine. **Nothing was arriving in the keyboard
controller at all.**

This build also had a side effect, and it became the key clue. With AdLib, it
froze the keyboard **already in the menu**, within seconds. With music off, it
froze on the leaderboard, which the plain game never did without music. The
diagnostic added only a few port reads per redraw, including `in 64h`, the
keyboard controller's status port. On the 86Duino, the USB keyboard emulation
intercepts that port itself. **More port work meant an earlier freeze.**

### Step 6: The BIOS side

The second diagnostic does no port I/O at all. It reads the BIOS data area
instead, which DOS/4G maps 1:1. Its source is
[`ww_kbdcells.S`](tools/ww_kbdcells.S), and
[`ww_kbdcells_build.py`](tools/ww_kbdcells_build.py) builds it into a copy of
`WW.EXE`. Row 1:

| Cell | Tall means |
|---|---|
| 0 | heartbeat (blinks while the timer runs) |
| 1 | the BIOS tick counter `0:046C` moved since the last redraw |
| 2 | the BIOS tick counter was ever seen standing still (sticky) |
| 3 | the BIOS keyboard buffer has keys (`0:041A` ≠ `0:041C`) |
| 4 | the BIOS shift flags `0:0417` say Ctrl or Alt is held |
| 5 | the game's keyboard handler is busy |
| 6 | the game read a key in the last ~1 s |
| 7 | the handler was ever seen busy (sticky) |

Row 2 is again the last byte the game read. On the frozen leaderboard, holding
Ctrl:

- cells 0 and 1 blinking and tall: **the BIOS timer runs**. Cell 2 short: it
  never stopped. So this is **not** [Tick Starvation](tick-starvation.md).
- cells 3 and 4 short: **the BIOS gets no keys either**, so the game's keyboard
  hook wasn't lost to the BIOS.
- row 2 = `B8`: the release of Alt, the accelerate key held to the finish line.

Nothing reaches the keyboard controller, the BIOS or the game, while everything
else runs. **The 86Duino's USB keyboard emulation itself has died.**

The game's code has no other keyboard I/O. Its only `in 60h`/`out 61h` are in
its own keyboard handler, and the other "64h" hits in the disassembly are the
number 100.

### Step 7: Counting the storm

Step 5 suggested a dose effect, so I counted the trapped instructions:

- **The Delay Drizzle.** The AdLib write routine at `0x502C8` does
  `pushf / cli`, `out 388h` (register), **6 × `in 388h`**, `out 389h` (value),
  **35 × `in 388h`**, `popf`. On a real OPL2 chip the dummy reads are a delay.
  Under SBEMU each one is a trap that does nothing useful. A counter in QEMU
  measured about **100 AdLib writes a second** while music plays. That's about
  4,400 trapped instructions a second, nearly all inside the timer interrupt.
- **The Palette Blizzard.** The palette read routine (`0x36CCA`) and the
  palette write routine (`0x37CF1`) do this for each colour component:

  ```
  37D2E  FA        cli
  37D2F  EC        in   al,dx          ; dx = 3DAh, wait for the end of ...
  37D30  A8 01     test al,1
  37D32  E0 FB     loopne 37D2F
  37D34  EC        in   al,dx          ; ... and the start of a horizontal retrace
  37D35  A8 01     test al,1
  37D37  74 FB     je   37D34
  37D39  FB        sti
  ```

  That's 768 `cli`/`sti` pairs, about **1,500 traps per palette change**, spread
  over about 25 ms of retrace waiting (768 scan lines). A fade does this
  for every step, and screen changes like the one into the leaderboard fade
  out and in. The page flip (`0x37DE0`) and the vertical-retrace wait
  (`0x37DC7`) have one pair each, twice a frame.

Both fit the pattern: the freeze needs music (the Drizzle), and it strikes at
screen changes (the Blizzard).

### Step 8: Ruled out along the way

- **A leaking interrupt flag.** At IOPL 0, `popf` can't change the interrupt
  flag. If HDPMI32i really cleared it on the trapped `cli`, every
  `pushf / cli … popf` from the main program would leave interrupts off. A
  counter in QEMU found 0 such cases in 220 writes from the main program, so
  HDPMI32i handles that pattern correctly.
- **Skipping repeated AdLib writes.** A register cache in front of the write
  routine would skip a write of a value the register already holds. In QEMU
  only 14–17% of the writes were repeats. Not worth it.

### Step 9: The fix

**Part A: The Delay Drizzle.** Jump over both dummy-read loops. Two trapped
port writes per register write remain:

| Linear | File offset | Original | Patched |
|---|---|---|---|
| `0x502E2` | `0x8DF36` | `B9 06 00 00 00` (`mov ecx,6`) | `EB 10 90 90 90` (jump to the `out 389h`) |
| `0x502FB` | `0x8DF4F` | `89 DA` (`mov edx,ebx`) | `EB 69` (jump to the `popf`) |

**Part B: The Palette Blizzard.** Replace the 8 `cli`/`sti` pairs around the
retrace waits with `nop`. The waits themselves stay, so the palette still
changes during retrace. The joystick routine's own `cli`/`sti` are left alone.

| Routine | `cli` at (file offset) | `sti` at (file offset) |
|---|---|---|
| palette read, red | `0x36CF2` (`0x74946`) | `0x36CFD` (`0x74951`) |
| palette read, green | `0x36D0F` (`0x74963`) | `0x36D1A` (`0x7496E`) |
| palette read, blue | `0x36D2C` (`0x74980`) | `0x36D37` (`0x7498B`) |
| palette write, red | `0x37D2E` (`0x75982`) | `0x37D39` (`0x7598D`) |
| palette write, green | `0x37D53` (`0x759A7`) | `0x37D5E` (`0x759B2`) |
| palette write, blue | `0x37D78` (`0x759CC`) | `0x37D83` (`0x759D7`) |
| vertical-retrace wait | `0x37DCF` (`0x75A23`) | `0x37DDA` (`0x75A2E`) |
| page flip | `0x37E01` (`0x75A55`) | `0x37E12` (`0x75A66`) |

All of them `FA` → `90` and `FB` → `90`. `le_load.py off` confirms that no
fixup touches any patched byte.

The complete command, including the Borrowed Interrupt Flag fix (`0x7E63D`):

```
python3 tools/patch.py WW.EXE WW_NP.EXE 0x7E63D:FB:90 \
    0x8DF36:B906000000:EB10909090 0x8DF4F:89DA:EB69 \
    0x74946:FA:90 0x74951:FB:90 0x74963:FA:90 0x7496E:FB:90 0x74980:FA:90 0x7498B:FB:90 \
    0x75982:FA:90 0x7598D:FB:90 0x759A7:FA:90 0x759B2:FB:90 0x759CC:FA:90 0x759D7:FB:90 \
    0x75A23:FA:90 0x75A2E:FB:90 0x75A55:FA:90 0x75A66:FB:90
```

The result has MD5 `ce66ad5c7f195cace92341528a4dbd51`. Rename it to `WW.EXE`
(keep the original), or start it by its new name.

**Part A is for SBEMU only.** On a PC with a real AdLib or Sound Blaster
card, the OPL2 chip needs those delays, and the patched game may lose notes.
Part B is harmless anywhere.

### Step 10: Tests

All builds on the 86Duino with AdLib music, PC-speaker sound effects, under
SBEMU. "Quick" builds add the test-only quick race of Step 3.

| Build | Fixes | 86Duino |
|---|---|---|
| `WW_NOSTI.EXE` | Borrowed Interrupt Flag | Leaderboard after race 1 froze about 19 times out of 20 |
| Diagnostic of Step 5 (quick) | + port reads every 32 ticks | Froze **in the menu** with AdLib; on the leaderboard even without music |
| `WW_ND.EXE` and its quick version | + Part A | Leaderboard 1 passed in 4 of 4 runs, but the quick version froze after race 2 (twice) and race 3 (once) |
| `WW_NP.EXE` quick version (`WW_NPQ.EXE`) | + Part A + Part B | ✅ **A whole season**: every leaderboard, all animations, back to the main menu and a clean quit |

In QEMU every build ran normally, and the music played in all of them
(checked in the recorded WAV file).

### Loose ends

- **The mechanism inside the 86Duino.** Why a storm of traps kills the USB
  keyboard emulation is unknown. Possibilities include a timeout inside the SMM
  firmware, or a USB transfer that misses its window, but nothing was traced.
  The evidence is the dose effect alone: more traps, earlier freeze; fewer
  traps, no freeze.
- **Full-length play.** The season was played with the quick-race build. The
  full build `WW_NP.EXE` has exactly the same fixes, just without the
  shortened races, and its earlier stage (`WW_ND.EXE`) already completed a full
  six-lap race with the leaderboard working.
- **Other trap sources.** About 300 trapped instructions a second remain while
  music plays (the AdLib `cli` and two port writes per register write), plus
  the joystick routine if a joystick is selected. None caused trouble in the
  season test.

---

## Recipe for the next game

1. **The symptom.** On the 86Duino, under HDPMI32i + SBEMU, the keyboard dies
   while the game keeps running, typically at a screen change or only with
   music on. In QEMU the same setup works.
2. **Rule out the easy cases.** If the freeze is total and happens at the first
   keypress, check [Borrowed Interrupt Flag](borrowed-interrupt-flag.md) first.
   If the game takes over the timer, check
   [Tick Starvation](tick-starvation.md).
3. **Look before touching.** A diagnostic like
   [`ww_kbdcells.S`](tools/ww_kbdcells.S) tells you whether the keys still
   reach the BIOS and whether the BIOS timer runs. **Don't read ports `60h` or
   `64h` from the diagnostic.** The 86Duino's keyboard emulation intercepts
   them, and the diagnostic itself becomes part of the storm. If the BIOS tick
   runs and no key arrives anywhere, it's a Trap Storm candidate.
4. **Count the traps.** Search the disassembly for:
   - loops of `in` on a sound-card port right after an `out` to it (AdLib
     `388h`, Sound Blaster `22xh`): delay reads;
   - `cli` … `sti` inside loops, especially around `in al,dx` with
     `dx = 3DAh` (retrace waits) in palette or page-flip code;
   - `pushf / cli … popf` in code that runs many times a second.
5. **Fix:** skip the delay reads (SBEMU only), and replace `cli`/`sti` around
   retrace waits with `nop`. Use `le_load.py off` for the file offsets and the
   fixup check.
6. **Test** on the 86Duino with music on. A test build that makes the
   failing moment come quickly (here: a race that ends at the first crossing)
   saves a lot of time. Freezes that become rarer but don't vanish mean there's
   still more storm to find.

## Tools

In [`tools/`](tools/):

| File | What it does |
|---|---|
| `ww_kbdcells.S`, `ww_kbdcells_build.py` | The Wacky Wheels keyboard diagnostic of Step 6. The build script assembles the source (GNU binutils) and hooks it into a copy of `WW.EXE`. The addresses are specific to `WW.EXE` v1.1. The idea (cells drawn from the timer handler, BIOS data area only, no keyboard-port reads) carries over to other games. |
| `le_load.py` | Reads LE executables (DOS/4G, DOS/4GW, CauseWay): object list, object dumps with relocations applied, linear address → file offset, fixup check. |
| `patch.py` | Applies `OFFSET:OLD:NEW` byte patches, checking the old bytes first. |
| `qemu_sbemu.sh`, `qemu_mon.py`, `fat12.py` | The QEMU test machine of [Borrowed Interrupt Flag](borrowed-interrupt-flag.md#tools). It can't reproduce Trap Storm, but it shows whether a patched build still runs, plays music and reacts to keys. `qemu_mon.py 'pmemsave 0 0x4000000 "out/m.bin"'` dumps the guest's memory, which is how the counters in Step 7 and Step 8 were read. |

No game files are included in this repository. Wacky Wheels v1.1 is shareware.

## Sources

- [SBEMU](https://github.com/crazii/SBEMU), release 1.0.0-beta.5: JEMMEX,
  `QPIEMU.DLL`, HDPMI32i and SBEMU.
- [HX DOS Extender / HDPMI](https://github.com/Baron-von-Riedesel/HX), by
  Japheth: HDPMI32i, the I/O-trapping DPMI host.
- [Intel 64 and IA-32 Architectures Software Developer's Manuals](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html):
  Vol. 1, "I/O Privilege Level"; Vol. 2, `CLI`, `STI`, `POPF`, `IN`, `OUT`.
- [Vortex86EX datasheet](https://www.86duino.com/wp-content/uploads/2013/11/Vortex86EX_A9123_V14_86duino.pdf):
  keyboard controller and legacy USB SMI.
- Yamaha YM3812 (OPL2) application manual: the register write delays (3.3 µs
  after the address, 23 µs after the data) that the dummy reads stand in for.
- [Ralf Brown's Interrupt List](https://www.ctyme.com/rbrown.htm): BIOS data
  area (`0:0417`, `0:041A`, `0:041C`, `0:046C`), VGA input status `3DAh`.
