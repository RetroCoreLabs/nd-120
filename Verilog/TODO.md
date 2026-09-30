# ND-120 Verilog TODO

> Last updated: 28-SEP-2026. Open work only - finished items are deleted
> (the record is in git history and `HISTORY.md`). Newest sections are near
> the top.
>
> Standing context: **SINTRAN III boots on the Tang Nano 20K** (24-AUG-2026),
> the Nexys 4 DDR (25-AUG-2026) and the MiSTer (02-SEP-2026).
> The ERRFATAL / page-fault campaign is CLOSED (`ND3202D.v:533` bank decode).
> The SD FAT-chain walk was fixed 24-AUG (boot 168 s -> 29.4 s, S3 cold
> 235.8 s -> 13.2 s).

---

## Diagnostics that do not pass

- [ ] OPEN - DISC-TEMA J02 on the Winchester (IOX 500): `DU-DI-C` reports
  `***ERROR*** DISC-74MB-1 Unit 0 / Hardware Status: 060010b / Controller
  finished / Additional Status: 002000b / Memory address Register not as
  expected`. The one known open diagnostic.
  Known facts:
  - Reproduces on the Tang AND in Verilator (same verdict on both).
  - Verilator run: `cd Verilog/sim; make probe-wd USE_LATCHES=0
    EXTRA_WD_DEFINES=-DND120_DEV_DELAY_TICKS=216000`, then
    `ND-BUS-DEVICES/WINCHESTER/sim/wd_disctema.py` (about 50 minutes; recipe
    in `Verilog/ND-BUS-DEVICES/README.md`). `ND120_DEV_DELAY_TICKS=216000` is
    needed or DISC-TEMA dies with `Software Timeout` first (the 8 ms disc
    delay is 800,000 cycles at the 100 MHz sim fallback vs 216,000 on the
    27 MHz Tang).
  - The transfer matches silicon operation-for-operation (silicon ops 22-35),
    incl. the two-part memory-address readback `R+0 001000`, `R+0 000001`
    (= 0o200000 + 512 words), which reads back correctly.
  - Every register the card exposes matches the nd100x C model
    access-for-access.
  - NOT the IOX-write-zeroes-A bug (`BIF_DPATH_9.v:198-206`, fixed 06-AUG) -
    that is a different defect.
  - Not yet done: watch the card's internal memory-address register and the
    DMA address in a waveform across the transfer (the probe build has
    `--public-flat-rw` / `--vpi`). Use the same disc image on both sides
    (the 06-AUG sim used WD0-M, the silicon capture WD0-L).
  Record (deleted from the tree 28-SEP, kept in git at commit 202c606):
  `Verilog/docs/HANDOFF-winchester-disc-tema-05-AUG.md` (sec 4: eleven
  hypotheses eliminated on silicon - do not re-test them; sec 5: the silicon
  trace) and `Verilog/docs/HANDOFF-winchester-verilator-06-AUG.md` (sec 4-7:
  the Verilator run and its trace). Read with
  `git show 202c606:Verilog/docs/<file>`.

- [ ] OPEN, status unknown: paged store to logical 177777 reads back 0 (TPE
  INSTCTION). 22-JUL-2026: under the ND-120/CX TPE-MON `INSTRUCTION`
  diagnostic (INSTCTION C03), every memory WRITE to logical 177777 (the top
  page, VPN 63) with PAGING on read back 0 (STA/STT/STX/MIN/STF/SBYT); the
  same store with paging off worked. INSTRUCTION-B's MEMORY-REFERENCE area
  passes 400/400, so the store data path is not the cause.
  `CPU_MMU_PT_29_replay_tb.v` proves the page-table RAM stores and returns
  VPN63 -> PPN o77 correctly. Not re-checked since: PAGING passes 11/11 on
  Tang silicon after the PAL 44306A fix (30-JUL) and INSTRUCTION levels 1-9
  pass on the Tang (31-JUL), but nothing records a clean TPE INSTCTION
  memory-reference run, so whether this is fixed is UNKNOWN. To close: run TPE
  INSTCTION to the memory-reference sub-test on a board or with
  `sim/examples/tpe_instction_store_capture.py`.

- [ ] OPEN - TPE "version too old". CONF and LOAD INSTR under TPE abort
  "*** TPE version too old ***" though the required versions (B00/A02) are
  older than the monitor's B01; `fpga/nexys4ddr/boardtests/tpe_boot.bt:3`
  still says KNOWN OPEN BUG. Not re-checked since the panel clock became
  default (29-AUG).

- [ ] RUN (INSTRUCTION-B) is not proven: after the 14-JUL interrupt fixes it
  reached LEVEL 13 / ARGUMENT `== END OF TEST ==` once in Verilator - one
  area's end inside RUN's level loop, not the end of RUN. No error count was
  recorded, no log committed, and RUN is in no gate.

