# Development Guide

How work is done in this repository: where things live, the conventions the code
follows, and what to read before changing anything.

- Project history, milestone by milestone: [HISTORY.md](HISTORY.md)
- Hardware components and specifications: [HARDWARE.md](HARDWARE.md)
- Building, simulating and testing: [BUILDING.md](BUILDING.md)
- Microword field layout and CPU signal names: [Verilog/nd120-plan.md](Verilog/nd120-plan.md)
- Current issues and task list: [Verilog/TODO.md](Verilog/TODO.md)

## Where the code lives

| Area | Directory | Contents |
|------|-----------|----------|
| DELILAH CPU Gate Array (CGA) | `Verilog/DELILAH-CPU/` | ALU, MAC, MIC, INTR, TRAP, DCD, WRF, IDBCTL, TESTMUX |
| Decoder Gate Array (DGA) | `Verilog/DECODE-GateArray/` | Instruction decode, control store address generation |
| CPU Board 3202D | `Verilog/CPU-BOARD-3202/` | MMU, memory, I/O, bus interface, cycle control |
| PAL chips | `Verilog/PAL/` | PALASM converted to Verilog, one file per chip |
| Shared logic | `Verilog/Shared/` | 74-series TTL, memories, support circuits |
| ND-BUS devices | `Verilog/ND-BUS-DEVICES/` | Papertape, floppy DMA, SMD disc, tape |
| Board top levels | `Verilog/fpga/<board>/` | Constraints, build scripts, board documentation |
| Schematics | `Logisim/` | Logisim-Evolution drawings |

The functional description of each block is in [HARDWARE.md](HARDWARE.md); it is
not repeated here.

## Source of truth

The Logisim-Evolution schematics were the original source: most Verilog was
generated from them. **That generation no longer happens.** The Verilog and the
schematics are now both maintained by hand, which means:

- A fix has to be made in **both** places, or the two drift apart.
- A schematic sheet that is still wrong is a regeneration hazard: anyone who
  regenerates from it re-introduces the bug. Every such sheet is listed in
  `Verilog/TODO.md`.
- The original 1988 design documents in `DesignDocuments/` outrank both. Where
  the Verilog and the paper disagree, the paper wins until proven otherwise.

## Coding conventions

### Verilog

- **Internal signals** use the `s_` prefix.
- **Buses** follow `BUSNAME_BITS`, for example `CD_15_0`, `FIDB_15_0`.
- **Active-low signals** end in `_n`, for example `reset_n`, `MWRITE_n`.
- **One primary module per file**, with the directory structure mirroring the
  schematic hierarchy.
- **Tri-state does not exist inside an FPGA.** A "3-state" buffer must drive `0`
  when disabled, never `z`. See `TTL_74245`, `TTL_74244`, `TTL_74241`,
  `AM29841`, `AM29861A`.
- **No LINQ** in any C# added to the surrounding tooling.
- **No Unicode** in anything fed to the period C compiler or assembler - those
  tools are from the late 1980s.

### Module headers

Every module carries a header naming the component, the schematic page it comes
from, and when it was last reviewed:

```verilog
/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/ALU/QREG                                                         **
** Q REGISTER                                                            **
**                                                                       **
** Page 43                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 11-NOV-2024                                            **
** Ronny Hansen                                                          **
***************************************************************************/
```

### Paths

Files in this repository only ever use paths relative to the repository root.
No drive letters, no `/mnt/...`, no `/home/...` - in scripts, Makefiles, source,
tests or documents. A script finds the root from its own location. A file that
lives outside the repository is either copied in, or reached through an
environment variable (`$ND_REPOS/<repo>/...` for the sibling ND repositories).

### Build modes

Two defines change behaviour and have to be understood before touching timing:

- `VERILATOR_SIM` - set for every Verilator build. Enables the bus ports, the
  fast UART and the large simulation RAM. Absent for FPGA synthesis, which uses
  a small block-RAM-friendly memory.
- `FPGA_FF_MODE` - forces edge-triggered flip-flops instead of the original
  transparent latches. The Makefiles add it when `USE_LATCHES=0`.

The full list is in `Verilog/docs/build-defines.md`, and the build commands are
in [BUILDING.md](BUILDING.md).

Why the flip-flop mode is a fair copy of the latches (the reasoning from the
2026 latch-to-flip-flop migration, kept here when its plan was retired):

