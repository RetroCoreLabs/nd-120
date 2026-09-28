# Plan: eliminate all 47 unconstrained-clock warnings (17 rogue clock nets)

**Full path:** `Verilog/docs/plan-fix-unconstrained-clocks.md`
**Date:** 9-JUL-2026. **Solved 10-JUL-2026** (P1-P4 done, 0 x Gowin TA1117,
every real Tang clock closes with 0.000 TNS setup and hold, and the first
console memory WRITE worked on silicon). This file is kept because about 70
RTL files cite its phase names (P1a-P1e, P2, P2b-P2e, P3, P4) for the
conversion each one carries. The phase plans, per-step checklists, the
validation harness and the day-by-day log are in git history; the sim gates
they used are now in `make test` / `make test-full`.

**Why it was needed:** the Tang deposit bug was measured down to
cross-clock-domain timing: every ND-120 layer, the SDRAM bridge FSM, and
sdram18.v were proven correct in isolation; the full build failed with
per-bitstream-stable wrong reads - the signature of unconstrained
register-as-clock domains. The Gowin log's 47 "WARN (TA1117) can't calculate
clocks' relationship" were 47 symmetric pairs over 17 nets used as clock
pins.

**Still open (P5):** a post-build check in `gowin_build.tcl` that fails on
any TA1117 (none exists yet), and the equivalent `check_timing` pass on the
Basys3/Vivado build. Also: the BD-bus strobes (CLKBD/SPEA/SPES, mode 2) are
dead logic on both boards - a residual risk, see P3.

## The 17 rogue clock nets

| #  | Net (Gowin name)          | Clocks what                                        | Phase |
|----|---------------------------|----------------------------------------------------|-------|
| 1  | `s_clk` (CYC CLK)         | DGA F924s (incl. the WRITE flop), IO consumers     | P2e   |
| 2  | `s_uclk_Z`                | microcode pipeline registers                       | P2c   |
| 3  | `s_mclk_Z`                | MCLK-domain registers                              | P2d   |
| 4  | `s_aluclk_Z`              | ALU registers (CGA_ALU_*)                          | P2b   |
| 5  | `s_rfclk`                 | WRF write strobes                                  | P2a   |
| 6  | `s_clk3_n_10`             | DGA internal inverted clk3                         | P2e   |
| 7  | `MEM/s_rdata`             | MEM_DATA_46.v:219,245 AM29861A read latches        | P1a   |
| 8  | `s_refrq_n`               | MEM_ADEC_45.v:175 D_FLIPFLOP                       | P1b   |
| 9  | `s_dbg_memw_0[2]` = **ECREQ** (v4 dbg layout bit2; NOT MWRITE50_n) | MEM_ADEC_45.v:235,238 `.CK(s_ecreq)` | P1c   |
| 10 | `BGNT_n_9`                | BIF_DPATH_BDLBD_10.v:75,94,113 TTL_74646/648 `.CLKBA(s_bgnt_n)` | P1d   |
| 11 | `DSTB_n_34`               | BIF_DPATH_CDLBD_11.v:77,93 TTL_74646 `.CLKAB(s_dstb_n)` | P3    |
| 12 | `BIF/SPES_12`             | BIF_DPATH_PESPEA_13 parity registers               | P3    |
| 13 | `s_ibapr_n_Z`             | BIF bus-address capture                            | P3    |
| 14 | `DELILAH/s_ldirv_2835`    | CGA_CPU_ALU_CONTR.v:657,669 IR registers           | P3    |
| 15 | `IO/s_sioc_n`             | IO_37 registers                                    | P3    |
| 16 | `DCD/s_div_16`, `s_XRTOSC`| IO_DCD_38.v:403 RTC divider chain                  | P3    |
| 17 | `sys_rst_n`               | `sys_rst_n_s0/F` (per .tr; find RTL flop in P4)    | P4    |

### P0 inventory addendum (9-JUL-2026, RTL clock-port sweep)

Additional register-as-clock consumers found by grepping every clock-capable
port hookup (`.CK/.CP/.CLK/.clock/.CLKAB/.CLKBA/.LE/.RAS_n/.CAS_n`) in
`CPU-BOARD-3202/circuit`, `DECODE-GateArray`, `DELILAH-CPU`. These do not all
appear as separate TA1117 clocks (some merge or optimize in synthesis) but
they are the same disease and get fixed in the same phase as their neighbors:

