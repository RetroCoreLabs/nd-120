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

# Plan: root-cause and fix the Tang page fault (campaign plan, 23-AUG-2026)

**Repo path:** `Verilog/fpga/tang-nano-20k/PLAN-pf-campaign-23aug.md`
**Extends, does not replace:** `PLAN-zero-read-nonresident-page.md` (still the
technical core). This plan adds: evidence salvage, trace-file cleanup, the
"does Verilator fault too?" experiment, and a comparison method against the
nd100x oracle that actually works.

External files live outside the repository and are referenced through
`$ND120_ORACLE_DIR`. **Standing rule from Ronny (23-AUG): every log and trace
this campaign produces — Verilator, Tang, oracle — is written into
`$ND120_ORACLE_DIR`, nowhere else** (not the repo, not session scratchpads).
The directory holds the oracle ground truth: `oracle_pf_full.log`,
`oracle_trace_full.log` + `oracle_landmarks.log` + `oracle_console.log` +
`oracle_pc_histogram.txt`, `oracle_simimg.trc` (Phase A2 input),
`oracle_full.trc`, `disdrv`, `lockstep.py`, `boot_compare.py`,
`oracle_make.sh`, and the disc images. A backup of the small irreplaceables
plus `WD0-sim.IMG` exists in a second directory Ronny has in chat.

---

## 1. Where the evidence actually stands (verified 23-AUG)

* **The board's fault is real and characterised.** ERRFATAL, L-reg 072627,
  Perror 064406, IIC 3 (Page Fault), PIL 1 — identical bytes across every
  capture. `TANG_JPL_CAPTURE` proved the CPU executes STZ (opcode 000000 =
  fetched ZEROS) at 064540..064547 where the disc image holds `JPL I 111`
  (`csa_capture_run1.log`).
* **The oracle faults at the same spot and services it.**
  `$ND120_ORACLE_DIR/oracle_pf_full.log`: 126 faults in a full boot, 89 with
  `PTe=0`. Line "VA=064540 am=FETCH PTe=0 PIL=1" is the decisive one — the
  oracle traps, pages the page in, re-executes. Our machine fetches zeros and
  keeps going.
* **Working hypothesis H1** (from `PLAN-zero-read-nonresident-page.md`): a
  committed access to a page whose page-table entry is zero completes and
  returns zeros instead of raising the page-fault trap. One cause explains the
  zero-fetch, the 0325xx zero-table scan, ENPT/CLPT never running, and the
  final ERRFATAL being taken in an already-corrupted context.
* **The retracted 23-AUG "IIC 7" traces (`nd120_win.trc` and friends) were
  deleted from `$ND120_ORACLE_DIR` on 23-AUG with Ronny's approval**, together
  with the other closed-line ND-120 traces (`nd120_jpl/maccap/pgs.trc`,
  `identhunt/`) and ~6 GB of stale scratchpad/`sim/` debris. Everything
  oracle-side was kept. Retraction details:
  `HANDOFF-iic7-verilator-only-retraction.md`.
* **Whether Verilator boots, faults like the Tang, or fails differently is
  UNKNOWN.** The only full-length Verilator boot attempt (1.10G ticks, 12 h)
  ran at the 800k-tick fake device delay, covered only 96 disc ops, and ended
  with no banner and no ERRFATAL — it was simply too short. Nothing about the
  Verilator boot outcome may be stated as fact until the run in Phase V below
  is done and **its console log has been read** (the 7-byte-console rule).

## 2. Why "compare the Tang against the nd100x log" keeps failing, and the method that works

Three attempts to line up instruction streams have died for the same reason:
SINTRAN multiplexes level 1 through the PIL-2 scheduler at 032037, and timing
decides which level-1 program runs. Two correct machines produce different
streams. The Tang additionally cannot stream a full trace (console locked at
9600 for SINTRAN; the capture ring holds 512 entries and BSRAM is at 100%).

So the comparison unit is never the instruction stream. Three units survive
timing skew:

