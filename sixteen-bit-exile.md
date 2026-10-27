# Sixteen-Bit Exile: when SBEMU's world has no room for a 16-bit game

SBEMU needs a DPMI host, and the one it comes with, HDPMI32i, serves
**32-bit** protected-mode programs only. Most protected-mode DOS games are
32-bit, so this rarely matters. But some games of the mid-1990s were built
with Borland Pascal 7 or Borland C++ as **16-bit** protected-mode programs,
started by Borland's run-time manager `RTM.EXE`. RTM finds a DPMI host
running, asks it for a 16-bit session, is turned away, and gives up with
*"Loader error (0025): cannot initialize"*. Without SBEMU the same game runs
fine, because then RTM starts Borland's own host, `DPMI16BI.OVL`. But that
host keeps the game's sound-card access to itself, out of SBEMU's reach.

Getting such a game back takes a second, 16-bit DPMI host next to SBEMU's,
and a messenger that carries the game's sound-card I/O over to SBEMU. On the
way there are four obstacles. I call the whole thing **Sixteen-Bit Exile**.

| Face | What you see | What is really there |
|---|---|---|
| **The Turned-Away Guest** | Under SBEMU: *"Loader error (0025): cannot initialize"*, straight back to DOS | Borland's RTM asks the resident DPMI host, HDPMI32i, for a 16-bit session; HDPMI32 runs 32-bit clients only |
| **The Jealous Doorkeeper** | HDPMI16i, the 16-bit sibling, loads without a word but isn't there; loaded first, it stops SBEMU's HDPMI32i from loading instead | Each HDPMI checks whether an HDPMI is already running, and quits if it's one of another version. SBEMU's HDPMI32i is 3.20, the current HDPMI16i is 3.23 |
| **The Deaf Room** | With both hosts loaded, the game runs, but in complete silence | SBEMU's port traps live in HDPMI32i. The game now runs under HDPMI16i, whose ports nobody watches |
| **The Trampled Frame** | With the sound forwarded, the game dies the moment the first sound starts: *"Runtime error 216"*, or a silent exit | The game's sound IRQ handler runs on HDPMI16i's interrupt stack. RTM's handler for a "segment not present" fault pushes three words just below the interrupted SP, right where HDPMI16i has just put the fault's own frame |

