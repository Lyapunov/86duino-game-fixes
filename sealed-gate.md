# Sealed Gate: when a protected-mode game knocks on its real-mode driver's door

Many DOS/4GW games of 1993–1995 carry a small **real-mode sound driver**. The
game loads it into conventional memory, points an interrupt vector at it, and
from then on calls it with a software interrupt, straight from protected mode.
On its own, DOS/4GW quietly passes such an interrupt down to real mode, and
the driver answers.

SBEMU needs a DPMI host, HDPMI32i, and under HDPMI32i that interrupt is
**a gate that stays shut**. The call faults, the fault handling goes round in
a loop that eats a little of the stack every round, and when the stack is
gone DOS/4GW gives up with **exit code 7**, right after its banner. The game
never gets as far as its first picture. I call this **Sealed Gate**.

| Face | What you see | What is really there |
|---|---|---|
| **The Endless Knock** | With HDPMI32i loaded (boot entry *S*), the game shows the DOS/4GW banner and drops straight back to DOS | A protected-mode `INT 80h` meant for the game's real-mode sound driver raises a general protection fault; the fault handling faults again and again, 32 bytes of stack each time, until DOS/4GW exits with code 7 |
| **The Short Pour** | Only after swapping in the newer DOS/4GW 2.00 extender (part of the fix): *"mk: file SBL.BIN is corrupt!"*, or worse, a sound driver loaded only by half that crashes the machine once the music starts | DOS/4GW Professional 2.00 delivers at most 8 KB per DOS read into conventional memory, but moves the file position on by the full amount: the rest of the file is silently lost |

The diagnosis and the patch on this page are by **Claude** (Anthropic's Claude
Opus 5.5, working in Claude Code). I tested them on the real 86Duino.

This is a sister page of [Tick Starvation](tick-starvation.md),
[Clock Mirage](clock-mirage.md), [Wet Ink](wet-ink.md),
[Borrowed Interrupt Flag](borrowed-interrupt-flag.md),
[Trap Storm](trap-storm.md), [Ghost Frame](ghost-frame.md),
[Broken Record](broken-record.md),
[Side Door](side-door.md),
[Sixteen-Bit Exile](sixteen-bit-exile.md) and [Late Echo](late-echo.md); all eleven are listed in the
[overview of the game fixes](86duino-game-fixes.md). Like Borrowed Interrupt Flag, this one is a
software-stack issue: it shows up in QEMU just the same, as soon as
HDPMI32i is loaded.

## Games

