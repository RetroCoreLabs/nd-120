# Nexys 4 DDR - CPU clock frequency search and timing bottlenecks

Measured 26-AUG-2026 on branch `clock-up`, Vivado 2026.1 (win64), part
`xc7a100tcsg324-1` (speed grade -1). Every number below is **post-route**
static timing from a full `synth_design -> opt -> place -> route` run at
that actual constraint - never synthesis estimates, never arithmetic on a
different run. One seed per point. Build configuration identical to the
SINTRAN-booting build (`ilaslim`, DDR2 main RAM, CPU cache off, WCS
preload) except the CPU divider.

Evidence: one directory per run under `timing-analysis/run_clk<N>/`
(full report battery + `post_route.dcp` checkpoint), written automatically
by `build.tcl` before its WNS gate. Full analysis with constraint audit and
per-domain detail: `timing-analysis/TIMING_CLOSURE_REPORT.md`.

## Result table

The board oscillator is 100 MHz; one MMCM (VCO 1000 MHz) generates every
internal clock. **Only CLKOUT0 (the CPU clock) moves with `-tclargs clk N`**
- the storage clock (27.027 MHz), the DDR2 controller clocks (200 MHz ref,
75 MHz user) and `sys_clk` are fixed and stay healthy at every candidate.
The CPU period in ns equals the divider (`clk_table` in `build.tcl`).

| `clk` | CPU period | CPU-domain WNS | verdict |
|-------|-----------|----------------|---------|
| 16 | 60 ns (16.667 MHz) | +26.455 | PASS - the 25-AUG build, SINTRAN boots; the high-margin fallback |
| 25 | 40 ns | +9.293 | PASS |
| 33 | 30 ns | +1.282 | PASS - with the cache ON this is the deployed clock since 31-AUG (see the 30/31-AUG sections below) |
| 35 | 28 ns | +1.308 | PASS |
| 38 | 26 ns | +0.316 | PASS |
| 40 | 25 ns | +0.319 | PASS |
| 42 | 24 ns | +0.152 | PASS |
| 45 | 22 ns | +0.085 | PASS - razor-thin |
| 50 | 20 ns | **-2.546** | **FAIL** - default flow, 1213 failing endpoints, TNS -1600; the WNS gate refuses the bitstream |
| 50 + `physopt` | 20 ns | **+0.007** | PASS - `phys_opt_design` recovered the full 2.55 ns; **BOOTS SINTRAN (silicon, 26-AUG)** |
| 45 + `physopt`, 115200 console | 22 ns | +0.020 | PASS - **BOOTS SINTRAN with 115200 console (silicon, 26-AUG); deployed until the cache came on (31-AUG)** |
| 50 + `physopt`, 115200 console | 20 ns | **-0.210** | **FAIL** - the baud-constant edit re-rolled placement; 50 MHz closure is single-seed fragile |

Hold (WHS) stayed between +0.012 and +0.043 ns across all runs (hold does
not scale with the period). Pulse width +0.264 ns (MIG clk200 domain) at
every run. TNS 0 on every PASS row.

`-tclargs physopt` (added 26-AUG, opt-in) runs
`phys_opt_design -directive AggressiveExplore` after `place_design` and
again after `route_design`. The default flow is unchanged.

## The bottleneck: one single path family

At every frequency tried, **all 100 worst CPU-domain paths are the same
path family** (extraction: `timing-analysis/report_cpu_paths.tcl` on the
run checkpoints; see `setup_paths_cpu_group.rpt` in the run directories):

- **From:** the WCS microcode BRAM read port
  (`CPU/CS/WCS/CHIP_21C..22D/idt_memory_array_reg`, RAMB18E1 - the
  microinstruction word coming out of the control store).
- **Through:** `CSIDBS_4_0` IDB-source decode -> `INTR/CNTLR/IRGEL` ->
  `ALU/ALU_OUTMUX` + `ALU_STS` -> `ALU_RALU` CARRY4 chain -> `FIDBO` ->
  `TRAP/TVGEN` + `BRKDET` -> `PAL_44307_UCYCLK` (BRK_n / MAP_n) ->
  `MIC/MIC_IPOS` (MA_12_0) -> `CS/ACAL` (LUA_12_0) -> `PAL_44403_UCYIN0`
  -> `U_TERM_D` -> `ALUCLK_EN` (fanout 238).
- **To:** the register-file clock-enable pins
  (`CGA/DELILAH/WRF/RBLOCK/<R0-R7,Z>_REG_*/regFF_reg[*]/CE`).

