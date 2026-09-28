# ND-120 FPGA Debug Methodology — Step-by-Step

**Full path:** `Verilog/docs/fpga-debug-methodology.md`
**Last updated:** 2026-09-28 (written 2026-07-03, when no board booted yet)

A followable procedure for finding and fixing any divergence between a
board and the Verilator reference. SINTRAN now boots on the Tang, Nexys and
MiSTer boards; the method is the same for the next divergence. The usual
suspect: **timing/semantic differences between transparent latches
(original hardware) and the edge-triggered flip-flops the FPGA needs.**
This doc gives the mental model, a triage decision tree, and per-step commands
to isolate the buggy module(s) and drive them to a fix.

Companion docs:
- `docs/boot-golden-spec.md` — the expected microcode boot flow + detection rule.
- `sim/SIGNAL-COMPARISON-HOWTO.md` — the `make compare` latch-vs-FF tool.
- `sim/FPGA_DEBUG_RUNBOOK.md` — Verilator-vs-FPGA workflow + signal map.
- `sim/FPGA_REFACTORING_GUIDE.md` — the async-clock -> synchronous conversion pattern.
- `Verilog/sim/FPGA_DEBUG_RUNBOOK.md` — build/flash/validate loop + capture automation.
- `docs/ILA-PROBE-SEMANTICS.md` — the Nexys ILA rules.

---

## 0. The mental model: THREE WORLDS

| World | Build | Clocking | Role |
|---|---|---|---|
| **Latch sim** | Verilator, `USE_LATCHES=1` (default) | transparent latches | **Golden reference** — boots to OPCOM |
| **FF sim** | Verilator, `USE_LATCHES=0` (`-DFPGA_FF_MODE`) | edge-triggered FFs | **"Simulated FPGA"** — same semantics the FPGA gets |
| **Real FPGA** | Vivado synth (`FPGA_FF_MODE` implied) | real FF + routing/timing | The target |

**The key insight that drives everything below:** FF sim uses the *same*
flip-flop semantics as the FPGA, in software, deterministically, in seconds.
So most FPGA boot bugs reproduce in **FF sim WITHOUT hardware**. Fix them in the
fast loop; only real-silicon effects (timing closure, RAM inference, tri-state,
routing) need the board.

```
Latch sim boots  ─┐
                  ├─►  If FF sim ALSO fails  → bug is in the latch→FF logic. Debug in sim (fast).
FF sim result   ─┘    If FF sim boots but FPGA fails → bug is silicon-only (timing/RAM/tristate).
```

**Current evidence (updated 2026-07-04):** a **fresh** `make compare` shows FF sim
now boots **identically to latch sim** — all 16 tracked signals match except the
documented harmless BDRY cycle-0 init transient; FF reaches exec start `o002001`
(cycle 69778) and the Phase-3 exit `o002047` (cycle 72362), and keeps executing.
So the latch->FF refactor is CORRECT in Verilator. **We are in Branch B
(Section 3): the latch/FF logic is fine; the remaining FPGA failure is
silicon-only** (timing closure, RAM inference, tri-state, reset). (The earlier
"FF stuck at CSA=0" reading came from a stale Mar-30 trace that predated the
refactor commits — disregard it.)

---

## 1. TRIAGE (do this first — ~10 min)

Answer three questions. They decide which branch (Section 2 or 3) you work in.

### 1a. Does FF-mode Verilator boot? (the pivotal question)

```bash
cd Verilog/sim
make clean
make compare          # builds latch + FF, runs both, diffs -> trace_diff.txt
```

Then find where FF first structurally diverges (ignore the known-harmless BDRY
init transient around cycle 16415):

```bash
# Does FF ever reach execution start o002001 and the Phase-3 exit o002047?
awk -F, 'NR>1 && $2==1025{print "FF reaches o002001 @"$1; f=1; exit} END{if(!f)print "FF NEVER reaches o002001"}' trace_ff.csv
awk -F, 'NR>1 && $2==1063{print "FF reaches o002047 @"$1; f=1; exit} END{if(!f)print "FF NEVER reaches o002047"}' trace_ff.csv
# Where does FF top out?
awk -F, 'NR>1{if($2>mx)mx=$2} END{printf "FF max CSA=%06o\n",mx}' trace_ff.csv
```

