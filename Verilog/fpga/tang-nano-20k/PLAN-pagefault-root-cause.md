> # SOLVED 24-AUG-2026 - this document is a HISTORICAL RECORD
>
> The ERRFATAL page-fault investigation this file belongs to is **closed**.
> Root cause: the memory bank was decoded from the wrong side of the bus
> transceiver (`ND3202D.v:533`). On an incoming DMA write the board drives
> nothing and that net idles all-ones, so every transfer decoded to BANK0 -
> disc data landed at the right ROW in the wrong BANK, the CPU fetched zeros
> from a page nothing had written, executed them as STZ and halted in
> ERRFATAL after exactly 143 s on every boot.
>
> **SINTRAN III now boots on the Tang Nano 20K.**
>
> Anything below describing the fault as open, or naming a suspect, is
> superseded. The measured trail and the theories that were REFUTED are in
> `PLAN-pf-campaign-prio.md`; the regression guard is `make test-bdbank`.

# Plan: identify the root cause of the page fault on the Tang

**Full path:** `Verilog/fpga/tang-nano-20k/PLAN-pagefault-root-cause.md`
**Date:** 21-AUG-2026
**Goal:** determine, from measured silicon evidence alone, why the ND-120 on the
Tang Nano 20K takes a page fault that halts SINTRAN in `ERRFATAL`.

No step in this plan depends on a theory being right. Every step captures facts
and every step has an outcome that kills at least one candidate.

---

## 0. What is ESTABLISHED (measured or read from source)

| fact | how it is known |
|---|---|
| SINTRAN halts in `ERRFATAL`, `IIC 3` (page fault), faulting level 1 | console output, reproduced |
| The running system is SINTRAN **M**, not K | image symbol tables match M06 at 99.5%, K03 at 42.7% |
| `Perror` = the P register of the interrupted level | `MP-P2-2.NPL:396` `A=:PERR` |
| The halting call is `IPAGFAULT`'s ND-500-window branch | `MP-P2-2.NPL:283`, and the ND "Fatal Error routine addresses" document |
| That branch fires when the faulting page == `WNDN5` and `RTREF.N5WINDOW = 0` | same source |
| `WNDN5 = 000760` = **page table 7 (DPIT), page 60** | M06 symbols + `A=:T/\1777=:PVPAGE SH -6 =:PVPIT` |
| `PGF = VACC & ~PT[6] & ~PT[5] & ~PT[4]` | `CGA_TRAP_TVGEN.v:252` |
| The seven trap-vector bits latch on `TCLK` | `CGA_TRAP_TVGEN_P2.v`, DELILAH p.104 sheet 2 |
| `PT_15_9` is a wired-OR; undriven reads all-zero | `CPU_MMU_24.v:217` |
| Our page-table RAM read is SYNCHRONOUS; the real TMM2018D is ASYNC | `Shared/support/TMM2018D_25.v:67` |
| `PGSREG` is wired 1:1, `PGS[n] = LA_21_10[n]` — no bit error | read from the RTL |
| If PT is idle at the capturing edge, a page fault is latched — 49/49 offsets, both build modes | `CGA_TRAP_TVGEN_ptrace_tb.v`, run 21-AUG |
| TPE PAGING passes 11/11 on this silicon | earlier campaign |

## 0b. What is NOT established - do not build on these

- That `VACC` is ever asserted while `PT_15_9` is idle **in the real design**.
- That the fault is spurious at all. It may be a genuine page fault.
- Any count of `PGF` assertions. The only existing number (2.7M) came from a
  probe that counted a LEVEL, not events, and is unusable.
- Any comparison of hardware signals against the C emulator. The emulator has
  no `PGF`, no `TCLK` and no page-table RAM. Only architectural events
  (dispatched traps) are comparable between the two.

---

## 1. THE DECIDING MEASUREMENT: freeze the trap in hardware and read it out

**Question it answers:** at the exact edge that latched the page fault, what
were the inputs?

That single capture distinguishes every remaining candidate without any
inference, because a real page fault and a spurious one look different in the
captured word:

- `PT_15_9` valid with all permission bits genuinely clear -> **real page
  fault**, and the bug is elsewhere (whoever left that PTE unmapped).
- `PT_15_9` all-zero while the page-table RAM was mid-read -> **spurious**, and
  the cause is the sync-read latency against an unqualified `PGF`.
