# VCD Signal Analysis Guide for ND-120 Simulation

## Purpose

This document describes how to extract and analyze signals from the Verilator VCD waveform dump
to debug the ND-120 CPU boot sequence. The working Verilator simulation produces `waveform.vcd`
(~500MB, ~67M lines, ~35K signals). A custom Python tool `vcd_extract.py` was built to parse
this efficiently since the standard `vcdvcd` library takes 67+ seconds just for header parsing.

> **Waveform format today: FST, not VCD.** The `sim/` harness now builds with
> `--trace-fst` (`sim/Makefile`) and `test_nd120.cpp` writes `waveform.fst`.
> `vcd_extract.py` still works: it opens both formats through `sim/fst.py`,
> which pipes a `.fst` file through `fst2vcd` (part of GTKWave). The sizes and
> timings in this guide were measured on the older `waveform.vcd`; the examples
> run the same with `waveform.fst` in place of `waveform.vcd`.

## Files

| File | Path | Description |
|:-----|:-----|:------------|
| VCD dump | `Verilog/sim/waveform.vcd` | 496MB Verilator trace, ~6824 unique signal IDs (34849 names with aliases) |
| GTKWave config | `Verilog/sim/top_3202d.gtkw` | GTKWave saved session with 1109 signals of interest |
| Extraction tool | `Verilog/sim/vcd_extract.py` | Custom fast VCD parser (~1s header parse vs 67s with vcdvcd) |
| Boot analysis | `Verilog/sim/boot_analysis.md` | Complete boot sequence reference with timings, addresses, and Vivado debug checklist |

## The Extraction Tool: vcd_extract.py

### Why custom?

- `vcdvcd` (pip package, installed) takes 67s just to parse headers on a 500MB file
- Our custom parser does it in ~1s by streaming with 8MB buffer and stopping at `$enddefinitions`
- Handles Verilator signal aliasing (same short ID reused for connected wires across scopes)

### VCD Signal Aliasing (important)

Verilator reuses the same short ID for wire-connected signals. For example, short ID `O_` maps to
both `TOP.CSA_12_0` (at TOP scope) and `TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.MIC.MIC_IPOS.s_ma_12_0_out`
(deep in hierarchy). The parser stores ALL aliases per ID, not just the last one. Use `--shortest`
to prefer the shortest (usually top-level) name.

### Trace Depth

The testbench (`test_nd120.cpp`) sets trace depth to `1`:
```cpp
top->trace(m_trace, 1); // 1 is the trace depth
```
This means many deep internal signals only have their initial value (1-2 transitions).
Signals at the ND120_TOP level and CPU_BOARD level generally have full trace data.

### Debug Signal Mapping

The Vivado ILA uses `mark_debug` signals with `s_debug_` prefix (defined in `ND120_TOP.v`).
These are aliases for internal signals. The VCD contains both the `s_debug_*` versions and
the underlying signals:

| Vivado ILA name | VCD signal name |
|:----------------|:----------------|
| s_debug_csa[12:0] | TOP.CSA_12_0 |
| s_debug_lcs_n | TOP.ND120_TOP.s_debug_lcs_n |
| s_debug_mclk | TOP.ND120_TOP.s_debug_mclk |
| s_debug_cc_term[4:0] | TOP.ND120_TOP.s_debug_cc_term |
| s_debug_uartTx | TOP.ND120_TOP.s_debug_uartTx |
| s_debug_fetch | TOP.ND120_TOP.CPU_BOARD.MEM.ERROR.s_fetch |
| s_debug_mr_n | TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.MIC.MIC_MASEL.s_mr_n |
| s_debug_intrq_n | TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.TRAP.TBUF.s_intrq_n |
| s_debug_powfail_n | (not traced at depth 1 - check IO/DCD module) |
| s_debug_clear_n | (not traced at depth 1) |
| s_run | TOP.ND120_TOP.s_run |
| sys_rst_n | TOP.ND120_TOP.sys_rst_n |
| regPowerOnClear | TOP.ND120_TOP.CPU_BOARD.IO.DCD.regPowerOnClear |
| FIDBO[15:0] | TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.s_FIDBO_15_0 |
| CD_15_0_OUT[15:0] | TOP.ND120_TOP.CPU_BOARD.CPU.s_stoc_cd_15_0_out |
| s_wca_12_0[12:0] | TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.MIC.s_wca_12_0 |

### ALU signals (needed for 0x0425/0x0426 loop debug):

| Signal description | VCD signal name |
|:-------------------|:----------------|
| ALU Q register | TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.ALU.ALU_QREG.Q_15_0 |
| ALU F result | TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.ALU.ALU_RALU.F_15_0 |
| ALU A input | TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.ALU.A_15_0 |
| ALU B input | TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.ALU.B_15_0 |
| Zero flag | TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.ALU.ZF |
| Carry flag | TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.ALU.CRY |
| Condition output | TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.MIC.COND |
| Condition (inverted) | TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.MIC.CSEL.CONDN |
| R1 register | TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.WRF.RBLOCK.R1_REG_9.REG_15_0 |
| GPR output | TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.ALU.ALU_GPR.GPR_15_0 |

