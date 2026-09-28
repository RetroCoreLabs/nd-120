# HANDOFF - Tang Nano 20K: BPUN boot from SD card

> **RESOLVED 24-AUG-2026 - kept for the storage-proof detail in section 1,
> the not-a-bug list and the toolchain traps.** The hang hunt itself (old
> sections 2, 4, 7 and 8) was cut 28-SEP-2026; git history keeps it.
> The "open blocker" below (`400$` / boot hangs the CPU on hardware) is closed:
> the memory bank was decoded from the wrong side of the bus transceiver
> (`ND3202D.v:533`), so DMA writes landed in BANK0 and the CPU fetched zeros.
> With that fixed the Tang Nano 20K boots SINTRAN III (regression guard
> `make test-bdbank`). What still stands here is the record of what the SD/FAT
> storage stack proved on real silicon.

Written 14-JUL-2026. Branch `clock-enable-fix`.
Commits: `30e8e02`, `64fe9c4`, `bff68b5`, `5ba5b02`.

**State: the storage side is PROVEN ON SILICON.**

---

## 1. What is proven on the real board

Bitstream `0b3b4e12...` (Gowin flow, VARIANT=slow), loaded volatile.

- `sd_status = OK` (LEDs 4+3 lit). The mount FSM only reaches `M_OK` via
  `M_SCAN -> M_LOAD -> M_PARK -> M_CHK`, so this ALONE proves: SD card init at
  the 136.4 kHz identification clock, FAT16 walk, `BOOT.BPUN` located,
  **the whole file preloaded THROUGH the SDRAM device port**, and the
  contiguity check passed.
- `400$` lights LED 0 (CPU asked the tape) and LED 2 (a byte was served).
- **Memory really does receive the file.** Dumped `0<77` off the board and
  diffed against the card's BPUN: every word matched except 7 that the running
  program had scribbled (decoded to `''LP'ommands'T` = fragments of "All
  commands" from its own HELP text). So the SD -> tape -> CPU byte path
  delivers correct data into low memory.
- BSRAM **44/46 (96%)**: 34 SP + 10 SDPB, up from the 41/46 device-less
  baseline. The storage stack costs 3 blocks, 2 spare. Tape needed NO
  sync-read refactor (floppy/SMD got theirs later - see
  `Verilog/fpga/tang-nano-20k/BSRAM-BUDGET.md`, Part 2).

## 3. Things that turned out NOT to be bugs (do not re-chase)

- **`?` after `400$`** = BPUN **checksum error**, and the machine was RIGHT:
  the card's `BOOT.BPUN` was corrupted by a test program. Microcode proof,
  `nd-120-delilah-L-from-K.uc:6212` in the separate nd120uc microcode source
  repository:
  after "ALL WORDS ARE PLACED IN MEMORY" it reads the checksum, `XORAB`s it
  against the running sum, and branches to `ILLEG` (prints `?`) on mismatch.
  Ronny fixed the file. The loader + its checksum arithmetic WORK on hardware.
- **`400$` not auto-starting the program.** All three BPUNs have
  **execute = 000000**, i.e. action code 0 = "load only, do not start"
  (BPUN sections A-I, see `loadfile()` in
  `Verilog/runSim/Run120.cpp`). `20!` is the
  intended way to start. (It explains a clean load that returns to the
  prompt; it did not explain the old hard hang.)
- **Words 1..15 reading `000001..000017`.** That address ramp IS the program's
  real content - an independent parse of the BPUN predicts it exactly.
- **Contiguity.** `sd_file_reader.v:37` DOES walk the FAT chain. The
  contiguity requirement is `nd_storage` v1's own contract, enforced at mount
  by `nd_storage_fatchk.v`, because the engine block-addresses by arithmetic
  for random access. Ronny's card already PASSES it (that is what `sd_status =
  OK` means). Not a live issue.

## 4. The BPUN memory-dump check

To check what a `400$` load put in memory: `400$`, press **S1** (resets the
CPU, KEEPS SDRAM), do NOT run `20!` (it scribbles its own scratch), then:
```
cd Verilog/tools
./check_bpun_memory.py --bpun ../runSim/CONFIGURATIO-C08.BPUN --commands
#   -> prints the n<y commands (1K-word blocks) for the whole image
#   ... capture the console to cap.log ...
./check_bpun_memory.py --bpun ../runSim/CONFIGURATIO-C08.BPUN --dump cap.log
```
It reports a per-block OK/BAD table and the FIRST mismatching address, and
says how much was NOT dumped. Console input must be paced ~0.3 s/char.

## 5. Toolchain landmines

- **On 14-JUL-2026 the OSS flow (yosys/nextpnr) could not PnR:** 22
  combinational loops in `CGA_INTR ... IRQ_REG.RQBIT_*` (the gate-level SR
  latch), pre-existing. RQBIT was later made loop-free (commit `9d5a1cb`,
  "RQBIT V2"); whether the OSS flow now finishes the full CPU is not recorded
  (see `README.md`, "Full ND-120 build").
- **`make` used to LIE**: nextpnr writes nothing on failure and `| tee` hid its
  exit status, so `test -f` passed against a PREVIOUS run's file - a failed PnR
  reported success and would flash a 2-day-old bitstream. Fixed with
  `rm -f` + `pipefail` + `.DELETE_ON_ERROR`. **Do not remove those.**
- **A Windows drive mounted in WSL (NTFS via `/mnt/<drive>`) serves stale files.** `obj_dir` there kept mixing
  files from different Verilator runs even after `rm -rf`. The identical
  sources build clean on ext4 (`/tmp`). If runSim fails with a missing
  generated header or "has no member named `__Vtrigprevexpr...`", it is the
  filesystem, not the code.
- **Never start a Verilog comment with the word `verilator`** - it lexes as a
  metacomment and `-Wno-*` cannot suppress it.

## 6. Verilator side (all green)

```
cd Verilog/runSim
make run          # INSTRUCTION-B from the simulated card (default SD_STORAGE=1)
make run-config   # CONFIGURATIO-C08 - RUN probes devices
make run-fs       # FILSYS-INV-Q04  - looks INTO floppy/SMD images
```
`400$` boots off the simulated card **with RAM starting empty** - the harness's
BPUN pre-deposit is now OFF under `ND120_SD_STORAGE`. That pre-deposit used to
put INSTRUCTION-B in RAM before every run (its default `DEBUG.BPUN` is
byte-identical to `INSTRUCTION-B.BPUN`), which made every earlier "boots from
SD" claim worthless.
`Verilog/sim/` KEEPS its pre-deposit on purpose
(Ronny's ruling): no tape exists there, it is the injection method, and the
traces are the latch-vs-FF golden gate.
