# Instruction-verify campaign - ND-120 RTL vs ND-110 golden traces

Goal: validate and bug-fix ALL macro instructions by comparing our ND-120
RTL (Verilator, runSim) against reference traces from a known-good ND-110
emulator running Norsk Data's INSTRUCTION-B verify program (204384B).
One gate per instruction group: `make test-instr-<AREA>` in `Verilog/`
(heavy, ~15-25 min each). These are NOT in `tests/run_all_tests.sh`; the
validated set is `INSTR_AREAS` in `Verilog/Makefile`.

## Reference material (delivered by the ND-110 side)

- Golden traces: `$ND_REPOS/ND110Compile/traces/TRACE-INSTRUCTION-VERIFY-<AREA>.md`
  (AREA = ARGUMENT, MEMORY-REFERENCE, SEQUENCE, REGISTER-OPERATIONS,
  BIT-OPERATIONS, SHIFT-INSTRUCTIONS, 32-BITS-FLOATING, 48-BITS-FLOATING,
  PRIVILEGED, BYTE-STRING, ND100-24BIT, BCD, ND100-CX, STACK).
  Regenerated on the ND-110 side with `dotnet test --filter "Name~GenerateTrace"`.
- ND-110 microcode listing: `$ND_REPOS/ND110Compile/ND110Compile/uCode/ND-110-RASK.LISTING.TXT`
- ND-110 symbols: `$ND_REPOS/ND110Compile/ND110Compile/uCode/ND-110-RASK.SYMBOLS.TXT`
- ND-120 microcode listing: `$ND_REPOS/ND110Compile/ND110Compile/uCode/ND-120-DELILAH-K.LISTING.TXT`

## Trace format (per golden file)

- Program started with `0!`, then the AREA command typed at the `>` prompt.
- One `###` section per macro instruction: `addr : opcode` + full register
  state at fetch (octal): A D T X B L P STS, current-level scratch R1-R7,
  Am2901 Q register, ALU output latch F, GPR shift register, loop counter LC,
  and PIL (the running interrupt level).
- Micro rows: `csar | symbol | changed-registers | RASK source`. Control-store
  addresses are ND-110 RASK addresses; the SYMBOL (exact label or LABEL+n
  octal offset) is the portable key into our DELILAH microcode.
- Detail arms at the first macro instruction on a test level (PIL 1-9),
  records 400 instructions; console preamble is skipped.

## Comparison rules (as calibrated 12-JUL-2026)

1. The instruction-correctness gate is the **architectural registers**
   `A D T X B L P STS` plus the instruction stream (`addr : opcode`, PIL).
   Those are the ND-100/110/120 programmer-visible register set; any mismatch
   is a HARD failure (the instruction executed wrong).
2. `R1-R7, Q, F, GPR, LC` are **microcode working state**, NOT architectural
   (the ND model has no R1-R7). Both microcodes normally leave the same values
   there, so the comparator still checks them - but our ND-120 runs a
   front-panel display-refresh routine (`DISPL/DSPLY`, which loads the constant
   `174001` into a WRF slot, then `LDPANC`) between instructions that the
   ND-110 emulator's panel does not trigger. That legitimately perturbs the
   scratch registers, so a scratch-only divergence is reported as a non-fatal
   **warning**, never a gate failure.
3. Both emitters log **between-instruction service** as macro rows: the MOPC
   panel poll (`PANEL/MACRI/PANVC`) and the `WAIT` instruction's timing-
   dependent wait-for-interrupt loop (`WAIT1/PVCHK/WAIT2/CHKIT`, opcode
   `151000`). The two disagree on whether each interlude gets its own row - our
   boundary detector folds the WAIT loop into the neighbouring instruction,
   golden logs it standalone, and WAIT spins a timing-dependent number of
   times. The comparator **resynchronises**: it skips service-led rows on
   whichever side is ahead and matches real instructions by (addr, opcode, PIL).
4. Micro rows compare PER-SYMBOL (what each routine step changes), never by
   control-store address - the two microcodes place routines differently.
5. Level-13 clock interrupts interleaved in the trace are real and
   timing-dependent - filtered into a separate count, never a divergence.

## Symbol map (this directory)

- `gen_mic_map.py` - regenerates the map from the two listings.
- `ND110-ND120-MIC-MAP.md` - human document (GENERATED - do not hand-edit).
- `nd110_nd120_mic_map.tsv` - machine-readable: symbol, nd110 addr,
  nd120 addr, status (same | moved | ocr:... | only-110 | only-120).

Map results: 1067 symbols in both microcodes (612 same address, 455 moved),
25 OCR spelling twins reconciled (the ND-110 listing is OCR-sourced: 0/O and
1/I/L confusions - trace tooling must treat twin spellings as one symbol),
10 genuinely ND-110-only, 14 genuinely ND-120-only (extra console/BAUDS/TRM
words). Every symbol seen so far in the golden traces exists on our side.

