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

# HANDOFF - Tang page-fault campaign, evening 23-AUG-2026 (pre-reboot)

**Repo path:** `Verilog/fpga/tang-nano-20k/HANDOFF-pf-campaign-23aug-evening.md`
**Plan this extends:** `Verilog/fpga/tang-nano-20k/PLAN-pf-campaign-23aug.md`
(all of today's measurements are recorded there in place; this handoff is the
resume sheet).
External files live outside the repository under `$ND120_ORACLE_DIR` (Ronny's
standing rule: every campaign log/trace goes there; the directory also holds
the oracle trace files and `oracle_pf_full.log`).

Ronny is rebooting Windows. The Verilator run dies with WSL and is NOT the
priority - Ronny's explicit direction: **monitor and measure the TANG.**
Verilator has never completed a SINTRAN boot and never reproduced the Tang's
page-fault ERRFATAL; treat it as a unit-check tool only, not as the reference
for this bug.

---

## 1. What is PROVEN on the Tang (all measured today, one build per fact)

Failure under test: `20500&` -> 143 s -> ERRFATAL, L-reg 072627,
Perror 064406, IIC 3, every run, byte-identical.

1. **The page-fault trap DISPATCHES.** At the refaulting page (software
   PT 4 page 26 = raw LA[19:10] 0o1032, the page holding VA 064540) a
   committed no-permit access freezes with TVEC=1 latched, PT entry zero at
   the edge AND one edge later (not a late arrival), VACC=1.
   (`$ND120_ORACLE_DIR/tang_zeroread_run1.*`)
2. **The handler reads the CORRECT page from PGS**: PGS at the first EPGS
   after the fault = software 0o432 - matches the fault. The overwrite
   hypothesis is dead. (`$ND120_ORACLE_DIR/tang_zeroread_run2.*`)
3. **Page-table writes WORK on silicon**: 85 write pairs + 170 attempt words
   in the ring at the halt. SINTRAN demand-pages table 7 normally
   (grant 162000 / invalidate 000000 cycles on software pages 763-766) and
   **SINTRAN itself zeroes software page 760 (WNDN5) in a 757-766 sweep**;
   the fatal fault is a later ACCESS to page 760 - which the oracle never
   makes (the oracle uses page 761 next door, 288 times, never 760).
   (`$ND120_ORACLE_DIR/tang_ptwr_run2.*`)
4. **The storage cache is exonerated, triple null**: cache ON / masked OFF
   (`-DiscsUncached`) / not synthesized (`-NoStorageCache`) all reach the
   identical ERRFATAL in identical 143 s. No boot-speed difference either.
   (`$ND120_ORACLE_DIR/tang_s1_uncached_run.*`, `tang_s2_nocache_run.*`)

