# PRIORITY PLAN - Tang page-fault root cause (post-reboot, 23-AUG-2026 evening)

**Repo path:** `Verilog/fpga/tang-nano-20k/PLAN-pf-campaign-prio.md`
**Supersedes as the working order:** the phase list in `PLAN-pf-campaign-23aug.md`
(that file keeps every measurement record; this one is the ordered to-do list).
**Resume sheet:** `HANDOFF-pf-campaign-23aug-evening.md`.
**Direction (Ronny, 23-AUG):** the TANG is the target and the reference.
Verilator = unit checks only; it has never booted SINTRAN or reproduced this
fault. No Verilator boot monitoring counts as progress on this plan.

External files: `$ND120_ORACLE_DIR` (all logs/traces; 10 GB per file allowed
for campaign logs, never trimmed).

---

## Standing facts (measured on silicon 23-AUG - build nothing that contradicts them)

| # | Fact | Evidence |
|---|------|----------|
| F1 | The fault at the VA-064540 page (software PT 4 page 26 = raw 0o1032) DISPATCHES: TVEC=1, PT=0 at the edge and after, VACC=1 | `tang_zeroread_run1.*` |
| F2 | The handler reads the CORRECT page from PGS (software 0o432) | `tang_zeroread_run2.*` |
| F3 | Page-table writes WORK; SINTRAN demand-pages table 7 and ITSELF zeroes software page 760 in a 757-766 sweep; the fatal fault is a later ACCESS to 760 (oracle only ever touches 761) | `tang_ptwr_run2.*` |
| F4 | Storage cache exonerated: on / masked off / not synthesized -> identical 143 s ERRFATAL; no speed gain | `tang_s1_*`, `tang_s2_*` |
| F5 | Unit level: the zero-PTe trap chain works in both clock modes | `PGF_COMMITTED_ACCESS_tb.v` |

**THE open question:** with F1+F2 true, SINTRAN's fault service never writes
a resident entry for page 0o432 (its row is only ever written as zero). WHY
does the handler decline this page on our machine while the oracle pages it
in on demand (`oracle_pf_full.log` line 49)?

Working chain to the halt: 0o432 never resident -> its contents execute as
zeros (STZ at 064540, JPL capture) -> an address computed from zeroed state
lands on page 760 instead of 761 -> WNDN5 branch -> ERRFATAL.

---

## Phase 0 - Recovery  `[x] DONE 23-AUG evening`
- [x] Working tree intact after reboot (16 edited/new files present, uncommitted)
- [x] Unit gates green: `test-pf-capture` (both modes), `test-pgf-committed`, `-ff`
- [x] Campaign logs present on `$ND120_ORACLE_DIR` (29 files)
- [ ] Board attached: `usb-attach.sh` needs `TANG_BUSID` - two 0403:6010
      devices on the host (busid 3-1 and 3-4; the other is the Nexys 4 DDR).
      **Ronny names the Tang busid.** Then reflash (bitstream is volatile).

## Phase 1 - MEASURED 23-AUG evening (results below); Phase 1b is the next step

### What Phase 1 measured on silicon (9 capture builds, all logs in $ND120_ORACLE_DIR)
| # | Measured | Evidence |
|---|---|---|
| P1 | The handler runs SINTRAN's PAGEFAULT normally and reaches `CALL SEGIN` | t7.seq, t8.seq |
| P2 | It executes SEGIN's DISC-READ body (036724..036726) - proven with a 3-word range trigger the P-ring's +-1 ambiguity cannot fake | t8.seq |
| P3 | MLRESERVE's 50 code words in Tang RAM are identical to the oracle's executed opcodes | tang_mlreserve_memcmp3.log |
| P4 | The resource word MLRESERVE tests (bank 1, 137007) = 046737 on both machines | tang_bank1_probe.log |
| P5 | The Tang WRITES a granting page-table entry for the faulting page: raw 001032 <- 066001 (RPM,FPM,PGU set) | tang_ptwr_run2 decode |
| P6 | Segment tables read correctly (LIMCHECK's LDDTX returns the oracle's LOGAD/SEGLE for FILSEGM and SEGMA) | tang_lddtx_disp_probe.log |
| P7 | No-permit accesses to raw 0o1360 (software page 760, the ND-500 window) occur ONLY inside the ERRFATAL printer path (031354..031451, 004541..004547) - NOT during the boot that leads to the halt | t9.seq |
| P8 | Perror 064406 lies in the SAME page as 064540 (page 0o32 -> software 0o432), so the fatal fault is on that page | arithmetic on the halt signature |