## Running a compare (the recipe)

```bash
# 1. build runSim with the trace emitter (FF mode, public signals)
cd Verilog/runSim
make compile USE_LATCHES=0 EXTRA_VDEFINES="--public-flat-rw" EXTRA_CFLAGS="-DND120_TRACE_VERIFY"

# 2. boot INSTRUCTION-B from tape 400 and type the area command
printf '400$ARGUMENT\r' | ND120_MAX_CNT=400000000 ND120_STDIN_GAP=300000 \
  ND120_TVERIFY_OUT=trace_nd120_argument.md \
  ND120_TVERIFY_SYMS=../tests/instruction-verify/nd120_symbols.tsv \
  ./obj_dir/VND120_TOP > run.log 2>&1

# 3. compare against the golden trace
python3 ../tests/instruction-verify/compare_trace.py \
  $ND_REPOS/ND110Compile/traces/TRACE-INSTRUCTION-VERIFY-ARGUMENT.md \
  trace_nd120_argument.md
```

The emitter arms at the first PIL 1-9 macro instruction and records 400
(ND120_TVERIFY_MAX overrides). Boundary detection uses the CPU FETCH strobe -
the ND-120 CONTINUE dispatch does NOT visit csa 0 (only level switches do),
so csa-0 boundaries miss most instructions.

## Calibration findings (12-JUL-2026)

Calibrated against ARGUMENT, STACK, BYTE-STRING, MEMORY-REFERENCE, SEQUENCE.
Result: **every instruction executes correctly** - the architectural registers
and instruction stream match golden exactly on all five areas. All observed
divergences are trace/emitter artifacts, not CPU bugs:

- **Panel display-refresh scratch.** Between instructions our ND-120 runs the
  octal front-panel display routine (`DISPL -> DSPLY` at csa 002500-002503,
  writing the hard-coded `174001` panel constant, then `LDPANC`). It borrows
  WRF/ALU scratch (`R4`, `Q`, `F`, `GPR`, `LC`), so those carry panel noise in
  the following instruction's snapshot. In byte-string `R4` is stuck at the
  panel constant `174001` for the whole run vs golden's `000000`; in
  memory-reference `Q` shows 17 such perturbations. The ND-110 emulator's panel
  does not raise the refresh (its `MIPANS`/`F15` path stays clear), so golden
  never runs it. These are non-fatal scratch warnings.
- **WAIT (opcode 151000) row asymmetry.** WAIT executes on both machines (its
  `WAIT1/CHKIT` microcode runs 1000+ times in ours), but our macro-boundary
  detector (P+GPR change) does not fire inside the wait loop, so ours folds
  WAIT into the previous instruction while golden logs it as a standalone row.
  Handled by resync, not a bug.
- **LC width.** Golden logs a 16-bit software count; our hardware loop counter
  is 6 bits (`{ICD5,ICD4,LC3:0}`) - comparator masks LC to the low 6 bits.
- **Preamble init.** `R7` and level-0 `D` differ only at their first-seen
  baseline (their emulator loads BPUN + `0!`; we boot the real `400$` MOPC
  path). Benign while neither trace writes them; the comparator's baseline
  tracking passes them.
- `F` (ALU output latch) lands one micro-row later than golden's combinational
  F - the default gate runs with `--ignore-regs F`.

Row counts: ours is shorter than golden's 400 because our normalization folds
service interludes and merges EXR sections; a fully-matching aligned prefix
(>=300, or the whole of the shorter trace) is a pass.

## Status

The live per-area status is [CAMPAIGN-STATUS.md](CAMPAIGN-STATUS.md). This
README keeps only how the gate works.

What the automated gate checks: `run_area_test.sh` compares the first 400
test-level instructions of an area against the golden (architectural registers
A D T X B L P STS + instruction stream). It does not run the area to its own
`== END OF TEST ==` and does not count the area's error lines. A missing golden
file is a FAIL (since 28-SEP-2026; it used to print a PASS without testing).

Coverage note: our emitter double-logs EXR (executed instruction as a second
same-address row) and logs panel interludes, so to cover the golden's 400 unique
test-level instructions we run with ND120_TVERIFY_MAX=460 (~440 rows after
normalization); the extra tail is harmless. A passing area typically also
shows ~25-37 non-fatal `Q` scratch warnings (panel display-refresh noise).

Arming: since the ND-110 side regenerated the goldens (~19:00 12-JUL-2026) the
14 area traces arm on the first test-code-region fetch at PIL 0; RUN arms
strictly at the first PIL 1-9. Our emitter matches each golden's window via
`ND120_TVERIFY_ARM_ADDR` (`run_area_test.sh` reads the golden's first `### #1`
address).

Gates: `make test-instr-<AREA>` runs one area; `make test-instr` runs the
`INSTR_AREAS` sweep (13 areas); `make test-full` runs ARGUMENT as a smoke gate.
