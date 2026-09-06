# ND-120 Verilog TODO

> Last updated: 28-AUG-2026. Newest entries are at the top; the "CURRENT PLAN -
> 02-AUG-2026" section below keeps its own date and says who owns what.
>
> Standing context: **SINTRAN III boots on the Tang Nano 20K** (24-AUG-2026).
> The ERRFATAL / page-fault campaign is CLOSED (`ND3202D.v:533` bank decode).
> The SD FAT-chain walk was fixed 24-AUG (boot 168 s -> 29.4 s, S3 cold
> 235.8 s -> 13.2 s).

---

## MiSTer port - 01-SEP-2026

**Next:** find why the CPU never reaches OPCOM. The state of the hunt is
written up in `docs/mister-microcode-loop.md`, including the annotated
31-microinstruction loop the board is stuck in.

Measured on the board, all of it ruling something OUT:
- CPU clock runs at exactly 20 MHz, a real PLL output on a global network;
  reset released; 0 synthesis errors; timing clean.
- `STERR` (002156) is NEVER entered and R2 is untouched - the self-test does
  not fail.
- Disabling the panel request (`TANG_NO_PAN`) removed a genuine spurious
  interrupt (debug word 000005 -> 000000) and changed the loop by not one
  address - the failure is not interrupt-driven.
- MIPS reads 00.00 with `ND120_MIPS_TAP` built, so NO macro instructions are
  being fetched: the loop is microcode-internal.
- All 32 WCS MIFs match the canonical microcode - MiSTer runs exactly what
  Nexys runs.
- Verilator with MiSTer's RTL settings reaches the `#` prompt (see item 2
  below for the caveat on that comparison).

The live lead: `NOTI2` (001020) is an UNCONDITIONAL `T,RETURN`, and MACL calls
`RIIE1` from 002026 with return address 002027 - the working sim returns
there, the board goes to 001021, the next sequential address. Same for
`CHKIT`, which returns to 001007 instead of the 2xxx caller. The
microsubroutine stack itself works (PICFM's call/return is correct), so the
question is why those particular returns take the wrong address.

Debug loop: `fpga/mister/tools/deploy_and_look.sh` flashes the board and pulls
a screenshot back over ssh, so no one has to watch the monitor. Probes:
`rtl/nd120_diag_print.v` (status line), `rtl/nd120_csa_trace.v` (the
consecutive microcode trace - the once-a-second sample ALIASES and must not be
read as a loop), `rtl/nd120_sterr_catch.v` (STERR + R2). All three have
self-checking testbenches registered in `tests/run_all_tests.sh`; retire them
with the `ND120_DIAG_PRINT` define once the CPU runs.

QUEUED, in order, once OPCOM is confirmed working on MiSTer:

1. **Real main memory - the DE10-Nano's 128 MB SDRAM.** MiSTer is the only
   target still on `MAIN_RAM_BLOCKRAM`, and `fpga/nexys4ddr/build.tcl:296-301`
   already records why that backend was retired there: the BRAM banks hold far
   less than the 4 MB `PAL_44446B` advertises, so everything above word
   0o200000 in a bank ALIASES onto low memory, "which forbids SINTRAN". Nexys
   keeps it only for A/B experiments. Nexys 4 DDR is the model to match.
2. **WCS images: sim and hardware run different microcode, and no test
   catches it** (found 01-SEP-2026). **DONE 02-SEP-2026.** Decided
   (Ronny): boards preload the RAW PROM word, simulators the 2024 patch.
   The patch is `A,6 -> A,0` in word 0o2002 = the master-clear wait loop's
   outer count 64 -> 1 (a 64x shorter power-on wait, nothing else; decoded
   in `Code/Microcode/gen_wcs_image.py`). `gen_wcs_image.py` now writes
   `wcs/` (raw, boards) and `wcs-sim/` (`--sim`, for SKIP_WCS sim runs);
   `Shared/support` is raw again; `tests/test-microcode-sync` now checks
   every `wcs_*.hex` copy in the tree against the variant its directory
   must hold (231 images, PASS).
3. **Storage in the MiSTer OSD** - WD0-3 plus floppy image selection, via
   `sys/sd_card.sv` presenting an OSD-mounted image as a virtual SPI SD card
   to the existing SD-FAT/SPI stack, rather than writing `hps_io` block-device
   glue.

For 1 and 3 - main memory and storage - the PDP-11 MiSTer core is a useful
SPEC ONLY - read it for the
shape of the solution, never copy its code (Ronny, 31-AUG-2026; also a licence
boundary, that core is not MIT and its terminal files are non-free).

---

## Terminal core is a VT100 - 30-AUG-2026

DONE: `Terminals/rtl/terminal_ctrl.v` rewritten as a plain VT100 (SINTRAN
terminal type 6) - ESC/CSI parser, CUP/ED/EL, SGR, DECSTBM regions with a
copy engine, DECOM/DECAWM/DECSCNM/DECTCEM, DECSC/DECRC, RIS, G0/G1 with DEC
Special Graphics (font page 2, `font/make_font.py`). Geometry 80x24 (was the
TDV's 80x25). New `byte_fifo.v` in front of the controller (a region scroll
outlasts one 115200 byte time). Unit suite green; decision + state in
`Terminals/README.md`.

DONE same day: keyboard arrows are VT100 too - `Terminals/rtl/key_vt100.v`
expands the decoder's new sequence markers into `ESC [ A/B/C/D/H` (FIFO'd, so
3 bytes per keypress survive the UART); wired on the Nexys top, tested end to
end in `terminal_console_tb.v`. MiSTer build 1 keeps raw bytes on its echo
path (arrows inert there until build 2 has a UART).