### Retracted this evening (do not rebuild on these)
* "MLRESERVE returns A<0 / SEGIN never reads the disc" - artifact of reading
  single P samples from a ring with +-1 ambiguity (P2 disproves it).
* "The fatal page is 760" as a CAUSE - P7 shows 760 is touched only while the
  error message is printed. The stale-PGS reading recorded on 21-AUG
  (PLAN-pagefault-root-cause Phase 4) is the better explanation of why
  SINTRAN's WNDN5 branch fires.
* "Page 0432 is never paged in" - P5 shows a granting entry IS written on
  silicon; that claim came from the unfinished Verilator run only.

## Phase 1b - the contradiction to resolve first  `[ ] NEXT`
P5 (a granting entry IS written for page 0432) and the freeze register's
capture of a NO-PERMIT access at that same page cannot both describe the same
moment. Resolve by ORDER, in one build: record, with timestamps from the same
counter, (a) the write of raw 001032 and (b) each no-permit access at that
page. If the no-permit access comes AFTER the granting write, the map RAM is
not retaining or not returning the entry - a hardware defect in the PT RAM
read path (Issue-D family). If it comes only BEFORE, the paging is working
and the halt cause is elsewhere - then chase the fault at Perror 064406
directly (same page, so the freeze target stays raw 0o1032, but trigger on
the fault that is followed by the ERRFATAL printer rather than the first one).

## Phase 1 (original wording, kept for reference)
One Tang build. Two candidate captures - Ronny picks (decision pending):
- **(A) Handler read-stream:** third record tag in the `DBG_PTW` emitter
  (`Verilog/CPU-BOARD-3202/circuit/CPU_MMU_24.v`) for IDB-directed page-table
  READS (`EPTI_n` low, WRITE low), ring frozen on the first 0o1032 fault.
  Shows WHICH table entries the handler consulted. ~1 h incl. build+run.
- **(B) Handler instruction path:** `TANG_PC_HISTORY` ({PIL,P} ring) with its
  freeze moved to the first 0o1032 fault. Shows WHERE in SINTRAN the decline
  branch goes; read against the listing (`SYMBOLS/M06`, SYMBOL-2-LIST).
  Smallest change (retarget an existing variant). ~45 min.
- **(S) Source first:** read `IPAGFAULT` in the SINTRAN NPL source (ask
  before scan-reading - standing rule) to name the exact variables the
  handler tests; then A or B becomes surgical. ~30 min, no board.
Suggestion: **S then B** - B is the cheapest build and, with the source
read, its P-register trail maps straight onto the decision code.
- [ ] Decision A / B / S recorded here
- [ ] Build, flash, run, decode; result appended to `PLAN-pf-campaign-23aug.md`

## Phase 2 - The oracle's SAME fault, from the trace files (no board, no sim)
`$ND120_ORACLE_DIR/oracle_full.trc` (25M instructions, full registers) holds
the oracle's service of fault #49 (VA=064540, PT=4, VPN=26) instruction by
instruction. Extract the handler's path and the registers/memory it used
(via `oracle_make.sh` regeneration if a window with memory reads is needed;
NEVER the DAP debugger). Diff against Phase 1's silicon trail: the first
instruction where the two paths split, and the value that split them, is
the root-cause candidate.
- [ ] Oracle handler trail for fault #49 extracted to `$ND120_ORACLE_DIR/oracle_fault49_trail.txt`
- [ ] Split point named (instruction address + the differing value)

## Phase 3 - Name the mechanism and fix it
From the split value, decide which it is and name file + line:
- a memory value that differs (loaded from disc, computed, or read through a
  non-resident page earlier) -> trace it back to its producer on the Tang
  (one targeted capture, same framework);
- a register/flag behaviour that differs (ND-120 RTL) -> unit testbench
  first (`PGF_COMMITTED_ACCESS_tb.v` pattern), then fix.
- [ ] Mechanism named with file:line (or SINTRAN symbol + the wrong value)
- [ ] Fix applied (one change) and the reproducing unit test added to
      `Verilog/tests/run_all_tests.sh`

## Phase 4 - Validate - tasks in this order, stop at the first red
- [ ] `make test` (fail-fast: re-run entries after any failure by hand)
- [ ] `make test-instr` (13 instruction-verify areas)
- [ ] Tang boot `20500&`: the 143 s ERRFATAL must be gone; report the new
      landmark reached (banner target at landmark ~986-1195)
