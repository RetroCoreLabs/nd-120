# ND-120: The Norsk Data ND-120 CPU, Rebuilt in Verilog

[![Verilog CI](https://github.com/RetroCoreLabs/nd-120/actions/workflows/verilog-ci.yml/badge.svg)](https://github.com/RetroCoreLabs/nd-120/actions/workflows/verilog-ci.yml)
[![Release](https://img.shields.io/github/v/release/RetroCoreLabs/nd-120?label=bitstreams)](https://github.com/RetroCoreLabs/nd-120/releases)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A full rebuild of the 1988 **Norsk Data ND-120** CPU card (the 3202D board) from
the original design documents - first drawn in Logisim-Evolution, now in
Verilog - that runs the original operating system, **SINTRAN III**, on FPGA
boards you can buy today.

**Note:** read more about this [CPU](https://www.ndwiki.org/wiki/3202) and the rest of the ND range in [NDWiki](https://www.ndwiki.org/), and on the official [Norsk Data](http://sintran.com/) site.

---

## 🎉 **SINTRAN III runs on real hardware**

**The machine boots SINTRAN III from a Winchester disc image on an SD card, and
you can log in and run programs.**

📥 **[Releases page](https://github.com/RetroCoreLabs/nd-120/releases)** - ready-built bitstreams, no FPGA tools needed

- ✅ **Tang Nano 20K** - boots SINTRAN, 20.25 MHz, timing-clean - [quickstart](Verilog/fpga/QUICKSTART-tang-nano-20k.md)
- ✅ **Nexys 4 DDR** - boots SINTRAN, 33.333 MHz with the cache on - [quickstart](Verilog/fpga/QUICKSTART-nexys4ddr.md)
- ✅ **MiSTer / DE10-Nano** - boots SINTRAN, 20 MHz - [quickstart](Verilog/fpga/QUICKSTART-mister.md)
- 🚧 **MEGA65** - builds for both board revisions, timing-clean, not yet run on a real MEGA65 - [quickstart](Verilog/fpga/QUICKSTART-mega65.md)

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Quick Start](#-quick-start)
- [FPGA Boards](#-fpga-boards)
- [Simulation](#-simulation)
- [Original Diagnostics](#-original-diagnostics)
- [What the Cache Is Worth](#-what-the-cache-is-worth)
- [Inside the Machine](#-inside-the-machine)
- [Documentation](#-documentation)
- [Project Status](#-project-status)
- [License](#-license)

---

## 🎯 Overview

This repository holds:

- the original **Norsk Data ND-120 design documents** from 1988, scanned in 2023;
- **Logisim-Evolution** schematics of every part of the board;
- the **Verilog** version of the whole card, which runs in Verilator and on FPGAs.

### Main Components

| Component | Schematic | HDL | Status |
|-----------|-----------|-----|--------|
| [DELILAH CPU Gate Array (CGA)](DesignDocuments/DELILAH-CPU/readme.md) | ✅ Complete | Verilog (first made from Logisim, now kept by hand) | ✅ Boots SINTRAN III |
| [NEC Decoder Gate Array (DGA)](DesignDocuments/DECODE-GateArray/Readme.md) | ✅ Complete | Verilog (first made from Logisim, now kept by hand) | ✅ Boots SINTRAN III |
| [ND 3202 CPU Board revision D](DesignDocuments/CPU-BOARD-3202/Readme.md) | ✅ Complete | Verilog (first made from Logisim, now kept by hand) | ✅ Boots SINTRAN III |
| [PAL chips](DesignDocuments/PAL-Code/Readme.md) | ✅ PALASM checked | Verilog with test benches | ✅ Boots SINTRAN III |

The CPU board carries the DELILAH CPU, the decoder, all PAL chips and the
support chips (74-series logic, RAM and the UART).

### What's Included

```
nd-120/
├── DesignDocuments/     # Original 1988 design documents (scanned)
├── NorskData-Doc/       # Functional description, instruction set, microprogramming guide
├── Logisim/             # Logisim-Evolution schematics
├── Code/
│   ├── Microcode/       # Microcode PROM images, sources (.uc) and listings (version L)
│   ├── 68705/           # Panel controller ROM dumps and analysis
│   └── RTC/             # Real-time clock notes
└── Verilog/
    ├── DELILAH-CPU/     # CPU gate array (ALU, microcode control, MMU access, interrupts)
    ├── DECODE-GateArray/# Instruction decoder gate array
    ├── CPU-BOARD-3202/  # The full 3202D board
    ├── PAL/             # PAL chips, converted from PALASM
    ├── Shared/          # TTL chips, memories, support logic
    ├── ND-BUS-DEVICES/  # Floppy, Winchester, tape and other bus devices
    ├── SD-FAT/          # SD card and FAT file system for the disc images
    ├── Terminals/       # TDV2200 terminal (screen + keyboard)
    ├── sim/  runSim/    # Verilator harnesses
    ├── tests/           # Test registry and instruction checks
    ├── docs/            # Design notes and analyses
    └── fpga/            # One folder per FPGA board
```

---

## 🚀 Quick Start

### Run it on a board (no tools needed)

1. Download the bitstream for your board from the
   [Releases page](https://github.com/RetroCoreLabs/nd-120/releases).
2. Follow the quickstart for your board:
   [Tang Nano 20K](Verilog/fpga/QUICKSTART-tang-nano-20k.md) ·
   [Nexys 4 DDR](Verilog/fpga/QUICKSTART-nexys4ddr.md) (incl. the SD-card-only path) ·
   [MiSTer](Verilog/fpga/QUICKSTART-mister.md) ·
   [MEGA65](Verilog/fpga/QUICKSTART-mega65.md) ·
   [QMTECH XC7A35T](Verilog/fpga/QUICKSTART-qmtech-a35t.md)

### Run it in the simulator

```bash
# Clone the repository
git clone https://github.com/RetroCoreLabs/nd-120.git
cd nd-120

# Waveform simulation: compiles, runs, and opens GTKWave
cd Verilog/sim
make clean
make all

# Full CPU: microcode load + self-test + OPCOM console
cd ../runSim
make clean
make compile
make run

# All self-checking test benches (fail-fast)
cd ..
make test
```

**Prerequisites:** [Verilator](https://www.veripool.org/verilator/), Icarus
Verilog, GTKWave (optional). Development is done on Linux / WSL2 with bash.

**Want the details?** See [BUILDING.md](BUILDING.md) for build, test and
troubleshooting steps.

---

## 🔧 FPGA Boards

Each board has its own folder of build scripts, pin files and notes under
[Verilog/fpga/](Verilog/fpga/README.md) - that page holds the full per-board
status and priority order.

| Board | Status | CPU clock | Main memory | Console | Disc images | Tools | Docs |
|-------|--------|-----------|-------------|---------|-------------|-------|------|
| **Tang Nano 20K** | ✅ Boots SINTRAN III - primary target | 20.25 MHz (`fast20`), timing-clean | 4 MB SDRAM | Serial, 115200 | SD card | OSS CAD Suite + Gowin EDA | [README](Verilog/fpga/tang-nano-20k/README.md) · [quickstart](Verilog/fpga/QUICKSTART-tang-nano-20k.md) |
| **Nexys 4 DDR** | ✅ Boots SINTRAN III | 33.333 MHz, cache on (7.52 MIPS) | DDR2 behind a BRAM cache | TDV2200 on VGA + USB keyboard, and serial | microSD - boots with no PC | Vivado | [README](Verilog/fpga/nexys4ddr/README.md) · [quickstart](Verilog/fpga/QUICKSTART-nexys4ddr.md) · [timing](Verilog/fpga/nexys4ddr/timing.md) |
| **MiSTer (DE10-Nano)** | ✅ Boots SINTRAN III | 20 MHz | 4 MB SDRAM module | TDV2200 on the MiSTer screen and keyboard | Picked in the OSD | Quartus | [README](Verilog/fpga/mister/README.md) · [quickstart](Verilog/fpga/QUICKSTART-mister.md) |
| **MEGA65** | 🚧 Built and timing-clean, not yet run on a MEGA65 | 13.33 MHz (R3) / 20 MHz (R4-R6) | 4 MB in HyperRAM (R3) / SDRAM (R4-R6) | TDV2200 on the MEGA65 keyboard and screen | SD card | Vivado | [README](Verilog/fpga/mega65/README.md) · [quickstart](Verilog/fpga/QUICKSTART-mega65.md) |
| **QMTECH XC7A35T** | 🚧 Built, timing met, not yet run | 20 MHz | 4 MB SDRAM | Serial | SD card (Pmod) | Vivado | [README](Verilog/fpga/qmtech-a35t/README.md) · [quickstart](Verilog/fpga/QUICKSTART-qmtech-a35t.md) |
| **Basys3** | ⚠️ Reaches OPCOM only - too little memory for the OS | - | 24K words BRAM | Serial | - | Vivado | [README](Verilog/fpga/basys3/README.md) |
| **Cmod A7-35T** | ⚠️ Misses timing, no bitstream - SRAM bridge planned | - | BRAM | - | - | Vivado | [README](Verilog/fpga/cmod-a7-35t/README.md) |

---

## 🧪 Simulation

Verilator is the **signal-level reference**: waveforms, unit test benches, and
the latch-versus-flip-flop comparison that proves a change altered nothing.

- ✅ **Microcode loads, Master Clear runs, and the CPU self-test passes clean:
  0 execution-phase STERR visits** (the `ND120_COUNT_STERR` probe in
  `Verilog/runSim/Run120.cpp`). An older "7 of 14 subtests" figure is retracted
  ([RETRACTED.md](Verilog/docs/RETRACTED.md)).
- ✅ **The self-test does not touch memory parity**, which is why the FPGA
  builds compute parity on read instead of storing it
  ([nd120-parity-analysis.md](Verilog/docs/nd120-parity-analysis.md)).
- ✅ **13 of 13 testable INSTRUCTION-B areas pass the automated gate:** the first
  400 instructions of each area match the ND-110 reference trace (`make
  test-instr`). RUN and 48-bit floating are not among the 13. Each area was
  also run by hand to its own end of test with zero error lines; those logs
  were not kept ([CAMPAIGN-STATUS.md](Verilog/tests/instruction-verify/CAMPAIGN-STATUS.md)).
- ✅ OPCOM console works; `INSTRUCTION-B` loads and runs from the Verilog paper
  tape device; DMA bus mastering works against the real arbiter.
- ✅ Golden-console and latch-vs-FF regression gates guard all of it.

```bash
cd Verilog
make test          # every self-checking test bench, fail-fast
make test-instr    # the INSTRUCTION-B trace gate
make test-full     # adds the heavy system gates
```

---

## 🔬 Original Diagnostics

These are the original Norsk Data test programs, not our own test benches.
Each row says where the result was measured.

| Program | Result | Measured on |
|---------|--------|-------------|
| **CONFIGURATION** | ✅ **Passes** with `NO ERRORS DETECTED`, and names the machine correctly (ND-120/CX, 32-bit float, MMS-2, cache, ALD 400B, print number 3202) | Verilator, Tang |
| **INSTRUCTION** | ✅ **Passes.** In Verilator, 13 of 13 testable areas pass the automated trace gate. On the board, the full run over interrupt **levels 1-9** passed clean (no log in the repository) | Verilator, Tang |
| **PAGING** | ✅ **Passes 11 of 11**, incl. test 3 (PGU/WIP), test 4 (alternative PIT) and test 11 (physical address generation) | Tang |
| **MEMORY** | ✅ **Passes.** The corrupted-banner fault was the cache data output not gated by `HIT` | Tang |
| **CACHE** (`CACHE-1X0-A00`) | ✅ **Passes all 8 tests**, incl. test 3 "Inhibit limits" | Nexys 4 DDR |
| **TPE Monitor B01** | ✅ Boots from a floppy image (`1560&` at the OPCOM `#` prompt) and reaches `TPE>` - the harness the diagnostics run from | Verilator, Tang |
| **RUN** | ⚠️ **Not proven.** Reached one area's `== END OF TEST ==` once (commit `3acef36`); no error count kept, and RUN is in neither `make test-instr` nor the test registry | Verilator |
| **48-BITS-FLOATING** | ➖ **Not applicable** - the PROM microcode is the 32-bit float version ([why](Verilog/docs/48bit-float-not-configured.md)) | - |
| **DISC-TEMA J02** | ❌ **Not passing.** Transfers real data off the disc image, matching the reference model register for register, but still reports `Memory address Register not as expected`. Unexplained - the one known open diagnostic | Verilator, Tang |

The five that pass clean on the board - **CONFIGURATION, INSTRUCTION, PAGING,
MEMORY and CACHE** - are the machine's own acceptance suite: the CPU names
itself correctly, runs every instruction group correctly, the MMU translates
and faults correctly, and main memory is sound.

**These programs found the real CPU bugs:**
- INSTRUCTION caught a multiply bug (every product's low word was zero) and a
  shift bug (all rotate and sign-extending shifts ran as plain shifts);
- PAGING caught an MMU fault where the physical-page map RAM was never written;
- CONFIGURATION caught a trap-vector fault that sent a page fault plus PGU to an
  unused vector, which then jumped to itself forever;
- CACHE needed four fixes, all single-input copying errors from the
  schematics: the PAL 44511A `CWR` feedback latch, that PAL's pin-19 polarity,
  a dropped Am9150 used-bit write, and a DGA `EPANS` data-window leak.

---

## 📊 What the Cache Is Worth

Measured on the Nexys 4 DDR with the operator panel's own MIPS counter, running
SINTRAN III. The cache is a build option (`cache` / `nocache`,
`ND120_NO_CACHE` - see [build-defines.md](Verilog/docs/build-defines.md)).

| Build | CPU clock | Cache | MIPS running SINTRAN | Clocks per instruction |
|-------|-----------|-------|----------------------|------------------------|
| 15 | 45.45 MHz | off | 2.44 | 18.6 |
| 16 | 33.33 MHz | **on** | **> 7.0** | **< 4.8** |

**The cache gives about 2.9x the throughput - on a clock 26% slower.** This
machine is limited by memory speed, not by the clock: with the cache off, every
instruction fetch is a DDR2 read, and DDR2 does not get faster when the CPU
clock rises. A one-word loop (`124000`, a `JMP` to itself) took **17.1 clocks
per instruction** uncached at both 45.45 and 33.33 MHz.

⚠️ **A warning that cost a day:** once the opposite was concluded and the
cache was dropped for speed. The MIPS counter was then counting memory cycles,
so it went blind exactly when the cache started working. Only after it was moved
to a true per-instruction event did the 3x difference show. Prove an instrument
before trusting it.

With the cache in, the routed worst path is 28.039 ns - a ceiling near
**35.6 MHz**. That one path (`WRF -> ALU -> TVGEN -> ACAL -> WCS` address) is
the most valuable thing to speed up on the board:
[timing.md](Verilog/fpga/nexys4ddr/timing.md).

---

## ⚙️ Inside the Machine

### Microcode

The [microcode](Code/Microcode/readme.md) comes from an ND-120 3202 CPU board, version 14/L. 

The repository has the PROM images, the microcode sources (`.uc`) and the listings for versions K and L.

### Panel controller - MC68705

The ND-120/CX CPU board has an on-board **MC68705-U3** CPU. The front panel has
an **MC68705-P3** - a smaller chip with fewer I/O pins
([Motorola 68HC05 family](https://en.wikipedia.org/wiki/Motorola_68HC05)).

- P3 version = 28 pins, 2x 8-bit I/O ports, 1x 4-bit I/O port
- U3 version = 40 pins, 4x 8-bit I/O ports

We have ROM dumps from both the U3 (from the 3202D CPU board) and the P3 (from
an ND-5000C panel controller), taken apart with
[GHIDRA](https://ghidra-sre.org/): [ROM dumps and analysis](Code/68705/readme.md).

### Logisim

The schematics are in the [Logisim folder](Logisim/readme.md), drawn with
[Logisim-Evolution 3.8.0](https://github.com/logisim-evolution/logisim-evolution/releases/tag/v3.8.0).

### Verilog

Most Verilog files were first made from the Logisim drawings with the
Logisim-Evolution FPGA tools. They are **no longer regenerated** - the Verilog
and the schematics are both kept by hand now, so a fix has to be made in both
places. All Verilog is in the [Verilog folder](Verilog/readme.md).

---

## 📚 Documentation

Paths in this repository are always relative to the repository root. Where a
document points at one of the *other* ND repositories, it writes
`$ND_REPOS/<repo>/...` - set `ND_REPOS` to the folder that holds your ND
checkouts.

### Primary Documentation

| Document | Description |
|----------|-------------|
| [README.md](README.md) | This file - overview and quick start |
| [BUILDING.md](BUILDING.md) | Build, test and troubleshooting |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Architecture, coding rules and how to contribute |
| [HARDWARE.md](HARDWARE.md) | Hardware details, part by part |
| [HISTORY.md](HISTORY.md) | Project history, milestone by milestone |
| [Verilog/TODO.md](Verilog/TODO.md) | Open work |

### Technical Reference

| Topic | Documentation |
|-------|---------------|
| **FPGA boards** | [Verilog/fpga/README.md](Verilog/fpga/README.md) |
| **Build options** | [Verilog/docs/build-defines.md](Verilog/docs/build-defines.md) |
| **Design notes** | [Verilog/docs/README.md](Verilog/docs/README.md) |
| **Design documents** | [DesignDocuments/Readme.md](DesignDocuments/Readme.md) |
| **Norsk Data manuals** | [NorskData-Doc/Readme.md](NorskData-Doc/Readme.md) - functional description, instruction set, microprogramming guide |

---

## 📊 Project Status

### ✅ Complete & Working

| Area | Status |
|------|--------|
| CPU, decoder, board and PAL chips in Verilog | ✅ Boots SINTRAN III |
| Tang Nano 20K, Nexys 4 DDR, MiSTer | ✅ Boot SINTRAN III from an SD card |
| CPU self-test | ✅ 0 errors |
| Original diagnostics | ✅ CONFIGURATION, INSTRUCTION, PAGING, MEMORY, CACHE pass on the board |
| Cache | ✅ ~2.9x throughput on the Nexys |

### 🚧 In Progress

- MEGA65 and QMTECH: first runs on real boards
- DISC-TEMA J02: the `Memory address Register not as expected` fault
- RUN: a proven clean run, and a gate that keeps it that way
- SD-card write workloads at full speed

### 🎯 Future Goals

1. Cache and a fast clock together on the Nexys (~9.5 MIPS if the 28 ns path can be cut)
2. The Cmod A7 SRAM bridge, so a small Xilinx board can run the OS

The live task list is [Verilog/TODO.md](Verilog/TODO.md).

---

## 📜 License

[MIT](LICENSE) for the Verilog, Logisim and tools in this repository. The
original design documents and manuals are Norsk Data material, kept here for
preservation.

---

## 🙏 Acknowledgments

- **Lasse Bockelie** - provided the original 1988 design documents
- **Matthieu Benoit** - read the ROM data out of the MC68705 chips
- **NDWiki community** - ND-120 documentation
- **GHIDRA team** - reverse engineering tools

---

## 🔗 Related Projects

- **[NDWiki](https://www.ndwiki.org/)** - everything Norsk Data
- **[Logisim-Evolution](https://github.com/logisim-evolution/logisim-evolution)** - the schematic tool used here
- **[MiSTer2MEGA65](https://github.com/sy2002/MiSTer2MEGA65)** - the framework behind the MEGA65 port

---

## 📞 Contact

- **GitHub Issues:** [github.com/RetroCoreLabs/nd-120/issues](https://github.com/RetroCoreLabs/nd-120/issues)

---

**Historical note:** a 1988 minicomputer CPU card, rebuilt from its own design
documents, running its own operating system on a hobby FPGA board.

**Start exploring:** [Quick Start](#-quick-start) | [FPGA Boards](#-fpga-boards) | [Documentation](#-documentation)
