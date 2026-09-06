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

# Plan: the CPU reads a NON-RESIDENT page as ZEROS instead of faulting

**Repo path:** `Verilog/fpga/tang-nano-20k/PLAN-zero-read-nonresident-page.md`
**Date:** 22-AUG-2026
**Supersedes as the active line of work:** `PLAN-pagefault-root-cause.md`
(that plan asked "is the page fault at 064406 real?"; the answer below is yes,
the oracle takes it too, so the question has moved).

External files live outside the repository and are referenced through
`$ND120_ORACLE_DIR` (the working directory that holds `oracle_simimg.trc`,
`oracle_pf_full.log`, `oracle_pc_histogram.txt`, `lockstep.py`, `disdrv`).

---

## 1. The two measurements this plan is built on

Both are already taken. Nothing here is estimated.

### 1a. Tang silicon: the machine executes ZEROS at 064540..064547

`TANG_JPL_CAPTURE` (microcode-address capture), log `csa_capture_run1.log`.
At 064544, 064545 and 064546 the microsequencer dispatches to

    CSA 006000 = STZ        (per tests/instruction-verify/ND110-ND120-MIC-MAP.md)

and **never** to 007340 (JPL) or any jump-group entry 007300..007334. STZ is
opcode 000000, so the fetched word is ZERO. The disc image holds
`135111 JPL I 111` at both 064544 and 064545.

The fetch **completed and returned data**. It was not aborted. STZ does not
branch, which is why three earlier `TANG_PC_HISTORY` runs recorded a
straight-line walk 064540 -> 064547.

### 1b. The oracle takes a PAGE FAULT at exactly those addresses

From `$ND120_ORACLE_DIR/oracle_pf_full.log`, 126 faults in a complete boot,
89 of them on a zero page-table entry. Three touch this page (VPN 26):

```
line 24:  PF VA=064406 PT=9 VPN=26 PTe=0x00000000 am=1 APT=1 PIL=1 PC=027244
line 49:  PF VA=064540 PT=4 VPN=26 PTe=0x00000000 am=4 APT=1 PIL=1 PC=064540
line 89:  PF VA=064134 PT=4 VPN=26 PTe=0x000001AD am=4 APT=1 PIL=1 PC=064134
```

`am`: 1 = READ, 2 = WRITE, 4 = FETCH, 5 = READ|FETCH.

**Line 49 is the decisive one.** The oracle, at PIL 1, tries to FETCH 064540,
finds `PTe = 0` (page not resident), **takes a page fault**, its handler pages
the page in, and only then does the real code at 064540 run. Our machine at the
same address, same level, fetches and gets zeros.

**Line 24 also corrects a recorded conclusion.** `Perror 064406` is not an
address our machine invented: the oracle touches 064406 too. It touches it as a
READ (`am=1`) from code at `PC=027244`, not as an instruction fetch. So
`[[oracle-never-executes-0644xx-gap]]` is right that the oracle never EXECUTES
there and wrong to imply the oracle never GOES there.

---

## 2. The hypothesis, stated as a hypothesis

> **H1: when the page-table entry has no permit bits (a non-resident page), the
> ND-120 RTL completes the access and returns zeros instead of raising the
> architectural page-fault trap.**

H1 is INFERRED. What is measured is one specific non-fault at one address.
H1 is worth the next round of work because it explains, with one cause, four
things already on file that have never been explained:

| already recorded | H1 explains it as |
|---|---|
| `[[reads-at-0644xx-return-zero]]` - STZ executed at 064540..064547 | non-resident code page fetched as zeros |
| `[[first-real-divergence-0325xx-zero-table-scan]]` - every `LDD ,X I` returns A=0 D=0 | non-resident data page read as zeros |
| `[[machine-never-runs-enpt-clpt]]` - the page-in microcode is never reached in a whole boot | nothing ever faults, so nothing ever asks to be paged in |
| `[[errfatal-is-nd500-window-pagefault]]` - a fatal fault on a page SINTRAN cannot own | the CPU has been running zero-garbage for a while by then; the fault that finally IS taken happens in a corrupted context |

Under H1 the ERRFATAL is the **last** symptom, not the fault. That reframes the
whole investigation: stop working backwards from 064406.

### What H1 must survive

`[[pgf-gate-is-not-a-fault-retraction]]` measured `PGF` asserting 2.7 M times
with 5 traps and warned that PGF is not an architectural fault - `PGF = VACC &
~PT15 & ~PT14 & ~PT13` fires on lookups that never commit, and the real trap
also needs `ETRAP_n`. **Do not resurrect "2.7 M unserviced faults".** That run
also only covered the first 3.4 M instructions, where neither machine pages at
all, so its "5 vs 126" is not a comparison. H1 says something narrower and
checkable: on a **committed** access to a page whose entry is zero, the trap
must be raised and on our machine at 064540 it was not.