- [ ] Commit only when Ronny says so (no commits/branches without permission)

## Parked (do not pick up without a new reason)
- Verilator SINTRAN boot (serviced faults, never reproduced the ERRFATAL,
  7-byte console at 134 disc ops when the reboot killed it) - unit checks only.
- Storage cache variants - closed by F4; levers kept (`-DiscsUncached`, `-NoStorageCache`).
- IIC-7 / IDENT PL10 line - retracted (`HANDOFF-iic7-verilator-only-retraction.md`).
- v24 leg-probe engine - built on a retracted premise; nothing to learn from it.

## Uncommitted edits in the tree (all from 23-AUG; keep until Ronny decides)
`ND120_PF_CAPTURE.v` (+tb), `CGA.v`, `CPU_MMU_24.v`, `CPU_15.v`, `ND3202D.v`,
`ND120_CORE.v`, `ND120_TANG20K_TOP.v`, `gowin_build.ps1`, `nd_storage.v`,
`PGF_COMMITTED_ACCESS_tb.v` (+Makefile, +`run_all_tests.sh`),
`pf_capture_run.py`, `ptwr_capture_decode.py`, the three plan/handoff docs.

## Phase 1b - run 10: the ordering build (23-AUG-2026, in progress)

Built as `TANG_PTORD_CAPTURE` (`gowin_build.ps1 -PtOrder`). One ring, written
in time order, carries BOTH event kinds for raw page 0o1032 (software 0o432):

| record | meaning |
|---|---|
| `0xB` + DBG_PTW word | page-table write traffic at raw index 0o1032 only |
| `0xC` + count | a committed no-permit access at that page |
| `0xD` + count | a page-fault vector at that page |

No shared timestamp is needed - ring order IS the order. At most 4 consecutive
access markers are recorded between writes so the writes cannot be evicted by
the endless refaults; the 12-bit counter in every marker states the true total,
so a suppressed run is visible rather than silent.

Verdict rule, applied by
`Verilog/fpga/tang-nano-20k/ptord_capture_decode.py`:

- a no-permit access AFTER the granting write -> the map RAM is not retaining
  or not returning the entry: a defect in the page-table RAM read path
  (Issue-D family).
- every no-permit access BEFORE it -> paging works on this page; the next
  target is the fault at Perror 064406.

Files changed for this run (all absolute):

- `Verilog/DELILAH-CPU/CGA/circuit/ND120_PF_CAPTURE.v`
  - new `evt_noperm` / `evt_fault` pulse outputs, NOT gated by `captured`.
- `Verilog/DELILAH-CPU/CGA/circuit/CGA.v`
  - `PF_CAPTURED` widened to `[2:0]` = {fault pulse, access pulse, frozen};
    `MATCH_LA_19_10` retargeted from 0o1360 back to 0o1032.
- `PF_CAPTURED` widened along the whole path: `CPU_PROC_CGA_33.v`,
  `CPU_PROC_32.v`, `CPU_15.v`, `ND3202D.v`, `ND120_CORE.v`.
- `Verilog/fpga/tang-nano-20k/src/ND120_TANG20K_TOP.v`
  - the `TANG_PTORD_CAPTURE` ring block and its `uart_txp` branch (without that
    branch synthesis strips the probe).
- `Verilog/fpga/tang-nano-20k/gowin_build.ps1`
  - `-PtOrder`, mutually exclusive with the other capture switches.

Checked before flashing: Verilator elaborates the Tang top clean in the
PTORD configuration and in the default / PFPATH / PTWR / PF configurations;
the decoder was verified against a synthetic ring.

### Run 10 RESULT (measured, 23-AUG-2026 23:04, log $ND120_ORACLE_DIR/ptord_run10.log)

The same ERRFATAL fired (L-reg 072627, Perror 064406, IIC 3 Page Fault), and
the ring holds the COMPLETE history of raw page 0o1032 since arming - 12
records, no wrap:

| # | record | data |
|---|---|---|
| 1 | ATTEMPT + WRITE raw 001032 | 000000 - cleared |
| 2 | ATTEMPT + WRITE raw 001032 | 000000 - cleared |
| 3 | ACCESS no-permit, FAULT, ACCESS, FAULT | - |
| 4 | ATTEMPT + WRITE raw 001032 | **062001** RPM=1 FPM=1 - GRANTS |
| 5 | ATTEMPT + WRITE raw 001032 | **066001** RPM=1 FPM=1 PGU=1 - GRANTS |

