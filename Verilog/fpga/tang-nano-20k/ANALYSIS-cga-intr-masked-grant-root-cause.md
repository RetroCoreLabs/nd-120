# ANALYSIS — Tang "masked level-10 grant": root-cause investigation (SOLVED 18-JUL-2026)

> **SOLVED 18-JUL-2026 - kept as the root-cause record.** The root cause was
> found and directly confirmed on silicon (section 3e): a stale-INTRQN panel
> pulse taken as a macro interrupt, reading an empty vector that defaults to
> level 10 - NOT an Am2914 masked grant. The Tang Nano 20K now boots SINTRAN
> III (24-AUG-2026). Trimmed 28-SEP-2026 to the mechanism (1), the root cause
> (3e), the fix (3f) and what was reverted (4); the experiments in between
> (old sections 2, 3, 3b-3d) are in git history. In short: Verilator did NOT
> reproduce the fault (experiment A, `-DND120_PROBE_VEC17` in `runSim`), and
> the `TANG_GRANT_CAPTURE` on-chip capture on silicon (experiment B1,
> `grant_capture.py`) caught the cause-less dispatch to CS 000017 at step 18
> of a single-step from P=0.

**Full path:** `Verilog/fpga/tang-nano-20k/ANALYSIS-cga-intr-masked-grant-root-cause.md`
**Status:** ROOT CAUSE FOUND AND CONFIRMED ON SILICON (18-JUL, section 3e). An
earlier trap-side guard was written and then **REVERTED** (18-JUL) at Ronny's
direction — it treated the symptom, not the cause, and it deviated from the
schematics; the real cause is in section 3e.

---

## 1. The mechanism (measured + source-verified — this part stands)

The Tang "masked level-10 grant" is a **cause-less trap dispatch**, not an Am2914
grant:

- `INTRQN` (CGA/INTR p.74, `CGA_INTR.v` `MEMORY_2`) = a one-MCLK-delayed register
  of `PAN | IRQ` (D = NAND(IRQN,PANN); async clear CLIRQN; **no hold feedback** —
  schematic-confirmed by Ronny 18-JUL).
- The trap break trigger is `IFETCH & INTRQ` (CGA/TRAP/BRKDET p.103, `INTR` NAND —
  schematic-confirmed: exactly two inputs).
- The panel-vs-macro classification is the 5-input NAND (CGA/TRAP/TVGEN p.104,
  `GATES_6` → `L3V0_FF`): inputs VTRPN, IFETCH, INTRQ, PAN, DSTOPN —
  schematic-confirmed: exactly five, **no IRQ/claim input**. PAN up → trap vec 16
  (panel); PAN down → trap vec 17 (macro interrupt).
- Trap vec 17 microcode does `PIC,RVECT` (CS 000017). With nothing claiming the
  read returns 0, and the interrupt vector table `ITSRV` (CS 003740) maps **entry
  0 → Q=12 octal = level 10**.

So a dispatch taken off the **lagged** INTRQN, after its cause dropped, is
classified "macro interrupt" (live PAN=0), reads an **empty** vector = 0, and
switches to **level 10**. Measured signature (`piltrace.log`): PIL 0→10, PIE=0,
P never advanced (instruction stream not involved). A *genuinely pending* level-10
would read 010 octal → level 14, not 10 — confirming the read was empty.

**Schematic validation (Ronny, 18-JUL):** all four transcription points above
(TBUF inverters, TVGEN 5-input NAND, BRKDET INTR NAND, INTRQN FF D-cone) match the
original DELILAH sheets. **The window exists in the design as drawn.** So the trap
logic is NOT where a transcription bug lives.

## 3e. ROOT CAUSE — DIRECTLY CONFIRMED ON SILICON (18-JUL)

Via the on-chip capture (grant_capture.py, TANG_GRANT_CAPTURE), stepping to the
hang and reading a debug word = {PAN, IRQ, INTRQ, PICV, MIREQ}. Measured
sequence around the dispatch:

    PAN=1 IRQ=0 INTRQ=1 PICV=0 MIREQ=0   <- PAN pulses; INTRQN asserts (from PAN)
    PAN=0 IRQ=0 INTRQ=1 PICV=0 MIREQ=0   <- PAN GONE, INTRQN STILL asserted = THE LAG
    PAN=0 IRQ=0 INTRQ=0 PICV=0 MIREQ=0   <- INTRQN clears
Summary: PAN pulsed=True, IRQ never asserted, INTRQ asserted, max PICV=0 (empty),
MIREQ never nonzero.

**THE ROOT CAUSE (proven, not inferred):**
1. A **PAN (panel request) PULSE** sets the INTRQN flip-flop (CGA_INTR.v
   MEMORY_2, `d = PAN | IRQ`). PAN here is a panel/PRQ pulse from console
   activity (the MOPC/PRQ output path - NOT a maskable interrupt).
2. INTRQN is a **registered snapshot** (holds a full MCLK period, cleared only
   by CLIRQ), so it **OUTLIVES the PAN pulse** - the measured `PAN=0 INTRQ=1`.
3. There is **NO real interrupt**: IRQ never asserts, MIREQ/IREQ are empty, PICV
   is always 0 (measured across the whole window and in two prior dedicated
   captures).
4. The trap unit fires on the **stale INTRQN**, but the panel-vs-macro
   classifier (CGA_TRAP_TVGEN_P2 GATES_6) uses **live PAN**, which is now 0 ->
   it dispatches a **MACRO interrupt (trap vector 17)**, not a PANEL interrupt
   (vector 16).
