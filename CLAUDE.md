# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a complete HDL implementation of the 1988 Norsk Data ND-120 CPU, recreated from original design documents and implemented in both Logisim-Evolution and Verilog. The goal is FPGA-synthesizable code that runs as the original ND-120 CPU. **SINTRAN III boots on the Tang Nano 20K (24-AUG-2026) and on the Nexys 4 DDR (25-AUG-2026)** - the Tang is the primary target. Clocked up 26-AUG-2026: the Nexys runs deployed at **45.45 MHz with a 115200 console** (50 MHz also booted; search + bottlenecks in `Verilog/fpga/nexys4ddr/timing.md`), the Tang boots the timing-clean `fast20` variant at **20.25 MHz with a 115200 console** (boot record: `Verilog/fpga/nexys4ddr/SINTRAN-BOOT-25AUG.md`). **Soaked 27-AUG-2026: both fast configurations ran SINTRAN for 4 unattended hours, 8/8 console probes each** - SD-card WRITE workloads at speed remain the one unproven item. Verilator remains the signal-level reference for unit checks and waveform work. The Basys3 `xc7a35t` synthesizes but does not meet timing and does not boot.

## Environment

- Work is driven from **Linux / WSL2 with bash**. Refer to files by **repo-root-relative paths** (e.g. `Verilog/readme.md`, `Verilog/sim/Makefile`) — do not use drive letters or absolute root paths. The older docs that say to use PowerShell/`cd E:\path` are stale.
- **Vivado runs on the Windows host** (invoked via `.ps1`/`.tcl`), so the Vivado scripts hard-code Windows host paths internally. That is expected and confined to those TCL scripts — don't replicate that style elsewhere.
- The `nd120-fpga` skill contains detailed, current guidance for FPGA debugging, VCD/waveform analysis, Verilator-vs-Vivado comparison, and latch→FF refactoring. Prefer it for those tasks.

## Architecture

Major functional blocks:

- **DELILAH CPU Gate Array (CGA)** — main CPU: ALU, microcode controller (MIC), memory access controller (MAC), interrupt controller (INTR), trap handler (TRAP), IDB control, write register file (WRF). Submodules live under `Verilog/DELILAH-CPU/CGA_*/circuit/`.
- **Decoder Gate Array (DGA)** — instruction decode (`Verilog/DECODE-GateArray/`).
- **CPU Board 3202D** — full board: memory management/MMU, memory, I/O, support TTL chips (`Verilog/CPU-BOARD-3202/`).
- **PAL chips** — hand-converted from PALASM to Verilog (`Verilog/PAL/`).
- **Shared** — reusable TTL logic, memory modules, support circuits (`Verilog/Shared/`).
- **Top level** — `Verilog/ND120_TOP.v` wires the board, exposes the FPGA pin interface (Basys3 LEDs / 7-seg), and gates sim-vs-FPGA behavior with `ifdef`.

Design flow: **Logisim-Evolution schematics are the source** for most generated Verilog; hand-written modules fill the gaps. Keep new code compatible with the Logisim-generated structure.

### Compile-time build modes

Three defines control behavior; understanding them is essential:

- `VERILATOR_SIM` — set for **all** Verilator sim builds. Enables bus ports, fast UART, and large sim RAM (6MB, `ramSize=2`). Absent for FPGA synthesis, which uses tiny BRAM-friendly RAM (24KB, `ramSize=3`) — the `xc7a35t` only has 100 RAMB18 blocks. Selected automatically in `MEM_RAM_49.v`.
- `FPGA_FF_MODE` — forces edge-triggered flip-flop behavior instead of the original transparent-latch behavior. Added by the Makefiles when `USE_LATCHES=0`.
- `USE_LATCHES` (Makefile var, default `1` in `sim/`, `0` in `runSim/`) — `1` = transparent latches (matches original hardware), `0` = FF mode (what the FPGA needs). This latch-vs-FF split is the crux of the FPGA boot divergence work.

The full reference for EVERY build option — all Verilog defines, sim make variables (`CACHE`, `PANEL_CLOCK`, `PACK16`, `SD_STORAGE`, …), Nexys `build.tcl` args + clock table, Tang `gowin_build.ps1`/OSS-make switches, Basys3 flags, and the runSim runtime env-var probes — is `Verilog/docs/build-defines.md`. Look there before adding or renaming any option, and keep it updated when one changes.

## Development Commands

