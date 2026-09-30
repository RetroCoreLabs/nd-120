# ND-120 on QMTECH XC7A35T SDRAM core board

**Full path:** `Verilog/fpga/qmtech-a35t/`

The point of this board: same FPGA die as the Basys3 but with 32 MB SDRAM on
board, which removes the Basys3's 24 KB BRAM main-memory limit. The Basys3
cannot run SINTRAN for want of memory, and that is a capacity limit no clock
speed fixes. **This is the SINTRAN-capable Artix-7 target.**

## Status

**BITSTREAM BUILT 04-SEP-2026: `nd120_qmtech.bit`, timing met, 0 errors.**
Not yet run on the board.

| measure | result |
|---|---|
| **WNS at 20 MHz** | **+4.645 ns - TIMING MET** |
| logic cells | **12,619 of 20,800** (61%) |
| registers | 8,390 of 41,600 (20%) |
| block RAM tiles | **22 of 50** (44%) |
| pins | 51 of 150 |
| CPU domain (pre-fix build) | +5.255 ns, 0 of 27,698 endpoints failing |
| storage domain | +11.475 ns, 0 of 11,113 |
| SDRAM bridge domain | +10.949 ns, 0 of 351 |
| CPU <-> bridge (related pair) | +4.105 ns, 0 of 255 |
| combinational loops (`LUTLP-1`) | 16, downgraded to Warning - see below |

The whole machine fits with room to spare, so none of the fallback levers are
needed - the panel clock and the CPU's own cache both stay in.

### The `LUTLP-1` downgrade - a parked debt, stated plainly

`write_bitstream` runs DRC as a precondition and `[DRC LUTLP-1]` is an ERROR
by default, so **the build cannot write a bitstream without downgrading it**,
timing met or not. `build.tcl` downgrades it to a Warning, as
`fpga/nexys4ddr/build.tcl:522` and `fpga/mega65/build.tcl:452` already do, and
writes `drc_loops.rpt` at full severity first so the loops stay on record.

Why that is defensible: the loop is functionally impossible (the IDB source
select is a binary microcode field, `CSBITS[41:37]`, decoded into distinct
minterms), and the same RTL with the same loops boots SINTRAN III on the Tang,
the Nexys and the MiSTer - the Gowin flow has no loop DRC at all.

**What it costs:** Vivado's analysis through those paths is not trustworthy,
so **+4.645 ns is a floor, not a guarantee.** The Cmod A7, same die family,
has the same loops cut at a different point and misses by 89.8 ns. A wide
floor is still a floor. Full analysis, and where the ring actually is (not
where `CGA.v` says):
[`../../docs/HANDOFF-cga-idb-ring-cut.md`](../../docs/HANDOFF-cga-idb-ring-cut.md).

**The CGA IDB combinational ring is present here and does not matter.** The
netlist carries 16 `LUTLP-1` warnings and 10 auto-inserted `Synth 8-326` cuts,
and on this part Vivado breaks the ring somewhere harmless. That is worth
stating plainly because the same ring, broken at a different point, is what
fails the Cmod A7 by 89.8 ns on the same die family. See
[`../../docs/HANDOFF-cga-idb-ring-cut.md`](../../docs/HANDOFF-cga-idb-ring-cut.md).

The first build did report WNS -2.137 ns, from **two** paths, both storage
clock crossings given a **1.000 ns required time** - two unrelated clocks
timed as synchronous, because this board's clock constraint never took effect.
Generated clocks do not exist when an XDC is read before synthesis, so the
guard in `nd120_timing.xdc` found nothing and the constraint silently did
nothing. The relationships now live in `build.tcl` after `synth_design`, as
`set_max_delay -datapath_only` bounds rather than asynchronous groups (the
Nexys proved on 22-AUG-2026 that groups leave the storage handshake payloads
untimed and corrupt floppy reads). That file is deliberately almost empty now
and explains why.

Also proven: the design **lints clean end to end** - 281 modules, 0 errors, no
warning in any file of this board's own (`make lint`, Verilator in WSL). And
the two pieces it leans on are proven elsewhere on silicon: the 16-bit SDRAM
bridge mode boots SINTRAN on the MiSTer and builds timing-clean for the
MEGA65 R6, and the uncached storage path served every disc on the Tang for
weeks.