Also new: `fpga/nexys4ddr/flash.tcl` + Makefile targets - `make load` (JTAG,
volatile) and `make flash` (QSPI, permanent); README documents build /
release / flash.

DONE 30-AUG: first synthesis, via the CACHEFIX session's cache build 8.
Round 1 failed the 1080p pixel clock (139.7 MHz) by -0.328 ns on the
cursor-move paths; fixed in two commits (191bdee defer the moves, e26f44b
latch their operands) -> WNS +0.211 ns, all endpoints met. Flashed to the
Nexys 06:22, exercised by TPE console traffic. Utilization delta vs the
old terminal: +695 LUTs, +494 regs, +2.5 BRAM.

Open:
- Nobody has LOOKED at the VGA output or typed on the real keyboard since
  the VT100 rewrite - the scancode table remains transcription-only.

---

## Panel clock (MC68705 + MM58274) - 28-AUG-2026

DONE: `CPU-BOARD-3202/circuit/PANCAL_68705_CLOCK.v` emulates the clock path of
the panel processor (TRR PANC PFUNC 4-7 / TRA PANS: half-days since 1979 +
seconds, read/write, STAT4/VAL handshake, text-command drain), wired into
`IO_PANCAL_40.v` behind `ND120_PANEL_CLOCK`. Off by default (Tang is full):
ON BY DEFAULT on the FPGA builds since 29-AUG-2026 - disable with
`-NoPanelClock` on both boards (`gowin_build.ps1 -NoPanelClock`,
Nexys `build.tcl -tclargs -NoPanelClock`). The sim
harnesses still opt IN with `PANEL_CLOCK=1` (their default is unchanged so the
golden traces and console stay comparable).
Protocol taken from a fresh disassembly of the ROM; `Code/68705/U3/U3-COMPLETE.MD`
corrected. Doc: `docs/panel-clock-68705.md`. Unit tests `test-pancal-clock(-ff)`
registered and green.

PROVEN in Verilator 29-AUG-2026: TPE Monitor B01 (`1560&`) no longer prints
"The clock is not updated" - it reads PFUNC 4-7 and gets the time. That needed
two DGA fixes that had nothing to do with the panel clock and hid ALL panel
commands (docs/panel-clock-68705.md, "Two DGA bugs"): `TRA PANS` returned 0 to
A (EPANSN window, `DECODE_DGA_IDBS.v`), and `TRR PANC` never wrote the FIFO
(LDPANC~ pulse vs XCLK, `DECODE_DGA.v`). Both are UNCONDITIONAL (not behind
the define) - the microcode's own 0x0A ACTLV / 0x0D traffic now reaches the
panel too. Not yet committed; instruction-verify regression running.

Open:
- DONE 29-AUG on the Tang (fast20): SINTRAN takes the time from the panel
  across a MACL and TPE boots without its clock warning. Still to do on Nexys:
  the SINTRAN
  `@UPDAT` / `@CLOCK` / `@DATCL` round trip on silicon.
- Host preset of the time at power-up (TIME_HALFDAYS/TIME_SECONDS are brought
  out of the module for it) - today the clock starts at 1979-01-01 00:00.
- STAT3 idle pulse: the ROM pulses PB4 every ~3 ms while idle (0x0153); the
  Tang analysis 3f says it does not. Decide whether to model it (it is the
  same edge the old "conkick" manufactured, and that tripped the INTRQN lag).
- Verilator `sim/ make test_nd120` and `runSim/ make compile` fail at HEAD with
  82 `-Wall` warnings (IMPLICIT `DBG_PPN`/`DBG_PTW`/`PF_CAPTURED` in
  `ND3202D.v` - ports declared under `ifdef MAIN_RAM_SDRAM`, assigned
  unconditionally; `DBG_WDSTAGE` in `ND120_CORE.v`; PINMISSING `DBG_PTW_LVL`/
  `DBG_PANEL` at `ND120_TOP.v:850`). Present since the 25-AUG squash
  (`202c606`). The TPE run above was built with `-Wno-IMPLICIT -Wno-PINMISSING`
  on the make line only; the tree itself needs the `ifdef` guards.

## Test-gate backlog - 21-AUG-2026

`make test` currently aborts in its two meta-gates before running a single
functional test, for reasons that predate the IDB-ring work:

- `tests/audit_testbenches.sh`: 4 orphan testbenches with no Makefile rule
  and no registry entry - `CPU-BOARD-3202/circuit/sim/PT_stale_read_tvec_tb.v`,
  `ND-BUS-DEVICES/WINCHESTER/sim/nd_winchester_boot_hang_tb.v`,
  `ND-BUS-DEVICES/WINCHESTER/sim/nd_winchester_ticks_tb.v`,
  `SD-FAT/sim/nd_storage_ticks_tb.v`.
- `tests/tb_catalog.py`: 101 unregistered testbenches from the 21-AUG
  committed testbench sweep (`TB_RESULT: FAIL 101 unregistered testbenches`).

Decision 21-AUG (Ronny): leave as a backlog, burn down in its own session -
register or delete each, do not baseline them away.

