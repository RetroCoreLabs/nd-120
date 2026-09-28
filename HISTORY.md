# Project History

## Milestones

The results that mark eras, pulled out of the full table below:

| Date | Milestone |
|------|-----------|
| 11. March 2023 | Design documentation received from Lasse Bockelie - the project becomes possible |
| April 2024 | The whole CPU board compiles in Verilator for the first time |
| 13. December 2024 | The CPU executes microcode in Verilator: MACL runs, OPCOM answers over UART |
| 7. July 2026 | OPCOM boots on real hardware for the first time (Basys3) |
| 13. July 2026 | Instruction set validated: 13/13 INSTRUCTION-B areas pass vs ND-110 golden traces, self-test clean |
| 19. July 2026 | **First CPU boot on FPGA silicon** (Tang Nano 20K) |
| **24. August 2026** | **SINTRAN III boots on the Tang Nano 20K** - the operating system runs on real hardware, login and programs work |
| **25. August 2026** | **SINTRAN III boots on the Nexys 4 DDR** - second board, main memory in DDR2, timing-clean |
| **26. August 2026** | **Both boards clocked up, both verified on silicon**: Nexys deployed at 45.45 MHz (50 MHz also booted) and Tang at 20.25 MHz timing-clean, each with a 115200 console - up from 16.667/6.75 MHz and 9600 baud |
| **31. August 2026** | **Nexys cache on silicon**: all 8 CACHE-1X0-A00 tests pass; deployed cache-on at 33 MHz gives ~2.9x the throughput of 45 MHz cache-off on the same SINTRAN workload |
| **1-2. September 2026** | **Board-independent TDV2200 terminal core**: real box-drawing font (set 2, from RetroCore) embedded in `font_rom.v`, PS/2 keyboard - the console is the machine's own screen and keyboard, on the Nexys, MiSTer and MEGA65 |
| **2. September 2026** | **SINTRAN III boots on the MiSTer (DE10-Nano)** - third board on real silicon, TDV2200 console, self-test green |
| **2. September 2026** | **MEGA65 cores built for both revisions** (R3 HyperRAM 13.33 MHz, R4/R5/R6 SDRAM 20 MHz), timing-clean, not yet run on a MEGA65; Release 2 (`bitstreams-2026-09`) ships the MEGA65 and MiSTer binaries |

## Full history

Compressed history of the work progress on the ND-120 recreation:

| Date | Area | Description |
|------|------|-------------|
| 11. March 2023 | DOC | Received Design Documentation from Lasse Bockelie |
| 21. August 2023 | SCHEM | Logisim Drawings completed for DGA and DELILAH/CGA |
| 03. December 2023 | CPU | Using Logisim drawings to start generate Verilog files for DGA and CGA |
| 12. December 2023 | CPU | Starting to consolidate all information about PAL chips (PNG for PALASM code, OCR to TXT and write Verilog version of PAL code) |
| 26. December 2023 | SCHEM | Logisim drawings of CPU Board 3202D completed |
| 27. December 2023 | CPU | Using Logisim drawings to start generate Verilog files for CPU Board 3202D |
| 11. January 2024 | CPU | Most PALASM code has been ported to Verilog |
| January-June 2024 | CPU | Adding support chips, refactoring and bugfixing. Adding tests and test results |
| April 2024 | CPU | Control store finished in Verilog (sheets 16, 18, 19, 20, 21, 22 and ACAL 17); the whole CPU board compiles in Verilator for the first time; microcode moved into block RAM as hex files; every `inout` split into separate IN and OUT ports so the design can be synthesised at all |
| May 2024 | TEST | Support-chip and PAL cleanup, first testbenches and recorded test results |
| June-November 2024 | | No work done |
| 9. November 2024 | CPU | Starting up again after a long break. Cleaning up code, refactoring and testing. Connecting everything together. |
| November 2024 | CPU | Code standardised for synthesis: the `s_` internal-signal convention, module and top-file renaming, and the first simulation harness for the whole 3202D board |
| 20. November 2024 | CPU | Verilator - Microcode is loaded from ROM to DRAM. MACL microcode starts but fail on STACK operations, and fails on COND operations. |
| 13. December 2024 | CPU | Verilator - Microcode MACL starts, CPU test code runs. OPCOM is initialized and communication over UART works. |
| 29. Januar 2025 | TEST | Verilator - Testprogram 'INSTRUCTION-B.BPUN' (204384B 83.11.01) loads and starts. 7 out of 14 tests succeed. |
| January 2025 | CPU | First transcription errors caught by re-reading the schematics: swapped inputs in BRKDET and TBUF, and PAL 45001B's TEST pin wired to a dead net. BPUN programs can now be loaded from the command line |
| 22. Mars 2025 | DEV | Verilator & C++ - Interface with ND BUS via BIF module to C connector. Added support for Papertape reader and Floppy PIO written in C++ |
| 1. June 2025 | DOC | Reverse engineered the ROM chips for the panel controller's with help of Ghidra |
| June 2025 | CPU | Signal-documentation sweep across the CGA, MIC, MMU and I/O modules, and the first debug probes (control store address trace, DEBUGFLAG) |
| November 2025 | FPGA | First Vivado campaign: latch analysis, latch-to-flip-flop phase 1, the first `xc7a35t` (Basys3) constraints, and compile-time RAM sizing that separates simulator memory from FPGA block RAM |
| March-April 2026 | FPGA | Basys3 bring-up: Vivado batch build and lint scripts, 16-LED / 7-segment / ILA debug infrastructure, combinational-loop and block-RAM-inference fixes, `LATCH.v` rerouted through `sysclk`, and the MASEL race experiment tried and reverted |
| 7. July 2026 | SILICON | OPCOM boots on Basys3 hardware (tag `fpga-opcom-working-basys3`); FF-mode clock architecture fixes |
| 11. July 2026 | SILICON | SD/FAT stack proven on Tang Nano 20K hardware (read+write); microcode analysis proves the self-test never touches memory parity -> packed 16-bit SDRAM storage (`ND_SDRAM_PACK16`): CPU keeps 4 MB, 4 MB freed for the disk cache |
| 12. July 2026 | FPGA | Dual-toolchain Tang builds: OSS CAD Suite (yosys/nextpnr) primary, Gowin EDA backup; nextpnr closes the full 27/54 MHz clock target with >2x margin |
| 13. July 2026 | FPGA | Basys3 SD-Pmod port; memory-backend speed validation vs the no-wait-state protocol for every board; Cmod A7-35T activated (first 27 MHz BRAM build + SRAM bridge plan) |
| 13. July 2026 | TEST | Instruction validation campaign complete: 13/13 testable INSTRUCTION-B areas pass vs ND-110 golden traces; MACL self-test clean (STERR=0); two CPU transcription bugs found and fixed (MPY product low word, ROT/shift control) |
| 14. July 2026 | SILICON | Board-independent `ND120_CORE` extracted from `ND120_TOP`; Tang Nano 20K boots the papertape from a real SD card - proven on silicon |
| 15. July 2026 | CPU | RUN test area unblocked: Am2914 interrupt status fence made default, MOR (memory-out-of-range) wired to level 12; 29 new interrupt/trap gate-level testbenches |
| 18. July 2026 | SILICON | Tang masked level-10 grant root cause: a stale-INTRQN panel pulse taken as a macro interrupt; fixed faithfully (IO_37 STAT3 from real panel activity) - `Verilog/fpga/tang-nano-20k/ANALYSIS-cga-intr-masked-grant-root-cause.md` |
| 19. July 2026 | SILICON | **First CPU boot on FPGA silicon** (Tang Nano 20K) - WCS read-address transparent-latch fix |
| 20. July 2026 | DEV | Portable C device cores (NDDeviceCore) added as a submodule; ND-BUS seam gate validates the C cores against the real `ND_BUS_SLAVE.v` in Verilator |
| 23.-26. July 2026 | DEV | ND-BUS device campaign: floppy/SMD/DMA IOX conformance testbenches; DMA master validated against the real bus arbiter |
| 27. July 2026 | DEV | Floppy boot (`1560&`) works in Verilator - FLOMON + TPE monitor load from a floppy image (DMA zero-word capture fix) |
| 27. July 2026 | TEST | TPE CONFIGURATION D05 runs to NO ERRORS DETECTED in Verilator (trap-vector TVGEN_P2 muxIn_3, cache HIT gate, CUP fixes) |
| 30. July 2026 | SILICON | PAL transcription audit vs the original PALASM: 8 equation fixes; PAGING test suite passes 11/11 on Tang silicon (MMU page-table fix in PAL 44306A) |
| 31. July 2026 | SILICON | MOVEW APT-to-APT word-drop and double-trap phantom-vector-7 fixed; full INSTRUCTION multi-level run (levels 1-9) passes clean on Tang silicon |
| 03.-04. August 2026 | DEV | SMD illegal-load and status-read conformance with real CHS->LBA mapping; ST506/8-inch Winchester disc controller written in RTL at IOX 500 |
| 04. August 2026 | FPGA | Parity is never stored on an FPGA target (computed on the read path instead); stale SDRAM bank map corrected |
| 10. August 2026 | DEV | SD storage hub reworked: per-client ports instead of flat concatenations, per-client bus slices gated so a dropped one cannot hide, failure reasons carried out to each controller's status, sub-block writes served by read-modify-write |
| 10. August 2026 | CPU | Sheet-20 control-store capture was missing, so `TRA CS` read 000000; CDLBD's own output was absent from the LBD wired-OR; ALD strap set to bootstrap-load the Winchester |
| 11. August 2026 | CPU | PAL/sheet audit batch, eight fixes: parity could never be reported (sheets 43 and 46), the cache comparator was fed the wrong bus and the wrong tag bits (sheets 24 and 27), the PPN<->IDB transceiver outputs were ungated (sheet 28), the ND-bus data lines were not released on direction change (sheet 10), and the BANK/MWRITE idle condition was inverted (sheet 45) |
| 11. August 2026 | FPGA | `ND120_NO_CACHE` compile-time cache removal - the machine reports the cache as disabled, matching the board's own SW1 switch |
| 21. August 2026 | FPGA | Nexys 4 DDR board port added |
| 22. August 2026 | CPU | IDB combinational ring cut - FIDBO is OUTMUX-only and the PCR readback is registered; BRAM inference for main RAM and sysclk edge-capture for the parity-error latches |
| 23. August 2026 | CPU | Level-10 interrupt request was wired to `BINPUT~` (sheet 5C) |
| 24. August 2026 | SILICON | **SINTRAN III boots on the Tang Nano 20K.** The memory bank was decoded from the wrong side of the bus transceiver (`ND3202D.v:533`), so every DMA write landed in BANK0 and the CPU fetched a page nothing had written |
| 24. August 2026 | FPGA | 42 storage seam nets were implicit 1-bit (declared below first use); `EX3638` 42 -> 0 and the disc-activity LEDs work. Winchester read cache re-enabled |
| 24. August 2026 | SILICON | Clock variants added above the 6.75 MHz baseline: 13.5 MHz closes with 0 setup violations, 27 MHz runs SINTRAN and s3 but reports 1667 setup violations - fast and functional, not timing-clean |
| 24. August 2026 | TEST | Regression guards for the bank decode (`make test-bdbank`) and for flip-flop mode on every board (`make test-no-latches`); board `preflight.sh` and a hard sim log-size cap |
| 24. August 2026 | SILICON | Boot was disc-bound: the FAT chain was walked one card read per hop. Following it inside the streamed sector cut boot 168 -> 29.4 s and S3 cold start 235.8 -> 13.2 s |
| 24. August 2026 | SILICON | SD write bit clock raised 2.7 -> 13.5 MHz. The 4-bit data bus was wired and pinned but left disabled - it does not reach the SINTRAN banner |
| 25. August 2026 | DOC | Tang microSD slot wiring settled from the Sipeed schematic: all four data lines are routed, so a 4-bit failure is logic and not wiring |
| 25. August 2026 | FPGA | Nexys 4 DDR main memory moved from 24 KB BRAM to the 128 MiB DDR2: MIG port wrapper, two-client arbiter (main memory + SD storage), sheet-49 backend with a BRAM cache whose miss freezes the control PALs (`MEM_HOLD`) to meet the no-wait-state deadline |
| 25. August 2026 | SILICON | **SINTRAN III boots on the Nexys 4 DDR.** The DDR2 cache dropped its update when a late write strobe compared against the live tag RAM (address already drifted), leaving one stale cached word per boot - spin hangs, ERRFATALs and silent WAITs from the same bitstream. Fix: hit verdict latched at address-check. 7/7 boots to banner (~40 s), console login, timing-clean at 16.667 MHz |
| 26. August 2026 | TEST | DDR2 arbiter hardened with a testbench that the old logic fails: ties alternate instead of starving the storage client, a watchdog flags a dead port (sticky, report-only - no invented completions), orphan responses are recorded instead of vanishing |
| 26. August 2026 | FPGA | Nexys debug panel: tri-colour LEDs show DDR2/arbiter health (green healthy, red watchdog, blue orphan) and memory traffic; the four blanked 7-segment digits now show PIL, DDR2 bridge state and the health flags live (`DEBUG-PANEL.md`) |
| 26. August 2026 | FPGA | Nexys clock-up campaign: ten post-route frequency probes found the wall - every step 25 to 45.45 MHz closes the default flow, 50 MHz needs `phys_opt_design`; one path family at every clock (WCS microcode BRAM through the full microcycle to the register-file clock-enables, routing-dominated); stale 80 ns crossing bounds fixed; per-run report battery added to `build.tcl` (`fpga/nexys4ddr/timing.md`) |
| 26. August 2026 | SILICON | **SINTRAN boots on the Nexys at 50 MHz, then deployed at 45.45 MHz with a 115200 console** (3x/2.7x the 25-AUG clock). The 50 MHz closure proved fragile: changing one UART constant re-rolled placement from +0.007 to -0.210 ns. Console physical baud is the build constant alone - the microcode's 1988 BAUDV thumbwheel table tops out at 9600 and its value is stored but never times a bit |
| 26. August 2026 | SILICON | **Tang `fast20` variant: SINTRAN boots at 20.25 MHz with a 115200 console, TIMING-CLEAN (TNS 0, Fmax 20.556 MHz)** - the fastest clean Tang (3x the validated 6.75 MHz; the 27 MHz variant runs 32% past its own Fmax). New rPLL branch 40.5/20.25 MHz on a 648 MHz VCO |
| 27. August 2026 | TEST | **Both fast configurations soaked: 4 unattended SINTRAN hours each (Nexys 45.45 MHz, Tang fast20), 8/8 console probes; all four release bitstreams boot-checked on silicon.** Same day: test backlog burned down (101 unregistered testbenches -> 0 unmeasured, 104 registered, memchain resolved as a stale expectation), `make test` green end to end for the first time since 21-AUG (328/328), and a Verilog CI added (registry + yosys netlist gates every push, Tang OSS bitstream on release tags) |
| 27. August 2026 | SILICON | **Nexys SD-card deployment works end to end: configure from the card, boot SINTRAN from the same card - no PC software.** The bug: `sd_reset` was a constant, the card stayed in the SPI mode the board's config controller left it in (only a power cycle exits SPI mode), so every disc op after SD-config failed with FDISK error 3. Fix: a power-cycle controller (slot OFF 100 ms + 50 ms settle) triggered by configuration, reset, MACL and the machine's own system clear |
| 31. August 2026 | SILICON | Nexys cache brought up on the board: all 8 CACHE-1X0-A00 tests pass after four single-input transcription fixes (PAL 44511A CWR latch + its pin-19 polarity, a dropped Am9150 used-bit write, a DGA EPANS data-window leak that alone caused 20062 test-1 errors). Deployed build runs cache ON at 33 MHz - ~2.9x the throughput of 45 MHz cache-off on the same SINTRAN workload |
| 1-2. September 2026 | FPGA | Board-independent TDV2200 terminal core: 800x600 screen, PS/2 keyboard, console UART (7E1/8N1), the real TDV2200 box-drawing font (set 2, dumped from RetroCore) embedded in `font_rom.v` so every board carries the glyphs; wired on the Nexys with the physical keyboard (incl. the Left-arrow bridge fix). Console framing settled at 7E1 - the SC2661 sends one stop bit, so the earlier 7E2 in the docs was documentation only |
| 2. September 2026 | SILICON | SINTRAN III boots on the MiSTer (DE10-Nano): the whole machine, 4 MB in the DE10-Nano SDRAM module, TDV2200 console on its own screen and keyboard, storage from the OSD; boot, CPU self-test (green G lamp), font and keyboard all confirmed |
| 2. September 2026 | FPGA | MEGA65 cores built for both revisions on the MiSTer2MEGA65 framework (R3 HyperRAM 13.33 MHz / R4-R6 SDRAM 20 MHz), timing-clean, not yet run on hardware. Release 2 (`bitstreams-2026-09`) published with the MEGA65 and MiSTer binaries and per-board quickstarts |