**VERDICT: every no-permit access precedes the granting write. Page 0o432
pages in correctly.** The contradiction is resolved in favour of the hardware:
the map RAM retains and returns the entry, the trap dispatches, the handler
services it, the write lands.

RETRACTED by this run: the whole "a non-resident page is read as zeros instead
of faulting" chain as an explanation of the halt, for this page.

The halt also printed two numbers worth keeping: **NPIT/APIT = 000012 /
000007**, and the fault is taken at **level 1**.

## Phase 1c - run 11: which fault actually halts SINTRAN

Built as `TANG_PFLOG_CAPTURE` (`gowin_build.ps1 -PfLog`). One record per
page-fault vector transition at ANY address, frozen by the ERRFATAL printer,
so the LAST record IS the fatal fault:

    record[16:10] = PT[15:9] (WPM RPM FPM WIP PGU ring1 ring0)
    record[ 9: 0] = LA[19:10], the raw page-table index

Decoder:
`Verilog/fpga/tang-nano-20k/pflog_capture_decode.py`

The two outcomes that matter:

- the fatal fault hits an entry that **grants nothing** -> ordinary demand
  paging; the question becomes why THAT page is never made resident, and the
  handler path for it is the next capture;
- the fatal fault hits an entry that **already grants** -> a fault on a
  granting entry is not demand paging at all: the permission compare or the
  entry read is wrong, and that is a hardware defect with a named page to
  chase it with.

Files changed for run 11 (all absolute):

- `Verilog/DELILAH-CPU/CGA/circuit/ND120_PF_CAPTURE.v`
  - new `evt_any` / `evt_any_la_19_10` / `evt_any_pt_15_9` outputs.
- `Verilog/DELILAH-CPU/CGA/circuit/CGA.v`
  - `PF_CAPTURED` widened to `[20:0]`; `TANG_PFLOG_CAPTURE` define block.
- `PF_CAPTURED` widened along the whole path: `CPU_PROC_CGA_33.v`,
  `CPU_PROC_32.v`, `CPU_15.v`, `ND3202D.v`, `ND120_CORE.v`.
- `Verilog/fpga/tang-nano-20k/src/ND120_TANG20K_TOP.v`
  - the `TANG_PFLOG_CAPTURE` ring block and its `uart_txp` branch.
- `Verilog/fpga/tang-nano-20k/gowin_build.ps1`
  - `-PfLog`.

### Run 11 RESULT (measured, 23-AUG-2026 23:4x, log $ND120_ORACLE_DIR/pflog_run11.log)

Same ERRFATAL (L-reg 072627, Perror 064406, IIC 3, NPIT/APIT 000012 / 000007).
512 page faults recorded, frozen by the printer.

**THE FATAL FAULT: raw 001360 -> software 000760, table 7 page 60, entry
000000 - grants nothing.** That is the ND-500 window page (WNDN5), and it is
the LAST fault before the ERRFATAL printer runs.

This CORRECTS run 9's reading. Run 9 recorded what ran AFTER the first
no-permit access to that page and found the printer, and that was written up
as "accesses to 760 happen only while the error message prints". The order is
the other way round: **the access to page 760 causes the fault, and the fault
service prints the message.**

Every one of the 512 recorded faults hit an entry granting nothing - the shape
of ordinary demand paging, so no permission-compare defect is visible. The two
faults immediately before the fatal one are on raw 001032 (page 0o432), the
page run 10 proved is granted straight afterwards.

Also recorded: 454 of the 512 records carry raw index 000000. They sit in the
OLDEST part of the ring and none appear in the last 30. Whether those are real
faults or a stale snapshot is NOT established - do not build on them.

**Where this points.** Perror 064406 is an address the oracle NEVER executes -
it only reads it (`oracle-never-executes-0644xx-gap`). In the oracle's memory
064406 holds `034703 = LDF ,B -75`
(`$ND120_ORACLE_DIR/oracle_0644xx_disasm.txt`). So an instruction at 064406
makes a data access that lands in page 760, where the oracle uses 761
(`oracle-never-pgs-0760-but-hammers-0761`). Two candidates, not yet separated:
the CPU is executing a region it should never have entered, or it is executing
the right code and forming an address one page low.

## Phase 1d - run 12: how the CPU reaches 064406