- **FF fails (stuck / never reaches o002001 or o002047):** -> **Branch A (Section 2).**
  Bug reproduces in sim. This is where the evidence currently points.
- **FF boots to OPCOM but FPGA does not:** -> **Branch B (Section 3).** Silicon-only.

### 1b. Does the FPGA meet timing?  (Windows)

```powershell
# After a synth+impl run, read the timing summary:
#   open_run impl_1 ; report_timing_summary
# or open the project in Vivado GUI -> Implementation -> Report Timing Summary
```
Note the **WNS** (Worst Negative Slack) at the CPU clock. Positive = timing
closes (boot failure is logic). Negative = a real setup/hold problem (the
combinational-clock paths likely cannot close) -> prioritise Section 3.2.

### 1c. Fresh ILA capture of the CURRENT bitstream  (Windows + WSL)

Do not trust old captures. Program the current `.bit`, capture the ILA, export
CSV (see `sim/FPGA_DEBUG_RUNBOOK.md`, last section), and confirm where the FPGA actually
stalls today. Compare against `docs/boot-golden-spec.md` phases.

---

## 2. BRANCH A — FF sim reproduces the bug (debug in simulation)

This is the fast path: edit -> `make compare` -> analyse, all in WSL, seconds
per iteration, fully deterministic. No FPGA needed until it boots in FF sim.

### 2.1 Find the FIRST structural divergence

The earliest signal that diverges between latch and FF is closest to the root
cause. Use the per-signal first-divergence script from `SIGNAL-COMPARISON-HOWTO.md`:

```bash
cd Verilog/sim
python3 - <<'PY'
import csv
first={}
with open('trace_latch.csv') as a, open('trace_ff.csv') as b:
    ra,rb=csv.DictReader(a),csv.DictReader(b)
    cols=ra.fieldnames
    for r1,r2 in zip(ra,rb):
        for c in cols:
            if c not in first and r1[c]!=r2[c]:
                first[c]=(int(r1['cycle']),r1[c],r2[c])
for c in cols:
    if c in first:
        cyc,v1,v2=first[c]; print(f"{c:10s} FIRST DIFF @{cyc:>8} latch={v1} ff={v2}")
    elif c!='cycle': print(f"{c:10s} MATCH")
PY
```

The 16-signal set (CSA, TERM_n, MCLK, MACLK, EMD, CBWRITE, CMWRITE, BACT,
EBADR_n, DAP, BLOCK, RERR, BDRY, DISB, TST, BLOCKL, LED) spans the cycle FSM,
bus PALs, and memory control. Whichever diverges **first** (excluding the cycle
~16415 BDRY init transient) names the subsystem. If you need a signal that is
not in the CSV, add it: build, then `grep <SIGNAL> obj_dir/VND120_TOP___024root.h`
to get the Verilator path, and add it to `latch_ff_compare.cpp`.

### 2.2 If the divergence is at/near CSA=0 (design never starts)

That is a clock/reset problem, not a datapath problem. Suspect the derived-clock
chain that must produce the very first `MCLK`/`MACLK`/`LCS_n` edges:
- `CYC_36` + `PAL_44403C` (the `LCS_n` load state machine).
- `Shared/ndlib/LATCH.v` and its `sysclk` routing (the current refactor).
- `MEMORY_*`/`D_FLIPFLOP` reset values in FF mode.

Zoom in with the waveform:
```bash
make gtk    # opens waveform.fst; look at sysclk, MR_n, LCS_n, MCLK, MACLK, CSA around cycle 0..20000
```

### 2.3 Zoom to the module, then test it in ISOLATION

Once a subsystem is implicated, test that module alone with an iverilog
testbench next to it (fast, targeted), driving latch vs FF behaviour:

```bash
# Example: the MASEL microcode-address path
cd Verilog/DELILAH-CPU/CGA_MIC/sim
make test-masel          # MASEL_cycle_tb + MASEL_iw_capture_tb (race/timing checks)
```

For a module without a testbench yet, create `<module>/sim/<module>_tb.v` that:
1. drives `sysclk` and the module's derived clock (e.g. `MCLK`) with realistic
   FPGA timing (derived clock rising 1 sysclk AFTER the data it gates),
2. asserts the expected output for a known input,
3. runs once in latch config and once with `-DFPGA_FF_MODE`.
A divergence there is your isolated, minimal reproduction.

