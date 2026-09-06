# DEBUG PLAN — floppy/tape boot: validate in Verilator, then find the Tang divergence

Date opened: 2026-07-27. Board: Tang Nano 20K (`FPGA_FF_MODE`). All paths absolute.

## Constraint (queue discipline)

**One Verilator run at a time** ([[one-verilator-run-at-a-time]]). Ronny is currently
running a manual Verilator TPE **PAGING** test (possibly slow, possibly hung). **Do NOT start
any Verilator build/run until that finishes and Ronny gives the go.** This plan is queued.

## Symptoms (measured on the flashed Tang, 27-JUL — the build with the trap-vector + cache
HIT-gate + CUP fixes)

CORRECTION 27-JUL: the `400$` "regression" was a FALSE LEAD. The flashed bitstream is a
**FLOPPY-ONLY build**: `src/tang20k_defines.v:52` has `` `define TANG_FLOPPY ``, and
`src/ND120_TANG20K_TOP.v:468-473` sets `TANG_INC_TAPE=0, TANG_INC_FLOPPY=1` under it — so
**there is NO device-400 tape hardware in this build at all.** `400$` finding "no memory
loaded, hangs" is therefore EXPECTED (nothing to load from), NOT a cache-fix regression. The
older build that loaded ~23244 words on `400$` was a TAPE-ONLY build (`TANG_FLOPPY` commented
out) — a different hardware config, so the before/after is not comparable. To test `400$` on
silicon you must flash a tape-only build (comment out `TANG_FLOPPY`, rebuild).

Real, still-open Tang symptoms on THIS (floppy) build:
- **`1560&` (floppy DMA boot) loads *something* into memory (correctness unknown), then HANGS.**
  THIS is the real target (matches Ronny's goal: validate floppy in Verilator, then find the
  Tang divergence).
- **OPCOM `#` memory test HANGS** ("used to work" per Ronny 27-JUL). Memory-only, no boot — the
  one remaining candidate for a cache-HIT-gate FPGA regression (H_A). CAVEAT: the nd120-fpga
  skill's [[tang-silicon-latch-divergences]] lists the `#` memory test as a KNOWN PRE-EXISTING
  silicon hang from before the fixes — so do not assume it's new; the ungated build settles it.
- In **Verilator** the same RTL boots the floppy fine (`1560&` -> `TPE>`), and CONFIGURATION /
  CX diagnostics pass — so the floppy failure is FPGA-specific ("works in sim, hangs on silicon"
  = the latch-divergence class; see the nd120-fpga skill TOP LEARNING).

## PHASE 1 — Verilator validation (run first, when the slot is free)

Goal: prove the current fixed RTL still boots floppy AND tape correctly in sim (so the Tang
bug is confirmed FPGA-only, and to rule out that a fix regressed the sim path too).

- **T1.1 floppy `1560&`**: boot `Verilog/runSim/FLOPPY1.IMG`
  to `TPE>` (probe engine `obj_dir_probe_cachefix` or a fresh floppycore build). Already
  demonstrated by the CX/CONFIG runs, but re-confirm on the exact committed RTL.
- **T1.2 tape `400$`**: runSim SD-tape boot (`cd Verilog/runSim`,
  the default `make run` = VERILOG_TAPE=1 SD_STORAGE=1) — does the BPUN load + reach the `#`
  prompt (STERR=0)? This is the sim analogue of the Tang `400$`.
- **T1.3**: backdoor-`examine`/`scanseq` the loaded region in both cases; confirm the bytes
  match the source image (rules out a load-path data bug in sim).
- GATE: both work in sim -> Phase 2/3 (FPGA divergence). Either fails in sim -> fix that first.

## PHASE 2 — Tang `400$` regression (PRIORITY: "no memory loaded now")

The change from "loads then hangs" to "no load at all" points at one of the 3 fixes breaking
the FPGA memory read/write path. Ranked hypotheses:

- **H_A (prime): the MMU cache HIT-gate fix.**
  `Verilog/CPU-BOARD-3202/circuit/CPU_MMU_CACHE_25.v:109-122`
  now drives `CD_15_0_OUT = s_hit ? s_cd_15_0_out : 16'b0`. On silicon `s_hit` (or the cache
  SRAM/`ECD`/`WCA` timing) may differ from sim, so gating the CD bus by `s_hit` could block
  correct memory reads during the tape load -> reads return 0 -> loader writes nothing / wedges.
  **TEST: rebuild the Tang with `-DND120_CACHE_DRIVE_UNGATED`** (the escape hatch already in the
  file) and re-flash: does `400$` load memory again? If YES -> the cache fix is the FPGA
  regression; need an FPGA-safe form (the banner bug it fixes is a sim/functional issue, so a
  Tang build could even ship UNGATED short-term).
- **H_B: latch-divergence (`ifdef VERILATOR_SIM`) in the cache/CD/MAC path.** Audit:
  `grep -rlE "ifdef VERILATOR_SIM" --include=*.v CPU-BOARD-3202 DELILAH-CPU | xargs grep -liE "transparent|latch|posedge|@\(\*\)"` — focus on CGA_MAC / CPU_MMU_CACHE / the CD read path.
- **H_C: trap-vector or CUP fix.** Lower likelihood (trap-vector only changes a spare mux input;
  CUP is status-only) but include in the bisect.
- **Method:** bisect the 3 fixes with per-build defines / reverts, re-flash, retest `400$`. Use
  the Tang on-chip capture to see where `400$` wedges now (CSA stable? memory bus? `s_hit`/`CD`):
  `Verilog/fpga/tang-nano-20k/grant_capture.py` + the probe word in
  `ND120_TANG20K_TOP.v` / `src/tang20k_defines.v` (`TANG_GRANT_CAPTURE`). Compare CSA-freeze point
  to the pre-fix build's "loads then hangs on an instruction".

## PHASE 3 — `1560&` floppy on Tang

- Confirm sim `1560&` loads the CORRECT image (backdoor examine the loaded region) as the golden.
- Tang `1560&` capture: what actually landed in memory + where it hangs; diff vs sim. Floppy on
  the Tang is newer (validated in Verilator only per the skill / [[floppy-syncread-refactor]]);
  it may have FPGA issues in the FLOPPY-DMA / SD-FAT path independent of the CPU.

## Cross-cutting

The #1 cause of "boots in Verilator, hangs on Tang" is the `ifdef VERILATOR_SIM` latch/timing
divergence class (nd120-fpga skill). Whatever Phase 2 finds, audit the involved path for a
sim-vs-FPGA branch. Tang serial console = `/dev/ttyUSB1` 9600 8N1; JTAG = `/dev/ttyUSB0`;
attach with `./usb-attach.sh` (usbipd FTDI 0403:6010 busid 3-2).

## Ordering (revised 27-JUL after the `400$` correction)
1. **Verilator `1560&` floppy validation + GOLDEN** (Ronny granted the slot): boot the floppy in
   sim on the current fixed RTL, confirm `TPE>`, and backdoor-capture WHAT it loads into memory
   (the golden). Use the already-built engine (no rebuild → no obj_dir risk). This is the
   comparison baseline for the Tang's "loads something".
2. **Tang `1560&` capture**: on the flashed floppy build, capture what actually landed in memory
   + the CSA freeze point (`grant_capture.py` / probe word), diff vs the sim golden. Split
   "wrong data loaded" from "correct load, CPU wedges after".
3. **`#` memory-test cache check** (H_A, only if worth it): Gowin build with
   `-DND120_CACHE_DRIVE_UNGATED` (clean revert, confirmed `CPU_MMU_CACHE_25.v:119-123`), re-flash,
   re-run `#`. Works ungated → cache fix is the FPGA regression; still hangs → pre-existing
   silicon hang, cache fix exonerated. LONG (~full Gowin build) — do only after 1-2.
4. Cross-cutting `ifdef VERILATOR_SIM` latch-divergence audit on whatever path 2 implicates.
