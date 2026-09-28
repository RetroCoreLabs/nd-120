# ND-120 FPGA Debug Runbook

This document enables any AI assistant or engineer to reproduce the Verilator-vs-FPGA
comparison workflow from scratch. It is self-contained and does not assume prior context.

## Problem Statement

The ND-120 CPU boots correctly in Verilator simulation. On silicon it boots
SINTRAN III on the Tang Nano 20K (24-AUG-2026), the Nexys 4 DDR (25-AUG-2026)
and the MiSTer (02-SEP-2026); the Basys3 boots OPCOM only (its 24K-word memory
cannot hold an OS). Board state per target: `Verilog/fpga/README.md`.
The workflow below was written for the Basys3 during the 2026 bring-up and still
applies to any board whose behaviour differs from Verilator.
The Verilator VCD trace serves as the "golden reference". The FPGA behavior is captured via
Vivado ILA (Integrated Logic Analyzer) and exported as CSV. The goal is to find where the
FPGA diverges from the reference and fix the Verilog.

## Repository Layout

```
Verilog/
  sim/                          # Verilator simulation directory
    waveform.vcd                # ~500MB Verilator trace (golden reference)
    top_3202d.gtkw              # GTKWave session (1109 signals)
    vcd_extract.py              # Custom fast VCD parser (this project)
    boot_analysis.md            # Complete boot sequence reference
    VCD_ANALYSIS_GUIDE.md       # Tool usage and signal mapping
    FPGA_DEBUG_RUNBOOK.md       # THIS FILE
    FPGA_REFACTORING_GUIDE.md   # Sync-design conversion pattern (long-term fix)
    latch_ff_compare.cpp        # Regression testbench for before/after diff
  vivado_build.tcl              # Vivado build script (includes ILA probe setup)
  vivado_build.ps1              # PowerShell wrapper
  ND120_TOP.v                   # FPGA top module
  DELILAH-CPU/CGA/circuit/CGA.v           # CGA (DELILAH) - main CPU gate array
  DELILAH-CPU/CGA_ALU/circuit/CGA_ALU.v   # ALU module
  DELILAH-CPU/CGA_MIC/circuit/CGA_MIC.v   # Microcode instruction controller
  DELILAH-CPU/CGA_TRAP/circuit/CGA_TRAP.v # Trap/interrupt handler
  CPU-BOARD-3202/circuit/ND3202D.v        # CPU board top
```

## Module Hierarchy (for signal paths)

```
ND120_TOP
  CPU_BOARD  (ND3202D)
    CPU  (CPU_15)
      PROC  (CPU_PROC_32)
        CGA  (CPU_PROC_CGA_33)
          DELILAH  (CGA)
            ALU  (CGA_ALU)      <- Q register, F result, ZF, CRY
            MIC  (CGA_MIC)      <- COND, MA address generation
            TRAP (CGA_TRAP)     <- TRAP_n, TVEC
            WRF  (CGA_WRF)      <- Register file (R0-R7, A, B, D, etc.)
            DCD  (CGA_DCD)      <- Instruction decode
```

## Tools

### vcd_extract.py - Verilator VCD Parser

Custom streaming parser. Header parse: ~1s (vs 67s with vcdvcd library).
Handles Verilator signal aliasing (same short ID reused for connected wires).

Key commands:
```bash
cd Verilog/sim

# List all signals
python3 vcd_extract.py waveform.vcd --list

# Extract signals by substring match
python3 vcd_extract.py waveform.vcd -s "s_debug_mclk" "s_debug_lcs_n" --ticks --table

# Extract by exact hierarchical name
python3 vcd_extract.py waveform.vcd \
  -e "TOP.CSA_12_0" "TOP.ND120_TOP.s_debug_lcs_n" \
  --ticks --table

# Extract with time window (ps)
python3 vcd_extract.py waveform.vcd -e "TOP.CSA_12_0" --tstart 5730000 --tend 5760000 --ticks --table

# JSON output for programmatic analysis
python3 vcd_extract.py waveform.vcd -e "TOP.CSA_12_0" --tend 6000000 --ticks --json

# Summary of key signals
python3 vcd_extract.py waveform.vcd \
  -e "TOP.CSA_12_0" "TOP.ND120_TOP.s_debug_lcs_n" \
     "TOP.ND120_TOP.s_debug_cc_term" "TOP.ND120_TOP.s_debug_mclk" \
     "TOP.ND120_TOP.s_run" \
  --ticks --summary
```