BURNED DOWN 27-AUG-2026 (branch fpga-soak): 101 -> 5 unregistered. 100
registry entries added, every one proven passing before registration; the
4 orphans above are all registered too (PT_stale_read_tvec converted to a
contract-pinning regression - lead=0 stale IS the contract). The 5 left,
all measured, none baselined:
  - CYC_STRETCH_STROBES_tb: measured 27-AUG - 39 of its 41 divergences are
    the bench's own artifacts (inverted CYD/UCLK polarity, growing count
    window, phase aliasing; WAIT1/WAIT2 tied 0 bypasses the real wait
    states). The surviving fact: a stretched grant holds CYD, and WMAP_n
    (CPU_MMU_24.v:256) is combinational off CYD, so PT RAMs rewrite every
    sysclk of a freeze - MEASURED HARMLESS on silicon: the overlap probe
    (DBG_PTW_LVL & MEM_HOLD, sticky+counter, panel digit 4 bit 2) stayed
    0/0 across a full SINTRAN boot, and the wrong-PPN trap signature
    (TVEC 3 at PIL>=8) did not fire in two armed full boots. The 25-AUG
    wrong-PPN ERRFATAL is attributed to the stale-word cache bug fixed the
    same evening. The bench needs a rewrite before it can gate (fixed
    window, true polarities, board-real waits) - or retirement.
  - CGA_MAC_pt_apt_selection_tb: FAILS 129/259 ("PT request selects
    PCR[14:11]"); 17-AUG ERRFATAL-campaign probe, campaign closed by the
    bank-decode fix - stale expectations vs real defect UNRESOLVED.
  - CGA_TRAP_TVGEN_ptrace_tb: deliberately-red detector (early PT_15_9
    release latches a false page fault), same family as the baselined
    TVGEN race benches; register when the trap-vector timing is fixed.
  - CGA_MAC_replay_tb: SKIP - needs a maccap_vectors.txt capture that has
    never triggered.
  - fpga/nexys4ddr/floppy-hw-test/sim tb: no Makefile in its dir; board
    workstream.

Also parked: `DELILAH-CPU/CGA/sim/ND120_PF_CAPTURE_tb.v` wires a port
`c_pgs_at_read` that `ND120_PF_CAPTURE.v` does not have (elaboration error) -
belonged to the ERRFATAL/PGS-capture investigation. **That investigation
closed 24-AUG-2026** (bus bank-decode fix, `ND3202D.v:533`; SINTRAN III boots).
`ND120_PF_CAPTURE.v` did gain `c_pgs_at_read` plus `evt_noperm`/`evt_fault`/
`evt_any*` during the campaign, so this testbench should be re-checked - it may
simply elaborate now.

---

## CURRENT PLAN - 02-AUG-2026

### Owned elsewhere - do NOT change these files here

**SMD disc controller (1540).** A separate session has taken over the SMD work
from `docs/HANDOFF-smd-controller-01-AUG.md`, together with the Pi Pico C-code
side that is running ground-truth tests to confirm the nd100x oracle is 100%
correct. Off our plate:

- `ND-BUS-DEVICES/SMD/circuit/ND_SMD.v` - register semantics, the
  controller-type / word-count flip-flop question, `21540&` mass-storage load.
- `SD-FAT/circuit/nd_storage_disc_adapter.v` position mapping (still
  `blkaddr2*2048 + blkaddr1*64`, not the oracle's cylinder/head/sector -> LBA;
  changing it means changing the adapter, `ND-BUS-DEVICES/SMD/sim/nd_smd_tb.v`
  and `process_verilog_smd()` in `simDevices/NDBus.cpp` together).

What we already fixed and leave in place (all uncommitted, all verified in
Verilator): the 8 ms `DELAY_TICKS` derived from the board clock in
`ND120_CORE.v`, the boot-mode `+1`/`+7` writes, the first-fetch ready drop,
status bit 11 as DMA channel error, and `ND120_MAX_CNT` in the
`test-smd-boot` gate. Captured ground truth for the oracle side lives in
`ND-BUS-DEVICES/SMD/sim/traces/`.

**Ronny's, not ours to start:** the combined floppy+SCSI PCB question (onboard
Z80, decodes both the 1560 floppy/streamer window and SCSI at 144300).

### Waiting on Ronny

1. **Commit approval** for the whole working tree: the SMD fixes above, the
   testbench migration into per-module `sim/` folders plus the
   `tests/run_all_tests.sh` registry entries, the `git mv`/`git rm` already
   staged, and the Gowin place/route options in
   `fpga/tang-nano-20k/gowin_build.tcl`.
2. **Tang rebuild + flash.** Nothing above is on silicon; the flashed bitstream
   predates all of it. Only silicon can say whether the residual "Disc unit not
   ready" is the SD/image side (`020001`) or the DMA side (`024001`).

### Ours, unblocked, in priority order

1. **Finish the testbench campaign** (paused): `DECODE_DGA_COMM` is partially
   written, `BIF_BCTL_6` not started, then Tier 6. Every new tb must print
   `TB_RESULT: PASS` and be registered in `tests/run_all_tests.sh`.
2. ~~The 3 failing sdram-bridge testbenches~~ **FIXED 4-AUG-2026** - stale
   testbench, not an RTL defect; see the section below.
3. Then the standing items further down this file, including the FPGA parity
   hole that `test-memchain` turned out to be sitting on.

Suite state 4-AUG-2026: the sdram-bridge three now pass. Note the runner is
fail-fast, so a green run means "green up to the first failure" - to see
everything, run past it deliberately.

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

Task: extend the hammer in `Verilog/dmaSim/dma_p3_main.cpp` with an
INCREMENTING-address mode (new env `ND120_DMA_HAMMER_INCR=1`; pre-seed RAM
word=address so a stale latch returns a detectably wrong word; keep the fixed
mode). Re-run the 2x2 at N>=512 per cell, strictly serial with `make clean`
between builds (MIN_GAP/EARLY_REREQ are compile-time via EXTRA_VDEFINES; no
build-flags stamp in `Verilog/dmaSim/Makefile`). Also sweep MIN_GAP
{0,1,2,4,8,16,32} at EARLY_REREQ=0. Then either correct the "load-bearing"
wording in the PLAN doc (note the 332ff8e correction, don't rewrite history;
flag the pptx deck for its owner) or document the true minimum gap. Full
task spec with guardrails: session memory `dma-min-gap-verify-task`.

