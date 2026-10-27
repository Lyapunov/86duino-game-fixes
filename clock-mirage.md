# Clock Mirage: when old games see clocks that aren't there

Some old DOS games freeze on the 86Duino even though nothing is wrong with
the keyboard, the video or the timer interrupt. They freeze because they
**believe in a clock that doesn't exist**. A measurement made in 1991 for a
1991 PC gives a phantom answer on the 86Duino, and the game acts on it. I call
this **Clock Mirage**.

Clock Mirage has four faces so far:

| Mirage | What the game believes | What is really there |
|---|---|---|
| **The 140 Hz Phantom** | "The screen runs at 140 Hz" (it measures a frame and halves the result) | A normal 70 Hz VGA. The BIOS left the timer chip in a different mode, so the halving was wrong. |
| **The Phantom Floppy** | "The BIOS will count down the floppy-motor timer on the next tick" | A BIOS for a machine without a floppy drive, which never touches that byte. |
| **The Vanishing Difference** | "A longer delay loop will take measurably longer" | A CPU so fast that the delay loop costs nothing next to one slow port read. The two timings come out equal, and the game divides by their difference. |
| **The Endless Staircase** | "A few steps of delay will slow my loop down to the right speed" (it adds one step per video frame until it does) | A CPU so fast that it needs thousands of steps. At one step per frame, the climb takes a minute or more of black screen. |

The diagnosis and the patches on this page are by **Claude** (Anthropic's Claude
Opus 5.5, working in Claude Code). I tested the patched games on the real
86Duino.

This is a sister page of [Tick Starvation](tick-starvation.md),
[Wet Ink](wet-ink.md), [Borrowed Interrupt Flag](borrowed-interrupt-flag.md),
[Trap Storm](trap-storm.md), [Ghost Frame](ghost-frame.md),
[Broken Record](broken-record.md), [Sealed Gate](sealed-gate.md),
[Side Door](side-door.md), [Sixteen-Bit Exile](sixteen-bit-exile.md) and
[Late Echo](late-echo.md); all eleven are listed in the
[overview of the game fixes](86duino-game-fixes.md).
Tick Starvation covers games that stop feeding the BIOS its timer ticks and lose the
USB keyboard. It also has the shared unpacking and patching tools and the
background on how the 86Duino emulates a PC keyboard.

## Games

