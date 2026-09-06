# PLAN — root-cause & fix the Tang diagnostic failures (Verilator-first, then Tang)

## PROGRESS (27-JUL, autonomous loop)
- **Issue A robust fix FLASHED to the Tang** (Gowin build VARIANT=slow, clean console, TANG_FLOPPY;
  make flash-gowin Done 100%). Hardware now carries the robust `!= 0xFFFFFF && != 0x000000` guard.
- **Issue A (DMA robust capture) = DONE.** Final `ND_DMA_MASTER.v` guard rejects BOTH idle patterns
  (`!= 0xFFFFFF && != 0x000000`); value-independent, works for the tbs (data AT BDRY) and ND120_TOP
  (data BEFORE BDRY, pre-data 0x000000, released-to-0xFFFFFF at edge). VALIDATED: test-dma-master +
  all 4 test-floppy-* PASS, `1560&` boots to TPE>. SMD gates FAIL but PRE-EXISTING (identical with the
  original `!= 0xFFFFFF` guard; "not ready at reset" is before any DMA read). 1 clean hunk, git-clean
  otherwise. COMMIT-READY (verify SMD against a clean tree first). Tang has the earlier non-robust fix
  flashed - boots the same; re-flash the robust version when convenient.
- **Issue E = RESOLVED 30-JUL by the PAL_44403C DLY0 fix** (every microcycle took
  the delayed path - the machine ran ~2x slow globally; Ronny confirms "feels
  quicker" and `#` is instant). Original triage below is superseded.
- **Issue E(orig) (`#` memory-test slow) = TRIAGED -> silicon-only.** Bank tests WORK + FAST in Verilator
  (in-range `0#`->pass by 12M ticks; out-of-range `77#`->MOR-fail `?` by 18M). MOR/memory-decode
  FUNCTIONS in sim; RTOSC/rfclk is a fixed 256-sysclk counter (same in sim+FPGA). So the Tang `#`
  slowness is the silicon TOUT-timing divergence = Issue B on the memory path. NOT a sim-fixable RTL
  bug. Localized to the `s_tout = ~(s_a631_q | s_rfclk)` FF chain (DECODE_DGA_POW.v FPGA_FF_MODE block
  lines 460-495, ACAL-class).
- **Issues B, C, D = OPEN.** B/E need on-chip capture (silicon). C/D need a reliable scripted-TPE
  harness (the SCRIPT_INPUT injector only settles after `&`, not between later commands like
  `run`->`3`); runtime `ND120_SCRIPT`/`ND120_SCRIPT_FILE` exists but the injector still needs
  prompt-wait between commands. Building that harness is the prerequisite for autonomous C/D triage.



Opened 2026-07-27. Board: Tang Nano 20K, `TANG_FLOPPY` (floppy-only), `FPGA_FF_MODE`.
All paths absolute. Engine for sim work: `Verilog/runSim/obj_dir_vflop`
(Verilog device stack, `-DND120_VERILOG_DEVICES -DFPGA_FF_MODE`).

## Where we are
The floppy DMA-master fix (`ND-BUS-DEVICES/DMA/circuit/ND_DMA_MASTER.v`) made `1560&` boot to `TPE>`
in Verilator AND on the flashed Tang (`li-fi`/list-files clean). That opened the door and the Tang is
now running diagnostics, which surfaced a SET of distinct issues. This plan roots-causes and fixes
each, Verilator-first then Tang.

## Method (applies to every RTL issue)
1. **Reproduce in Verilator** (full observability) with a MINIMAL trigger (skip slow preamble; select
   the specific sub-test). Confirm it's an RTL bug (repros in sim) vs SILICON-ONLY (clean in sim).
2. **Root-cause** with targeted `$display`/probe traces (guarded, e.g. `\`ifdef FLPDBG_RTL`); remove
   after.
3. **Fix** the RTL.
4. **Validate in Verilator**: the specific test passes AND the regression suite
   `Verilog/tests/run_all_tests.sh` (`make test` from `Verilog/`) is
   green — in particular the 8 DMA-consumer gates (see Issue A).
5. **Re-flash Tang** (`make gowin VARIANT=slow` then `make flash-gowin` from
   `Verilog/fpga/tang-nano-20k/`) and **validate on silicon**.
SILICON-ONLY issues (clean in Verilator) can't use step 1 — they need ON-CHIP CAPTURE instead
(re-enable a targeted probe like `TANG_GRANT_CAPTURE` and compare the captured timing to the Verilator
golden). Issue B is this kind.

---

## Issue A — DMA read-capture is not robust (BLOCKER: floppy fix not commit-ready)
STATUS: root cause KNOWN; the current one-line fix boots the floppy but FAILS all 8 DMA/floppy/SMD
gates. Must land a robust version before commit.

- **Root cause:** `ND_DMA_MASTER.v` ST_DATA captures read data with a bus-VALUE heuristic
  (`BD_23_0_n_IN != <idle>`). The released/idle bus differs by environment — ND120_TOP + FPGA drive
  the wired-AND LOW when disabled (released = `0x000000`, the project "drive 0 when disabled" rule),
  the standalone tbs (`ND-BUS-DEVICES/DMA/sim/nd_dma_master_tb.v:55,150`, and the floppy/SMD tbs) idle
  HIGH (`0xFFFFFF`). Worse, a data value of `0` encodes as `0xFFFFFF` and `0xFFFF` as `0x000000` on the
  inverted bus, so BOTH idle patterns alias real data. No `!= constant` guard works everywhere.
- **Verilator plan:** decide the real contract by TRACING the ND120_TOP memory read timing — when does
  the memory/BIF DRIVE vs RELEASE the read data relative to `BDRY_n`? (`CPU-BOARD-3202/circuit/
  BIF_BCTL_BDRV_7.v`, the MEM read path, and the DMA `ST_DATA` in `ND_DMA_MASTER.v:268-285`.) Two viable
  fixes: (1) make ND120_TOP memory HOLD read data through the `BDRY` leading edge and have the DMA
  capture AT `BDRY` (value-independent, matches how the tb already holds data); or (2) add/consume an
  explicit memory-data-valid strobe. Prefer whichever keeps the tb bus model valid; if the tb models the
  wrong convention, fix the tb too (align to drive-0) — but only after confirming ND120_TOP's real
  contract, not to mask.
- **Gate (Verilator):** ALL 8 must pass AND `1560&` must still reach `TPE>`:
  `ND-BUS-DEVICES/DMA/sim :: test-dma-master`; `FLOPPY-DMA/sim :: test-floppy-{dma,boot,iox,p2}`;
  `SMD/sim :: test-smd{,-iox,-p2}`. Run: `cd <dir>/sim && make clean && make test` (rebuilds against
  the fixed RTL).
- **Tang:** already validated booting with the non-robust fix; re-flash the robust version and
  re-confirm `1560&` + `li-fi`.

---

## Issue B — SERIAL-DIAGNOSED ON HARDWARE 27-JUL (autonomous, /dev/ttyUSB1 @ 9600 8N1)
Drove the Tang directly over the serial console (python pyserial; PACE chars ~120ms - MOPC has no RX
FIFO, or the digit is dropped). Findings on the flashed robust-fix build:
- **Memory bus-timeout / MOR WORKS + is FAST:** `0#` -> `#0##` (pass), `77#` (out-of-range) -> `#77#?`
  (MOR fires), both ~0.2s. So a single `#` bank test and MOR are fine - the "~6 sec `#`" was a
  misread; it's the CONFIG test.
- **IO/IOX path: "ANSWERS ALL CALLS".** CONFIGURATION `run` enumerates the ENTIRE IOX device space -
  every unmapped device number (RTC 2/3/4, sync modems, line printers, terminals up past dev 1300o,
  hundreds of them) returns `Device status: 000000B` (a spurious response) instead of timing out, so
  the test thinks each exists, fails its ident (`No identcode found on level 10D/12D`), and grinds for
  a long time. THIS is the real slowness + "bus/device detection fucked" + the missing level-14
  IOX-error.
- **Root-cause hypothesis (strong):** the FPGA "drive-0-when-disabled" convention (z doesn't work, see
  CLAUDE.md tri-state note) makes the active-low ready signal `BDRY_n`/`IBDRY_n` default to 0
  (=ASSERTED) for an unmapped IOX -> the IOX "completes" fast with drive-0 data (status 0), no TOUT,
  no IOXERR. SAME CLASS as the DMA-0 bug. Memory MOR works because its BDRY/timeout path differs.
  BIF_BCTL_BDRV_7.v: `BDRY_n=s_bdry_n` (l.130); IOXERR_n/MOR_n gated by TOUT (l.250-252). NEXT: find
  which IO device / bus signal drives IBDRY_n=0 when NOT selected (should idle 1); confirm via on-chip
  capture of BDRY_n/IBDRY_n/TOUT on an unmapped IOX. Serial tools: scratchpad/tang_{serial,cmd,drive}.py.
  Tang left mid-config-enum; reset with `openFPGALoader -b tangnano20k <fs>` (SRAM reload) for a clean #.

## Issue B(old) — bus-timeout / IOX-error (TOUT) does not fire on silicon  [SILICON-ONLY]
SYMPTOMS (Tang): CONFIGURATION reports PHANTOM devices (every unmapped device number "answers"),
INSTRUCTION verifier "Internal interrupts" reports `IOX-error: No interrupt generated on level 14`.
Both are ONE root: an IOX to a non-existent device should time out -> `IOXERR/MOR` -> level-14, but on
the Tang it gets a spurious response. CLEAN in Verilator (instruction-verify campaign + RUN area pass),
so SILICON-ONLY.

- **Localized:** `CPU-BOARD-3202/circuit/BIF_BCTL_BDRV_7.v:251-252` gates `IOXERR_n/MOR_n` on `TOUT`
  (`s_ioxerr_n = s_tout ? s_iod_n : 1'b1`). `TOUT` = `s_tout` from
  `DECODE-GateArray/DGA/circuit/DECODE_DGA_POW.v:256` = `~(s_a631_q | s_rfclk)`, off the RTC/`rfclk`
  J-K divider (A616/618/617/624/631) which has `FPGA_FF_MODE` splits. The timeout/error window is
  RTC-clock-derived and doesn't produce IOXERR/MOR on real FPGA timing (ACAL-class).
- **Plan (capture-driven, NOT sim-reproducible):**
  1. Establish the Verilator GOLDEN: trace `TOUT`/`s_a631_q`/`s_rfclk`/`IOXERR_n`/`MOR_n` and the
     level-14 request during an IOX to an unmapped device in FF-mode Verilator (it works there) — what
     is the correct `TOUT` pulse timing vs the bus cycle?
  2. On-chip capture on the Tang: re-enable a targeted probe (thread `TOUT`/`s_a631_q`/`s_rfclk`/
     `IOXERR_n` into the `TANG_GRANT_CAPTURE` 512-sample analyzer, trigger on an IOX cycle) and compare
     to the golden. See `fpga/tang-nano-20k/ANALYSIS-cga-intr-masked-grant-root-cause.md` +
     `grant_capture.py` for the probe/dump workflow.
  3. Fix the latch/timing divergence in the `DECODE_DGA_POW` timeout chain (or the BIF gating) so
     `TOUT` fires on silicon. Validate: CONFIGURATION shows only real devices (no phantoms) and the
     INSTRUCTION internal-interrupt test gets its level-14.
- Cross-check the nd120-fpga skill "`ifdef VERILATOR_SIM` latch-divergence" audit on the a631/rfclk
  chain first — may be the same class as the ACAL fix (`tang-sdram-rmw-bug`).

---

## Issue C — `MOVEW APT ==> APT` drops the destination page-boundary word  [RTL, repros in sim]
STATUS 31-JUL: **ROOT CAUSE MEASURED at signal level; fix needs the original schematic
term confirmed (MAC DECODE, DELILAH pages 25-28) — waiting on Ronny's go for the
schematic check.** Full chain (all measured in Verilator, current build, probe engine
`Verilog/sim/obj_dir_probe_cx`, artifacts in the session scratchpad):
1. Repro: `1560&` -> `load inst` -> `cx-instructions` (single-area command). Failing
   subtest: MOVEW opcode 143104, D=161750 -> T=163754, L=100o; dest crosses page
   boundary 164000o after 24o words.
2. The boundary word's write IS issued (ucode APTWR+1, CSA 4323, data 24o), then a
   SPURIOUS level-14 page-fault trap (TVEC=3) fires one microcycle later (after the
   CONDENABL slot -> no INTER rewind), the test's level-14 handler runs ~8.2k ticks,
   the move resumes at the NEXT word: the in-flight write never lands. Control: the
   passing PT->APT subtest writes the identical dest block through the identical
   WRRQ,APT micro-op, same boundary, zero faults (6 clean repeats).
3. Cause of the spurious fault (FST, `movew_sel.fst`): at EVERY `WRRQ,APT` (and
   `RDRQ,APT`) the CGA_MAC_DECODE strobes assert **SPT AND SAPT simultaneously**;
   the PTSEL JK (J=SPT, K=SAPT, `CGA_MAC_PTSEL.v`) sees J=K=1 = TOGGLE. Coming from
   a PT request the toggle lands on APT by luck (all passing variants); coming from
   an APT request (APT->APT: the src read left it at APT) it flips to PT, the dest
   first-touch protection check consults the NORMAL PT's entry for page 72o ->
   page fault -> word dropped.
4. Decode math (verified against microword encodings, CSCOMM bits 36:32 / CSMIS 43:42):
   `GATES_59 = NAND(s_cscomm_2, s_csmis_1_n, s_csmis_0)` masks SPT on APT only for
   c2=0 codes (22,30,32 - all clean); the c2=1 request codes 34/35 (RDRQ/WRRQ) have
   NO APT mask -> SPT stays asserted. A blanket mask (drop the cscomm_2 input) would
   also hit codes 24-27 with CSMIS=1 which DO occur in the L-ROM (CSMIS = unrelated
   MIS modifier there), so the surgical original term must be read off the schematic:
   GATES_59/GATES_60 inputs on the MAC DECODE sheet, `Verilog/DELILAH-CPU/CGA_MAC/
   circuit/CGA_MAC_DECODE.v:352-360,797-809`. ALTERNATIVE: the original element in
   PTSEL may not be a toggle-on-J=K JK (SR-style with priority) - the schematic
   decides which fix is faithful.
Old attack plan v2 below (superseded by the above; kept for method reference):
1. REPRODUCE MINIMAL (Verilator, engine runSim/obj_dir_testmode or fresh build):
   scripted `1560&` -> `load inst` -> run ONLY the cx/MOVEW area (the scripted-TPE
   injector is proven), OR craft a 20-word BPUN doing SETPT + MOVEW APT->APT across
   176000o and deposit-load it - trigger in MINUTES not 209M ticks.
2. OBSERVE, do not guess: arm `Verilog/sim/fst_window.h` (windowed full-signal FST,
   committed today) with ND120_FST_TRIG_P at the MOVEW loop address -> capture EVERY
   signal around the boundary word: LA_20_10, PT/PPN outputs, WMAP/EPT strobes,
   SPT/SAPT + SELPTN (CGA_MAC_PTSEL - MOVEW toggles PT<->APT per word!), the
   write strobes into MEM, and the cache-side WCA/ECD.
3. PRIME SUSPECTS, ranked by what the paging hunt taught us:
   H1 the alternate-PT toggle (SPT/SAPT JK in CGA_MAC_PTSEL) races the write strobe
      exactly at the page-crossing word - same PONI/PT-select corner as Issue D;
   H2 dest PT write-back (COMM,WRRQ,HOLD) displaces the data write - single
      s_wmap_n strobe in CPU_MMU_24.v:243 (the original H1);
   H3 cache write-allocate/inhibit at the boundary (CPU_MMU_CACHE_25 - NOTE the
      44402D used-bit fix changed this area; re-test BEFORE deep-diving: the bug
      may already be GONE, it was filed pre-fix!).
4. STEP 0 THEREFORE: re-run the failing INSTRUCTION cx area on the CURRENT build
   (sim first, and Ronny already sees the MOVEW error still present on Tang as of
   30-JUL morning - but that flash predated the 44402D fix; the CURRENT flash has
   it -> RE-CHECK ON SILICON before assuming still-broken).
5. Fix -> gates: instruction-verify cx area + golden traces, full suite, PAGING
   11/11 regression, Tang re-flash + INSTRUCTION on silicon.
STATUS(orig): known bug, memory `movew-page-boundary-word-drop`. Same failure in Verilator and on Tang, so
NOT silicon-specific. `MOVEW APT->APT` drops the dest word at `176000o` (reads 0, expected `24o`).

- **Verilator plan:** the DECISIVE experiment (already designed, not yet run): stop right after the
  APT->APT move, backdoor-read PHYSICAL mem `176000o` vs a CPU read to split H1 (dest PT write-back
  `COMM,WRRQ,HOLD` displaces the boundary data write in `CPU_MMU_24.v:243` single `s_wmap_n` strobe)
  from H2 (cache read-back slip, `CPU_MMU_CACHE_25.v`). Trigger on the APT->APT move directly (don't
  wait ~209M ticks for the full verifier). Fix the RTL, re-run the INSTRUCTION `cx` group -> the MOVEW
  error must be gone.
- **Tang:** re-flash, re-run INSTRUCTION -> MOVEW error gone.

---

## Issue D — SOLVED 29-JUL (silicon-validated): PAL 44306A EIPL transcription error
ROOT CAUSE: `Verilog/PAL/PAL_44306A.v` (MMU control PAL 21G) EIPL equation had an extra
`DOUBLE &` term vs the original PALASM (`DesignDocuments/PAL-Code/SRC/44306A.txt`:
`EIPL = WCHIM + DOUBLE*LSHADOW*CA0 + LSHADOW*WRITE`). EIPL gates IDB -> PPN-map-RAM
write data; with the bogus DOUBLE term it never asserted in REX mode, so the PPN map RAM
(CPU_MMU_PT_29 chips 22G/23G) was never written and EVERY paged access ran in physical
page 0 (garbage fetches -> POF-as-NOP -> lost store -> protect violation -> 10-error
abort). Fix applied (one term). VALIDATED ON TANG 29-JUL (flashed build, Cache=Yes):
PAGING tests 1-10 ALL pass incl. test 3 (PGU/WIP) and 4 (alt-PIT). Sim long-run +
regression suite still owed before commit. Full writeup:
`Verilog/docs/HANDOFF-paging-test3-pof-dispatch-rootcause.md`.

## Issue F — PAGING Test 11 (PHYSICAL ADDRESS generation): PES/PEA read 0  [NEW 29-JUL, silicon]
STATUS: CLOSED 30-JUL — SILICON-VALIDATED: full PAGING All-tests sweep on the Tang
(driven over serial) = 11 of 11 "- End of test -", zero errors, single pass 27 min,
Cache=Yes. Issues D and F both closed. Sim validation trail below.
STATUS(29-JUL): FIXED + SIM-VALIDATED — test 11 passes in Verilator
("11. PHYSICAL ADDRESS generation - End of test -", zero errors, scripted
1560&/load pag/run/11 on obj_dir_pes2). TWO defects, both fixed:
(1) the PAL_45001B strobe literals below;
(2) `Verilog/CPU-BOARD-3202/circuit/BIF_DPATH_9.v` PESPEA instantiation tapped only
    the EXTERNAL BD_23_0_n_IN side of the split bidirectional bus port - during CPU
    cycles the address is on OUR OWN drivers (BDLBD releases to all-ones), so the
    74534s froze the idle bus (all-ones -> inverted to 0 readback). Fix: feed the
    wired-AND `BD_n_IN & BD_n_OUT` (one line). Same split-bidir modeling class as
    Issue A's DMA capture. PESDBG probe run proved the rest of the chain live
    (SPEA/SPES pulse, MOR25 fires, RERR/BLOCK latch, EPES/EPEA assert on TRA).
Remaining: regression suite over the BIF change (in flight), Tang rebuild+flash,
silicon All-tests re-run. Temporary probe to REMOVE: `ifdef PESDBG` block in
`Verilog/CPU-BOARD-3202/circuit/BIF_BCTL_6.v`. `Verilog/PAL/PAL_45001B.v` (BPAR, 8D - the PES/PEA strobe/freeze PAL) had
THREE inverted literals vs `DesignDocuments/PAL-Code/SRC/45001B.txt`:
- SPEA (strobes all 16 PEA bits + PES bits 7:0 = addr 23:16): used `DBAPR_n` where the
  PALASM pin DBAPR is ACTIVE-HIGH (needs `~port`), and `MR_n` where PALASM has `MR`.
  With MR_n=1 in normal operation SPEA was CONSTANT 0 - the address registers never
  captured ANY cycle; FPGA power-up zeros were read back = the exact symptom.
- SPES (PES bits 15:8): used `BLOCK25_n` where PALASM has `BLOCK25` - the freeze sense
  was inverted (could only strobe AFTER an error).
All other 45001B equations (BLOCK/PARERR/RERR) match the PALASM. Same transcription-error
class as Issue D's PAL_44306A and the earlier PAL_44801A IOD fix.
Capture chain (agent-traced, for validation): 77xxxxxx -> 44445B raises CRQ, no responder
-> DGA TOUT (DECODE_DGA_POW.v:256) -> BIF_BCTL_BDRV_7.v:252-254 MOR_n + forced BDRY ->
MEM_LBDIF_48.v:237 MOR25 -> 45001B BLOCK+RERR latch, strobes freeze; readback TRA PES/PEA
-> DGA XPEN/XPAN -> IO_DCD_38.v:496-497 PS_n/PA_n -> BIF_BCTL_6.v:230-244 EPES/EPEA
(gated on RERR latched) -> BIF_DPATH_PESPEA_13.v 74534s onto IDB.
KNOWN RESIDUAL RISKS: (a) whether TOUT/MOR25/RERR actually fire on the Tang for 77xxxxxx
(Issue B(old) family) - sim evidence says the TOUT/MOR decode works in Verilator (77# ->
MOR-fail); (b) parity paths are HARD-DISABLED (`MEM_43.v:234` LPERR_n forced 1,
`ND3202D.v:819` s_ibperr_n forced 1) - irrelevant for test 11 (MOR-gated) but will break
any diagnostic that provokes REAL parity errors.
VALIDATION OWED: Verilator PAGING test 11 (after the sim slot frees), regression suite,
then Tang rebuild+flash and silicon re-run of All-tests.
- Symptom (Tang, all-tests run after the Issue-D fix): tests 1-10 pass, test 11 aborts
  with 10 errors, all of the form "Wrong address found in PES/PEA registers": expected
  77777777B / 77776000B / 77774000B / 77772000B / 77770000B (top of the 24-bit physical
  space, both "24 bits Direct" and "Through Paging" modes), found 00000000B every time.
- Reading: the test provokes accesses at high physical addresses and expects the
  parity-error address/status capture chain to latch the PHYSICAL ADDRESS into PEA (and
  status into PES) for readback via TRA PES/TRA PEA. We return 0 -> either the capture
  chain never latches (enable/strobe path), the physical address never reaches the
  latch (24-bit path truncated), or the IDB readback path is broken.
- Suspect RTL: `Verilog/CPU-BOARD-3202/circuit/BIF_DPATH_PESPEA_13.v` (PES/PEA capture),
  its enables from the BIF control PALs, the 24-bit LBD/PPN address path feeding it, and
  the TRA PES/PEA IDB readback decode. Oracle behavior: nd100x `src/cpu/cpu_mms.c` /
  device model for PES/PEA semantics.
- NOTE: memory beyond installed sim/FPGA RAM (4MB Tang SDRAM vs 16MB addressed) - the
  test may rely on accesses to NONEXISTENT memory producing a a parity/timeout capture;
  behavior may interact with Issue B(old) (TOUT on silicon).
- ORACLE CONTRACT (nd100x, 29-JUL agent analysis; oracle PASSES test 11 with the same
  4MB): PES/PEA latch on MEMORY OUT OF RANGE - any physical access (read or write) with
  no responding memory latches PEA = phys addr bits 15:0 and PES bits 7:0 = phys addr
  bits 23:16 (PES bits 12:8 = ECC syndrome on the parity path only, 0 for MOR; bit 13 =
  fatal), and raises internal-interrupt level 14 IID bit 9 (MOR) / bit 8 (PTY). Capture
  happens INDEPENDENT of interrupt enables. FIRST error wins: both registers lock until
  a TRA PEA executes (TRA PES = pure read, no side effect; TRA PEA re-arms both locks;
  values are never zeroed, only re-armed). For 77777777B: PEA=177777B, PES=000377B; all
  five test addresses share PES=377B and differ in PEA. nd100x refs: cpu_mms.c:1027-1036
  (HandleMemoryOutOfRange), 938-941/991-994 (call sites), 858-911 (ECC simulate path,
  comment names PAGING test 11), cpu_regs.c:49-64 (locks), cpu_instr.c:3619-3641
  (TRA PES/PEA). Our returning 0 = the MOR->PES/PEA ADDRESS CAPTURE path missing/unwired
  in RTL (adjacent to the known MOR level-12/TOUT wiring in BIF_BCTL_BDRV_7.v).

## Issue G — CONFIGURE detects local memory as MPM5, not local  [LOW-PRIO, 29-JUL, silicon]
STATUS: OPEN, low priority (fix later if time permits). Reported by Ronny 29-JUL:
- TPE CONFIGURE test program ran COMPLETELY OK on the Tang except one detail: it
  detects local memory as "MPM5" (multiport memory) instead of LOCAL memory.
- Ronny's read: related to the ECC logic. nd100x has code enabling ECC bit-error
  reporting (see `src/cpu/cpu_mms.c` ECC-simulate path around lines 858-911 and the
  ECCR register handling, `cpu_instr.c` TRR ECCR / IOX 100115) - CONFIGURE likely
  probes ECC behavior (or the ECC-related ID/status) to classify memory type.
- Constraint: our Verilog does NOT store ECC detail bits in RAM - we store data + 1
  parity bit per 8 bits (as a memory-saving choice on the Tang; the original design
  stores more ECC state). Full local-memory ECC semantics may be IMPOSSIBLE without
  widening RAM - OR the classification may just be a few wrong wires in the memory
  section (memory-type ID readback), independent of real ECC storage. UNKNOWN which.
- MECHANISM MEASURED (29-JUL agent, gdb on the oracle - oracle classifies all banks
  Local): CONFIGURATIO-D05:TEST `print-memory-map` probes EVERY 16Kw block with:
  TRR ECCR := 0o11 (simulate-data-bit-0 + DisableECC) -> WRITE one word in the block
  (must latch "bad ECC" even with disable set) -> TRR ECCR := 0o04 (sim off,
  interrupt-on-all-errors on) -> READ back. Block answers with level-14 PTY interrupt
  (IIC 10 octal) + PES/PEA loaded => "Local"; block silent (data fine, no interrupt)
  => "Mpm 5" - EXACTLY our FPGA behavior (ECC-simulate probe answers nothing).
  Also one IOXT to 100115 octal (ECCR bus window) that must ACK, not IOX-error.
  PES = (errorCode<<8)|addr[23:16] with code 3 for the bit-0 case, PEA = addr[15:0],
  lock until TRA PEA. With ECCR bit2=0 a single-bit error must NOT interrupt (WALK
  diagnostic deadlocks otherwise). nd100x refs: cpu_mms.c:817-911 (latch+detect),
  cpu_instr.c:3824-3825 (TRR ECCR), 1605-1624 (IOXT 100115), cpu_regs.c:48-64.
- FEASIBLE WITHOUT STORED ECC SYNDROME: YES. The probe needs ONE bit of per-word
  state ("written while simulate armed"), never reads syndrome from RAM. Our
  1-parity-bit-per-byte store suffices: when ECCR bit0 armed, write the byte parity
  INVERTED; on read with detection enabled, bad parity -> PES/PEA latch (synthesize
  code 3 constant) + level-14 PTY. Caveat (UNKNOWN): whether CONFIGURATION checks
  exact PES code bits or just interrupt+nonzero PES - reproducing code 3 matches the
  oracle bit-for-bit either way. Prereq: un-disable the parity paths
  (`MEM_43.v:234` LPERR_n forced 1, `ND3202D.v:819` s_ibperr_n forced 1) and wire
  ECCR (TRR + IOX 100115) into the memory section.
- Agent trace artifacts (scratchpad, session 61614461): gdb_out.txt (probe event
  stream), guest_out.txt/conf2_out.txt (oracle Local memory map), eccr.gdb.

## Issue H — RESOLVED 29-JUL: MEMORY D04 WALK TEST is SLOW, not hung
STATUS: NOT A BUG (behavioral). Ronny's follow-up the same evening: left running, the
WALK TEST (34 PATTERNS) prints === END OF TEST === and MEMORY proceeds to
"=== THE TESTS ARE NOW LOOPING ===" (normal continuous mode). ALL FIVE MEMORY D04
sub-tests pass on the Tang. The long runtime is expected work (34 walking patterns
over 4MB at the 6.75 MHz slow variant); possibly compounded by the Issue-E timing
family but there is no failure. No action. (Original report kept below for record.)
- Symptom: `load mem` (MEMORY - Version: D04 - 1988-02-01, total memory 4.000 Mbytes),
  `run`: READ TEST ON PROGRAM PART, ADDRESSES IN ADDRESSES, WRITE/READ TEST (7
  PATTERNS), RAPIDLY CHANGING ADDRESS BITS all print === END OF TEST ===; then
  "WALK TEST (34 PATTERNS)" never finishes (hang, no output).
- Untriaged. Candidate directions (NOT verified):
  (a) legitimately slow, not hung - 34 walking patterns over 4MB at the 6.75 MHz slow
      variant could take very long; needs a bounded-wait measurement before calling it
      a hang (how long was it left running?).
  (b) genuine hang in the walk pattern's access sequence - possibly the same
      memory-path timing family as Issue E (`#` slow, silicon-only TOUT divergence).
  (c) ECC interaction: nd100x cpu_mms.c:884-895 comments that WALK deadlocks if
      single-bit (simulated) errors interrupt when ECCR bit2=0 - on our board ECC is
      absent entirely (no interrupts), so the nd100x-style deadlock shape does not
      apply directly, but WALK clearly exercises the parity/ECC corner (Issue G
      neighborhood).
- Triage order when picked up: reproduce in Verilator (`load mem`, `run`, watch for
  the WALK banner + progress vs wedge; CSA sample if wedged), and time-box the Tang
  run to distinguish slow-vs-hung.

## Issue I — RESOLVED 30-JUL: no bug in the current build; two overlapping artifacts
STATUS: CLOSED by measurement (serial-driven, capture-armed session, 30-JUL afternoon):
- OPCOM `#`: 13/13 clean passes cold on the final build; `1560&` boots warm; CONFIGURE
  completes; PAGING/MEM pass. NO wedge reproducible.
- The morning `#` hangs / `1560&` `?` were RESIDUE: tests ran without a power cycle
  after the OLD build's CONFIGURE crash left TST latched (all memory writes broken
  until master clear) - see Issue F/G section for that mechanism, since fixed.
