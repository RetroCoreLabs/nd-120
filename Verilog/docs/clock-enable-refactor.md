# Clock-Enable Refactor: eliminating the derived-clock nets

**Full path:** `Verilog/docs/clock-enable-refactor.md`
**Last updated:** 2026-09-28
**Status:** DONE 2026-07-05 (`CYC_TERM_D.v`, `CYC_CC_D.v`, the second
`PAL_44307C` instance in `CYC_36.v`); the level fix for MCLK/MACLK/UCLK
followed 2026-07-07. This file keeps how it works and the rules learned.
The planning sections and the failed experiments are in git history.

## Why

The CPU makes its clocks (ALUCLK, MCLK, MACLK, UCLK, CLK) with
combinational gates in `CYC_36` and fans them out as clock nets. On the
FPGA, Vivado force-inserted global buffers on exactly these nets and STA
could not constrain the dozens of gated clock domains (Basys3 routed WNS
was about -38.7 ns on 2026-07-04). The fix below turns them into clean
sysclk-generated flip-flop clocks in `FPGA_FF_MODE`.

## IMPLEMENTED (2026-07-05): phase-accurate clocks via validated mirrors

The gated-combinational clocks minted in `CYC_36` are now clean sysclk-generated FF
clocks in `FPGA_FF_MODE`, boot byte-identical to golden (seqcheck IDENTICAL). The
key that made it work (after edge/level/uniform all failed by +1 sysclk): fire each
clock's enable on the FSM's **next-state**, which leads by one cycle, so registering
it lands the rising edge on the exact edge the old gated clock fired (net-zero
latency).

- **Validated next-state mirrors** of `PAL_44601B` (PALs stay untouched & golden):
  - `CYC_TERM_D.v` - TERM next-state. Exhaustively validated == PAL (all 16 states x
    2 TERM x 128 inputs = 4096 checks, 0 err; mutation-tested). `make test-cyctermd`.
  - `CYC_CC_D.v` - CC3..CC0 next-state. Exhaustively validated == PAL (512 checks,
    0 err). `make test-ccd`. (Both in `CPU-BOARD-3202/circuit/sim/`.)
- **MCLK/MACLK/UCLK next values**: a SECOND (combinational) `PAL_44307C` instance is
  fed the next-state (TERM_D + CC_D) - the real PAL reused, no mirror of 44307.
- **Per clock**: register the predicted next LEVEL: `q <= <clock>_NEXT`.
  UPDATE 2026-07-07: originally this registered the rise pulse
  `<clock>_NEXT & ~<clock>_NOW`. That kept every RISING edge phase-accurate
  (which is all boot seqcheck exercises) but collapsed the HIGH phase to
  1 sysclk. Level consumers then broke: `CPU_CS_ACAL_17`'s address latches are
  transparent while MACLK is HIGH, so with a 1-sysclk MACLK the WCS address
  (LUA) froze mid-microcycle and the DGA instruction-dispatch address (WCA,
  e.g. o7250) never reached the WCS -> FF-mode program execution hung
  (the 07-JUL "`20!` hangs in FF mode" bug). MCLK/MACLK/UCLK are now level-registered:
  identical rising edge, full high phase reproduced. RULE: a generated
  replacement for a gated clock must reproduce the WAVEFORM, not just the
  rising edge - transparent-latch consumers use it as a level.
  - ALUCLK: `aluclk_en = TERM_D & ~LCS`.
  - CLK (`~TERM_n`): `clk_en = TERM_D`; the clean `clk_pa` also feeds the FSM's own
    `PAL_44403/44404` `.CLK` (their clock source changes, the PALs do not).
  - MCLK/MACLK: `~(TERM_n_next & MCLK_n_next/MACLK_n_next)` from the 2nd 44307.
  - UCLK: `TERM_n_next & UCLK_44307_next`.
