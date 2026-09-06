# PLAN: Nexys 4 DDR - from tape boot to SINTRAN (written 23-AUG-2026 evening, after the reboot)

Goal (Ronny, 23-AUG): boot SINTRAN on the Nexys. The work is an ordered list
of boot tests - each test must pass on the board before the next one is
attempted, because each test uses more of the hardware than the one before.
Companion evidence: `HANDOFF-floppy-dma-investigation.md`. Paths are
repo-relative. Nothing below is committed yet.

The tasks, in order (each is a boot test on the board):

| Task | What                                                     | Status 23-AUG            |
|------|----------------------------------------------------------|--------------------------|
| 1    | `400&` tape boot loads FILSYS (File System Investigator) | PASS on silicon          |
| 2a   | FILSYS inspects the floppy (FLOPPY-DISC-1, unit 0)       | PARTIAL: LIST-USERS PASS; LIST-FILE-NAMES root-caused = wrong indirect-jump address on silicon (FPGA timing) |
| 2b   | FILSYS inspects the Winchester (DISC-74MB-1, unit 0)     | NOT YET TRIED on Nexys   |
| 3    | `1560&` floppy boot -> TPE monitor                       | FAIL (silent; reproduced in sim) |
| 3a-c | TPE tests: INSTRUCTION, MEMORY, PAGING                   | blocked by 3             |
| 4    | SINTRAN boot: `201540&` (or bare `&` = autoboot WD)      | blocked by 3             |

## Phase 0 - post-reboot sanity (NOW, ~30 min, hands-free)

- [ ] Reprogram the board with the window-filter bitstream on disk
      (`fpga/nexys4ddr/nd120_nexys4ddr.bit`, 23-AUG 17:02) - program-only
      tcl, no rebuild. The FPGA lost its configuration in the reboot.
- [ ] OPCOM answers (`console.ps1 -Send` CR -> `#`).
- [ ] Fast unit gates for today's RTL: `ND-BUS-DEVICES/DMA/sim: make test`,
      `ND-BUS-DEVICES/FLOPPY-DMA/sim: make`, `CPU-BOARD-3202/circuit/sim:
      make test-blockram test-memchain`.
- [ ] `git status`; hash `CPU_15.v`, `CPU_MMU_24.v`, `CGA.v` before any A/B
      sim build (concurrent-session edits; see HANDOFF A/B WARNING).

## Phase 1 - land what is proven (HIGH, Ronny's decisions, ~1 h)

- [ ] Ronny reviews the diff: `MEM_RAM_49_BLOCKRAM.v`, `MEM_43.v`,
      `ND_DMA_MASTER.v`, `fpga/nexys4ddr/build.tcl`,
      `fpga/nexys4ddr/nd120_nexys4ddr_top.v`, `dmaSim/dma_p3_main.cpp`,
      new bench `ND-BUS-DEVICES/DMA/sim/ND_DMA_MASTER_STALE_CAPTURE_tb.v` +
      Makefile + `tests/run_all_tests.sh`, `tests/floppy-dma-test/`,
      `fpga/nexys4ddr/floppy-seam-test/`, `deposit_loader.ps1`,
      `ila_capture.tcl`.
- [ ] DECISION: keep the opt-in `ila` section in `build.tcl`?
- [ ] DECISION: keep or strip the 7-seg debug mux in the Nexys top?
- [ ] DECISION: make `nocache` (ND120_NO_CACHE, the Tang configuration) the
      Nexys DEFAULT. Measured 23-AUG: with the cache compiled out the CPU
      is noticeably FASTER (Ronny, at the console) - a correct cache can
      never be slower, so CPU_MMU_CACHE_25 costs cycles and was never
      validated. Cache validation becomes its own task, off the SINTRAN
      path. (Cache-off did NOT change the LIST-FILE-NAMES runaway.)
- [ ] Commit on Ronny's go (no AI mention). Update `Verilog/TODO.md`
      (MIN_GAP item measured: shipping config clean; the hazard was CPU
      contention).