- SECOND artifact discovered and PROVEN: openFPGALoader (WSL/usbipd) loads - SRAM OR
  flash - leave the board WEDGED (dead console) until a PHYSICAL power cycle. Every
  "dead build" of the afternoon was this. RULE: after any openFPGALoader operation,
  power-cycle the Tang before judging the design. (Also: never run two Gowin builds
  into the same build dir concurrently - one afternoon bitstream was a collision
  product.)
- The 40s-arm analyzer capture build remains built (and currently in flash, with the
  UART dump muxed OFF via the diagnostic TX bypass); the arm-widening in
  ND120_TANG20K_TOP.v is a keeper (the old 2.5s arm false-triggers during the WCS
  load phase where CSA is static).
(Original open entry kept below for the record.)
STATUS(orig): capture campaign STARTED, blocked on a tooling snag; full pair tree in place.
- Symptoms (Tang, full-batch+pair build): OPCOM `#` echoes then HANGS the machine;
  `1560&` returned `?` once at first power-on, fine after reset; CONFIGURE + PAGING +
  MEM + INSTRUCTION all load/run. Sim-clean (`0#` -> `#0##`, floppy boots repeatedly).
- Suspect set (SILICON-ONLY margin/timing): the 44403C/44310D/44302B trio; ranked
  44302B DSTB (+ CDLBD mode-3 coupling) > 44310D BDRY (DMA-hold) > 44403C (global).
  Ronny's ruling: NO blind bisect - debug at signal level with the on-chip analyzer.