5. Trap-17 microcode does `PIC,RVECT` -> reads the empty vector `{PD=0,PICV=0}`
   = R1=0 -> `ITSRV+0` -> **PIL level 10** (Agent C's table; level 10 is the
   default decode of "grant with empty vector").

So the "masked level-10 grant" is **a stale-INTRQN panel pulse mis-taken as a
macro interrupt, reading an empty vector that defaults to level 10.** It is NOT
an Am2914 masked grant, NOT a real level-10 source, NOT metastability
(deterministic; it is the registered-snapshot lag), and NOT IOXERR/RTC/conkick
(all disable-tested with no effect - because the PAN source is the general
panel/PRQ path, confirmed by TANG_NO_PAN breaking the console entirely).

**Why Verilator never shows it:** the lag (INTRQN holding after PAN drops) exists
in the RTL in both worlds, but on silicon the real cadence (9600-baud console
PRQ pulses, real MCLK/TCLK phases) deterministically lands a PAN-pulse's lag
window on the JAZ instruction fetch (step 18, CSA 00214 CONTINUE). Zero-delay
Verilator's aligned delta-cycles + fast-UART cadence never place the lag window
on an instruction boundary, so the stale-INTRQN is always re-evaluated
consistently. This is the "real-timing effect zero-delay sim collapses" class.

**Structural fault (Agent D):** INTRQN (the grant, latched) is not interlocked
with the live panel-vs-macro classifier or the live vector read (PICV, strobed
by S). The fix must make the trap act on a cause that is still valid - which is
exactly what the reverted CGA_TRAP guard (`intrq & (pan | IRQ)`) did. Fix
options (Ronny's call, faithfulness constraint):
- (a) the CGA_TRAP live-cause guard (schematic deviation, directly blocks it);
- (b) latch PAN alongside INTRQN so trigger and classifier use one snapshot
  (a faithful interlock);
- (c) address the un-original console PRQ/conkick pulse generation so panel
  pulses are not manufactured the way the real 68705 never did.

## 3f. The real MC68705U3 behavior + the FAITHFUL FIX (18-JUL)

Agent read the U3 firmware analysis AND the sheet-40 schematic
(`Code/68705/3202D_PANCAL_SHEET40.png`). Findings:
- STAT3 = PB4, a firmware-HELD LEVEL: set at panel-command completion, cleared
  at idle, ACKed by the CPU reading PANS (`TRA PANS` / EPANS/MIPANS). Not a
  hardware one-shot; the DGA A282/A283 turns its rising edge into PRQ.
- The 68705 is a command/response SLAVE: it raises STAT3/PRQ ONLY as the tail of
  an LDPANC command the CPU itself issued. Its timer/RTC ISR raises no CPU
  attention.
- **At cold start it raises NO panel request** (boot sets PB4=0, idle loop keeps
  it low).
- **It has no connection to the console UART** - a console output character never
  touches it and would never toggle STAT3.

CONCLUSION: the recreation's `conkick` (IO_37.v: pulse STAT3 once per console-TX
character) is **un-faithful** - it manufactures PRQ->PAN edges the real chip
never generates, including at cold start. Those spurious PAN pulses are what the
CGA_INTR/CGA_TRAP INTRQN lag mis-dispatches as a phantom macro-interrupt ->
level 10. So the phantom grant is, in normal (free-run) operation, an
**emulation artifact of the conkick.**

FAITHFUL FIX (prototype, 18-JUL): IO_37.v now drives STAT3 from real panel
activity only (IO_PANCAL) by DEFAULT; the old console-speedup conkick is behind
opt-in `ND120_CONKICK_CONSOLE_SPEEDUP` (default OFF). This matches the real
68705: STAT3 low at cold start and during console I/O. Cost: OPCOM console
output reverts to the slower RTC-tick pacing (the conkick's original purpose) -
the correct place to speed console output is the console/UART path, which on
real hardware does NOT go through the panel; that is a separate follow-up.

VALIDATION (must be FREE-RUN, not single-step): single-stepping injects its own
panel Stop/Continue PAN pulses, so it cannot test the conkick fix. A fresh
free-run cold start (400$ autostart, or MACL+P=0+run) has no panel-step ops, no
console output yet, and no RTC tick in the first ~tens of us - so with the
conkick gone there is no PAN pulse at the P=21 hang point. If 400$ now boots
past the hang, the conkick was the free-run trigger and the faithful fix cures
the real-operation failure.

RESIDUAL / belt-and-suspenders: the INTRQN lag (a real RTL structural bug, see
3e) still makes ANY brief PAN pulse (a legitimate panel op, an RTC tick landing
on a fetch) potentially fatal. For full robustness, ALSO add the interlock so
the CGA_TRAP panel-vs-macro classifier and the INTRQN trigger use one consistent
snapshot (or hold PAN as a level like the real STAT3). The faithful STAT3 fix
removes the un-original trigger; the interlock hardens against legitimate ones.

## 4. What was reverted (for the record)

The trap-side guard `INTRQ := INTRQ & (PAN | IRQ)` in CGA_TRAP (+ IRQ port wired in
CGA.v, + tb golden) was implemented, passed all sim gates, then **reverted** — it is
a schematic deviation and a symptom patch. The three files are back to their
committed state (verified `git diff` empty). The S3 HVE/LVE int-req-enable gate in
`CGA_INTR_CNTLR_IRGEL_HIRL.v` / `_LORL.v` was committed later (in `cd9b94f`,
23-JUL-2026); it is Am2914-ground-truth-correct but is NOT this bug's cure (the
claim was already empty).
