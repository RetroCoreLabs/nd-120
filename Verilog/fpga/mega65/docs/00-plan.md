# MEGA65 port - the living plan

**Next:** act on what the testers send back. Both `.cor` files are attached
to the live release `bitstreams-2026-09` (uploaded 05-SEP-2026); the tester
instructions are `../../QUICKSTART-mega65.md`. Nothing of this port is
recorded as having run on a real MEGA65 yet.

Rebuilt 04-SEP-2026 (both cores, ~19 min each): `nd120_mega65_r6_20MHz_115200.cor`
(SDRAM, CPU 20 MHz, WNS +0.249 / WHS +0.002 ns, stamp `bc612ad+ 04-Sep-2026
09:25`) and `nd120_mega65_rev3_13MHz_115200.cor` (HyperRAM, CPU 13.33 MHz,
WNS +0.093 / WHS +0.032 ns, stamp `3e1f90c+ 04-Sep-2026 09:46`; the stamps
differ only by a commit the build does not read - same sources). What
changed since the 02-SEP cores: the boards' microcode preload is the RAW
PROM word 0o2002 (decision of 02-SEP, `Verilog/docs/nd120-facts.md`), and
RUN/STOP sends EXIT (SLUTT) - Alt+X proven on this path too
(`sim/nd120_console_mega65_tb.v`). If a 02-SEP core (stamp `e5bdea5+`)
is already out there, it has neither: RUN/STOP does nothing on it. Timing-clean incl. hold; the CGA IDB-loop DRC downgraded exactly as
on the Nexys. Two hold constraints on the framework's clk live in
`CORE/CORE.xdc` (a divider-feedback analysis artefact, and 100 ps of hold
uncertainty because the router's hold estimate sat ~70 ps above sign-off).

Rewritten 02-SEP-2026. Ronny's requirement: the bitstream shall have a
fully working ND-120 CPU, a TDV terminal with keys working, floppy, tape
and Winchester working - for BOTH memory revisions. No console-only or
memtest-only bitstreams go out.

## Decisions (Ronny, 02-SEP-2026)

1. **Both memories, two backends, picked by the board revision at build.**
   - R3 / R3A: the 8 MiB HyperRAM (all it has), through the framework's
     Avalon-MM port and the Nexys variable-latency seam.
   - R4/R5/R6: the 64 MB SDRAM, on the MiSTer/Tang sheet-49 bridge.
2. **MiSTer2MEGA65 (M2M) for everything else:** per-revision tops, keyboard,
   video (VGA + HDMI), virtual drives, OSD, `.cor` packaging. Costs accepted:
   GPL-3 framework as a submodule of an MIT repo, mixed VHDL + Verilog
   build, the QNICE disc-throughput question (unmeasured).
3. **No MEGA65 here. Friends test.** Every bitstream must show its own
   result on the MEGA65's screen and the case LED; one variable per send;
   ask the tester's revision first.

## What is built (02-SEP-2026)

The whole machine, two revisions, one `build.tcl`:

| Piece | File | Proof so far |
|---|---|---|
| CPU board, bus devices, WCS microcode | `ND120_CORE` + the MiSTer `files.qip` list, defines as `fpga/mister/nd120.qsf` minus Quartus-only | boots SINTRAN on the DE10-Nano at these settings |
| Main memory R4-R6 | `MEM_RAM_49_SDRAM` + `sdram18` (ND_SDRAM_PACK16 + DQ16, refresh 7 us), pins through `CORE/vhdl/framework-overrides/top_mega65-r{4,5,6}.vhd` | proven on the DE10-Nano's 16-bit module; the R6 chip is the same shape (32M x 16, A[12:0], BA[1:0]) |
| Main memory R3 | `MEM_RAM_49_DDR2` (Nexys cache + MEM_HOLD) over `rtl/nd_avalon_port.v` on the framework's `hr_core_*` port, window at word 0x200000 | seam proven on the Nexys DDR2; the port passes `sim/nd_avalon_port_tb.v` (burst and single-beat, random wait/latency, 300 random ops); the HyperRAM controller is the framework's, proven in every M2M core |
| Storage | `rtl/nd_storage_vdrives.v` (the MiSTer `nd_storage_hps.v` on vdrives' byte-wide bus) + `rtl/nd_storage_mega65_devices.v` (fd0 fd1 wd0 wd1 tape) | `sim/nd_storage_vdrives_tb.v` (8 checks) and `sim/nd_storage_mega65_devices_tb.v` (floppy R/W both drives, Winchester R/W both units, tape stream/rewind/EOF) against `sim/vdrives_model.v`; the vdrives side is the framework's, proven in the C64 core |
| Console | `Verilog/Terminals/` on the framework's video, `rtl/m65_keys_to_ps2.v` + the shared TDV decoder, 7E1 UART bridge at 115200 | `sim/m65_keys_to_ps2_tb.v` (60 keycap checks), `sim/nd120_console_mega65_tb.v`; **`make vtest` (`sim/nd120_mega65_machine_tb.v`): the whole R6 machine booted in Verilator on a 16-bit SDRAM model, RETURN typed through the framework's key scan answered by MOPC with a new `#`, twice** - the full keyboard path scan -> decoder -> UART -> SC2661 -> MOPC, after the first tester reported the console keyboard dead; the console-only bitstreams (B1) closed timing on both revisions |
| Machine top | `rtl/nd120_mega65_machine.v` (Verilog) under `CORE/vhdl/main.vhd` + `mega65.vhd` (VHDL skin, vdrives x5, HyperRAM port, SDRAM pins, OSD: text colour, panel, cache, HDMI mode) | Verilator lint clean in both memory configurations (`sim/lint_machine.sh sdram|hyperram`); Vivado elaborates and synthesises the whole thing |
| Clocks | `CORE/vhdl/clk.vhd`: one MMCM -> 40 MHz main (SDRAM bridge, the framework's keyboard scan), **25.197 MHz console clock** on the fractional CLKOUT0 (the whole console: 640x480@60 pixels, keyboard decoder, UART bridge; see the budget below), CPU 20 MHz on R4-R6 / **13.333 MHz on R3** (the R3 netlist times the CGA IDB ring through a longer loop-break, 57 ns; the period is made to fit it rather than untiming the internal data bus), 40 MHz @180 SDRAM chip; `CORE.xdc` names them; `build.tcl` bounds cpu_clk<->qnice_clk, cpu_clk<->hr_clk and the crossings into pix_clk with `set_max_delay -datapath_only` | the bridge's "same PLL" rule holds by construction |
| Packaging | `make all BOARD=r6` / `r3` -> `build/<board>/nd120_mega65_<board>.cor` via `coretool` (model byte, CRC, FPGA-part check); `.cor` version = the banner stamp | `--verify` on both |
| Boot verdict without a monitor | case power LED: amber = self-test running / halted, green = MACL2 reached (self-test passed) | wired from the CPU board's own green lamp |

### Video data rate and the HyperRAM budget

The first R6 tester's picture tore in every HDMI mode above 480p (diagonal
streaks, colour noise, the panel drawn twice) and showed red flecks in
720x480; the welcome screen and the framework menu were clean. The cause is
the data rate of our picture into the framework's HDMI path, not sync:

- The framework's `ascal` rescaler stores every input pixel in the board's
  HyperRAM and reads it back for the HDMI mode. That is ONE 8-bit chip at
  100 MHz; a 128-byte burst costs ~75 clocks (`hyperram_ctrl.vhd`: command,
  latency 4, data, recovery), so the chip moves ~170 MB/s for writes and
  reads together.
- The rescaler's input buffer is 2 x 128 bytes with no back-pressure
  (`ascal.vhd` `i_dpram`, write queue depth 1 + 1). Writes have priority but
  must wait for a read already in flight, so a half must be drained within
  2 + 75 + 74 = **151 clocks** of filling, or the input overwrites it and that
  chunk is lost. At 24 bpp a 128-byte chunk is 42 2/3 pixels, so a lost chunk
  also rotates R/G/B for the rest of the line - the colour noise.
- 800x600 at 40 Mpx/s x 24 bpp filled a half every **107 clocks**: lost
  chunks whenever the output side was reading, which in 720p is nearly
  always. The other M2M cores feed the rescaler 7.9 Mpx/s (C64) and
  14.3 Mpx/s (Apple II); we fed it 2.8x anything it had been used with.

| console into the rescaler | half-buffer fill | margin vs 151 | chip load, 720p60 |
|---|---|---|---|
| 800x600 @ 40 MHz, 24 bpp (first release) | 107 clocks | **-44** | 105 % |
| 800x600 @ 40 MHz, 16 bpp | 160 | +9 (+2 after the 5-clock toggle delay) | 72 % |
| 640x480 @ 25.2 MHz, 24 bpp | 169 | +18 | 67 % |
| **640x480 @ 25.2 MHz, 16 bpp (now)** | 254 | **+103** | 45 % |

Load = (write bursts + read bursts per second) x 75 clocks / 100 MHz; reads
are one input line per input line per frame (nearest-neighbour, `o_readlev`).
In 480p/576p the rescaler downscales first and the first release ran at
~75 %, which is why those modes were nearly clean. Where it is implemented:
the pixel clock in `CORE/vhdl/clk.vhd`, the 640x480 parameters in
`rtl/nd120_console_mega65.v`, the 16 bpp format in
`CORE/vhdl/framework-overrides/digital_pipeline.vhd` (the framework hard-wires
24 bpp), `VGA_DX/DY` in `globals.vhd`, the OSM texts re-wrapped to 38
columns in `config.vhd`.

**First full R6 build (02-SEP 15:32):** synthesis and implementation went
through; WNS -0.174 ns on 17 endpoints that were ONE bug (vdrives' mount
records left in the wrong clock domain - fixed), and 26 hold misses on the
framework's MMCM DRP pins that the router believed it had fixed (its own
summary said +0.053, sign-off said -0.491) - `phys_opt_design -hold_fix`
added after routing, and the timing gate now checks hold too. The
combinatorial-loop DRC alerts (16 loops, same nets, same sizes) exist in
the deployed Nexys build.

## Remote-testing gate (still binding)

1. Every bitstream diagnoses itself on the MEGA65's own screen and LED.
2. Results come back as a photograph: banner with git hash + date + board
   revision + memory, the SINTRAN start-up text, the LED colour.
3. One variable per send.
4. Ask the revision first (RESTORE ~2 s, HELP: "MEGA65 MODEL"); the flash
   menu refuses a wrong-model `.cor`.
5. Everything provable in simulation is proven there first; every new file
   has a bench registered in `Verilog/tests/run_all_tests.sh`.

## Toolchain facts (B0, 02-SEP-2026)

1. `.v` files of the framework must be read as SystemVerilog under 2026.1.
2. `auto_detect_xpm` before `synth_design`, or the XPM CDC false paths are
   never applied (229 phantom failing endpoints).
3. `common.xdc:122` (`-through .../i_ascal/reset_na`) matches nothing under
   2026.1; `CORE/CORE.xdc` restates it against the registers' CLR/PRE pins.
   The framework's own line still prints one CRITICAL WARNING per build.
4. Framework floor on the A200T: ~14.8k LUTs, 55.5 BRAM tiles.
5. `coretool` (mega65-tools, fetched by `make toolchain`, pinned) packs the
   `.cor`; the QNICE submodule's `bit2core` cannot (no model byte).
6. Host prerequisites in WSL: gcc for `qasm`/`qasm2rom`/`monitor.rom`
   (`make toolchain`), `make rom` for the M2M firmware; both submodules need
   LF line endings (`core.autocrlf false` set locally in each).
   `CORE/m2m-rom/make_rom.sh` assembles the Shell from a COPY of the
   framework's `M2M/rom/` with `CORE/m2m-rom/framework-overrides/` laid on
   top - the firmware counterpart of `CORE/vhdl/framework-overrides/`. cpp
   resolves a quoted `#include` next to the including file first, so a `-I`
   path alone cannot replace a file `shell.asm` includes; hence the copy.
   `overrides.sha256` names the submodule file each override was made from
   and the build stops when that file changes (a submodule bump), so an
   override is re-made, never silently kept.
7. VHDL file paths in `globals.vhd` resolve relative to the reading VHDL
   file; our `CORE/` is one level above the submodule, so the firmware
   path gained one `../`.

## Found by the first tester: keyboard and Help key dead

The report was "the keyboard does not work at all, the Help key neither",
with the CPU at the OPCOM `#` prompt. The whole keyboard path of OUR code
(framework scan -> `m65_keys_to_ps2` -> `ps2_decoder_tdv` -> UART -> CPU)
answers a RETURN in the full-machine Verilator bench (`make vtest`), so the
fault was looked for in what runs beside it: the framework's QNICE Shell.

The cause is a V2.0.1 firmware bug, upstream issue sy2002/MiSTer2MEGA65#58:
`ROSM_SAVE` (`M2M/rom/options.asm`) walks the virtual drives before saving
the menu settings and keeps the drive number in R8, the register
`VD_DRV_READ` returns its result in. With clean write caches R8 alternates
0,1,0,1 for ever. The loop is left by accident with one drive; we have five
(`C_VDNUM`), and the code only runs with a settings file on the card - we
ship `/nd120/nd120cfg`. So QNICE froze the moment the tester closed the
Help menu (the HDMI-mode photo proves the menu was used). The keyboard is
disconnected from the core while the menu is open (`KEYBOARD_AT_OSD` false,
`gencfg.asm RP_OPTM_START`) and reconnected only AFTER `ROSM_SAVE`
(`HELP_MENU`), so the freeze left the core without a keyboard and the Help
key dead - both symptoms, one fault. The shipped ROM's listing has the loop
at 0x2BE5-0x2BF0, where the upstream reporter found QNICE stuck.

Upstream fixed it on `develop` (commit `bcb34f4`, planned for V2.1.0); that
fix is `CORE/m2m-rom/framework-overrides/options.asm` here (toolchain fact 6
above). Related upstream reports worth knowing when a tester says "no
keyboard, no menu": #82 (a short reset while QNICE waits on a HyperRAM read
hangs QNICE; watchdog in `qnice2hyperram` on `develop`, R3 only for us) and
#59 (QNICE stuck in `HANDLE_DRV_RD` with disc images in HyperRAM; open).