### 2.4 Apply the fix pattern, prove it with `make compare`

The canonical fix for an async/derived clock is in `FPGA_REFACTORING_GUIDE.md`:
sample the derived "clock" as **data** on `sysclk`, edge-detect it to make a
single-cycle enable, and clock the register on `sysclk` gated by that enable.
After the change:

```bash
cd Verilog/sim
make compare    # goal: FF sim now reaches the same boot phases as latch sim
```
Iterate 2.1 -> 2.4 until FF sim boots to OPCOM. THEN go to the FPGA (Section 3
residual checks + Section 4 flash/validate).

---

## 3. BRANCH B — FF sim boots but the FPGA does not (silicon-only)

If FF sim reaches OPCOM but hardware does not, the cause is something Verilator
does not model. Check these in order:

### 3.1 RAM inference
- `MEM_RAM_49.v` selects tiny BRAM RAM for synthesis (`ramSize=3`, 24KB) vs large
  sim RAM. Confirm the microcode ROM (`AM27256_4513{2,3}L.hex`) is present in the
  Vivado project dir and actually initialises the BRAM (not empty).
- Check `IDT6168A`/control-store RAM inferred as block RAM, not distributed.

### 3.2 Timing closure on the Xilinx boards

> **Numbers below the 2026-07 line were superseded on 21-AUG-2026.** Measured
> then, Vivado 2026.1: Basys3 **WNS -29.778 ns** at 16.667 MHz, TNS -44293.688,
> 1714 failing endpoints of 44510 — with **hold CLEAN** (WHS +0.035 ns) and the
> **Inter Clock Table EMPTY**. The asynchronous clock grouping works, so every
> remaining violation is inside the CPU clock domain and is genuine logic depth
> (worst path 156 logic levels, WCS BRAM output straight into a WRF clock
> enable). Nexys 4 DDR the same day: **WNS -17.143 ns**, zero combinational
> loop alerts. Chasing a constraint fix for these is wasted work.
>
> Note also that the FPGA-does-not-boot framing is Xilinx-only now: the **Tang
> Nano 20K boots SINTRAN III** (24-AUG-2026).

**What was fixed, and what is left.** In 2026-07 the Xilinx builds failed
timing by 65-101 ns because dozens of flip-flops were clocked on DERIVED
signals (`posedge s_aluclk`, `s_clock`, `s_clkab` ...): each became its own
clock net that STA could not constrain. That class is fixed: the CYC_36
clocks are clean generated flip-flop clocks (`docs/clock-enable-refactor.md`)
and the rogue clock nets were converted one by one
(`docs/plan-fix-unconstrained-clocks.md`, 0 unconstrained clocks on the Tang
since 10-JUL-2026). The violations measured on 21-AUG (above) are inside
the CPU clock domain and are real logic depth, not constraint gaps. Current
per-board timing work: `fpga/nexys4ddr/timing.md` and
`docs/HANDOFF-cga-idb-ring-cut.md` (the CGA IDB ring).

**The fix pattern that was used (Section 2.4), for any derived-clock site that turns up again:** replace
`always @(posedge <derived>) q <= d;` with
`always @(posedge sysclk) if (<derived>_rising_edge) q <= d;` so there is ONE
clock domain (`sysclk`) and the derived signals become clock *enables*. Then STA
constrains cleanly and timing closes (the ND-120 is a slow CPU; a single modest
sysclk has plenty of margin).

**Work list — files with derived-clock always-blocks (35 when written; 22
remain as of 25-AUG-2026 - the base primitives `LATCH`, `L4`, `L8` and the
`*_EN` variants are converted and clock on `sysclk`, the PAL set mostly is
not):** the PAL set
(`PAL_44302B/44303B/44304E/44310D/44401B/44407A/44408B/44445B/44446B/44511A/
44601B/44801A/44803A/44902A/44904B/45001B/45008B/45009B`), Shared support
(`AM29841`, `AM29C821`, `TTL_74534/74646/74648`, `SC2661_UART`), Shared ndlib
(`LATCH`, `R41P`, `R81`, `R81P`, `SCAN_FF`), Shared logisim
(`D_FLIPFLOP`, `D_FLIPFLOP_SIMPLE`, `J_K_FLIPFLOP`, `T_FLIPFLOP`), and
`CGA_ALU_ARG`, `CGA_WRF_RBLOCK_DR16`, `BIF_DPATH_PPNLBD_14`. Convert the base
flip-flop/latch primitives first (`D_FLIPFLOP`, `LATCH`, `R81`, etc.) — most of
the PALs and TTL parts instantiate those, so fixing the primitives fixes the
majority in one place.