- Iteration 1 prepared: TANG_GRANT_CAPTURE build (hang-triggered CSA capture, probe
  {3'b0,CSA[12:0]}, bitstream built 12:24 30-JUL) - but the SRAM load
  (openFPGALoader without -f) configures OK ("Done") yet the design never comes up
  (no console, no dump). Same flow worked 27-JUL (scratchpad tang_*.py /
  grant_capture.py). TO DEBUG NEXT SESSION: diff vs the 27-JUL procedure (flash-vs-
  SRAM, reset knob, arm-time false-trigger during WCS load - CSA is STATIC in the
  load phase, so the 0.31s hang detector may fire instantly and latch dbg_dumping
  with a dead dbg UART...). Defines restored OFF after the attempt; the FLASH still
  holds the good full-pair build - power-cycle recovers the board.
- Next capture iterations once loading works: 1) CSA-at-wedge for `#`; 2) repack to
  {TERM_n,CC*,BDRY,DSTB,EMD} (the CC_TERM probe pattern already documented in
  ND120_TANG20K_TOP.v) for the implicated handshake.

## Issue D(orig) — PAGING Test 3 (PGU/WIP) crashes  [REPRODUCED IN VERILATOR 27-JUL -> RTL BUG, debuggable]
CONFIRMED: with the injector prompt-wait fix (Run120.cpp -2 quiet-wait after \r) a scripted
`1560&load pag\rrun\r3\r` in FF-mode Verilator (obj_dir_vflop) drives cleanly and PGU/WIP test 3
REBOOTS the CPU (fresh `TPE Monitor B01` banner after "3. PGU/WIP bits for all PITS and ENTRIES") -
same as the Tang. So NOT silicon-only; it's an RTL/microcode bug reproducible with full observability.
The reboot = an unhandled trap/fault -> master-clear/restart during the PGU/WIP page-status
manipulation (neighbour: the fixed CGA_TRAP_TVGEN_P2 PGF+PGU trap-vector bug; possibly another
trap-vector or MMU-status-bit issue). NEXT: TRACE_CSA the run, find the CSA/trap sequence at the
reboot (jump to the restart vector). Injector fix (Run120.cpp) is uncommitted - a real harness
improvement, commit later.