- `PT_15_9` valid and granting -> the trap fired on something else entirely and
  both current candidates are dead.

### What to build

A **first-fault freeze register**: a small block that, on the FIRST latched
page-fault trap, captures a word and then locks until reset. Not a trace
buffer - one sample, one event. It survives the rest of the boot so it can be
read at leisure.

Capture at the `TCLK` edge that sets the vector:

| field | why |
|---|---|
| `PT_15_9` (7 bits) | the entire question |
| `VACC` | was an access even in progress |
| `LA_21_10` (12) | the logical page, and therefore the PIT/page SINTRAN reports |
| `PGS_11_0` (12) | what SINTRAN will actually read back |
| `TVEC_3_0` (4) | which vector was latched |
| `PVIOL`, `RESTR` | was a protect violation also true at that instant |
| page-table RAM chip-select / output-enable | **was the RAM even driving** |
| a free-running cycle counter (24) | when, relative to boot |

Readout: the board already has this pattern. `ND120_TANG20K_TOP.v` carries
`TANG_WD_TRACE_DUMP` and `TANG_GRANT_CAPTURE`, which pack a word and push it out
the console. Reuse that mechanism rather than inventing one, and gate the whole
block behind a new `TANG_PF_CAPTURE` define so no other build pays for it.

**Cost:** roughly 80 flip-flops plus the dump path. One synthesis + flash cycle
(~15 min), then one boot to the halt (25-35 min).

**Why a freeze register and not GAO:** GAO exists and is documented
(`GAO-HOWTO.md`, `src/nd120_tang20k_gao.rao`), but it needs a trigger armed for
a rare event, consumes BSRAM the design is short of, and the capture window is
tiny. The event here is one-shot and self-announcing - the machine halts right
after it. One frozen sample is worth more than a window we may not catch.

### Pass/fail is not the point - the captured word IS the answer

Do not report "the capture worked". Report the field values and which of the
three branches above they select.

---

## 2. IF the capture says SPURIOUS - confirm the mechanism before changing RTL

Two independent confirmations, both cheap, both without a boot:

1. **`VACC` / PT-idle overlap bench.** Instantiate `CPU_MMU_24` with its real
   page-table RAM, run accesses, assert that `PT_15_9` is driven for the whole
   window in which `VACC` is asserted. A failure here is the mechanism, proved
   on the real module rather than on forced inputs.
2. **Rebuild with `TMM_ASYNC_READ`** (the faithful async read already present in
   `TMM2018D_25.v`) and run the same capture in Verilator. If the spurious
   capture disappears, the sync-read latency is confirmed as the cause.
   NOTE: async read breaks BRAM inference, so this is a DIAGNOSTIC build only,
   not a candidate fix.

## 3. IF the capture says REAL page fault

Then the MMU is reporting correctly and the question moves to *why that page is
unmapped*. Next measurement: capture the same word plus the page-table WRITE
history for that entry - which PIT and index were last written, and by whom.

## 4. IF the capture says the trap fired with a granting PTE

Both current candidates are dead. Next measurement: capture `TCLK`, `ETRAP` and
the level-14 entry conditions around the event - the trap was raised by
something that is not `PGF`.

---

## 5. Candidate fixes - NOT to be applied before step 1 reports

Recorded only so the analysis is not lost. Applying any of these now would be
guessing.

| candidate | assessment |
|---|---|
| Qualify `PGF` with the PTE-driver enable | Smallest change. Restores explicitly the invariant the original hardware had implicitly (async SRAM always driving during an access). |
| `TMM_ASYNC_READ` in the shipped build | Faithful, but a combinational-read array kills BRAM inference and the page tables will not fit in LUT RAM on this part. Diagnostic only. |
| Re-phase or delay `TCLK` | Band-aid. `TCLK` clocks seven vector bits and other logic; moving it closes this window and opens others. |
| Replace the wired-OR with proper enables | Good hygiene, does NOT fix this: an unenabled driver still leaves the bus at zero. |

---

## 6. Order of work

1. Build the freeze register behind `TANG_PF_CAPTURE`, with a unit testbench
   proving it captures the right cycle and locks.
2. Synthesize, flash, boot to the halt, read the word out.
3. Report the captured fields. Branch per sections 2-4.
4. Only then touch the design.

**Nothing in sections 2-5 is to be treated as a finding until step 2 reports.**

