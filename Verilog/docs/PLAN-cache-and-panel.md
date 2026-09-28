# Plan - cache and operator panel: what is left

**Full path:** `Verilog/docs/PLAN-cache-and-panel.md`
Living plan. Outstanding work only - finished items are deleted, not ticked.
The cache is fixed and board-confirmed (all 8 `CACHE-1X0-A00` tests pass,
31-AUG-2026); the root causes and how to test are in
[`CACHE-STATUS.md`](CACHE-STATUS.md). The ACTIVE LEVEL row is driven by the
ACTLV word from `PANCAL_68705_CLOCK.v` (commit `4c9855a`, hold time
`ACTLV_HOLD_FRAMES = 2` in `term_panel.v`) and the MIPS counter is built
(`ND120_MIPS_TAP`, see `build-defines.md`).

> **Next:** decode the duty-cycle loop in `Code/68705/MC68705U3_35C.BIN`
> (section 1) before touching the meters.

## 1. Panel meters are not faithful

`Terminals/rtl/terminal_top.v` feeds both bars through `rate_meter` with 8
steps, a 2^24 window (`WINDOW_BITS(24)`) and a linear fall. The real MC68705
samples LHIT at 400 Hz over a 128-tick (320 ms) window in steps of 32,
carrying over half of the previous window (ROM-checked,
`Code/68705/U3/U3-COMPLETE.MD` sections 3, 4, 12) - wrong on every axis.

## 2. Known broken, not blocking

- **`-tclargs ila` is dead.** Its probe list in
  `fpga/nexys4ddr/build.tcl` still names `s_ila_ram_addr`, which does not
  exist in this configuration, so it exits before building a debug core.
  `ilacache` and `ilaslim` are unaffected. Fix by pruning that list when
  someone next needs the floppy/IOX probe set.
- **`term_panel.v`:** `s_ruler_reversed` is `(s_row == 3'd3) && s_in_levels
  && ...`, and `s_in_levels` already requires `s_row == 3'd2`. Always false,
  so the ruler row never highlights. Cosmetic.
- **`Verilog/sim` `make test_nd120`** failed on 29-AUG with 80 missing-pin
  warnings promoted to errors (`DBG_PANEL` and `DBG_CACHE` unconnected in
  `ND120_TOP.v`); it failed the same way at `54f30ca`. Not re-checked since.
- **The N=2 multicycle derivation's one assertion** is still to be written
  (weakest link and the check are in
  `fpga/nexys4ddr/docs/wcs-multicycle-analysis.md`).

## 3. Open question on the 44155A listing

A PAL 44155A was found with the same signal set as our 44511A, LEV0
byte-identical. Its CUP function matches ours once CWR's inverted polarity is
accounted for (its CWR means "no cache write happened", ours "a cache write
happened"), which is useful independent confirmation. To say more, two things
are needed and neither is in hand:

- its **pin list** (the line above the equations) - without it the polarity
  convention of its CWR pin is unknown;
- its **DESCRIPTION block** - date and board reference, which would say
  whether it is an earlier revision, a different board, or a fix we are
  missing.

Do not adopt its equations into `PAL_44511A.v`. Ours drives pin 19 so that
it FOLLOWS CWR (see fault 2 in `CACHE-STATUS.md`), and `CPU_MMU_CACHE_25.v`
consumes it as `!s_cwr` for HIT. Mixing halves inverts HIT silently.