Options: `-s` (substring), `-e` (exact name), `-p` (regex), `--tstart/--tend` (ps),
`--ticks` (show clockTick column), `--table/--json/--csv/--summary`, `--shortest` (prefer short alias).

clockTick formula: `tick = time_ps / 10 + 1`

### Vivado ILA Export

In Vivado Hardware Manager after capturing:
```tcl
write_hw_ila_data -csv_file -force <capture-dir>/ila_capture.csv [upload_hw_ila_data hw_ila_1]
```

## Signal Name Mapping

Vivado ILA uses hierarchical net paths. The Verilator VCD has both `s_debug_*` aliases
(defined in ND120_TOP.v with `mark_debug`) and the underlying internal signals.

| Purpose | Vivado ILA net path | VCD signal name |
|:--------|:-------------------|:----------------|
| Microcode address | `s_debug_csa[*]` | `TOP.CSA_12_0` |
| Load control store | `s_debug_lcs_n` | `TOP.ND120_TOP.s_debug_lcs_n` |
| Memory clock | `s_debug_mclk` | `TOP.ND120_TOP.s_debug_mclk` |
| Cycle FSM | `s_debug_cc_term[*]` | `TOP.ND120_TOP.s_debug_cc_term` |
| CPU run | `s_run` | `TOP.ND120_TOP.s_run` |
| UART TX | `s_debug_uartTx` | `TOP.ND120_TOP.s_debug_uartTx` |
| ALU Q register | `CPU_BOARD/.../ALU/s_q_15_0[*]` | `TOP.ND120_TOP...ALU.ALU_QREG.Q_15_0` |
| ALU F result | `CPU_BOARD/.../ALU/s_f_15_0[*]` | `TOP.ND120_TOP...ALU.ALU_RALU.F_15_0` |
| Zero flag | `CPU_BOARD/.../DELILAH/s_zf` | `TOP.ND120_TOP...DELILAH.ALU.ZF` |
| Carry | `CPU_BOARD/.../DELILAH/s_cry` | `TOP.ND120_TOP...DELILAH.ALU.CRY` |
| Condition | `CPU_BOARD/.../DELILAH/s_cond` | `TOP.ND120_TOP...DELILAH.MIC.COND` |
| FIDBO bus | `s_debug_fidbo[*]` | `TOP.ND120_TOP...DELILAH.s_FIDBO_15_0` |

Full hierarchy prefix: `CPU_BOARD/CPU/PROC/CGA/DELILAH/`

## Boot Sequence Reference (from Verilator - the correct behavior)

### Phase 1: Microcode Loading (tick 7 - 573,437)
- LCS_n = 0
- CSA counts sequentially 0x0000 to 0x1FFF (oct 0-17777, all 8192 addresses)
- ~68 ticks per address
- After 0x1FFF, LCS_n goes HIGH

### Phase 2: Initialization (tick 573,438+)
- First executed address: **0x0401** (oct 2001)
- 69 microcode instructions with subroutine calls
- Key jump pattern: 0x040F -> 0x0BB0 -> 0x0BB8 -> 0x0410
- Ends at 0x0424 which flows into the countdown loop

### Phase 3: ALU Countdown Loop (tick 573,799 - 754,018)
- CSA alternates 0x0425 / 0x0426 (oct 2025/2026)
- **16,384 iterations**
- Mechanism: Q loaded with 0x3FFF, F = A - Q each iteration, F counts up
- Exit when F = 0x0000 -> ZF = 1 -> COND = 1 -> exits to 0x0427