- [ ] OPEN - the `test-full` runSim golden console gate (Verilog/Makefile,
  "runSim FF console vs golden") does not pass. Until commit c8cf73a it did
  not even compile (`PINMISSING BAUD_9600` at ND120_TOP.v - the input was
  never tied in the sim top). With that fixed, a run in a clean clone
  (28-SEP-2026) prints the load lines and `#124002 0!`, then nothing: the
  INSTRUCTION-B banner never comes and the `[instrumented] cycle budget
  reached` stop never fires (ran 37 h at 100% CPU before it was stopped).
  Not explained. Known differences from the golden recording: the clone has
  no `FLOPPY.IMG` ("Unable to open file FLOPPY.IMG"; untracked test image),
  and the log now also shows the `BPUN pre-deposit into RAM: DEBUG.BPUN`
  line the golden predates. Next step: run the gate from a checkout that
  has the untracked test images, and compare against the golden again.

---

## Hidden bugs found by reading the code (not yet shown to bite)

- [ ] **IO_37 IDB mux default ORs all sources.**
  `CPU-BOARD-3202/circuit/IO_37.v:308`: `default: s_idb_mux =
  s_idb_15_0_uart_out | s_idb_15_0_pancal_out | s_idb_15_0_reg_out |
  {8'b0, s_idb_7_0_dcd_out};` - ORs all four IO_37 sources for every CSIDBS
  code not listed, incl. `IDBS,ALU`; the mux's own comment says the OR-bus
  "caused contamination". Candidate fix `default: s_idb_mux = 16'b0;` (the
  explicit cases 16/37/20/21/26/35/27 cover all four sources; ECSR 24,
  EPEA 12, EPES 13 come from MEM and BIF). Verified still present 28-SEP.
- [ ] **TTL_74273 async clear commented out.** `Shared/support/TTL_74273.v:43`:
  `always @(posedge CLK ) //or negedge CLR_n)` - the IOC register can only be
  cleared by a CLEAR_n that coincides with a SIOC strobe; on a real 74273 the
  pin is asynchronous. Untested. Verified still present 28-SEP.
- [ ] **Unexplained: BINT10..13 -> IREQ[0..3].** `CGA_INTR_IRSRC.v` puts
  BINT10..13 on IREQ[0..3], BINT15N on IREQ[15], IOXERR/PARERR/MOR/POWFAIL on
  10..13; the tb header (`CGA_INTR_IRSRC_tb.v:34`) says "CHARACTERISED, not
  judged". A 23-AUG PIL histogram refutes that BINT10..13 produce PIL 0..3, so
  a remap exists that nobody has located. Read the drawing before touching it.
- [ ] **ND_WINCHESTER irq outside the idle guard (question).**
  `ND-BUS-DEVICES/WINCHESTER/circuit/ND_WINCHESTER.v:935` `s_irq <=
  iox_wdata[0];` sits outside the `if (!s_active)` guard that line 934 applies
  to `s_rft`, against the module's own section-4.1 comment. Not proven a bug.
- [ ] **Verify on silicon: no phantom IOX devices / TOUT on unmapped IOX**
  (old Issue B, 27-JUL): CONFIGURATION `run` saw every unmapped IOX device
  answer 000000B; suspect drive-0-when-disabled keeps BDRY_n/IBDRY_n asserted
  so TOUT/IOXERR never fire (`BIF_BCTL_BDRV_7.v:250-252`, `DECODE_DGA_POW.v`).
  No fix commit found; indirect evidence it may be gone (INSTRUCTION
  multi-level and PAGING 11 pass on silicon).

---

## MiSTer port

SINTRAN III boots on the DE10-Nano (02-SEP-2026, `fpga/mister/README.md`).
The microcode loop was the WCS read taking two clocks
(`docs/mister-microcode-loop.md`). Open:

1. **Strip the debug scaffolding.** Debug ports `XWRFB_DBG_19_0` and
   `XCYC_DBG_7_0` threaded through `CGA.v`, `CYC_36.v`, `CPU_PROC_CGA_33.v`,
   `CPU_PROC_32.v`, `CPU_15.v`, `ND3202D.v`, `ND120_CORE.v`, `ND120_TOP.v`;
   probe modules `fpga/mister/rtl/nd120_diag_print.v`, `nd120_csa_trace.v`,
   `nd120_sterr_catch.v` (KEEP `pll_cpu.v`); their testbenches and Makefile
   targets (`fpga/mister/sim/Makefile`); and the probes in
   `runSim/Run120.cpp`. After it: one Quartus build and a board check that
   it still reaches `#`.
2. **Four inferred latches** reported by Quartus (01-SEP-2026):
   `ND_DMA_MASTER.v` (`s_pend_addr`, `s_pend_wdata`, `s_pend_wr`) and
   `ND_WINCHESTER.v` (`s_rw_gate`). Not re-checked since.
3. Storage board checks: `docs/PLAN-mister-storage.md`.

---

## Panel clock (MC68705 + MM58274) - open items

The panel clock is emulated by `CPU-BOARD-3202/circuit/PANCAL_68705_CLOCK.v`
(doc: `docs/panel-clock-68705.md`). Open:
- Nexys: the SINTRAN `@UPDAT` / `@CLOCK` / `@DATCL` round trip on silicon
  (done on the Tang, fast20, 29-AUG).
- Host preset of the time at power-up (TIME_HALFDAYS/TIME_SECONDS are brought
  out of the module for it) - today the clock starts at 1979-01-01 00:00.
- STAT3 idle pulse: the ROM pulses PB4 every ~3 ms while idle (0x0153); the
  Tang analysis 3f says it does not. Decide whether to model it (it is the
  same edge the old "conkick" manufactured, and that tripped the INTRQN lag).