### 3.3 Tri-state
- Inside the FPGA `z` does not exist. Every "3-state" buffer must drive `0` when
  disabled (`TTL_74245/244/241`, `AM29841`, `AM29861A`). A `z` that sim resolves
  but silicon floats -> wrong data.

### 3.4 Reset
- `sys_rst_n` must reach every FF (POR counter). A latch that powered up to a
  benign value in sim may come up wrong on the FPGA.

### 3.5 ILA-vs-golden localisation
- Capture the ILA (fresh), reduce to `MA @ posedge MACLK`, diff against
  `boot-golden-spec.md`. First structural divergence names the failing phase;
  probe that region's signals (add `mark_debug`, rebuild).

---

## 4. The build / flash / validate loop (once FF sim is good)

```bash
# WSL: regenerate golden reference
cd Verilog/sim && make clean && make all
```
```powershell
# Windows: full synth (logic changed) then flash
cd Verilog/fpga/basys3
.\vivado_build.ps1          # ~1h full synth; writes output\ND120_TOP.bit + .ltx
.\flash.ps1 -Quick          # volatile JTAG program (fast iteration)
```
Then capture ILA -> CSV -> compare against golden (Sections 1c / 3.5). Success =
FPGA `MA` walks the `boot-golden-spec.md` phases and escapes Phase 3 to o002047.

---

## 5. Root-cause techniques (toolbox)

| Technique | Tool | When |
|---|---|---|
| Latch-vs-FF first-divergence | `make compare` + python (2.1) | Every FF-mode logic bug |
| Waveform zoom | `make gtk` / GTKWave on `waveform.fst` | Inspect exact edges around divergence |
| Module isolation | iverilog `*_tb.v` in module `sim/` | Confirm/repro a single module's bug |
| Microcode path check | `MA @ posedge MACLK` vs `boot-golden-spec.md` | "Did it take the right branch?" |
| Async-clock refactor | `FPGA_REFACTORING_GUIDE.md` pattern | Fix derived-clock races (root class) |
| FPGA signal capture | ILA + `capture_ila.tcl` + `vcd_extract.py` | Silicon-only bugs, final validation |

**Bias:** always try to reproduce in FF sim before touching the FPGA. A bug you
can reproduce in `make compare` is one you can bisect in minutes; a bug you can
only see on the board costs an hour per iteration.

---

## 6. Traps (each cost real time in the SINTRAN-boot and Winchester hunts)

- Never report a finding from a single instrument; cross-check against the
  oracle or a second signal first.
- Know the instrument's semantics before reading it (the trace prints P-1;
  OP=000027 is the trap signature, not an instruction; a gate signal is not
  an event).
- A probe that never fires is a RESULT, not a broken probe.
- Timing differences against an emulator are not bugs: the oracle's disc is
  instant and its boot load bypasses the card.
- Judge progress by instructions and landmarks, never by device-op counts.
- Testbenches, not boots, for module questions: a boot costs hours and
  answers one bit; a testbench costs seconds and stays as a regression test.
- A testbench that samples `iox_rdata` with a blocking read AFTER the clock
  edge is one delta late; the real slave latches it AT the edge
  (`ND_BUS_SLAVE.v`). Mirror it:
  `always @(posedge clk) if (iox_rd) capture <= iox_rdata;`
- A check placed after a status read proves nothing: the status read itself
  resets flip-flops and hides the fault being tested.
- `uniq` destroys evidence in a trace dump: each access appears twice (the
  tap spans two clk2x capture cycles) and a diagnostic may legitimately
  write the same word twice. Collapse exact pairs only.
- Trace trigger: anchor on an operation completing plus about 1 s of quiet,
  not on a register access and not on quiet alone (both fire at the start
  and dump an empty ring).
- `TANG_WD_TRACE_DUMP` does not fit with everything else on (95% logic /
  98% CLS, routing 25+ minutes; without it 91%/94%, about ten minutes).