`gowin_build.ps1 -PcHistory` - the level-1 program-counter ring, deduped,
frozen by the same ERRFATAL printer signature. It holds the last ~512 distinct
level-1 addresses BEFORE the halt, so it shows the path into the 0644xx region
and whether 064406 is reached by a jump, by falling through, or by a dispatch.

### Run 12 RESULT - ROOT-CAUSE LOCATION (measured 24-AUG-2026, log $ND120_ORACLE_DIR/pchist_run12.log)

Level-1 program-counter trail into the halt:

    032120 -> 064540 064541 064542 064543 064544 064545 064546 064547
           -> 064404 064405 -> 064406 064407  (fault, ERRFATAL)

Oracle, `$ND120_ORACLE_DIR/oracle_full.trc` line 13698566:

    064540 021114  064541 146145  064542 146131  064543 170017
    064544 135111 JPL I 111 -> 004600 .. 004617 -> 064545 135111 -> 052031

**The two `JPL I 111` at 064544 and 064545 do not transfer control on Tang
silicon.** The CPU falls through to 064546, 064547 and then runs data at
064404/064406; that data access forms an address in software page 0o760, which
grants nothing, and that fault is the ERRFATAL.

Eight consecutive addresses - not the single-sample +-1 ambiguity that forced
the earlier retraction of the same claim.

This reclassifies runs 9-11 as consequences: page 0o432 pages in correctly, the
fatal fault's entry grants nothing for a legitimate reason, and page 760 is
only where the executed data points.

## Phase 2 - run 13: is it the fetched word or the decode

`gowin_build.ps1 -JplCapture` records, across exactly those two instructions,
the address bus, the fetched word on FIDBO, and the microcode address the
decode dispatched to.

- fetched word != 135111 -> the instruction fetch is wrong at that address;
- fetched word == 135111 but the microaddress is not JPL's -> the decode
  dispatches the wrong microroutine (compare
  `Verilog/tests/instruction-verify/ND110-ND120-MIC-MAP.md`);
- both correct -> the branch is lost inside the JPL microroutine itself.

### Run 13 RESULT - ROOT CAUSE (measured 24-AUG-2026, log $ND120_ORACLE_DIR/jpl_run13.log)

Microcode trail, each program-counter bump with the microaddresses after it:

    pc 64543 -> csa 2001 (MACL) -> pc 64544 -> csa 16543 -> 0 -> csa 6000
    pc 64544 -> csa 2001 (MACL) -> pc 64545 -> csa 16544 -> 0 -> csa 6000

`006000` = **STZ**, `007340` = **JPL**
(`Verilog/tests/instruction-verify/ND110-ND120-MIC-MAP.md`). CSA never reaches
007340 nor any conditional jump (007300-007334).

**The decode is not losing instruction bit 11. Every instruction in that
region is fetched as 000000 and executed as STZ** - 064543 (`SAB 17`) as much
as 064544 (`JPL I 111`). The oracle's memory holds real code there.

Put beside run 10: **the page is mapped and GRANTED (066001: RPM FPM PGU) and
its CONTENTS read as zero.** The page-table status bits are correct; the data
behind them is not.

## Phase 3 - the physical page number bank

`Verilog/CPU-BOARD-3202/circuit/CPU_MMU_24.v` carries the physical page number
on a path separate from the status bits: `PPN_25_10_IN` / `PPN_25_10_OUT`
(lines 56-57), and line 223 `PPN_25_10_OUT = s_pt_ppn_25_10_out |
s_ppnx_ppn_25_10_out`, with the PT map RAM, PPNX and the external PPN input
all on one node (lines 233-234). Run 10's `DBG_PTW` probe watched only the
STATUS bank strobe (`EPT_n & WMAP_n`).

TODO 3.1 - read the PT write path in the RTL and name the strobe that writes
the PHYSICAL PAGE bank (no board time needed).
TODO 3.2 - probe what that bank holds, and what PPN the fetch at 064544
actually presents, for raw index 0o1032.
TODO 3.3 - compare against the Issue-D fix (`PAL_44306A` EIPL, the PPN map RAM
write) which is already in the tree - the defect may be a second, similar
missing term rather than a regression of that one.

### Run 14 RESULT - the zeros are MEASURED, not inferred (24-AUG, log $ND120_ORACLE_DIR/jpl_run14.log)