---

# PHASES AND TODOS

Legend: `[x]` done  `[ ]` not started  **(R)** = needs Ronny  **(C)** = Claude
Cost is wall-clock, not effort.

## PHASE 0 - Fact baseline  `[x] COMPLETE`

- [x] (C) Identify the SINTRAN version actually running -> **M, not K** (99.5% vs 42.7%)
- [x] (C) Establish which symbol list is the resident system -> SYMBOL-2-LIST (41% vs 4%)
- [x] (C) Decode every field of the halt dump
- [x] (C) Find `Perror`'s definition in source -> P register of the interrupted level
- [x] (C) Find the exact `ERRFATAL` call site -> `IPAGFAULT` ND-500-window branch
- [x] (C) Decode `PNUMB` -> bits 9:6 = page table, 5:0 = page; `WNDN5` = PIT 7 page 60
- [x] (C) Read the `PGF` term out of the RTL
- [x] (C) Verify `PGSREG` bit mapping -> clean 1:1, no defect
- [x] (C) Bench: does an idle PT bus at the capture edge latch a page fault -> **yes, 49/49, both modes**
- [x] (C) Confirm PT is a wired-OR that reads 0 when undriven
- [x] (C) Confirm our page-table RAM read is synchronous vs the real async part

## PHASE 1 - Build the capture  `[x] COMPLETE`

- [x] (C) Capture word layout and freeze condition
      (trigger = the `TCLK` edge that sets trap vector 1, ONE shot, then lock)
- [x] (C) Wrote `ND120_PF_CAPTURE.v` - freeze register, behind `TANG_PF_CAPTURE`
- [x] (C) Captures: `PT_15_9`, `VACC`, `LA_21_10`, `PGS_11_0`, `TVEC_3_0`,
      `PVIOL`, `RESTR`, page-table RAM CS/OE, 24-bit cycle counter
- [x] (C) Wired via `CGA.v` + `ND120_TANG20K_TOP.v` reusing the existing
      `TANG_WD_TRACE_DUMP` / `TANG_GRANT_CAPTURE` console-dump pattern
- [x] (C) Confirmed zero cost when off (0 instances vs 5) (define-gated, zero cost when off)

## PHASE 2 - Prove the capture before trusting it  `[x] COMPLETE`

- [x] (C) Testbench: captures the RIGHT cycle (the latching edge, not before/after)
- [x] (C) Testbench: LOCKS - a second page fault must not overwrite the first
- [x] (C) Testbench: survives reset of the surrounding logic
- [x] (C) Testbench: negative control - no page fault, nothing captured
- [x] (C) BOTH modes, 36 checks, 0 failures; results must agree
- [x] (C) Registered in `tests/run_all_tests.sh` (this one passes, so it can go in)

### DESIGN CHANGE DURING PHASE 2 - the first version could not answer

Self-testing the decoder against the EXPECTED word (PT all zero, VACC high, LA
decoding to page table 7 page 60) produced:

    -> consistent with BOTH a real 'page not present' AND an idle bus.
       NOT DECIDABLE without the RAM strobes, which are not routed.

The most likely outcome was the undecidable one. `HAS_PTRAM_STROBES = 0` was
chosen to avoid routing the page-table RAM strobes up through four levels of
hierarchy, and that quietly made the experiment inconclusive.

REPLACED WITH A DISCRIMINATOR THAT NEEDS NO NEW ROUTING: record `PT_15_9` at
the faulting edge AND one capturing edge later.

| PT at the edge | PT one edge later | verdict |
|---|---|---|
| grants (any of WPM/RPM/FPM) | - | trap did NOT come from PGF; both hypotheses dead |
| all zero | GRANTS | entry ARRIVED LATE, trap read an idle bus -> **SPURIOUS** |
| all zero | still zero | entry really is unmapped -> **REAL** |

Word grew 56 -> 78 bits, readout 4 x 14-bit slices -> 6 x 13-bit slices.

### THINGS THAT SILENTLY DELETED THIS BLOCK - all caught, all would have shipped

A build reporting success proves NOTHING about whether the diagnostic is in it.
Three separate mechanisms removed it, each producing a bitstream that flashes
cleanly and streams constants:

1. **Not in the Gowin project file.** `nd120_tang20k.gprj` lists sources
   explicitly; a new file is a BLACK BOX. Caught by `yosys hierarchy -check`.