## Open questions only the board can answer

- **HyperRAM latency vs SINTRAN (R3).** MEM_HOLD absorbs it; the number is
  unmeasured. The banner's memory line says which backend a photo is of.
- **QNICE-served disc throughput.** Sized for floppy-class traffic in the
  framework's own cores; SINTRAN pages at Winchester rates. If the machine
  runs but crawls, this is where to look; the fallback is a small
  standalone benchmark bitstream (random-LBA `sd_rd -> ack` on a 75 MB
  image) - never a probe on the SINTRAN console (Ronny, 02-SEP-2026).
- **The R6 SDRAM bridge on this chip.** Same geometry as the DE10-Nano
  module; refresh 7 us for 8192 rows. Unverified on the MEGA65's pins and
  trace lengths; no I/O timing constraints, as on the MiSTer.
- Automount / image folder conventions of the framework (`/nd120`).

## Layout under `Verilog/fpga/mega65/`

| Path | What |
|---|---|
| `m2m/` | git submodule -> sy2002/MiSTer2MEGA65 @ `423ba6e`; its own `M2M/QNICE` submodule inside |
| `CORE/` | our side of M2M's `CORE/` contract (the framework's template, edited): `vhdl/mega65.vhd` (wrapper), `vhdl/main.vhd` (VHDL skin over the Verilog machine), `vhdl/clk.vhd`, `vhdl/config.vhd` (OSD texts + menu), `vhdl/globals.vhd` (5 vdrives), `vhdl/framework-overrides/top_mega65-r*.vhd` (SDRAM pins into the core), `CORE.xdc`, `m2m-rom/` (firmware build; `m2m-rom/framework-overrides/` = fixed copies of framework `M2M/rom/` files). Capital CORE because the framework's `#include "../../CORE/..."` depends on it |
| `rtl/` | the Verilog: `nd120_mega65_machine.v`, `nd120_console_mega65.v`, `m65_keys_to_ps2.v`, `nd_storage_mega65_devices.v`, `nd_storage_vdrives.v`, `nd_avalon_port.v` |
| `sim/` | one bench per file + `vdrives_model.v`, `lint_machine.sh`; `make all` runs them; registered in `Verilog/tests/run_all_tests.sh` |
| `build.tcl`, `Makefile` | `make toolchain` once, `make all BOARD=r3|r4|r5|r6` -> `.bit` + `.cor` under `build/<board>/` |
| `../QUICKSTART-mega65.md` | what goes to a tester |
| `tools/` | gitignored; `coretool` lands here |

**Isolation rule (Ronny, 27-AUG):** everything for this port lives under
`fpga/mega65/`. The one shared-RTL change: `Verilog/Terminals/` gained
`hblank`/`vblank` outputs (additive; the framework needs the two halves of
`de`).