## Issue D(old) — PAGING Test 3 (PGU/WIP bits) crashes/reboots the CPU  [triage first]
SYMPTOM (Tang): PAGING Tests 1-2 pass; Test 3 "PGU/WIP bits for all PITs and ENTRIES" ejects back to
the TPE monitor (fresh banner = CPU reset). A PGU/WIP-related fault hitting an unhandled trap would
reset the CPU. Neighbours: the earlier trap-vector fix (`CGA_TRAP_TVGEN_P2.v`) was a `PGF+PGU` case;
per memory `nd120-cache-never-validated` the MMU status-bit features have never been functionally
validated (may be always-broken, not a regression).

- **Verilator plan (triage):** boot `1560&` in Verilator, `load pag`, at the "Test number(s)" prompt
  select ONLY test 3 (skip the slow Tests 1-2). Does it crash/reset in sim too?
  - Repros in sim -> RTL bug: trace the PGU/WIP page-table update + the trap/CSA at the reset moment
    (TRACE_CSA) to find the unhandled trap / bad microcode jump. Fix in the MMU/trap RTL.
  - Clean in sim -> SILICON-ONLY -> on-chip capture (like Issue B).
- **Tang:** re-flash, re-run PAGING all-tests -> Test 3 completes.

---

## Issue E — OPCOM `#` memory test is SLOW (~6 sec, normally instant)  [Ronny 27-JUL: memory-size/MOR]
SYMPTOM (Tang, CORRECTED): the `#` memory test does NOT hang - it takes ~6 sec where it is normally
instant. Ronny: "something wrong with memory size / MOR (Memory Out of Range) detection."
UNIFYING ROOT (likely = Issue B on the MEMORY path): the memory-size scan probes addresses and relies
on **MOR firing at the real 4 MB boundary** to stop. MOR is gated by the SAME `TOUT` as IOXERR
(`BIF_BCTL_BDRV_7.v:252` `s_mor_n = s_tout ? s_mem_n : 1'b1`). If out-of-range memory reads "answer"
(spurious response) or MOR fires only slowly, the scan doesn't terminate at the boundary and grinds ->
~6 sec. So Issue E is the memory-path twin of the config phantoms (Issue B, IO-path IOXERR). ONE root:
out-of-range accesses don't get a PROMPT timeout/MOR. May also underlie the general boot/exec slowness
(every out-of-range or slow-timeout access adds latency).
- **Verilator triage FIRST:** does the `#` memory-size/MOR path behave correctly in sim? NOTE config
  passed CLEAN in Verilator (no phantoms -> IO-path TOUT works in sim), so the IO side is sim-clean;
  need to check the MEMORY side. Boot to OPCOM `#` in Verilator, run `<bank>#` (incl. a high/out-of-
  range bank), MEASURE the tick cost and trace `MOR_n`/`TOUT`/`s_mem_n`/`BDRY` on out-of-range reads:
  does MOR fire promptly at 4MB, or does memory "answer" out-of-range? Fast+correct in sim -> silicon
  (Issue B class, on-chip capture). Slow/wrong in sim too -> RTL bug in the MOR/memory-decode path
  (fixable with full observability). Reuse `runSim/obj_dir_vflop` (no rebuild).