`TANG_JPL_CAPTURE` extended with tag 2 = FIDBO, the word the CPU actually
receives. (The build script's help text claimed the old probe already recorded
FIDBO. It did not - it carried CSA and the program counter only.)

    385  pc   064544   <-- the first JPL I 111
    386  fid  000000   <-- the word the CPU received
    387  csa  000000
    388  csa  006000   <-- STZ

`135111`, the real `JPL I 111` opcode, appears NOWHERE in the ring. The decode
is innocent: it received 000000 and dispatched STZ correctly. **Memory delivers
zero.** The lost-instruction-bit-11 story is dead for good.

### The mechanism the RTL already documents

- `fpga/tang-nano-20k/sdram-bridge/MEM_RAM_49_SDRAM.v:17-21` - "Capacity: 2M x
  18-bit words = BANK0 + BANK2 (1M words each) = 4 MB. **BANK1 is not
  populated: never written, reads as 0**, so the ND-120's boot-time memory
  sizing simply detects two banks."
- same file line 415 - `bstate <= B_TAIL;  // BANK1 / no bank: not populated, do nothing`
- `PAL/PAL_44445B.v:65-67` - CPU-side bank decode from PPN21, PPN20:
  00 -> BANK0, 01 -> BANK2, **10 -> BANK1 (absent)**, 11 -> no bank.

A page whose physical page number lands in BANK1 is mapped, granted,
translated correctly, silently swallows the disc transfer, and returns 000000
on every read - with no bus error to tell SINTRAN. That is precisely the
measured behaviour.

The header's closing clause - "boot-time memory sizing simply detects two
banks" - is an ASSUMPTION written as fact and has never been verified.

Related, also unverified: `PAL/PAL_44446B.v:85` sets
`AOK = ~(BMEM_n | BD23 | BD22 | BD21 | MOFF)`, so local memory acknowledges a
BUS/DMA transfer only when BD21 = 0, while the CPU-side decode reaches BANK1
with PPN21 = 1. `ND-BUS-DEVICES/DMA/circuit/ND_DMA_MASTER.v:97` carries a full
24-bit address, so there is no truncation there.

## Run 15 - the physical page of the failing fetch

`DBG_PPN` = PPN[23:10] added through `ND3202D.v` (line 175 port, 248 assign) ->
`ND120_CORE.v` -> `ND120_TANG20K_TOP.v`, recorded as ring tag 3 inside the
`TANG_JPL_CAPTURE` window. Decoder prints the bank for each value.

- PPN[21:20] = 10 at that fetch -> the chain is closed: SINTRAN allocated a
  page into a bank this board does not have.
- a populated bank -> the absent bank is not the explanation and the zeros
  come from what is stored there; next question becomes the disc transfer.

### Two documentation defects found while reading the memory path (24-AUG)

1. **The docs contradict the RTL about WHICH bank is absent.**
   `Verilog/docs/nd120-dram-memory.md:239-241` says "2 banks of 1M words =
   4 MB - **BANK2 simply reports absent**", and line 251 says "**BANK0+BANK1**
   (still the full 4 MB)". The RTL says the opposite:
   `fpga/tang-nano-20k/sdram-bridge/MEM_RAM_49_SDRAM.v:17-21` populates
   **BANK0 + BANK2** and leaves **BANK1** absent.
   The RTL is the correct one, and it is checkable: `PAL/PAL_44445B.v:65-67`
   decodes PPN[21:20] as 00 -> BANK0 (words 0-1M), 01 -> BANK2 (words 1M-2M),
   10 -> BANK1 (words 2M-3M). So the contiguous first 2M words really are
   BANK0+BANK2, and the absent bank sits at the TOP, not in the middle.
   The doc needs correcting - as written it would send the next reader looking
   for a hole in the middle of physical memory that is not there.

2. **The Verilator harness cannot reproduce an absent-bank fault at all.**
   `docs/nd120-dram-memory.md:156`: `MEM_RAM_49_SIM.v` models **3 banks x 1M =
   6 MB** - every bank present. Any defect that depends on the Tang's missing
   third bank is invisible in simulation by construction. That is worth
   knowing before anyone tries to reproduce this campaign in Verilator.

3. `MEM_RAM_49_SDRAM.v:380` compares `{BANK2, AA_9_0}` (11 bits, max 2047)
   against `CPU_PART_ROWS[11:0]` (default 2048), so the partition check is
   always true and never carves anything out of the CPU's memory. That matches
   the intent at the default setting; it is only worth remembering if anyone
   lowers `CPU_PART_ROWS`.