---

## 3. Phases

Each phase names the measurement that ends it. No board build starts before the
phase above it has produced its number.

### Phase A - free, no board, no sim: bound the claim from the oracle side

A1. From `oracle_pf_full.log`, list every fault with `PTe=0x00000000` together
    with the PC and the access mode, and note which of them are FETCH faults on
    a page the code then runs from. This is the list of moments a correct
    machine MUST trap. **89 candidates already counted.**

A2. From `oracle_simimg.trc`, confirm that immediately after the 064540 fault
    the oracle runs its handler and then re-executes 064540 successfully.
    Confirms the fault is serviced and the restart is on the same instruction
    (`[[perror-is-the-faulting-instruction]]`).

A3. Find the earliest `PTe=0` FETCH fault in the boot. That address, not
    064540, is where our machine first had to trap and did not. Everything
    after it is downstream damage and not worth instrumenting.

**Ends when:** the earliest must-trap address and its instruction count are
written down.

### Phase B - RTL reading, no run: find the gate

B1. Read the translation path in `Verilog/CPU-BOARD-3202/circuit/CPU_MMU_24.v`
    and `CPU_MMU_PPNX_28.v`: what does the RTL drive on the data/instruction
    bus when the entry read from the map RAM has no permit bits? Does the read
    still complete?

B2. Read the fault path: `PGF` -> `ETRAP_n` -> the trap request in
    `Verilog/DELILAH-CPU/CGA_TRAP/circuit/CGA_TRAP*.v`. Name the exact term
    that must be true for a page-fault trap and check it against the drawings
    at 600 DPI (the OCR layer is garbage - see the skill).

B3. Check the FETCH path specifically. Line 49 of the oracle log is a FETCH
    fault, and a fetch aborts differently from a data read. If FETCH faults are
    wired at all, say where.

**Ends when:** either a missing/incorrect term is named with a file and line,
or B concludes the RTL looks correct and the fault must be in the map-RAM
contents instead.

### Phase C - Verilator, cheap and repeatable: reproduce a non-fault

The Tang costs ~7 min to build and ~13 min to run. Verilator costs seconds and
gives every internal signal. **Do not spend another Tang run until C has been
tried.**

C1. Write a testbench that sets up a page-table entry with zero permit bits and
    issues (a) a data read, (b) an instruction fetch to that page, and asserts
    that a page-fault trap is requested. This is a unit test of the MMU + trap
    path, not a boot. It lives in the module's own `sim/` and goes into
    `Verilog/tests/run_all_tests.sh` with a `TB_RESULT: PASS` line.

C2. If C1 passes (the RTL does trap when asked directly), the fault is in what
    reaches it during the boot - the map RAM contents, or the qualifier that
    decides a lookup is committed. Then instrument the full-boot Verilator run
    at the Phase-A3 address instead.

**Ends when:** a testbench either FAILS (H1 confirmed, go fix it) or PASSES
(H1 refuted at unit level, and C2 says where to look next).

### Phase D - Tang confirmation, one build

Only after C. Capture at the Phase-A3 address, on the Tang, the three things
that decide it: the translated physical page, the permit bits read from the map
RAM, and whether a trap was requested. One `TANG_*_CAPTURE` variant.

**Ends when:** silicon agrees or disagrees with Verilator.

### Phase E - fix and validate

E1. Fix. E2. `make test` (48 unit tests + the new one) - and remember
    `make test` is fail-fast, so run the entries AFTER any failure by hand.
    E3. The 13 instruction-verify areas. E4. Verilator boot, measured by
    LANDMARK not by instruction count, target the banner at landmark ~986-1195.
    E5. Tang boot.

---

## 4. What NOT to do (each of these has already cost a run or a day)

- **Do not compare instruction STREAMS against the oracle.** SINTRAN
  multiplexes level 1 from the PIL-2 scheduler at 032037; timing decides which
  program runs. Compare FAULTS and LANDMARKS, which are timing-independent.
- **Do not count a signal and call it an event.** Three probes in a row did
  this. Prove the qualifier chain, and cross-check against the oracle's PIL
  histogram before believing any counter.
- **Do not add a Tang capture variant without adding the `uart_txp` branch.**
  Four edits are needed and lint catches none of them; miss the TX branch and
  synthesis strips the probe silently - the board looks like the trigger never
  fired. See `[[tang-capture-variant-needs-tx-branch]]`.
- **Do not try to grow the capture ring.** BSRAM is at 100%.
- **Do not chase the JPL at 064544 or instruction bit 11.** Measured dead:
  JPL never executed.