The two older stage tests (LED smoke test, mem-test port) are also written and
sim-verified, and have never run on the board either. Board facts and the smoke
tests: [docs/board-notes.md](docs/board-notes.md).

### What to do next, in order

The build is done; everything left is physical.

1. **Confirm a ground pin on JP3 with a meter** against the JTAG header's GND
   - see the ground section of [`../QUICKSTART-qmtech-a35t.md`](../QUICKSTART-qmtech-a35t.md).
   Do this before anything is wired.
2. Wire the console and the SD Pmod to JP3 (pin table in the quickstart,
   section 1).
3. `make load` with the Platform Cable USB II on the JTAG header, or program
   the existing `nd120_qmtech.bit` from the Vivado Hardware Manager.
   `make load` needs `ND120_VIVADO` and `ND120_BUILD_DIR` in `local.mk` at the
   repository root (run `python3 configure.py` once; see
   [CONTRIBUTING.md - Local settings](../../../CONTRIBUTING.md#local-settings));
   the bitstream lands in `$ND120_BUILD_DIR/qmtech-a35t/`.
4. Press ENTER on the console - OPCOM should answer with no card present at
   all. That is the smoke test; only then trust the card wiring.
5. Boot from the same SD card the Tang and Nexys use: `20500&`.
6. `make lint` is free and catches anything that drifts in the shared tree.

The step-by-step version, written for someone who has only the board and a
release binary, is [`../QUICKSTART-qmtech-a35t.md`](../QUICKSTART-qmtech-a35t.md).

### Release name

`build.tcl` writes the generic `nd120_qmtech.bit`. The download name carries
the board, CPU clock and console baud like every other board's, and is applied
at staging - never by hand:

```
cd Verilog/fpga && ./stage-release.sh nd120_qmtech_a35t_20MHz_115200.bit
```

The canonical name lives in [`../release-manifest.txt`](../release-manifest.txt).

## Files

| File | Purpose |
|------|---------|
| [`Makefile`](Makefile) | Standard board API (see [`../README.md`](../README.md) "Building"): `make` = full bitstream, `make load` = build + JTAG program, `make lint` = Verilator lint of the whole design, `make test TEST=led-test\|mem-test` = a stage test, `make sim` = the mem-test testbench, `make clean`. |
| [`build.tcl`](build.tcl) | The full ND-120 build. In-memory Vivado flow, no `.xpr`. Source list comes from the Tang project file minus the Tang-specific files; the SDRAM bridge files are kept. `-tclargs -noburn` builds without programming, `-promload` uses the runtime PROM-to-WCS load instead of preloading, `-nopanelclock` drops the panel clock. |
| [`rtl/nd120_qmtech_top.v`](rtl/nd120_qmtech_top.v) | Top level: MMCM, resets, `nd_storage_devices` on the card, `ND120_CORE` with SDRAM main memory. Reads as the MEGA65 machine wrapper with the Tang's card-side storage. |
| [`rtl/nd_storage_bram.v`](rtl/nd_storage_bram.v) | The region behind nd_storage's `mem_*` port, in block RAM. Its header explains why it is not a slice of the SDRAM here, which is the one real design constraint on this board - see "The 16-bit bridge and the disc cache" below. |
| [`rtl/lint_stubs.v`](rtl/lint_stubs.v) | Hollow `MMCME2_BASE` and `BUFG` so Verilator can lint past the clocking. **Lint only** - never in `build.tcl`. |
| [`nd120_qmtech.xdc`](nd120_qmtech.xdc) | Pins for the full build: board pins copied from `board-pins.xdc`, plus the console and SD card on header JP3 with the pin table. |
| [`nd120_timing.xdc`](nd120_timing.xdc) | Clock groups. `clk_cpu` and `clk2x` stay RELATED (the bridge depends on it); `clk_stor` is asynchronous to both. |
| [`board-pins.xdc`](board-pins.xdc) | Reference pin map - every pin confirmed from the vendor XDCs/manual (50 MHz clock `R2`, LEDs `C8`/`D8` **active-low**, key `H18`, full 39-pin SDRAM map, config properties). Copy ports from here; don't re-derive. Includes commented placeholders for future OPCOM UART header pins. |
| [`led-test/`](led-test/) | Stage-1 smoke test: `led_test_top.v` (1 Hz heartbeat on `led_n[0]`, key echo on `led_n[1]`), `led_test.xdc`, `build.tcl` (in-memory synth -> impl -> bitstream -> JTAG program, modeled on [`../basys3/mem-test/build.tcl`](../basys3/mem-test/build.tcl)). Run on the Windows host: `vivado -mode batch -source build.tcl` |
| [`mem-test/`](mem-test/) | Stage-2: port of [`../basys3/mem-test/`](../basys3/mem-test/) (same FSM/vectors/`MEM_RAM_49`, directly comparable with the Basys3 run that passes on silicon). 50 MHz MMCM math; no UART pin - `msg_printer` TX is an internal `mark_debug` net for ILA; result on the LEDs: running = fast blink, PASS = 1 Hz blink, FAIL = both solid. Sim: `cd mem-test/sim && iverilog -g2012 -DNO_MMCM -o tb qmtech_mem_test_tb.v ... && vvp tb` (passes). |
| [`docs/`](docs/) | Local copies of the vendor user manual + board schematic, and [`docs/board-notes.md`](docs/board-notes.md) - the distilled analysis of both plus the vendor SDRAM/LED sample projects. |

Hardware notes discovered while writing these (from the schematic/manual):
LEDs are **active-low** (3V3 -> 1k -> LED -> pin; drive 0 = lit); only 2 of
the "4 LEDs" are user-drivable (the others are the 3.3 V power indicator and
`FPGA_DONE`); the key on `H18` is active-low with a 4.7k pull-up; JP2/JP3
net names are `IO_<pin>` so header pins map straight to FPGA pins, but
**pin 1 = USB_5V and pin 2 = 3V3 on both headers** - don't wire signals there.

## Board facts

Source: official QMTECH repo
<https://github.com/ChinaQMTECH/QMTECH_XC7A15T_35T_CSG325_CORE_BOARD>
(schematic `Hardware/QMTECH_XC7A15T_35T_50T_CSG325_SDRAM_V1.pdf`, sample
projects with full pin XDCs under `Software/`).

- **FPGA:** XC7A35T-1CSG325C - the **same die** as the Basys3 `xc7a35t`, only
  the package differs. Vivado part string: `xc7a35tcsg325-1`. Anything that
  synthesizes / meets timing / gets fixed on the Basys3 applies here unchanged.
- **Clock:** 50 MHz crystal on pin `R2` (Basys3 is 100 MHz - MMCM settings
  differ, the target CPU/bus frequency does not).
- **SDRAM:** 32 MB Winbond `W9825G6KH-6`, **16-bit** data bus. Same chip family
  as the Tang Nano 20K `sdram-test` that already passes on hardware, but the
  Tang bridge ([`../tang-nano-20k/sdram-bridge/`](../tang-nano-20k/sdram-bridge/README.md))
  assumes a 32-bit SDRAM word - this board needs a **burst-of-2 variant**
  (two 16-bit beats per 18-bit ND word: data beat + parity beat).
- **Main-memory target:** 2 MB (1M ND words = 4 MB of the 32 MB chip).
- **I/O:** 4 user LEDs (sample XDC: `C8`, `D8`), 3 switches (reset on `H18`),
  two 50-pin 2.54 mm headers, Micro-SD slot, 8 MB `N25Q064A` SPI flash for
  standalone boot.
- **No on-board USB-UART.** Programming and debug go over JTAG (6-pin header,
  Xilinx Platform Cable USB II): bitstream + SPI flash, ILA and VIO all work
  through it, so the existing [`../basys3/`](../basys3/README.md) `ila_*.tcl`
  workflow carries over. OPCOM console options:
  1. BSCANE2-based JTAG-UART bridge,
  2. VIO character poking (manual, bring-up only),
  3. OPCOM TX/RX on header pins to an external 3.3 V USB-serial adapter -
     put those pins in the XDC from day one.

## Loading, wiring and the console test

Wiring (JP3 table + ground check), JTAG loading and the console test:
[`../QUICKSTART-qmtech-a35t.md`](../QUICKSTART-qmtech-a35t.md) - that file is
the one copy.

Developer notes that are not in the quickstart:

- `make flash` deliberately fails: no `.mcs`/SPI-flash flow is written for
  this board yet, so programming is JTAG only and volatile.
- The programming block at the end of `build.tcl` is a plain
  `open_hw_manager` / `connect_hw_server` / `open_hw_target` sequence against
  `get_hw_devices xc7a35t*`, so it works with any cable Vivado recognises,
  not only the Platform Cable.
- The build uses 1-bit SD mode (`USE_4BIT(0)` in the top level). Going to
  4-bit later is a parameter flip, not a rewiring job - but change one
  variable at a time: the Tang's 4-bit attempt failed on 24-AUG-2026 because
  the bit clock and the bus width were changed together, and it took a
  separate experiment to tell which broke it.

## The 16-bit bridge and the disc cache - the one design constraint here

**These two features cannot both be used as the code stands.** It is worth
understanding before reading a bring-up result, because the workaround shapes
the whole storage path.

The sheet-49 bridge has a 16-bit module mode, `ND_SDRAM_DQ16`, added 01-SEP-2026
for the DE10-Nano. In that mode one ND word occupies one 16-bit location and
the "two words per 32-bit location" folding disappears. The mode also drops
the full-location 32-bit access: `sdram18.v`'s DQ16 write branch takes the
16-bit buffer and ignores the `acc32` qualifier entirely, which its own header
says in as many words.

nd_storage's region port needs exactly that 32-bit access - `MEM_RAM_49_SDRAM`
raises `acc32` on every device operation. So the region cannot live in this
board's SDRAM. Nobody hit this before because the only two boards using the
16-bit mode, the MiSTer and the MEGA65, get their disc images from the host
side and never touch the SDRAM device port.

**The way round it, used here:** run every storage client DIRECT (uncached).
A DIRECT build needs one shared 2 KB staging line rather than a 4 MB cache,
which fits in a single block RAM ([`rtl/nd_storage_bram.v`](rtl/nd_storage_bram.v)).
Image size is not affected - under Phase 4 a DIRECT client fetches every
request from the card, so a 75 MB `WD0.IMG` is served through the same line.
It costs disc speed, not function, and it is a configuration that has run:
the Tang served every disc that way for weeks, and the 23-AUG-2026 experiment
measured no functional difference between cache on, cache masked off, and
cache not synthesized. `build.tcl` therefore defines `ND_STORAGE_NO_CACHE`
**and** `ND_STORAGE_DISCS_UNCACHED` - the two go together and neither is
optional.

**The proper fix, when disc speed matters:** teach the DQ16 mode a two-beat
32-bit access - two 16-bit locations per cache word - and widen the location
space so a region fits above main memory. The chip has room: 8192 rows against
the 2048 the mode currently maps. `sdram-bridge/sim/mem_ram_49_sdram_tb.v`
(measured ND-120 protocol replay) is the testbench to do it against.

## Planned bring-up order

1. Board files: XDC + build script. *(done)*
2. LED smoke test - clock and JTAG programming proven. *(written, never run)*
3. Port of the standalone [`../basys3/mem-test/`](../basys3/README.md).
   *(written, passes its testbench, never run)*
4. Full ND-120 build: SDRAM main memory, SD storage, serial console.
   *(built 04-SEP-2026, timing met WNS +4.645 ns, never run on the board - start here)*
5. Restore the disc cache by extending the 16-bit bridge mode, if disc speed
   turns out to matter. *(not started - see the section above)*

Steps 2 and 3 are no longer on the critical path. They were written when the
full build did not exist and were the only way to prove the clock and the
programming chain; step 4 proves both by booting. Run them if step 4 fails in
a way that makes the board itself the suspect.

## See also

- [`../README.md`](../README.md) - all FPGA targets
- [`../mega65/rtl/nd120_mega65_machine.v`](../mega65/README.md) - the closest
  relative: same CPU core, same 16-bit SDRAM bridge mode, same fabric and flow
- [`../tang-nano-20k/src/ND120_TANG20K_TOP.v`](../tang-nano-20k/README.md) -
  where the card-side storage wiring comes from
- [`../basys3/README.md`](../basys3/README.md) - same die, same Vivado flow,
  and the board this one exists to get past
