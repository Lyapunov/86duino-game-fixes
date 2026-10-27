# Wet Ink: when the 86Duino runs code before the ink is dry

Some old programs write into their own code while they run. They change a
byte or two, jump there, and expect the CPU to execute the new bytes. Every
x86 CPU since the 486 promises that this works, as long as the program jumps
after writing. **The 86Duino's Vortex86EX doesn't always keep that promise.**
If the freshly written byte sits close to where the program jumps, the CPU
sometimes runs the *old* byte instead. It reads the code before the ink is
dry. I call this **Wet Ink**.

Wet Ink is not a problem with the game's logic, the timer, the keyboard or
the DOS extender. It comes from the processor itself. Any program that
patches its own code just before running it can be hit, so this page
documents it in detail.

| Face | What the program does | What the Vortex86EX does |
|---|---|---|
| **The Runaway Brush** | Writes a `ret` into an unrolled pixel loop to say "stop after n pixels", then calls the loop | Sometimes misses the `ret` when it is within about 54 bytes of the loop start, and paints on to the end of the loop: hundreds of pixels, reading far past the end of its table |

The diagnosis, the test program and the patch on this page are by **Claude**
(Anthropic's Claude Opus 5.5, working in Claude Code). I tested everything on
the real 86Duino.

This is a sister page of [Tick Starvation](tick-starvation.md),
[Clock Mirage](clock-mirage.md),
[Borrowed Interrupt Flag](borrowed-interrupt-flag.md),
[Trap Storm](trap-storm.md), [Ghost Frame](ghost-frame.md),
[Broken Record](broken-record.md), [Sealed Gate](sealed-gate.md),
[Side Door](side-door.md), [Sixteen-Bit Exile](sixteen-bit-exile.md) and
[Late Echo](late-echo.md); all eleven are listed in the
[overview of the game fixes](86duino-game-fixes.md). Tick Starvation and Clock
Mirage are about timers and the BIOS. This one is about the CPU.

## Games

| Game | Year | Files patched | Face | Fix | Status on 86Duino |
|---|---|---|---|---|---|
| [The Elder Scrolls II: Daggerfall](#case-1-the-elder-scrolls-ii-daggerfall-1996) | 1996 | `FALL.EXE` (v1.07.213) | Runaway Brush | 22 bytes, 5 sites | ✅ Fixed |
| *next game here* | | | | | |

**Suspects (not tested).** The shading loop lives in Daggerfall's hand-written
assembly renderer, part of Bethesda's XnGine. Other XnGine games could carry
the same code: *The Terminator: Future Shock* (1995), *SkyNET* (1996),
*An Elder Scrolls Legend: Battlespire* (1997) and *The Elder Scrolls
Adventures: Redguard* (1998). More generally, any 1990s software renderer
that plants `ret`s or jump targets in unrolled loops is a candidate. See
[Recipe for the next game](#recipe-for-the-next-game).

---

## The original request

The symptom, in my words at the time: some sprites show artifacts, then the game exits with
"Daggerfall has detected the error 519". It happened several times during normal play.
One save reproduced it reliably. The crash comes "always there when I'm turning
rightward", give or take a frame or two, with "the very same dynamic". The same
save ran fine in DOSBox-X and in QEMU.

Later, with photos of the artifacts:

> […] one is a photo with barrels and if you look at carefully you see
> something strange in the middle of thin air when you look rightward to the
> rightmost barrel. On the other photo — and this is more important, because
> this is very close to the frame that freezes — you see an open area in the
> front and rightward to the road there is something like a railing except
> that is not that, the pixels are too colorful and as far as I interpret the
> wall in the distance is badly display and those strange pixels are
> artefacts.

After the shading-off test build:

> the shaderless FALLNOSH.EXE seems to work very well. […] I see no barrels
> any more and it turned out there are no walls around this city so probably
> the distant walls were also just artefacts too.

After the fix:

> FALLFIX is another banger, no barrels, no walls, all of those were just
> mirages. But I see shades in the distance, so the shader must work very
> well.

---

## Background

### Self-modifying code, and what x86 promises

In the 1990s, fast software renderers often **patched their own code**. Two
habits are common:

- **Patch an immediate.** Store a per-frame constant (a step, a bound, a
  table address) directly into an instruction like `add ecx, 12345678h`. That
  saves a register or a memory read in the inner loop.
- **Plant a `ret`.** Unroll a pixel loop for the widest possible span. To draw
  n pixels, write a `ret` (byte `C3h`) at the start of pixel n's code, call
  the loop's start, then put the original byte back. That gives a loop of any
  length with no counter at all.

A CPU fetches and decodes code ahead of execution, so a byte written as data
may already sit in the CPU in its old form. Intel's rule for this has been
stable since the 486. The *Intel 64 and IA-32 Architectures Software
Developer's Manual*, Vol. 3, "Handling Self- and Cross-Modifying Code", gives
two portable ways:

1. Store the new code, then **jump** to the new code or to an intermediate
   location, then run the new code.
2. Store the new code, then run a **serializing instruction** (such as
   `cpuid`), then run the new code.

Later Intel CPUs (the P6 family onward) go further and detect such stores
by themselves. Emulators (DOSBox, DOSBox-X, QEMU) always run the new bytes.

Daggerfall follows rule 1: it stores the `ret`, then calls the loop. On the
Vortex86EX that isn't always enough.

### The 86Duino's CPU

The 86Duino uses a DM&P **Vortex86EX** system-on-chip: an x86 core with
CPUID vendor "Vortex86 SoC", signature `00000601`. It runs real DOS games, and
for nearly everything it behaves like a fast 486/586. The differences are in
corners few programs visit. Before Wet Ink, a differential test (CPUDIFF,
below) had found two: what `bsf`/`bsr` leave in their destination when the
source is zero, and a few FPU results.

---

## Case 1: The Elder Scrolls II: Daggerfall (1996)

Bethesda, version 1.07.213 (the last official patch), `FALL.EXE`, started by
`DAGGER.BAT` as `FALL z.cfg`. Sound was off (`HMISET.CFG`: no digital and no
MIDI device), so sound-card DMA plays no part.

| File | Size | MD5 |
|---|---|---|
| `FALL.EXE` (original, 1.07.213) | 1 864 183 | `40521280419d602e470e84fcc90f2ec2` |
| `FALL.EXE` (fixed, `FALLFIX.EXE`) | 1 864 183 | `f4c140063498e033714facb6a9d31ce0` |
| `FALL.EXE` (shading off, `FALLNOSH.EXE`) | 1 864 183 | `36133549a2ea06240bc4360174502540` |

All tools mentioned here are in [`tools/`](tools/).

### The machine

Vortex86EX, 128 MB RAM, FreeDOS with HIMEMX. The repro save was slot 3,
"kinn", in the Orsinium Area: a snowy town at night.

### Step 1: What "error 519" means

`FALL.EXE` is a 32-bit Watcom program bound to the **CauseWay 3.32** DOS
extender (an LE executable, header at file offset `0xB680`). It has the
**MemCheck 3.5** debugging library linked in. MemCheck catches CPU
exceptions and writes a dump to `MEMCHECK.LOG`.

| Object | Base (VA) | Size | Contents |
|---|---|---|---|
| 1 | `0x10000` | `0xAB27F` | C code |
| 2 | `0xC0000` | `0xA1568` | hand-written assembly renderer, mixed with its tables |
| 3 | `0x170000` | `0x45520` | data, BSS, stack |

The number in the message is **not an error code**. Daggerfall sprinkles
"checkpoints" through its code: `mov eax, N` / `call 0x6a319`, which only
records N in a variable (`0x18dbfc`). When any CPU exception happens, the
handler at `0x6a606` prints "Daggerfall has detected the error %d" with the
**last checkpoint passed**.

519 = `0x207`, set at `0x12a8a3`, just before the renderer's **per-row span
loop** (`0x12a8af`–`0x12a967`). For each screen row, the loop walks a linked
list of spans and makes two calls per span:

```
12a939: call *0x3c(%eax)      ; the span's drawer (textured wall, floor, sprite...)
12a940: call *0xcea58         ; a post-pass over the same span (the hook)
```

So "error 519" only says: something crashed while the renderer was drawing
spans.

### Step 2: Suspects that weren't it

Before the crash dumps were readable, every general suspect was tested on
the 86Duino:

| Suspect | Test | Result |
|---|---|---|
| The DOS extender (CauseWay) | Ran `FALL.EXE` under DOS/32A instead | Same crash |
| CPU cache, or stale code from the cache | `CACHEOFF.COM`: CR0.CD=1 plus `wbinvd`; the CPU visibly several times slower | Same crash, at about the same point |
| Bad RAM | `RAMTEST.COM`: all XMS, 10 patterns, 30 s hold | No errors |
| Timing, CPU speed | (follows from the cache-off run) | Crash point barely moved at a fraction of the speed |
| Different CPU arithmetic | `CPUDIFF.COM`: 50 instruction forms, hashed results, compared with QEMU and DOSBox | Only `bsf`/`bsr` with a zero source, and a few FPU results, differ. Daggerfall's six `bsf`/`bsr` sites guard the zero case; the FPU differences point to the emulators being the inaccurate ones. |
| Damaged game files | The SD card's `DAGGERF` copy ran the same save fine in DOSBox-X | Not it |

None of these was it. In hindsight, the cache-off run was the most
misleading: it seemed to rule out "stale code". As Step 6 shows, the stale
code doesn't come from the cache at all.

### Step 3: Five crash dumps, and an address trap

I reproduced the crash five times and kept every `MEMCHECK.LOG`. All five
crashes are **page faults** (exception 0Eh, error code 4: a read from a page
that isn't present), with identical ESP (`0x5C8418`). The EIPs differ:

| Log | EIP (linear) | EAX | ECX | EDX |
|---|---|---|---|---|
| LG1 | `0x56E8B8` | `0191740A` | `01918960` | `0000152E` |
| LG2 | `0x56EF78` | `01952406` | `01953370` | `00000EF5` |
| LG3 | `0x56ED02` | `01917809` | `0191844C` | `00000BB3` |
| LG4 | `0x56EA9E` | `0191700B` | `01918013` | `00000FAF` |
| LG5 | `0x56ED4A` | `01917609` | `01918161` | `00000B57` |

To read them, linear addresses must be turned back into program addresses
(VAs). The obvious offset was taken from MemCheck's stack frames, which lie in
object 1: linear − `0x425000`. Applied to these EIPs, it put the CPU in the
middle of a **colour table** at `0x149980`, apparently executing data. That
looked like a wild jump, and sent the first round of investigation hunting for
corrupted function pointers.

**The trap:** CauseWay doesn't load the objects at their VA spacing. It packs
them back to back, each starting on a page boundary:

| Object | Linear base | VA = linear − … |
|---|---|---|
| 1 | `0x435000` | `0x425000` |
| 2 | `0x4E1000` | **`0x421000`** |
| 3 | `0x583000` | `0x413000` (inferred) |

With the right offset for object 2, all five EIPs land on **the same
instruction**. For object 3, ESP then falls 0x108 bytes below the end of the
object, where a stack top belongs.

> **Lesson for LE/CauseWay crash dumps:** take the linear base of each object
> separately. One matching stack frame proves the offset for one object only.

### Step 4: The Runaway Brush

All five crashes are on `mov (%eax),%al` inside one enormous unrolled loop:
`0x14d320`–`0x150032`, 641 copies of an 18-byte pixel step, ending in `ret`.
Pixel k:

```
mov  %ecx,%eax          ; eax = shade pointer
mov  k(%edi),%al        ; low byte = the pixel already on screen
add  %edx,%ecx          ; step the shade pointer
mov  (%eax),%al         ; look up: shade table[row][pixel]   <-- crash
mov  %al,k(%edi)        ; write the shaded pixel back
```

This is Daggerfall's **distance shading**: the pass that darkens and fogs
far-away surfaces. It doesn't draw new pixels. It re-colours the ones the
span's drawer just drew, through a 64 × 256 shade table, moving through the
table's rows as the depth changes along the span. The table is a 16 KB
buffer allocated at start-up (`0x14d200`, 256-aligned).

The setup routine at `0x150040` runs once per span, as the hook
`*0xcea58`. It computes the starting row pointer (ECX) and the per-pixel step
(EDX = −Δ/n, using a reciprocal table at `0x148980[n]`). Then it sets the run
length the 1990s way:

```
1500cd: movzwl 0x14cc1c(,%ebp,2),%ebp   ; ebp = 18*n from a constant table
...
1500e3: movb   $0xc3,0x14d320(%ebp)     ; plant RET at pixel n
1500ea: call   0x14d320                 ; run the loop from pixel 0
1500ef: movb   $0x8b,0x14d320(%ebp)     ; put the original byte back
1500f6: ret
```

A second path at `0x150120`–`0x15012c` does the same for flat spans (step 0).
A per-frame routine at `0x14d23c` also patches about ten immediates in this
setup code, and installs the hook. It installs a plain `ret` (at `0x14d300`)
instead when shading is off.

### Step 5: The numbers say the brush didn't stop

At the crash, EAX is the shade pointer with its low byte replaced by a screen
pixel, ECX is the next one and EDX is the step. The EIP gives the pixel index.
Working backwards gives where each run **started**:

| Log | Crashed at pixel | Step (bytes/pixel) | Start pointer | Offset in table | Pixels that fit in the table |
|---|---|---|---|---|---|
| LG1 | 79 | 5422 | `0x18AEB00` | `0x0000` | ~3 |
| LG2 | 175 | 3829 | `0x18AEB00` | `0x0000` | ~4 |
| LG3 | 140 | 2995 | `0x18B12B5` | `0x27B5` | ~2 |
| LG4 | 106 | 4015 | `0x18AF1EE` | `0x06EE` | ~3 |
| LG5 | 144 | 2903 | `0x18B151A` | `0x2A1A` | ~1 |

- **All five runs started inside the same 16 KB table.** LG1 and LG2 started
  at exactly the same address. The setup was right.
- **The step says each run was meant to be 1–4 pixels long.** That fits a
  short sliver of a distant wall, where the depth changes steeply across a
  few pixels.
- **Every run went on for 79–175 pixels.** By then it was 420–670 KB past the
  table, reading heap memory as shade values, until it hit an unmapped page.
- **n wasn't simply too large.** The same n sets both the `ret` position and
  the step, and a large n would give a small step. The 18·n table at
  `0x14cc1c` is constant data, never written.

So the loop ran straight through the `ret` that had been planted for it.

This also explains the photos. The runaway pass keeps "shading" along the
screen row, and each pixel's colour indexes into whatever heap memory the
pointer has reached. Much of that memory is texture data, so the result
looks like fragments of real textures: colourful runs, bits of barrel, a
"wall" of icicles and windows around a town that has no walls. With the fix,
all of them are gone. (That the mirages are texture bytes is inferred. That
they disappear with the fix was confirmed on the 86Duino.)

It also explains why **turning right** reproduced it reliably. That way the
view opens onto distant terrain and buildings, which means many short,
steeply shaded spans. That is exactly the case that plants the `ret` within
the first few pixels.

### Step 6: Catching the CPU in the act: SMCTEST

`SMCTEST.COM` rebuilds the pattern outside the game, in a real-mode DOS
program:
- a block of 160 entries of 18 bytes, with the same instruction mix (register
  copy, two byte reads, a byte write, an add), plus `inc si` to count entries;
- `mov byte [bx+block], C3h` / `call block` / put the byte back, exactly like
  `0x1500e3`;
- after each call, SI must equal n.

It runs 50 000 calls for each of two orders of n:
- **A:** random n from 0 to 127,
- **B:** alternating long (n = 127) and short (n = 0..7). Every short run
  follows a run that executed straight through the bytes now being patched.

It also tries five ways of planting the `ret`.

The 86Duino, cache on:

```
SMCTEST 1.0 - RET planted in code, then called (Daggerfall shading pass)
CPUID: Vortex86 SoC  signature 00000601
A V0 store,call        bad  1169  n<4  1169  n<16  1169  worst   160
A V1 store,jmp,call    bad     1  n<4     0  n<16     0  worst    40
A V2 store,read,call   bad     0  n<4     0  n<16     0  worst     0
A V3 xchg,call         bad     0  n<4     0  n<16     0  worst     0
A V4 store,cpuid,call  bad     0  n<4     0  n<16     0  worst     0
B V0 store,call        bad  9316  n<4  9316  n<16  9316  worst   160
B V1 store,jmp,call    bad     0  n<4     0  n<16     0  worst     0
B V2 store,read,call   bad     0  n<4     0  n<16     0  worst     0
B V3 xchg,call         bad     0  n<4     0  n<16     0  worst     0
B V4 store,cpuid,call  bad     0  n<4     0  n<16     0  worst     0
```

DOSBox (`cputype=pentium_slow`) gives `bad 0` on every line. As a negative
control, a copy that never plants the `ret` makes DOSBox count every call as
bad, with worst = 160. So the counter works.

What the 86Duino shows:

- **The game's own sequence (V0) fails, and only when the `ret` is close.**
  Every failure had n < 4: the `ret` at most 54 bytes after the call target.
  In order B, n = 4..7 (72–126 bytes) never failed, in about 12 500 tries. About
  three short calls in four fail. That would fit n = 1–3 always failing and
  n = 0 not, but that's inferred, not measured per n.
- **A missed `ret` runs to the end of the block** (worst = 160 = all
  entries), exactly the Runaway Brush.
- **Writing and then reading the byte back (V2), writing it with `xchg`
  (V3), or a `cpuid` (V4) between write and call each give 0 failures.**
- **An extra `jmp` (V1) is not fully reliable.** It fixed the short case but
  had one stray miss at a longer distance, overrunning by 40.

Together with Step 2: with the cache off, the game still crashed. So the
stale byte doesn't come from the L1 cache. It must come from some buffer
closer to the core: a prefetch or fetch buffer, or a store still in flight
when the call's fetch arrives. Which one isn't known. The fix doesn't need to
know.

### Step 7: The fix: read the ink back

The fix applies V2 in `FALL.EXE`: after planting the `ret`, read the byte back
before calling the loop. A load from the same address has to wait for the
store, and in the test it was enough every time.

The catch is space. The store instruction contains the absolute address
`0x14d320`, and **CauseWay rewrites those four bytes at every load**
(relocation). A patch can't move them or put other bytes there. So the store
becomes an `lea` with the address field in the same place. The loader keeps
relocating it, and EAX receives the address of the byte to patch. The actual
store, the read-back and the jump into the loop go into a 10-byte stub in the
padding just before the loop. That padding is `xchg ebx,ebx` filler that
nothing executes.

Before (the same at `0x150120`/`0x150126`):

```
1500e3: c6 85 20 d3 14 00 c3   movb   $0xc3,0x14d320(%ebp)
1500ea: e8 31 d2 ff ff         call   0x14d320
1500ef: c6 85 20 d3 14 00 8b   movb   $0x8b,0x14d320(%ebp)
```

After:

```
1500e3: 8d 85 20 d3 14 00      lea    0x14d320(%ebp),%eax   ; same address field, still relocated
1500e9: e8 f6 d1 ff ff         call   0x14d2e4               ; the stub
1500ee: 90                     nop                           ; the loop's ret returns here
1500ef: c6 85 20 d3 14 00 8b   movb   $0x8b,0x14d320(%ebp)   ; unchanged

14d2e4: c6 00 c3               movb   $0xc3,(%eax)           ; plant the ret
14d2e7: 8a 00                  mov    (%eax),%al             ; read it back
14d2e9: e9 32 00 00 00         jmp    0x14d320               ; run the loop
```

- **EAX is free at both sites.** The loop's first instruction is
  `mov %ecx,%eax`, so nothing reads EAX on the way in.
- **The return path is unchanged.** The loop's `ret` returns to the `nop`
  after `call 0x14d2e4`, and the original "put the byte back" follows as
  before.
- **The game's own "off" `ret` at `0x14d300`**, which sits in the same
  padding, is untouched.

The patch, as file offsets for [`patch.py`](tools/patch.py):

```
python3 patch.py FALL.EXE FALLFIX.EXE ^
  0x1948E4:db87db87db87db87db87:c600c38a00e932000000 ^
  0x1976E3:c685:8d85 ^
  0x1976E9:c3e831d2ffff:e8f6d1ffff90 ^
  0x197720:c685:8d85 ^
  0x197726:c3e8f4d1ffff:e8b9d1ffff90
```

(On Linux, use `\` instead of `^`.) `le_load.py` confirms that no relocation
touches any patched byte. 22 bytes change. Rename the result to `FALL.EXE`,
or start it as `FALLFIX z.cfg`.

### The other option: shading off

Before the fix existed, a one-site patch tested whether the shading pass was
the only crash site. It forces `0x14d23c` onto the game's own "shading off"
path. The `je` at `0x14d240` becomes a `jmp` to `0x14d2cd`, so the hook is
always the plain `ret`, and objects always get the unshaded drawers.

```
python3 patch.py FALL.EXE FALLNOSH.EXE 0x194840:0f8487000000:e98800000090
```

It ran SAVE3 without crashing, which confirmed that the shading pass was the
only crash site. Distance fog is lost, so far-away things look flat and
bright. FALLFIX keeps the shading, so FALLNOSH is only a curiosity now.

### Step 8: Tests

| Build | 86Duino, SAVE3, turning right | Shading | Artifacts |
|---|---|---|---|
| Original | Crash ("error 519"); 5 of 5 logged runs page-faulted in the shading loop | yes | colourful runs, mirage barrels and walls |
| `FALLNOSH.EXE` | ✅ no crash | none | gone |
| `FALLFIX.EXE` | ✅ no crash | ✅ distant shading visible | ✅ gone: "no barrels, no walls, all of those were just mirages" |

In DOSBox-X and QEMU the original never crashed. Those emulators always run
freshly written code, so Wet Ink can't happen there.

### Loose ends

- **One earlier `MEMCHECK.LOG`** (2026-10-21) showed a different crash: an
  invalid-opcode exception on a perfectly valid `movl $0,0x33(%eax)` at
  `0x86d76`, in C code that frees buffers. Which machine and which test it
  came from was never established, and it hasn't been seen since. An invalid
  opcode on valid bytes would also fit "the CPU ran bytes other than the ones
  in memory". But nothing in that C code is self-modifying, so it stays
  unexplained.
- **The bounds aren't fully mapped.**
  - SMCTEST hasn't been run with the cache off.
  - It hasn't been run per n, to see whether n = 0 really never fails.
  - It ran in real mode, while the game runs in 32-bit protected mode with
    paging. The distances could differ there.
- **V1's single miss** (a plain `jmp` between store and call) at a longer
  distance suggests the window isn't strictly "54 bytes". Treat any
  write-then-run sequence as suspect.

---

## Recipe for the next game

1. **The symptom.** A crash or garbage that appears only on the 86Duino,
   never in DOSBox or QEMU, and is reproducible at a fixed spot, but doesn't
   move with CPU speed and survives cache-off. Visual garbage often comes
   first: a drawing loop that ran too far.
2. **Get a dump.** Find the program's own exception handler, MemCheck log or
   extender dump (CauseWay writes `CW.ERR`; DOS/4GW prints registers). Map
   each object's linear base **separately** (see
   [Step 3](#step-3-five-crash-dumps-and-an-address-trap)).
3. **Look for self-modifying code near the crash.** Typical byte patterns in
   32-bit code:
   - `c6 8x .. .. .. .. c3`: `mov byte [reg+abs], 0C3h`, planting a `ret`;
   - `c6 05 .. .. .. .. c3`: the same at a fixed address;
   - `a3 xx xx xx xx` / `89 1d …` writing into the code object, patching
     immediates, then a `call` or `jmp` into the patched code soon after.
   Wet Ink needs the write and the execution to be **close together in both
   time and address**.
4. **Run [`SMCTEST.COM`](tools/smctest.S)** on the machine. Any nonzero V0
   line means the CPU has Wet Ink. Adapt the entry size and distance to the
   game's pattern if needed.
5. **Fix:** after the store, **read the byte back** (`mov al, [same address]`),
   store with **`xchg`**, or execute **`cpuid`** before running the new code.
   Don't rely on a `jmp` alone. In a relocated executable, keep relocated
   address fields where they are. Turn the store into an `lea` with the same
   address field, and move the work into a stub in padding. `le_load.py off`
   tells you whether a byte is relocated.
6. **Test** on the 86Duino at the reproducing spot, and check that the effect
   the self-modifying code serves (here: distance shading) still works.

## Tools

In [`tools/`](tools/):

| File | What it does |
|---|---|
| `smctest.S`, `smctest_build.py`, `SMCTEST.COM` | The Wet Ink test: plants a `ret` in an unrolled block and calls it, 2 orders × 5 planting methods × 50 000 calls. Run as `SMCTEST > SMC.TXT`. Every line should say `bad 0`. |
| `cpudiff.S`, `cpudiff_build.py`, `CPUDIFF.COM` | Differential CPU test: 50 instruction forms on edge and random operands, hashing results, defined flags and undefined flags. Run on two machines and compare. `CPUDIFF_DOSBOX.TXT` is a DOSBox reference. |
| `cacheoff.S`, `cacheoff_build.py`, `CACHEOFF.COM`, `CACHEON.COM` | Turn the CPU caches off (CR0.CD=1 + `wbinvd`) and back on, to test whether a bug depends on caching. |
| `ramtest.S`, `ramtest_build.py`, `RAMTEST.COM` | XMS memory test: all free XMS, 10 patterns, with a hold time. |
| `le_load.py` | Reads LE executables (DOS/4GW or CauseWay): object list, object dumps with relocations applied, VA → file offset, patching that refuses to touch relocated bytes. |
| `patch.py` | Applies `OFFSET:OLD:NEW` byte patches, checking the old bytes first. |

The `.COM` tools are built with GNU `as`/`ld` (16-bit, `.intel_syntax`). No
game files are included in this repository. You need your own copy of
Daggerfall: it has been freeware from Bethesda since 2009.

## Sources

- [Intel 64 and IA-32 Architectures Software Developer's Manuals](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html):
  Vol. 3A, "Handling Self- and Cross-Modifying Code" (the jump and
  serializing-instruction rules), and `cpuid` as a serializing instruction.
- [Ralf Brown's Interrupt List](https://www.ctyme.com/rbrown.htm): DPMI
  services used by the extenders.
- The CauseWay DOS extender (later released as open source): LE loading and
  object placement.