### Run 15 RESULT - BANK1 EXONERATED (24-AUG, log $ND120_ORACLE_DIR/jpl_run15b.log)

`DBG_PPN` (tag 3) recorded alongside FIDBO. At the fetch:

    364  pc   064544
    365  fid  000000    <-- the word received
    366  ppn  003770    <-- the physical page for that access
    367  csa  000000
    368  csa  006000    <-- STZ

PPN 0o3770 = physical page 2040. PPN[21:20] = 01 -> **BANK2, POPULATED**,
row 1016 of 1024, and `{BANK2, AA_9_0}` = 2040 < `CPU_PART_ROWS` 2048, so the
bridge services the access.

**RETRACTED: the absent-BANK1 hypothesis.** The page is backed by real SDRAM
and still reads as zeros. Everything in the BANK1 chain (AOK/BD21, the
unpopulated third bank) is irrelevant to this fault.
[[tang-bank1-not-populated-reads-zero]] stays true as a board property but is
NOT the cause here.

Note for reading these dumps: PPN[23:10] and FIDBO are LIVE BUSES that change
every microcycle. Only the record immediately following the fetch-qualified PC
bump belongs to that fetch. The first decoder verdict scanned every value in
the window and wrongly reported "NO BANK"; it must key on the record right
after the PC bump.

## Run 16 - did ANY write ever reach physical page 0o3770

The page exists, the MMU points at it, and it holds zeros. So the disc data
was never stored there. The probe records every memory WRITE whose physical
page is 0o3770 together with its data, taken AT THE SDRAM BRIDGE - the last
point before storage.

- writes present with the right data -> the data was stored and something
  cleared or re-mapped it afterwards;
- no writes at all -> the Winchester transfer never targeted this page, and
  the question moves to the physical address the DMA presents versus the one
  the MMU later resolves.

# ============================================================
# RUN 16 - ROOT CAUSE (24-AUG-2026)
# ============================================================

Log `$ND120_ORACLE_DIR/pgw_run16.log`, decoder `pgw_capture_decode.py`.
Measured AT THE SDRAM BRIDGE, the last point before the chip:

    target page 2040: 0 writes, 26 reads
    page 1016:        many writes, carrying real code -
                      004600, 052031, 051632, 004624, 065000, 056460 ...

- The CPU READS physical page **2040** = {BANK2, row 1016}.
- The disc data was WRITTEN to physical page **1016** = {BANK0, row 1016}.
- Same row; the difference is exactly 1024 pages = **address bit 20**.
- The data is provably correct content: **004600** and **052031** are the two
  `JPL I 111` targets the oracle jumps to from 064544 and 064545.

**ROOT CAUSE: the disc transfer stores the segment one BANK low. The CPU then
reads the bank the MMU points at, which was never written.** Every earlier
measurement in this campaign follows from that.

## Where the bit is lost

The CPU and the bus decode the bank from DIFFERENT sources, identical logic:

- CPU read path: `Verilog/PAL/PAL_44445B.v:65-67` from **PPN20/PPN21**
- Bus/DMA write path: `Verilog/PAL/PAL_44446B.v:66-68` from **BD20/BD21**

DMA address path (no truncation anywhere): `ND_DMA_MASTER.v:230` drives
`BD_23_0_n_OUT <= ~s_addr` (24 bits) -> `ND3202D.v:533`
`s_ram_bd_23_19_n = s_bif_bd_23_0_n_out[23:19]` -> `MEM_43.v:196` ->
`MEM_ADEC_45.v:98-99` `s_bd20_n = BD23_19_n[1]` -> `PAL_44446B`.

**HYPOTHESIS, NOT YET MEASURED.** The bank bits and the low address bits are
captured by DIFFERENT STROBES: `PAL_44446B` is clocked on `DBAPR`
(`MEM_ADEC_45.v:308`) while the row/column latch `MEM_ADDR_44` latches
`LBD_19_0` on `BCGNT25` (`MEM_43.v:441`, whose comment says it was moved
earlier "before it goes away"). `ND_DMA_MASTER` holds the address on the bus
for only two clocks (`ST_ADDR`). If the DBAPR edge falls outside that window
the bank latches 0 while the row/column latch takes the right value - which
produces exactly the measured result: correct row, bank forced to 0. CPU
accesses use PPN20/PPN21, which are stable, so CPU reads and writes to the
same page stay correct.

## TODO next