- A PAL16L8 has no clock; its self-referencing feedback terms act as latches
  through the AND-OR array. In the original board they settle within the PAL
  delay (about 25-35 ns), and the logic after them only reads their outputs on
  the next OSC edge (39.3 MHz, about 25 ns; the AM29C821 pipeline in
  `BIF_BCTL_SYNC_8` makes the *25/*50/*75 delayed copies on OSC edges). A
  flip-flop on `posedge OSC` therefore captures the same settled state.
- The real risk is not the clock but the rewrite: an OR of product terms
  becomes an if/else chain, which adds a priority the PAL never had. Each PAL's
  flip-flop logic has to be checked against its original equations. Example of
  such a check: PAL_44304E `EBADR_n_reg` was first flagged as wrong and then
  proved right by algebra (the clear term `!GNT_n & !IBAPR_n` already rules
  out the set term, so the order does not matter); `BACT_reg` likewise.
- There are no feedback loops between PALs that would need more than one OSC
  cycle to settle: PAL_44302B takes Q0_n/Q2_n from PAL_44401B, PAL_44303B takes
  BACT_n from PAL_44304E (both one way), and PAL_44304E and PAL_44401B take
  only delayed copies from the AM29C821 pipeline.
- `make compare` in `Verilog/sim` is the proof for a given change. At the end
  of the migration (29-MAR-2026, 1M cycles) the two modes differed only in the
  BDRY start-up value (cycles 0-2: the latch settles to 1, the flip-flop resets
  to 0) and the CSA shift that follows from it at cycle 16415.

## Testing

Testbenches live in a `sim/` directory **next to the module they test**. There is
no central test tree.

```
<component>/circuit/module.v      source
<component>/sim/Makefile          build and run targets
<component>/sim/module_tb.v       Icarus Verilog testbench
<component>/sim/test_module.cpp   Verilator testbench with C++ harness
<component>/sim/*.gtkw            GTKWave signal groups
```

- **Icarus Verilog** (`*_tb.v`) for fast unit tests and race checks.
- **Verilator** (`test_*.cpp`) for full-module simulation with waveforms.

Rules that keep the suite honest:

1. Every testbench must print a machine-checkable verdict; the convention is
   `TB_RESULT: PASS`. A test that can pass silently can fail silently.
2. Every new testbench must be registered in `Verilog/tests/run_all_tests.sh`
   with a strict pass pattern, or `make test` will not run it.
3. A behaviour-preserving refactor must be proven with the latch-versus-flip-flop
   golden trace comparison (`make compare` in `Verilog/sim`), not by inspection.

The acceptance gate for the CPU self-test is the count of execution-phase STERR
visits, which must be zero. Instruction-level correctness is measured by the
INSTRUCTION-B campaign in `Verilog/tests/instruction-verify/`.

## Working on this project

### Getting started

1. Read [README.md](README.md), then [BUILDING.md](BUILDING.md).
2. Get the Verilator simulation running before changing anything - it is the
   reference every change is judged against.
3. Run `make test` from `Verilog/` to see the current state of the unit suite.
4. Pick a component and read its schematic pages in `DesignDocuments/` alongside
   the Verilog.

### Workflow

1. Reproduce the problem in simulation first. The FPGA is slow to iterate on and
   hard to observe; Verilator is neither.
2. Make the change in the Verilog **and** the matching Logisim sheet.
3. Add or extend a testbench that fails before the fix and passes after it.
4. Run the unit suite, and the golden-trace comparison if timing was touched.
5. Only then build for the board.

### What tends to be wrong

Most bugs found so far have been **transcription errors** - a single wrong input
on a gate, copied by hand from a scanned 1988 schematic. They hide well: the
circuit looks right, simulates, and fails only in one instruction or one mode.
When something misbehaves, compare the Verilog against the original sheet gate
by gate before theorising about timing.

### Reporting a problem

1. Environment: build mode, defines, board or simulator.
2. Reproduction: the smallest command sequence that shows it.
3. Expected versus actual, with the console output or the trace.
4. Which reference says the expected behaviour is right.

## Reference material

### In this repository

- `DesignDocuments/` - the original 1988 schematics and specifications
- `NorskData-Doc/` - functional descriptions, instruction set, microprogramming
  guide
- `Code/Microcode/` - control store dumps and the microcode listing
- `Code/68705/` - panel controller ROM dumps and their analysis

### External

- [NDWiki](https://www.ndwiki.org/wiki/3202) - ND-120 documentation
- [Norsk Data historical site](http://sintran.com/)
- [Logisim-Evolution](https://github.com/logisim-evolution/logisim-evolution)
- [Verilator](https://www.veripool.org/verilator/)

### Acknowledgments

Lasse Bockelie provided the original 1988 design documentation. Matthieu Benoit
read the data out of the ROM chips. Reverse engineering of the panel controller
firmware was done with [GHIDRA](https://ghidra-sre.org/).