| Game | Year | Files patched | Faces | Fix | Status on 86Duino |
|---|---|---|---|---|---|
| [Mortal Kombat II](#case-1-mortal-kombat-ii-1994) | 1994 | `MK2.EXE` (7 Feb 1995), plus `SBL.BIN` for [Broken Record](broken-record.md#case-3-mortal-kombat-ii-1994) | The Endless Knock (The Short Pour inside the fix) | Extender swap, 18 sites, 3 helpers | ✅ "The sound and the music are perfect and the game is stable enough to play" |
| *next game here* | | | | | |

**Suspects (not tested).** Any DOS/4GW game that calls a real-mode driver
with a software interrupt from protected mode (Watcom's `int386()`, or a
plain `int` instruction), run under HDPMI32i. The giveaway: exit code 7
right after the DOS/4GW banner, only with HDPMI32i loaded.
[Command & Conquer](command-and-conquer-on-86duino.md) exits with code 7
under HDPMI32i + SBEMU too, for a reason still unknown; it would be the first
place to look.

---

## The original request

> [...] it would be good to make it not just working but also to work with
> SBEMU.

And on the way:

> One more thing: could you patch the program to use IRQ5? I read somewhere
> that it's recommended not to use IRQ7 on 86Duino, it may be or may not be
> true.

After the first complete fix:

> verified that MK2.EXE exits immediately and in contrast MK2FIX.EXE is much
> more playable - I can select a character, I can win a match, I can advance
> in the tournament to the next match - these are great things. Music also
> plays well, but the sound effects are like e-e-e-e-e-e just in the case of
> the GTA.

That last part is [Broken Record, Case 3](broken-record.md#case-3-mortal-kombat-ii-1994).
After its fix: *"this version makes the cut to me, the sound and the music
are perfect and the game is stable enough to play."*

---

## Background

### Calling a real-mode driver from a DOS/4GW game

A DOS/4GW game runs in 32-bit protected mode. A sound driver written for real
mode can't simply be called from there. The usual trick of the time:

1. Load the driver file into conventional memory (below 640 KB).
2. Point a real-mode interrupt vector at its entry point (DPMI function
   `0201h`, *set real-mode interrupt vector*).
3. Call it with that interrupt from protected mode, for example with the
   Watcom C library function `int386(0x80, &in, &out)`, which ends in a plain
   `int 80h` instruction.

Without a DPMI host, DOS/4GW is in charge of the machine: it catches the
protected-mode `int 80h`, finds no protected-mode handler, switches to real
mode, runs the real-mode vector 80h, and comes back with the registers.

### Under a DPMI host

With HDPMI32i loaded, DOS/4GW doesn't run the machine any more; it becomes a
client of HDPMI32i, and every interrupt goes through HDPMI32i's interrupt
table. The DPMI specification has one guaranteed way for a client to call a
real-mode interrupt: function `0300h`, *simulate real-mode interrupt*, with
the registers in a structure. A bare protected-mode `int 80h` depends on what
the host and the extender happen to do with vector 80h, and here they do
nothing good.

---

## Case 1: Mortal Kombat II (1994)

Midway / Acclaim, the DOS version, ported by Probe. `MK2.EXE` is a Watcom C
program bound to DOS/4GW 1.97. The sound drivers for each card are separate
real-mode files (`SBL.BIN` for the Sound Blaster, `GRV.BIN`, `AWE.BIN` and
others); `RM.DRV` is a real-mode keyboard and timer driver. The music is in
`SOUND\`, the sound effects in `FX\`. The settings, sound card included, are
kept in a 440-byte file named `CMOS`, like the arcade machine's battery-backed
memory.

| File | Size | MD5 |
|---|---|---|
| `MK2.EXE` (original, 7 Feb 1995) | 861 133 | `98f1803e75b836fd9e62434e1ae6cd6d` |
| `MK2.EXE` fixed (`MK2FIX.EXE`) | 936 669 | `acfc68b1a05d1cb3c3049c7503646c06` |
| `SBL.BIN` (Sound Blaster driver, see [Broken Record](broken-record.md#case-3-mortal-kombat-ii-1994)) | 11 408 | `0251aa45903c415ec705ddf28d1f1ac9` |
| `RM.DRV` (not patched) | 2 522 | |

The 86Duino setup (boot menu entry *S*): `HIMEMX /MAX=32768`,
`JEMM386 EMX NOA20 NOHI I=TEST X=TEST`, `JLOAD QPIEMU.DLL`,
`HDPMI32I -r -x`, `SBEMU /i5`, `SET CAUSEWAY=DPMI`, `CTMOUSE /W`,
`86CRSBAR N`.

All tools mentioned here are in [`tools/`](tools/). Addresses are linear
addresses in the loaded program, as `le_load.py` shows them.

### Step 1: The symptom

On the 86Duino under boot *S*, `MK2.EXE` prints the DOS/4GW banner and is
back at the DOS prompt a moment later. In QEMU, with the same driver stack
(JEMMEX, QPIEMU, HDPMI32i, SBEMU with an emulated HD Audio card, see
[`qemu_sbemu.sh`](tools/qemu_sbemu.sh)), every build of the game that still
had a protected-mode `int 80h` in it ended the same way, with exit code
**7**.

Exit code 7 is DOS/4GW giving up. It is also what Command & Conquer does
under the same stack.

### Step 2: The trace

QEMU can log every interrupt and exception (`qemu_mon.py 'log int'`). Just
before the end, the log shows:

1. The game executes `int 80h` in protected mode, with `AH` = a driver
   function number.
2. That raises a **general protection fault** with error code `0402h`, which
   means "interrupt table entry 80h".
3. The fault handling then issues `int 0FCh`, which faults the same way
   (error code `07E2h`), again and again. Each round the stack is 20h bytes
   lower.
4. When the stack runs out, DOS/4GW calls DOS function `4Ch` with exit code 7.

A trap for the unwary when checking exit codes in a batch file: any program
run after the game (here a small "back to text mode" `.COM`) resets
`ERRORLEVEL` to 0. The real exit code was found in the interrupt log.

### Step 3: Who knocks on gate 80h

The game installs its sound driver like this: it loads `SBL.BIN` into
conventional memory, then sets the **real-mode** vector 80h to the driver's
entry at offset 4 (a `call` to the driver's dispatcher, then `iret`), with
DPMI function `0201h`, through a small helper at `0x102E4`. The driver's
functions are selected by `AH` (0 init, 3 timer tick, 4 start song, and so
on).

Then the game calls the driver in two ways:

- **Through `int386()`** (`0x4C936`, Watcom's library function): driver
  setup, starting and stopping songs, volumes.
- **With a bare `int 80h`**, in 11 places in the music code (`0x2F871`,
  `0x2F879`, `0x2F87D`, `0x2F881`, `0x2F8C3`, `0x2F966`, `0x34ACB`,
  `0x34AD1`, `0x34AD7`, `0x34ADD`, `0x34AFA`).

Both end in a protected-mode `int 80h`, and both knock on the sealed gate.

### Step 4: Opening the gate

Two patches, one for each kind of call:

1. **`int386()`**: its first 7 bytes become a jump to
   [`mk2_int80.S`](tools/mk2_int80.S). When the interrupt number is 80h, the
   helper copies the game's registers into a DPMI real-mode call structure,
   calls the driver with **DPMI `0300h`** (*simulate real-mode interrupt*,
   `BL` = 80h) and copies the results back. That works under every DPMI host
   and without one. Any other interrupt number goes on into the original
   `int386()`.
2. **The 11 bare `int 80h`**: there is no room to turn a 2-byte `int`
   instruction into a call, so each one becomes **`int 68h`**, an interrupt
   HDPMI32i and DOS/4GW pass down to real mode the ordinary way. For that to
   reach the driver, real-mode vector 68h must point at it too: the game's
   "set real-mode vector" helper (`0x102E4`) now jumps first to
   [`mk2_vec68.S`](tools/mk2_vec68.S), which, whenever the game sets vector
   80h, sets vector 68h to the same address. When the game uninstalls the
   driver, vector 68h gets its old value back.

Why `int 68h` passes where `int 80h` faults wasn't investigated (see
[Loose ends](#loose-ends)).

The helpers need room. `MK2.EXE`'s code object ends at `0x4EE98`, in the
middle of a 4 KB page, and the rest of that page is zeros in the file. The
object's size is raised to `0x3F000` bytes, and the helpers go into that
tail: `mk2_int80.S` at `0x4EEA0`, `mk2_read.S` (below) at `0x4EF40`,
`mk2_vec68.S` at `0x4EF80`. No relocation touches any patched byte;
`mk2_build.py` checks.

### Step 5: The extender swap

The fix also replaces the DOS/4GW 1.97 extender in `MK2.EXE` with **DOS/4GW
Professional 2.00**, taken from Grand Theft Auto's `GTA8.EXE` (the freeware
release, its first `0x38D64` bytes). The game's own program part, from its
inner `MZ` header at file offset `0x26654`, is put behind it unchanged.

This was done early in the diagnosis, when the old extender itself looked
like part of the trouble (in the first trace it made a VCPI call of its own
before giving up), while DOS/4GW 2.00 had already run GTA under exactly this
stack. The version tested and confirmed on the 86Duino has the swap.
**Whether the swap is actually needed is an open question:** once both kinds
of `int 80h` were dealt with, a single QEMU run of a build that kept the
original 1.97 extender also reached a fight, with sound. That build was
never tried on the 86Duino.

### Step 6: The Short Pour

The new extender brought a trap of its own. With just the swap, the game
stopped with *"mk: file SBL.BIN is corrupt!"*.

DOS/4GW 2.00, asked to read more than 8 KB into conventional memory in one
DOS call, delivers only 8 KB (`2000h` bytes) and reports that, **but the file
position moves on by the full amount**. The rest of the data is simply lost;
the next read starts after it. DOS/4GW 1.97 reads the whole block. The game
reads each file with a single DOS call and expects everything:

| Where | What it reads | With the short read |
|---|---|---|
| `0x10818` file loader | Drivers, `RM.DRV`, `CMOS`, all `*.GRA` graphics | Compares the count and stops with *"is corrupt"*, or, for files loaded without that check, carries on with a half-loaded file |
| `0x2F8AF`, `0x2F99E` | Music (`SOUND\*.SBL`), up to 64 KB | No check: silently truncated songs |
| `0x4C65A` | Sound effects (`FX\*`) | Checks the count and gives up on the effect |

The half-loaded case is the nasty one. An early build of the fix, before the
reads were split, crashed on the 86Duino with a JEMM386 *"exception 06"*
(invalid opcode) inside the sound driver as soon as the first song started.
A memory dump in DOSBox-X showed the driver in memory matching `SBL.BIN` only
up to offset `1FFFh`: everything after the first 8 KB, including the
pointer to the song data, was whatever had been in memory before. In QEMU
that junk happened to be harmless; on the 86Duino it sent the driver's
voice setup loop running over its own code.

The fix is [`mk2_read.S`](tools/mk2_read.S), *readcap*: it reads in pieces of
at most 8 KB until the wanted size has arrived or the file ends. The loader
is rewritten around it ([`mk2_loader.S`](tools/mk2_loader.S), in the
original's 112 bytes, same error messages), and the music and effect reads
call it in place of their single `int 21h`.

Theories ruled out on the 86Duino before the memory dump found the real
cause: a DMA buffer crossing a 64 KB boundary, interrupts nesting in the
driver's mixer, the DMA channel (1 or 3), and a difference between what
protected mode and real mode see in conventional memory.

### Step 7: IRQ 5 and the `CMOS` file

The game passes the Sound Blaster's port, IRQ and DMA channel from its
`CMOS` file to the driver (the driver's own autodetection runs only with
port 0). The original file says IRQ 7. SBEMU on the 86Duino is set to IRQ 5
(`SBEMU /i5`), and IRQ 7 is often advised against on the 86Duino, so `CMOS`
was changed to IRQ 5.

The file has a checksum: the word at `1B6h` is the 16-bit sum of bytes
`0`–`1B5h`. With a wrong checksum the game discards the whole file and uses
its defaults, sound off. [`mk2_cmos.py`](tools/mk2_cmos.py) shows and edits
the sound fields and fixes the checksum:

| Offset | Field |
|---|---|
| `0BCh` | Sound card: 8 = Sound Blaster (`SBL.BIN`), 0 = no sound |
| `0C0h` | Port (`220h`) |
| `0C4h` | IRQ |
| `0C8h` | DMA channel |
| `1B6h` | Checksum (word) |

```
python3 tools/mk2_cmos.py CMOS CMOS.I5 irq=5
```

### Step 8: Building and installing

```
python3 tools/mk2_build.py MK2.EXE GTA8.EXE MK2FIX.EXE
python3 tools/mk2_sbl_build.py SBL.BIN SBLFIX.BIN
python3 tools/mk2_cmos.py CMOS CMOS.I5 irq=5
```

`mk2_build.py` checks the MD5 of `MK2.EXE` and of the extender part of
`GTA8.EXE` first. Then, in the game folder, keep the originals and copy
`SBLFIX.BIN` over `SBL.BIN` and `CMOS.I5` over `CMOS`, and start
`MK2FIX.EXE`. F1 and F2 are the start buttons for players 1 and 2.

All patches of `mk2_build.py`:

| Address | Original | New |
|---|---|---|
| file start | DOS/4GW 1.97 (`0x26654` bytes) | DOS/4GW Professional 2.00 from `GTA8.EXE` (`0x38D64` bytes) |
| `0x10818` | file loader (112 bytes) | `mk2_loader.S` (readcap, same checks and messages) |
| `0x102E4` | `push ecx; sub esp,1Ch; mov [esp+4],al` | `jmp 0x4EF80` (`mk2_vec68.S`) |
| `0x2F8AF`, `0x2F99E` | music read (`int 21h`, `AH=3Fh`) | `call readcap` |
| 11 sites (Step 3) | `int 80h` (`CD 80`) | `int 68h` (`CD 68`) |
| `0x4C65A` | effect read | `call readcap` |
| `0x4C936` | `int386` prologue | `jmp 0x4EEA0` (`mk2_int80.S`) |
| object 1 size | `0x3EE98` | `0x3F000` (helpers at `0x4EEA0`, `0x4EF40`, `0x4EF80`) |

### Step 9: Tests

| Where | Build | Result |
|---|---|---|
| QEMU, boot *S* stack | extender swap + readcap + `int386()` patch only | Exit code 7: the 11 bare `int 80h` in the music code still fault |
| QEMU, boot *S* stack | `MK2FIX.EXE`, `CMOS` IRQ 5 | Intro with music, F1 → *Choose Your Fighter*, the whole tower, fights with music and effects |
| 86Duino, boot *S* | `MK2.EXE` | Exits immediately |
| 86Duino, boot *S* | `MK2FIX.EXE`, `CMOS` IRQ 5 | Character select, winning a match, on to the next one; music fine; sound effects "e‑e‑e" → [Broken Record](broken-record.md#case-3-mortal-kombat-ii-1994) |
| 86Duino, boot *S* | `MK2FIX.EXE` + `SBLFIX.BIN`, `CMOS` IRQ 5 | ✅ "The sound and the music are perfect and the game is stable enough to play" |

QEMU's keyboard needs keys held a little for this game
(`qemu_mon.py 'sendkey f1 300'`).

### Loose ends

- **Is the extender swap needed?** See [Step 5](#step-5-the-extender-swap).
  If it isn't, the Short Pour and its fix aren't needed either.
- **Why `int 80h` faults and `int 68h` doesn't.** Both are plain software
  interrupts with real-mode vectors set the same way. The difference lies
  somewhere in how HDPMI32i and DOS/4GW treat vector 80h; not investigated,
  since `int 68h` and DPMI `0300h` both work.
- **Command & Conquer.** Its exit code 7 under HDPMI32i looks the same from
  the outside. Not checked yet.

---

## Recipe for the next game

1. **Is it Sealed Gate?** A DOS/4GW game exits with code 7 right after the
   banner, only when HDPMI32i is loaded. Check the code with
   `IF ERRORLEVEL 7` straight after the game, before anything else runs.
2. **Trace it** in QEMU with [`qemu_sbemu.sh`](tools/qemu_sbemu.sh) and
   `qemu_mon.py 'log int'`: look for a software interrupt from the game's code
   followed by a general protection fault whose error code is the interrupt
   number × 8 + 2 (`0402h` for 80h).
3. **Find the callers.** Calls through `int386()` can be redirected at one
   place, the start of `int386()`, to DPMI `0300h` (copy
   [`mk2_int80.S`](tools/mk2_int80.S)). Bare `int` instructions need each
   site patched, for example to an interrupt that passes, with its real-mode
   vector set alongside (like [`mk2_vec68.S`](tools/mk2_vec68.S)).
4. **If you swap the extender** for DOS/4GW 2.00, look for DOS reads of more
   than 8 KB into conventional memory and split them
   ([`mk2_read.S`](tools/mk2_read.S)). Check loaded files against the
   originals with a memory dump before trusting them.
5. **Room for helpers:** the tail of the last page of the code object is
   often free; raise the object size in the object table (`le_load.py`
   shows the objects and their fixups).

---

## Tools

| File | What it does |
|---|---|
| `mk2_build.py` | Builds `MK2FIX.EXE` from `MK2.EXE` and `GTA8.EXE` (extender swap, all patches; checks the original bytes and relocations). |
| `mk2_int80.S` | `int386()` hook: interrupt 80h via DPMI `0300h`. |
| `mk2_vec68.S` | Sets real-mode vector 68h whenever the game sets 80h; restores it on uninstall. |
| `mk2_read.S`, `mk2_loader.S` | *readcap* (reads in pieces of at most 8 KB) and the file loader rewritten around it. |
| `mk2_cmos.py` | Shows and edits the sound card fields of the game's `CMOS` file and fixes its checksum. |
| `mk2_sbl_build.py`, `mk2_sbl_dmapoll.S` | The [Broken Record](broken-record.md#case-3-mortal-kombat-ii-1994) fix for `SBL.BIN`. |
| `le_load.py`, `qemu_sbemu.sh`, `qemu_mon.py` | Shared tools (see the [tools in the overview of the game fixes](86duino-game-fixes.md#tools)). |

## Sources

- Disassembly of `MK2.EXE` (via `le_load.py`), `SBL.BIN` and `RM.DRV`
  (16-bit `objdump`).
- QEMU interrupt and exception logs (`-d int`) of the game under JEMMEX,
  HDPMI32i and SBEMU 1.0.0-beta.5.
- DPMI 0.9 specification: functions `0200h`/`0201h` (get/set real-mode
  interrupt vector) and `0300h` (simulate real-mode interrupt).
- Watcom C library: `int386()` and its `REGS` layout.