- **Not converted**: WRFSTB (no posedge/clock use - the WRF clocks on ALUCLK).
- **Consumers unchanged** - they still `posedge <clock>`, but on a clean FF clock
  instead of a gated LUT net. (True single-sysclk-domain, i.e. converting consumers
  to `if(<clk>_en)`, is a later optional step - mainly for Gowin.)
- **OSC** (the FSM clock): `= sysclk` in sim; on FPGA `oc_select=2'b11` constant-
  folds it to `clk1`, so it is a clean clock net (not the gated-clock problem).

Gate for all of the above: `sim/seqcheck.py` after `make compare` -> address
sequence IDENTICAL, FF reaches o002001@69778 / o002047@72362.

## The two idioms, and WHEN to use each (this is the load-bearing decision)

`Shared/ndlib/LATCH.v` is **already converted** and its header records the trap:

> Edge-detect was tried first and broke LCS loading, because during LCS load
> `s_aluclk_n` is held high constantly - no rising edge ever appears, so an
> edge-detect FF never fires and CSEL_Q stayed at its init value.

So there are two patterns, and picking wrong silently breaks boot:

**A. Level-capture (the LATCH pattern) - the SAFE DEFAULT.**
```verilog
always @(posedge sysclk) if (enable_level) q <= d;   // tracks d while enable high
```
Use when the "clock"/enable can be **held static** across a whole phase (the LCS
load holds ALUCLK's source static). Matches `L4.v`/`L8.v`/`LATCH.v` already in the
tree. Transparent on a 1-sysclk grain - the closest synchronous analog of the
original 74xx transparent latch.

**B. Edge-enable (one-shot) - only where a true single pulse per cycle is needed.**
```verilog
reg d1; always @(posedge sysclk) d1 <= raw;
wire en = raw & ~d1;                                 // 1-sysclk pulse on rising edge
always @(posedge sysclk) if (en) q <= d;
```
Use for genuine edge-triggered registers whose source **pulses** every cycle
(MCLK/MACLK/UCLK per bus cycle). NEVER use where the source can sit static - that
is the exact failure LATCH hit.

**RESOLVED RULE (2026-07-04 investigation).** The level-vs-edge choice is decided
by the primitive's *type*, not per-instance guesswork:

- **Transparent latches** (`LATCH`, `L4`, `L8`) are level-sensitive - they must
  track D across the whole enable-high window -> **pattern A (level-capture)**.
  Already converted. The LCS trap only ever applied to these.
- **Edge flip-flops** (`D_FLIPFLOP`, `J_K_FLIPFLOP`, `T_FLIPFLOP`, `R81`, `R41P`,
  `R81P`, `SCAN_FF`) trigger on `posedge <clock>` -> **pattern B (edge-detect)**.
  There is NO LCS trap for them: a real edge FF clocked on a static-held signal
  *also* never fires, so edge-detect (`raw & ~raw_d`) is the exact equivalent.

So the FF-primitive conversion is uniform - edge-detect for all of them - and
`make compare` (only-BDRY gate) confirms each one. This removes the biggest
correctness risk the earlier draft flagged.

## Lesson from the failed attempts (2026-07-04/05)

Edge-detect, level-capture and a uniform sysclk migration of the consumers
all failed at the same point: each captured ONE sysclk late, because an
enable derived from an already-risen clock is late by construction. The
working fix fires each enable from the cycle FSM's NEXT state (available
combinationally before the edge), so the registered clock rises on the
exact sysclk edge the old gated clock did.

## References
- `fpga-debug-methodology.md` 3.2 - root cause + the derived-clock work list.
- `plan-fix-unconstrained-clocks.md` - the later net-by-net conversion of the
  remaining derived clocks (finished 10-JUL-2026).
- `sim/FPGA_REFACTORING_GUIDE.md` - the async-clock -> synchronous pattern.
- `Shared/ndlib/LATCH.v` - the already-converted reference (pattern A + the LCS trap).
- `boot-golden-spec.md` - the boot phases `make compare` must still hit.