Functionally this is the machine's full microcycle: the microinstruction
out of the WCS deciding, combinationally within the same cycle, whether
the write register file clocks at the end of it - a faithful transcription
of the original board's PAL/TTL microcycle logic with no register in
between.

Composition: 29-30 logic levels (LUT2..LUT6 plus 3 CARRY4), but the LUT
delay is only 7.0-7.8 ns of the total. **Routing dominates everywhere**
and compresses as the constraint tightens:

| constraint | worst arrival | logic | route | route share |
|-----------|---------------|-------|-------|-------------|
| 60 ns | 32.99 ns | 7.70 | 25.28 | 76% |
| 30 ns | 28.72 ns | 6.99 | 21.14 | 74% |
| 22 ns | 21.68 ns | 7.80 | 13.88 | 64% |

That routing dominance is why the router kept absorbing each step of the
search, and why the plain arithmetic estimate from the 60 ns run
("~30 MHz") undershot the demonstrated 45-50 MHz: a loose constraint gets
lazy routing.

No second family exists - when this path is met, the whole CPU domain is
met. The fixed-frequency domains (75 MHz DDR2 user logic worst intra-WNS
~+1.2 ns, 27 MHz storage +13 ns, MIG internals +1.46 ns) then hold the
design-wide WNS and are unaffected by the CPU divider.

## Constraint work done during the search

- **Fixed:** the `set_max_delay -datapath_only` bounds INTO the CPU clock
  (the toggle-handshake payload contract "one destination period") were
  hard-coded 80 ns - one period of the 12.5 MHz era. They now track the
  selected period (`$mmcm_div` in `build.tcl`).
- **Not done, deliberately:** no false-path or multicycle exception was
  added anywhere. The old "52 ns WCS->ACAL multicycle" idea from the Tang
  notes was not assumed; no RTL proof exists, and the search closed
  45-50 MHz without it.

## What STA does NOT prove (read before shipping a fast clock)

1. **Functional validation.** UPDATE 26-AUG-2026, both Ronny-verified on
   the board, one boot each:
   - **SINTRAN III boots at 50 MHz** (the 9600-baud `physopt` build,
     WNS +0.007).
   - **SINTRAN III boots at 45.45 MHz with the console at 115200 baud**
     (`clk 45 ilaslim physopt`, WNS +0.020) - the deployed configuration
     until 31-AUG-2026; since then the deployed build is 33.333 MHz with
     the cache ON.
   SOAKED 27-AUG-2026: a booted SINTRAN at 45.45 MHz answered all 8
   console-attention probes over a 4-hour unattended run (the Tang fast20
   did the same). SD-card WRITE workloads at these clocks remain
   unproven. Clocks between 16.667 and 45 are STA-passed; the 16.667 MHz
   release artifact is boot-checked.
2. **The WNS is a floor, not a guarantee.** Synthesis auto-inserts two
   loop-breaking false paths through the historical CGA IDB ring
   (`ALU_OUTMUX/D_15_0[8]`, `ALU_i_426/O`; `check_timing` reports 6
   combinational loops). Paths through those nodes are untimed at every
   frequency. Cutting the ring in RTL (the "PARKED DEBT" block in
   `build.tcl`) is the prerequisite for trusting sub-0.5 ns margins.
3. **Single-seed results, and the 50 MHz point is proven fragile.**
   Vivado is deterministic per configuration, so each row is one
   placement. Demonstrated 26-AUG: changing ONLY the console baud
   constant (9600 -> 115200, one UART divider) re-rolled placement and
   the 50 MHz + physopt closure went from +0.007 to **-0.210 ns FAIL**
   (`run_clk50_2`). Any netlist edit near the wall is a new dice roll.
4. **CPU:ui_clk ratio.** The MEM_HOLD freeze and the nds_sync toggle
   handshakes are contract-based and their payload bounds now track the
   CPU period, but ratios above 16.667:75 have never run on silicon.
5. `BOARD_CLK_FREQ` moves with `clk=` automatically (UART baud, RTC,
   watchdog counts) - the pair is atomic in `build.tcl`.

Recommended tiers from the report: **25 MHz conservative** (+9.3 ns = 23%
margin), **33.3 MHz balanced** (+1.28 ns), 40-50 MHz aggressive (no
engineering margin; needs the IDB ring cut, a seed sweep and a soak before
unattended use). Every tier is gated on booting SINTRAN and passing the
board tests at that clock.

## Reproducing a point