### Verilator simulation

Two harnesses under `Verilog/`:

- `sim/` — exercises `ND120_TOP`, writes FST waveforms for GTKWave inspection (`test_nd120.cpp`).
- `runSim/` — runs the full microcode load + CPU self-test, then enables OPCOM (UART) for CPU interaction (`Run120.cpp`).

```bash
# Waveform / signal-level sim (paths relative to repo root)
cd Verilog/sim
make clean
make all               # compile, run, open GTKWave (waveform.fst + top_3202d.gtkw)
make test_nd120        # compile only
make run               # run only
make compile USE_LATCHES=0   # build in FPGA FF mode instead of latch mode

# Full CPU sim (microcode load + self-test + OPCOM)
cd Verilog/runSim
make clean
make compile
make run
```

**Latch vs FF divergence check** (in `sim/`): `make compare` builds both modes, runs each, and diffs the traces (`trace_latch.csv` vs `trace_ff.csv`) → `trace_diff.txt`. Use this to prove a refactor kept behavior identical.

### Testbench conventions

Testbenches live in a `sim/` directory **next to the module** they test — no central test tree.

```
<component>/circuit/module.v      ← source
<component>/sim/Makefile          ← build & run targets
<component>/sim/module_tb.v       ← iverilog testbench   (*_tb.v)
<component>/sim/test_module.cpp   ← Verilator testbench  (test_*.cpp)
<component>/sim/*.gtkw            ← GTKWave configs
```

- **iverilog** (`*_tb.v`) — fast unit tests, race/timing checks. Run via `make test-*` in that `sim/`.
- **Verilator** (`test_*.cpp`) — full-module sim with C++ harness + waveforms. Run via `make all`.
- `Verilog/tests/vivado_warning_fixes/` is **legacy**; new testbenches go in the module's own `sim/`.

**Global test suite** (from `Verilog/`): `make test` runs every self-checking
unit testbench, fail-fast — the first failure aborts loudly with exit 1.
Green end to end since 27-AUG-2026: **328/328 in ~34 min** after the backlog
burn-down (101 unregistered -> 0 unmeasured; 5 evaluated stragglers live in
`tests/tb_catalog.py` ORPHAN_BASELINE, each with its reason and its
register-or-retire condition — that reasoned-baseline convention is the ONLY
acceptable way to leave a testbench out). CI: `.github/workflows/verilog-ci.yml`
runs the registry + the Tang yosys netlist gates on every push/PR, and builds
the Tang OSS bitstream as an artifact on `bitstreams-*` release tags —
Vivado/Gowin stay local-only.
`make test-full` adds the heavy system gates (latch-vs-FF golden trace compare,
runSim golden console, Tang vtest boot+deposit). The registry lives in
`Verilog/tests/run_all_tests.sh`: **every new testbench must be added there**
with a strict pass pattern (`TB_RESULT: PASS` convention preferred), and every
tb must print a machine-checkable verdict — a test that can pass silently can
fail silently.

### FPGA build (Vivado, on Windows host)

FPGA build/flow files are under `Verilog/fpga/<board>/` (Basys3 = `fpga/basys3/`,
Tang Nano 20K = `fpga/tang-nano-20k/`). See `Verilog/fpga/README.md`.

```
# from Verilog/fpga/basys3/ :
vivado -mode batch -source vivado_build.tcl -tclargs [flags...]
# or: .\vivado_build.ps1   (copies microcode hex, then runs the tcl)
```

Key `vivado_build.tcl` flags: `full_synth` (required for a ~1h full re-synth; otherwise the existing `synth_1` checkpoint is reused), `skip_program`, `no_reset_synth`, `backup_bit`. `vivado_lint.tcl` runs lint only. Part: `xc7a35tcpg236-1`. Microcode `AM27256_4513{2,3}L.hex` must be present or the ROM is empty. Tang Nano 20K (Gowin) build is in progress — see `Verilog/docs/tang-nano-20k-port.md`.

### Code quality

**Always compile before reporting success.** Never create standalone test programs — use the existing sim/ infrastructure. No linter is configured; Verilator warnings (see the `-Wno-*` suppression list in the Makefiles) and `vivado_lint.tcl` are the quality gates.

## Toolchain traps (measured, each cost real time - do not relearn them)

- **git log --follow is unusable here** (>2 min on the /mnt/e checkout,
  times out): use a plain pathspec with globs ('*NAME.md' finds moved
  files) or `git log -S`.