1. **Page faults.** Each fault is (VA, PT, VPN, PTe, access-mode, PIL, PC).
   The oracle's complete list exists (`oracle_pf_full.log`). A correct ND-120
   must produce faults at the same VAs for the same reasons, in a similar
   count — order may differ slightly, presence may not.
2. **Landmarks.** Control writes / IOX milestones (banner at landmark
   ~986-1195 on the oracle). Coarse, timing-independent progress metric.
3. **Halt signatures.** ERRFATAL text, IIC, Perror — already byte-stable.

The campaign's comparison artifact is therefore a **fault log in the oracle's
exact format, produced by the Verilator harness**, diffed against
`oracle_pf_full.log`. The Tang is used only to confirm single, targeted facts
with one capture build per fact — never to hunt.

**Oracle side = TRACE FILES, never debugger stepping** (Ronny's directive,
23-AUG). Measured line counts (23-AUG): `oracle_full.trc` = 25,000,001 lines
with full register columns (`PIL PC OP A D T X B L STS PIE PID IIE IID PGS
MMU INT SEX`) — extends past the banner threshold (~17-18M instructions) and
is THE reference boot trace; `oracle_simimg.trc` = 25,000,001 lines, compact
mode; `oracle_trace_full.log` = 1,955,151 lines only (~2M instructions,
human-readable, NOT full boot). CAVEAT: the source disc image of each
existing trace is not recorded in the files — verify or regenerate before
any image-dependent conclusion. A fresh trace is regenerated with
`$ND120_ORACLE_DIR/oracle_make.sh <max-instr> <abs-outfile> [compact] [img]`
(nd100x `--trace`, no debugger; always trace a COPY of the disc image —
booting modifies it). The nd100x DAP debugger is acceptable ONLY for
interactive one-off spot checks, and only when Ronny asks.

## 3. Phases

### Phase 0 — DONE 23-AUG: salvage and cleanup
Irreplaceables backed up (`oracle_pf_full.log`, `WD0-sim.IMG`, `win_run.py`,
`dis/`); ~9 GB of stale traces deleted with Ronny's approval (retracted-run
`.trc` files in `$ND120_ORACLE_DIR`, old session scratchpad `.trc` files,
`Verilog/sim/` July `lbyt_*` debris). All future logs/traces go to
`$ND120_ORACLE_DIR` per the standing rule above.

### Phase B — RTL reading (no build, no run): find the gate
Unchanged from `PLAN-zero-read-nonresident-page.md` Phase B:
* `Verilog/CPU-BOARD-3202/circuit/CPU_MMU_24.v`, `CPU_MMU_PPNX_28.v`: what is
  driven when the map-RAM entry has no permit bits; does the access complete?
* The trap path: PGF -> ETRAP_n -> `Verilog/DELILAH-CPU/CGA_TRAP/circuit/`.
  Name the exact term required for a page-fault trap; verify against the
  600 DPI drawings, not the OCR.
* FETCH aborts specifically (the decisive oracle fault is am=FETCH).
**Ends when** a wrong/missing term is named with file+line, or B concludes the
RTL is right and the fault is in what reaches it (map-RAM contents or the
committed-access qualifier).

### Phase C — MMU+trap unit testbench (Verilator/iverilog, seconds per run)
Unchanged from the core plan, and it is the CHEAPEST decisive experiment —
run it before any boot:
* Set up a page-table entry with zero permit bits; issue (a) a data read,
  (b) a data write, (c) an instruction fetch; assert a page-fault trap is
  requested and the returned data is not consumed.
* Lives in the module's own `sim/`, registered in
  `Verilog/tests/run_all_tests.sh`, prints `TB_RESULT: PASS/FAIL`.
**FAIL = H1 confirmed at unit level** -> go fix (Phase F).
**PASS = H1 refuted at unit level** -> the boot-time fault is in the map-RAM
contents or the qualifier chain; Phase V's instrumentation targets that.