**The one open question, sharp:** the handler takes the 0o432 fault with the
correct page number and NEVER writes a resident entry for it (the write ring
shows the page's row written only as zero). Why does SINTRAN's fault service
decline this page on our machine while the oracle pages it in on demand?
Working chain to the halt: 0o432 never resident -> its contents execute as
zeros (STZ at 064540, proven by the earlier JPL capture) -> an address
computed from zeroed state lands on page 760 instead of 761 -> SINTRAN's
WNDN5 branch = ERRFATAL.

## 2. What was WRONG today (do not rebuild on these)

* "Zero page-table write strobes in Verilator" - grep artifact (the `WR`
  probe lines carry a `t=` timestamp; match `"WR  addr="`). Corrected:
  writes land 1:1 with attempts in sim.
* Tang ptwr run 1 "zero records" - VOID, not zero: the ERRFATAL trigger
  lacked `ND120_PC_ON_DBG_PORT` (fix now in `Verilog/DELILAH-CPU/CGA/circuit/CGA.v`),
  the dump never started. An absent dump is never a zero.
* The IIC-7 line of work stays retracted
  (`Verilog/fpga/tang-nano-20k/HANDOFF-iic7-verilator-only-retraction.md`).

## 3. Resume checklist after the Windows reboot

1. `Verilog/fpga/tang-nano-20k/usb-attach.sh` to re-attach the board
   (usbipd); console is `/dev/ttyUSB1` at 9600.
2. The FPGA config is volatile - reflash the wanted bitstream with
   `~/oss-cad-suite/bin/openFPGALoader -b tangnano20k <fs>`; bitstreams
   build with `gowin_build.ps1` (PowerShell, Windows Gowin at
   `C:\Utils\Gowin\...`). Build switches that exist today:
   `-PfCapture` (freeze register, retargeted to the no-permit-access
   trigger at raw 0o1032), `-PtwrCapture` (page-table write-history ring),
   `-DiscsUncached`, `-NoStorageCache`.
3. Runner scripts (each sends `20500&` with 0.30 s per-character pacing,
   logs with timestamps, decodes at window close):
   `Verilog/fpga/tang-nano-20k/pf_capture_run.py --zeroread` and
   `Verilog/fpga/tang-nano-20k/ptwr_capture_decode.py`.
4. All of today's edits are UNCOMMITTED in the working tree. Touched files:
   `Verilog/DELILAH-CPU/CGA/circuit/ND120_PF_CAPTURE.v` (no-permit trigger,
   c_pgs_at_read in the readout word), `.../CGA.v` (instance retarget +
   trigger define), `Verilog/CPU-BOARD-3202/circuit/CPU_MMU_24.v` (DBG_PTW
   write/attempt emitter), `CPU_15.v` / `ND3202D.v` / `Verilog/ND120_CORE.v`
   (DBG_PTW pass-through), `Verilog/fpga/tang-nano-20k/src/ND120_TANG20K_TOP.v`
   (TANG_PTWR_CAPTURE variant + TX branch), `gowin_build.ps1` (new switches),
   `Verilog/SD-FAT/circuit/nd_storage.v` (ND_STORAGE_NO_CACHE),
   `Verilog/CPU-BOARD-3202/circuit/sim/PGF_COMMITTED_ACCESS_tb.v` (+Makefile
   +`Verilog/tests/run_all_tests.sh` registration),
   `Verilog/DELILAH-CPU/CGA/sim/ND120_PF_CAPTURE_tb.v` (check 16),
   the two runner scripts, and the plan/handoff documents.
5. Unit gates that must stay green: `make test-pf-capture` (CGA/sim),
   `make test-pgf-committed` / `test-pgf-committed-ff` (CPU-BOARD sim dir).

## 4. The next TANG measurement (the campaign's actual next step)

Answer "what does the handler READ between the fault and its decline" ON THE
BOARD. Two candidate captures, one build each - pick one:

* **(A) Handler read-stream capture:** extend the DBG_PTW emitter in
  `Verilog/CPU-BOARD-3202/circuit/CPU_MMU_24.v` with a third tag for
  IDB-directed PT reads (`EPTI_n` low, WRITE low - the RDI condition), ring
  armed to freeze on the FIRST fault at raw 0o1032. The ring then holds the
  table entries the handler consulted while deciding. Small emitter change +
  a trigger tweak in the top; everything else exists.
* **(B) Handler instruction-path capture:** `TANG_PC_HISTORY` variant
  re-armed with its freeze on the first 0o1032 fault (it already carries
  {PIL,P}) - shows WHERE in SINTRAN the decline branch goes, to be read
  against the SINTRAN listing (`SYMBOLS/M06`, resident list SYMBOL-2-LIST;
  the NPL source root is on the machine - see the memory index).

Reading `IPAGFAULT` in the SINTRAN NPL source names the exact variables the
handler consults and would make either capture surgical - Ronny had not yet
answered whether to open the source; ask before scan-reading it.

## 5. Today's collected files (all under `$ND120_ORACLE_DIR`)

`tang_zeroread_run1.*`, `tang_zeroread_run2.*` (freeze-register runs),
`tang_ptwr_run1.*` (void - trigger bug), `tang_ptwr_run2.*` (write history),
`tang_s1_uncached_run.*`, `tang_s2_nocache_run.*` (cache experiment),
build logs `tang_pfcap_zeroread_build*.log`, `tang_ptwr_build*.log`,
`tang_s1_uncached_build.log`, `tang_s2_nocache_build2.log`; Verilator-side
`v23_*` (probe logs; the sim serviced 30+ faults correctly, wrote 17k PT
entries, never reproduced the ERRFATAL, console stayed at 7 bytes through
115 disc operations - it dies with the reboot and does not need restarting
for the Tang work). Log allowance for this directory: 10 GB per file
(Ronny, 23-AUG); do not trim or deduplicate campaign logs.