The diagnosis, the tools and the patches on this page are by **Claude**
(Anthropic's Claude Opus 5.5, working in Claude Code). I tested them on the
real 86Duino.

This is a sister page of [Tick Starvation](tick-starvation.md),
[Clock Mirage](clock-mirage.md), [Wet Ink](wet-ink.md),
[Borrowed Interrupt Flag](borrowed-interrupt-flag.md),
[Trap Storm](trap-storm.md), [Ghost Frame](ghost-frame.md),
[Broken Record](broken-record.md), [Sealed Gate](sealed-gate.md),
[Side Door](side-door.md) and [Late Echo](late-echo.md); all eleven are listed in the
[overview of the game fixes](86duino-game-fixes.md). Like Side Door, this one is a software-stack
issue: it shows up in QEMU exactly as on the 86Duino.

## Games

| Game | Year | Files patched | Faces | Fix | Status on 86Duino |
|---|---|---|---|---|---|
| [Chasm: The Rift](#case-1-chasm-the-rift-1997) | 1997 | none: `HDPMI16X.EXE` + `SBFWD16.COM`, started by `CHASMSB.BAT` | all four | Patched HDPMI16i (2 sites) + a port forwarder | ✅ "It works very well" |
| *next game here* | | | | | |

**Suspects (not tested).** Any 16-bit protected-mode game made with Borland
Pascal 7 or Borland C++ 3.x/4.x: look for `RTM.EXE` and `DPMI16BI.OVL` next
to the game, or *"Loader error"* under SBEMU. `SBFWD16` and `HDPMI16X` are
not tied to Chasm; only the batch file is.

---

## The original request

> Now at the game in directory CHASM. It works well without sound and SBEMU
> but when SBEMU is in the background then it is not starting up but exits
> with an error. Please make it work with SBEMU.

Asked for the exact message: *"yes, it's Loader error (0025), please
continue"*. After the fix: *"another case of dark magic, it works very well
on my x86Duino."*

---

## Background

### Sixteen and thirty-two

A DPMI client tells the host at its first switch into protected mode whether
it is a 16-bit or a 32-bit program (bit 0 of `AX`). The difference goes
deep: 16- and 32-bit clients get different interrupt and exception frames,
different stack handling and different register conventions throughout the
DPMI interface. HDPMI is therefore built twice from the same source:
`HDPMI16` for 16-bit clients and `HDPMI32` for 32-bit ones. Its
documentation says the two can be resident together: a request of the other
kind is passed on to the host installed before.

The `i` variants (`HDPMI16i`, `HDPMI32i`) run their clients at I/O privilege
level 0, so that every `in` and `out` traps into the host, and they offer an
interface for other programs to watch port ranges. SBEMU uses that interface
in its own copy of HDPMI32i to emulate the Sound Blaster for protected-mode
games.

### How SBEMU hears a game

For a protected-mode game, HDPMI32i passes trapped port accesses to SBEMU.
For a real-mode game, JEMMEX with `JLOAD QPIEMU.DLL` does the same in
virtual-8086 mode. The second path is the way back in for the exile: any
I/O that is replayed in real mode reaches SBEMU, whoever did it first.

### Borland's RTM

`RTM.EXE` is the loader and memory manager of Borland's 16-bit protected-mode
programs. It looks for a DPMI host. If there is none, it starts Borland's
`DPMI16BI.OVL`; if there is one, it uses that. It also loads code segments on
demand and makes memory blocks present only when they're first touched. Both
go through its handler for exception 0Bh, "segment not present".

---

## Case 1: Chasm: The Rift (1997)

Megamedia's first-person shooter, patched version with the TCP/IP add-on.
`CHASM.EXE` is a small real-mode Borland Pascal program (the network
processor); it starts `PS10.EXE`, the game itself, a Borland Pascal 7
16-bit protected-mode program run by `RTM.EXE`. The game reads the
`BLASTER` variable for its Sound Blaster settings.

| File | Size | MD5 | Changed? |
|---|---|---|---|
| `CHASM.EXE` | 20 688 | `104795857667c6bd84d5539af0119f82` | no |
| `PS10.EXE` | 273 920 | `305880623d52af0558a2633f28d63df3` | no |
| `RTM.EXE` | 108 846 | `591559541934942bdc2e9c1542d9c010` | no |
| `HDPMI16i.EXE` (HX 2.23) | 37 376 | `68d6a2714a0ddb538fad2d3dc3e7a782` | → `HDPMI16X.EXE` |
| `HDPMI16X.EXE` | 37 376 | `6b7e3cfcadb4ce1d50725e1bfb30d645` | new |
| `SBFWD16.COM` | 2 640 | `5e654311632c4c63821917da14e8066f` | new |

The 86Duino setup (boot menu entry *S*): `HIMEMX /MAX=32768`,
`JEMM386 EMX NOA20 NOHI I=TEST X=TEST`, `JLOAD QPIEMU.DLL`,
`HDPMI32I -r -x`, `SBEMU /i5`, `SET CAUSEWAY=DPMI`, `CTMOUSE /W`,
`86CRSBAR N`.

### Step 1: The Turned-Away Guest

In QEMU with the same driver stack (see [`qemu_sbemu.sh`](tools/qemu_sbemu.sh)),
the game stops exactly as on the 86Duino:

```
CHASM Network processor. Version 2.1. (TCP/IP)
Starting CHASM:
Loader error (0025): cannot initialize
```

The message comes from the loader stub in `PS10.EXE`: RTM has found HDPMI32i
and asked it for a 16-bit session.

A detour on the way: with QEMU's CPU at full speed, `CHASM.EXE` died even
earlier, with *"Runtime error 200"*. That is the well-known division overflow
in Borland's delay calibration on very fast CPUs (here at `CHASM.EXE`
`0x32AA` and `PS10.EXE` `0x14C74`). It needs over 36 million loop rounds per
timer tick, which the 86Duino is nowhere near, so it played no part. The
full-speed QEMU tests used copies with the calibration neutralised. The final
check ran the untouched files on a slowed-down CPU.

### Step 2: The Jealous Doorkeeper

The 16-bit HDPMI16i comes with the HX runtime (`HXRT223.zip`,
`BIN\HDPMI16i.EXE`). Loaded **before** HDPMI32i, the game started, but
SBEMU then found no 32-bit host (*"Load error: no DPMI"*), because HDPMI32i
had quietly refused to load. Loaded **after** HDPMI32i, HDPMI16i printed
nothing and wasn't there; the game showed loader error 0025 again.

The reason is in HDPMI's start-up code (`INIT.ASM`, lines 642–664). It asks
for a DPMI host, and if the one it finds is an HDPMI, it compares the name
**and the version number**. Same version, other bitness: install, and share
the other host's buffer. Any other HDPMI: quit without installing. SBEMU
ships its own HDPMI32i, version 3.20; HDPMI16i from HX 2.23 is 3.23.

Sharing the other host's buffer would mean reading fields of a different
version's internal tables, so the patch doesn't pretend the versions match.
It sends HDPMI16i down the "no DPMI host found" path instead, and it installs
as an independent host on JEMMEX's VCPI:

| File offset | Original | New |
|---|---|---|
| `0x0F7C` | `0F 85 5A 01` (`jnz initsvr_ex`) | `0F 85 0A 00` (`jnz nodpmi`) |

This HDPMI16X catches every DPMI program started while it is resident,
32-bit ones included, and it can't serve those. So it is loaded just for the
game and removed right after (`HDPMI16X -u`).

### Step 3: The Deaf Room

With HDPMI16X next to SBEMU, the game starts and runs its demo, and QEMU's
recording of the sound card is all zeros. The game's port I/O goes through
HDPMI16X, whose traps SBEMU never set.

The messenger is [`sbfwd16.S`](tools/sbfwd16.S), `SBFWD16.COM`:

1. It enters protected mode as a 16-bit client of HDPMI16X.
2. Through HDPMI's vendor interface (`INT 2Fh`, `AX=168Ah`, function 6) it
   traps the same ports SBEMU watches, in eight ranges (HDPMI's maximum):
   DMA `00h`–`0Fh`, `81h`–`8Fh`, `C0h`–`DFh`; PIC `20h`–`21h`, `A0h`–`A1h`;
   Sound Blaster `220h`–`22Fh`; MPU-401 `330h`–`331h`; OPL `388h`–`38Bh`.
3. It runs the game as its child (`INT 21h`, `AX=4B00h`, which HDPMI
   translates). The child is a new client of the same host and address
   space, so the traps cover it.
4. Each trapped `IN` or `OUT` arrives at SBFWD16's handler like an exception,
   with the instruction's size, direction and port in the error code. The
   handler replays it in real mode with DPMI function `0301h` (call a
   real-mode procedure). There JEMMEX and QPIEMU catch it and hand it to
   SBEMU. For an `IN`, the result goes back into the game's `AL`/`AX`; then
   the game's `IP` is moved past the instruction.
5. When the game ends, it removes the traps and prints how many accesses it
   forwarded.

The interrupt needs no help: SBEMU raises it by calling the real-mode
vector, and HDPMI16X passes that on to the game's protected-mode handler as
it would any real-mode IRQ.

With SBFWD16 the game reported *"Sound: SB16 #220h, IRQ05, DMA5, DSPv4.00"*.
It had found the emulated card. Then it died.

### Step 4: The Trampled Frame

The crash came a few seconds in, right where the first sound starts:
*"Runtime error 216"* (Borland's code for a protection fault) at
`00E7:95F7`, or just a silent exit. QEMU's exception log showed the chain:

1. The game's sound IRQ handler runs on HDPMI16X's **locked interrupt stack**,
   because the IRQ arrives from real mode.
2. It touches a memory block RTM hasn't made present yet: exception 0Bh,
   "segment not present", selector `068Ch`. During normal play RTM handles
   hundreds of these.
3. HDPMI16X calls RTM's handler. Because the fault happened on the locked
   stack, HDPMI puts the 16-byte exception frame **directly below the
   interrupted SP, on that same stack** (`HDPMI.ASM`, line 1945).
4. RTM's handler (`RTM.EXE`, code at `9576h`) loads the block and then
   arranges a detour through its own code. It decrements the interrupted
   SP and writes FLAGS, CS and IP there, the three words right below the
   interrupted SP. With the frame sitting there, the first word, FLAGS
   `0202h`, overwrites the frame's SS field.
5. Its next instruction reads the interrupted SS:SP back from the frame
   (`les bx,[bp+20h]` at `95F7h`), loads `0200h` as a selector and faults.

Under Borland's own host the exception frame is always on a separate stack,
so the pushes can't hit it. The patch leaves room: HDPMI16X puts the frame
64 bytes lower when the locked stack is already in use. HDPMI's return path
takes the frame from the current stack position, so the gap costs nothing.

| File offset | Original | New |
|---|---|---|
| `0x2129` | `83 EF 10` (`sub edi,10h`) | `83 EF 50` (`sub edi,50h`) |

An earlier attempt, marking all of `PS10.EXE`'s code segments "preload", got
rid of the first such fault but not of the memory blocks. With the frame gap,
the untouched `PS10.EXE` works.

### Step 5: Building and installing

```
python3 tools/hdpmi16x_build.py HDPMI16i.EXE HDPMI16X.EXE
python3 tools/dosbuild.py sbfwd16.S
```

`hdpmi16x_build.py` checks the MD5 of `HDPMI16i.EXE` from
[HX 2.23](https://github.com/Baron-von-Riedesel/HX/releases/tag/v2.23)
(`HXRT223.zip`, folder `BIN`). Copy `HDPMI16X.EXE` and `SBFWD16.COM` into the
game folder, together with `CHASMSB.BAT`:

```
@ECHO OFF
HDPMI16X -r
SBFWD16 CHASM.EXE %1 %2 %3 %4 %5 %6 %7 %8 %9
HDPMI16X -u
```

Boot with SBEMU as usual (*S*), then start `CHASMSB` in place of `CHASM`.
For the add-on levels: `CHASMSB -addon:addon1`. When the game
ends, SBFWD16 prints the number of forwarded port accesses,
`HDPMI16X -u` reports *"HDPMI16 uninstalled"*, and SBEMU's HDPMI32i stays in
place for the next game.

### Step 6: Tests

| Where | Setup | Result |
|---|---|---|
| QEMU, boot *S* stack | `CHASM.EXE` | Loader error (0025) |
| QEMU | HDPMI16i before HDPMI32i | Game starts; SBEMU: *"no DPMI"* |
| QEMU | HDPMI16i after HDPMI32i | HDPMI16i doesn't install; loader error (0025) |
| QEMU | + HDPMI16X (version patch) | Demo runs, silent |
| QEMU | + SBFWD16 | SB16 detected; crash when the first sound starts (Runtime error 216) |
| QEMU | + frame gap | Demo, menus, briefing, level 1 moving and shooting: sound throughout, 2.6 minutes, no stuck loop; clean quit and unload |
| QEMU, slowed CPU | untouched game files, `CHASMSB.BAT` | Demo with sound |
| 86Duino, boot *S* | `CHASMSB.BAT` | ✅ "It works very well" |

About 8 300 port accesses were forwarded in a minute and a half of play,
under a hundred per second: far from a [Trap Storm](trap-storm.md).

### Loose ends

- **String I/O** (`INS`/`OUTS`) isn't forwarded, only counted; Chasm uses
  none. A game that does would need it added to `sbfwd16.S`.
- **Multiplayer** wasn't tried.

---

## Recipe for the next game

1. **Is it Sixteen-Bit Exile?** *"Loader error"* under SBEMU, fine without;
   `RTM.EXE` / `DPMI16BI.OVL` next to the game (Borland Pascal 7 or
   Borland C++ protected mode).
2. **Run it** with `HDPMI16X -r`, then `SBFWD16 GAME.EXE`, then
   `HDPMI16X -u`. SBFWD16 needs the full file name with extension; if the
   game is started by a batch file or a loader, start that program through
   SBFWD16, so the 16-bit game ends up as its child.
3. **If it's silent**, check the game's sound settings against SBEMU's, and
   look at SBFWD16's count when it exits. Zero means the game never talked to
   the card; string I/O counted means `sbfwd16.S` needs to forward it.
4. **If it crashes at the first sound**, trace it in QEMU
   (`qemu_mon.py 'log int'`) and look for a fault on HDPMI's locked stack
   (`SS` with base `FF82xxxx`).

---

## Tools

| File | What it does |
|---|---|
| `sbfwd16.S` (`SBFWD16.COM`) | 16-bit DPMI client of HDPMI16i that traps the ports SBEMU emulates, replays each `IN`/`OUT` in real mode for SBEMU, and runs the game as its child. |
| `hdpmi16x_build.py` | Builds `HDPMI16X.EXE` from HX 2.23's `HDPMI16i.EXE` (version check, frame gap). |
| `dosbuild.py` | Assembles `sbfwd16.S`. |
| `qemu_sbemu.sh`, `qemu_mon.py`, `loopcheck.py` | Shared tools (see the [tools in the overview of the game fixes](86duino-game-fixes.md#tools)). |

## Sources

- HX source code, [github.com/Baron-von-Riedesel/HX](https://github.com/Baron-von-Riedesel/HX):
  `Src/HDPMI/INIT.ASM` (start-up, host detection), `HDPMI.ASM`
  (`lpms_call_exc`, port-trap dispatch), `I2FHDPMI.ASM` (vendor API,
  port traps); `HDPMI.TXT`, `HDPMIAPI.TXT`.
- SBEMU source code, [github.com/crazii/SBEMU](https://github.com/crazii/SBEMU):
  `hdpmipt.c` (its HDPMI32i port traps), `sbemu/virq.c` (virtual IRQ),
  `main.c` (trapped port ranges).
- Disassembly of `RTM.EXE` (exception 0Bh handler) and of `PS10.EXE`'s loader
  stub and NE segment table.
- QEMU interrupt and exception logs (`-d int`) and the GDB stub, under JEMMEX,
  HDPMI32i, HDPMI16X and SBEMU 1.0.0-beta.5.
- DPMI 0.9 specification: `INT 2Fh` `1687h`, `INT 31h` `0301h`, exception
  handler frames.