- **A root-only pathspec proves nothing about existence** - the
  DEVELOPMENT.md/HARDWARE.md files "never existed" for two compactions
  because the search skipped subdirectories. `make docs-check` (the
  dead-link gate) now guards the README side of this.
- **Windows env vars do not reach Vivado launched through WSL interop**
  unless named in WSLENV. Licence variables especially.
- **Vivado runs go in background tasks** (they exceed the 2-minute
  foreground limit) and failure-grep must anchor `^ERROR:` - Vivado
  echoes sourced script text, so an unanchored ERROR pattern matches the
  build script's own puts lines.
- **Every command chain uses absolute paths** - the shell's working
  directory does not reliably persist between calls, and a failed `cd`
  silently eats the rest of a && chain (this destroyed commits).
- **Canonical build commands**: Nexys 4 DDR = `Verilog/fpga/nexys4ddr/build.tcl`
  (via powershell, see its header; build-watch.ps1 wraps it), Basys3 =
  `Verilog/fpga/basys3/vivado_build.ps1`, Tang = `Verilog/fpga/tang-nano-20k/gowin_build.ps1`
  or the OSS `make` in that folder.
- **Board power-cycle detaches USB from WSL** - after asking for one, run
  the board's `usb-attach.sh` before declaring the console ready.
- **git update-index --chmod stages file CONTENT too**, not just the mode
  - it once swallowed another session's uncommitted edits. Stage
  explicitly, never broadly, when other sessions share the tree.
- **Committed files must carry the executable bit and exact casing** -
  the Windows-drive checkout shows every file as rwx and case-insensitive;
  the Linux CI runner does not (14 CI rounds of exactly this, 27/28-AUG).
- **Never reference Claude, CLAUDE.md or any AI tool in committed files
  or commit messages**, and **never use `git checkout --` / `git restore`
  on tracked files without explicit permission** - both are standing
  rules that must survive compaction.

## Conventions

- Internal signals use the `s_` prefix.
- Bus signals follow `BUSNAME_BITS` (e.g. `CD_15_0`, `FIDB_15_0`); active-low control signals use the `_n` suffix.
- Comments follow the existing header format (component name, design-doc page references, review dates).
- Tri-state note: inside the FPGA, `z` does not work — "3-state" buffers must drive `0` when disabled, not `z` (see `TTL_74245/244/241`, `AM29841`, `AM29861A`).
- Never use LINQ in any code additions.

## Status & known issues

> Last verified: 26-AUG-2026. State only what is measured here — this section
> is what other people (and other agents) read first, so stale claims here
> propagate as fact.

**Verilator (the working reference)**

- Microcode load + Master Clear run; OPCOM UART works.
- **CPU self-test passes clean: 0 execution-phase STERR visits.** (The old
  "7 of 14" claim was stale; measured with the `ND120_COUNT_STERR` probe in
  `runSim/Run120.cpp`. Careful: the WCS loader walks past the STERR address
  once during loading — only execution-phase visits count.)
- **Instruction validation: 13 of 13 testable INSTRUCTION-B areas pass**, on
  both layers (each area's own `== END OF TEST ==` with zero error lines, and
  the 400-instruction golden-trace gate vs the ND-110 reference). Matrix:
  `Verilog/tests/instruction-verify/CAMPAIGN-STATUS.md`; run with
  `make test-instr`.
  - `48-BITS-FLOATING` is **N/A**: our PROM microcode implements the 32-bit
    float option (`Verilog/docs/48bit-float-not-configured.md`).
  - `RUN` is the one area that does **not** fully pass yet, but the level-14
    **livelock is FIXED** (14-JUL). The interrupt controller's Am2914 status
    fence (READ VECTOR auto-loads vector+1 into the status register) was never
    wired correctly; it is now the **RTL default** (escape hatch:
    `ND120_INTR_STATUS_FENCE_OFF`). Validated fence-ON in FF mode: self-test 0
    STERR, unit suite 48/48, all 13 instruction-verify areas, and the sim/
    latch-vs-FF golden traces byte-identical. Ground-truth confirmed against
    the C# DELILAH-L PIC trace
    (`$ND_REPOS/ND110Compile/traces/PIC-TRACE-RUN-ND120.md`):
    vector+1 loads on the winning chip only, per-group DCDF (HIF/LOF) qualifies
    it. The follow-on `IIC: 11 - Memory Out of Range` misreport was a THIRD
    transcription bug — `CGA_INTR_CNTLR.v` swapped FIDBO bits 1<->2 on the
    status-fence LDSTAT path, decoding an IOX error as MOR — fixed straight
    through (commit `3acef36`); RUN now reaches its END OF TEST. MOR itself is
    **wired** (same commit): `CGA_INTR.v:117` connects `MORN` by default (the
    old tie-off survives only behind `ND120_MOR_TIED_OFF`, defined by no
    build); source chain is bus-timeout (`DECODE_DGA_POW.v`) split MEM/IO in
    `BIF_BCTL_BDRV_7.v` -> level 12. See
    `Verilog/docs/HANDOFF-mor-level12-wiring.md` and
    `Verilog/docs/RUN-level14-livelock-analysis.md`.
