# Retracted claims

Statements that were written down as fact in this repo, believed, acted on —
and later shown to be wrong.

## Why keep a list of things that are not true

A corrected claim does not stay corrected. It survives in an old handoff, an
old comment, a summary of a summary, and comes back months later sounding
authoritative. Every entry below cost real time *twice*: once when it was
believed, and again when it had to be disproved.

If you find one of these claims asserted anywhere in the tree, it is stale.
Fix it and note it here.

## Format

Each entry says what was claimed, why it was believed, what is actually true,
and what disproved it. "What disproved it" is the important column — a
retraction with no evidence behind it is just another claim.

---

### MACLK is the "Memory Access Clock"

- **Claimed in:** `PAL_44307C.v` port comments, `CPU_CS_ACAL_17.v` header, and
  several docs, for over a year.
- **Why believed:** the name. Nobody traced it.
- **Actually:** MACLK is the **micro-address latch strobe**. It has nothing to
  do with memory cycles. Its only consumer on the whole board is the
  control-store address latches in `CPU_CS_ACAL_17` (CHIP_30H 74373 pin C,
  CHIP_31F AM29841 pin LE), reached via `CPU_15` → `CPU_CS_16`.
- **Disproved by:** tracing every consumer of the net; all three of the PAL's
  product terms latch whatever is on MA. Confirmed against the drawing by
  Ronny, 08-AUG-2026.
- **Cost:** most of a day of the TRA CS investigation searched the memory path.

### MCLK is the "Main Clock" / "Master Clock" / "Memory Clock"

- **Claimed in:** `PAL_44307C.v`, `CYC_36.v`, `CPU_15.v`, `CGA.v`, several docs.
- **Actually:** the **microcycle clock**. Its PAL equation contains *only* RWCS
  terms, so outside a RWCS cycle it collapses to plain TERM — one pulse per
  microinstruction cycle, stretched during RWCS.
- **Disproved by:** reading the equation. The PAL is named CYCLK on the board.
- **Corrected:** 08-AUG-2026.

### "During execution, MACLK = 1 always (TERM_n = 0), so LUA = CSA with no delay"

- **Claimed in:** `CPU_CS_ACAL_17.v` header comment.
- **Actually:** MACLK pulses once per microcycle. The conclusion it supported
  (LUA must track CSA with zero latency) happens to be correct, but for a
  different reason — LUA feeds the control store combinationally, so a
  microcode jump must read the target's word in the same cycle the address
  changes.
- **Disproved by:** measured in the waveform; MACLK goes low mid-cycle on
  ordinary microwords. Reproducible now with
  `CPU-BOARD-3202/circuit/sim :: make test-cycle-timeline`.
- **Corrected:** 08-AUG-2026.

### "A 1-cycle LUA lag on FPGA is acceptable — ILA-confirmed"

- **Claimed in:** `CPU_CS_ACAL_17.v`, FPGA-mode branch.
- **Actually:** the lag corrupted CSBITS on microcode jumps and **was** the Tang
  Nano 20K boot hang (wedge at microcode 06000, STZ→CONT). Measured on silicon:
  `CSBIT_11_0 = 0xC00`, `s_jmpaddr = 16000` instead of `0145`.
- **Disproved by:** root-caused and fixed 19-JUL-2026 — the FPGA branch is now a
  synthesizable transparent latch (mux + hold-FF), matching the original
  74373/AM29841 chips.
- **Regression:** `sim/CPU_CS_ACAL_17_tb.v` asserts zero-latency transparency.

### "CPU self-test: 7 of 14 areas pass"

- **Actually:** the self-test passes clean — **0 execution-phase STERR visits**.
- **Disproved by:** the `ND120_COUNT_STERR` probe. Note the trap: the WCS loader
  walks past the STERR address once during loading, so only execution-phase
  visits count.
- **Corrected:** before 13-JUL-2026.

### "Neither ECSL nor RWCS ever assert" (control-store readback)