**MEASURED 23-AUG: PASS, both build modes.** The testbench is
`Verilog/CPU-BOARD-3202/circuit/sim/PGF_COMMITTED_ACCESS_tb.v`
(`make test-pgf-committed` / `test-pgf-committed-ff`, registered in
`Verilog/tests/run_all_tests.sh`). Through the real chain - cycle PALs
44601B+44307C, TMM2018D PT status RAM, CGA_TRAP_BRKDET, CGA_TRAP_TVGEN(_P2),
CGA_MIC_IPOS, with the board's real BRK/TRAP feedback - a committed FETCH,
READ and WRITE against a zero entry each assert TRAPN and force
MA = trap vector 0001 at the mid-cycle MACLK trap-vector strobe
(PAL_44307C.v:119, the `TRAP & CC3_n & CC1 & CC0_n` term, states d+e);
a fully resident entry does not trap. Latch mode AND FPGA_FF_MODE.
**H1 is refuted at unit level: the trap chain works when the PT data arrives
before VACC.** The boot-time non-fault therefore lives in what reaches the
chain: map-RAM contents at that moment, the VACC qualifier, or PT-data
arrival timing relative to the ETRAP-enabled window. Phase V's [win]/[etrap]
probes decide between those - they name ETRAPn_high/CBRK per NOTRAP window.
Side findings, both measured while building the bench: (1) traps are
consumed at the MID-CYCLE MACLK strobe, never at TERM - ETRAP_n disables
TRAPN in the TERM state by the PAL equation itself; (2) a mapped page with
PGU=0 (or a write with WIP=0) breaks via BRKDET's A02 terms - the used-bit
bookkeeping - so "trap on a resident page" is not automatically a bug.

### Phase V — Verilator fast boot (agent-runnable, in parallel with B/C)
Answers the open question: does Verilator take the same fault?
* Build: `Verilog/sim/` `make probe-wd USE_LATCHES=0
  EXTRA_WD_DEFINES="-DND120_DEV_DELAY_TICKS=216000 -DRTC_SIM_20MS=<cal>"`.
  216000 removes the 800k fake device delay. `RTC_SIM_20MS` exists in
  `DECODE_DGA_POW.v` (line ~370); the 8192 default was measured 16.5x too
  fast and STARVES SINTRAN, so start from ~135000 and sanity-check the PIL-13
  share against the oracle's PIL histogram early in the run.
* Run: `ND120_WD_IMG=$ND120_ORACLE_DIR/WD0-sim.IMG`, boot `20500&`. Budget a
  full ~1G-tick run; poll landmarks, don't wait blind.
