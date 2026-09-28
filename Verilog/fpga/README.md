# FPGA targets

**Full path:** `Verilog/fpga/`

Per-FPGA build and flow files. The Verilog/HDL source is **shared** and stays
under `Verilog/` - the build scripts reference it by absolute path. Only the
board-specific build/flow files (scripts, constraints, tool projects) live here,
one folder per board.

**Ready-built bitstreams** are on the
[Releases page](https://github.com/RetroCoreLabs/nd-120/releases) with
step-by-step loading guides: [QUICKSTART-nexys4ddr.md](QUICKSTART-nexys4ddr.md),
[QUICKSTART-tang-nano-20k.md](QUICKSTART-tang-nano-20k.md),
[QUICKSTART-mister.md](QUICKSTART-mister.md),
[QUICKSTART-mega65.md](QUICKSTART-mega65.md) and
[QUICKSTART-qmtech-a35t.md](QUICKSTART-qmtech-a35t.md). The MEGA65 cores and
the QMTECH bitstream are built and timing-clean but have never run on their
board - the first testers are the users, and both quickstarts say so and say
what to report back.
Release process: [RELEASE-PLAN.md](RELEASE-PLAN.md).

## Targets

| Target | FPGA | Toolchain | Status | Details |
|--------|------|-----------|--------|---------|
| [**tang-nano-20k/**](tang-nano-20k/README.md) | Gowin `GW2AR-18` | OSS (yosys+nextpnr) primary / Gowin EDA backup | **Primary target - BOOTS SINTRAN III on silicon (24-AUG-2026)**, banner in 29.4 s from a Winchester image on the SD card. Full CPU bitstream with **4 MB SDRAM main memory** (packed 16-bit storage + computed parity, `ND_SDRAM_PACK16`; other 4 MB reserved for the SD disk-image cache); SD/FAT stack proven on hardware (read+write, safety-gated); nextpnr closes the full 27/54 MHz clock target with >2x margin | [tang-nano-20k/README.md](tang-nano-20k/README.md) |
| [**basys3/**](basys3/README.md) | Xilinx Artix-7 `xc7a35tcpg236-1` | Vivado (Windows host) | **OPCOM boots on hardware** (tag `fpga-opcom-working-basys3`); active debug line at 16.67 MHz; SD-card Pmod test build included ([`basys3/sd-fat-test/`](basys3/sd-fat-test/README.md), Pmod JB) | [basys3/README.md](basys3/README.md) |
| [**cmod-a7-35t/**](cmod-a7-35t/README.md) | Xilinx Artix-7 `xc7a35t-1cpg236` (Digilent Cmod A7-35T DIP module, 512 KB external SRAM) | Vivado (Windows host), same flow as Basys3 (same part) | **First built 04-SEP-2026: fits easily (11,493 of 20,800 LUTs) but MISSES TIMING, WNS -89.8 ns at 27 MHz** - the CGA IDB ring cut at an unlucky point, not the board (see [`../../docs/HANDOFF-cga-idb-ring-cut.md`](../docs/HANDOFF-cga-idb-ring-cut.md)); no bitstream written. Two build-script defects fixed on the way (missing include paths, runtime PROM-to-WCS load). 512 KB pack16 SRAM main-memory bridge planned ([`cmod-a7-35t/SRAM-BRIDGE-PLAN.md`](cmod-a7-35t/SRAM-BRIDGE-PLAN.md)) | [cmod-a7-35t/README.md](cmod-a7-35t/README.md) |
| [**nexys4ddr/**](nexys4ddr/README.md) | Xilinx Artix-7 `xc7a100tcsg324-1` (Digilent Nexys 4 DDR = Nexys A7-100T; 128 MiB DDR2, microSD, ~607 KB BRAM) | Vivado (Windows host), Basys3 flow as template | **SINTRAN III boots (25-AUG-2026), clocked up 26-AUG: deployed at 45.45 MHz with a 115200 console; 50 MHz also booted; 27-AUG: SD-card deployment end to end (configure + boot from one card, no PC software)** - DDR2-backed main RAM with BRAM cache; frequency search + bottlenecks in [`nexys4ddr/timing.md`](nexys4ddr/timing.md), boot record in [`nexys4ddr/SINTRAN-BOOT-25AUG.md`](nexys4ddr/SINTRAN-BOOT-25AUG.md), SD path in [`QUICKSTART-nexys4ddr.md`](QUICKSTART-nexys4ddr.md) | [nexys4ddr/README.md](nexys4ddr/README.md) |
| [**qmtech-a35t/**](qmtech-a35t/README.md) | Xilinx Artix-7 `xc7a35tcsg325-1` (QMTECH XC7A35T SDRAM core board, 32 MB SDRAM) | Vivado (Windows host), same flow as Basys3 | **BITSTREAM BUILT 04-SEP-2026: timing met, WNS +4.645 ns at 20 MHz**, 12,619 of 20,800 LUTs, 22 of 50 BRAM tiles. Not yet run on the board. The 16 `LUTLP-1` loops are downgraded to Warning to let `write_bitstream` run, as on the Nexys and MEGA65, so that slack is a floor not a guarantee. The whole machine: 4 MB SDRAM main memory via the sheet-49 bridge in 16-bit module mode (the MiSTer/MEGA65 configuration), SD-card storage and serial console on header JP3. **The one Artix-7 target that can run SINTRAN** - same die as the Basys3 without its 24 KB memory ceiling. Storage runs UNCACHED: the 16-bit bridge mode has no 32-bit access for the cache's region port. Wiring the console and SD Pmod to JP3, JTAG loading and the console test: [`QUICKSTART-qmtech-a35t.md`](QUICKSTART-qmtech-a35t.md) | [qmtech-a35t/README.md](qmtech-a35t/README.md) |
| [**mega65/**](mega65/README.md) | Xilinx Artix-7 `xc7a200tfbg484-2` (MEGA65 retro computer; R3: 8 MiB HyperRAM, R4/R5/R6: + 64 MiB SDR SDRAM; 100 MHz osc) | Vivado 2026.1 in-memory flow on the MiSTer2MEGA65 framework (git submodule) | **Whole machine built for BOTH revisions (02-SEP-2026), timing-clean, not yet run on a MEGA65** - CPU + 4 MB main memory (R6: SDRAM via the MiSTer sheet-49 bridge, 20 MHz; R3: HyperRAM via the Nexys cache seam + an Avalon port, 13.33 MHz), TDV2200 terminal on the machine's own keyboard/screen (VGA + HDMI), floppy 0/1 + Winchester 0/1 + tape on the framework's virtual drives, one `.cor` per revision; every new block has a self-checking bench ([`mega65/docs/00-plan.md`](mega65/docs/00-plan.md), [`QUICKSTART-mega65.md`](QUICKSTART-mega65.md)) | [mega65/README.md](mega65/README.md) |
| [**mister/**](mister/README.md) | Intel Cyclone V SE `5CSEBA6U23I7` (DE10-Nano / "MiSTer PI", ~110K LE + ARM HPS running Linux) | Quartus Lite 17.0.2 (free, Docker `raetro/quartus:17.0`) | **BOOTS SINTRAN III on silicon (02-SEP-2026)** - the whole ND-120 machine: 4 MB main memory in the DE10-Nano SDRAM module, TDV2200 console on the MiSTer's own screen + keyboard, floppy 0/1 + Winchester 0/1 + tape as Linux-side image files from the OSD, CPU at 20 MHz. Hardware-verified `.rbf` in Release 2; load guide [`QUICKSTART-mister.md`](QUICKSTART-mister.md) | [mister/README.md](mister/README.md) |
| [**azure-x930613/**](azure-x930613/README.md) | Intel/Altera **Stratix V GS** (Microsoft Azure FPGA 40GbE QSFP+ PCIe, P/N X930613-001, PCB DAT6MTHUEB0; 4 GB DDR3 ECC, 2x QSFP+/40GbE, PCIe Gen3 x16) | Quartus Prime **Standard** (per third-party report, unverified against a datasheet) | **Paper plan (31-AUG-2026)** - a datacenter PCIe accelerator card, not a devboard: no confirmed console/GPIO, custom non-catalog FPGA part per a third-party blog, real specs still unverified against a datasheet or the physical card | [azure-x930613/README.md](azure-x930613/README.md) |

## How fast can each device run the CPU - and what stops it

The honest yardstick is the machine's one critical-path family, identical on
every target: the **full microcycle** - WCS microcode BRAM ->
CSIDBS/INTR/ALU/FIDBO/TRAP/PALs/MIC/ACAL -> the WRF register-file
clock-enables, ~30 logic levels of combinational PAL/TTL transcription with
no register in between. Whoever executes those ~30 levels fastest wins.
Full analysis: [`nexys4ddr/timing.md`](nexys4ddr/timing.md) and
[`nexys4ddr/timing-analysis/TIMING_CLOSURE_REPORT.md`](nexys4ddr/timing-analysis/TIMING_CLOSURE_REPORT.md).

Legend: **measured** = read from that board's own post-route timing report
or proven on its silicon; *estimate* = transferred from a measured board
with the same die/fabric; unknown = never built or never measured.

| Device | Fabric | Microcycle on this fabric | Honest CPU ceiling (STA) | Proven on silicon | What actually limits it |
|---|---|---|---|---|---|
| **Nexys 4 DDR** `xc7a100t-1` | 28 nm Artix-7, LUT6 | **measured**: 29-30 levels, ~0.73 ns/level, 21.7 ns total at the wall | **measured**: 45.45 MHz default flow, 50 MHz with `phys_opt` (both single-seed; 50 is fragile) | **SINTRAN at 45.45 MHz + 115200 console (deployed, 4 h soak 8/8 probes) and at 50 MHz** | Nothing structural left below ~45 MHz. Beyond: the microcycle itself (only a pipeline breaks it, which kills cycle-faithfulness). DDR2 is decoupled in its own 75 MHz domain, so memory never gates the CPU clock |
| **Tang Nano 20K** `GW2AR-18` | ~55 nm Gowin Arora, LUT4 (vendor data) | **measured**: 32 levels, ~1.5 ns/level, ~49 ns total (`tang-nano-20k/build/.../nd120_tang20k_build.tr`) | **measured**: Actual Fmax **22.932 MHz** (fast20, after the 31-AUG `.sdc` CDC fix; was 20.6) | **SINTRAN at 20.25 MHz + 115200 console, TIMING-CLEAN (TNS 0), booted 26-AUG-2026, 4 h soak 8/8 probes** - the `fast20` variant, 3x the long-validated 6.75 MHz. 27 MHz also boots but runs **32% past its own Fmax** (1667 violations, margin unquantified) | 1) fabric ~2x slower per level than Artix-7 (physics), 2) Gowin flow has no phys_opt and no WNS gate, 3) SDRAM clocks share the rPLL VCO with the CPU clock (cap ~33 MHz), 4) ~~the `.sdc` is one line~~ **FIXED 31-AUG-2026**: it described no clock-domain crossing at all, so the storage data buses were timed as synchronous with a 0.000 ns requirement - 24 of the 25 worst setup paths. Two `set_false_path` lines: CPU-domain TNS -260.076 ns/398 endpoints -> -6.489/24, and with the MIPS tap off `ALUCLK_EN` the build now closes TNS 0.000 on every clock at 13.2% margin. Bottlenecks 1-3 stand |
| **Basys3** `xc7a35t-1` | same 28 nm Artix-7 fabric as the Nexys | *estimate*: identical per-level speed (same die family, same speed grade) | last **measured** 21-AUG-2026: WNS -29.8 at 16.667 MHz - **PRE-ring-cut and stale**; never re-measured after commit `b3ee391` cut the FIDBO ring | OPCOM boots; SINTRAN impossible regardless of clock | **Capacity, not speed**: 100 RAMB18 -> 24 KB main RAM config. The fabric could do Nexys-class clocks; there is no memory to run an OS in |
| **Cmod A7-35T** `xc7a35t-1` | same 28 nm Artix-7 fabric | *estimate*: identical per-level speed | first bitstream built at 27 MHz; its own timing report not yet examined for a ceiling | CPU runs; no OS (BRAM-only today) | Capacity until the 512 KB SRAM bridge lands (`cmod-a7-35t/SRAM-BRIDGE-PLAN.md`); then the SRAM protocol timing becomes the question, not the fabric |
| **QMTECH XC7A35T** `xc7a35t-1` | same 28 nm Artix-7 fabric | **measured** 04-SEP-2026, first build: CPU domain closes at 20 MHz with **+5.255 ns** slack over 27,698 endpoints, none failing | headroom exists but is unmeasured - 20 MHz was the target, not the ceiling | not yet run on the board | **Bitstream built, timing met at +4.645 ns. 12,619 of 20,800 LUTs, 22 of 50 BRAM tiles.** The CGA IDB ring is present (16 LUTLP-1, 10 auto-cuts) and lands harmlessly on this netlist - unlike the Cmod, same die family, where it costs 89.8 ns. The SDRAM bridge caps its own 2x clock at 66.7 MHz, so 20-33 MHz is the band |
| **MiSTer / DE10-Nano** `5CSEBA6U23I7` | 28 nm Cyclone V SE, ALM (vendor data) | synthesized; per-level figure not separately reported | not separately measured (runs at 20 MHz) | **SINTRAN at 20 MHz + TDV console, deployed 02-SEP-2026** | Runs at 20 MHz; the fabric ceiling is not yet measured. 28 nm ALM should land between the Tang and the Artix-7 per level - an *inference* until a Quartus timing report says otherwise |
| **MEGA65** `xc7a200t-2` | same 28 nm Artix-7 fabric as the Nexys, one speed grade faster | **measured** 02-SEP-2026 on the post-route checkpoints: the WCS -> MAC microcycle path is 34 ns in the R6 netlist (58 levels) and 57 ns in the R3 netlist (93 levels) - the R3 netlist times the CGA IDB ring through a longer loop-break point, the same "impossible but unprovable" ring the Nexys documents | **measured**: R6 closes at 20 MHz with 15.9 ns of CPU-domain slack; R3 closes at 13.33 MHz with 29.8 ns | nothing yet - no MEGA65 here; the first testers are the users of the release cores | The IDB ring, not the fabric: the period was set to fit the ring path rather than untime the internal data bus. Cut the ring in RTL and the R3 goes to 20 MHz+ like the R6; the R6 has room for ~40 MHz on paper (unmeasured) |

Three portable lessons from the Nexys campaign that apply to every row:

1. **A loose constraint hides the real ceiling.** At 60 ns the Nexys
   microcycle "took" 33 ns; under pressure the router compressed the same
   logic to 21.7 ns. Estimating Fmax from a relaxed run's WNS undershot the
   demonstrated ceiling by 50%.
2. **A WNS gate is what makes numbers mean anything.** The Vivado flows
   refuse to write a bitstream over negative slack; the Gowin flow does not,
   which is how the Tang ships 1667 violations and still boots - on margin
   nobody has quantified.
3. **Closures at the wall are single-seed lottery tickets.** Changing one
   UART divider constant re-rolled the Nexys 50 MHz closure from +0.007 ns
   to -0.210 ns FAIL. Near the wall, every edit needs its own clean report.

## Priority order (2026-07-14)

1. **Tang Nano 20K - primary target** (faster synth than Vivado, Linux-native
   OSS flow, 8 MB SDRAM for full main memory - 4 MB main + 4 MB disk cache).
   It is also the project's **value-for-money benchmark**: under 300 NOK for
   SDRAM + microSD + USB-JTAG/UART + HDMI - judge any new board suggestion
   against it.
2. **Basys3** - active debugging line for the board-independent timing work;
   OPCOM boots on hardware. BRAM-only (~64K words), so it stays the ILA/debug
   board, not a full-memory target.
3. **Cmod A7-35T** - active. First bitstream runs the CPU at 27 MHz on BRAM
   (same shape as Basys3); the 512 KB on-board SRAM upgrade to 256K-word main
   memory via the pack16 bridge is planned (`cmod-a7-35t/SRAM-BRIDGE-PLAN.md`).
4. **Nexys 4 DDR / Nexys A7-100T** - new (19-AUG-2026). The largest part
   in the set (xc7a100t: ~63k LUT, ~607 KB BRAM) plus 128 MiB DDR2 and an
   on-board microSD slot. Added as a Basys3 clone so the first bitstream is a
   known quantity; the point of the board is the two extensions (SD, then
   real main memory) and the headroom to raise the CPU clock.
5. **QMTECH XC7A35T** - the SINTRAN-capable Artix-7 target (Ronny owns it,
   with the Platform Cable USB II and an SD Pmod). Same die as the Basys3
   plus 32 MB SDRAM, which is exactly the ceiling the Basys3 runs into. The
   full build was written 04-SEP-2026 and lints clean; it has never been
   through Vivado. 4 MB of main memory, which is the whole of the ND-120's
   onboard memory space - the CPU board decodes onboard memory in the bottom
   2M words (`PAL_44445B.v:85`), so the other 28 MB of the chip could not be
   addressed as main store however it were wired.
6. **MiSTer** - future "full machine" target (disk images served from the
   board's Linux side); starts once FF-mode boot works.

Per-board detail lives **with the board** (README, vendor docs, plans and
handoffs in each `<board>/` folder) - this file is only the directory. For
the QMTECH resume instructions specifically, see
[`qmtech-a35t/HANDOFF-qmtech-a35t-bringup.md`](qmtech-a35t/HANDOFF-qmtech-a35t-bringup.md).

## Prerequisites

Every tool needed - Vivado, Gowin EDA, Verilator, iverilog, yosys, the
serial/JTAG access route, and the documentation generators - with exact
install and validation commands and the versions in use, is documented in
[`../docs/PREREQUISITES.md`](../docs/PREREQUISITES.md).

## Building - one API for every board

Every board folder has a `Makefile` with the **same targets**, whatever the
toolchain underneath. From WSL (the Windows-hosted tools are reached via
`powershell.exe` - works because the repo lives on a Windows drive):

| Target | Meaning |
|--------|---------|
| `make` | Build the bitstream (no board needed) |
| `make load` | Program the FPGA - **volatile** (JTAG/SRAM; gone at power-cycle) |
| `make flash` | Program **persistent** config flash (survives power-cycle) |
| `make sim` | Run the board folder's iverilog testbenches (where present) |
| `make clean` | Remove build outputs (where present) |

Board-specific extras: `basys3` adds `make reuse` (skip the ~1h resynth,
reuse the `synth_1` checkpoint) and `make lint`; `qmtech-a35t` takes
`TEST=led-test|mem-test` (default `mem-test`) and has no `flash` flow yet;
`nexys4ddr` takes `CLK=<MHz>` (default 16) plus `CACHE=0` / `VGACONSOLE=0` /
`PANELCLOCK=0`, and has the full `load` (JTAG, volatile) / `flash` (QSPI,
permanent) pair;
`mister` has a Quartus project (DE10-Nano / Cyclone V) and builds via the
Quartus-in-Docker flow - `make build` / `make load` / `make flash` / `make sim`;
its console is the TDV2200 terminal, same as the Nexys; `cmod-a7-35t`
uses the same Vivado flow as Basys3 (`make` / `make build` / `make clean`,
delegating to `build.tcl`). The standalone
`tang-nano-20k/sdram-test/` keeps its own Makefile with the same
`all`/`load`/`flash`/`sim`/`clean` targets (Linux-native OSS flow).

**On the Windows host** the underlying scripts are the direct entry points
(the Makefiles just delegate to them):

```powershell
cd Verilog/fpga/basys3
.\vivado_build.ps1              # bitstream ('make'); -ReuseSynth / -LintOnly / -Program
.\flash.ps1 -Quick              # 'make load' (JTAG only); omit -Quick for 'make flash'

cd ..\tang-nano-20k
.\gowin_build.ps1               # bitstream ('make'); copies WCS preload + checks EX3988

cd ..\qmtech-a35t\mem-test      # or led-test
vivado -mode batch -source build.tcl -tclargs skip_program   # 'make'
vivado -mode batch -source build.tcl                         # 'make load'
```

Programming transport per board: Basys3 and Cmod A7 = onboard USB-JTAG;
Tang Nano 20K = `openFPGALoader` from WSL (usbipd-attached) or the Gowin
programmer GUI; QMTECH = Xilinx Platform Cable USB II on the JTAG header.

## Shared context (applies to all boards)

- **The boot blocker is timing, not logic.** The FF-mode Verilator sim boots
  correctly; the FPGAs fail because ~35 modules use derived signals as clock
  nets. The fix (single `sysclk` + clock-enables) is board-independent. See
  [`../docs/fpga-debug-methodology.md`](../docs/fpga-debug-methodology.md) 3.2.
- **Microcode preload:** `SKIP_WCS_LOAD` bitstream-preloads the WCS and skips the
  runtime load phase - verified in Verilator, and required to fit the Tang's
  BSRAM. See [`../docs/skip-wcs-load.md`](../docs/skip-wcs-load.md).
- **Compile-time defines** (per-target behavior): see
  [`../docs/build-defines.md`](../docs/build-defines.md).
- **Golden boot reference** for validation: see
  [`../docs/boot-golden-spec.md`](../docs/boot-golden-spec.md).

## Reference docs

- [`../docs/tang-nano-20k-port.md`](../docs/tang-nano-20k-port.md) - Tang port analysis
- [`../docs/fpga-debug-methodology.md`](../docs/fpga-debug-methodology.md) - Verilator-vs-FPGA debug
- [`../docs/build-defines.md`](../docs/build-defines.md) - compile-time defines
- [`../docs/skip-wcs-load.md`](../docs/skip-wcs-load.md) - preloaded-WCS microcode
- [`../docs/boot-golden-spec.md`](../docs/boot-golden-spec.md) - expected boot sequence
- [`../docs/basys3-memory-speed-validation.md`](../docs/basys3-memory-speed-validation.md) - which memory backends meet the no-wait-state protocol (per board)
- [`../FPGA-BRINGUP-PLAN.md`](../FPGA-BRINGUP-PLAN.md) - overall bring-up plan