### Phase 4: Self-test (tick 754,018+)
- 0x0427 -> 0x07C8 -> 0x021D (utility calls)
- MACL test loop at 0x044E-0x0453 (16 iterations)
- UART output via 0x07B6 -> 0x01C2

### Phase 5: OPCOM fetch loop (tick ~776K+)
- Pattern: 0x0000 -> 0x0401 -> 0x1xxx -> 0x0000 -> 0x0C00 -> execute -> 0x0065 -> repeat

## Current FPGA Bug

**Symptom**: FPGA gets stuck in Phase 3 (0x0425/0x0426 loop), never reaches 0x0427.

**Root cause candidates** (in order of probability):
1. Q register not loaded with 0x3FFF at 0x0424
2. ALU F result not computing correctly (synthesis optimization broke combinatorial logic)
3. ZF (zero flag) not asserting when F = 0x0000
4. COND not propagating through CSEL condition latch (ALUCLK timing)
5. Condition not reaching MASEL address mux (SC5/SC6 control)

**Deeper systemic cause**: The design uses combinational signals (ALUCLK, MACLK, UCLK, MCLK,
PAL outputs) as clock sources via `always @(posedge some_signal)`. This works in original
TTL hardware because of physical propagation delays, but is nondeterministic in Verilator
and invalid on FPGA. See `FPGA_REFACTORING_GUIDE.md` for the synchronous conversion pattern
(sample derived "clocks" as data on sysclk, use edge detection to generate single-cycle
enables). This is the long-term fix; the ALU loop bug above is one symptom of it.

## How to Add ILA Probes

**DO NOT thread debug signals through module ports.** Instead:

1. Add `(* mark_debug = "true", DONT_TOUCH = "true" *)` directly on the `wire` declaration
   inside the submodule source file (e.g., CGA_ALU.v, CGA.v)

2. Add a probe entry in `vivado_build.tcl` using the hierarchical net path:
   ```tcl
   create_debug_port u_ila_0 probe
   connect_probe u_ila_0/probeNN {CPU_BOARD/CPU/PROC/CGA/DELILAH/ALU/s_signal_name[*]} "LABEL"
   ```

3. Update the probe count in the `puts` message

4. Rebuild: `.\vivado_build.ps1`

Current probes are defined in `vivado_build.tcl` (probe0 through probe26).

## Regeneration Workflow

When the Verilog changes or a new VCD/ILA capture is available:

### Step 1: Generate new Verilator reference (if Verilog changed)
```powershell
cd Verilog/sim
make clean && make all
```
This produces a new `waveform.vcd`.

### Step 2: Re-extract boot sequence from VCD
```bash
cd Verilog/sim

# Verify boot timeline
python3 vcd_extract.py waveform.vcd \
  -e "TOP.ND120_TOP.s_debug_lcs_n" "TOP.ND120_TOP.s_run" "TOP.ND120_TOP.sys_rst_n" \
  --ticks --table

# Extract CSA execution trace after loading
python3 vcd_extract.py waveform.vcd \
  -e "TOP.CSA_12_0" \
  --tstart 5734355 --tend 7600000 --ticks --json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
csa = data['TOP.CSA_12_0']['changes']
prev = None
for c in csa[:300]:
    dec = int(c['value'].replace('0x',''), 16)
    tick = c['tick']
    marker = ''
    if prev is not None:
        if dec == prev + 1: marker = ''
        elif dec == prev + 2: marker = f'  << COND SKIP 0x{prev+1:04x}'
        else: marker = f'  << JUMP (from 0x{prev:04x})'
    print(f'  tick={tick:>8}  CSA=0x{dec:04x}  oct {oct(dec)[2:]:>5}{marker}')
    prev = dec
"

# Extract ALU signals during countdown loop
python3 vcd_extract.py waveform.vcd \
  -e "TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.ALU.ALU_QREG.Q_15_0" \
     "TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.ALU.ALU_RALU.F_15_0" \
     "TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.ALU.ZF" \
     "TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.MIC.COND" \
  --tstart 5737800 --tend 5738200 --ticks --table
```

