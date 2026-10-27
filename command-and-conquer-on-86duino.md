# Command & Conquer (1995) on the 86Duino

This page covers what it took to get the DOS version of **Command & Conquer**
running on the 86Duino. Running the game without the CD has its own page,
[Command & Conquer without the CD](command-and-conquer-no-cd.md), and this page
builds on it (Option A, the `-CD` switch).

Two problems turned up:

1. **The 64 MB limit of the DOS extender.** The 86Duino has 128 MB, and the
   game's DOS/4GW 1.97 crashes at start with more than 64 MB. This isn't
   86Duino-specific. It is explained in general on the
   [no-CD page](command-and-conquer-no-cd.md#more-than-64-mb-of-ram). Here it
   only matters which workaround suited this machine. **Fixed** by capping XMS.
2. **Crashes (exit code 7) with HDPMI32i and SBEMU loaded**, which the
   86Duino needs for sound. They were found on one particular setup. The root
   cause isn't found, but there are **fixes that make the game playable**: a
   patch that skips the score screen, where the crash showed up first, or
   leaving out the sound drivers.

**Status:** ✅ playable, with a choice between two trade-offs. With the
score-screen skip and full sound, missions 1–3 ran on the 86Duino without a
crash.

| | Sound, no score screen | Score screen, no sound |
|---|---|---|
| Sound drivers | HDPMI32i + SBEMU loaded | none |
| `GAME.DAT` | with the [score-screen skip](#fix-skipping-the-score-screen) | original (or no-CD patched) |
| `CONQUER.INI` | your sound card settings | `Card=0` |
| Trade-off | no score screen between missions | silent |

The author of these tests prefers sound without the score screen. Players who
would rather keep the score screen and go without sound can do that instead.
Both need XMS capped below 64 MB.

This is a partial solution, and the project stops here. Why the game crashes
under HDPMI32i + SBEMU is still unknown. The findings, the ruled-out causes and
the open questions below are left as a starting point for whoever takes it
further.

The diagnosis and the patch are by **Claude** (Anthropic's Claude Opus 5.5,
working in Claude Code). I tested them on my 86Duino.

## Contents

- [Summary](#summary)
- [The setup](#the-setup)
- [What happened, in order](#what-happened-in-order)
- [Problem 1: the 64 MB limit](#problem-1-the-64-mb-limit)
- [Problem 2: exit code 7 under HDPMI32i and SBEMU](#problem-2-exit-code-7-under-hdpmi32i-and-sbemu)
- [Fix: skipping the score screen](#fix-skipping-the-score-screen)
- [How the exit code was traced](#how-the-exit-code-was-traced)
- [Open questions, for whoever continues](#open-questions-for-whoever-continues)

---

## Summary

Common to both ways of playing:

| Item | Setting |
|---|---|
| XMS driver | HIMEMX **with its `/MAX=` option**, capping XMS below 64 MB |
| Game | `GAME.DAT` started with `C&C -CDC:\CNCCD\` |

Then either HDPMI32i + SBEMU with the score-screen skip (sound), or neither
driver with `Card=0` (score screen, no sound).

What each setup did on the 86Duino:

| Setup | Result |
|---|---|
| No HDPMI32i/SBEMU, XMS **not** capped (128 MB) | ❌ DOS/4GW error 2001 (general protection fault) at start |
| HDPMI32i + SBEMU, not capped | ⚠️ Mission 1 plays, then exit code 7 at the score screen |
| HDPMI32i + SBEMU, `Card=0` | ⚠️ Same crash, so sound playback isn't what triggers it |
| HDPMI32i + SBEMU, XMS capped | ⚠️ Exit code 7 at **varying points**: usually mid-mission, once with the score screen already counting |
| `GAME.DAT` rebound to DOS/32A, with or without HDPMI32i | ❌ Freezes right after DOS/32A starts |
| **No HDPMI32i/SBEMU, XMS capped, `Card=0`** | ✅ Mission 1, score screen, mission 2 |

---

## The setup

- 86Duino with 128 MB of RAM, booting FreeDOS (a 2025 install).
- HIMEMX as the XMS driver.
- At boot, the normal configuration loads **HDPMI32i** (a DPMI host) and
  **SBEMU** (a Sound Blaster emulator that runs on top of HDPMI32i) for the
  86Duino's sound.
- Command & Conquer, GDI disc v1.07, installed under `C:\GAMES\CNC\C&C\`, with
  the CD contents in a directory next to it, started through `START.BAT`
  (`C&C -CDC:\CNCCD\`).

---

## What happened, in order

1. With the normal boot (HDPMI32i + SBEMU), the game played mission 1. At the
   score screen after "Mission Accomplished", the eagle and panels were drawn,
   but the counters never started, and the game dropped to the DOS prompt with
   no message. `DIAG.BAT` caught **exit code 7**.
2. Booting without HDPMI32i and SBEMU gave **DOS/4GW error 2001** at once.
3. In DOSBox-X this reproduced as the 64 MB limit (63 MB runs, 65 MB fails).
   Rebinding the game to the DOS/32A extender fixed it there. On the 86Duino,
   though, the DOS/32A version froze right at start.
4. Capping XMS with HIMEMX `/MAX=` did not stop the exit-code-7 crash under
   HDPMI32i + SBEMU. Over several runs, the crash point moved around:

   > the program still exited with error code 7, but not just from the usual
   > point at the stat screen. Usually a little bit earlier, during the game,
   > but in one in my test it the control flow advanced a little bit further
   > and the stat screen started to come alive, numbers started to show up and
   > animations started rolling.

5. With XMS still capped, but HDPMI32i and SBEMU taken out of the boot and
   `Card=0`:

   > now the very first time I was able to survive the stat screen and mission
   > 2 started

   (SBEMU couldn't be taken out on its own. Leaving the boot sequence half
   changed made it hang later on, so both went.)

---

## Problem 1: the 64 MB limit

The general explanation and the possible workarounds are on the
[no-CD page](command-and-conquer-no-cd.md#more-than-64-mb-of-ram). On the
86Duino:

- The crash without a DPMI host is the 64 MB bug: with XMS capped below 64 MB
  the same boot runs the game. This is the photo of the uncapped crash, in
  text form:

  ```
  DOS/4GW Professional error (2001): exception 0Dh (general protection fault) at 3E58:000024D7
  ...
  CS= 3E58, USE16, byte granular, limit  CA8F, base  115820, acc 9B
  ```

  `USE16` means the fault is in DOS/4GW's own 16-bit code, before the game
  runs.
- **Capping XMS with HIMEMX `/MAX=` is what worked.** The cap must be below
  64 MB. At 2 MB the game doesn't start (too little memory).
- Under HDPMI32i the 64 MB bug doesn't trigger at all. DOS/4GW then runs as a
  client and uses HDPMI32i's memory services instead of its own. So the cap
  makes no difference there, which matches step 4 above.
- The DOS/32A rebinding, which worked at 128 MB in DOSBox-X, froze on the
  86Duino. It runs in raw XMS mode and ignores HDPMI32i unless a V86 memory
  manager such as JEMM is loaded. Since the cap works, this wasn't
  investigated further.

---

## Problem 2: exit code 7 under HDPMI32i and SBEMU

**Symptom:** with HDPMI32i and SBEMU resident, the game exits to DOS with no
message and errorlevel 7, at a different moment in each run. It usually
happens during a mission, sometimes at the score screen.

**What it is not:**

- **Not the game quitting.** A diagnostic build gave 16 of the game's
  `exit()` calls a distinct code from 101 to 116 (see
  [below](#how-the-exit-code-was-traced)). None of them was ever seen. Code 7
  comes from below the game: the extender or the DPMI host ending the program,
  most likely after a fault.
- **Not the sound being played.** It also happens with `Card=0`, when the game
  plays nothing.
- **Not memory size.** It also happens with XMS capped.
- **Not the CD logic** (`-CD` gives `RequiredCD = -2`, so no CD checks run) and
  **not disk space** for the swap file (27.7 GB free).

**What it probably is:** because the crash point varies, the cause is
asynchronous: an interrupt or timing problem, or a resident program changing
state the game depends on. SBEMU traps the Sound Blaster ports and services the
real sound hardware's interrupt even when the game doesn't use sound. It needs
HDPMI32i, so the two couldn't be told apart in these tests. Which one is at
fault is still open.

This was seen with one 86Duino, one FreeDOS install and one SBEMU setup. Other
SBEMU versions or options may behave differently.

---

## Fix: skipping the score screen

With HDPMI32i + SBEMU loaded, the score screen after a mission is where the
crash first showed up, and in every uncapped run it was where the game died.
This patch removes that screen, so the game can be played **with sound**: the
game goes from one mission straight to the next. The crash isn't tied to the
score screen alone: in the diagnostic runs with XMS capped it was also seen
during missions. So this is a workaround, not a cure. In the long play-through
with full sound, though, no crash happened during a mission.

| Linear address | File offset | Old | New | What it does |
|---|---|---|---|---|
| `0x76B50` | `0xCC3F4` | `53` | `C3` | `push ebx` → `ret` at the entry of `Score::Presentation`: the score screen returns at once |

```
patch.py GAME.DAT GAME.NEW 0xCC3F4:53:c3
```

Why it is safe:

- The function is called from three places (`0x325E6`, `0x32657`, `0x76130`).
  Each one pushes one argument and removes it itself (`add esp, 4`) after the
  call, and the function ends in a plain `ret`, so an immediate `ret` leaves
  the stack correct.
- The game already has its own path that returns from this function without
  showing anything (flag at `0xF3087` bit 0, plus `0xF64EC`), so nothing after
  it depends on the screen having run.
- Possible side effect: the running score totals and the hall of fame may not
  be updated.

Results (MD5 of the patched file):

| Starting from | Patches | MD5 |
|---|---|---|
| original `GAME.DAT` | score skip | `76207fd8b561878a2719b36f4f834bd4` |
| original `GAME.DAT` | no-CD patch 1 + score skip | `48ca6a205d977195d253cdc8ee0fb500` |
| original `GAME.DAT` | no-CD patches 1 + 2 + score skip | `2d424f43c545a886fd41e4af5f9ad396` |

**Tested in DOSBox-X** (63 MB, original DOS/4GW, a test scenario that is won at
once): "Mission Accomplished" leads straight to the next movie, then the map
selection, then the mission 2 briefing.

**Tested on the 86Duino** ✅: with the score-screen skip, HDPMI32i + SBEMU
loaded and full sound, mission 1 and mission 2 were played to completion, and
mission 3 started, with no crash.

---

## How the exit code was traced

**The exit code.** COMMAND.COM only reports the exit code through
`if errorlevel N`, which is true for N **or higher**. `DIAG.BAT` runs the game
and then tests from 255 downwards, writing the first match to a file:

```bat
GAMEDIAG -CDC:\CNCCD\ > C:\DIAGOUT.TXT
if errorlevel 255 goto e255
...
if errorlevel 1 goto e1
...
:e7
echo Exit code 7>C:\DIAG.TXT
goto done
```

A pitfall: in COMMAND.COM, a redirection on an `IF` line opens and empties the
file even when the condition is false. So
`if errorlevel 7 echo 7 > DIAG.TXT` on every line doesn't work. Hence the
`goto` ladder. `DIAG.BAT` also saves `mem` and `dir` output and sets
`DOS4G=VERBOSE`, so the extender's startup report ends up in `DIAGOUT.TXT`.

**`GAMEDIAG`.** This is a copy of `GAME.DAT` in which 16 of the game's
calls to `exit()` each get their own exit code, 101–116, by changing the value pushed
as the argument just before the call. If the game ended through its own code,
the code would tell which call. The run kept ending with 7, so those exits
are ruled out. The patches were checked, like all patches here, not to
overlap LE fixups (see [`le_load.py`](tools/le_load.py)).

---

## Open questions, for whoever continues

The project stops here with the partial solution above. If you want to find
the real cause, these are the places to start:

- **HDPMI32i or SBEMU?** Load only HDPMI32i (`HDPMI32i -r`), with `Card=0`. If
  the crashes stop, SBEMU is the problem; if not, HDPMI32i. This needs a clean
  boot-menu entry, because removing SBEMU alone left the boot hanging.
- **Sound without crashes.** Ideas: other SBEMU versions or options (IRQ/DMA,
  OPL off); a different sound card type in the game's setup (Sound Blaster or
  Pro instead of SB16).
- **Why DOS/32A froze.** Raw XMS mode on the 86Duino. Possibly an interaction
  with the 86Duino's USB keyboard emulation, which runs in SMI (see
  [Tick Starvation](tick-starvation.md#background-how-dos-gets-a-keyboard-on-the-86duino)).
  Not needed now that the XMS cap works.
- **What exit code 7 really is.** A dump of the faulting address, if HDPMI32i or
  DOS/4GW can be made to print one, would point at the code that dies.
  Mortal Kombat II later showed one way DOS/4GW ends with exit code 7 under
  HDPMI32i: a protected-mode software interrupt meant for a real-mode driver
  ([Sealed Gate](sealed-gate.md)). Command & Conquer's crash at varying points
  doesn't obviously fit that pattern, but a QEMU interrupt trace up to the
  exit would tell.