```
vivado -mode batch -source build.tcl -nolog -nojournal -tclargs clk 40 ilaslim -noburn
```

Reports and checkpoint land in a fresh `timing-analysis/run_clk40[_N]/`;
the WNS gate refuses to write a bitstream on negative slack. Add `physopt`
for the phys_opt flow. **Every passing run overwrites
`nd120_nexys4ddr.bit`** - rebuild at the intended clock before programming
the board.

## 30-AUG-2026: 45.45 MHz with the REAL cache - parked, and why

Every earlier 45.45 boot ran the broken cache (dead logic after synthesis).
With the cache real (builds 9+), 45.45 fails and the record is:

- Build 10 (clk=45 physopt, no exceptions): WNS -6.552, TNS -10047, 4248
  endpoints, all clk_cpu. Worst: MIC LAA_REG -> WCS BRAM address, 36 logic
  levels, 27.986 ns (72% route) vs 22 ns.
- N=2 multicycle for the LAA/LBA -> WCS-address family derived from the
  PAL fences (docs/wcs-multicycle-analysis.md) and added to
  nd120_timing.xdc. It APPLIED (build 12: no 12-4739, LAA gone from the
  violation list) and is kept - it is correct at every clock.
- Build 12 (clk=45 physopt + the exception): WNS -6.780, 4269 endpoints.
  New worst: WRF R2_REG_10 regFF[6] -> WCS CHIP_20D address - the family
  the analysis DELIBERATELY did not relax (WRFSTB writes land in state b,
  1 clk before an open RWCS capture window; no masking proof). The whole
  WRF -> ALU -> TVGEN -> ACAL -> WCS cone is ~28 ns whoever launches it.
- The same cone closed at +0.085 pre-cache: the cache added ~1900 LUTs of
  ROUTING pressure (path is 72% route), not logic in the cone.

Routes to 45 with cache, rising cost: placement/strategy runs to recover
route delay; a masking-proof analysis for the WRF launch family;
pipelining the TVGEN/ACAL cone (RTL surgery). Parked 30-AUG (Ronny) in
favour of test-3 and MIPS work; the deployed cache clock is 33.333 MHz
(build 11: WNS +0.037, physopt required).

## 31-AUG-2026: why 45 MHz with cache is not a build-flow problem

Measured, so nobody re-runs it: the cone is ~28 ns whichever endpoint the tool
picks (27.986 / 28.039 / 28.047 ns across builds 10, 12 and 18, on three
different worst paths), and it is 75-80% ROUTING.

- **Build effort is exhausted.** `timingexplore` (opt ExploreWithRemap, place
  ExtraTimingOpt, route AggressiveExplore) moved WNS from -6.780 to -6.440 -
  0.34 ns of the 6.4 ns needed.
- **Not congestion.** The part is 31% LUTs, 47% slices, 11% registers. The
  routing delay is DISTANCE: Block RAM is 68% (91.5 of 135 tiles), so the WCS
  BRAMs sit spread across fixed BRAM columns and the cone runs out to them and
  back every cycle.
- **The cone is architectural, from the schematics.** DELILAH.pdf page 103
  (`/CGA/TRAP/BRKDET`, sheet 1 of 1) has NO flip-flops at all: the page-table
  bits, `IPCR`, `IWRITE`, `IFETCH` and `VACC` reach `BRKN` and then
  `TRAPN = NAND(BRKN, CBRK, ETRAPN)` through pure combinational logic. Page 104
  (`/CGA/TRAP/TVGEN`, sheet 2 of 2) registers every trap TERM in FD1 flops on
  TCLK, but `TVEC3` is a bare NAND of `LEV1`/`LEV2` and those same signals
  select the `MUX31LP`s producing TVEC0-2 - and `LEV1`/`LEV2` are combinational
  from `VACC` + the page-table bits. So both the trap vector AND the IPOS mux
  select come live from the MMU protection check, with no register between the
  ALU's address and the WCS address pins. That is by design; `ETRAP_n`
  ("UNSTABLE TRAP IN THIS PERIOD CAN DESTROY MA !") is how the 1988 designers
  made it safe in time rather than by pipelining.

**So no local register can cut this cone**, and the only real fix is a pipeline
stage in the memory-protection path, which moves every fault a cycle later
machine-wide. Deployed answer stays 33.333 MHz with cache (7.52 MIPS).

With the cache the ceiling is 1/28.039 ns = 35.66 MHz. `clk=35` is 28.0 ns,
a 0.039 ns miss on paper - untested on the board and not worth the margin.