### Step 3: Rebuild FPGA with new probes (if needed)
```powershell
cd Verilog
.\vivado_build.ps1
```

### Step 4: Capture ILA data from FPGA
1. Open Vivado Hardware Manager
2. Program the FPGA with the new bitstream
3. Set ILA trigger (e.g., CSA rising edge from 0x0424)
4. Arm and capture
5. Export: `write_hw_ila_data -csv_file -force <capture-dir>/ila_capture.csv [upload_hw_ila_data hw_ila_1]`

### Step 5: Compare ILA CSV against Verilator reference
Load the CSV in Python and compare CSA sequences, ALU values, and flag transitions
against the values documented in `boot_analysis.md`.

## MIC Address Generation (how CSA is computed)

The microcode address MA_12_0 (= CSA_12_0) is selected by a pipeline:

1. **MASEL** selects source via SC5/SC6:
   - 00: JUMP (from microword bits)
   - 01: RETURN (stack pop)
   - 10: NEXT (IW + 1)
   - 11: REPEAT (same address)

2. **IPOS** final mux:
   - Normal: W_12_0 from MASEL
   - Loading (LCS_n=0): WCA_12_0
   - Trap (TRAP_n=0): CD[15:6] + TVEC[3:0]

3. **CSEL** evaluates conditions (ZF, CRY, OVF, IRQ, etc.) selected by TSEL[3:0]
   - Output CONDN latched on ALUCLK falling edge
   - Feeds back to address mux for conditional jumps

## Regression Testing: Before/After Verilog Changes

When modifying Verilog (e.g., replacing latches with flip-flops, fixing bugs, refactoring),
you need to verify the change didn't break the reference behavior. There are two workflows:

### Workflow A: CSV diff (existing latch_ff_compare.cpp pattern)

This is the lightweight approach used for the latch->FF migration. It logs a fixed set of
signals on every clock edge to a CSV file. Two runs produce two CSVs; `diff` shows divergence.

**Files:**
- `sim/latch_ff_compare.cpp` - testbench that samples signals on each posedge OSC
- `sim/trace_latch.csv` / `sim/trace_ff.csv` - reference CSVs from before/after
- CSV format: `cycle,CSA,TERM_n,MCLK,MACLK,EMD,CBWRITE,...`

**How to use:**
```powershell
cd Verilog/sim

# Before making changes: capture reference
make compare_latch          # produces trace_latch.csv (or whatever the "golden" is)

# Make Verilog changes...

# After changes: capture new
make compare_ff             # produces trace_ff.csv

# Diff them
diff trace_latch.csv trace_ff.csv | head -50
```

**To add new signals to the trace:** edit `latch_ff_compare.cpp`, add the signal to the
header row printf and the per-cycle sample printf. Recompile and re-run both sides.

**When to use this:** Fast iteration on a small set of ~20 signals you care about for a
specific change. Not useful for wide-hierarchy debugging.

### Workflow B: VCD snapshot diff (for bigger changes)

When the change may affect many signals or you don't know in advance which will differ,
use full VCD captures and compare with `vcd_extract.py`.

