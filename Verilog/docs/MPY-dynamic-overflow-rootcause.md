# MPY "dynamic overflow bit not set" - root cause (12/13-JUL-2026)

Solved 13-JUL-2026. The fix is in `DELILAH-CPU/CGA_ALU/circuit/CGA_ALU_QREG.v`
(MUXQ15 `.D3`, with a comment); the commit history for it was squashed into
`cd9b94f`.

Symptom (from INSTRUCTION-B MEMORY-REFERENCE):
`DYNAMIC OVERFLOW BIT NOT SET. SHOULD HAVE BEEN -> "MPY" FAILED (MPY2OP)`

## Bottom line
A one-input transcription error in the Q register: MUXQ15 D3 was wired to
Q[0] instead of F[0], so every MPY product's low word was 0 and the
+/-32768 boundary overflow was lost. Not an ALU, STS, condition-latch or WRF
problem - those theories were written up here first and then retracted
(see "Retracted theories" at the end).

## How MPY is supposed to set overflow (verified from the DELILAH listing)
`ND-120-DELILAH-K.LISTING.TXT` 11642-11665, multiply loop MPY1/MPY2 (CSA 4424-4434):
- 004431: `B,R5 ALUF,PASSB ALUD,SRD ... COND,F=0 F,NEXT F,HOLD` — evaluates the
  F=0 condition on the (shifted) multiply result in R5.
- 004432: `B,R4 ALUF,ZERO ALUD,B ... T,JMP MPY3 CONDENABL` — conditional jump to
  MPY3. NOTE this word's own ALU op is `ALUF,ZERO` (result 0 -> live ZF=1).
- 004433 (fall-through = overflow): `B,R4 ALUF,PASSD ALUD,B IDBS,ARG 60` — load R4=060.
- 004434 MPY3: `A,STS B,R4 ALUF,ORAB ... STS,LO` — STS <- STS OR R4, sets bits
  4 (static ovf, 020) and 5 (dynamic ovf, 040).
Intended: overflow => branch NOT taken => 004433 runs (R4=060) => both bits set.

## What is CORRECT (audited to source, do NOT re-review these for this bug)
- STS register `CGA_ALU_STS.v` ("Page 51"): bit4 = STS4_MUX, bit5 = STS5_MUX;
  CSTS=11 selects D0 (databus FIDBO) for both; bits 4/5 are structurally
  identical on the databus path -> the register cannot set bit4 while dropping
  bit5. STS,LO decodes to CSTS_1_0=11 (verified via CGA_CPU_ALU_CONTR).
- ALU overflow `CGA_CPU_ALU_RALU.v`: s_ovf = signed-add overflow (correct);
  ALU zero-flag ZF polarity correct (ZF=1 iff F==0), via GATES_6/7/11.
- MIC condition select `CGA_MIC_CSEL.v`: F=0 token (0o340) -> TSEL selects the ZF
  mux input (idx6); JMP/NEXT true/false mapping correct. No static wiring bug.

## Final root cause (13-JUL, fixed)

The REAL bug (found via a 10-pair MPY operand sweep, deposited program
MPYSWEEP2.BPUN, results read back from RAM):

  EVERY MPY returned product 000000, and boundary overflows (product exactly
  +32768: 000002x040000, 100000x177777) failed to set the overflow bits.

Root cause: CGA_ALU_QREG.v MUXQ15 input D3 (the qsel=11 shift-right-double
serial input) was wired to Q[0] - a 16-bit ROTATE of Q onto itself - instead
of F[0], the bit leaving the R-side shifter. In the FMU multiply loop
(microword 004427: ALUF,A+B ALUD,SRD ALUM,FMU) the product's low bits stream
from R5 into Q via exactly that input; Q is cleared at MPY entry (004424
ALUF,ZERO ALUD,Q), so with the rotate wiring Q stayed 0 through the whole
loop: product low word always 0, PASSQ (004436) returned A=0, and the SLD
overflow probe (004430, RLI=Q15) lost the +/-32768 boundary bit -> the
INSTRUCTION-B "DYNAMIC OVERFLOW BIT NOT SET" failure. Every other bit of the
qsel=11 mux chain takes Q[i+1] (a true right shift), and the mirror link for
shift-LEFT-double already existed (RLI = Q15 in CGA_CPU_ALU_CONTR GATES_18/40),
which confirms the intent. Schematic reference: CGA page 43 (QREG), MUXQ15.

FIX (one input): CGA_ALU_QREG.v MUXQ15 .D3(s_f_15_0[0]) (was s_q_15_0_out[0]).
Data-path transcription bug - present in BOTH latch and FF modes, no clocks
involved.

VERIFIED after the fix (both USE_LATCHES=0 and =1):
- all 10 sweep products correct (2x037777=077776, 177777x177777=000001, ...);
- overflow bits (Q=020 dynamic, O=040 static) match the nd100x reference
  emulator's MPY rule "abs(result) > 32767 -> set O and Q" on all 10 pairs,
  including product exactly -32768 (fits, but the negate-first microcode
  algorithm still flags it - nd100x does the same);
- boot reaches "#".

SCHEMATIC CONFIRMED (13-JUL, Ronny, CGA page 43): MUXQ15 inputs on the
original schematic are D0=Q15, D1=F15, D2=Q14, D3=F0, mux output to the R81P
A input whose QA output is Q15. The error was in the LOGISIM DRAWING (the
original PDF scan is very unclear at exactly this point), and the generated
Verilog inherited it. The fix (.D3(F[0])) matches the original hardware.

WARNING - REGENERATION HAZARD: Logisim is the source for this generated
Verilog. Until the Logisim CGA_ALU QREG sheet is corrected (MUXQ15 D3 wire:
Q0 -> F0), regenerating CGA_ALU_QREG.v from Logisim will REINTRODUCE this
bug. Fix the drawing before any regeneration.

## How to probe MPY again

- Deposit programs and the run recipe: `runSim/mpy-tests/README.md`
  (`mpycheck.s`, `mpylvl.s`, `mpysweep2.s`; results read back from RAM).
- Microcode-level probe: build runSim with
  `make compile USE_LATCHES=0 EXTRA_VDEFINES="--public-flat-rw" EXTRA_CFLAGS="-DND120_PROBE_MPY"`.
  The `ND120_PROBE_MPY` block in `runSim/Run120.cpp` prints `[mpy]` lines for
  CSA 004425-004435. Start the deposited program from MOPC with `1000!`; both
  input pacing (`ND120_STDIN_GAP=300000`) and `stdbuf -oL` are needed, or the
  `1000!` is dropped and the probe output is not live. `loadfile()` does not
  set P, so MOPC `1000!` is how a deposited program is started.

## Retracted theories (kept so nobody repeats them)

- Condition-latch clock phase in `CGA_MIC_CSEL.v` (CSEL_LATCH): wrong. The
  branch at 004432 was measured correct.
- WRF write-to-immediate-read hazard (004433 R4=060 "one microcycle late"):
  wrong. Two probe errors produced it - the probe read WRF scratch register 8
  as "STS", and the probe window ended before ALU_STS's capture edge. The WRF
  write pipeline is correct.
- Registering the ALU flags (ZF) broke boot and was never the cause.

The full investigation log is in git history.