### clockTicks

The `TOP.ND120_TOP.clockTicks` signal is a 33-bit counter that increments every 10ps
(both edges of 100MHz sysclk). Conversion: `tick = time_ps / 10 + 1`.
Use `--ticks` flag to show tick values alongside ps timestamps.

## Common Commands

### List all signals
```bash
python3 vcd_extract.py waveform.vcd --list 2>/dev/null | head -50
python3 vcd_extract.py waveform.vcd --list 2>/dev/null | grep -i "MCLK"
```

### Extract specific signals by substring match
```bash
python3 vcd_extract.py waveform.vcd -s "s_debug_mclk" "s_debug_lcs_n" --ticks --table
```

### Extract by exact VCD name
```bash
python3 vcd_extract.py waveform.vcd \
  -e "TOP.CSA_12_0" \
     "TOP.ND120_TOP.s_debug_lcs_n" \
     "TOP.ND120_TOP.s_debug_cc_term" \
  --ticks --table
```

### Extract with time window
```bash
# Loading phase only
python3 vcd_extract.py waveform.vcd -e "TOP.CSA_12_0" --tstart 0 --tend 5740000 --ticks --table

# Around LCS transition
python3 vcd_extract.py waveform.vcd -e "TOP.CSA_12_0" --tstart 5730000 --tend 5760000 --ticks --table

# Post-boot execution
python3 vcd_extract.py waveform.vcd -e "TOP.CSA_12_0" --tstart 7540000 --tend 7600000 --ticks --table
```

### JSON output (for programmatic analysis in Python)
```bash
python3 vcd_extract.py waveform.vcd -e "TOP.CSA_12_0" --tend 6000000 --ticks --json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
csa = data['TOP.CSA_12_0']['changes']
print(f'Total changes: {len(csa)}')
for c in csa[:10]:
    print(f'  tick={c[\"tick\"]:>10} CSA={c[\"value\"]}')
"
```

### CSV export
```bash
python3 vcd_extract.py waveform.vcd -e "TOP.CSA_12_0" "TOP.ND120_TOP.s_debug_lcs_n" --ticks --csv output.csv
```

### Summary of all key boot signals
```bash
python3 vcd_extract.py waveform.vcd \
  -e "TOP.CSA_12_0" \
     "TOP.ND120_TOP.s_debug_lcs_n" \
     "TOP.ND120_TOP.s_debug_cc_term" \
     "TOP.ND120_TOP.s_debug_mclk" \
     "TOP.ND120_TOP.s_run" \
     "TOP.ND120_TOP.sys_rst_n" \
     "TOP.ND120_TOP.CPU_BOARD.IO.DCD.regPowerOnClear" \
     "TOP.ND120_TOP.s_debug_uartTx" \
     "TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.s_FIDBO_15_0" \
     "TOP.ND120_TOP.CPU_BOARD.CPU.s_stoc_cd_15_0_out" \
  --ticks --summary
```

### Extract microcode execution trace (CSA addresses with jump detection)
```bash
python3 vcd_extract.py waveform.vcd \
  -e "TOP.CSA_12_0" \
  --tstart 5734355 --tend 7600000 --json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
csa = data['TOP.CSA_12_0']['changes']
prev = None
for c in csa[:200]:
    v = c['value']
    dec = int(v.replace('0x',''), 16)
    marker = ''
    if prev is not None:
        if dec == prev + 1: marker = ' (seq)'
        elif dec < prev: marker = f' (JUMP from 0x{prev:04x})'
        else: marker = f' (SKIP +{dec-prev} from 0x{prev:04x})'
    print(f'  t={c[\"time\"]:>10}ps  CSA=0x{dec:04x} (oct={oct(dec):<8}){marker}')
    prev = dec
"
```

## Boot Sequence Quick Reference

See `boot_analysis.md` for full details. Summary:

| Tick | Phase | CSA Pattern |
|:-----|:------|:------------|
| 1-6 | Reset | sys_rst_n=0, everything initializing |
| 7 | LCS_n=0 | Microcode loading begins |
| 7-573,436 | Loading | CSA counts 0x0000 to 0x1FFF sequentially (8192 addresses) |
| 573,437 | LCS_n=1 | Loading complete, execution begins |
| 573,438 | First exec | CSA=0x0401 (microcode entry point) |
| 573,438-573,799 | Init | 69 instructions: 0x0401-0x0424 with subroutine calls |
| 573,799-754,018 | POWFAIL wait | 0x0425/0x0426 loop, 16384 iterations |
| 754,018+ | Self-test | 0x0427 onward, MACL test, UART output |
| ~776K+ | OPCOM | Instruction fetch loop: 0x0000->0x0401->0x1xxx->0x0C00->execute |