## LOW PRIO: RTC persistence - 6805 panel-processor / calendar clock emulation + ESP32 NTP time source

Added 31-JUL-2026 (Ronny). Today the machine has no saved wall-clock: TPE
reports "==TPE42=> The clock is not updated (display panel wrong or
unexisting)". On the real ND-120 the calendar clock lives with the display
panel's 6805 microcontroller; we need to emulate ENOUGH of the 6805 + RTC
chip that the operating system can save the clock and restore it on boot.

Constraints / design direction (part of the larger board plan):
- The Tang Nano 20K has no RTC and no battery backup, so the FPGA alone
  cannot keep time across power-off. Align this task with the planned ESP32
  integration: the ESP32 tracks real time via network NTP and provides it to
  the emulated panel clock on boot.
- SINTRAN III is NOT year-2000 safe (y2k). The ESP32 must therefore store a
  year OFFSET and always present SINTRAN a pre-2000 date - e.g. real year
  minus a fixed number of years (exact scheme to be decided; leap-year
  alignment matters when picking the offset) - so the OS never sees a year
  that crashes it. The true date lives only on the ESP32 side.
- Scope to work out when picked up: which 6805 panel registers/commands the
  OS actually uses (save clock / read clock), where they surface in the
  ND-120 I/O map, and the minimal emulation that satisfies both TPE and
  SINTRAN. Full notes: session memory `rtc-6805-esp32-persistence-task`.

## CLOSED 14-JUL-2026: interrupt status fence (Am2914) - now the RTL default

The DELILAH interrupt system is a close Am2914 copy. Its **status register**
(the fence that stops the interrupt just taken from being re-dispatched:
"READ VECTOR auto-loads vector+1 into the Status Register") had never worked in
our RTL - two transcription bugs in `CGA_INTR_CNTLR_VECGEN_STAT{,_SBIT}.v`
(schematic p.87): the cell's vector-load NAND took GPE instead of DCDF, and the
six SBIT instances (drawn WITHOUT pin names on the sheet) had four pins rotated.

Both fixes are now **ON by default** in the RTL; the escape hatch that restores
the old dead-fence behaviour is `ND120_INTR_STATUS_FENCE_OFF`, which no build
defines. Validated in FF mode: self-test 0 execution-phase STERR, unit suite
48/48, all 13 instruction-verify areas, and the `sim/` latch-vs-FF golden traces
byte-identical. Ground truth came from the C# DELILAH-L PIC trace: vector+1
loads on the winning chip only, and per-group DCDF (HIF/LOF) qualifies it.

The follow-on `IIC: 11 - Memory Out of Range` misreport was a separate
transcription bug - `CGA_INTR_CNTLR.v` swapped FIDBO bits 1 and 2 on the
status-fence LDSTAT path, decoding an IOX error as MOR - fixed in commit
`3acef36`. INSTRUCTION-B `RUN` now reaches its end of test.

Still owed: the Logisim CGA_INTR sheet needs the same two corrections, since
the schematic and the Verilog are maintained by hand and must agree. Full
analysis: `docs/RUN-level14-livelock-analysis.md`.

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

## DONE 3-AUG-2026: parity is COMPUTED everywhere, never stored (policy)

Ronny's decision: **no FPGA target wastes memory storing parity, ever.** All
five sheet-49 backends now drop DD[8]/DD[17] on write and regenerate them on
read as odd parity (`~^data`, the Am29833A convention) - previously Tang
regenerated, Basys3 returned a constant 0 (wrong for 128 of 256 byte values),
and the other three stored. `RAM_PARITY_STORAGE` is deleted, so storage cannot
be switched back on. Full table, rationale and gates: `docs/nd120-parity-
analysis.md` section 6b. New gate `test-am29833a-parity` proves the polarity
against the chip that checks it; the `test-memchain*` sweep writes deliberately
wrong parity and demands correct parity back (teeth-proven: Q9 forced to 0
fails 35 checks).

**What remains open below is the CHECKING side, which this did not touch.**

---

## OPEN: parity is never CHECKED - two independent reasons

Found 3-AUG-2026 while gating the policy above. Even now that every read
carries correct parity, nothing can ever report a bad one:

1. **`MEM_43.v:234`**: `assign LPERR_n = s_lperr_n | 1;` - "Always set to 1 to
   avoid Parity Error. TODO: FIX! ?" The local parity error cannot reach the
   CPU.
2. **`AM29833A.v:126`**: the error register is loaded only `else if
   (!ReceiveMode)`. But `MEM_DATA_46.v:230-255` wires **T to the memory bus and
   R to LBD**, so a memory READ is receive mode - the direction we care about
   is exactly the one the model does not evaluate. The datasheet text quoted at
   the top of `AM29833A.v` says the opposite: "In the receive mode, data and
   parity are read at the T port, and the data is output at the R port along
   with an /ERR flag showing the result of the parity test."

Point 2 looks like a transcription error in the chip model, but changing a
checker's semantics needs Ronny's call, and the two must be fixed together with
a decision about what the CPU should DO with a real parity error (level 14 +
IIC, PES/PEA - see `docs/nd120-parity-analysis.md` section 5). Until then FPGA
memory is unprotected: correct parity in, no checking.

---

## SUPERSEDED 3-AUG-2026 (kept for the root-cause trail): FPGA memory has NO parity

Root-caused 3-AUG-2026, out of the long-standing `test-memchain` "bit 8 drops"
failure. That failure was the testbench over-asserting, and it is fixed; the
hole it was sitting on is real and is still open.