- 16.1 Measure it: record the bank bits the BUS decoder latches together with
  `BD_23_19_n` and the `DBAPR` / `BCGNT25` edges during a Winchester DMA write.
- 16.2 If the strobe skew is confirmed, the fix is to latch the bank bits from
  the same strobe (and the same bus snapshot) as the row/column address.
- 16.3 Regression gate: a testbench that issues a DMA write to a BANK2 page and
  asserts the data is readable at the same physical address. This class of bug
  is INVISIBLE in Verilator (`MEM_RAM_49_SIM.v` = 3 banks, all present), so the
  gate must be an iverilog testbench on the board decode path, not a sim boot.

## Run 16 - PROOF that the write is MISPLACED, not absent

Searching the captured write stream for the oracle's content at the failing
address:

    oracle 064540..064547 = 021114 146145 146131 170017 135111 135111 124064 175035
    EXACT SEQUENCE FOUND in the writes to physical page 1016, at write index 82

The captured writes begin at 064416 and run contiguously, matching
`$ND120_ORACLE_DIR/oracle_0644xx_disasm.txt` word for word.

Window totals: **242 writes, all to page 1016 (BANK0); 26 reads, all from page
2040 (BANK2).** No write to any BANK2 page; no read from any BANK0 page.

The DMA reads the right data in the right order and stores it at the wrong
physical page. **The lost bit is address bit 20** (`PPN20` / `BD20`).

## THE DEFECT (found in RTL, 24-AUG-2026)

`Verilog/CPU-BOARD-3202/circuit/ND3202D.v:533`

    assign s_ram_bd_23_19_n[4:0] = s_bif_bd_23_0_n_out[23:19];  // for address decoding

Takes the bank-decode bits from what the BOARD DRIVES (`..._out`) instead of
what the bus CARRIES (`..._in`). During a DMA write the board drives nothing
and `BIF_DPATH_BDLBD_10.v:76` idles the output at `~24'b0` (all ones,
active-low idle), so BD23..BD19 all decode as 0 and `PAL_44446B.v:66` selects
**BANK0 for every DMA write**. The row/column come from `LBD_19_0`, captured
from the bus INPUT through the `TTL_74648` transceivers, so the row is right
and only the bank is wrong - the measured signature exactly.

The DMA address does reach the board (`ND120_CORE.v:1006` wired-ANDs the
Winchester master into `BD_23_0_n_IN`); it is never read. The same wrong bits
feed `AOK`, so the transfers are accepted rather than refused.

PROPOSED FIX (not applied - awaiting Ronny):

    assign s_ram_bd_23_19_n[4:0] = s_bif_bd_23_0_n_in[23:19] & s_bif_bd_23_0_n_out[23:19];

Wired-AND of both sides = the faithful shared active-low bus node, and stays
correct when the board is the master.

SUPERSEDED: the strobe-skew hypothesis (DBAPR vs BCGNT25) - plausible but
wrong; the bits are not late, they are taken from the wrong side and are never
present.

# ============================================================
# FIXED - SINTRAN III BOOTS (24-AUG-2026)
# ============================================================

Fix applied at `Verilog/CPU-BOARD-3202/circuit/ND3202D.v:533`, built, flashed,
booted. Log `$ND120_ORACLE_DIR/boot_after_fix.log`:

    09.46.45     16 SEPTEMBER   1994
    SINTRAN III - VSX/500 M
    STANDARD CONFIGURATION:    C
    GENERATION (WORK MODE NO.):      6B
    REVISION (PATCH FILE NO.):       0B
    CPU TYPE:      102
    CPU NUMBER:    120
    GENERATED:   09.45.00     16 SEPTEMBER   1994
    SINTRAN III RUNNING -
    PAGES FOR SWAPPING:   3074B

**No ERRFATAL.** The halt that hit at exactly 143 s on every previous boot is
gone. (The console is 7E2 and the log is raw bytes, so the text appears with
the high bit set - `SÉNÔÒAN`.)

## Still open

- TODO 16.3 regression gate: an **iverilog** testbench on the board decode path
  - DMA write to a BANK2 page, then read the same physical address. A Verilator
  boot cannot catch this class (`MEM_RAM_49_SIM.v` = 3 banks, all present).
- `Verilog/docs/nd120-dram-memory.md:239-251` still contradicts the RTL about
  which bank is unpopulated (doc says BANK2, RTL says BANK1; the RTL is right).
- All of this work is uncommitted on branch `nd-bus-seam-gate`.