- If confirmed the `TOUT`/MOR root, fixing it (Issue B) likely fixes E + the config phantoms + the
  missing level-14 together, and may cut the boot slowness.

## Ordering
1. **Issue E FIRST (Ronny's steer)** — the `#` memory-test hang may be a common root of other hangs;
   triage in Verilator to classify (RTL vs silicon) and see if it's the `TOUT`/bus-timeout root shared
   with Issue B. Cheap (reuse obj_dir_vflop, no rebuild).
2. **Issue A** — it's the enabler and the fix is in-tree but not commit-ready; landing a robust
   version unblocks committing everything and keeps the 8 gates green.
2. **Issue C** (MOVEW) — repros in sim, self-contained, decisive test already designed.
3. **Issue D** (PGU/WIP) — triage in Verilator (test-3-only) to classify RTL vs silicon, then fix.
4. **Issue B** (TOUT) — silicon-only, needs the on-chip-capture workflow; do after the sim-reproducible
   ones (A/C/D) are landed so the board is otherwise clean when capturing.

## Standing rules for this work
- ONE Verilator run at a time; separate `obj_dir*` per build; logs < 1GB (window/bound them).
- Don't edit `Verilog/sim/`, `runSim/` CPU probes, or CPU/microcode owned by the concurrent CPU-debug
  session without coordination; device + DMA + BIF/DGA RTL is in scope here.
- Every RTL fix: re-run `make test` (the 48-gate suite) before declaring done; no commit while any gate
  is red.