- **Claimed in:** `CPU_CS_RWCS_tb.v` header, from CSV trace analysis.
- **Actually:** both assert correctly, and the right control-store word reaches
  the CPU's IDB for exactly the two cycle states `PAL_44305D` intends.
- **Disproved by:** the CSV sampler in `nd120_probe.py` takes **one settled
  sample per tick** and is therefore blind to anything happening within a cycle
  state. Three separate conclusions from that sampler had to be retracted.
- **Lesson:** use `Verilog/sim/wq.py`, which prints every transition, or the
  microcycle benches, which run the real PALs. Do not draw timing conclusions
  from a tick-sampled CSV.
- **Corrected:** 08-AUG-2026.

### "The control-store word must be on the IDB at the TERM edge"

- **Claimed in:** `CPU_CS_RWCS_CYCLE_tb.v` header, and used to steer the whole
  TRA CS search on 08-AUG-2026. The reasoning was: the A register is written by
  ALUCLK, `CYC_36.v:365` makes ALUCLK fire only at TERM, and the IDB-to-register
  path is combinational - so the word must survive until TERM.
- **Actually:** the design deliberately moves the micro-address on before TERM.
  `PAL_44307C`'s own MCLK comment says so - "the control store address to be
  [read] is presented onto MA. THEN the address of the control store location to
  be executed is presented". MA is a combinational mux (`CGA_MIC_IPOS.v`), LUA
  follows it while MACLK is high, and the writable control store is addressed
  solely by LUA (`CPU_CS_WCS_21_22.v:73`). So the word is gone by TERM *by
  design*, and something must capture it during the two-state EWCA/ECSL overlap.
- **Disproved by:** the microcycle timeline (`make test-cycle-timeline`), which
  shows ECSL stays asserted right through to TERM - the read window never closes
  early, contradicting the premise - while EWCA drops at state 1100 and MACLK
  does not fall until 1111.
- **Also retracted with it:** "ECSL drops before TERM". It does not.
- **Corrected:** 08-AUG-2026. The follow-on question (what captures the IDB
  during the EWCA/ECSL overlap?) is answered: the control-store read path
  captures the word on the falling edge of ECSL~ and holds it on the IDB until
  TERM. That capture was missing from the RTL and was added the same day
  (`CPU_CS_TCV_20.v` header, "root cause of TRA CS returning 000000";
  guarded by `test-cs-rwcs` and `test-cs-rwcs-cycle`).

### "PAL_44307C's fourth MACLK term is an OCR artefact"

- **Claimed:** briefly, on 08-AUG-2026 - that `+ RWCS * CC2 * /CC1`, annotated
  "TURNED OFF", was a commented-out line whose marker the OCR had dropped (the
  same failure mode as the documented 44601B `/CGNTCACT` slash-drop).
- **Actually:** false. `DesignDocuments/PAL-Code/IMG/44307C.png` shows the term
  live and uncommented. `PAL_44307C.v` matches the listing exactly.
- **Disproved by:** reading the scan.
- **Consequence:** the PAL is faithful and is not the fault. An earlier edit to
  this PAL, made on a hunch, was correctly reverted.

### "The SD-FAT reader can drop long-filename support for free"

- **Claimed in:** the FPGA resource-limit notes, as a way to reclaim LUT4s.
- **Actually:** blocked — `.BPUN` is a 4-character extension, which the 8.3
  short-name path cannot represent.
- **Corrected:** 01-AUG-2026.

### "The ECC controller might be at IOX address 500, not 1540"

- **Retracted by Ronny the same day**, as simply wrong. Recorded because it
  briefly redirected a search.

---

## Adding an entry

When you disprove something the repo asserts:

1. Fix the assertion wherever it appears.
2. Add an entry here, with the evidence that disproved it.
3. If a testbench could have caught it, add the testbench and register it in
   `Verilog/tests/run_all_tests.sh`.

Step 3 is what stops the claim coming back.