## Retired documents

Plans, worklogs and handoffs whose work is finished were removed on
28-SEP-2026. Git history keeps their full text; this table says what each one
was and where its still-useful facts went.

| Document | Dated | What it was | Facts now in |
|----------|-------|-------------|--------------|
| `LATCH_ANALYSIS.md` | 7 Nov 2025 | Inventory of the six latch kinds (F595, TTL_74373, AM29841, generic LATCH, PAL_44401B DAP, CGA_INTR LAA) and a plan to turn them into flip-flops | Done as the dual latch/flip-flop build (`USE_TRANSPARENT_LATCHES`, `FPGA_FF_MODE`): `Verilog/docs/build-defines.md`, `DEVELOPMENT.md` "Build modes" |
| `VIVADO_FIX_PLAN.md` | 7 Nov 2025 | First Vivado campaign: synthesis failed on 3496 RAMB18 (35x the `xc7a35t`), 66 latch warnings, declaration order, port widths | RAM sizing done in `MEM_RAM_49.v` (`Verilog/readme.md` "RAM Configuration"); Basys3 state in `Verilog/fpga/basys3/README.md` |
| `verilog-code.md` | 2024 figures | Module-by-module tour of the 2024 tree (75,511 lines in 259 files) | The per-module docs in `*/circuit/doc/` and `HARDWARE.md` |
| `Verilog/verilog-remove-latch.md` | 29 Mar 2026 | Latch-to-flip-flop migration plan; phase 0 complete (dual mode, PAL_45001B stray-semicolon fix, `sys_rst_n` threaded to the PALs, `latch_ff_compare.cpp`) | Why the flip-flop mode is safe: `DEVELOPMENT.md` "Build modes"; the defines: `Verilog/docs/build-defines.md` |
| `Verilog/worklog-latch-refactor.md` | Mar-Apr 2026 | Branch `redo-idb` worklog for `LATCH.v`: the edge-detect version stopped the LCS load at CSA o000231 (ALUCLK is held constant during the load), so the level-sensitive `sysclk` capture was kept | The comment in `Verilog/Shared/ndlib/LATCH.v` |
| `Verilog/fast-clock-design-ida.md` | Apr 2026 | Idea only, never built: run the CPU on a slower clock than the latch-sampling clock to catch 1-sysclk enable pulses (MCLK, MACLK, ALUCLK) | Overtaken - the boards run 20-45 MHz in flip-flop mode with one `sysclk` and clock-enables |
| `Verilog/FPGA-BRINGUP-PLAN.md` | 3 Jul 2026 | Basys3 bring-up plan on branch `redo-idb` (boot stuck in phase 3 at CSA 0x0425/0x0426; the "MASEL Variant F" experiment, a second try after the revert in `0e4be9d`) | The comparison method, the boot golden-model idea and the ILA capture notes: `Verilog/sim/FPGA_DEBUG_RUNBOOK.md` |
| `Verilog/DELILAH-CPU/CGA_MIC/LDLCN_o000016_investigation.md` | 14 Apr 2026 | LDLCN / o000016 PANVC dispatch check: LC loads o01 at the first PANVC dispatch in Verilator; MASEL "Variant F" sysclk stage | Dispatch path and LC value: `Verilog/docs/boot-golden-spec.md` Phase 5; the analysis scripts: `Verilog/sim/VCD_ANALYSIS_GUIDE.md` last section; Variant F is in `CGA_MIC_MASEL.v` |
| `Verilog/sim/IDB_ANALYSIS.md` | 6 Apr 2026 | "Before" map of every IDB driver and reader, made ahead of the sysclk refactor | The IDB as it is now: `Verilog/docs/HANDOFF-cga-idb-ring-cut.md` |
| `Verilog/sim/HANDOFF-session-2026-07-22.md` | 22 Jul 2026 | Session handoff: built the scriptable probe (`nd120_probe`), captured the real INSTRUCTION-B paging set-up (`sim/tpe_paging.csv`, never committed: identity page table, PON after the table is filled, VPN 63 -> PPN o77, PT 162000), added `CPU_MMU_PT_29_replay_tb.v`, fixed the probe's UART `send` pacing | `Verilog/sim/PROBE-README.md`; the 177777 question is in `Verilog/TODO.md` |
| `Verilog/sim/HANDOFF-csharp-paging-capture.md` | Jul 2026 | Request to the C# ND-120 team for a reference capture of the TPE `INSTRUCTION` paging set-up, because every paged store to logical 177777 (the top page) read back 0 while the same store with paging off worked | The open question is in `Verilog/TODO.md` |
| `Verilog/floppyTester/PLAN-floppy-validation.md` | 20 Jul 2026 | Floppy validation campaign, phases 0-6, goal a full `1560&` boot | Goal met 27 Jul 2026 (above); ground rules and ownership split in `Verilog/floppyTester/CONFORMANCE.md`; testbenches in `Verilog/ND-BUS-DEVICES/FLOPPY-DMA/sim/` |
| `Verilog/tests/TESTBENCH-COVERAGE-CATALOG.md` | 31 Jul 2026 | One-off coverage sweep (109 registered entries then) | Generated `Verilog/tests/TESTBENCH-CATALOGUE.md` and `UNTESTED-MODULES.txt` (`make catalog`) |
| `Verilog/tests/doc-examples/COLOR-STANDARDS.md` | - | Byte-identical copy of `Verilog/docs/COLOR-STANDARDS.md` | `Verilog/docs/COLOR-STANDARDS.md` |
| `Verilog/sim/PROBE-DESIGN.md` | 22 Jul 2026 | Design note for the probe, implemented | Folded into `Verilog/sim/PROBE-README.md` |

## Area tags

Every entry carries one area tag. Choose it by **where the result landed, not
where the work happened**: a PAL fix proven on a board is `SILICON`, the same
fix proven only in Verilator is `CPU`. If a day produced two results in
different areas, write two rows for that date rather than tagging one row twice.

The set is fixed. Do not invent new tags - if something genuinely does not fit,
change this list deliberately.

| Tag | Covers |
|-----|--------|
| `DOC` | Original design documentation, ROM dumps, reverse engineering of the paper and the chips |
| `SCHEM` | Logisim-Evolution schematics |
| `CPU` | CPU and board logic in Verilog, including the PAL conversions and the bug fixes, proven in simulation |
| `DEV` | Peripherals and the ND bus: papertape, floppy, SMD disc, DMA, SD storage |
| `TEST` | Verification: testbenches, instruction campaigns, regression gates |
| `FPGA` | Synthesis, constraints, boards, toolchains, debug infrastructure |
| `SILICON` | Proven working on real hardware |