- Unit suite green (`make test`); the registry grew from ~48 to 150+ entries
  in the 27-AUG backlog burn-down (101 unregistered testbenches -> 5, every
  addition proven passing). The old "pre-existing test-memchain failure" is
  RESOLVED: it was the SIM variant's stale expectation of pre-11-AUG parity
  behavior - tb fixed, all four memchain variants pass and are registered.
- CPU bugs found and fixed by the campaign (both were single-input
  transcription errors from the schematics, both have Logisim regeneration
  hazards listed in `Verilog/TODO.md`): `CGA_ALU_QREG` (every MPY product's
  low word was 0) and `CGA_CPU_ALU_CONTR` (all ROT/ZIN-right/LIN shifts ran as
  plain shifts).

**FPGA**

- **SINTRAN III boots on the Tang Nano 20K (24-AUG-2026).** The last blocker
  was the memory bank being decoded from the wrong side of the bus
  transceiver (`ND3202D.v:533`): on an incoming DMA write the board drives
  nothing, that net idles all-ones, so every transfer decoded to BANK0. Disc
  data landed at the right ROW in the wrong BANK, the CPU fetched zeros from
  a page nothing had written, executed them as STZ and halted in ERRFATAL
  after exactly 143 s on every boot. Guarded by `make test-bdbank`; that
  class of fault is invisible in Verilator, whose memory model has all three
  banks present.
- Also proven on real silicon (Tang Nano 20K): the SDRAM controller, and the
  SD/FAT stack incl. 4-bit-bus transfers.
- **Clock:** 6.75 MHz is the long-validated speed. A 13.5 MHz variant
  (`-Variant mid`) closes with 0 setup violations. **NEW 26-AUG-2026:
  `-Variant fast20` boots SINTRAN at 20.25 MHz with a 115200 console,
  TIMING-CLEAN (TNS 0)** - the fastest clean Tang. **UPDATED 31-AUG-2026:
  its margin is now 13.2%, Fmax 22.932 MHz (was 20.556 MHz / 1.5%).** The
  old figure was not a property of the CPU: `nd120_tang20k.sdc` was one
  `create_clock` line, so the data buses crossing between `nd_storage`'s
  card side and its client side were analysed as synchronous with a
  required time of 0.000 ns - 24 of the 25 worst setup paths in the build.
  Two `set_false_path` lines took the CPU domain from -260.076 ns over 398
  endpoints to -6.489 ns over 24; with `aa210eb` taking the MIPS tap off
  `ALUCLK_EN`, TNS is now 0.000 on all five clocks, setup and hold. Details,
  and the traps (a WIDER exception set measured WORSE; Gowin leaves the
  previous `.tr` on disk when a build aborts):
  `Verilog/fpga/tang-nano-20k/README.md`. The `slow`/`mid`/`full` Fmax
  numbers still predate this and are pessimistic by an unmeasured amount.
  **27 MHz (`-Variant full`)
  runs SINTRAN, LIST-FILES and s3** and is visibly faster, but Gowin reports
  1667 setup violations against a CPU-domain Fmax of 17.7–19.6 MHz — fast and
  functional, but NOT timing-clean: margin over temperature and voltage is
  unquantified, so it is not a configuration to trust for long unattended
  runs or anything writing to the card.
  - Beware a false signal here: an s3 "hang" at 27 MHz was first read as
    corruption. It was not. **A slow first start and a quick second start is
    a caching effect** — first run loads from disc, second finds it resident —
    and the same apparent hang appears at 13.5 MHz. No comparative startup
    timing exists between the clock variants; each observation came from a
    different boot with a different cache state.
  - The `.sdc` is a single `create_clock` line with no multicycle on the known
    52 ns WCS→ACAL path, so the timing numbers are a floor, not a verdict.
    Writing a real `.sdc` is the route to a fast machine that is also
    defensible.