2. **Two drivers on the shared debug port.** `ND_WD_TRACE_TVEC_CSA` is defined
   BY DEFAULT in `src/tang20k_defines.v:194` and also drives `XMIC_DBG_15_0`.
   Gowin stopped with EX2000. A Verilator lint of `CGA.v` alone MISSED this -
   the conflict only exists at system scope with the real define set.
3. **Dead-code elimination.** The TX mux only selects `dbg_txd` for a fixed
   list of capture defines; `TANG_PF_CAPTURE` was not among them, so the dump
   never reached a pin and everything feeding it was removed.

THE CHECK THAT WORKS: search the post-synthesis netlist
`build/nd120_tang20k_build/impl/gwsynthesis/*.vg` for the block's signals, and
compare the register count against a build without the define. Present = +174
registers. Absent = the only trace is a file-path comment.

## PHASE 3 - Get the number off the silicon  `[x] COMPLETE 21-AUG-2026`   ~15 min build + 25-35 min boot

- [ ] (C) Synthesize with `TANG_PF_CAPTURE`; check resource delta is small
- [ ] (R) Flash the Tang
- [ ] (R) Boot to the `ERRFATAL` halt
- [ ] (C) Read the frozen word out over the console
- [ ] (C) Report the FIELD VALUES - not "the capture worked"

## PHASE 4 - Branch on what the word says  `[x] ANSWERED`

**The captured word says: REAL page fault, at page table 13 (X5DPT) page 60.**

```
LA_23_10 = 001360   PT@fault = 0000000   PT before = 0110110   PT after = 0000000
VACC = 1  TVEC = 1  PVIOL = 1        census: 57 faults, none at 0o760
```

PT was granting one edge earlier and all-zero at the fault and after, VACC high,
word internally consistent. Per the branch table this is a REAL fault and the
MMU is reporting it correctly.

**But it is NOT the address SINTRAN acts on.** `IPAGFAULT` takes the ND-500
branch only for `PNUMB == 0o760`; with 0o1360 the compare would not match and
the fault would fall through to `ACTMON`. It halted, so SINTRAN read 0o760.
Both PGS paths are 1:1, so the value is not corrupted in transit - **PGS is
read STALE**, consistent with its documented behaviour of holding the last LA
presented while VACC was high.

### PHASE 4b - the one unmeasured link  `[ ]`

- [ ] Capture PGS AT THE MOMENT the handler reads it (EPGS asserted) and
      compare against the frozen faulting LA. Difference proves the overwrite.
- [ ] Establish why the machine translates through table 13 (X5DPT, the ND-500
      name/standard-domain table) on a machine with no ND-500.

## PHASE 4 (original branch table, kept for reference)

- [ ] (C) `PT` valid, permissions genuinely clear -> **REAL page fault**.
      Next: capture the page-table WRITE history for that entry (which PIT,
      which index, last writer).
- [ ] (C) `PT` all-zero while the RAM was mid-read -> **SPURIOUS**. Go to Phase 5.
- [ ] (C) `PT` valid and granting -> **both candidates dead**. Next: capture
      `TCLK`, `ETRAP` and the level-14 entry conditions; something other than
      `PGF` raised the trap.

## PHASE 5 - Only if Phase 4 says SPURIOUS  `[ ]`

- [ ] (C) Confirm on the real module: instantiate `CPU_MMU_24` with its page-table
      RAM and assert `PT_15_9` is driven for the WHOLE window `VACC` is asserted
- [ ] (C) Diagnostic build with `TMM_ASYNC_READ`; spurious capture must disappear
      (DIAGNOSTIC ONLY - async read kills BRAM inference, cannot ship)
- [ ] (C) Implement the fix: qualify `PGF` with the PTE-driver enable
- [ ] (C) Re-run the Phase 0 bench - the 49/49 failure must become 0/49
- [ ] (C) Re-run `make test` unit suite + instruction-verify
- [ ] (R) Flash and boot; the halt must not recur
- [ ] (C) Update memory and the nd100-debug skill with the confirmed root cause

## HARD RULE FOR THIS PLAN

**No RTL change before Phase 3 reports.** Sections 2-5 of this document and
every candidate fix in it are UNPROVEN. Two hypotheses have already been wrong
today; the capture is what replaces guessing.
