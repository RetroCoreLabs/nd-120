# Known-benign differences: ND-120 trace vs nd100x oracle trace

Every entry here was found by a comparison run, explained, and then suppressed
in the tooling. A difference NOT in this list is a candidate bug. Anything added
here needs a demonstrated reason - never a hand-wave.

Tools: `lockstep.py` (windowed, timing-tolerant) and `ctxdiff.py`
(context-matched) - both in the shared analysis folder.

---

## B1. Different boot mechanism
The oracle's `--boot=wd` loads 1K words **straight into core 0**; the ND-120
loads through the **real card** (`20500&` -> microcode -> IOX). At bootstrap
entry the card state therefore differs:

```
  ND-120 status 060010  (on-cylinder + card-id + finished)
  oracle status 020000  (card-id only)
```

First divergence at instruction ~2,037, and the machines never re-converge at
instruction level. Ours is arguably the more faithful behaviour.
**Suppression:** start comparisons after this point (landmark anchoring).

## B2. The oracle's disc completes instantly
Its DMA/transfer has ~zero latency, so its driver polls the Winchester status a
handful of times where ours polls hundreds, and it re-enters wait loops far
fewer times. Same code, different iteration count.
**Suppression:** fold repeated LOOP CYCLES (not just repeated rows - a disc
wait is a multi-row cycle); and the discriminator "does the oracle EVER execute
this address".

## B3. Interrupts land at different instants
RTC (PIL 13), disc (PIL 11), terminal (PIL 10/12) fire wherever they fire. The
same program interrupted at a different instruction is not a divergence. Left
unfiltered this alone produced ~157 false hits, because "the next traced row"
was often a handler entry.
**Suppression:** drop PIL>=10 rows; take "next PC" only at the SAME level.

## B4. Our emitter double-emits some instructions
MEASURED: **586 consecutive-duplicate rows per 400,000 in the ND-120 trace,
ZERO in the oracle's.** The `ND120_INSTR_TRACE` boundary rule's second clause
(dispatch through microcode address 0) fires an extra time for some
instructions - worst case `046000` (`LDA ,X 0`) at `060622`, doubled 531 times.
Left in, it makes `next_pc == pc` and fakes a divergence.
**Suppression:** drop a row identical in (PC, opcode) to its predecessor.

## B5. The trace prints P-1, and OP=000027 is the trap signature
`ND120_TOP.v` emits `(w_itr_p - 16'd1)` as the PC. For normally-retired
instructions that IS the instruction address, but when a trap is taken right
after a jump the row shows `target-1` with the trap's stale opcode. **All 167
rows preceding a PIL-14 entry in one run carried `OP=000027`.** This faked an
entire bug ("indirect JPL lands one word early") for hours.
**Suppression:** never read a row whose successor is a PIL-14 entry as an
executed instruction.

## B6. Register columns differ at reset, and STS formatting differs
Uninitialised A/D differ for the first ~3 instructions; the oracle prints STS
in a different format (`1000` vs `000177`).
**Suppression:** compare PC and opcode only.

---

## Comparison hygiene (learned by getting each one wrong first)

* **Match invocations, not positions.** A routine entered many times with
  different contexts looks divergent if you line up call 7 against call 3. The
  `032066` "branch divergence" evaporated this way: in the SAME context
  (`L=153034, X=012276`) the oracle takes the same branch we do. Key on
  (PC, L, B, X).
* **Anchor on a common event, not a row index.** We execute ~1.5x more
  instructions, so the same raw row number is a different point in the boot -
  measured 0% alignment at every fixed skip. Use the control-register write
  (IOX `164505`) as the common clock.
* **Compare equal WORK, not equal rows.** 60k raw rows collapsed to 2.1k of
  work on our side and 28.7k on the oracle's.

## B7. Our emitter emits the EXR'd instruction as an extra row

`EXR` (execute the instruction held in a register, opcode `140650` for A)
produces TWO rows in the ND-120 trace and ONE in the oracle's:

```
  ND-120:  043067 140650 A=174206     <- the EXR itself
           043067 174206 A=174206     <- extra row; the "opcode" IS the A value
           043070 013011
  oracle:  043067 140650 A=174206
           043070 013011
```

This is deliberate in `ND120_TOP.v`, whose own comment says dispatches through
microcode address 0 - "a level switch, or an EXR'd instruction" - are a trace
boundary. The oracle does not do it.

**Effect if unfiltered:** every EXR looks like "we repeat the PC, the oracle
advances". With a tight context key (PC,L,B,X,A,D) over 1,054,254 shared
contexts, **all 25 visible differences were this artifact and nothing else.**
**Suppression:** treat `next_pc == pc` where the next row's opcode equals the
register value as an EXR emission, not a control-flow difference.

## B8. nd100x updates PGS only on a fault

nd100x updates PGS ONLY on a fault (all four `UpdatePGS` call sites in
`src/cpu/cpu_mms.c` are error paths); the real ND-120 PGS follows every
VACC-qualified access. A PGS value that differs between the two traces
outside a fault is expected. (Recorded 23-AUG-2026 in a retired Tang plan,
git `043c460`; not re-checked against nd100x since.)

## Note on key tightness - it cuts BOTH ways

A tight key removes false positives but can also HIDE real differences: the
`047266` one-in-2049 wrong-instruction-fetch shows up with the loose key
(PC,L,B,X) and NOT with the tight one, because with A and D included that
context is no longer shared between the machines. Run both, and treat
disagreement between them as information, not noise.