* **Instrument the harness, not the RTL**: extend
  `Verilog/sim/nd120_probe.cpp` to emit a fault log in the oracle's exact
  format (`PF VA= PT= VPN= PTe= am= APT= PIL= PC=`) on every committed
  page-fault trap, plus a `ZR` line on every committed access that reads a
  zero PTe WITHOUT trapping (H1's smoking gun). The probe registry already
  reaches the MMU/INTR internals.
* Verdict rules: read the console log FIRST (`wc -c`), then diff the fault
  log against `oracle_pf_full.log`.
Three possible outcomes:
  1. **Verilator shows the zero-read too** -> full-visibility reproduction;
     finish root-cause entirely in Verilator, Tang only confirms the fix.
  2. **Verilator boots to the banner** -> the RTL trap path works; the Tang
     divergence is board-specific (SDRAM path, timing, latch/FF residue) ->
     re-aim at `Verilog/fpga/tang-nano-20k/` board layer, compare
     Tang-vs-Verilator instead of Tang-vs-oracle.
  3. **Verilator fails differently** -> record signature, DO NOT build a
     chain on it (the IIC-7 lesson); fix the earlier failure first.

### Phase T — one Tang capture build, only after B/C/V have a verdict

**RUN 1 MEASURED 23-AUG (log `$ND120_ORACLE_DIR/tang_zeroread_run1.log`):**
`ND120_PF_CAPTURE` retargeted with `MATCH_ON_NOPERM_ACCESS(1)` at raw
LA[19:10]=0o1032 (software table 4 page 26, the VA-064540 page). Result:
captured=1, PT=0000000 at the edge AND one edge after (not late arrival),
VACC=1, **TVEC=1 latched — the page-fault trap DISPATCHED**; census 56
faults, most recent at the target page; EPGS seen (the handler read PGS);
ERRFATAL still followed, naming software 0o760. **The trap is not missing —
the divergence is in what the handler reads/does. Prime suspect: PGS
overwritten between the fault and the handler's read** (PGS reloads on every
VACC-high cycle). **RUN 2 MEASURED 23-AUG (log `$ND120_ORACLE_DIR/tang_zeroread_run2.log`):
PGS at the handler's read = software 0o432 — MATCHES the faulting page. THE
PGS-OVERWRITE HYPOTHESIS IS DEAD.** Trap dispatch correct, PGS correct, and
the page still refaults forever (census 58, most recent still 0o432).
Surviving suspect: the PAGE-TABLE WRITE path — the handler's entry write
never lands, or lands at the wrong map-RAM index (one mechanism explaining
the eternal refault, granting entries at wrong rows feeding the zero
fetches, 0o760-instead-of-0o761 touches, and ENPT/CLPT never running;
compare Issue-D, PAL 44306A). Decider: the Verilator boot's PTDBG `[pt] WR`
records (address + data of every PT write) around the software-0o432
faults. If Verilator does not reproduce, the next Tang build captures the
PT-write history for the target row instead.

**PT-WRITE HISTORY — CORRECTED RECORD 23-AUG (see the memory note
silicon-zero-pt-writes-vs-sim-3053 for both retractions):** Tang run 1's
"zero write records" was VOID, not a measurement — the ERRFATAL trigger
lacked `ND120_PC_ON_DBG_PORT`, never fired, and no dump ever started (fix in
`CGA.v`, in build 2). And an intermediate "0 `[pt] WR` in Verilator" claim
was a grep artifact (the WR lines carry a `t=` timestamp; match
`"WR  addr="`). Correct measurements, Verilator FF-mode boot at ~38 disc
ops: **`[pt] WR` = 3583, `[pt] WRI` = 3583, paired 1:1 — the write path
WORKS in simulation**, including the table-init sweep (data 162000,
granting). The finding that stands: **the refaulting row raw 0o1032
(software 0o432) is written exactly ONCE — data 000000, the init-time
clear — and never receives a resident entry in sim**, while the oracle
pages it in on demand. The question is now WHY the handler never writes a
resident entry for that page (what it consults after reading the correct
PGS, and what it sees on our machine vs the oracle). **Silicon write history MEASURED (run 2, decode in
`$ND120_ORACLE_DIR/tang_ptwr_run2.console.txt`): 85 writes + 170 attempts in
the ring — the write path works on the board.** The pre-ERRFATAL pattern is
SINTRAN demand-paging table 7: grant/invalidate cycles on sw pages 763-766,
and **SINTRAN itself zeroes sw page 760 (WNDN5) in a 757-766 sweep**; the
fatal fault is a subsequent ACCESS to 760 — a page the oracle never touches
(it uses 761 next door). Working chain: 0432 never resident -> its contents
execute as zeros -> an address computed from zeroed state lands on 760
instead of 761 -> the WNDN5 branch = ERRFATAL. Root question unchanged and
sharpened: why does the 0432 fault service never WRITE a resident entry.
Locating measurement: the first fault in the Verilator run whose service
window contains no `WR  addr=` line — inspect what the handler read there.
Trigger the existing generic capture framework (ONE ring, `s_cap_src/stb/
arm/event`, and ALWAYS the `uart_txp` branch — miss it and synthesis strips
the probe) at the earliest must-trap address from `oracle_pf_full.log`
(earliest PTe=0 FETCH fault: VA=113607; earliest PTe=0 fault overall is a
PIL-0 read of 177777 — Phase A3 of the core plan decides which is the usable
trigger). Capture: translated PPN, permit bits read from map RAM, trap
requested yes/no.