### Key microcode address regions
| Range | Oct | Purpose |
|:------|:----|:--------|
| 0x0000 | 0 | Fetch entry |
| 0x000E-0x002A | 16-52 | Fetch sequencing/decode |
| 0x0065 | 145 | Instruction complete |
| 0x0206-0x027F | 1006-1177 | Subroutine library |
| 0x0401-0x04FF | 2001-2377 | Self-test / init |
| 0x07B6-0x07F0 | 3666-3760 | Utility routines (UART) |
| 0x0BB0-0x0BB8 | 5660-5670 | Trap/interrupt handlers |
| 0x0C00-0x0FFF | 6000-7777 | Instruction decode dispatch |
| 0x1000-0x1FFF | 10000-17777 | Instruction microcode handlers |

## MIC (Microcode Controller) Architecture

The microcode address (MA_12_0 / CSA_12_0) is generated by a 3-stage pipeline in the CGA:

### Stage 1: MASEL (Address Source Selection)
SC5/SC6 select 4 sources: JUMP, RETURN (stack), NEXT (IW+1), REPEAT (same addr)

### Stage 2: IPOS (Final Mux)
Selects between: Normal exec (W_12_0), Cache Write (WCA_12_0), Trap Vector (TVEC)

### Stage 3: Output
MA_12_0 drives CSA_12_0

Key control signals: SC[6:3], TRAP_n, MAP_n, EWCA_n, LCS_n, MCLK

### MIC Submodules (in CGA_MIC):
- **MASEL** - 4:1 address mux (jump/return/next/repeat)
- **IINC** - Address incrementer (IW + CIN = NEXT)
- **STACK** - 13-bit LIFO for subroutine calls (SC3/SC4 control)
- **WCAREG** - Write Cache Address register (for loading phase)
- **IPOS** - Final address selector (normal/cache/trap)
- **CSEL** - Condition select (8 conditions x 2 banks)
- **CONDREG** - Condition register (loop counter compare)

### TRAP Module (in CGA_TRAP):
- **TBUF** - Signal buffering (true/inverted pairs)
- **TVGEN** - Violation detection (8 types: page fault, write protect, ring violations)
- **TVGEN_P2** - Trap vector generation (3-level pipeline, TVEC[3:0])
- **BRKDET** - Break detection, generates TRAP_n signal

When TRAP_n=0, IPOS overrides normal address with trap vector address.

## Vivado Comparison Workflow

1. Capture ILA trace in Vivado with trigger on LCS_n falling edge
2. Export ILA data to CSV
3. Compare CSA_12_0 sequence against the reference in boot_analysis.md
4. First divergence point indicates the bug location
5. Use the debugging decision tree in boot_analysis.md to narrow down the cause

## The analysis scripts in `Verilog/sim/`

All read `waveform.fst` from `make run` by default and print addresses and
values in OCTAL (`o{v:06o}` for CSA/CD/IDB, `o{v:02o}` for CSCOMM/CSIDBS/LC).
Run the simulator under WSL (the Git Bash verilator does not work).

| Script | Purpose |
|--------|---------|
| `fst.py` | `open_wave(path)`: reads `.fst` through `fst2vcd` (ships with GTKWave), `.vcd` directly. New trace scripts should `from fst import open_wave`. |
| `nd120_vcd.py` | Older signal-discovery helper (`find_ids`, `extract`), used by older scripts. |
| `fst_query.py` | FST signal query with octal output and named markers (CSA, LCS_n, MCLK, LC, LDLCN, CSCOMM, CSIDBS, IDB, PAN_n, CONN_n). A good start for a new `trace_*.py`. |
| `vcd_extract.py` | The CLI extractor described above (`-s`, `-p`, `--gtkw`, `--tstart/--tend`, `--json`, `--table`, `--list`). |
| `list_sigs.py` / `find_sigs.py` | Dump every signal name / grep names for substrings (edit `SUBS` at the top). |
| `find_wcs_signals.py`, `find_epans.py`, `find_panvc.py` | `find_sigs.py` pre-set for WCS / EPANS / PANVC signals. |
| `decode_mcode.py` | Decode a 64-bit microword into CSIDBS (bits 41:37) and CSCOMM (bits 36:32). |
| `analyze_ila.py` | Parse a Vivado ILA CSV and list CSA at MCLK rising edges (CSV path as argv[1]). |
| `compare_boot.py` | Line up an ILA CSV against the Verilator boot trace and find where they part; labels addresses from the DELILAH-L listing. Its `LISTING_PATH` and `ILA_CSV_PATH` constants hold one machine's paths - set them before use. |

The ~34 `trace_*.py` scripts are one-off captures from past investigations
(LDLCN/LC, PANVC/TVEC dispatch, PROM->WCS handoff, MOPC, MACL, signal
routing). Copy the closest one (`trace_ldlc2.py` is the cleanest template:
edit `WANT`, `T_START`, `T_END`) rather than treating them as a stable API.
FST timestamps are picoseconds; `tick = t_ps // 10 + 1` gives the tick
number `make run` prints. `s_debug_*` signals are debug taps brought out of
`ND120_TOP.v`; CGA signals sit under
`TOP.ND120_TOP.CPU_BOARD.CPU.PROC.CGA.DELILAH.*`.
