# ND-120 CPU

## Content

This repo contains:

* Original **Norsk Data** ND-120 CPU Design Documents from 1988. Scanned in 2023
* Modern Logisim and HDL implementation from 2023.

You can read more about this [CPU](https://www.ndwiki.org/wiki/3202) and much more in [NDWiki](https://www.ndwiki.org/) and the official website for [Norsk Data](http://sintran.com/)

The goal of this repo is to re-create the schematics and create the HDL files so we can program an FPGA to run as the original ND-120 CPU Card.

On the way to the FPGA code, there will be testable Logisim Circuits and Logisim code that can be converted and tested in C++ using Verilator.

## Current Status

### Where the project stands (02-SEP-2026)

The machine runs the original operating system on real hardware - on **three
boards**. **SINTRAN III boots on the Tang Nano 20K** (24-AUG), the **Nexys 4
DDR** (25-AUG) and the **MiSTer / DE10-Nano** (02-SEP), each from a Winchester
disc image, and you can log in and run programs. The Tang is the primary
target. A fourth machine, the **MEGA65**, builds for both board revisions and
is timing-clean, but has not yet run on a real MEGA65 - the release cores are
its first hardware test.

Verilator is no longer "the thing that works while hardware doesn't" - it is
the **signal-level reference**: waveforms, unit testbenches, and the
latch-versus-flip-flop comparison that proves a refactor changed nothing. The
Xilinx boards that only reach OPCOM (Basys3, Cmod A7) are held back by memory
capacity or timing, not by the CPU.

**Simulation (Verilator - the signal-level reference):**
- Microcode loads, Master Clear executes, and the CPU self-test passes
  clean: **0 execution-phase STERR visits** (measured with the
  `ND120_COUNT_STERR` probe in `Verilog/runSim/Run120.cpp`).
  An older status here read "self-test runs, 7 of 14 subtests passing".
  **That figure is retracted** - it predated the fixes and was never
  re-measured (`Verilog/docs/RETRACTED.md`). Careful when measuring: the
  WCS loader walks past the STERR address once while loading, so only
  execution-phase visits count.
- The self-test result is **not** a memory-parity question. Microcode
  analysis proved the self-test never touches memory parity, which is why
  FPGA targets compute parity on the read path instead of storing it
  (`Verilog/docs/nd120-parity-analysis.md`).
- **13 of 13 testable INSTRUCTION-B areas pass** on both layers - each
  area's own end-of-test with zero error lines, and the 400-instruction
  golden-trace comparison against the ND-110 reference
  (`Verilog/tests/instruction-verify/CAMPAIGN-STATUS.md`). The
  48-bit floating area is not applicable: our PROM microcode implements
  the 32-bit float option.
- OPCOM console works; `INSTRUCTION-B` loads and runs from the Verilog
  papertape device; DMA bus mastering against the real arbiter
- Golden-console and latch-vs-FF regression gates keep it all pinned

### TPE diagnostic programs - what actually runs

These are the original Norsk Data test programs, not our own testbenches.
Each row says where the result was measured; nothing here is inferred from
a passing run somewhere else.

| Program | Result | Measured on |
|---|---|---|
| **CONFIGURATION** (`load conf`) | **Passes** - runs to completion with `NO ERRORS DETECTED` and correctly enumerates the machine (ND-120/CX, 32-bit float, MMS-2, cache present, ALD 400B, print number 3202). Version D05, 1988-11-08 | Verilator (logged, 27-JUL-2026); confirmed working on the Tang |
| **INSTRUCTION** | **Passes.** In Verilator, **13 of 13** testable INSTRUCTION-B areas - each area's own deep end-of-test with zero error lines, plus a golden 400-instruction trace gate against the ND-110 reference. On the board, the full multi-level run over interrupt **levels 1-9 passes clean** | Verilator (13-JUL-2026) + Tang silicon (31-JUL-2026) |
| **PAGING** | **Passes 11 of 11**, including test 3 (PGU/WIP), test 4 (alternative PIT) and test 11 (physical address generation) | Tang silicon (30-JUL-2026) |
| **MEMORY** | **Passes.** An earlier open item here - the TPE Monitor's memory diagnostic returning a corrupted banner string (23-JUL) - was closed by the MMU cache fix on 27-JUL: the cache data output was not gated by `HIT`, so a stale line jammed the wired-OR `CD` bus. That is the same defect that produced the garbled `INST??CTION` banner | Tang silicon |
| **CACHE** (`CACHE-1X0-A00`) | **Passes all 8 tests**, including test 3 "Inhibit limits", which used to hang the board at `P=124563B`. Four faults had to be fixed first, all single-input transcription errors: the PAL 44511A `CWR` feedback latch, that PAL's pin-19 polarity (sheet 25 forms `HIT` with a 74S260 NOR that needs the net LOW on a read, so with `~CWR` no read could ever hit), a dropped Am9150 used-bit write, and a DGA `EPANS` data-window leak that accounted for all 20062 of test 1's errors | Nexys 4 DDR silicon (31-AUG-2026) |
| **TPE Monitor B01** | Boots from a floppy image (`1560&` at the OPCOM `#` prompt), reaches the `TPE>` prompt and accepts its own commands - this is the harness the diagnostics above are loaded and run from | Verilator (27-JUL-2026) + Tang silicon |
| **RUN** | Reaches its `== END OF TEST ==` after the Am2914 interrupt status fence was made default and MOR (memory-out-of-range) was wired to level 12 | Verilator (15-JUL-2026) |
| **48-BITS-FLOATING** | **Not applicable** - this machine's PROM microcode implements the 32-bit float option, so the area cannot apply (`Verilog/docs/48bit-float-not-configured.md`) | - |
| **DISC-TEMA J02** | **Not passing.** Loads and transfers real data off the disc image, register-for-register matching the reference model, but still reports `Memory address Register not as expected`. Unexplained, and the one known open diagnostic | Verilator + Tang silicon |

The five that pass clean on the board - **CONFIGURE, INSTRUCTION, PAGING,
MEMORY and CACHE** - are the machine's own acceptance suite: they check the CPU
identifies itself correctly, executes every instruction group correctly, that
the MMU translates and faults correctly, and that main memory is sound. With
those green and SINTRAN III booting, the ND-120 is a working machine rather
than a partially working one.

These campaigns are also what found the real CPU bugs, which is the argument
for running the original diagnostics rather than only our own testbenches:
INSTRUCTION caught a multiply bug (every product's low word was zero) and a
shift-control bug (all rotate and sign-extending shifts ran as plain shifts);
PAGING caught an MMU fault where the physical-page map RAM was never written
at all; CONFIGURATION caught a trap-vector generator that resolved a
simultaneous page-fault-plus-PGU to an unimplemented vector and self-jumped
forever.

### What enabling the cache is worth (31-AUG-2026)

The ND-120's cache can be compiled in or out (`cache` / `nocache` on the Nexys
build, `ND120_NO_CACHE`; see `Verilog/docs/build-defines.md`). Measured on the
Nexys 4 DDR with the operator panel's own MIPS counter, running SINTRAN III:

| build | CPU clock | cache | MIPS running SINTRAN | clocks per instruction |
|---|---|---|---|---|
| 15 | 45.45 MHz | off | 2.44 | 18.6 |
| 16 | 33.33 MHz | **on** | **> 7.0** | **< 4.8** |

**Enabling the cache is worth about 2.9x the real throughput - on a clock 26%
SLOWER.** Per instruction it is close to a 4x saving. Both figures are the same
workload (ordinary SINTRAN operation) read off the same counter, so it is a
like-for-like comparison rather than a benchmark.

**Why it is so large: this machine is memory-latency bound, not clock bound.**
With the cache out, every instruction fetch is a DDR2 read, and DDR2 does not
get faster when the CPU clock rises. The evidence is a one-word loop
(`124000` = `JMP` to its own address - no operand fetch, no write, no I/O),
deposited from the panel and therefore running on a page the cache-inhibit RAM
has not been set up for:

- at 45.45 MHz it ran at 2.66 MIPS - **17.1 clocks for a single `JMP`**
- at 33.33 MHz it ran at 1.95 MIPS - **17.1 clocks**, the identical figure

Three independent uncached measurements agreeing at 17.1 clocks per
instruction, with throughput scaling exactly with the clock (2.66/1.95 =
1.364 = 45.45/33.33), is what pins the bottleneck on memory rather than on the
CPU.

**A caution worth repeating, because it cost a day.** The opposite conclusion
was reached on 30-AUG - "speed beats cache", cache dropped to buy 45 MHz - and
it was wrong. The MIPS counter was then fed from a signal that counts MEMORY
CYCLES, so it went blind precisely when the cache started working: both
configurations read 2.44 and the cache looked worthless. Only after the counter
was re-tapped to a true per-instruction event (the instruction register taking
a new opcode) did the 3x difference appear. Never compare two numbers taken
with different instruments, and prove an instrument before trusting what it
says (`Verilog/docs/HANDOFF-mips-and-clock.md`).

**What this makes valuable.** Cache and a fast clock together is the real
machine: at under 4.8 clocks per instruction, the cache running at 45.45 MHz
would be roughly **9.5 MIPS**. It is not reachable today - with the cache in,
the routed worst path is 28.039 ns, a hard ceiling near **35.6 MHz** - and that
one path (`WRF -> ALU -> TVGEN -> ACAL -> WCS` address, 75% routing) is now the
highest-value optimisation target on the board. Details and the three possible
routes: `Verilog/fpga/nexys4ddr/timing.md`.

**FPGA hardware:**

> **Ready-built bitstreams:** grab them from the
> [Releases page](https://github.com/RetroCoreLabs/nd-120/releases) - no FPGA
> toolchain needed. Quickstarts: `Verilog/fpga/QUICKSTART-nexys4ddr.md`
> (incl. the no-software SD-card path),
> `Verilog/fpga/QUICKSTART-tang-nano-20k.md`,
> `Verilog/fpga/QUICKSTART-mister.md` and
> `Verilog/fpga/QUICKSTART-mega65.md` (MEGA65 cores: built, not yet run on
> a MEGA65 - the first testers are you).

- **Tang Nano 20K - SINTRAN III BOOTS (24-AUG-2026).** The operating system
  runs on the FPGA from a Winchester disc image on the SD card: banner in
  **29.4 s**, login, `LIST-FILES`, and the S3 program (cold start 13.2 s).
  Full CPU bitstream with **4 MB SDRAM main memory** (packed 16-bit storage,
  computed parity - `ND_SDRAM_PACK16`), the other 4 MB for the SD disk-image
  cache; SD/FAT stack proven on hardware (read + write, safety-gated).
  **Clocked up 26-AUG-2026: the `fast20` variant boots SINTRAN at
  20.25 MHz with a 115200 console, timing-clean (TNS 0)** - 3x the
  long-validated 6.75 MHz. Timings and clock variants:
  `Verilog/fpga/tang-nano-20k/README.md`.
- **Nexys 4 DDR - SINTRAN III BOOTS (25-AUG-2026), clocked up to
  45.45 MHz with a 115200 console (26-AUG-2026), SD-card deployment
  end to end (27-AUG-2026: the board configures itself from the microSD
  and boots from the same card - no PC software).** Full CPU, deployed at
  **45.45 MHz** (50 MHz also booted; frequency search and bottleneck
  analysis in `Verilog/fpga/nexys4ddr/timing.md`), main memory in **DDR2
  through a BRAM cache** (`MEM_RAM_49_DDR2`), boot disc on the on-board
  microSD:
  banner in ~40 s, console login verified, 7/7 boot cycles. The blocker
  was a dropped cache-hit update on late DDR2 write strobes - root cause,
  fix and validation in `Verilog/fpga/nexys4ddr/SINTRAN-BOOT-25AUG.md`.
  The board carries a debug panel (RGB health LEDs incl. a DDR2 watchdog,
  8-digit live state display): `Verilog/fpga/nexys4ddr/DEBUG-PANEL.md`.
- **MiSTer (DE10-Nano) - SINTRAN III BOOTS (02-SEP-2026).** The whole ND-120
  machine on the MiSTer framework: boots to OPCOM and, with a Winchester image
  mounted in the OSD, boots SINTRAN. CPU at 20 MHz, **4 MB main memory in the
  DE10-Nano SDRAM module**, the TDV2200 terminal on the MiSTer's own screen and
  keyboard, floppy/Winchester/tape as image files from the OSD. Confirmed on the
  board: boot, self-test (green `G` lamp), the box-drawing font and the keyboard.
  Quickstart: `Verilog/fpga/QUICKSTART-mister.md`.
- **Basys3**: OPCOM boots on the board (tag `fpga-opcom-working-basys3`);
  active debug line at 16.67 MHz. Does not meet timing (WNS -29.778 ns at
  16.667 MHz, measured 21-AUG-2026), so it does not boot the OS.
- **Dual toolchain**: the Tang builds with the OSS CAD Suite
  (yosys/nextpnr, primary) and Gowin EDA (backup) - all clock variants;
  nextpnr closes the full 27/54 MHz target with >2x margin
  (`Verilog/docs/tang20k-build-flows.md`)
- **Cmod A7-35T**: first build ready (BRAM memory, CPU at 27 MHz);
  512 KB SRAM main-memory bridge planned
- **MEGA65 - the whole machine builds for BOTH board revisions
  (02-SEP-2026), timing-clean, NOT YET RUN ON A MEGA65.** On the
  MiSTer2MEGA65 framework: ND-120 CPU with 4 MB main memory (R3: in the
  HyperRAM through the Nexys cache seam and a new Avalon port, CPU
  13.33 MHz; R4/R5/R6: in the 64 MB SDRAM through the MiSTer sheet-49
  bridge, CPU 20 MHz), the TDV2200 terminal on the MEGA65's own keyboard
  and screen (VGA + HDMI), floppy 0/1, Winchester 0/1 and paper tape as
  image files on the SD card through the framework's virtual drives, one
  `.cor` per revision flashed from the MEGA65's own menu. Every new block
  has a self-checking bench; the port and its facts:
  `Verilog/fpga/mega65/README.md`, `Verilog/fpga/mega65/docs/00-plan.md`.
  (`Verilog/fpga/cmod-a7-35t/SRAM-BRIDGE-PLAN.md`)
- Memory-backend speed rules for every board (what meets the no-wait-state
  protocol at 40 MHz and what cannot):
  `Verilog/docs/basys3-memory-speed-validation.md`

## Quick Start

```bash
cd Verilog/sim
make clean
make all  # Compiles, runs, and opens GTKWave
```

**Prerequisites:** [Verilator](https://www.veripool.org/verilator/), Icarus Verilog, GTKWave (optional). Development is done on Linux / WSL2 with bash.

See [BUILDING.md](BUILDING.md) for detailed build and test instructions.

## Requirements

The minimum requirements to make the CPU work:

| Component | Schematic | HDL | Status |
|-----------|-----------|-----|--------|
| [DELILAH CPU Gate Array (CGA)](DesignDocuments/DELILAH-CPU/readme.md) | Completed | Logisim generated Verilog | QA on schematic/Verilog ongoing |
| [NEC Decoder Gate Array (DGA)](DesignDocuments/DECODE-GateArray/Readme.md) | Completed | Logisim generated Verilog | QA on schematic/Verilog ongoing |
| [ND 3202 CPU Board revision D](DesignDocuments/CPU-BOARD-3202/Readme.md) | Completed | Logisim generated Verilog | QA on schematic/Verilog ongoing |
| [PAL Chips](DesignDocuments/PAL-Code/Readme.md) | All PALASM code has been validated | Verilog and testcode created | QA on Verilog ongoing |

In the CPU Board we will plug in the DELILAH CPU and the Decoder, all PAL chips and several other support chips (74-series, RAM and UART).

## History

The compressed history of the work progress has moved to [HISTORY.md](HISTORY.md).

## Design documents

All the design documents are in the [Design Documents](DesignDocuments/Readme.md) folder.

## Norsk Data documents

Functional Description, Instruction set, Microprogramming guide and more are in the [NorskData-Doc](NorskData-Doc/Readme.md) folder.

## Microcode

The [Microcode](Code/Microcode/readme.md) dump is from a ND-120 3202 CPU Board is Version 14/L
The source code is also for the L version.

## Panel Controller - 6805 CPU CHIP

[ROM dump](Code/68705/readme.md)

The ND-120/CX CPU Board has an on-board MC68705-U3 CPU.

The physical front panel also has an MC68705 CPU, however this chip is not identical to the on on the 3202D CPU Board - its an MC68705-P3 with fewer I/O pins.

The MC68705 is an MC 6805 8-bit CPU with on-chip RAM, I/O and Timer. [Motorola 68HC05](https://en.wikipedia.org/wiki/Motorola_68HC05)

* P3 version = 28 pins, 2x 8 bits I/O ports, 1x 4 bit I/O port
* U3 version = 40 pins, 4x 8 bits I/O ports

We have a ROM dumps from both the *MC68705-U3* chip (from the 3202D CPU Board) and the *MC68705-P3* (from an ND-5000C panel controller).

**Big thanks to Matthieu Benoit for reading the data out of the chips**

Reverse engineering has been done using the free SRE tool [GHIDRA](https://ghidra-sre.org/) from NSA.

## Schematic drawings

### Logisim

All the Logisim files are stored in the [Logisim folder](Logisim/readme.md)

#### Logisim Requirements

You need to install the Logisim-Evolution design tool from [Logisim Evolution Repository](https://github.com/logisim-evolution/logisim-evolution)

The Logisim diagrams has been drawn with [Version 3.8.0](https://github.com/logisim-evolution/logisim-evolution/releases/tag/v3.8.0)

## FPGA

### FPGA Hardware

The project targets several FPGA boards, each with its own folder of build
scripts, pin constraints, vendor documentation and bring-up plans under
[Verilog/fpga/](Verilog/fpga/README.md).

**For the current per-board FPGA status, target line-up and priority order,
see [Verilog/fpga/README.md](Verilog/fpga/README.md).**

### Verilog

Most Verilog files were originally generated from the Logisim drawings using the
Logisim-Evolution FPGA tools. They are **no longer regenerated** - the Verilog and
the schematics are now both maintained by hand, so a fix has to be made in both
places.

All the Verilog files are stored in the [Verilog folder](Verilog/)

### Verilator

To test the Verilog code using Verilator you need to install the [Verilator](https://www.veripool.org/verilator/) tool

## Documentation

Paths in this repository are always relative to the repository root. Where a
document has to point at one of the *other* ND repositories, it writes
`$ND_REPOS/<repo>/...` - set `ND_REPOS` to the directory that holds your ND
checkouts.

| Document | Description |
|----------|-------------|
| [BUILDING.md](BUILDING.md) | Build instructions, testing, and troubleshooting |
| [HISTORY.md](HISTORY.md) | Project history, milestone by milestone |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Architecture, coding standards, and contribution guide |
| [HARDWARE.md](HARDWARE.md) | Hardware specifications and component details |

## Acknowledgments

- **Lasse Bockelie** - Provided original 1988 design documentation
- **Matthieu Benoit** - ROM chip reading and data extraction
- **NDWiki Community** - Comprehensive ND-120 documentation
- **GHIDRA Team** - Reverse engineering tools