### Phase S — QUEUED by Ronny 23-AUG: storage cache off, functionality + speed
Two Tang runs against today's cache-on baseline (`20500&` -> ERRFATAL = 143 s,
`$ND120_ORACLE_DIR/tang_ptwr_run1.console.txt` 13:44:37 -> 13:47:00):
* **S1 `-DiscsUncached`**: `ND_STORAGE_DISCS_UNCACHED` (the 09-AUG lever) —
  cache logic present, every disc client DIRECT through the staging line.
* **S2 `-NoStorageCache`**: NEW `ND_STORAGE_NO_CACHE` in
  `Verilog/SD-FAT/circuit/nd_storage.v` — the cache directory is not
  synthesized at all (BSRAM/routing/timing presence-effects removed); forces
  the mask off too.
Questions: (a) does the boot failure CHANGE (different signature, further
progress, or — best case — past the ERRFATAL) with the cache out of the
path? Historical motivation: on 09-AUG the CACHED Winchester client returned
zeros on silicon while the DIRECT tape client read the same card correctly —
zeroed disc blocks feeding SINTRAN's own tables would corrupt exactly the
state that decides page-in. (b) Speed: same `20500&`->halt interval (and
disc-op pacing if visible) cache-on vs DIRECT — is the cache paying for
itself, or is the SD reader fast enough alone? Caveat for reading the
result: a boot is mostly first-touch reads, where a cache helps least;
state the number as "boot-phase cost", not a general verdict.
CACHE_MASK is per-client (Winchester = bits 7:6), so a Winchester-only
variant is one parameter edit if S1/S2 disagree.

**S1 MEASURED 23-AUG (`$ND120_ORACLE_DIR/tang_s1_uncached_run.console.txt`):
NULL RESULT, both questions.** `20500&` 14:44:57 -> ERRFATAL 14:47:20 =
143 s, byte-identical signature (L-reg 072627 / Perror 064406 / IIC 3) —
exactly the cache-on baseline. (a) The cache is NOT the cause of the page
fault. (b) No measurable boot-speed difference at 1 s resolution over ~30
disc operations — the SD reader through the staging line keeps up; the
cache's value would only appear under re-read workloads SINTRAN never
reaches here. **S2 MEASURED 23-AUG (`$ND120_ORACLE_DIR/tang_s2_nocache_run.console.txt`):
also NULL.** Cache absent from the netlist (`ND_STORAGE_NO_CACHE`): 15:05:59
-> 15:08:22 = 143 s, byte-identical signature. Phase S verdict: the storage
cache neither causes the page fault nor speeds up the boot (all three
builds: 143 s to the same halt). S2 resources: Logic 16501/20736 (80%),
Register 7378/15915 (47%); the cache-present delta needs one report
regeneration (the PnR reports share a path) if ever wanted. Build levers
kept: `gowin_build.ps1 -DiscsUncached` / `-NoStorageCache`; the S2 tie-off
note: `c_alloc_way` is ENGINE-driven - tie only the cache's own outputs
(first S2 build failed EX2000 on exactly that).

### Phase F — fix and validate (task order unchanged)
1. Fix named term. 2. `make test` (fail-fast — after any failure run the
rest by hand) + the new Phase-C testbench. 3. 13 instruction-verify areas.
4. Verilator boot to banner by LANDMARK. 5. Tang boot.

## 4. Standing rules carried forward

* Read a run's console log before trusting its trace (`wc -c` first).
* Compare faults and landmarks, never instruction streams.
* No signal counting without proving the qualifier chain (PGF alone is not a
  fault; the committed-access term matters).
* One Tang build per question; Verilator first, always.
* Capture ring: 512 entries, drop PIL 14, BSRAM full — do not grow it.
* Do not chase the JPL at 064544 or bit 11 — measured dead.
