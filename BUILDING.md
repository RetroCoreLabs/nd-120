# Building and Testing ND-120

This document provides instructions for building, testing, and running the ND-120
CPU implementation.

All paths below are relative to the repository root.

## Prerequisites

### Required Tools

#### Verilator
Install [Verilator](https://www.veripool.org/verilator/) for Verilog simulation
and testing. `verilator` must be on your `PATH`.

#### Icarus Verilog
The unit testbenches (`*_tb.v`) are run with `iverilog`.

#### GNU Make and a C++ compiler
Needed for the Verilator harnesses.

#### Logisim-Evolution (Optional)
For viewing and modifying the original schematics:
- Install [Logisim-Evolution](https://github.com/logisim-evolution/logisim-evolution)
- Tested with [Version 3.8.0](https://github.com/logisim-evolution/logisim-evolution/releases/tag/v3.8.0)

Note: the Verilog is no longer regenerated from Logisim. The schematics and the
Verilog are both maintained by hand, so a fix must be applied to both.

#### GTKWave (Optional)
For viewing simulation waveforms:
- Install [GTKWave](https://gtkwave.sourceforge.net/)
- The sim harness writes FST directly, which GTKWave opens far faster than VCD

### System Requirements

Development is done on **Linux / WSL2 with bash**. The exceptions are the
vendor FPGA tools (Vivado, Gowin EDA), which run on a Windows host and are
driven by the `.ps1` / `.tcl` scripts under `Verilog/fpga/<board>/`.

After cloning, run `python3 configure.py` at the repository root (`py
configure.py` from a Windows shell) once: it finds the tools, makes the
microcode preload images and writes `local.mk`, which every build reads. See
[CONTRIBUTING.md - Local settings](CONTRIBUTING.md#local-settings).

## Building the Project

### Quick Start

```bash
# Waveform / signal-level simulation
cd Verilog/sim
make clean
make all            # compile, run, open GTKWave (waveform.fst + top_3202d.gtkw)
```

### Build Targets

#### Signal-level simulation (`Verilog/sim`)

Exercises `ND120_TOP` and writes FST waveforms.

```bash
cd Verilog/sim
make clean            # remove build artifacts
make test_nd120       # compile only
make run              # run only
make gtk              # open GTKWave with the saved signal groups
make all              # compile, run and view
```

#### Full CPU system with microcode (`Verilog/runSim`)

Runs the microcode load and the CPU self-test, then hands the console to OPCOM
over the UART so you can interact with the CPU.

```bash
cd Verilog/runSim
make clean
make compile
make run
```

#### Latch mode versus flip-flop mode

`USE_LATCHES` (default `1`) selects transparent latches, which match the
original hardware. `USE_LATCHES=0` adds `FPGA_FF_MODE` and builds edge-triggered
flip-flops instead, which is what the FPGA needs.

```bash
cd Verilog/sim
make compile USE_LATCHES=0   # build in FF mode
make compare                 # build both, run both, diff trace_latch.csv vs trace_ff.csv
```

`make compare` writes `trace_diff.txt`. An empty diff is the proof that a
refactor left behaviour unchanged.

#### Individual component testing

Testbenches live in a `sim/` directory next to the module they test.

```bash
cd Verilog/PAL/sim
make clean
make all

cd Verilog/DELILAH-CPU/CGA_ALU/sim
make clean
make all
```

#### The whole test suite

```bash
cd Verilog
make test        # every self-checking unit testbench, fail-fast
make test-full   # adds the heavy gates: latch-vs-FF golden trace compare,
                 # runSim golden console, Tang boot + deposit
make test-instr  # the INSTRUCTION-B instruction-verification campaign
```

The registry is `Verilog/tests/run_all_tests.sh`. Every new testbench must be
added there with a strict pass pattern (the convention is to print
`TB_RESULT: PASS`), because a test that can pass silently can fail silently.

## Build Configuration

### Compile-time defines

| Define | Meaning |
|--------|---------|
| `VERILATOR_SIM` | Set for all Verilator builds. Enables the bus ports, the fast UART and the large simulation RAM (6MB). Absent for FPGA synthesis, which uses a small BRAM-friendly RAM. Selected in `MEM_RAM_49.v`. |
| `FPGA_FF_MODE` | Forces edge-triggered flip-flops instead of transparent latches. Added by the Makefiles when `USE_LATCHES=0`. |

See `Verilog/docs/build-defines.md` for the full list.

### Verilator flags

The build system suppresses a fixed set of warnings; the current list lives in
the Makefiles, for example:

```makefile
SUPPRESS_FLAGS = -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY -Wno-UNUSED -Wno-UNDRIVEN -Wno-WIDTH -Wno-EOFNEWLINE -Wno-LATCH
```

### Include paths

The build automatically includes:
- `Verilog/Shared/logisim` - Logisim-generated components
- `Verilog/Shared/ndlib` - ND-120 specific libraries
- `Verilog/Shared/support` - support circuits
- `Verilog/CPU-BOARD-3202/circuit` - CPU board modules
- `Verilog/DELILAH-CPU/` - CGA submodules
- `Verilog/DECODE-GateArray/` - DGA modules
- `Verilog/PAL` - PAL chip implementations

## Testing

### Simulation output

- **Console output**: CPU state, microcode execution, UART traffic
- **FST waveforms**: complete signal traces for GTKWave
- **CSV traces**: microcode address and CSA traces for automated comparison

Keep every log, trace, FST and CSV under 1GB. Window or bound long runs instead
of dumping everything.

### Boot sequence

1. **Microcode load**: 64KB control store, low half plus high half
2. **Master Clear**: CPU initialisation
3. **MACL**: microcode-level initialisation
4. **Self-test**: the CPU's own test sequence
5. **OPCOM**: operator communication over the UART

### Expected results

```
Microcode loading: OK
Master Clear: OK
MACL execution: OK
CPU self-test: 0 execution-phase STERR visits
UART communication: working
```

The self-test acceptance gate is the count of execution-phase STERR visits,
measured with the `ND120_COUNT_STERR` probe. Zero is the pass condition. Note
that the control-store loader walks past the STERR address once while loading -
that visit does not count.

### Waveform analysis

```bash
cd Verilog/sim
make gtk
```

GTKWave opens with the pre-configured signal groups in `top_3202d.gtkw`. See
`Verilog/sim/VCD_ANALYSIS_GUIDE.md` and `Verilog/sim/FPGA_DEBUG_RUNBOOK.md`.

### Debugging

1. **Check build output**: Verilator compilation warnings and errors
2. **Console logs**: CPU execution traces and error messages
3. **Waveforms**: signal-level debugging in GTKWave
4. **Component tests**: run individual module tests to isolate the failure

#### Common issues

- **Stale `obj_dir`**: changing a `-D` define without cleaning silently reuses
  the old build. Run `make clean` when you change build flags.
- **One build at a time**: never run two Verilator builds or simulations
  concurrently in the same directory; concurrent `obj_dir` writes corrupt it.
- **Clock timing**: check MCLK and UCLK in the waveforms
- **Microcode**: make sure the ROM hex files are present, or the control store
  is empty and nothing runs

## FPGA build

Every board has its own folder under `Verilog/fpga/<board>/` with its build
script, constraints and README. The board list, which boards boot SINTRAN,
their clocks and limits are in `Verilog/fpga/README.md`; ready-built
bitstreams and per-board quickstarts are on the Releases page it links to.

Two notes that apply across boards:

- **Every board** writes all of its output - bitstream, reports, logs,
  Vivado's `.Xil` - to `$ND120_BUILD_DIR/<board>/`, the build folder set by
  `configure.py`; nothing lands in the checkout. `make fresh-build
  ND120_FRESH_DIR=<empty folder>` in a board folder clones the current commit
  there and builds it, to prove the build needs nothing outside the
  repository.
- **Vivado boards** (Basys3, Cmod A7, Nexys 4 DDR, QMTECH, MEGA65) build on the
  Windows host from each folder's `.tcl` / `.ps1` script. The microcode hex
  files must be where the build expects them or the ROM is empty -
  `configure.py` makes them (`Code/Microcode/gen_wcs_image.py`).
- **Tang Nano 20K** has two flows. `make` in `Verilog/fpga/tang-nano-20k/` runs
  the open-source flow (yosys + nextpnr-himbaechel + gowin_pack), which its
  Makefile names as primary; `make gowin` / `gowin_build.ps1` runs Gowin EDA.
  The `fast20` variant that boots SINTRAN at 20.25 MHz is built with Gowin
  EDA only. Power-cycle the board after every programming operation.
  Never run two Gowin builds into the same build directory at once - one
  bitstream was a mix of both.

## Troubleshooting

### Build errors

```bash
make clean
# check that verilator and iverilog are on PATH
# check that a C++ compiler is available
```

### Simulation errors

- Check that the microcode ROM hex files are present
- Verify all Verilog module dependencies
- Read the console output for the specific error
- Use GTKWave to find the signal timing problem

## Advanced Usage

### Custom test programs

Test programs are loaded in BPUN format through the papertape device. Place the
binary in `Verilog/runSim/` and select it there.

### Signal tracing

Customise tracing by editing the GTKWave save files:
- `Verilog/sim/top_3202d.gtkw` - main CPU signals
- the per-component `.gtkw` files in each `sim/` directory