---

## Owned elsewhere (from the 02-AUG-2026 plan)

**SMD disc controller (1540).** A separate session has taken over the SMD work
from the old SMD handoff (now the `ND_SMD.v` header), together with the Pi Pico C-code
side that is running ground-truth tests to confirm the nd100x oracle is 100%
correct. Off our plate:

- `ND-BUS-DEVICES/SMD/circuit/ND_SMD.v` - register semantics, the
  controller-type / word-count flip-flop question, `21540&` mass-storage load.
- `SD-FAT/circuit/nd_storage_disc_adapter.v` position mapping (still
  `blkaddr2*2048 + blkaddr1*64`, not the oracle's cylinder/head/sector -> LBA;
  changing it means changing the adapter, `ND-BUS-DEVICES/SMD/sim/nd_smd_tb.v`
  and `process_verilog_smd()` in `simDevices/NDBus.cpp` together).

Captured ground truth for the oracle side lives in
`ND-BUS-DEVICES/SMD/sim/traces/`.

**Ronny's, not ours to start:** the combined floppy+SCSI PCB question (onboard
Z80, decodes both the 1560 floppy/streamer window and SCSI at 144300).

**Testbench campaign (paused 02-AUG):** `BIF_BCTL_6` has no testbench yet.
`DECODE_DGA_COMM_tb` sits in `tests/tb_catalog.py` ORPHAN_BASELINE with its
reason. Every new tb must print `TB_RESULT: PASS` and be registered in
`tests/run_all_tests.sh`.

---

## LOW PRIO: disc image >= 128 MiB is silently mis-sized at mount

Found while documenting the Winchester/SMD geometry, 09-AUG-2026. Nothing is
broken today - it is recorded so it is not rediscovered as a mystery.

**What is fine.** A disc image LARGER than its drive geometry is harmless by
design. `ND_WINCHESTER.v` (and `ND_SMD.v`) refuse any CHS beyond their own
GEO_* bounds before the storage stack is asked for anything, so sectors past
the end of the drive are unreachable whatever the file size, and SINTRAN
never asks for them. `WD0.IMG` does not have to be exactly 75,497,472 bytes.