| Net             | Clocks what                                            | Phase |
|-----------------|--------------------------------------------------------|-------|
| `s_dbapr`       | MEM_ADEC_45.v:270,273 `.CK(s_dbapr)`                   | P1c   |
| `s_ddbapr`      | MEM_ADEC_45.v:163 `.clock(s_ddbapr)` D_FLIPFLOP        | P1c   |
| `s_spesl`       | MEM_ERROR_47.v:114 `.CK(s_spesl)`                      | P3    |
| RAS_n/CAS_n     | MEM_RAM_49.v:170-272 SIP1M9 row/col/write capture      | P1e   |
| `s_clk1/s_clk2/s_clk3(_n)` | DECODE_DGA_COMM.v:959-1146 F924 banks (internal CYC-derived) | P2e |
| `s_mclk` as LE  | CPU_PROC_32.v:324 `.LE(s_mclk)` AM29841 latch          | P2d   |

Clock Summary cross-check (`build/nd120_tang20k_build/impl/pnr/*.tr` 2.2):
19 base clocks = sys_clk + the 18 rogue roots; matches the table above plus
`s_ldirv` (source `DCD/GATES_10/s_ldirv_s3/F` - a LUT output as clock).
Max-frequency reality check from the same report: `s_clk` domain Fmax
**2.689 MHz**, `s_mclk` 2.732 MHz, `s_aluclk` 5.286 MHz - even the
*constrainable* paths are 5-10x too slow for the 13.5 MHz clk2x, and TNS
on aluclk is -40862 ns over 355 endpoints. P2 does not just constrain
these paths, it moves them onto sysclk where the tools can finally retime.

Rules that bind every phase:
- **Never modify `Verilog/PAL/PAL_*.v`** - conversions live in consumers or
  `_D` wrapper modules (CYC_CC_D / PAL_44446B_D pattern).
- **Convert a clock domain whole, never partially** (R41P lesson: a
  half-converted domain creates phase skew between its own registers).
- One net / one domain per commit - every step revertable and bisectable.
- All conversions sit behind `FPGA_FF_MODE`; latch mode (original hardware
  semantics) stays byte-identical.

## Phase 1 - memory-path capture points (deposit-critical, smallest blast radius)

Converted #7-#10 to the proven sysclk edge-capture pattern (`AM29C821`
`USE_SYSCLK=2` - one capture per detected CK rise, no routed clock; the same
fix that solved the MEM_ADDR_44 deposit regression):