The 18-bit memory word is two lots of 8 data + 1 parity: data in `DD[7:0]` and
`DD[16:9]`, **parity in `DD[8]` and `DD[17]`** - `MEM_DATA_46.v:239-242` and
`:266-269` wire exactly those two bits to the AM29833A `PAR` / `PAR_OUT` pins
(CHIP_1H low byte, CHIP_2H high byte).

Two things are missing on the FPGA path, and each one alone makes parity dead:

1. **Not stored.** `SIP1M9.v:92-105,141-145`: the `ramSize=3` BRAM path returns
   `reg_Q9 <= 1'b0` unless `RAM_PARITY_STORAGE` is defined. Deliberate - one bit
   per word still costs a whole RAMB18 per chip, 6 chips = 6 RAMB18 to hold
   4 Kbit. This is the path Basys3 synthesizes. (Tang uses the SDRAM backend
   instead, where `ND_SDRAM_PACK16` computes parity rather than storing it.)
2. **Not reported.** `MEM_43.v:234`: `assign LPERR_n = s_lperr_n | 1;` -
   "Always set to 1 to avoid Parity Error. TODO: FIX! ?" A local parity error
   can never reach the CPU even when the bit IS stored.

So the storage cut is only harmless because the checking was already disabled.
Fixing this means both halves together: define `RAM_PARITY_STORAGE` (accepting
the BRAM cost) AND make `LPERR_n` report, then decide what the CPU should do
with a real parity error. Until then FPGA memory is unprotected, silently.

`MEM_CHAIN_tb.v` now models the build choice instead of failing on it: a
`STORE_MASK` expects all 18 bits for the BLOCKRAM and SIM backends (which do
store parity) and clears bits 17 and 8 for the SIP1M9 FPGA path, so the data
bits are still checked exactly and an unstored parity bit must read back 0.
All three variants pass. Undo that mask the day parity storage comes back.

---

## FIXED 4-AUG-2026: 3 sdram-bridge testbenches failed on committed code

Found 3-AUG-2026, root-caused and fixed 4-AUG-2026. `make test` is fail-fast and
had been aborting at `test-memchain`, which sits EARLIER in
`tests/run_all_tests.sh` than these - so these three had been failing unseen
behind it:

```
fpga/tang-nano-20k/sdram-bridge/sim :: test              (11 errors)
fpga/tang-nano-20k/sdram-bridge/sim :: test-pack16       (9 errors)
fpga/tang-nano-20k/sdram-bridge/sim :: test-storage-port (9 errors)
```

**The RTL was right; the testbench was stale.** Commit `81462c0` (23-JUL-2026,
"Tang 4MB fix") changed which ND banks the bridge treats as populated, because
the board decode PAL `PAL_44445B` wires the three 1M-word banks in PHYSICAL
address order **BANK0, BANK2, BANK1**. So the two populated 1M regions are
**BANK0 (phys 0-1M) and BANK2 (phys 1M-2M)**, and **BANK1 is the absent third
bank** at phys 2M-3M (`MEM_RAM_49_SDRAM.v` lines 375-384). That fix is validated
on silicon - it is what made the Tang report 4 MB instead of 2 MB.

`mem_ram_49_sdram_tb.v` was last touched 11-JUL and still used the pre-fix map:
banks 0/1 populated, bank 2 absent. Every failing check follows from that one
mismatch - reads of BANK1 returned 0 (absent) where the tb expected written
data, and the BANK2 "absent" access returned real data where the tb expected 0.
The errors only LOOKED late because the soak repeats the same mismatch; the
first three fire immediately after the directed writes.

`test-pack16-part` passed throughout for the same reason: with
`TB_PART_ROWS=1024` only BANK0 is inside the CPU partition, so tb and RTL agreed
by accident on banks 1 and 2 both being unreachable.

Fix: the tb now derives the physical bank index from the real map
(`phys(bank) = (bank == 2)`), does its directed first/last-word writes on BANK0
and BANK2, uses BANK1 as the unpopulated-bank case, and soaks over {0,2}. No RTL
change. All four targets pass.

---

## BUG: 400$ tape boot triggers a continuous level-12 interrupt storm

The SD/FAT rewiring of the sim device path broke the tape byte feed: booting
INSTRUCTION-B from tape with `400$` produces tens of thousands of
"Generating/Clearing interrupt at level 12" cycles - the tape's level-12
interrupt re-arms every cycle instead of one-per-byte. Tests still finish
but runs crawl; the RUN command can't run at all. Full detail, repro, code
map and acceptance criteria: `docs/BUG-tape400-sd-level12-storm.md`.
Desired: run through the Verilog `ND_TAPE_400` fed by SD (one interrupt per
byte); acceptable fallback = restore the C tape wiring behind a build define
(like `VERILOG_TAPE`) so both variants stay buildable. Blocks the
instruction-verify per-area pass/fail (needs INSTRUCTION-B's own
`== END OF TEST ==` output, which the storm makes impractical).

---

## SD-FAT stack - PROVEN ON HARDWARE 11-JUL-2026; nd_storage underway

Hardware status: menu LIST/DUMP/CHECK/COPY/WRBLK1/speed tests all ran on
the Tang against a real FAT32 card. A cold-start create bug destroyed the
card's boot sector (root cause: sd_fat_rewrite S_DIR_W wrote the patched
dir sector to the raw input instead of the internal register = CMD24 to
sector 0); FIXED and now guarded by a permanent safety net (see the
WRITE-PATH SAFETY POLICY in SD-FAT/README.md): illegal-sector assertion
in the card models, boot-region byte-identity, fsck gates, cold-start
first-command plans, big-geometry FAT32 gate. Bitstream with the fix
built 11-JUL 12:05.