## Phase 2 - tasks 1 and 2: FILSYS from tape, then floppy AND Winchester (HIGH)

Task 1 re-verify (5 min):
- [ ] `400&` -> "File System Investigator - Version: Q04" banner.

Task 2a - floppy (FLOPPY-DISC-1, unit 0):
- [ ] LIST-USERS -> `000 FLOPPY-USER` (known PASS, re-verify).
- [ ] LIST-FILE-NAMES user 0 -> 33 files (oracle list in HANDOFF). FAILS
      today: input-immune runaway printing FILSYS's own intro text. ALL
      pages it reads are byte-exact on the board, clean in sim ->
      CPU-side, silicon-only. Fix campaign:
  - [ ] Rebuild the ILA v2 bitstream (`build.tcl -tclargs ila -noburn`;
        probe set already = `CSA_12_0`, `s_xmic_dbg`, FDISK seam,
        `uart_rxd_out`). ~40 min; retry once on the Vivado out-of-memory /
        debug-hub crash.
  - [ ] `ila_capture.tcl program`; drive `400&` -> FILSYS -> FLOPPY-DISC-1
        -> LIST-FILE-NAMES -> `0` until the runaway prints.
  - [ ] `ila_capture.tcl capture` WHILE it loops (trigger = any
        `uart_rxd_out` edge); decode `ila_data.csv`: CSA histogram = the
        spinning microcode path; XMIC_DBG = sequencer health.
  - [ ] Map CSA -> microcode listing -> the FILSYS instruction; compare
        with the oracle (`~/repos/nd100x --disasm`, same BPUN + image).
  - [x] 23-AUG "wrong indirect jump" theory REFUTED 24-AUG by ILA v3
        measurement (probes s_cd_15_0 / s_ica_15_0 / s_la_23_10_out at the
        CGA_MAC; build.tcl `ila` flag now sets ND120_ILA_MARK_DEBUG so the
        nets survive synthesis): the JPL I to 0o060004 executes CORRECTLY
        on silicon (capjpl capture), the CPU never fetches at 0o016004
        (capbad trigger never fires), and the old 0o016xxx readings were
        CSA-bus transients of the form {3'b111, ICA[9:0]}.
  - [x] MEASURED 24-AUG - what the runaway actually is: after the correct
        end-of-list jump, FILSYS's generic DEVICE-RETRY loop at
        0o060033-37 (EXR of IOX 303 control write, then IOX 306 status
        read, BSKP tests bit 0o10) never sees the ready bit, calls the
        "DEVICE NEVER READY" error printer at 0o060224 every pass, and
        prints one help-text line (word 0o010446) per retry forever. The
        FDISK storage seam is IDLE during the runaway (v2 probes:
        REQ=DONE=ERR=0 all 4096 samples) - NOT a floppy hang. Oracle
        ground truth (nd100x DAP): same routine entered during healthy
        LFN, exits FIRST poll with IOX 306 = 0o000010.
        Captures: /mnt/f/tmp/verilog/nexys_lfn_ila_healthy_jpl.csv and
        nexys_lfn_ila_runaway_loop.csv.
  - [ ] CONSOLE-UART PASS (the actual fix campaign): why does IOX 306
        (console output status) bit 0o10 never read as 1 in this loop on
        silicon? Suspects, in order:
        (a) Shared/support/SC2661_UART.v line 221 forces TxRDY not-ready
            whenever cmd_txEnabled=0, and the loop WRITES the control reg
            (IOX 303) every pass - the known "command write with TxEN=0
            aborts the character" bug lives in the same area and also
            explains the garbled HELP text.
        (b) CPU-BOARD-3202/circuit/IO_UART_42.v: what IOX 303 writes
            actually touch, and which bits IOX 306 returns.
        Repro path: the dmaSim rig masks this via the fast-UART sim path -
        build the rig with real UART timing so the poll actually spins,
        reproduce the never-ready loop IN SIM, fix, verify, then silicon.
- [ ] DUMP-PAGE of a file page and LIST-PAGE-NUMBERS of one file -> match
      the image.

Task 2b - Winchester (DISC-74MB-1, unit 0) - never exercised on Nexys:
- [ ] FILSYS: EXIT -> device name `DISC-74MB-1` -> unit 0 -> LIST-USERS,
      LIST-FILE-NAMES for the system user -> compare with the oracle
      (`~/repos/nd100x --wd0=WD0.IMG`, FILSYS via bpun, same commands).
- [ ] If it fails: the WD path = nd_storage client 6 (CACHED on Nexys,
      `CACHE_MASK 8'b11000000`) + `ND_WINCHESTER` + its own
      `ND_DMA_MASTER` instance (already carries today's fix). First
      discriminator: the standalone-test pattern adapted to the
      Winchester CB/IOX sequence (IOX 1540 block, see `ND_WINCHESTER.v`)
      - same generator style as `tests/floppy-dma-test`.

## Phase 3 - task 3: `1560&` floppy boot -> TPE, then the TPE tests (HIGH once task 2 passes)

- [ ] `1560&` -> "TPE Monitor, ND-100 series - Version: B01" + `TPE>`.
      FAILS today: silent on silicon AND in the dmaSim rig (all 37
      command blocks load; TPE never transmits; CPU polls a flag at
      ~0o176755 forever; UART ready; not memory-model or aliasing). TPE
      enables PAGING (FILSYS does not) -> ties to the other session's open
      MMU bug (non-resident page reads as zeros instead of faulting).
  - [ ] When that MMU fix lands: re-run the rig (`dmaSim`,
        `ND120_OPCOM_SCRIPT=boot1560 ND120_FLOPPY_IMG=FLOPPY1.IMG`, ~3 min).
  - [ ] If still silent: in the rig, trace the flag cell 0o176755 and the
        page-table state; compare the poll site with the oracle's
        instruction trace at the same point.
  - [ ] Then `1560&` on silicon.
- [ ] TPE test programs from the floppy, each to its own END OF TEST
      with zero error lines, compared with the oracle's run of the same
      program (oracle harness: `tests/instruction-verify/run_area_test.sh`
      pattern):
  - [ ] INSTRUCTION (INSTRUCTION-C03:TEST on this diskette)
  - [ ] MEMORY
  - [ ] PAGING (this is the direct pre-check of the MMU before SINTRAN;
        the Tang campaign's `PAGING 11/11` memory is the reference bar)

## Phase 4 - task 4: SINTRAN from the Winchester (the goal)

- [ ] `201540&` (Winchester boot, device 1540) - or bare `&` if the
      autoboot selects the Winchester on this configuration (verify which
      the microcode does on the Nexys top: WCS preload + jumpers).
- [ ] Expected landmarks (from the oracle boot of the same WD0 image):
      banner at ~17-18M instructions; compare FAULTS and LANDMARKS only,
      not instruction streams (memory: stream comparison is impossible
      because the PIL-2 scheduler multiplexes level 1).
- [ ] Known hazards carried from the Tang campaign (check before blaming
      the Nexys): RTC_SIM_20MS/RTC rate, storage cache (exonerated on
      Tang), the level-10 IRQ wiring (fixed in the tree), the MMU
      non-resident-page bug (open).

## Phase 5 - consolidation (LOW)

- [ ] `dmaSim/README-rig.md`: OPCOM typist, BPUN poke, floppy server
      (FULL-clock cadence rule), `[flpchk]`/`[ramhist]`/`[edge]` probes,
      `DMASIM_RAM_MASK`.
- [ ] Register `test-dma-reset-pend` in `tests/run_all_tests.sh`
      (pre-existing gap).
- [ ] Drop the `-Wno-IMPLICIT` workaround once `DBG_PTW` in `ND3202D.v`
      is finished by the other session.
- [ ] Board README: Nexys status per task.