**What is not fine.** `nd_storage_mount.v` M_OK stores the block count as

    r_nblk[cur_client] <= s_size[26:11] + {15'd0, |s_size[10:0]};

`s_size[26:11]` is a 16-bit slice, so a file at or above 2^27 bytes
(134,217,728 = 128 MiB) loses its high size bits and the client is told the
image is a different, smaller size than it is:

| image | true blocks | stored | result |
|-------|-------------|--------|--------|
| 72 MiB (exact geometry) | 36,864 | 36,864 | fine |
| 75 MiB (oversized) | 38,400 | 38,400 | fine |
| 128 MiB | 65,536 | 0 | every read refused |
| 150 MiB | 76,800 | 11,264 | most reads refused |

The failure is a SILENT wrong answer, which is precisely what
`SD-FAT/circuit/nd_storage_status.vh` exists to eliminate.

**Fix when it matters:** refuse the mount with `NDS_ERR_RANGE` for an image
>= 128 MiB. Widening the slice alone is NOT sufficient - `n_blocks` is a
16-bit output port and the engine's range check compares against it, so the
port width has to grow too.

**Why it is low priority:** the largest drive modelled is 75.5 MB and no ND
unit image in this project approaches 128 MiB. The mount-time guard is cheap
insurance, not a live bug.

Documented at: `nd_storage_mount.v` (header + the r_nblk assignment),
`ND-BUS-DEVICES/README.md` ("The image file may be LARGER than the
geometry"), `SD-FAT/CARD-LAYOUT.md`.

## LOW PRIO: confirm-or-refute that the DMA master's MIN_GAP_TICKS gap is load-bearing

Added 31-JUL-2026. The committed conclusion (commit 332ff8e,
`Verilog/floppyTester/PLAN-P3-dma-master-validation.md` section "0. RESULTS",
plus the DMA slide deck) says the MIN_GAP_TICKS recovery gap prevents the
"every second read lost" DMA hazard. A 26-JUL isolation sweep (dmaSim hammer,
FIXED read address 010000 octal, 2x2 over MIN_GAP {0,32} x EARLY_REREQ {0,1})
contradicts it: stale reads track EARLY_REREQ only (7/64 stale whenever
EARLY_REREQ=1, 0/512 when 0, at BOTH gap values), suggesting MIN_GAP is
vestigial. NOT conclusive: a fixed-address hammer is blind to the
stale-ADDRESS-latch variant (a stale latch still holds the right address);
the original evidence (`Verilog/docs/nd100-bus-dma.md` section 10.8) used a
CHANGING-address burst.

Step 1 is done: the hammer in `Verilog/dmaSim/dma_p3_main.cpp` has the
INCREMENTING-address mode (`ND120_DMA_HAMMER_INCR=1`). With it, the deleted
floppy handoff measured the shipping config CLEAN for changing-address bursts
(512/512): "the missing ingredient was CPU contention, not the gap". The full
2x2 and the MIN_GAP sweep below were not recorded.

Still to do: re-run the 2x2 at N>=512 per cell, strictly serial with `make clean`
between builds (MIN_GAP/EARLY_REREQ are compile-time via EXTRA_VDEFINES; no
build-flags stamp in `Verilog/dmaSim/Makefile`). Also sweep MIN_GAP
{0,1,2,4,8,16,32} at EARLY_REREQ=0. Then either correct the "load-bearing"
wording in the PLAN doc (note the 332ff8e correction, don't rewrite history;
flag the pptx deck for its owner) or document the true minimum gap. Full
task spec with guardrails: session memory `dma-min-gap-verify-task`.

## LOW PRIO: keep the wall-clock time across power-off (ESP32 NTP time source)

Added 31-JUL-2026 (Ronny). The panel clock is emulated now (see "Panel clock"
above), but nothing keeps the time while the power is off.

- The Tang Nano 20K has no RTC and no battery backup, so the FPGA alone
  cannot keep time across power-off. Align this task with the planned ESP32
  integration: the ESP32 tracks real time via network NTP and provides it to
  the emulated panel clock on boot.
- SINTRAN III is NOT year-2000 safe (y2k). The ESP32 must therefore store a
  year OFFSET and always present SINTRAN a pre-2000 date - e.g. real year
  minus a fixed number of years (exact scheme to be decided; leap-year
  alignment matters when picking the offset) - so the OS never sees a year
  that crashes it. The true date lives only on the ESP32 side.

## Logisim drawing fix needed: CGA_INTR status fence (regeneration hazard)

The Am2914 status-fence fixes of 14-JUL-2026 (`CGA_INTR_CNTLR_VECGEN_STAT{,_SBIT}.v`:
the vector-load NAND took GPE instead of DCDF, and four SBIT pins were rotated;
plus the FIDBO bit 1/2 swap in `CGA_INTR_CNTLR.v`, commit `3acef36`) are in the
Verilog only. The Logisim CGA_INTR sheet needs the same corrections, since the
schematic and the Verilog are maintained by hand and must agree. Analysis:
`docs/RUN-level14-livelock-analysis.md`.

---

## Logisim drawing fix needed: CGA_ALU CONTR MEMORY_46/47 (regeneration hazard)

`CGA_CPU_ALU_CONTR.v` captured the instruction's shift-type bits (CD 10:9 -
ROT/ZIN/LIN select) in two rising-edge D flip-flops (MEMORY_46/47) clocked by
the LDIRV strobe. The CD bus holds the instruction only late in the
LDIRV-high window (measured: CD=0 at every rise, instruction present at every
fall), so the flops captured 0 forever, SSEL stayed 00 and every
SHA/SHD/SHT/SAD ROT / ZIN-right / LIN shift ran as a PLAIN arithmetic shift
(INSTRUCTION-B SHIFT sub-tests 5OP-8OP, 256 failures each; both latch and FF
builds). FIXED (13-JUL): replaced with the `SSEL_LATCH` L8 transparent latch,
wired like the proven CGA_MIC IRLATCH. **Until the Logisim CGA_ALU_ sheet
(page 42) gets the same latch, regenerating CGA_CPU_ALU_CONTR.v reintroduces
the bug.** Ronny: please also check what the original PDF draws for the SSEL
capture (the MIC IR capture is a latch on its sheet). Full analysis:
`docs/SHIFT-serial-input-rootcause.md`.

---

## Logisim drawing fix needed: CGA_ALU QREG MUXQ15 D3 (regeneration hazard)

`CGA_ALU_QREG.v` had MUXQ15 input D3 wired to Q0 (a Q rotate) instead of F0
(the shift-right-double link that streams the multiply product from R5 into
Q). Result: EVERY MPY/RMPY product low word read 0 and +/-32768-boundary
overflows never set the O/Q status bits (INSTRUCTION-B "DYNAMIC OVERFLOW BIT
NOT SET"). The Verilog is FIXED (13-JUL, verified vs nd100x on a 10-pair
sweep, latch+FF, golden areas re-pass), and Ronny confirmed the original
schematic (CGA p.43) reads D3=F0 - the error is in the LOGISIM DRAWING
(original PDF scan very unclear at this point). **Until the Logisim sheet is
corrected, regenerating CGA_ALU_QREG.v reintroduces the bug.** Full analysis:
`docs/MPY-dynamic-overflow-rootcause.md`.

---

## OPEN: parity is never CHECKED

Found 3-AUG-2026. Every read carries correct parity (computed, never stored -
`docs/nd120-parity-analysis.md` section 6b), and `MEM_43.v:270` now passes the
local parity error through (`assign LPERR_n = s_lperr_n;`). What is left:

- **`AM29833A.v:126`**: the error register is loaded only `else if
  (!ReceiveMode)`. But `MEM_DATA_46.v:230-255` wires **T to the memory bus and
  R to LBD**, so a memory READ is receive mode - the direction we care about
  is exactly the one the model does not evaluate. The datasheet text quoted at
  the top of `AM29833A.v` says the opposite: "In the receive mode, data and
  parity are read at the T port, and the data is output at the R port along
  with an /ERR flag showing the result of the parity test."

This looks like a transcription error in the chip model, but changing a
checker's semantics needs Ronny's call, together with a decision about what
the CPU should DO with a real parity error (level 14 + IIC, PES/PEA - see
`docs/nd120-parity-analysis.md` section 5). Until then FPGA memory is
unprotected: correct parity in, no checking.

- [ ] Parity probe path: five items not done - see
  `docs/nd120-parity-analysis.md` 6c.

---

## Storage and devices - open items

- [ ] nd_storage clean-up: remove the dead M_LOAD path and s_slot_bytes from
  SD-FAT/circuit/nd_storage_mount.v (frees an 8x32 FIFO, the byte packer and
  counters), and the vestigial SLOTn_* parameters from nd_storage.v. See
  docs/nd-storage-design.md 2.7.
- [ ] nd_storage cache geometry (owner's call): the pool uses 1024 of 2048
  region blocks (~2 MB unused). Options: accept, or CACHE_WAYS=3 /
  CACHE_SETS=512 (1536 lines). See docs/nd-storage-design.md 2.7.
- [ ] Silicon check left from the FAT-walk work (07-AUG): 400$ (BOOT.TAP on
  the card) and 1560& DISC-TEMA on the SAME Tang bitstream after a power
  cycle. (SINTRAN boots from the Winchester through the walker, but this pair
  was never recorded.)
- [ ] Decide: fold test-dma-rtl + test-dma-xcheck into make test-full
  (+~24 min) or keep them on-demand like the floppy/SMD boot gates. Today: on
  demand (Verilog/Makefile test-full has no DMA gate).
- [ ] CONFIG-tool gate: make run-config exists (runSim/Makefile) but there is
  no automated test-config-* gate asserting that CONFIGURATIO-C08 detects the
  tape/floppy/SMD controllers.
- [ ] Before driving real external ND-bus cards: prove in sim that the CPU
  releases BD (all ones) whenever a DMA master owns the bus (assert
  BD_23_0_n_OUT == all ones while OUTGRANT_n is given to a device), and re-run
  the test-tristate netlist gate for any real pad work.
- [ ] Disc delay model (owner's call): ND120_CORE.v models an 8 ms wall-clock
  delay, so every clock variant and the 100 MHz sim fallback get different
  cycle counts (see ND-BUS-DEVICES/README.md, Winchester in Verilator).
- [ ] Filename selection UI (console command?) for multiple disc images.
- [ ] Floppy DMA: absent-drive hang (review C2) - DISK_TIMEOUT watchdog exists
  but defaults to 0 = off; M4 test mode latched and unused; M5 one
  media-format input for all drives. See docs/floppy-review-findings.md.
- [ ] `ND_FLOPPY_PIO.v:94` buffer still async-read (lines 171, 182) - needs
  the sync-read treatment before any board build.
- [ ] dmaSim rig: TPE prompt deaf in the rig only (LOW). Typed characters pile
  up to an SC2661 overrun; silicon TPE input works. Probe left at
  `IO_REG_41.v:277`.
- [ ] Remove the Issue-F probe `ifdef PESDBG` block,
  `CPU-BOARD-3202/circuit/BIF_BCTL_6.v:349` (inert unless -DPESDBG).

---

## The CGA IDB combinational ring - analysed, NOT blocking the target (04-SEP-2026)

**Full analysis: `docs/HANDOFF-cga-idb-ring-cut.md`.** Four things in it change
what anyone should do next, and two of them contradict comments in the tree:

1. **The ring is NOT where `CGA.v:707-745` says it is.** That comment describes
   the design before the 21/22-AUG cuts. The internal ring it names is DEAD -
   every SEL6 source (PCR, PGS, PICMASK, PICS, PICV) is behind a register now.
   The live ring **leaves the chip**: FIDBI -> OUTMUX pass-through -> FIDBO ->
   `BusDriver16` -> `TTL_74245` -> board IDB -> back -> `XFIDBI` -> SEL6 ->
   FIDBI. `BusDriver16.v:49` reads the pad back **unconditionally, with no
   enable**. A second live arc runs FIDBO -> MAC's transparent PCR/SEG/XPT
   latches -> `MAC_LASEL`/`MAC_LA1025`, which is why every Cmod worst path
   ended at `MAC_LA1025/R_LA_L`.
2. **The one-hot exclusivity is REAL and structural**, not a microcode
   accident: `CSIDBS_4_0` is `CSBITS[41:37]`, a binary field, decoded as full
   minterms and by two complementary 3-to-8 decoders. The tool cannot see it
   only because the decoded enables are registered and then cross two module
   boundaries. `CGA_IDBCTL.v:115` is the shape that already convinces Vivado.
3. **Nothing in simulation covers the PGS readback leg.** All four `IDBS,PGS`
   microwords are SINTRAN paging traps, and no target boots SINTRAN in
   Verilator. Verified against the golden trace: those control-store addresses
   show only the loader's single pass. A broken PGS leg passes every
   simulation gate in this repo and shows up as a board dying on a page fault.
   **Only a hardware SINTRAN boot covers it.**
4. **THE RING DOES NOT BLOCK THE SINTRAN TARGET.** Measured on the QMTECH's
   first build, with the ring present (16 `LUTLP-1`, 10 auto-cuts): CPU domain
   **+5.255 ns, 0 of 27,698 endpoints failing** at 20 MHz. Cutting it is
   quality work now, not a blocker, and should be done to the full
   verification bar rather than in a hurry.

One gate-integrity defect found on the way and still open: `make -C sim
compare` cannot fail because its diff sits in a `|| (echo ...)`. (The other one,
`run_area_test.sh` printing PASS on a missing golden, was fixed 28-SEP-2026: it
now FAILs.)

---

## The ring as a board blocker (Cmod A7 only)

The ring documented at `DELILAH-CPU/CGA/circuit/CGA.v:700-745` stopped being a
warning-count nuisance and became the thing that fails a build.

**Measured on the Cmod A7 (`xc7a35t`), first build of those files:** fits the
part easily at 5,285 of 20,800 LUTs (its own util.rpt; an "11,493" figure
stood here and was wrong), then **WNS -89.814 ns at 27 MHz**, 5133
of 18465 endpoints failing. From the routed checkpoint, **all 200 worst paths
share one start and one end** - `CPU/CS/WCS/CHIP_21C` to
`CPU/PROC/CGA/DELILAH/MAC/MAC_LA1025/R_LA_L`, 234 logic levels, 126.5 ns,
through the ALU, never touching main memory. The build reports **16
`[DRC LUTLP-1]` critical warnings and 23 auto-inserted `Synth 8-326`
loop-breaking false paths**, naming the ring exactly:
`ALU_OUTMUX/OUTMUX_IDBS/IDBS_R1/D_15_0[n]` -> `G_15_0[n]` -> FIDBO ->
MAC/INTR -> back.

**The number is a property of the netlist, not the machine.** The same RTL
gives that path **31** logic levels on the Nexys at 45.45 MHz (MEASURED:
fpga/nexys4ddr/timing-analysis/run_clk45/setup_paths_post_route.rpt:24) and
234 here (MEASURED: fpga/cmod-a7-35t/top5_paths.rpt). The MEGA65 58/93
figures are UNVERIFIED - no report in the tree backs them. A "7 on the
Nexys" figure was written here on 04-SEP-2026 and was WRONG.
The design also boots SINTRAN on the Tang, whose toolchain has no loop DRC
at all. Two things follow:

- **Lowering a clock does not fix it.** 126.5 ns would need the CPU under
  7.9 MHz. That fits the clock to a tool artifact.
- **Every Artix board's WNS is a floor while the ring exists**, which the
  Nexys README already says of its own 45 MHz sign-off. The QMTECH build may
  land anywhere on this spectrum; its README says what to read first.

Ruled out on the way, so nobody repeats it: the runtime PROM-to-WCS load was
the first suspect (the very first worst path ended at the PROM's data
register). `SKIP_WCS_LOAD` bought **5.7 ns of 95** and is kept only on its own
merits.

What CGA.v:734-737 says would actually work: stop FIDBO feeding MAC/INTR
combinationally - either register it, or qualify the PCR/PGS readback with the
one-hot `CSIDBS_4_0` select at the SEL6 inputs so the tool can prove
exclusivity inside one module. Three other attempts are recorded there and all
measured WORSE; read them before trying a fourth.

---

## QMTECH XC7A35T board - FIRST BUILT 04-SEP-2026, fits and closes

The whole machine now has a top level, a pin map and a Vivado script under
`fpga/qmtech-a35t/`: CPU at 20 MHz, **4 MB of SDRAM main memory** through the
sheet-49 bridge in its 16-bit module mode, SD-card storage on header JP3, and
a serial console on two more header pins.

This board matters because it is the one Artix-7 target that can run SINTRAN:
same die as the Basys3, whose 24 KB of block RAM is a capacity limit no clock
speed fixes.

**Measured on the first build:** 13,170 of 20,800 LUTs, 22 of 50 block RAM
tiles, and the **CPU domain closes at +5.255 ns with 0 of 27,698 endpoints
failing** at 20 MHz. Storage +11.475, SDRAM bridge +10.949, the related
CPU/bridge pair +4.105. It fits with room, so the panel clock and the CPU
cache both stay in.

The build still reported WNS -2.137 ns from **two** paths, both storage clock
crossings with a **1.000 ns required time** - two unrelated clocks timed as
synchronous. **A constraint bug, not the design:** generated clocks do not
exist when an XDC is read before `synth_design`, so the `get_clocks` guard in
`nd120_timing.xdc` found nothing and the constraint silently did nothing. The
relationships moved into `build.tcl` after synthesis, as
`set_max_delay -datapath_only` bounds rather than asynchronous groups - the
Nexys proved on 22-AUG-2026 that groups leave the `nds_sync` handshake
payloads untimed and corrupt floppy reads. **This trap has now cost three
boards; it is written up in `docs/HANDOFF-cga-idb-ring-cut.md` section 9.**

**Next: wire JP3 and boot.** Confirm a ground pin on JP3 against
the board before wiring - the schematic extraction could not settle it, and a
card with no shared ground fails exactly like a bad card.

Two things a reader should know before interpreting any result there:

- **The 16-bit bridge mode and the disc cache are mutually exclusive** as the
  code stands: `ND_SDRAM_DQ16` drops the 32-bit full-location access that
  nd_storage's region port raises on every operation (`sdram18.v` header, and
  its DQ16 write branch). The build runs every client DIRECT instead, with the
  staging line in block RAM (`rtl/nd_storage_bram.v`). That costs disc speed,
  not function - the Tang ran that way for weeks. Restoring the cache means a
  two-beat 32-bit access in the DQ16 mode plus a wider location space; the
  chip has 8192 rows against the 2048 the mode maps today.
- **The LED and mem-test smoke tests are no longer the critical path.** They
  were the only way to prove the clock and programming chain before a full
  build existed. Keep them for when the board itself is the suspect.

Detail: `fpga/qmtech-a35t/README.md`; hardware facts in `fpga/qmtech-a35t/docs/board-notes.md`.

---

## Nexys 4 DDR - open items

- **Full validation suite not run on the 01-SEP RTL** (13 instruction-verify
  areas + unit suite + latch-vs-FF compare) - started twice on 01-SEP and
  stopped for board work. UNVERIFIED whether it has run since.
- **Nexys keyboard TX framing vs UART framing:** the PS/2 keyboard path sends
  7 data bits + EVEN parity while the SC2661 runs 8N1, so the serial mirror
  shows typed characters with bit 7 set (`d` -> 0o344). Cosmetic on the PC
  side; look at it when `key_tdv2200.v`'s transmitter is next touched.
- **ASYNC_REG hygiene** on the CDC-5/CDC-8 synchronizers incl. debug-panel
  `sync_hold`/`sync_grb` (TIMING_CLOSURE_REPORT section 7 item 2) - not done.
- **Re-read the synthesis log** for `ND_FLOPPY_DMA` 8-7137 set/reset priority
  and the 22 deleted registers + `sd_writer` connections
  (BUILD-WARNINGS-ANALYSIS sections 3-4); not re-checked since the floppy
  rework.
- **SD-config boot at 16.667 MHz** after the SD power-cycle fix - verified at
  45 MHz only (old soak plan 1.5); SD-card WRITE at speed still unproven (1.6).

---

## Tang Nano 20K bring-up

### OPEN: the OSS flow (yosys/nextpnr) does not fit the full CPU on the Tang

The open-source flow (yosys) maps the full CPU to 22,254-22,626 LUT4 against
the 20,736 LUT4 on the GW2AR-18, so no legal placement exists: CI run
33664876050 sat in the placer for 2 h, and local runs do the same (measured
28-SEP-2026). The Gowin flow fits the same design. The full CPU did build
with the OSS flow on 12-JUL-2026; what has grown since is not known.

Bitstreams come from Gowin EDA; no bitstream is built in CI (the CI job
`tang-oss` that tried was removed 30-SEP-2026). The work, if the OSS flow is
wanted for the full CPU: find where the open-source synthesis spends the
extra LUTs and fix that at the root, WITHOUT shrinking the design.

Done so far (28-SEP-2026, branch `worktree-agent-a09183b55a25ca921`, commit
263aad7 - NOT on main, needs the owner's decision): synthesis settings only,
no RTL change - LUT4-only mapping with a size-first ABC script (-1580),
`cmp2softlogic` (-393), `share -aggressive` (-126), `simplemap t:$buf` (the
`$buf` cells yosys 0.69 leaves behind), family gw2a. LUT4 22254 -> 19790
(95%), ALU 3880 -> 3114. It STILL does not place ("Unable to find legal
placement"): nextpnr's GW2A model lets a flip-flop share a slot only with the
LUT that drives it (about 2690 flip-flops fed from another flip-flop take a
slot each) and each of the 278 LUT RAMs blocks a whole 8-LUT group - about
22170 of 20736 slots. No equivalence check of the new netlist was run.
Also: `gowin_build.ps1` turns `ND120_PANEL_CLOCK` on by default, the OSS
Makefile never does (about 600 more slots if it did). Where the extra cost
sat, OSS vs Gowin: the SD stack `u_engine` (+1606 LUT+ALU), the CPU gate
array (+1343), the floppy (+481).

### Get a timing-clean Tang build above 20.25 MHz

`fast20` (20.25 MHz) is the fastest timing-clean build (TNS 0, Fmax
22.932 MHz, 31-AUG-2026). `full` (27 MHz) boots SINTRAN but Gowin reports 1667
setup violations, so it is not a configuration to trust unattended. Keep
`BOARD_CLK_FREQ` and all UART/RTC counts derived from the clock, per the OPCOM
speed fix. Details: `fpga/tang-nano-20k/README.md`.

---

## Future boards / peripherals (captured 8-JUL-2026)

### CMOD A7-35T target (Digilent)

The owner has the board; build files are in `fpga/cmod-a7-35t/`. The first
build misses timing on the CGA IDB ring (see "The ring as a board blocker"
above) and the block-RAM memory ceiling is 24K words
(`fpga/cmod-a7-35t/README.md`). Open:

- **The pack16 SRAM bridge** - 512 KB / 256K-word main memory, full plan in
  `fpga/cmod-a7-35t/SRAM-BRIDGE-PLAN.md` (the old 4-byte-access idea is
  INVALID per `docs/basys3-memory-speed-validation.md`; pack16 is mandatory,
  <= 33 MHz validated, est. 2-4 days).

### SD-card storage on the Basys3 and Cmod A7

Floppy/HDD images from an SD-card Pmod on the Pmod connector (same module,
same SPI-mode controller on both). Basys3 Pmod pins: `docs/sd-bpun-device-plan.md`
6.2 (unverified). Note the 24K-word memory ceiling on both boards.

---

## High Priority

### CPU_15: MMU/LAPA/STOC validation

Previously marked as fixed but needs double-checking. IN/OUT signal assignments must be validated.

**File**: `CPU-BOARD-3202/circuit/CPU_15.v`

---

## Medium Priority

### CPU_MMU_WCA_31: WCA_n polarity check

Should `WCA_n` be switched in this assignment?

```verilog
assign PPN_23_10 = WCA_n ? 14'b0 : CPN_23_10;
```

**File**: `CPU-BOARD-3202/circuit/CPU_MMU_WCA_31.v`

### Search for `TODO:` in code

Periodic cleanup -- grep for `TODO:` comments and address remaining items.

---

## Low Priority

### CGA/MAC and CGA_MAC_FASTADD: Unit tests

No dedicated unit tests. CPU self-test exercises these through the ALU path. Lower priority unless specific MAC bugs found.

### MEM_ADDR_44: Add test code

No dedicated test. Works in full sim.

**File**: `CPU-BOARD-3202/circuit/MEM_ADDR_44.v`

### MEM_RAM_49: Refactor DD_17_0 signals for hardware

RAM works in simulation. For real FPGA hardware, the `DD_17_0` IN/OUT signals may need refactoring depending on memory type.

**File**: `CPU-BOARD-3202/circuit/MEM_RAM_49.v`

### Tang build: fail on any TA1117 (P5 of plan-fix-unconstrained-clocks)
Add a post-build check to `gowin_build.tcl` that greps the log for TA1117
(unconstrained clock relationship) and fails loudly - the bug class must not
come back silently. Also run the Vivado `check_timing` equivalent on the
Basys3 build. Source: docs/plan-fix-unconstrained-clocks.md.

### Delete SIP1M9.v / MEM_RAM_49.v once BLOCKRAM is proven on a Basys3 build
Agreed 04-AUG-2026, deferred. The same change must port or archive
`fpga/basys3/mem-test/basys3_mem_test_top.v` and
`fpga/qmtech-a35t/mem-test/qmtech_mem_test_top.v`, retire `test-ram`, and
drop the SIP variant of `test-memchain`. (`MAIN_RAM_SIP1M9` is selected by
no build today.)

### Dead `_OLD_WAY_` code
`CGA_MAC_APOS_INC.v`, `CGA_MIC_IINC.v` (and their tbs) hold `ifdef _OLD_WAY_`
branches; the symbol is defined nowhere. Delete when convenient.

### VERILATOR_SIM does three jobs
It gates the harness bus ports, the sim RAM size and the fast UART under one
symbol. Split only if one of them ever needs to change alone.

---

## Microcode-execution fidelity (added 10-JUL-2026)

### Static finding, unmeasured: CGA_CPU_ALU_CONTR GATES_49 mixes microword generations

`CGA_CPU_ALU_CONTR.v` GATES_49 (~line 730) NANDs the REGISTERED `s_alui8`
(executing word) with `s_gates1_out` = AND(CSALUM[1:0]) taken from the RAW,
unregistered field (next word). The C# microcode emulator forms the
"M set automatically" (ES) term from the executing word's ALUM and i8.
Effect if real: during a shift-type word followed by an ALUM,IR word, CSTS[1]
is forced (STS bit 7 reclocked, or a low-byte load when the word has
STS,EA). Fix direction: register the ALUM==11 term through the same ALUCLK
stage for the GATES_49 input only. Never measured; found by the July 2026
BFILL static analysis (git history, docs/bfill-sts-static-analysis.md).

### Audit: microorder-by-microorder fidelity sweep

The JMP0-3 hunt (parked by the owner 11-JUL-2026, docs/serial-binload-300.md)
suggested a class: microorders that no current test
exercises may be wrong or unimplemented, and could explain remaining
macro-instruction bugs (this was written while the self-test was still
failing; the self-test is clean since 13-JUL-2026). Plan: extract the
COMM/IDBS/condition decode tables from the Microprogrammer's Guide,
diff against what CGA_MIC/CGA_DCD/DGA actually implement, and give each
divergence a targeted unit test (the C# CPU at ND110Compile is a
working oracle for expected behavior - verify against the guide before
copying). Candidates to check first: vectored jumps, LDIRV
data source (IDB vs CD), MANIR/manual-IR flows, SCOND/hold-register
condition pipeline, COMM decodes marked "changed" in the ND-110->ND-120
delta (5, 36.2, 36.3).

### Evaluate: replace IDB OR-bus merging with muxes

Today many IDB/CD readers OR together all source outputs (inactive
sources drive 0). Evaluate switching to explicit muxes: pros - a wrong
enable produces an X/detectable in sim instead of silently OR-corrupted
data, clearer synthesis, kills a class of sim-vs-FPGA divergences
(EIOR-style read races); cons - large mechanical change across
generated code, must keep Logisim-structure compatibility, and the
golden byte-identity gates must hold throughout. Decision needed on
scope (board-level buses only vs inside gate arrays too).