Speed: hardware measured 137 KB/s (single-sector CMD24 at 2.7 MHz;
per-sector card program busy dominates). Plan + ladder in
docs/sd-speed-plan.md; rungs a (13.5 MHz) + b (CMD18/CMD25 multi-block
in the MIT writer, menu 6/7 on bursts) in implementation.

nd_storage (Ronny's spec docs/nd-storage-interface-spec.md; design +
validation + status in docs/nd-storage-design.md /
nd-storage-spec-validation.md): steps 1-3 of 10 done, gates
test-nds-cdc/-engine/-write registered and green. Next: mount/preload,
contiguity check, Verilator system gate, tape + floppy adapters,
SDRAM board glue (partition decision; see also
docs/nd120-parity-refactor-order.md - the parity refactor work order
that upgrades the partition to 4 MB CPU + 4 MB storage).

## OLD STATUS (superseded 11-JUL): built incl. WRITES, sims pass

Reusable SD/FAT library in `SD-FAT/`: `sd_file_reader.v` (clean-room
project MIT since 12-JUL-2026; runtime file name, dir-entry
name/size/date/is-dir outputs, first-sector output, split sdcmd
tristate, 13.5 MHz data phase) + CLEAN-ROOM `sd_writer.v`
(CMD24, MIT, own unit tb `SD-FAT/sim :: test-writer`). Tang test project
`fpga/tang-nano-20k/sd-fat-test/`: UART menu (9600 8N1, `#` prompt):
1=LIST (size + DD-MMM-YYYY date + name, <DIR> entries), 2=DUMP BOOT.BPUN
(hex/octal, byte-verified), 3=COPY BOOT.BPUN over pre-created TEST.TXT
(in-place sector rewrite, Route B), 4=WRBLK1 (word[w]=w pattern into 1KW
block 1 = sectors first+4..7, range-guarded), H=help; persistent `SD:`
status; watchdogs everywhere. `make console` = interactive Verilator UART.
Verilator system test verifies dump bytes, list columns, copy content and
that WRBLK1 touched ONLY block 1. Bitstream builds (OSS flow).
Block map convention: 1KW block N of contiguous file = 4 SD sectors at
first_sector+4N (SD-FAT/README.md).

Next actions:
1. `make load` on the Tang, card from the README recipe -> acceptance
   A3-A6 + menu 3/4 on real silicon.
2. DONE 12-JUL-2026: the GPL vendoring question is moot - the reader was
   replaced by a clean-room MIT implementation (whole SD-FAT library MIT).
3. Milestone 2: ND_BUS_DEV_IF + TAPE_READER_400 against the Verilator bus
   ports, then `$` boot from card (plan sections 8 and 10); floppy device
   builds on the 1KW block map.

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

Two gate-integrity defects found on the way, both verified and both worth
fixing regardless of the ring: `tests/instruction-verify/run_area_test.sh:23-27`
prints `TB_RESULT: PASS` and exits 0 when its golden is missing (and the
goldens live OUTSIDE the repo), and `make -C sim compare` cannot fail because
its diff sits in a `|| (echo ...)`.

---

## The ring as a board blocker (Cmod A7 only)

The ring documented at `DELILAH-CPU/CGA/circuit/CGA.v:700-745` stopped being a
warning-count nuisance and became the thing that fails a build.

**Measured on the Cmod A7 (`xc7a35t`), first build of those files:** fits the
part easily at 11,493 of 20,800 LUTs, then **WNS -89.814 ns at 27 MHz**, 5133
of 18465 endpoints failing. From the routed checkpoint, **all 200 worst paths
share one start and one end** - `CPU/CS/WCS/CHIP_21C` to
`CPU/PROC/CGA/DELILAH/MAC/MAC_LA1025/R_LA_L`, 234 logic levels, 126.5 ns,
through the ALU, never touching main memory. The build reports **16
`[DRC LUTLP-1]` critical warnings and 23 auto-inserted `Synth 8-326`
loop-breaking false paths**, naming the ring exactly:
`ALU_OUTMUX/OUTMUX_IDBS/IDBS_R1/D_15_0[n]` -> `G_15_0[n]` -> FIDBO ->
MAC/INTR -> back.

**The number is a property of the netlist, not the machine.** The same RTL
gives that path 58 logic levels on MEGA65 R6, 93 on R3, 7 on the Nexys at
33.9 MHz, and 234 here; and it boots SINTRAN on the Tang, whose toolchain has
no loop DRC at all. Two things follow:

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

**Next: rebuild, then wire JP3 and boot.** Confirm a ground pin on JP3 against
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

Detail: `fpga/qmtech-a35t/README.md`. The older
`HANDOFF-qmtech-a35t-bringup.md` is superseded and says so at the top.

---

## Tang Nano 20K bring-up

### Integrate the SDRAM controller as ND-120 main memory (Tang only)

The 8 MB embedded SDRAM is validated standalone
(`fpga/tang-nano-20k/sdram-test/` - passes on hardware, full-8MB write+verify).
Next: bridge the nand2mario controller behind the `MEM_RAM_49.v` interface
(`AA_9_0`, `BANK0-2`, `RAS`/`CAS`, `MWRITE50_n`, `DD_17_0`), gated behind a
Tang-only define (`TARGET_TANG20K` / `MAIN_RAM_SDRAM`) so Verilator and Basys3
builds are completely unaffected. 8 MB of RAM available is acceptable.

