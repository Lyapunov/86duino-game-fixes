# Tick Starvation: the 86Duino keyboard freeze

Some old DOS games lose the keyboard on the 86Duino after a few seconds of play.
The game keeps running and the picture keeps moving, but no key does anything any
more. I call this **Tick Starvation**: as far as we can tell, the game stops feeding
the BIOS its timer ticks, and the BIOS needs those ticks to keep the USB keyboard
working.

The diagnosis and the patches on this page are by **Claude** (Anthropic's Claude
Opus 5.5, working in Claude Code). I tested the patched games on the real
86Duino.

This page is part of a [collection of 86Duino game fixes](86duino-game-fixes.md). It is a
living catalogue. Whenever another game shows the same symptom,
it gets its own section below, and the [recipe](#recipe-for-the-next-game)
gets refined.

## Games

| Game | Year | File patched | Cause | Fix | Status on 86Duino |
|---|---|---|---|---|---|
| [Grand Prix Circuit](#case-1-grand-prix-circuit-1988) | 1988 | `GPEGA.EXE` | Stops calling the BIOS timer ~5 s into a race | 2 bytes | ✅ Fixed |
| [Test Drive](#case-2-test-drive-1987) | 1987 | `TDEGA.EXE` | Never calls the BIOS timer during a race; holding a key relies on BIOS key repeat | 137 bytes (v3) | ✅ Fixed (v3) |
| [The Duel: Test Drive II](#case-3-the-duel-test-drive-ii-1989) | 1989 | `TD2EGA.EXE`, `TD2CGA.EXE` | Stops calling the BIOS timer ~5 s into a race (same code as GPC) | 2 bytes | ✅ Fixed |
| [California Games II](#case-4-california-games-ii-1990) | 1990 | `CGII.EXE` | Never calls the BIOS timer once the game is running (fixes the DOS clock afterwards instead) | 70 bytes | ✅ Fixed |
| [Sensible Soccer](#case-5-sensible-soccer-1993) | 1993 | `SOC.EXE` | Passes ticks to the BIOS only in the menus, never during a match | 4 bytes (in the unpacked EXE) | ✅ Fixed |
| *next game here* | | | | | |

---

## The original request

This is the message that started the job, unedited:

> I'm starting to write up your next job. Look into the directory Gpc, it contains
> the old PC-DOS game Grand Prix Circuit from 1988. I want to run it on a 86Duino
> System-On-A-Chip and when I try it the keyboard stops working in a very short
> time. As far as I know - and this is something you may want to double-check -
> these recent x86 systems always use USB keyboards and they provide it through
> some sort of firmware to MS-DOS which apparently has no idea about USB because it
> was made before the days of USB. However, I have other DOS games that work very
> well with this keyboard firmware, for example Outrun from 1986, it has almost
> never have problems. As an other trivia, I also know that for anti-debug
> purposes these old games very frequently re-program the keyboard controller that
> sometimes serves no real functional purpose from the perspective of the program.
> Anyway, what I want is some kind of binary patch or crack for the Grand Prix
> Circuit which could make it run on 86Duino. Please do some kind of research and
> try to come up with a viable plan to achieve this goal.

After the plan, the follow-ups were *"build the three patched variants and test
them in DOSBox-X"*. Then came the hardware report: *"patch A worked marvelously and
patch B failed, the keyboard stopped working in the menu"*.

---

## Background: how DOS gets a keyboard on the 86Duino

DOS and 1980s games know nothing about USB. They expect an IBM PC keyboard:

- **Keyboard controller.** The keyboard controller (an Intel 8042) sits at I/O
  ports `60h` (data) and `64h` (status/command).
- **IRQ 1 / INT 9.** Each key press raises IRQ 1, which runs the **INT 9**
  handler. That handler reads the scancode from port `60h`.
- **INT 8 / INT 1Ch.** A timer chip (the 8253/8254 PIT) raises IRQ 0 about
  18.2 times a second. That runs the BIOS **INT 8** handler, which updates the
  clock and calls the user hook **INT 1Ch**.

The 86Duino's Vortex86EX chip does have an 8042-compatible keyboard controller
built in, plus "legacy USB" support. With that support, the BIOS makes a USB
keyboard look like an old PC keyboard. According to the
[Vortex86EX datasheet](https://www.86duino.com/wp-content/uploads/2013/11/Vortex86EX_A9123_V14_86duino.pdf)
(§10.10 and §11.3.14, and the "Legacy USB OHCI/EHCI SMI" status bits), this works
through firmware running in System Management Mode. We could not find out exactly
what the 86Duino BIOS does inside that firmware. The Grand Prix Circuit case shows
two things, though: it needs the BIOS timer interrupt to keep running, and it
relies on the old way of acknowledging a key (see
[what didn't work](#what-didnt-work-patch-b)).

Most games take over INT 9, and that is fine on the 86Duino; Outrun is an
example. **Tick Starvation** happens when a game also takes over the timer
interrupt (INT 8) and at some point **stops passing the ticks on to the BIOS**.

---

## Case 1: Grand Prix Circuit (1988)

Accolade / Distinctive Software. The EGA version, started by the menu program
`GP.EXE`.

| File | Size | MD5 |
|---|---|---|
| `GPEGA.EXE` (original) | 87 411 | `fd6fa7785c06420426d9009d6588cb86` |
| `GPEGA.EXE` (patched, fix A) | 87 411 | `db8089722c54485426930b9224618384` |

### Step 1: Look at the files

`GP.EXE` (1 106 bytes) is just a menu. It asks which graphics card you have, then
runs `gpega.exe` with the command-line argument `94857102387604294775`. The game
itself is in `GPEGA.EXE`. Its strings include
`MS Run-Time Library - Copyright (c) 1987, Microsoft Corp`, so it was written in
Microsoft C.

### Step 2: Unpack it

The disassembly looked wrong (jumps into the middle of instructions), and the EXE
header has no relocations. The entry point is a small stub near the end of the
file with the `RB` signature and the message `Packed file is corrupt`. That means
the file is compressed with **Microsoft EXEPACK**. `tools/unexepack.py` reverses
the compression:

```
python3 tools/unexepack.py GPEGA.EXE GPEGA_unp.EXE
entry 0000:e016  stack 1a60:0800  35 relocations  106336 bytes of code/data
```

The game is one 64 KB code segment (segment 0), with its data segment at `108Fh`.

### Step 3: Find everything that touches the keyboard and the timer

```
pip install capstone
python3 tools/dis16.py GPEGA_unp.EXE --scan
```

This lists every place that reads or writes the keyboard, PIC, PIT and port `61h`,
or changes an interrupt vector:

```
in al,60h   (read scancode)            1  0x77b3
in al,64h   (KBC status)               0
out 64h,al  (KBC command)              0
out 60h,al  (KBC data)                 0
out 43h,al  (PIT control)              1  0x6fa3
out 40h,al  (PIT ch0 rate)             4  0x6ff6 0x6ffa 0x7035 0x7037
int 8       (call BIOS timer)          1  0x7128
mov es:[20h],imm  (hook INT 8)         1  0x6fe1
mov es:[24h],imm  (hook INT 9)         1  0x7731
mov es:[58h],imm  (hook INT 16h)       1  0x774f
```

The game **never** touches the keyboard controller's command port (`64h`). It has
no anti-debugging code either (no hooks on INT 1 or INT 3, no trap-flag tricks).
So the "reprogrammed keyboard controller" theory from the request is a good
general rule, but it doesn't apply to this game.

### Step 4: Read the keyboard handler

To disassemble the handler: `python3 tools/dis16.py GPEGA_unp.EXE 7700-7860`

- **Install (`0:770C`).** Saves the old INT 9 and INT 16h vectors and points both
  at the game's own code. The PIC is masked while it does this.
- **INT 9 handler (`0:77A8`).**
  1. Reads the scancode with `in al,60h`.
  2. Pulses bit 7 of port `61h`. This is the IBM PC/XT way of telling the
     keyboard "got it".
  3. Sends end-of-interrupt (EOI) to the PIC and records the key in its own table.
  4. **Never passes the key on to the BIOS.**
- **INT 16h replacement (`0:7858`).** Hands the game's own key buffer to the menus.

Nothing here is unusual for a game of that era.

### Step 5: Read the timer handler (this is where the bug is)

To disassemble the setup code and the handler:
`python3 tools/dis16.py GPEGA_unp.EXE 6ee8-7140`

- **Timer setup.**
  1. Reprograms the timer chip to **100 Hz** (divisor `2E9Ch`).
  2. Hooks INT 8 with the game's own handler at `0:7090`.
- **Passing ticks to the BIOS.** On every 5th tick (about 20 Hz, close to the
  normal 18.2 Hz), the handler calls the routine at `0:70FF`. That routine
  temporarily puts the original BIOS vector back, runs `int 8`, then re-hooks.
- **The countdown flag.** Before calling the BIOS, `0:70FF` checks the byte at
  `[7FECh]`:
  - If it is set, a counter at `[7FEEh]`, started at **100**, counts down.
  - When the counter reaches zero, the routine clears `[7FEDh]`.
  - From then on **the BIOS timer is never called again**.
- **Three setup routines.**
  - At start-up, `0:6F16` sets `[7FEC]=0`: ticks are passed on forever. This is
    why the menus work.
  - Two other routines set `[7FEC]=1`: `0:6EE8` is called from code that loads the track, so it most likely runs
    as the race is being set up,
    and `0:6F6E` is used by the sound code. After 100 passed-on ticks (about
    **5 seconds**) the BIOS gets no more timer interrupts.

On a 1988 PC the only visible effect is that the DOS clock stops while you race.
The intent was probably to keep the BIOS ticking just long enough to switch the
floppy drive motor off, then save CPU time. On the 86Duino, losing the BIOS tick
apparently also kills the USB keyboard emulation. That matches *"the keyboard
stops working in a very short time"*.

### Step 6: The patch

Make the countdown never start. In both setup routines, change
`mov byte ptr [7FECh],1` to `mov byte ptr [7FECh],0`:

| Image address | Instruction before → after |
|---|---|
| `0:6F0E` | `C6 06 EC 7F 01` → `C6 06 EC 7F 00` |
| `0:6F96` | `C6 06 EC 7F 01` → `C6 06 EC 7F 00` |

The game then passes ticks to the BIOS about 20 times a second for the whole
session. The only side effect is that the DOS clock runs about 10% fast while the
game is running.

You don't need to ship an unpacked EXE. EXEPACK stores most bytes as literal runs,
so `tools/exepack_map.py` can find where each byte sits in the packed original:

```
python3 tools/exepack_map.py GPEGA.EXE 6f12 6f9a
6f12  -> file offset 0x7106   bytes there: 01 e9 85 00 55 ba 9c 2e
6f9a  -> file offset 0x718E   bytes there: 01 e4 61 24 fc e6 61 b0
```

EXEPACK has no checksum, so you can patch the bytes in place:

```
python3 tools/patch.py GPEGA.EXE GPEGA_A.EXE 0x7106:01:00 0x718E:01:00
```

`patch.py` checks the original bytes first. If your copy is a different
version, it refuses to write anything.

### Step 7: Test in DOSBox-X before touching the hardware

DOSBox-X can't reproduce the freeze, because its keyboard doesn't depend on the
BIOS timer. It can still prove that the patch doesn't break the game, and that the
BIOS timer really keeps ticking.

- **Setup.** The config used `machine=ega`, `cputype=386`, `cycles=fixed 3000`,
  with the game folder mounted as `C:`.
- **Scripted input.** DOSBox-X's `AUTOTYPE` command typed the keys:
  `AUTOTYPE -w 4 -p 2 enter ×7, up ×20, …` clicks through the menus into a
  qualifying lap, then accelerates for about 40 seconds.
- **Clock check.** Run DOS `TIME` before and after the game, and compare how far
  the DOS clock moved with the real time that passed.
  - The game quits with **Ctrl+X → Y**, but `AUTOTYPE` cannot hold Ctrl down.
  - So for the test only, the copies had the Ctrl+X hotkey remapped to the
    backtick key: in the packed file, byte `0xA295` changed from `18h` to `60h`.
  - Never use those copies on the 86Duino.

| Variant | Race input works | DOS clock over a ~72 s run |
|---|---|---|
| Original | yes | 18.6 s (stops ~5 s into the race) |
| **A** (timer fix) | yes | **71.7 s** |
| B (no port 61h pulse) | yes | 18.6 s |
| A+B | yes | 71.7 s |

### Step 8: Test on the 86Duino

| Variant | Result |
|---|---|
| **A** | ✅ **Works.** The keyboard stays alive through the whole race. |
| B | ❌ Keyboard froze **already in the menu**; never reached the race. |
| A+B | not tried (B alone already broke the keyboard) |

**Fix A is the fix for Grand Prix Circuit.**

### What didn't work (patch B)

The plan had a second idea. The game's keyboard handler sets bit 7 of port
`61h`, and the Vortex86EX datasheet (§11.3.19) says *"When writing to port 061,
bit 7 must be a 0"*. So patch B removed that pulse: file offsets
`0x79AA–0x79B5`, the 12 bytes `E4 61 8A E0 0C 80 E6 61 86 E0 E6 61`, replaced
with `NOP`s.

On the real 86Duino, B froze the keyboard **in the menu**, where the timer is
still being passed on, so the failure has nothing to do with the timer bug. In
other words, the 86Duino's keyboard emulation **needs** the old XT-style port
`61h` acknowledge, or something it causes. Lesson: **leave a game's own
keyboard acknowledge alone.** Its key-handling code was not the problem.

---

## Case 2: Test Drive (1987)

Accolade / Distinctive Software, the EGA version. This is the same developer as
Grand Prix Circuit, one year earlier. The request was: *"Please do very similar
patching with the games in TestDrive and TestDrive2 - I'm experiencing the very
same problem with them."*

| File | Size | MD5 |
|---|---|---|
| `TDEGAX.EXE` (original, 1987) | 66 517 | `93e5a236278e61d4586401276d4cb347` |
| `TDEGA.EXE` (the user's copy, see below) | 66 517 | `407084b66ad21e713098d7f563b5ec91` |
| `TDEGAX.EXE` (patched, v3) | 66 517 | `7738afc5536067b2222cbbb779dd94fc` |
| `TDEGA.EXE` (patched, v3) | 66 517 | `520d1fccb93eec5478d10419a266a3ae` |

The patch went through three versions. v1 and v2 are steps 5–7; the hardware
test of v2 led to v3 (steps 8–10).

### Step 1: Look at the files

`TDH.EXE` is the menu. It asks for the graphics card and runs
`tdega.exe 94857102387604294775`, the same argument as Grand Prix Circuit.
The folder had two copies of the game:
- `TDEGAX.EXE`, dated 1987;
- `TDEGA.EXE`, modified later.

They differ in only 4 bytes. Two `int 16h` calls with `AH=2`, which read the
Shift/Ctrl/Alt state, are replaced by `mov al,0` (image `0:6810` and
`0:68F6`). The timer patch below works on both copies, at the same offsets.

### Step 2: Unpack it

The file is EXEPACKed again, but with an **older EXEPACK header**: 16 bytes,
with no "skip length" field, so the `RB` signature sits at offset 14 instead
of 16. `tools/unexepack.py` now accepts both layouts:

```
python3 tools/unexepack.py TDEGAX.EXE TDEGAX_unp.EXE
entry 0000:a50c  stack 14a5:0800  47 relocations  81424 bytes of code/data
```

### Step 3: Scan

```
in al,60h   (read scancode)            0
out 43h,al  (PIT control)              1  0x69d7
out 40h,al  (PIT ch0 rate)             4  0x6981 0x6983 0x6a17 0x6a1b
int 8       (call BIOS timer)          1  0x6a5f
int 16h                               13  ...
mov es:[20h],imm  (hook INT 8)         1  0x6a02
mov es:[24h],imm  (hook INT 9)         0
mov ah,25h  (DOS set vector)           4  0x1f29 0x1f3a 0x4926 0x492f
```

Two things are different from Grand Prix Circuit:
- **No keyboard handler at all.** The game never hooks INT 9 or reads port
  `60h`. Every key goes through the BIOS (`int 16h`). So the BIOS's own
  keyboard code is the only thing between the USB emulation and the game.
- **A second INT 8 hook.** It is installed through DOS (`mov ah,25h` with
  `al=8` at `0:4926`/`0:492F`).

### Step 4: Read the timer code

To disassemble: `python3 tools/dis16.py TDEGAX_unp.EXE 694a-6a75`

The handler at `0:6A1F` counts ticks. Every *N* ticks it calls the BIOS, but
only if the flag `[643Fh]` is set. Three routines set the timer up:

| Routine | Rate | *N* (`[6434h]`) | `[643Fh]` | Called from |
|---|---|---|---|---|
| `0:698C` | 100 Hz | 32000 | **0** | the race start (`0:48FA`) |
| `0:699E` | 100 Hz | 5 | 1 | start-up and the menus |
| `0:69B6` | any | 65536 ÷ divisor | 1 | not used |

So in menus the BIOS gets 20 ticks a second. **From the moment a race starts it
gets none at all**: not after 5 seconds as in Grand Prix Circuit, but
immediately.

Right after `0:698C`, the race start (`0:4908`) also hooks INT 8 with a
second handler at `0:3B1F`. That handler first calls the previous vector (the
`0:6A1F` handler), then does per-tick race work, such as smoothing the
engine-sound pitch. At the end of the race (`0:1F2F`) both are unhooked again.

### Step 5: The patch

**Part 1: let the race pass ticks on.** Make `0:698C` continue into `0:699E`'s
set-up (100 Hz, every 5th tick to the BIOS, flag on). Two bytes after its
`mov dx,2E97h` turn into a short jump:

| Image address | Before → after |
|---|---|
| `0:6990` | `C7 06` (`mov word ptr [6434h],7D00h`…) → `EB 10` (`jmp 69A2h`) |

**Part 2: don't knock out the second handler.** The DOSBox-X test of part 1
alone showed a trap. The `0:6A1F` handler calls the BIOS the same way Grand
Prix Circuit does:
1. It writes the BIOS vector back into the interrupt table.
2. It runs `int 8`.
3. It writes **its own** address back.

In a race, step 3 overwrites the `0:3B1F` hook, which then never runs again.
The fix calls the BIOS without touching the interrupt table:

| Image address | Before → after |
|---|---|
| `0:6A4C` | `06 33 C0 8E C0 A1 26` → `9C FF 1E 26 64 EB DE` |

The new code is `pushf` / `call far [6426h]` (the saved BIOS vector) /
`jmp 6A31h`. `pushf` + `call far` behaves exactly like `int` here, because
interrupts are already off inside the handler. The rest of the old block is
now dead code.

In the packed files:

```
python3 tools/exepack_map.py TDEGA.EXE 6990 6a4c
6990  -> file offset 0x63B6   bytes there: c7 06 34 64 00 7d c6 06
6a4c  -> file offset 0x6472   bytes there: 06 33 c0 8e c0 a1 26 64

python3 tools/patch.py TDEGA.EXE TDEGA_fix.EXE 0x63B6:c706:eb10 0x6472:0633c08ec0a126:9cff1e2664ebde
```

### Step 6: Test in DOSBox-X

Test Drive has no "quit to DOS" at all. The program only ends through
the C runtime's error paths. A small TSR on F12 was tried first, but the game
crashes when anything else has hooked INT 9 ahead of it (probably part of its
protection). So the test-only copies were built from the unpacked image with
two changes:
- an exit stub at `0:68AB`, over the Ctrl+J handler (not needed for the test), which restores
  INT 8, INT 0 and the timer chip and calls DOS terminate;
- the race's **P** (pause) key, at `0:5C6C`, sent to that stub.

These copies are for testing only; never use them on the 86Duino.

| Variant | Race runs | DOS clock over a ~78 s run |
|---|---|---|
| Original | yes | 48.0 s (the whole race is missing) |
| v1 (part 1 only) | yes, but the `0:3B1F` hook is lost | did not exit cleanly |
| v2 (part 1 + 2) | yes | 85.4 s |

### Step 7: Test on the 86Duino (v2)

The keyboard no longer dies, but the hardware report was: *"In the original
game, I can keep pressing the upward arrow and then the car is accelerating. In
your patched version, pressing the arrow isn't enough, I need to keep tapping
it which is just clumsy."*

### Step 8: Why holding a key stopped working

The race reads the keyboard in `0:5C24`, once per frame:
- If the BIOS buffer holds a key, it takes the newest one and turns it into a
  direction. The table at data `63B8h` maps scancodes `47h`–`51h` to
  directions 1–8; `A` is shift up and `Z` is shift down.
- If the buffer is empty, it asks the joystick routine `0:A12F` (which returns
  0 when the joystick is off) and turns its bits into a direction through the
  table at `63A8h`.

So a held key only counts on frames when a key **repeat** has just arrived.
Between repeats the game sees "nothing pressed". The game depends completely
on the BIOS's typematic repeat. A USB keyboard doesn't repeat by itself; the
86Duino BIOS has to generate the repeats. Once that BIOS gets its timer ticks
back, it apparently doesn't repeat (or barely does). We couldn't find out why
from outside the BIOS. Test Drive II and Grand Prix Circuit don't care: they
read the keyboard port themselves and keep a table of which keys are down.

### Step 9: Part 3, track held keys (v3)

Make the game see held keys the way it sees a held joystick:

1. **Watch presses and releases.** While racing, the game hooks **INT 15h,
   function 4Fh**: the keyboard intercept that the BIOS's INT 9 calls with
   every scancode. This avoids reading port `60h`, which could disturb the
   86Duino's keyboard emulation. The new handler keeps a byte of held
   directions in joystick format (up=1, down=2, right=4, left=8):
   - It reacts to scancodes `47h`–`51h`: arrows, Home/PgUp/End/PgDn, and the
     keypad. A make code sets the key's bits; a break code clears them again.
   - Keypad keys with NumLock on are ignored, because then they are digits,
     which the game uses for gear shifts. Keys sent with the `E0` prefix (the
     grey arrow keys) always count.
   - It keeps the CPU flags exactly as they arrived (`pushf`/`popf`), because
     for function 4Fh the carry flag decides whether the BIOS keeps the key.
     A first version without this lost keys in DOSBox-X.
2. **Feed the game.** In `0:5C24`, the call to the joystick routine now goes
   through a tiny wrapper that ORs the held directions into the joystick bits.
   A held arrow therefore reads as a held joystick on every frame.
   Tapping, the letter keys and real key repeats work exactly as before.
3. **Install once.** `0:698C` (the race start) now hooks INT 15h through DOS,
   unless the hook is already there, and then continues into `0:699E` as in
   part 1. The hook stays in place for the rest of the session, like the
   game's other vectors. The game has no normal way back to DOS anyway.

Free space was the hard part:
- The packed file can only be patched in place on literal bytes, and the big
  zero areas inside the EXE are fill runs. So the code reuses bytes made dead
  by parts 1 and 2 (`0:698E`, `0:69B6`, which was the unused third timer
  routine, and `0:6A53`).
- The handler itself (71 bytes) goes in the data segment over three fatal
  error messages of the picture loader's memory manager (data `6A78h`–`6AC0h`).
  The first byte of `6A78h` stays 0. The table and variables go over the
  decompressor message `" File packed with too many bits %d"` (data `69E3h`),
  which also keeps a 0 at its start.
- Should one of those errors ever happen, the message prints garbage
  instead. They only appear when the game has already failed: out of memory
  or a corrupt picture file.

All changes, as `patch.py` arguments for `TDEGA.EXE` or `TDEGAX.EXE` (same
offsets; 137 bytes):

```
0x5654:ff44:230e
0x63B2:55ba972ec7063464007dc6063f:b81535cd2181fb796a7407eb1d
0x63DC:558becba010033c0f77e06a33464a33664c6:891ef1698c06f369ba796ab81525cd21ebd6
0x6472:0633c08ec0a1266426a32000a12864:9cff1e2664ebdee8d9360a06ef69c3
0xFB16:2046696c65207061636b6564207769746820:0009010500080004000a0206000000000000
0xFBA1:4f555420:009c80fc
0xFBA6:46204d454d4f52592042554646455253004f5554204f4620425546464552204d454d4f52590000425546464552204e4f5420464f554e442052454c4541534520455252:753b5388c32e861ef06980fbe0740d1e31db8edbf6061704201f752088c383e37f80eb4780fb0a77132e8a9fe4692e081eef69a88074052e301eef695b9d2eff2ef169
```

### Step 10: Test v3 in DOSBox-X

DOSBox-X repeats held keys, so it can't show the problem directly. A test-only
TSR, `HOLDSIM.COM`, imitates a keyboard without repeat: it runs on INT 1Ch, and
at a set time it:
1. sends INT 15h/4Fh make `48h` and puts **one** ↑ into the BIOS buffer;
2. 15 seconds later, sends the break `C8h`.

(INT 1Ch only runs in the race once the BIOS gets ticks, so this compares v2
with v3, not with the original.)

| Variant | Simulated 15 s hold of ↑ | Typed keys, exit | DOS clock over a ~78 s run |
|---|---|---|---|
| v2 | the car barely moves (one frame of throttle) | ok | 85.4 s |
| **v3** | **the car accelerates for the whole hold** (and, unsteered, leaves the road) | ok | **85.4 s** |

### Step 11: Test v3 on the 86Duino

✅ **Works.** The hardware report: *"the patched test drive one works like charms"*.
The keyboard stays alive through the race, and holding an arrow key works again.

**v3 is the fix for Test Drive.**

---

## Case 3: The Duel: Test Drive II (1989)

Accolade / Distinctive Software. `RUNME.BAT` and `DUEL.EXE` start
`td2ega.exe` (or `td2cga.exe`). Both EXEs got the same fix.

| File | Size | MD5 |
|---|---|---|
| `TD2EGA.EXE` (original) | 114 421 | `8dd14da952e51aae42d29907329da07a` |
| `TD2EGA.EXE` (patched) | 114 421 | `2f7f722dd85195f14437d49a1b112376` |
| `TD2CGA.EXE` (original) | 104 149 | `ec0ec8de7d41e650f845ca4e17b5ad5b` |
| `TD2CGA.EXE` (patched) | 104 149 | `59577c6d71f68ee7bf52c4eae51dab6f` |

### Step 1–3: Unpack and scan

The files use normal EXEPACK (the newer 18-byte header), with a multi-segment
Microsoft C program:

```
python3 tools/unexepack.py TD2EGA.EXE TD2EGA_unp.EXE
entry 13a8:03f8  stack 20d2:0fa0  1652 relocations  130240 bytes of code/data
```

The scan looks like Grand Prix Circuit's:
- its own INT 9, INT 16h and INT 8 handlers;
- the timer at 100 Hz;
- one `int 8` (image `0xCEE9`).

There is only one INT 8 hook. The race code plugs into the timer through a
callback list inside the handler, not through a second vector.

### Step 4: Read the timer code

Image addresses are given for `TD2EGA`. The code segment is `06C9h`, so the
handler `06C9:61BF` sits at image `0xCE4F`.

The handler runs every tick and calls the BIOS every 5th tick if
`[5E95h]` is set. The BIOS call (`0xCEC0`) starts with the **same countdown
as Grand Prix Circuit**:
- If `[5E94h]` is set, `[5E96h]` counts down from 100.
- At zero, both `[5E94h]` and `[5E95h]` are cleared. From then on the BIOS
  gets nothing.

| Routine (image) | Sets | Called from |
|---|---|---|
| `0xCCE9` | `[5E94]=0`, `[5E95]=1`: ticks forever | start-up (`0x081A`, `0x42AE`) |
| `0xCCAC` | `[5E96]=100`, **`[5E94]=1`** | race code (`0x887B`, `0xAC69`) |
| `0xCD0A` | `[5E96]=100`, **`[5E94]=1`** | not used |

### Step 5: The patch

Exactly fix A from Grand Prix Circuit: change `mov byte ptr [5E94h],1` to
`…,0` in both routines that start the countdown.

| File | Image addresses | File offsets | Change |
|---|---|---|---|
| `TD2EGA.EXE` | `0xCCC8`, `0xCD28` | `0xCEC8`, `0xCF28` | `01` → `00` |
| `TD2CGA.EXE` | `0xCC4A`, `0xCCAA` | `0xCE4A`, `0xCEAA` | `01` → `00` |

(In `TD2CGA` the variables are at `5D34h`… instead of `5E94h`…)

```
python3 tools/patch.py TD2EGA.EXE TD2EGA_fix.EXE 0xCEC8:01:00 0xCF28:01:00
python3 tools/patch.py TD2CGA.EXE TD2CGA_fix.EXE 0xCE4A:01:00 0xCEAA:01:00
```

### Step 6: Test in DOSBox-X

The game has a real exit, so no test-only copies were needed. Esc in the race
goes back to the menu. Esc in the menu goes to the title, and Esc on the title
asks **"Exit to DOS (Y/N)?"**.

| Variant | Race runs | DOS clock over a ~101 s run |
|---|---|---|
| `TD2EGA` original | yes | 59.0 s (stops ~5 s into the race) |
| **`TD2EGA` patched** | yes | **111.9 s** |
| **`TD2CGA` patched** (`machine=cga`) | yes | **111.9 s** |

### Step 7: Test on the 86Duino

✅ **Works.** The hardware report: *"The Test Drive 2 patch seems flawless."*

---

## Case 4: California Games II (1990)

Epyx. Start it with `CGII.EXE`. It is a small resident "kernel" with the
keyboard, timer, sound and file services (INT 60h–66h). It then loads `BEACH`,
which shows the video menu and the event menu and loads the events (`SNOW`,
`JETSURF`, `GLIDE`, `BOOGIE`, `SKATE`) on top of it.

The symptom on the 86Duino: *"the first keypress in the selection menu works,
after that the keyboard dies"*. The keyboard is dead from the moment the
game proper starts, not after a few seconds.

✅ **Fixed and confirmed on the 86Duino** (2026-10-16).

| File | Size | MD5 |
|---|---|---|
| `CGII.EXE` (original) | 28 831 | `529ab137c86fc934bb23eb6d9dda1273` |
| `CGII.EXE` (patched) | 28 831 | `d92bba2386907f8c5477d81491b60e73` |

The event files are not changed; they reach the timer only through `CGII`.

### Step 1–3: Unpack and scan

```
python3 tools/unexepack.py CGII.EXE CGII_unp.EXE
entry 0000:5ffa  stack 0b45:042c  97 relocations  46128 bytes of code/data
```

`CGII` installs:
- its own INT 9 at `0:5AFF`, which reads port `60h` and acknowledges with
  the old port `61h` pulse;
- its own INT 16h at `0:5AA0`, which serves the game from its own key buffer;
- its own INT 8 at `0:1A0E`, with the timer set to 60 Hz (divisor `4DAEh`).

There is one `int 8` (`0x1219`). It belongs to a routine that pauses the game
timer around disk loads, not to the timer handler.

### Step 4: Read the timer code

The handler at `0x1A0E` calls the sound hook and the game's per-tick routine,
sends the EOI and returns. **It never calls the BIOS.** Instead, the game keeps
its own count of ticks in `[3E04h]`. When it gives the timer back, routine
`0x5FAC` converts that count into BIOS ticks and sets the DOS clock with
`int 1Ah`. So the DOS clock comes out right, but while the game runs, the BIOS
gets **no ticks at all**. This is the purest Tick Starvation so far. The
video menu still works because `CGII` installs its handlers right after it.

### Step 5: The patch

The new handler has the same 69 bytes and the same calls. Only the ending
differs:

```
1A36  81 06 04 3E AE 4D   add word [3E04h],4DAEh   ; accumulate the divisor
1A3C  72 0E               jc  chain                ; carry = 65536 counts = one BIOS tick
1A3E  B0 20 E6 20         mov al,20h / out 20h,al  ; otherwise: EOI as before
1A42  07 1F 5D … 58       pop es … ax
1A4B  CF                  iret
1A4C  9C                  chain: pushf
1A4D  FF 1E A4 3B         call far [3BA4h]         ; the saved BIOS INT 8, which sends the EOI
1A51  EB EF               jmp 1A42
```

Every carry of the 16-bit sum is exactly one 18.2 Hz BIOS tick, so the BIOS
gets its ticks at the right average rate. `[3E04h]` now serves as the
accumulator. Its old job, fixing up the DOS clock afterwards, is no longer
needed, so `0x5FAC` becomes a plain `ret`. Otherwise it would set the clock
from a sum that no longer counts ticks.

The bytes are in the uncompressed part of the packed file
(`tools/exepack_map.py`):

| Image address | File offset | Change |
|---|---|---|
| `0x1A0E` (69 bytes) | `0x1BE8` | new timer handler |
| `0x5FAC` | `0x58C0` | `50` → `C3` |

```
python3 tools/patch.py CGII.EXE CGII_fix.EXE 0x1be8:fa505351525657551e062e8e1e2e5eff1e100c2e8e1e2e5eff06043e741ea1300cffd0833e183e007d04ff0e6238b020e620071f5d5f5e5a595b58cfff0e043ee85b45ebd9:fa505351525657551e062e8e1e2e5eff1e100c2e8e1e2e5ea1300cffd0833e183e007d04ff0e62388106043eae4d720eb020e620071f5d5f5e5a595b58cf9cff1ea43bebef 0x58c0:50:c3
```

[`tools/cgii_build.py`](tools/) prints and disassembles the new handler.

### Step 6: Test in DOSBox-X

Esc during the event menu returns to DOS, so no test-only copy was needed.

| Variant | Game runs (VGA, hang gliding practice) | DOS clock over the session |
|---|---|---|
| original | yes | (set at exit by the game itself) |
| **patched** | yes, in 9 of 9 clean runs | **45.8 s for 51.7 s host time**, including emulator start-up; the game's own clock fix-up is switched off, so the BIOS got its ticks |

### Step 7: Test on the 86Duino

✅ **Works.** The keyboard now keeps working after the video menu. The hardware
report (2026-10-16): *"both worked."*

---

## Case 5: Sensible Soccer (1993)

Sensible Software, PC conversion by Audio Visual Magic, v1.1 (18 June 1993).
Start it with `SENSIBLE.EXE`, a small packed loader ("Copyware") that runs
`SOC.EXE`, the game itself. `SOC.EXE` is compressed with **PKLITE**.

The symptom on the 86Duino: *"everything is great after the startup and I can
start a game in the menu, somewhere after that I lose the keyboard control and
I never get it back."*

✅ **Fixed and confirmed on the 86Duino** (2026-10-17).

| File | Size | MD5 |
|---|---|---|
| `SOC.EXE` (original, PKLITE) | 82 331 | `cc216db29739e314c53447c069304eac` |
| `SOC.EXE` (unpacked + patched) | 266 199 | `ed540edc33634ea03bd034bfea58c0fa` |

`SENSIBLE.EXE` and the data files are not changed. The loader runs the
unpacked, patched `SOC.EXE` without complaint.

### Step 1–3: Unpack and scan

PKLITE compresses the whole program, so the bytes we need to change are not in
the file in readable form. None of the existing tools handles PKLITE, so the
new [`tools/sensible_build.py`](tools/) unpacks by emulation instead:

1. Run the PKLITE stub in an x86 emulator (unicorn) until it jumps back down to
   the game's entry point (`0000:0000`), and dump the memory.
2. Do it a second time with the program loaded 64 KB higher. Every word that
   differs between the two dumps is a segment address, i.e. a relocation
   (1286 of them).
3. Write a plain MZ EXE from the image and the recovered relocations. The stack
   (`3E55:0400`) is the one the stub hands over.

`SOC.EXE` installs (via DOS `int 21h/25h`, set-up routine at `0xDFD2`):
- its own INT 9 at `CS:0197`, which reads port `60h`, acknowledges with the
  old port `61h` pulse and keeps its own table of held keys;
- its own INT 8 at `CS:02F2`, with the timer at 69 Hz (divisor `438Ch`);
- the old INT 8 and INT 9 vectors as **INT 62h** and **INT 65h**, and the
  music and sound-effect drivers as INT 60h and INT 61h.

There is no `int 8` and no `int 16h` in the program. The handler reaches the
BIOS through `int 62h`.

### Step 4: Read the timer code

```
E24B  81 06 10 19 EC 5D   add word [1910h],5DECh  ; accumulator
E251  73 0B               jnc  eoi
E253  83 3E 43 5E FF      cmp word [5E43h],-1     ; in the menus?
E258  75 04               jne  eoi                ; no (match): don't call the BIOS
E25A  CD 62               int 62h                 ; old INT 8 = BIOS, which sends the EOI
E25C  EB 05               jmp  done
E25E  FB B0 60 E6 20      eoi: sti / out 20h,60h  ; EOI ourselves
```

`[5E43h]` is the game's "where am I" flag. The menu code sets it to `-1`, and
the routine that starts a match (`0xD1F3`) sets it to `0`. (The same flag
picks the screen buffer in the drawing code at `0x2E82A`.) So **in the menus
the BIOS gets its ticks, and from kick-off on it gets none.** That matches
the report exactly: the menus work, the match is where the keyboard dies.

Two smaller things turned up on the way:
- The accumulator step `5DECh` doesn't match the divisor `438Ch`. Even in the
  menus the BIOS gets 69 × 5DECh / 65536 ≈ **25.3 ticks a second** instead of
  18.2, so the DOS clock runs 39% fast. The game never reads the BIOS tick
  count itself. It uses its own counters (`[0A74h]`, `[59A6h]`).
- `[67DCh]` holds the copy-protection result. It is `-3` after the right word
  from the manual. The timer handler checks it on every tick of a match and
  jumps to the exit routine if it is anything else. It is a trap for cracks that
  skip the question, so **the fix doesn't touch the protection**.

The user also never got the keyboard back after the match, although the menus
pass ticks on again. So once the 86Duino's keyboard emulation has been starved
for a while, it doesn't seem to recover by itself.

### Step 5: The patch

Two changes of two bytes each in the unpacked `SOC.EXE`. The file has a 1440h
byte header, so file offset = image address + 1440h:

| Image address | File offset | Change | Effect |
|---|---|---|---|
| `0xE24F` | `0xF68F` | `EC 5D` → `8C 43` | accumulator step = divisor `438Ch`: exactly one BIOS tick per 65536 timer counts, 18.2 Hz |
| `0xE258` | `0xF698` | `75 04` → `90 90` | call the BIOS on every carry, in the menus **and** during a match |

The match path is now the same as the menu path, which already worked on the
86Duino: the BIOS sends the EOI on the ticks it gets, and the handler sends it
on the others.

```
python3 tools/sensible_build.py SOC.EXE SOC_fix.EXE     # needs: pip install unicorn
```

It unpacks, applies both changes after checking the old bytes and writes the
new `SOC.EXE`. Copy it over the original (keep a backup) and start the game
with `SENSIBLE.EXE` as usual.

### Step 6: Test in DOSBox-X

The protection asks for a word from the manual, and the game only quits with
Ctrl+F1 in the menus. So the tests used a test-only copy
(`sensible_build.py … --test`) that accepts any word and quits with F1
anywhere. The run: intro, English, the word, Friendly, Italy v Luxembourg
(both played by the computer), then a match. The DOS `time` was taken before and
after.

| Variant | Game runs | DOS clock vs real time |
|---|---|---|
| original, menus only | yes | 84.5 s for ~62 s (BIOS ticks at 25.3/s) |
| **patched**, menus only | yes | **61.4 s for ~62 s** |
| original, with a match | yes | 205.3 s for ~231 s: the clock **stops** at kick-off |
| **patched**, with a match | yes, match plays normally | **230.4 s for ~231 s**: the BIOS gets its ticks all the way through |

### Step 7: Test on the 86Duino

✅ **Works.** With the patched `SOC.EXE`, the keyboard keeps working through
the match and after it. The hardware report (2026-10-17): *"everything worked
as expected."*

---

## Recipe for the next game

1. **Confirm the symptom.** The keyboard dies after a while, not immediately, and
   the game keeps running. Note *when* it dies: right away in the menus, or a few
   seconds into gameplay?
2. **Find the real game EXE.** Look for a loader or menu program (like `GP.EXE`)
   and note any command-line arguments it passes.
3. **Unpack it if needed.**
   - The `RB` signature or "Packed file is corrupt" message means EXEPACK; use
     `tools/unexepack.py`. It handles both the older 16-byte and the newer
     18-byte EXEPACK header.
   - `PKLITE Copr.` in the header means PKLITE. Unpack it by emulation and
     ship the unpacked, patched EXE, as in
     [Sensible Soccer](#case-5-sensible-soccer-1993). The same trick (run the stub
     twice at two load segments, diff the dumps for relocations) works for
     LZEXE and most other packers.
4. **Scan it:** `python3 tools/dis16.py GAME_unp.EXE --scan`. The interesting hits:
   - `mov es:[20h]`, or `mov ah,25h` with `al=08`: the game hooks the **timer**.
   - `out 40h` / `out 43h`: it reprograms the timer rate.
   - `int 8`: it passes ticks on to the BIOS itself. Look for the condition that
     **stops** it doing so.
   - `mov es:[70h]`: it hooks INT 1Ch. Does it call the old handler?
   - `out 64h`: it really does reprogram the keyboard controller. That is a
     different problem from Tick Starvation.
   - `in al,40h`, a wait on `0040:0040`, or a speed calibration: the game
     may freeze for a different reason. See [Clock Mirage](clock-mirage.md).
5. **Read the timer handler.**
   - Look for any path where the game stops calling the old INT 8: a counter, a
     flag, or a mode switch.
   - Or: the game never calls the old INT 8 at all, yet runs the timer faster than
     18.2 Hz.
   - Look for a flag that switches the pass-on off in one game mode only
     (menus vs. play), as in [Sensible Soccer](#case-5-sensible-soccer-1993).
     Check that the accumulator step equals the timer divisor.
   - Hooks set with `int 21h/25h` don't show up in the `--scan` vector
     patterns. Search for `B8 08 25` (`mov ax,2508h`). The old vector may be
     parked on a spare interrupt (`int 62h`) and called from there.
   - Look for a **second** INT 8 hook (`mov ah,25h` with `al=08`, or another
     `mov es:[20h]`) stacked on top of the first, as in
     [Test Drive](#case-2-test-drive-1987).
6. **Patch it so the BIOS keeps getting about 18 ticks a second.**
   - Usually this is a flag or counter, like here.
   - The Distinctive Software games (Grand Prix Circuit, Test Drive, Test
     Drive II) share one timer library. Look for the 100 Hz divisor
     (`2E97h` / `2E9Ch`), and for a set-up routine that turns the BIOS pass-on
     off or starts the countdown of 100.
   - If the handler passes ticks on by swapping the INT 8 vector, and the game
     stacks another hook on top, change the swap to `pushf` + `call far
     [saved vector]`. Otherwise the swap unhooks the other handler.
   - If the game never passes ticks on at all, call the old vector yourself:
     add the timer divisor to a 16-bit sum each tick and call the BIOS on each
     carry. If the game sets the DOS clock itself afterwards, switch that off.
     See [California Games II](#case-4-california-games-ii-1990). Squeeze the
     code into the handler if you can, or find a code cave.
   - Use `tools/exepack_map.py` to find the bytes in the packed file and
     `tools/patch.py` to apply them.
7. **Check how the game reads the keyboard while playing.**
   - If it has its own INT 9 handler, it keeps its own table of held keys
     and nothing more is needed.
   - If it polls the BIOS (`int 16h`) once per frame, a held key only works
     through BIOS key repeat, and the 86Duino's BIOS may not repeat. Add
     held-key tracking through INT 15h/4Fh, as in
     [Test Drive part 3](#step-9-part-3-track-held-keys-v3).
8. **Don't touch the game's own keyboard acknowledge** (the port `61h` pulse, the
   EOI). See [patch B](#what-didnt-work-patch-b).
9. **Test in DOSBox-X.** Check that the game runs and that the DOS clock keeps up
   with real time. Then test on the 86Duino.
   - The clock check needs the game to return to DOS.
   - If it has no exit, build a test-only copy from the unpacked EXE. Send a
     key the game already handles during play to a small stub that restores
     the vectors and the timer chip and calls DOS terminate. See
     [Test Drive, step 6](#step-6-test-in-dosbox-x).
   - A TSR is no substitute: some games crash if INT 9 is hooked ahead of them.

## Tools

All in `tools/`, Python 3. `dis16.py` needs `pip install capstone`.

| Script | What it does |
|---|---|
| `unexepack.py` | Unpacks an EXEPACK-compressed EXE so it can be disassembled. |
| `exepack_map.py` | Translates an address in the unpacked image to a file offset in the packed original. |
| `dis16.py` | 16-bit disassembly of address ranges, plus a `--scan` for keyboard and timer code. |
| `patch.py` | Applies `OFFSET:OLD:NEW` byte patches, checking the old bytes first. |
| `cgii_build.py` | Prints and disassembles the California Games II timer-handler patch. |
| `sensible_build.py` | Unpacks Sensible Soccer's PKLITE `SOC.EXE` by emulation and applies its patch (`pip install unicorn`). |

The same folder also holds the [Clock Mirage](clock-mirage.md#tools) tools
(`RETRACE.COM`, `PITMODE2.COM`).

No game files are included in this repository. You need your own copy of each
game.

## Sources

- [Vortex86EX datasheet, Rev. 1.3 (DM&P, hosted by 86duino.com)](https://www.86duino.com/wp-content/uploads/2013/11/Vortex86EX_A9123_V14_86duino.pdf):
  keyboard controller §10.10/§11.3.14, port 61h §11.3.19, legacy USB SMI status.
- [US 6067589 A: USB legacy support system](https://patents.google.com/patent/US6067589A/en):
  how USB keyboards are made to look like an 8042 to DOS.
- [Ralf Brown's Interrupt List](https://www.ctyme.com/rbrown.htm): INT 8, INT 9,
  INT 16h, ports 40h–43h, 60h–64h.