- **P1a** MEM_DATA_46 RDATA read latches (add USE_SYSCLK-style mode to
  AM29861A, matching AM29C821's).
- **P1b** MEM_ADEC_45:175 refrq_n flop -> sysclk + refrq edge detect.
- **P1c** MWRITE50_n-as-clock consumer (from P0 inventory).
- **P1d** BGNT_n-as-clock consumer (from P0 inventory).
- **P1e** SIP1M9 / MEM_RAM_49 RAS-edge row capture -> sysclk + RAS edge
  detect (Basys3 evidence: PAL_44902 RAS_n is an unconstrained root clock
  feeding the BRAM row capture - deposit-critical on the Basys3; see the
  Basys3 appendix).


## Phase 2 - the CYC_36 generated CPU clocks (the branch thesis)

`CYC_36` additionally emits one-sysclk-wide enable pulses aligned with each
level-registered clock: `CLK_EN, UCLK_EN, MCLK_EN, MACLK_EN, ALUCLK_EN`
(**landed 9-JUL** - see progress log; alignment property tb = `test-cycen`).
Consumers convert from `posedge s_xclk` to `posedge sysclk + if (XCLK_EN)`,
one whole domain per commit, smallest first.

**CORRECTION (9-JUL, from the P1d .tr):** the plan's original "P2a s_rfclk
(WRF)" was a misidentification - netlist s_rfclk's source is
`DGA/POW/A633/reqQ_n` (the DGA power/RTC divider chain, 1 endpoint), NOT
the CGA write register file. It moves to the P3 IO/divider batch. The WRF
is inside the ALUCLK/WRFSTB structure and is handled with P2b.

- **P2b** s_aluclk domain (CGA_ALU: GPR/DBR/QREG/STS + CGA condition regs)
- **P2c** s_uclk domain (microcode pipeline)
- **P2d** s_mclk domain
- **P2e** s_clk domain (DGA XCLK + IO). Converting the DGA turns F924 into
  sysclk+CE and dissolves the internal clk2/clk3/clk3_n (#6) for free.

**REVISION (10-JUL, from the P2b red gates): P2b-P2d cannot land as separate
commits - the CGA clock group must convert TOGETHER.** Proof by measurement:

- With rise-aligned enables the P2b conversion is byte-identical to golden
  for 557,335 ticks, then ONE unconverted flop flips: `CGA_MIC.MEMORY_35`
  (`s_zfff_q_out`, Z-flag sync, `posedge s_mclk`, d = combinational ZF off
  the converted ALU registers). Waveforms show MCLK and ALUCLK rising on
  the SAME sysclk edge in that cycle shape: the original derived-clock flop
  samples ZF BEFORE the ALU registers' same-edge update lands (NBA
  old-value exchange between two pass-2 derived clocks); the converted ALU
  registers update in the sysclk pass, so the still-pa-clocked MEMORY_35
  captures the NEW ZF one clock early. The corruption spreads
  ZFFF -> COND -> INTR priority state (PD/HIGSN at ~650k) -> self-test
  TEST 2 STERR at ~737836 -> runSim WAIT-loop hang.
- Enable placement cannot fix this class. All three placements were built
  and measured: rise-aligned (correct for converted<->converted and
  latch-fed data; breaks unconverted same-edge observers), rise+1 posedge
  and rise+negedge (both shift the capture VALUE to post-edge, which
  diverges from cycle 0 - BDRY refresh chain +1 tick, 900k-line diff).
  Verilator's derived-clock flops sample PRE-edge values of other
  same-edge derived-clock flops; only same-pass NBA reproduces that, i.e.
  BOTH sides of every coincident-edge transfer must be converted.
- ALUCLK/CLK rise coincide by construction (both TERM-derived) and MCLK
  coincides in short cycle shapes, so the coupled unit is the whole CGA
  clock group: ALUCLK + CLK + UCLK + MCLK + MACLK consumers (MIC, INTR,
  TRAP, IDBCTL, DCD, MAC, ALU, WRF) in ONE tree state, gated by the same
  byte-identity compare at the end. Fall-edge consumers
  (InvertClockEnable / ~ALUCLK style) need FALL enable pulses
  (`pa & ~next`) added to CYC_36 alongside the rise enables.
- Debug harness for residual flips (sim/): `ND120_START_TRACE` /
  `ND120_MAX_TICKS` env overrides in test_nd120.cpp + kept obj_dir_base
  (conversions off) and obj_dir_conv builds + scratchpad
  vcd_diff.py/vcd_snap.py/bisect_time.sh - binary-searches the first
  diverging tick and names the first diverging signals in ~30 min without
  rebuilds. Ground zero for any new flip = convert that observer's module
  next.

**GROUP CONVERSION (10-JUL):** the whole
coupled group is now converted with rise-aligned enables:

- CGA: ALU + WRF (P2b) + MIC (48 flops incl. M169C LC counters, SR44 stack
  on MCLK-fall) + INTR (17) + DCD (21) + IDBCTL PGSREG (14) + MAC (7+1) +
  TRAP TVGEN_P2 (7, TCLK=UCLK domain). New wrappers: J_K_FLIPFLOP_EN,
  SR44_EN, SCAN_WITH_SET_N_EN, SCAN_WITH_RESET_N_EN, M169C_EN, F924_EN
  (composites = structural copies with only the flop primitive swapped).
- CYC PALs 44403C/44404C: new PAL_44403C_EN.v / PAL_44404C_EN.v in
  Verilog/PAL/ (equation copies with `if (EN)`; originals untouched) -
  they register on CLK and sample converted outputs (ACOND_n -> LCS_n was
  the 557151 detonation).
- DGA (P2e pulled in): COMM (13) + IDBS (4) + panel FIFO on XCLK=CLK;
  one CLK_FALL_EN site (COMM A204 on ~clk3). POW divider left for P3.
- Board: ND3202D regMIS, IO_UART_42 CHIP_33G (AM29C821 CK driven by the
  CLK_EN pulse in FF mode). CS/ACAL/PANCAL verified no pa-clocked flops.
- CYC_36 emits FALL enables (level & ~next) for all five clocks;
  test-cycen extended (18990 checks).
- Wrapper init bug found by harness: SCAN_WITH_SET_N_EN async set must be
  `posedge ~S_n` (active-high preset like the original ACTIVE_ASYNC flop),
  NOT `negedge S_n` - at time 0 S_n starts low, the negedge never fires,
  the original's preset 0->1 does (DZD_FF t=0 flip).
- **BDRY baseline finding:** latch-vs-FF `make compare` at committed HEAD
  (0843e88) already differs in EXACTLY the BDRY column (5872 rows, refresh
  pulses at reset rows 0-7 in latch, 100-107 in FF, then +1 offset) - a
  PRE-EXISTING FF-mode reset artifact, not from this campaign. The
  practical gate is therefore: diff columns == {BDRY, first@0, 5872} and
  nothing else.
- With all of the above, latch-vs-FF divergence moved 557151 -> 738965
  (only CSA/LED/MCLK/TERM_n after 738965 + the baseline BDRY artifact).

**ALL SIM GATES GREEN (10-JUL):** after two more fixes the full group
conversion passes everything:

1. CMDDEC PALs 44407A/44408B/44511A converted (PAL_*_EN equation copies,
   CLK_EN threaded ND3202D -> CPU_15 -> CPU_PROC_32 -> CMDDEC). Fixed the
   VEX/LDEXM flip at ~557533.
2. CGA_MIC_MASEL regIW: its FF-mode capture read regREP - but regREP is
   itself a sysclk register updating on the same edge, so the pa-clocked
   original saw regREP's NEW value while the converted pre-edge sample was
   one cycle stale. Fix: capture regREP_comb (the register's D input).
   This is THE pattern for native-sysclk-producer -> converted-consumer
   same-edge transfers: sample the producer's D, not its Q. Fired only
   when a conditional jump resolved exactly on an MCLK rise (survived to
   tick ~738920, self-test).
3. Result: latch and FF traces byte-identical to the STORED GOLDENS
   (cmp trace_{ff,latch}.csv vs sim/golden/ = OK over 1M rows), global
   `make test` 24/24, runSim FF console byte-identical to golden
   (previously hung in the STERR wait-loop), Tang vtest deposit
   22/054321 readback PASS.

Fmax reality from the P1d .tr (why P2 matters): s_clk 3.06 MHz,
s_mclk_Z 3.07 MHz, s_aluclk_Z 5.85 MHz, CLKOUTD domain 5.67 MHz vs the
6.75 MHz crawl clock - and none of it hold-analyzed.

## Phase 3 - control-strobe clocks (#11-#16) - done 10-JUL-2026

Same edge-capture conversion, batched per module: BIF batch (DSTB_n, SPES,
ibapr_n), CGA batch (LDIRV), IO batch (sioc_n, div_16, XRTOSC divider chain
-> sysclk counter with terminal-count enables). TA1117 went 28 -> 2.


- **BIF end-of-window lesson (the board deposit bug):** DSTB_n marks the
  END of the memory data window - the mode-2 (rise+1) edge capture reads
  a dead bus, and every memory READ returned 000000 (vtest + runSim both
  caught it; examine looked right only because memory was zero).
  New `TTL_74646 USE_SYSCLK_AB=3` WINDOWED capture: follow the data on
  posedge sysclk while the strobe is low, hold from the rise -> holds the
  at-rise value with no lag. Legal in CDLBD because SAB=DSTB_n selects
  real-time data during the low window, so regA is unobserved until the
  rise. RULE: strobe conversions must classify the strobe first -
  START-of-window (ECREQ, BGNT_n: data valid after the rise -> mode 2) vs
  END-of-window (DSTB_n: data dies at the rise -> mode 3).
- BIF batch: CDLBD CLKAB (mode 3), BDLBD CLKAB=CLKBD (mode 2, BD bus tied
  off - residual risk documented), PESPEA 4x TTL_74534 on SPEA/SPES (new
  USE_SYSCLK=2 param), PPNLBD posedge ECREQ -> inline edge capture.
  s_dbg_memw_0[2] root was ECREQ seen through the DBG_MEMW bus - gone
  with the PPNLBD fix.
- IOC: TTL_74273 gained USE_SYSCLK=2 (sync clear kept); CHIP_28A_IOC
  captures on the detected ~SIOC_n rise. Cost: the two LED trace columns
  shift one tick (the only non-BDRY trace change - accepted, FF golden
  regenerated).
- LDIRV: D_FLIPFLOP_EN gained USE_ENABLE=2 (strobe edge-capture via the
  clock pin); MEMORY_46/47 in CGA_CPU_ALU_CONTR converted.
- Dividers: the two ripple 74393s (s_div_16/s_XRTOSC roots) replaced in
  FF mode by one synchronous 8-bit counter (bit-exact mapping: pposc=
  bit2, div_16=bit3, XRTOSC=bit7); the POW F714/F617 RTOSC ripple network
  (s_rfclk root) replaced by a sync 6-bit counter + rfclk/panosc toggles
  + F617 set-priority equations, with the rfclk rise derived from the
  q633 NEXT value so the CLOSC-forced QB rise still clocks A630/A631.
  Refresh phase moves -> BDRY diff rows grew (13684, still BDRY-only).
- MMU cache roots (s_mclk_Z/s_uclk_Z): PAL_44402D posedge UCLK ->
  PAL_44402D_EN equation copy on UCLK_EN; AM29841 CHIP_25F posedge
  LE=mclk -> new AM29841 USE_ENABLE=1 on MCLK_EN. UCLK_EN threaded
  CPU_15 -> CPU_MMU_24 -> CPU_MMU_CACHE_25. Cache RAMs were already
  sysclk BRAMs.

- vtest caught a P3 regression before the board did: mode-2 DSTB capture
  read a dead bus and ALL memory reads returned 000000 -> the mode-3
  windowed capture above (TTL_74646 USE_SYSCLK_AB=3) fixed it; both
  goldens stayed byte-identical.

## Phase 4 - sys_rst_n as clock (#17) - done 10-JUL-2026

- After the P3 fixes the board stayed silent: hardware bisect (DIAG builds) showed the
  boot lived or died with the SIOC conversion - but DIAG2's timing report
  was violation-free and the identical RTL passes vtest. The real
  mechanism was the LAST unconstrained root: POW A572 clocked by
  s_clear_n (= sys_rst_n on FPGA). Gowin auto-created a bogus 100MHz
  "sys_rst_n" base clock for it and every path near it was unanalyzed -
  the same per-bitstream placement-lottery that caused the original write
  bug. Each recompile rolled the dice; the SIOC localparam flip just
  reshuffled the layout.
- P4 fix: A572 converted in FF mode to a sysclk flop capturing
  s_esload_n on a detected s_clear_n rise (async CLRTI preset kept,
  q init 0 so s_lrst starts 1 like the original).
- RESULT: **zero TA1117 warnings, the bogus sys_rst_n clock is gone from
  the Clock Summary, and every real clock closes timing with 0.000 TNS
  setup AND hold.** All sim gates green (24/24 units, both trace goldens
  byte-identical, runSim console golden, vtest PASS). **BOARD: boots to
  the OPCOM '#' prompt, deposit 22/54321 + readback = 054321 - the first
  time a memory WRITE from the console works on silicon.**


Also found on the way: the write-path analyzer in `ND120_TANG20K_TOP`
triggered on the first write decode - which fires during a normal boot once
writes work - and then held the console TX pin forever. That pin takeover
is now behind `TANG_WRITE_ANALYZER_DUMP` (off by default).

## Gowin SDC lessons (from the thrown-away P0.3 constraint probe)

The probe (constrain the derived clocks instead of converting them) did
not fix the board: a netlist whose real Fmax is below its clock cannot be
rescued by constraints. The Gowin SDC lessons it cost, three builds' worth:

  1. The SDC parser is a tiny Tcl subset: **no foreach/variables** -
     flat commands only.
  2. **PLL output pins are not clock sources until explicitly declared** -
     chain create_generated_clock from [get_ports sys_clk] first.
  3. **Auto-inferred clocks are not addressable objects** - get_clocks on
     a .tr auto-clock name fails with TA2004 at parse time; declare an
     explicit create_clock on the source PIN (from the .tr Source column),
     then reference the explicit name.
  4. Synthesis uniquification suffixes in pin names change between builds
     (`s_dbg_memw_2_s17/F` in one build, `_s2/F` in the next), so a
     pin-named constraint is fragile.