| Game | Year | Files patched | Mirages | Fix | Status on 86Duino |
|---|---|---|---|---|---|
| [Civilization](#case-1-civilization-1991) | 1991 | `CIV.EXE`, `MGRAPHIC.EXE` | 140 Hz Phantom; Phantom Floppy and/or Vanishing Difference | 24 + 46 bytes | ✅ Fixed |
| [Railroad Tycoon](#case-2-railroad-tycoon-1990) | 1990 | `MGRAPHIC.EXE` (and `EGRAPHIC`, `CGRAPHIC`, `TGRAPHIC`) | Endless Staircase | 59 bytes per driver | ✅ Fixed |
| *next game here* | | | | | |

**Suspects (not tested).** Civilization's timer and graphics drivers are
MicroProse's in-house code of 1990–92. Other MicroProse games of that time
may well carry the same mirages. *Railroad Tycoon* (1990) did; see
[Case 2](#case-2-railroad-tycoon-1990). Still unchecked: *Covert Action*
(1990), *Darklands* (1992) and *F-15 Strike Eagle III* (1992).

---

## The original request

> Okay, let's move on, look at the directory Civ with CIV.EXE. When I start it
> up on the X86Duino in VGA / No Sound / Mouse and Keyboard mode, then it freezes
> in the intro, after printing out the text of "A MICROPROSE PRESENTATION". The
> background is not completely black, so some animation may started, but it
> freezes almost immediately and it is not reacting for keys. Can you look at
> CIV.EXE and figure out what is going south?

After the first patch: *"the intro keeps rolling. However, when I hit a key and
the effect of noise-to-text transition should happen with the title screen,
then the program freezes one more time."*

After the second patch: *"it works flawlessly."*

---

## Background

### The timer chip and its modes

The PC's timer chip (Intel 8253/8254, ports `40h`–`43h`) has three channels.
Channel 0 drives IRQ 0, the BIOS clock, about 18.2 times a second. A program
can **latch** channel 0 and read its current count: it counts down from 65 536
to 0, over and over. How it counts depends on the **mode** the BIOS chose:

- **Mode 3 (square wave)**, used by the IBM PC BIOS and copied by nearly every
  1980s–90s clone BIOS. The counter steps down **by 2** on each clock pulse,
  and runs through its range twice per tick.
- **Mode 2 (rate generator)**, used by some later BIOSes, **including the
  86Duino's**. The counter steps down **by 1** on each clock pulse.

The tick rate is the same in both modes, so nothing in DOS notices. Only a
program that reads the counter and assumes mode 3 sees half the difference it
expects.

### The retrace-locked timer

To keep animation smooth, MicroProse locked its game timer to the video frame:

1. At start-up, time a few VGA frames by reading the timer chip at each start
   of vertical retrace (port `3DAh`, bit 3).
2. If the frame length looks plausible, reprogram the timer to fire once per
   frame. Then re-sync it with the retrace every 20 ticks, inside the timer
   interrupt.
3. Keep the BIOS supplied with its 18.2 Hz ticks by adding up the counts and
   calling the old INT 8 every 65 536 counts. (So this is **not**
   [Tick Starvation](tick-starvation.md).)

### The BIOS data area

Old programs often read BIOS variables at segment `0040h` directly:

- `0040:006C`: the tick counter. Every BIOS increments it 18.2 times a second.
- `0040:0040`: the floppy-motor countdown. On an IBM PC the BIOS timer
  interrupt counts it down and switches the drive motor off at zero. A BIOS
  without a floppy controller has no reason to touch it.

---

## Case 1: Civilization (1991)

MicroProse, version 475.01, played in VGA / No Sound / Mouse and Keyboard mode.

| File | Size | MD5 |
|---|---|---|
| `CIV.EXE` (original) | 304 512 | `8c0960a9470c8183fdd88c5810f1f243` |
| `CIV.EXE` (patched) | 304 512 | `a8e7083be89d924faf749e4290d71646` |
| `MGRAPHIC.EXE` (original, VGA driver) | 7 142 | `f28636e2fd8698658436def3a9d5f67e` |
| `MGRAPHIC.EXE` (patched) | 7 142 | `634d6da6304ecae9e36a8b5a9061e4e4` |

All tools mentioned here are in [`tools/`](tools/).

### Step 1: Unpack and scan

`CIV.EXE` is EXEPACKed Microsoft C. The VGA driver `MGRAPHIC.EXE` is a
separate, unpacked file that the game loads.

```
python3 tools/unexepack.py CIV.EXE CIV_unp.EXE
entry 2058:2e83  stack 3999:0800  2517 relocations  199776 bytes of code/data

python3 tools/dis16.py CIV_unp.EXE --scan
out 43h,al  (PIT control)              3  0x50 0x24c 0x318
out 40h,al  (PIT ch0 rate)             5  ...
int 8       (call BIOS timer)          0
mov ah,25h  (DOS set vector)           7  0x36 ...
```

Civ never touches the keyboard controller and doesn't hook INT 9. The timer
code is all at the start of segment 0.

### Step 2: Read the timer code

- **Calibration (`0:0268`).** Routine `0:02FD` waits for the start of
  vertical retrace, then latches and reads channel 0. Repeated 17 times, this
  gives 16 frame lengths. The sum is averaged, then **halved** (`shr ax,1` at
  `0:02AC`) to turn mode-3 steps into clock pulses.
- **Plausibility check.** If the frame works out to 4–6 units of 3977 counts
  (a 50–75 Hz screen), the timer is locked to the frame. Otherwise a fallback
  path with a fixed value is taken.
- **Interrupt handler (`0:0199`).** It re-syncs every 20 ticks and keeps the
  BIOS fed correctly.
- Several palette routines poll `3DAh` in loops with interrupts off and no
  timeout. They were the first suspects. But forcing the retrace bit to 0 or
  to 1 in DOSBox-X gave different symptoms, so they are innocent.

### Step 3: Measure the hardware

[`tools/RETRACE.COM`](tools/) is a 1.6 KB DOS diagnostic written for this
case. It switches to VGA mode 13h for about 2 seconds, then prints:
- Civ's calibration, repeated exactly;
- retraces, `3DAh` reads and bit changes over one second, and the BIOS ticks;
- DAC (palette) readback, and Civ's "colours per frame" palette measurement;
- whether the BIOS counts down `0040:0040`, and Civ's dissolve calibration
  (see step 7).

Run it as `RETRACE > RT.TXT`. On the 86Duino, compared with DOSBox-X:

| | 86Duino | DOSBox-X |
|---|---|---|
| Timer count difference per frame | **17 028** | 34 050 |
| Civ's computed refresh rate | **140 Hz** | 70 Hz |
| Retraces counted in one second | 69 | 70 |
| BIOS ticks in one second | 18 | 18 |
| DAC readback of (21,42,63) | 21,42,63 | 21,42,63 |

The video is fine: 69 retraces a second. The timer difference is exactly half
of normal, because **the 86Duino BIOS leaves channel 0 in mode 2**. Civ halves
it anyway and sees **the 140 Hz Phantom**. Its plausibility check fails, it
takes the fallback path, and the fallback path freezes in the intro.

### Step 4: Reproduce it in DOSBox-X

[`tools/PITMODE2.COM`](tools/) (13 bytes) puts channel 0 into mode 2, like the
86Duino BIOS.

| Run in DOSBox-X | Result |
|---|---|
| `RETRACE` | 34 050 per frame |
| `PITMODE2`, then `RETRACE` | 17 025 per frame (the same as the 86Duino) |
| `CIV` | intro runs |
| `PITMODE2`, then `CIV` | **freezes in the intro** |
| `PITMODE2`, then `CIV` with only the `shr ax,1` removed | intro runs |

That pins it on the calibration. We didn't trace exactly where the fallback
path hangs; the fix keeps Civ off it.

### Step 5: Fix 1, `CIV.EXE`: show Civ the clock it expects

Put channel 0 into mode 3 right before calibrating. That takes 10 bytes:
`mov al,36h / out 43h,al / xor ax,ax / out 40h,al / out 40h,al`. They fit
into the install routine at `0:000B`, whose four
`mov word ptr [x],imm` instructions (24 bytes) can be written in 13:

```
0:000B  b0 36        mov al,36h
        e6 43        out 43h,al        ; channel 0, mode 3, divisor 65536
        31 c0        xor ax,ax
        e6 40        out 40h,al
        e6 40        out 40h,al
        a3 42 00     mov [42h],ax      ; was mov word ptr [42h],0
        a3 44 00     mov [44h],ax      ; was mov word ptr [44h],0
        40           inc ax
        a3 4c 00     mov [4Ch],ax      ; was mov word ptr [4Ch],1
        a3 54 00     mov [54h],ax      ; was mov word ptr [54h],1
        90           nop
```

These bytes lie in the uncompressed start of the packed file, at file
offset `0x20B`:

```
python3 tools/patch.py CIV.EXE CIV_fix.EXE 0x20B:c7064c000100c70654000100c70642000000c70644000000:b036e64331c0e640e640a34200a3440040a34c00a3540090
```

Civ reprograms the timer in mode 3 later on, and restores mode 3 on exit. So
it never relied on the BIOS's mode apart from this one measurement.

On the 86Duino: the intro now runs. But pressing a key, which starts the
noise-to-text dissolve into the title screen, froze it again.

### Step 6: The title dissolve

In DOSBox-X the dissolve works in both timer modes, so this freeze is caused
by the real hardware. The dissolve is drawn by the VGA driver
`MGRAPHIC.EXE`, which is not packed; its file offsets are the image address
plus `0x200`. Routine `MGRAPHIC:06B7` has two weak spots:

- **The Phantom Floppy (`06BD`).**
  - To wait for the next BIOS tick, it writes 1 into the floppy-motor
    countdown at `0040:0040`.
  - It then spins, with no timeout, until the BIOS timer interrupt counts
    that byte down.
  - If the BIOS never does, the game waits forever.
- **The Vanishing Difference (`0776`).** The first time, it runs the dissolve
  loop (`07A4`) for one video frame twice.
  - It runs once with a delay of 1 and once with a delay of 17 per pixel,
    counting pixels each time.
  - It then computes `count17 × 256 ÷ (count1 − count17)`.
  - On a fast CPU each pass is dominated by the slow `in al,3DAh` read, so the
    two counts are nearly equal. The `div` overflows, and the CPU raises a
    divide error.

### Step 7: Fix 2, `MGRAPHIC.EXE`: replace both mirages with real clocks

| File offset | Fix | Before → after |
|---|---|---|
| `0x8BD` (17 bytes) | Wait for the tick counter `0040:006C` to change, which every BIOS keeps up | `33C0 8EC0 B001 26A24004 2638064004 74F9` → `33C0 8EC0 26A06C04 263A066C04 74F9 9090` |
| `0x987` (29 bytes) | Same calculation, but the divisor is raised when needed so the `div` can't overflow (the rounding step was dropped to make room) | `32C0 8AE1 8AD5 32F6 2E8B1EB306 2BD9 F7F3 D1EB 3BDA 150000 2EA3B506 C3` → `2E8B1EB306 2BD9 32C0 8AE1 8AD5 32F6 3BD3 7203 8BDA 43 F7F3 2EA3B506 C3` |

```
python3 tools/patch.py MGRAPHIC.EXE MGRAPHIC_fix.EXE 0x8BD:33c08ec0b00126a24004263806400474f9:33c08ec026a06c04263a066c0474f99090 0x987:32c08ae18ad532f62e8b1eb3062bd9f7f3d1eb3bda1500002ea3b506c3:2e8b1eb3062bd932c08ae18ad532f63bd372038bda43f7f32ea3b506c3
```

Both fixes went to the hardware together, so we don't know yet whether one
mirage or both struck. The last three lines of `RETRACE.COM` would tell:
- **"BIOS counts down 0040:0040" shows 0:** the Phantom Floppy.
- **The two "Dissolve test" counts are nearly equal:** the Vanishing
  Difference.

DOSBox-X gives 1, 9 336 and 5 486.

### Step 8: Tests

| Where | Timer mode before start | Original | Fix 1 | Fix 1 + 2 |
|---|---|---|---|---|
| DOSBox-X | 3 (normal) | runs | runs | runs |
| DOSBox-X | 2 (`PITMODE2`) | freezes in the intro | runs | runs |
| 86Duino | 2 (its BIOS) | freezes in the intro | freezes at the title dissolve | ✅ **works flawlessly** |

---

## Case 2: Railroad Tycoon (1990)

MicroProse, version 455.00. The intro freezes on the 86Duino.

✅ **Fixed and confirmed on the 86Duino** (2026-10-16) with the patched
`MGRAPHIC.EXE`.

| File | Size | MD5 |
|---|---|---|
| `MGRAPHIC.EXE` (original, VGA/MCGA driver) | 6 756 | `8f086435de47a8cfb581bc889e021793` |
| `MGRAPHIC.EXE` (patched) | 6 756 | `ecb69135b2a2dcd59c4261751b1270e0` |
| `EGRAPHIC.EXE` (original, EGA driver) | 10 390 | `5db84bce752eacb8de9a925ad0c79624` |
| `EGRAPHIC.EXE` (patched) | 10 390 | `ecc5a8b9d1fc150b51eb707b804e54d0` |
| `CGRAPHIC.EXE` (original, CGA driver) | 9 428 | `a5a8dd8c0930b6a66233ac6c2d31dd28` |
| `CGRAPHIC.EXE` (patched) | 9 428 | `a6511627d426bfeb87bf43cdf569ad53` |
| `TGRAPHIC.EXE` (original, Tandy driver) | 8 852 | `b396cd389fe57546bddc930b0d6ec1c4` |
| `TGRAPHIC.EXE` (patched) | 8 852 | `9447d38756e10b46bc7fd071b43313f5` |

`GAME.EXE` is not changed. Only the driver for your graphics mode matters;
on the 86Duino that is `MGRAPHIC.EXE` (VGA) or `EGRAPHIC.EXE` (EGA).

### Step 1: Scan

```
python3 tools/unexepack.py GAME.EXE GAME_unp.EXE
python3 tools/dis16.py GAME_unp.EXE --scan
out 43h,al  (PIT control)              0
out 40h,al  (PIT ch0 rate)             0
```

Unlike Civ, `GAME.EXE` never touches the timer chip. The timer code lives in
the sound drivers (`?SOUND.RR`), and the screen effects live in the graphics
drivers (`?GRAPHIC.EXE`, not packed; file offset = image address + `0x200`).

### Step 2: Reproduce it in DOSBox-X

The game runs normally in DOSBox-X at 386 speed, in both timer modes
(`PITMODE2` makes no difference with "No sounds"). The fault only shows
when the emulated CPU is fast (`core=dynamic`, `cycles=fixed 300000`):

| Run in DOSBox-X, VGA, No sounds | Result |
|---|---|
| 386 speed | MicroProse logo dissolves in after about 3 s |
| fast CPU | **black screen for about 80 s**, then the intro carries on |
| fast CPU, EGA or CGA | black screen (the same fault, in the EGA and CGA drivers) |

So this is a CPU-speed fault, not a timer-mode fault.

### Step 3: The Endless Staircase

The first dissolve (the noise-to-picture effect) calibrates its speed.
In `MGRAPHIC.EXE` this is at `05FB`:

```
05FB  inc bx                 ; delay := delay + 1
      wait for the start, then the end of vertical retrace
loop: next pseudo-random pixel, copy it to an invisible spot
      delay loop of bx steps (dec ax / jnz)
      inc cx                 ; pixels drawn in this frame
      in al,3DAh / test al,8 / jz loop   ; until the next retrace
      cmp cx,215h / ja 05FB  ; more than 533 pixels in one frame? climb a step
      mov cs:[05D6],bx       ; remember the delay
```

It wants the dissolve to draw no more than 533 pixels per frame, so that the
whole picture takes about two seconds. To get there it raises the delay **by
one step per video frame**. On a 1990 PC a handful of steps did it. On the
86Duino, one delay step costs a few nanoseconds; the 86Duino's
`RETRACE.COM` run shows one `3DAh` read takes about 1.4 µs. Each pixel needs
about 27 µs, so the delay must reach several thousand steps. At 70 steps a
second, the climb takes a minute or more, with a black screen and no reaction
to keys. That is the freeze.

The EGA (`EGRAPHIC:0CDC`, 355 pixels per frame), CGA (`CGRAPHIC:098E`) and
Tandy (`TGRAPHIC:0B03`) drivers have the same staircase.

### Step 4: Fix: take bigger steps

Instead of `delay + 1`, each frame now sets `delay + delay/8 + 1`. That climbs
from 1 to 4 000 in about 60 frames (under a second). It can overshoot the
ideal delay by at most 1/8, so the dissolve may take up to an eighth longer than
intended.

The bigger step needs 8 more bytes. Each calibration loop has bytes to spare:
- a `cmp si,0 / jb` pair that can never jump (unsigned < 0);
- a `mov si,1` (or `mov bp,1`) that only seeds the throwaway pixel
  sequence used during calibration.

```
05FB  89 D8      mov ax,bx
      B1 03      mov cl,3
      D3 E8      shr ax,cl
      40         inc ax
      01 C3      add bx,ax        ; delay += delay/8 + 1
      ...        the rest of the loop as before, minus the two dead parts
```

The patch fills exactly the original 59 bytes of `MGRAPHIC.EXE`. In the other drivers, the
loop's inner jump moves by a few bytes, and its jump-back is adjusted to match.
[`tools/rtycoon_build.py`](tools/) assembles all four and prints these lines:

```
python3 tools/patch.py MGRAPHIC.EXE MGRAPHIC_fix.EXE 0x7fb:43bada03eca80874f8eca80875fbbe010033c9d1ee730481f600b483fe0072f34ebfffffa48bc34875fd41eca80874e381f9150277ca2e891ed605:89d8b103d3e84001c3bada03eca80874fbeca80875fb31c9d1ee730481f600b44ebfffffa489d84875fd41eca80874e881f9150277ca2e891ed605

python3 tools/patch.py EGRAPHIC.EXE EGRAPHIC_fix.EXE 0xedc:2eff069e0cbada03eca80874f8eca80875fbbd010033c9bace03b805022e8826d625efd1ed730481f500b483fd0072f3beffff4e8bfe:2ea19e0cb103d3e8402e01069e0cbada03eca80874fbeca80875fb31c9bace03b805022e8826d625efd1ed730481f500b4befeff89f7 0xf8d:e96fff:e975ff

python3 tools/patch.py CGRAPHIC.EXE CGRAPHIC_fix.EXE 0xb8e:43bada03eca80874f8eca80875fbbd010033c9d1ed730481f500b483fd0072f3:89d8b103d3e84001c3bada03eca80874fbeca80875fb31c9d1ed730481f500b4 0xbe3:74bc:74c1

python3 tools/patch.py TGRAPHIC.EXE TGRAPHIC_fix.EXE 0xd03:45bada03eca80874f8eca80875fbbe0100badf0333c92e833e7c1e0075aed1ee730481f600b483fe0072f3:89e8b103d3e84001c5bada03eca80874fbeca80875fbbadf0331c92e833e7c1e0075a9d1ee730481f600b4 0xd59:74c6:74cb 0xd77:74a8:74ad
```

### Step 5: Tests

| Where | Mode | Timer mode | Original | Patched |
|---|---|---|---|---|
| DOSBox-X, 386 speed | VGA | 3 and 2 | runs | runs |
| DOSBox-X, fast CPU | VGA | 3 and 2 | black for ~80 s | ✅ logo dissolves at once, intro runs |
| DOSBox-X, fast CPU | EGA | 2 | black screen | ✅ runs |
| DOSBox-X, fast CPU | CGA | 2 | black screen | ✅ runs |
| DOSBox-X, fast CPU | Tandy | 3 | runs (its intro has no dissolve) | ✅ runs to the main menu |
| 86Duino | VGA | 2 | freezes in the intro | ✅ **works** |

### The sound drivers (not patched)

Two sound drivers carry Civ's older mirages. With "Shhh! No sounds" neither is
loaded:
- **`ASOUND.RR` (AdLib).**
  - At `00B6` it has a Phantom Floppy wait: it sets `0040:0040` to 1 and
    waits for the motor bits in `0040:003F` to clear. This only hangs if
    those bits are already set.
  - At `00CF` it times 256 `loop`s on the timer chip, assuming mode 3.
  - Its result is cut to 8 bits (`mov ah,0`). So on a fast CPU the AdLib
    register delays come out wrong in either timer mode.
- **`RSOUND.RR` (Roland MT-32).** It has the same 256-loop timing at `010D`.
  The result sets the pause after a SysEx message.

If you play with AdLib or Roland sound on the 86Duino and something goes
wrong, these are the places to look.

---

## Recipe for the next game

1. **Run `RETRACE.COM` once on the machine.** It shows the timer mode (look
   at the "PIT count difference": about 17 000 means mode 2, about 34 000
   means mode 3). It also shows the floppy-motor countdown and the BIOS tick
   rate. These are properties of the machine, not of the game.
2. **Unpack and scan the game.** Use the shared tools of the
   [Tick Starvation page](tick-starvation.md#tools); then
   search the binary for the patterns below. Remember that drivers like
   `MGRAPHIC.EXE` are separate files.
3. **The 140 Hz Phantom.**
   - Look for `mov al,0` / `out 43h,al` / `in al,40h` / `in al,40h` (a
     channel-0 latch and read), usually next to a `3DAh` retrace wait.
   - If the code assumes mode 3 (it halves, or `shr`s, the difference),
     program mode 3 (`out 43h,36h`, divisor 0) before the measurement.
   - Check: in DOSBox-X, run `PITMODE2` first. The game should freeze before
     the fix and run after it.
4. **The Phantom Floppy.** Look for writes to `0040:0040` (`26 A2 40 04`,
   `26 C6 06 40 04`, …) followed by a loop comparing the same byte. Replace
   the wait with one on the tick counter `0040:006C`.
5. **The Vanishing Difference.** Look for speed calibrations that time a loop
   twice with different delays and `div` by the difference. Clamp the divisor
   so the quotient fits (divisor > high word of the dividend), or give it a
   floor.
6. **The Endless Staircase.** Look for a `3DAh` retrace loop that counts
   pixels (or iterations) per frame, compares the count with a constant, and
   jumps back to an `inc` of the delay. Make the step proportional (for example
   `delay += delay/8 + 1`). Check: in DOSBox-X with `core=dynamic` and
   `cycles=fixed 300000`, the original shows a long black screen.
7. **Test in DOSBox-X in both timer modes, at slow and fast CPU speed.** Then
   test on the 86Duino.

## Tools

In [`tools/`](tools/), next to the unpacking and patching tools described on
the [Tick Starvation page](tick-starvation.md#tools).

| File | What it does |
|---|---|
| `RETRACE.COM` | DOS diagnostic: VGA retrace and refresh rate, timer-chip mode (via Civ's calibration), BIOS ticks, DAC readback, Civ's palette and dissolve timing, the floppy-motor countdown. Run as `RETRACE > RT.TXT`. |
| `PITMODE2.COM` | Puts timer channel 0 into mode 2, to imitate the 86Duino BIOS in an emulator. |
| `retrace_build.py` | Builds `RETRACE.COM` (Python 3, `pip install keystone-engine`). |
| `rtycoon_build.py` | Assembles the Railroad Tycoon dissolve patches and prints the `patch.py` arguments (`pip install keystone-engine`). |

No game files are included in this repository. You need your own copy of each
game.

## Sources

- [Intel 8254 Programmable Interval Timer datasheet](https://www.scs.stanford.edu/10wi-cs140/pintos/specs/8254.pdf):
  counter modes 2 and 3, the counter-latch command.
- [Ralf Brown's Interrupt List](https://www.ctyme.com/rbrown.htm): ports
  `40h`–`43h` and `3DAh`, BIOS data area `0040:0040` and `0040:006C`.
- [FreeVGA: Input Status #1 register (`3DAh`)](http://www.osdever.net/FreeVGA/vga/extreg.htm):
  vertical retrace (bit 3) and display enable (bit 0).