**Files**: `CPU-BOARD-3202/circuit/MEM_RAM_49.v`, `Shared/support/SIP1M9.v`,
new adapter module under `fpga/tang-nano-20k/`.

**Design analysis done** (8-JUL-2026): the full protocol measurement (25k
accesses traced), the per-board backend plan (replace the MEM_RAM_49 body per
target instead of more SIP1M9 ifdefs), the 2x-clock SDRAM bridge design with
timing budget, refresh strategy, and the 18-bit-in-32 word mapping (2 banks =
4 MB) are documented in `docs/nd120-dram-memory.md`.

**Bridge implemented and protocol-validated** (8-JUL-2026):
`fpga/tang-nano-20k/sdram-bridge/` - `MEM_RAM_49_SDRAM.v` + `sdram18.v`, with
a testbench that replays the measured protocol (2000-access soak, parity
round-trip, refresh cadence) - PASSES.

**Tang top-level built** (8-JUL-2026): `fpga/tang-nano-20k/` -
`src/ND120_TANG20K_TOP.v` + rPLL (27/54 MHz) + cst/sdc + `nd120_tang20k.gprj`
(247 files) + `gowin_build.tcl`/`.ps1` (gw_sh on the Windows host). SDRAM pins
threaded through `MEM_43`/`ND3202D` under `ifdef MAIN_RAM_SDRAM` (Verilator
regression-checked; full Tang file set elaborates under Verilator lint).
**DUAL-TOOLCHAIN since 12-JUL-2026 (docs/tang20k-build-flows.md +
worklog-2026-07-12-pack16-dual-toolchain.md):** the full CPU also builds
with the OSS suite (`make [VARIANT=slow|crawl|full]` in
fpga/tang-nano-20k/, PRIMARY flow; `make gowin` = backup). All three
variant bitstreams built; nextpnr closes the FULL 27/54 MHz variant at
clk_cpu Fmax 57.5 MHz (GowinSynthesis had measured 9.38 MHz - the number
behind TANG_SLOW_BRINGUP). Remaining: `make load` on the board, compare
boot against `docs/boot-golden-spec.md` on the 9600-baud console; if
VARIANT=full boots on hardware, retire the slow-bringup default.

### CPU clock above 27 MHz (after 27 MHz validation)

The Tang's 27 MHz crystal is only the PLL reference - the `rPLL` can multiply
it. Plan: **validate everything at 27 MHz first**, then raise the CPU/SDRAM
clock via the rPLL. Data points: the vendored `gowin_rpll.v` has a ready-made
54 MHz setting (commented out), the nand2mario controller's timing parameters
are good to 66.7 MHz, and the factory LiteX SoC runs this SDRAM at 48 MHz
CL-2. So 27 -> 54 MHz is the natural step (keep `BOARD_CLK_FREQ` and all
UART/RTC counts derived from it, per the OPCOM speed fix).

---

## Future boards / peripherals (captured 8-JUL-2026)

### CMOD A7-35T target (Digilent)

> **ACTIVE since 13-JUL-2026 - the owner has the board.** First-version
> build files landed in `fpga/cmod-a7-35t/` (BRAM main memory, CPU at
> 27 MHz via the TARGET_CMOD_A7 MMCM branch, self-contained build.tcl +
> Makefile, SD-Pmod wiring documented incl. the 3.3V/VU voltage rules).
> **TODO: the pack16 SRAM bridge** - 512 KB / 256K-word main memory,
> full detailed plan in `fpga/cmod-a7-35t/SRAM-BRIDGE-PLAN.md` (the old
> 4-byte-access idea is INVALID per
> `docs/basys3-memory-speed-validation.md`; pack16 is mandatory,
> <= 33 MHz validated, est. 2-4 days).
>
> (Origin note, superseded: board folder created 2026-07-08; downgraded
> to research-only the same day on price - the owner has since acquired
> one.)

Same `xc7a35t-1cpg236` die as Basys3 in a DIP module: 20,800 LUT, 225 KB
BRAM, **512 KB external SRAM (8-bit bus, 8 ns)**, 4 MB QSPI, USB-JTAG/UART,
2 LEDs + 1 RGB, 2 buttons, one Pmod + 44 DIP I/O. Backend plan: start with
`MAIN_RAM_BLOCKRAM` (raise `BANK_ADDR_BITS`; 225 KB BRAM minus WCS budget),
later a `MEM_RAM_49_SRAM` backend for the 512 KB external SRAM (8-bit bus ->
~4 byte-accesses per 18-bit word; needs its own protocol bridge like the
SDRAM one). Reference manual:
https://digilent.com/reference/programmable-logic/cmod-a7/reference-manual
Demo: https://github.com/Digilent/Cmod-A7-35T-OOB (QSPI flash mx25l3273f).

### SD-card block devices across all boards

Goal: floppy/HDD images from SD card (FAT filesystem) so the ND-120 can load
software on every target:
- **Basys3 + CMOD A7:** SD-card Pmod on the Pmod connector (same module,
  same SPI-mode controller on both).
- **Tang Nano 20K:** on-board microSD (TF) slot.
- **MiSTer:** different route - images served by the ARM/Linux side (see
  `fpga/mister/`).
Shared piece: one SPI SD + FAT reader core (or soft-CPU-less FAT16/32
reader) behind a common "block device" interface feeding the ND-120 I/O
(floppy controller emulation). Design doc needed before implementation.

---

## High Priority

> Items raised when the self-test was still failing. The self-test itself is now
> clean (0 execution-phase STERR visits, 13-JUL-2026); these entries are kept
> because the underlying questions were never answered.

### CPU_15: IDB output assignment

Add assign of IDB out of `CPU_15` based on IDB out from PROC or CS. Also validate:

- `s_rt_n` -- also output from `CPU_PROC_32`. Verify which source to use (PROC or PCB top module).
- `s_rwcs_n` -- also output from `CPU_PROC_32`. Same question.

**File**: `CPU-BOARD-3202/circuit/CPU_15.v`

### CPU_15: MMU/LAPA/STOC validation

Previously marked as fixed but needs double-checking. IN/OUT signal assignments must be validated.

**File**: `CPU-BOARD-3202/circuit/CPU_15.v`

### AM29833A: Parity and error not implemented — RESOLVED (stale entry)

**Stale as of 11-JUL-2026:** `Shared/support/AM29833A.v` has real parity
logic (PAR_OUT = ~(^R) generate, 9-bit receive-side check register driving
ERR_n; reviewed 22-MAR-2025; equivalence tb `test-am29833a`). And parity
cannot be behind any self-test failure anyway: the microcode self-test
never touches memory parity — all 8 subtests are CPU-core-only. Evidence
with octal microcode references: `docs/nd120-parity-analysis.md`.

**File**: `Shared/support/AM29833A.v`

---

## Medium Priority

### CPU_MMU_WCA_31: WCA_n polarity check

Should `WCA_n` be switched in this assignment?

```verilog
assign PPN_23_10 = WCA_n ? 14'b0 : CPN_23_10;
```

**File**: `CPU-BOARD-3202/circuit/CPU_MMU_WCA_31.v`

### 3-state outputs: Verify all return 0 not z

For FPGA, tri-state (`z`) doesn't work internally. Check that all "3-state" buffers output `0` when disabled, not `z`.

**Relevant modules**: `TTL_74245`, `TTL_74244`, `TTL_74241`, `AM29841`, `AM29861A`

### Search for `TODO:` in code

Periodic cleanup -- grep for `TODO:` comments and address remaining items.

---

## Low Priority

### CGA/MAC and CGA_MAC_FASTADD: Unit tests

No dedicated unit tests. CPU self-test exercises these through the ALU path. Lower priority unless specific MAC bugs found.

### Tang Nano: SPI flash for microcode ROM

Gowin project has `` `ifdef GOWIN `` placeholder in `CPU_CS_PROM_19.v` but no SPI flash implementation yet. Needed for Tang Nano deployment.

**File**: `CPU-BOARD-3202/circuit/CPU_CS_PROM_19.v`

### MEM_ADDR_44: Add test code

No dedicated test. Works in full sim.

**File**: `CPU-BOARD-3202/circuit/MEM_ADDR_44.v`

### MEM_RAM_49: Refactor DD_17_0 signals for hardware

RAM works in simulation. For real FPGA hardware, the `DD_17_0` IN/OUT signals may need refactoring depending on memory type.

**File**: `CPU-BOARD-3202/circuit/MEM_RAM_49.v`

---

## Completed

| Item | Status |
|------|--------|
| `s_logisimNet`/`s_logisimBus` cleanup | Done -- dead PFIFC/PFIFD files deleted |
| BusDriver16 | Validated working |
| Static/Dynamic RAM refactoring for FPGA | IDT6168A BRAM fix done |
| Bus Connectors A-B-C | All connected in ND3202D |
| `s_acond_n` | Connected from `CGA_MIC_CONDREG` (was hardcoded to 1) |
| `s_brk_n` | Connected through CGA TRAP/INTR path |
| `s_inr_7_0` | Connected from `installation_number` via `INR_7_0` port |
| MEM_ADEC_45, MEM_DATA_46, MEM_LBDIF_48 | Logisim naming cleaned up |
| MEM_RAMC_50 | PAL chips connected |
| Latch-to-FF migration | Complete -- see `verilog-remove-latch.md` |
| LINT and latches | All latches converted to FFs with ifdef guards |
| CPU_15 "disconnected" signals | Verified: `s_eccr` -> MEM_43, `s_ioni` -> IO_37, `s_rrf_n` -> CYC_36, `s_mreq_n` is input from CYC_36. All properly connected. |

---

## Microcode-execution fidelity (added 10-JUL-2026)

### Fix the JMP0-3 vectored-jump dispatch (CGA_MIC)

The microsequencer's vectored jump (`T,JMP0-3`, microword bit 25 VECT)
always lands on the vector base: the low-4-bit OR (IR(0-3) or A-operand,
selected by MIS0) never contributes. Blocks the 300$ serial binary
loader (INCH polls IOX 302 but dispatches to the IOX 300 handler) and
any microcode-issued vectored device I/O. Pre-existing (fails in latch
mode too, first exercised 10-JUL). Full analysis + 2-minute sim repro:
docs/serial-binload-300.md. Reference implementations to compare
against (ASK before porting C# behavior - it may contain hacks):
$ND_REPOS/ND110Compile/ND110CPU (Cpu.cs ~783 vector dispatch,
~1310 LDIRV loads IR from the IDB - note our IRLATCH samples CD instead)
and NorskData-Doc ND-06.031.1 Microprogrammer's Guide (bit 25 / MIS0).

### Audit: microorder-by-microorder fidelity sweep

The JMP0-3 find suggests a class: microorders that no current test
exercises may be wrong or unimplemented, and could explain remaining
macro-instruction bugs (this was written while the self-test was still
failing; the self-test is clean since 13-JUL-2026). Plan: extract the
COMM/IDBS/condition decode tables from the Microprogrammer's Guide,
diff against what CGA_MIC/CGA_DCD/DGA actually implement, and give each
divergence a targeted unit test (the C# CPU at ND110Compile is a
working oracle for expected behavior - verify against the guide before
copying). Candidates to check first: vectored jumps (this bug), LDIRV
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