- **Panel clock (28-AUG-2026):** the MC68705/MM58274 hardware clock
  (TRR PANC / TRA PANS, PFUNC 4-7) is emulated by
  `Verilog/CPU-BOARD-3202/circuit/PANCAL_68705_CLOCK.v`, OPT-IN via
  `ND120_PANEL_CLOCK` (ON by default on both FPGA builds; disable with
  `-NoPanelClock` on both boards (`gowin_build.ps1 -NoPanelClock`,
  `build.tcl -tclargs -NoPanelClock`),
  sims `PANEL_CLOCK=1`) because the Tang is nearly full. Without it the panel
  is a stub and SINTRAN cannot set or read the time. Proven in Verilator with
  the TPE Monitor floppy (its start-up clock probe passes). Finding it exposed
  two UNCONDITIONAL DGA fixes: `TRA PANS` used to return 0 to A, and
  `TRR PANC` never reached the panel FIFO - so before 29-AUG-2026 no panel
  command of any kind (incl. the microcode's own ACTLV/0x0A traffic) ever
  left the CPU. Details and what is not modelled:
  `Verilog/docs/panel-clock-68705.md`.
- **MEGA65 (02-SEP-2026): the whole machine builds for both revisions on
  the MiSTer2MEGA65 framework (submodule `Verilog/fpga/mega65/m2m/`),
  timing-clean, NOT yet run on a MEGA65** - there is none here; the release
  cores go to testers. R6 (and R4/R5): 4 MB in the 64 MB SDRAM via the
  MiSTer sheet-49 bridge, CPU 20 MHz. R3: 4 MB in the 8 MiB HyperRAM via
  the Nexys `MEM_RAM_49_DDR2` cache seam + `nd_avalon_port.v`, CPU
  13.33 MHz (the R3 netlist times the CGA IDB ring through a longer
  loop-break, 57 ns; the period fits it rather than untiming the IDB).
  Console = `Verilog/Terminals/` on the framework's keyboard scan
  (`m65_keys_to_ps2.v`, keycap-faithful) and video; storage = the MiSTer
  `nd_storage_hps.v` logic on the framework's byte-wide vdrives
  (`nd_storage_vdrives.v`), fd0/fd1/wd0/wd1/tape. Toolchain traps that
  cost a build each: read the framework's `.v` as SystemVerilog,
  `auto_detect_xpm` before `synth_design`, the framework's
  `-through i_ascal/reset_na` false path matches nothing under 2026.1, the
  router's hold estimate sits ~70 ps above sign-off on the framework's
  `clk`. All in `Verilog/fpga/mega65/docs/00-plan.md` and `build.tcl`.
  ALSO FOUND THERE: microword 0o2002 exists in two variants - the raw PROM
  word and the 2024 run-simulator patch (`A,6` -> `A,0` in the
  master-clear wait loop's count: 64 passes -> 1, a 64x shorter power-on
  wait, nothing else). NOT a bug either way. **Decided 02-SEP-2026: boards
  preload the raw word (`gen_wcs_image.py` -> `Code/Microcode/wcs/`, and
  `Shared/support/` for the MiSTer), simulators run the patched word
  (`gen_wcs_image.py --sim` -> `wcs-sim/`, and their patched
  `AM27256_45133L.hex`).** `test-microcode-sync` enforces the split per
  directory. `Verilog/docs/nd120-facts.md`.
- Live task list: `Verilog/TODO.md`. Historical latch-refactor notes:
  `Verilog/verilog-remove-latch.md`, `Verilog/worklog-latch-refactor.md`.

## Files to reference

(paths relative to repo root)

- `README.md` — project overview and history
- `Verilog/readme.md` — Verilog implementation status, testbench + RAM-config details
- `Verilog/nd120-plan.md` — detailed CPU architecture
- `Verilog/TODO.md` — current issues and tasks
- `Verilog/boot-sequence.md`, `Verilog/sim/boot_analysis.md` — boot walkthrough
- `Verilog/sim/FPGA_DEBUG_RUNBOOK.md`, `Verilog/sim/VCD_ANALYSIS_GUIDE.md` — FPGA debug + VCD workflow