**Pattern:**
```bash
cd Verilog/sim

# 1. Capture BEFORE state
make clean && make all           # produces waveform.vcd
cp waveform.vcd waveform_before.vcd

# 2. Extract key signals to a reference JSON
python3 vcd_extract.py waveform_before.vcd \
  -e "TOP.CSA_12_0" \
     "TOP.ND120_TOP.s_debug_lcs_n" \
     "TOP.ND120_TOP.s_debug_cc_term" \
     "TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.ALU.ALU_QREG.Q_15_0" \
     "TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.ALU.ALU_RALU.F_15_0" \
     "TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.ALU.ZF" \
     "TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.MIC.COND" \
  --ticks --json > reference_before.json

# 3. Make Verilog changes

# 4. Capture AFTER state
make clean && make all
cp waveform.vcd waveform_after.vcd

# 5. Extract same signals from after
python3 vcd_extract.py waveform_after.vcd \
  -e "TOP.CSA_12_0" \
     "TOP.ND120_TOP.s_debug_lcs_n" \
     ... (same list) ...
  --ticks --json > reference_after.json

# 6. Compare with Python (ask AI to build a diff tool or use a pre-built one)
python3 compare_traces.py reference_before.json reference_after.json
```

**Key comparison checkpoints from boot_analysis.md:**
- Does the LCS_n transition happen at the same tick? (loading phase timing unchanged)
- Does the first executed instruction CSA match? (should be 0x0401)
- Does the countdown loop entry at 0x0425 happen at the same tick?
- Does the loop exit at 0x0427 happen at the same tick?
- Do the ALU Q/F/ZF/COND values match at equivalent boot points?

**Tolerance**: The tick numbers should match exactly for determinism. Any drift means
something changed clock behavior, latching timing, or reset sequence.

### Workflow C: FPGA vs Verilator comparison (the current task)

For comparing Vivado ILA capture against Verilator reference:

1. Verilator produces `waveform.vcd` at ps-level resolution
2. Vivado ILA captures at sample clock rate (typically one sample per sysclk edge)
3. Use `vcd_extract.py --ticks` to get Verilator data in clock tick units
4. Export ILA data: `write_hw_ila_data -csv_file ...`
5. Load both in Python, align on a common event (e.g., CSA transition from loading to 0x0401)
6. Compare signal-by-signal from that alignment point forward
7. First divergence = bug location

**AI should build:** a Python comparison tool (e.g., `compare_fpga_vs_verilator.py`) that
takes the Vivado CSV and the Verilator JSON, aligns them, and prints the first divergence
with context.

### Documenting a regression test

When adding a new regression check:
1. Define the "golden" behavior in `boot_analysis.md` with specific tick numbers and values
2. Add a section to this runbook explaining what the check verifies
3. Update `latch_ff_compare.cpp` if it needs new signals
4. Commit the reference CSV/JSON alongside the Verilog change so future AI can diff against it

## Key Microcode Address Regions

| Range (hex) | Range (oct) | Purpose |
|:------------|:------------|:--------|
| 0x0000 | 00000 | Fetch entry point |
| 0x000E-0x002A | 00016-00052 | Fetch sequencing/decode |
| 0x0065 | 00145 | Instruction complete |
| 0x0206-0x027F | 01006-01177 | Subroutine library |
| 0x0401-0x04FF | 02001-02377 | Self-test / init code |
| 0x07B6-0x07F0 | 03666-03760 | Utility routines |
| 0x0BB0-0x0BB8 | 05660-05670 | Trap/interrupt handlers |
| 0x0C00-0x0FFF | 06000-07777 | Instruction decode dispatch |
| 0x1000-0x1FFF | 10000-17777 | Instruction microcode handlers |

## Comparing a whole boot: the golden-model method (designed, not built)

Moved here on 28-SEP-2026 from the retired `Verilog/FPGA-BRINGUP-PLAN.md`
(sections 8, 11 and 12). Of the parts below only `docs/boot-golden-spec.md`
exists; `boot_trace.json`, `compare_boot_trace.py` and `capture_ila.tcl` were
never written. Kept because the reasoning still holds for the next board.

### Why a tick-by-tick diff gives false alarms

The boot path is not fully timing-deterministic. Every external event that can
steer the microcode address (`CSA`) meets in one 4:1 address mux in
`CGA_MIC_IPOS.v` (through `TRAP_n` selecting the `TVEC_3_0` branch, or
`MR_n -> LCS_n` for the load sequence). At boot they sort like this:

| Event | Steers CSA via | Deterministic at boot? |
|---|---|---|
| Master Clear / power-on | `MR_n -> LCS_n` load, start at o02001 | yes (once) |
| Traps (page fault / protect violation) | `TRAP_n -> TVEC` | yes (fault-driven) |
| Panel / keylock / ALD | `PANN` / PANVC vector | yes in the build this was written for (68705 stubbed `STAT=0`, buttons tied inactive) |
| Hardware interrupts / PIL | `INTRQ -> TVEC` (LEV3) | quiet - external bus interrupt lines idle |
| **RTC / 20 ms clock** | `s_rtc_n -> PANN/PANVC -> TVEC` -> microcode o016 | **no - the one truly async source** |

So in a clean boot the RTC interrupt is the only source of timing difference
(re-armed by the microcode `CLRTC`; the RTC counter is in `DECODE_DGA_POW.v`). Its timing relative to
microcode progress differs between Verilator and a board, so it can dispatch to
the PANVC handler at o016 at different points. Everything else must match
exactly: compare the microcode state machine, not the timeline.

Note: the panel row is from before the 68705 panel-clock emulation
(`PANCAL_68705_CLOCK.v`, `ND120_PANEL_CLOCK`); with it enabled, check whether
the panel adds a second async source before relying on this table.

### Comparator rule

Reduce both sides (sim trace and board ILA CSV) to one record per microcode
basic-block transition, with the reason each branch was taken, then:

- **Structural divergence = a real bug**: the same `(csa, branch cause, state)`
  gives a different next address. Example: the board at o02046 with `ZF=1`
  loops back to o02045 instead of leaving for o02047.
- **Harmless divergence = ignore**: a different loop count (it depends on the
  clock), a different number or timing of RTC dispatches, a different absolute
  tick.

A count-down loop (for example o02045/o02046 x 180,213) is one record whose
entry and exit must match but whose count may differ. `docs/boot-golden-spec.md`
is the ground truth: a trace that passes the diff but breaks the spec is still
flagged.

### Scripted ILA capture over hw_server

- Windows runs `hw_server` (it owns the USB-JTAG cable); WSL drives captures
  over TCP `localhost:3121`, so the Digilent device never has to be passed into
  WSL. `hw_server.bat` is in the Vivado install's `bin` folder.
- A capture script does `connect_hw_server -url`, selects the ILA, sets a real
  **trigger condition** (not `-trigger_now`), runs `run_hw_ila` /
  `wait_on_hw_ila` / `upload_hw_ila_data`, then exports in one step with
  `write_hw_ila_data -csv_file` (do not use the fragile two-step
  `list_hw_samples`).
- **The trigger matters most.** The ILA is only 2048 samples deep (commit
  `f618a9b`), while boot runs hundreds of thousands of ticks. `-trigger_now`
  catches a random window. Trigger on a landmark (for example `s_debug_csa ==
  o02047`, or entry to o02045/o02046) and use the same landmark to line the
  capture up with the golden trace.
- Longer term, a UART debug-event streamer (a short record per microcode step:
  marker + CSA + flags) escapes the 2048-sample limit and gives a full-length
  boot trace in the same form. The ILA stays the tool for zooming into one
  failure.

### Build gotchas (Vivado)

- A logic change must let `synth_1` really re-run (the `vivado_build.ps1`
  default). Reusing the old checkpoint is fine only for probe or constraint
  changes.
- The microcode hex files must sit where Vivado's `$readmemh` looks, or the ROM
  is empty (see the board README for the exact place).
- The `.ltx` must match the `.bit`; both are written by each build, and a stale
  `.ltx` labels the probes wrongly.
- For the debug loop use the volatile JTAG load (`flash.ps1 -Quick`); program
  the SPI flash only when the image must survive a power cycle.
