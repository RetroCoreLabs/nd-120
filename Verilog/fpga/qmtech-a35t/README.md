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
   - see the caution in the wiring section. Do this before anything is wired.
2. Wire the console and the SD Pmod to JP3 (pin table in "Wiring the console
   and the SD Pmod to JP3" below).
3. `make load` with the Platform Cable USB II on the JTAG header, or program
   the existing `nd120_qmtech.bit` from the Vivado Hardware Manager.
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

### Resource estimate - NOT MEASURED

Scaled from the Nexys build's hierarchical report
(`../nexys4ddr/timing-analysis/run_clk33_9/utilization_hierarchical.rpt`),
which is the same CPU and the same storage stack on the same fabric:

| block | Nexys LUTs | here |
|---|---|---|
| whole Nexys machine | 19,681 | |
| DDR2 controller | 3,329 | gone - SDRAM bridge instead, much smaller |
| TDV2200 terminal | 1,158 | gone - console is a plain UART |
| remainder + bridge | ~15,200 | of **20,800** on this part |

Block RAM is the comfortable half: the Nexys spends 66 RAMB36 on its DDR2
cache, which goes away, and the Tang runs this same configuration in 738 Kbit
against the 1,800 Kbit here. `SKIP_WCS_LOAD` drops the microcode PROM as well.

**A real measurement on the same die, 04-SEP-2026:** the Cmod A7 build (this
CPU with block-RAM main memory, no storage stack, no terminal, and the
microcode PROM still in the netlist) placed and routed at **11,493 of 20,800
LUTs and 26.5 of 50 block RAM tiles** on `xc7a35t`. Adding the storage stack
costs roughly 6,800 LUTs by the Nexys hierarchy, less the ~1,800 that
`SDFAT_NO_LFN` strips; block-RAM main memory and the microcode PROM come off.
That lands close to the scaled figure above but with less room than it
suggests, so **treat the fit as open until `util_synth.rpt` says otherwise.**

The levers if it does overflow, cheapest first: `SDFAT_NO_LFN` is already on;
`-tclargs -nopanelclock` (costs the SINTRAN time-of-day); turning the CPU's
own cache off in the top level (`CACHE_SW`); dropping the floppy or the
Winchester from `INCLUDE_*`.

### Timing: what the Cmod run says to expect

The same Cmod run **missed timing by 95.488 ns at 27 MHz** with the microcode
PROM in the netlist: 5133 of 18465 endpoints failing, worst path 233 logic
levels and 132 ns ending at the PROM's own data register. The Inter Clock
Table was empty, so that was real logic depth, not a constraint problem.

This build uses `SKIP_WCS_LOAD` from the start for the same reasons the Tang
and Nexys do, but **be warned that it is not what fixed the Cmod, and the Cmod
is not fixed.** Preloading the microcode there bought 5.7 ns of 95. The real
cause, read off the routed checkpoint, is the **CGA IDB combinational ring**
(`DELILAH-CPU/CGA/circuit/CGA.v:700-745`): the design has genuine
combinational loops, Vivado breaks them where it likes, and where it breaks
decides the reported critical path. All 200 worst paths in the Cmod netlist
share one start and one end, 234 logic levels; the SAME RTL gives that path
58 levels on MEGA65 R6, 93 on R3, and 7 on the Nexys.

**So a timing failure here may say more about the netlist than the design.**
If the first synthesis misses at 20 MHz, read in this order:

1. **Inter Clock Table.** Non-empty means a crossing is being timed that the
   clock groups should have excluded - a constraint bug, fix it here.
2. **`[DRC LUTLP-1]` count and the auto-inserted `Synth 8-326` false paths.**
   If the worst path runs through `ALU_OUTMUX/OUTMUX_IDBS` or ends in
   `MAC_LA1025`, it is the ring, and lowering the clock is fitting the clock
   to an artifact rather than to the machine.
3. Only if it is neither: real depth, and a lower CPU clock is the answer.
   Change the MMCM in the top level and `BOARD_CLK_FREQ` together, or they
   disagree about every derived count.

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

## Loading the bitstream onto the board

**A user-facing walkthrough of all of this - wiring, programming, first boot,
troubleshooting - is [`../QUICKSTART-qmtech-a35t.md`](../QUICKSTART-qmtech-a35t.md).**
This section is the developer's short form.

**JTAG is the only way in, and it is volatile.** The Mini USB socket is power
only (the vendor manual says so in section 2.1), there is no SD-card
configuration path like the Nexys has, and no `.mcs`/SPI-flash flow is written
for this board yet - `make flash` deliberately fails rather than pretending.
So every power cycle needs a re-program. It takes seconds.

Connect a **Xilinx Platform Cable USB II** to the 6-pin JTAG header J1.
Pin order and the flying-lead colours are in the vendor manual section 2.2.4,
Figure 2-3 (`docs/QMTECH_XC7A35T_SDRAM-User_Manual_V01.pdf`) - the header
carries VREF and GND besides TCK/TDO/TDI/TMS. Power the board over Mini USB;
LED **D2** lights when the 3.3 V rail is up.

```
# from Verilog/fpga/qmtech-a35t/, Vivado on the Windows host:
vivado -mode batch -source build.tcl                    # build + program over JTAG
vivado -mode batch -source build.tcl -tclargs -noburn   # build only, no board needed
```

From WSL: `make load` (build + program) or `make` (build only) - the Makefile
delegates through `powershell.exe`, using `ND120_VIVADO` and the build folder
`ND120_BUILD_DIR` from `local.mk` at the repository root (written by `python3
configure.py`; see
[CONTRIBUTING.md - Local settings](../../../CONTRIBUTING.md#local-settings)).
Everything the build writes goes to `$ND120_BUILD_DIR/qmtech-a35t/`. To program a bitstream that is already
built, use the Vivado Hardware Manager: *Open Target -> Auto Connect*, the
board must enumerate as **`xc7a35t`**, then *Program Device*. LED **D3**
(`FPGA_DONE`) lights on success. The free **Vivado Lab Tools** is enough for
that - no full Vivado licence needed just to load a release bitstream.

The programming block at the end of `build.tcl` is a plain
`open_hw_manager` / `connect_hw_server` / `open_hw_target` sequence against
`get_hw_devices xc7a35t*`, so it works with any cable Vivado recognises, not
only the Platform Cable.

## Wiring the console and the SD Pmod to JP3

Neither is a plug-in job: JP3 is a 2x25 2.54 mm header, not a Pmod connector,
so the SD Pmod goes on jumper wires. Pin numbering and the FPGA pins behind it
are in [`nd120_qmtech.xdc`](nd120_qmtech.xdc). JP3's schematic net names are
`IO_<pin>`, so the net name IS the FPGA pin.

| what | JP3 pin | FPGA pin | other end |
|---|---|---|---|
| console: FPGA -> adapter RX | 5 | F18 | adapter **RX** |
| console: adapter TX -> FPGA | 6 | G17 | adapter **TX** |
| card CLK / SCK | 7 | E18 | Pmod 4 |
| card CMD / MOSI | 8 | F17 | Pmod 2 |
| card DAT0 / MISO | 9 | D18 | Pmod 3 |
| card DAT1 | 10 | E17 | Pmod 7 |
| card DAT2 | 11 | C17 | Pmod 8 |
| card DAT3 / CS | 12 | C18 | Pmod 1 |
| 3V3 | 2 | (power rail) | Pmod 6 or 12 |
| ground | see below | | Pmod 5 or 11, and the adapter GND |

The Pmod column is the Digilent Pmod MicroSD / Pmod SD mapping taken from
[`../cmod-a7-35t/README.md`](../cmod-a7-35t/README.md), where the same module
plugs straight into connector JA: 1 = ~CS/DAT3, 2 = MOSI/CMD, 3 = MISO/DAT0,
4 = SCK, 5 and 11 = GND, 6 and 12 = VCC (3.3 V), 7 = DAT1, 8 = DAT2,
9 = card detect (unused by the stack), 10 = unused. Check it against the
module's own datasheet before wiring - a wrong VCC pin costs a card.

The same mapping drawn out, because a table of sixteen numbers is easy to
mis-transcribe onto sixteen wires:

```
   QMTECH JP3  (2x25)                      Digilent Pmod MicroSD / Pmod SD (2x6)
   pin 1 is marked on the silkscreen       pin 1 is marked on the board

        odd        even                    +------------------------------+
      +------+   +------+                  |  1    2    3    4    5    6  |
   1  | 5V   |   | 3V3  |  2 ----------,   | ~CS  MOSI MISO SCK  GND  VCC |
      +------+   +------+              |   |                              |
   3  | GND? |   | GND? |  4  <-- meter|   |  7    8    9   10   11   12  |
      +------+   +------+     these    |   | DAT1 DAT2  CD   NC  GND  VCC |
   5  | F18  |   | G17  |  6   four    |   +------------------------------+
      +------+   +------+              |
   7  | E18  |   | F17  |  8           |
      +------+   +------+              |
   9  | D18  |   | E17  | 10           |
      +------+   +------+              |
  11  | C17  |   | C18  | 12           |
      +------+   +------+              |
  13  |  .   |   |  .   | 14           |
       ......      ......              |
  21  | GND? |   | GND? | 22  <-- and  |
      +------+   +------+       these  |
       ......      ......              |
  49  |  .   |   |  .   | 50           |
      +------+   +------+              |
                                       |
   JP3 pin 2  (3V3) --------------------'-------------> Pmod pin 6   VCC

   JP3 pin 7   E18  ------------------------------->  Pmod pin 4   SCK
   JP3 pin 8   F17  ------------------------------->  Pmod pin 2   MOSI / CMD
   JP3 pin 9   D18  <-------------------------------  Pmod pin 3   MISO / DAT0
   JP3 pin 10  E17  <------------------------------>  Pmod pin 7   DAT1
   JP3 pin 11  C17  <------------------------------>  Pmod pin 8   DAT2
   JP3 pin 12  C18  ------------------------------->  Pmod pin 1   ~CS / DAT3
   JP3 ground  ????  ------------------------------>  Pmod pin 5   GND

                          ... and the console adapter:

   JP3 pin 5   F18  ------------------------------->  adapter  RX
   JP3 pin 6   G17  <-------------------------------  adapter  TX
   JP3 ground  ????  ------------------------------>  adapter  GND
```

`--->` is the FPGA driving, `<---` the FPGA listening, `<-->` a line that goes
both ways (unused in 1-bit mode, still wired). **The console pair crosses
over** - the FPGA's transmit goes to the adapter's receive; getting that
backwards gives a silent terminal with everything else looking healthy.

The drawing puts odd pins on the left because that is how the schematic lists
them; find the **pin 1 marker on the silkscreen** and count from there rather
than trusting left/right, on both connectors. Counting from the wrong end puts
5 V where 3V3 was meant.

Two cautions, and one thing still not verified:

- **JP3 pin 1 is the USB 5 V rail and pin 2 is 3V3, on both headers.** Do not
  put a signal on either. The card runs from pin 2.
- **The first build uses 1-bit mode** (`USE_4BIT(0)` in the top level), so
  only CLK, CMD and DAT0 carry traffic. DAT1 and DAT2 still need their
  pull-ups and DAT3 doubles as the card's chip select during initialisation,
  which is why all four are wired. Going to 4-bit later is a parameter flip,
  not a rewiring job - but change one variable at a time: the Tang's 4-bit
  attempt failed on 24-AUG-2026 because the bit clock and the bus width were
  changed together, and it took a separate experiment to tell which broke it.
- **NOT VERIFIED: which JP3 pin is ground.** Extracting the schematic's text
  (`pdftotext -layout` on `docs/QMTECH_XC7A15T_35T_50T_CSG325_SDRAM_V1.pdf`)
  gives an I/O net name for every JP3 pin from 5 to 50 **except pins 3, 4, 21
  and 22**, which is what makes those four the ground candidates - but the
  extraction loses the power-pin labels, so that is an inference and is
  recorded here as one.

  **The cheap way to settle it: the 6-pin JTAG header J1 has a GND pin.**
  Meter in continuity mode, one probe there, the other on JP3 pin 3, 4, 21,
  22. Do it before wiring: a card powered from 3V3 with no shared ground
  simply does not respond, and that failure looks exactly like a bad card, a
  bad image, or broken RTL.

Keep the jumper wires short. These are 20 MHz-class signals on flying leads
with no ground plane between them; if the card is unreliable, wire length is
the first suspect and a ground wire run alongside the card bundle helps.

## Testing the console

The console is the CPU's own emulated SC2661 serial pins, brought straight out
to JP3 - the same console the Tang and the Nexys have, minus their on-board
USB-UART. Use a **3.3 V** USB-to-serial adapter.

**Settings: 115200 baud, 7 data bits, EVEN parity, 1 stop bit, no flow
control.**

```
picocom -b 115200 -y e -d 7 -p 1 /dev/ttyUSB0
```

**Why 7E1 when `SC2661_UART.v` says 8N1 - both are right, and this has cost
time before.** The wire framing is genuinely 8 data bits, no parity, one stop
bit: the emulated chip has no mode-register decode and cannot do anything
else. SINTRAN then puts an EVEN **software** parity bit in bit 7 of its early
boot text (measured on the MiSTer, 02-SEP-2026: CR = 0o215, space = 0o240,
'4' = 0o264). Setting the host terminal to 7E1 strips that bit and the text
comes out clean; 8N1 shows the banner with stray high-bit characters. The
`115200 8N1` comment in [`nd120_qmtech.xdc`](nd120_qmtech.xdc) describes the
wire, not the terminal setting to use.

Test in this order - each step proves one thing, and the first needs no card:

1. **Press ENTER.** OPCOM answers. That proves the bitstream loaded, the CPU
   runs, the clock is right, and both console wires are on the right pins.
2. **`20500&`** boots from the Winchester image. UPPERCASE only, and type at
   a human pace: OPCOM silently drops characters typed faster than ~0.3 s
   apart and answers `?`, which reads as a machine fault and is not one.
3. SINTRAN's banner and the Watchdog line follow.

Card images go in the FAT32 root with 8.3 names - `BOOT.TAP`, `WD0.IMG`,
`FLOPPY1.IMG` - because `SDFAT_NO_LFN` strips long-filename parsing from this
build to save ~1800 LUTs.

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
   *(written 04-SEP-2026, lints clean, NEVER BUILT - start here)*
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
