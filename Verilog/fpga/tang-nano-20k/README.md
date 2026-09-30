# Tang Nano 20K (Gowin GW2AR-18) FPGA target

**Full path:** `Verilog/fpga/tang-nano-20k/`

> **Status (02-SEP-2026): SINTRAN III BOOTS ON REAL SILICON.** The Tang Nano
> 20K was the FIRST board to boot SINTRAN (24-AUG-2026) and is a working
> machine you log into. `fast20` runs it at **20.25 MHz, 115200 7E1 console,
> timing-clean (TNS 0)**; 6.75 MHz is the long-validated safe speed and `mid`
> (13.5 MHz) also closes. Main memory is 4 MB of the embedded SDRAM (packed
> 16-bit, `ND_SDRAM_PACK16`); the SD/FAT storage stack is proven on hardware.
> From the Winchester image on the SD card it reaches the SINTRAN banner in
> **29.4 s** from cold; login, `LIST-FILES` and the S3 program work (S3 cold
> start 13.2 s). `fast20` is a Gowin EDA build only - the OSS `Makefile`
> offers `slow`, `crawl` and `full`.
> The old page-fault / silicon-hang / level-14 livelock / bank-decode
> campaigns are all RESOLVED - that is why it boots. Details below.

Gowin build/flow for the Sipeed **Tang Nano 20K**. This is the **primary FPGA
target** going forward - chosen for faster synthesis than Vivado, a Linux-native
open-source toolchain option, and 8 MB of SDRAM that lets the FPGA run the full
memory config like the simulator. (The pre-port analysis and staged plan,
`Verilog/docs/tang-nano-20k-port.md`, is finished and was deleted 28-SEP-2026;
git history keeps it.)

## Bring-up: getting the board talking (do this first)

Every session starts here. The whole USB dance is already scripted - it does
not need to be done by hand, and doing it by hand is how most of the wasted
time on this board has been spent.

```bash
cd Verilog/fpga/tang-nano-20k
make usb            # find the Tang on the Windows host, attach it to WSL,
                    # open the raw USB node AND /dev/ttyUSB* permissions
make flash-gowin    # program the current bitstream
```

After `make usb` you have:

| Device | Use |
|--------|-----|
| `/dev/ttyUSB0` | JTAG side (openFPGALoader) |
| `/dev/ttyUSB1` | OPCOM console, **115200 7E1** |

**Reflashing reboots the design - no power cycle needed.** Measured
09-AUG-2026: `make flash-gowin` restarts the ND-120 and the console comes back
to the `#` prompt on its own. So a build/flash/test cycle can run unattended.

**A real power cycle is different.** Pulling power detaches the device from
WSL and the host busid CHANGES (seen 3-3, then 2-4, then 5-2 on different
days). After a power cycle, run `make usb` again - never assume the old busid.

### When it will not talk

| Symptom | Cause | Fix |
|---------|-------|-----|
| `unable to open ftdi device: -4 (usb_open() failed)` | the raw USB node's permissions reset when the device re-enumerated | `make usb`, or `sudo chmod 666 $(lsusb -d 0403:6010 \| sed -E 's#Bus ([0-9]+) Device ([0-9]+).*#/dev/bus/usb/\1/\2#')` |
| `unable to open ftdi device: -3 (device not found)` | not attached to WSL at all | `make usb` |
| `cannot open /dev/ttyUSB1: No such file or directory` | attached, but `ftdi_sio` has not created the serial nodes | `make usb` |
| `openFPGALoader: command not found` | running the command on the Windows side instead of inside WSL | run it from WSL |

### Driving the console

OPCOM is picky and the rules are not guessable:

- **UPPERCASE only.**
- **~0.30 s between characters.** At 0.12 s characters are dropped silently in
  the middle of a number and OPCOM answers `?` - which looks like a machine
  fault and is not one.
- **115200 7E1** on `/dev/ttyUSB1`. Since 26-AUG-2026 `UART_BAUD_RATE` is
  115200 for EVERY variant (`src/tang20k_defines.v:554`, unconditional) -
  scripts written before that opened 9600 and must be updated.

Use the committed driver rather than writing another one:

```bash
python3 ../../tools/ndconsole.py --seconds 90 --out run.log '400$'
```

Command reference: https://nd110.hackercorp.no/Terminal; boot commands in
`NorskData-Doc/OPCOM-Boot-Reference.md`.

## Board / device

**Hardware reference:** [Sipeed wiki - Tang Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html)
(datasheets/schematics: [dl.sipeed.com](https://dl.sipeed.com/shareURL/TANG/Nano_20K/),
official examples: [sipeed/TangNano-20K-example](https://github.com/sipeed/TangNano-20K-example)).

| Item | Value |
|------|-------|
| Board | Sipeed Tang Nano 20K (22.55 mm x 54.04 mm) |
| FPGA | Gowin **`GW2AR-LV18QN88C8/I7`** (GW2AR-18, QN88) |
| Logic | 20,736 LUT4, 15,552 FF, 48 18x18 multipliers, 8 I/O banks |
| Block RAM (BSRAM) | **828 Kbit** (46 blocks) + 41,472 bit shadow SRAM |
| Big RAM | **8 MB SDRAM** (64 Mbit, 32-bit SDR, embedded in the GW2AR package; no package pins - see sdram-test/) |
| Config flash | 64 Mbit |
| Clock | 27 MHz crystal + MS5351 clock chip (3 extra clocks, BL616-controlled), 2 PLLs (use a Gowin `rPLL` for the CPU clock) |
| Programmer | BL616 onboard USB (JTAG + USB-UART + USB-SPI + MS5351 control); openFPGALoader-compatible; enumerates as one USB serial port (COM5 on Ronny's machine) |
| Peripherals | HDMI, 40-pin RGB LCD connector, TF-card slot, MAX98357A audio amp |
| UI | 6 LEDs (active low, pins 15-20), 1 WS2812 RGB LED, 2 buttons (S1 = pin 88, S2 = pin 87) |

**Factory firmware:** the flash ships with a **LiteX SoC** (VexRiscv_Min @ 48 MHz,
from the `litex/` folder of the TangNano-20K-example repo; prebuilt
`litex/tang_nano_20k_litex.fs`). Its BIOS talks at **115200** baud and has
`mem_test` / `mem_speed` / `sdram_test` commands - an independent check that the
SDRAM hardware works. Its boot report confirms the SDRAM at **48 MHz CL-2** with a
clean 2 MB memtest, mapped at `0x40000000` (8 MB). Loading a bitstream into SRAM
(openFPGALoader without `-f`) leaves it intact; flashing replaces it (restore with
`openFPGALoader -b tangnano20k -f .../litex/tang_nano_20k_litex.fs`).

### vs Basys3
Fewer LUTs (20,736 LUT4 vs 33,280 LUT6) and less BSRAM (828 vs ~1,800 Kbit), but
adds 8 MB SDRAM and a much faster, Linux-friendly toolchain. **Fit is the top
risk** (see [Memory architecture](#memory-architecture)).

## Toolchain (two options)

### Option 1 - Gowin EDA (authoritative)
`gw_sh` (Tcl, scriptable, driven by `gowin_build.ps1`) or the GUI, using
`nd120_tang20k.gprj`. Uses a Synplify-based synth that tolerates the design's TTL-style
flip-flops (clock + async preset + async clear). Has **GAO** (Gowin Analyzer
Oscilloscope), the on-chip logic analyzer = Vivado ILA equivalent. This is the
reliable path to a real bitstream today.

### Option 2 - OSS flow (Linux-native, WSL)
`yosys synth_gowin` -> `nextpnr-himbaechel --device GW2AR-LV18QN88C8/I7` ->
`gowin_pack` -> `openFPGALoader`. Runs entirely on WSL/Linux (no Windows context
switch).

**Install (oss-cad-suite - the whole chain in one prebuilt bundle, no sudo):**
```bash
cd ~
# resolve the latest linux-x64 tarball via the GitHub API, then extract
URL=$(curl -s https://api.github.com/repos/YosysHQ/oss-cad-suite-build/releases/latest \
  | grep -oE '"browser_download_url":[^,]*linux-x64[^"]*\.tgz' | grep -oE 'https://[^"]*')
curl -L -o oss-cad-suite.tgz "$URL"
tar xzf oss-cad-suite.tgz            # -> ~/oss-cad-suite/

# activate in each shell that uses the tools:
source ~/oss-cad-suite/environment
yosys --version                       # expect 0.4x+ (not the distro's 0.9)
which nextpnr-himbaechel gowin_pack openFPGALoader
```
(Lighter alternative for a yosys-only fit check: `pip install yowasp-yosys`.)

The full CPU built with this flow on 12-JUL-2026, but it no longer fits: see
[Two build flows](#two-build-flows) below. Use Gowin EDA for a bitstream.

**OSS flow + embedded SDRAM:** nextpnr does **not** auto-connect the on-package
SDRAM the way Gowin EDA does with the magic `O_sdram_*`/`IO_sdram_dq` port names -
they must be pinned explicitly to internal pseudo-pins (`IOL13A` etc.). The pin
list (from [Seyviour/sdram-tang-nano-20k-os-example](https://github.com/Seyviour/sdram-tang-nano-20k-os-example))
is vendored at `sdram-test/src/sdram_pins_oss.cst` and must be kept **out** of
the Gowin EDA constraints.

## Two build flows

Everything runs from `Verilog/fpga/tang-nano-20k/`. Both flows compile the
same ordered file list parsed out of `nd120_tang20k.gprj`, with
`src/tang20k_defines.v` first, so every `` `define `` comes from one place (yosys
keeps defines across the files of one `read_verilog`, like Gowin's ordered
compilation unit). The clock variant is chosen without editing a file:
the OSS Makefile passes `-DTANG_VARIANT_*`; `gowin_build.ps1 -Variant ...`
writes `build/tang20k_variant.v` as the first project file on every build.
No variant define = `slow`.

| | Gowin EDA | OSS CAD Suite |
|---|---|---|
| Runs on | Windows host (`gw_sh`) | WSL / Linux (`~/oss-cad-suite`, override `OSS_CAD=`) |
| Build | `.\gowin_build.ps1 [-Variant slow\|crawl\|mid\|full\|fast20]` or `make gowin` | `make [VARIANT=slow\|crawl\|full]` (no mid/fast20) |
| Bitstream | `build/nd120_tang20k_build/impl/pnr/nd120_tang20k_build.fs` | `build/nd120_tang20k_oss-<variant>.fs` |
| Load / flash | `make load-gowin` / `make flash-gowin` | `make load` / `make flash` |
| Netlist gates | EX3988 empty-WCS check in the ps1 | `make check` (IO_sdram_dq tristate + latch census; also in CI) |

What the OSS flow needed (all under `` `ifdef YOSYS ``, other flows untouched):

1. `CPU_PROC_32.v` `registerBlock` selects distributed LUT RAM (yosys treats
   `ram_style="block"` as a hard requirement, and the read port is async).
2. `Shared/ndlib/SCAN_WITH_SET_N_EN.v` powers up to 1: yosys `dfflegalize`
   rejects a power-up value that differs from the async-set value.
3. nextpnr does not auto-connect the SDRAM ports: the Makefile appends
   `sdram-test/src/sdram_pins_oss.cst` to the board .cst into `build/oss.cst`.
4. The WCS preload hex files resolve against the yosys working directory;
   `make wcs-hex` refreshes them. A missing file is a hard error.
5. nextpnr takes no SDC: judge timing by the Fmax in `...-pnr.log`.
   First OSS builds (12-JUL-2026): clk_cpu Fmax 47.98 (slow), 48.99 (crawl),
   57.51 MHz (full, 27 MHz needed).
6. On the Windows drive a WSL compile now and then misses a just-written
   file ("No such file or directory"); re-run.

**The full CPU no longer fits with the OSS flow** (measured 28-SEP-2026 with
the oss-cad-suite CI downloads): yosys maps it to 22254-22626 LUT4 against
20736 on the chip (107-109%), so nextpnr cannot place it - older suites sit in
the placer until they are stopped (CI run 33664876050: 2 h), newer ones stop
at once with `no BELs remaining`. No timeout fixes that. Gowin EDA fits the
same design (it maps it differently), so bitstreams come from Gowin.
Synthesis-setting work that brings it to 19790 LUT4 but still does not place
is recorded in `Verilog/TODO.md` (the OSS-fit item). No bitstream is built in
CI.

## Full ND-120 build

The complete ND-120 CPU has a Tang top-level and Gowin project here:

| File | Purpose |
|------|---------|
| `src/ND120_TANG20K_TOP.v` | Board top: instantiates `ND3202D`, ties off the external bus, S1 = Master Clear, OPCOM UART 115200 on the BL616 (pins 69/70), 6 LEDs: block-read/write activity, tape byte served, SD status pair, heartbeat (see the LED table below) |
| `src/tang20k_defines.v` | **Must stay FIRST in the project** - defines `GOWIN`, `TARGET_TANG20K`, `FPGA_FF_MODE`, `SKIP_WCS_LOAD`, `MAIN_RAM_SDRAM`, `BOARD_CLK_FREQ` (per clock variant), `UART_BAUD_RATE=115200` |
| `src/gowin_rpll_27_54.v` | One rPLL: 54 MHz (SDRAM ctrl) + 54 MHz shifted (SDRAM chip) + 27 MHz (CPU/bus/OSC) |
| `src/nd120_tang20k.cst` / `.sdc` | Pins (verified 20K pinout); the 27 MHz input clock plus three reasoned `set_false_path` exceptions (see [Clock variants](#clock-variants-and-measured-boot-timings-24-aug-2026), 31-AUG and 01-SEP notes) |
| `nd120_tang20k.gprj` | Gowin GUI project - 247 files, generated from the Verilator dependency list (single source of truth for the tcl too) |
| `gowin_build.tcl` / `gowin_build.ps1` | Scripted build on the Windows host: `.\gowin_build.ps1` copies the 32 WCS preload hex files (`Code/Microcode/wcs/`), runs `gw_sh` from the Gowin EDA install (its path is set in `gowin_build.ps1`) -> `build\impl\pnr\nd120_tang20k_build.fs` |
| `lint/rpll_stub.v` | Lint-only rPLL stub (Verilator elaboration check; not in the Gowin build) |

Build config: microcode is **bitstream-preloaded** (`SKIP_WCS_LOAD`, PROM never
read), main memory is the **8 MB embedded SDRAM** through
[`sdram-bridge/`](sdram-bridge/README.md) (2 banks = 4 MB), CPU clock chosen by
the variant (below; `slow` = 6.75 MHz is the default). The Verilator sim build is
unaffected by the Tang defines.

**Which toolchain builds it:** Gowin EDA. The OSS flow (yosys/nextpnr) built
the full CPU locally on 12-JUL-2026 (all three variants; Fmax in
[Two build flows](#two-build-flows)) but no longer fits it (see there).
Release bitstreams are Gowin EDA builds, made locally and checked on the
board. The Fmax and violation figures in this README are Gowin EDA timing
reports.

## Clock variants and measured boot timings (24-AUG-2026)

Clock variants, selected with `gowin_build.ps1 -Variant
<slow|mid|fast20|full>`. `clk_cpu` is always exactly half of `clk2x`;
slow/mid/full share one 864 MHz VCO, `fast20` uses 648 MHz.

| Variant | CPU | SDRAM | Setup violations | CPU-domain Fmax (Gowin STA) |
|---------|-----|-------|------------------|------------------------------|
| `crawl` | 3.375 MHz | 6.75 MHz | - | - |
| `slow` (default) | 6.75 MHz | 13.5 MHz | **0** | 17.68 MHz |
| `mid` | 13.5 MHz | 27 MHz | **0** | 19.03 MHz |
| `fast20` (26-AUG-2026) | **20.25 MHz** | 40.5 MHz | **0** | **22.932 MHz** (31-AUG; was 20.556) |
| `full` | 27 MHz | 54 MHz | **1667** | 19.55 MHz |

The `slow`/`mid`/`full` Fmax figures above predate the 31-AUG `.sdc` work
and are therefore PESSIMISTIC by an unmeasured amount - they were taken
while the storage crossings were still being analysed as synchronous. Only
the `fast20` row has been re-measured.

**31-AUG-2026: `fast20` margin went from 1.5% to 13.2%.** The CPU-domain
Fmax was never a statement about the CPU. `nd120_tang20k.sdc` was a single
`create_clock` line, so the data buses between `nd_storage`'s card side
(`clk_stor`, the 27 MHz `sys_clk` domain) and its client side (`clk_cpu`,
the PLL's `CLKOUTD`) were analysed as same-edge synchronous paths with a
required time of 0.000 ns. That produced **24 of the 25 worst setup paths
in the build**. Two `set_false_path` lines, measured with the `.sdc` as the
only variable and the source tree hashed identical either side:

| | CPU-domain TNS | failing endpoints |
|---|---|---|
| without the two lines | -260.076 ns | 398 |
| with them | -6.489 ns | 24 |

Together with `aa210eb` taking the MIPS tap off `ALUCLK_EN` (neither fix
alone got there), `fast20` now closes at **TNS 0.000 on all five clocks,
setup AND hold**, CPU Fmax **22.932 MHz** against the 20.250 MHz
constraint. Flashed and confirmed running on the board.

Three things learned doing it, all worth knowing before touching the
`.sdc` again:

- **A WIDER exception set measured WORSE.** Also excepting the synchroniser
  first flops (`*/s_meta*` - `SD-FAT/circuit/nds_sync.v` calls it
  `// first flop (metastability guard)`) and the `s_led_*_stretch` LED
  counter describes the hardware just as correctly, but on an identical
  tree gave **-35.352 ns over 90 endpoints** vs -6.489/24. Excluding a path
  also removes the placer's reason to close it. Pick the exception set on
  measurement, not on how thorough it looks.
- **Gowin silently ignores a constraint that matches nothing** - check
  section 3.8 `Timing Constraints Report` in the `.tr` for `Actived`. Worse,
  a constraint naming a register that did not survive synthesis is a hard
  `ERROR (TA2003)` that aborts the build and leaves the PREVIOUS `.tr` on
  disk, where it reads as a perfectly plausible result. Compare the `.tr`
  `<Created Time>` against the `.sdc` mtime.
- **Do not reach for `set_clock_groups -asynchronous`** between the two
  domains. It clears every violation in one line and excuses every crossing
  nobody has read, including the one somebody adds next month.

### Only simple ratios of the 27 MHz crystal can be signed off (01-SEP-2026)

Measured while looking for a clock above `fast20`. Four ratios, one build
each, RTL and constraints identical - only the PLL dividers changed:

| CPU clock | ratio to crystal | TNS reported | negative paths in the report |
|---|---|---|---|
| 20.25 MHz | **3/4** | **0.000 / 0** | 0 - agrees |
| 27 MHz | **1/1** | -8.572 / 35 | 35, worst -0.839 - agrees |
| 22.5 MHz | 5/6 | -1332 / 1129 | **0** - contradicts |
| 24.75 MHz | 11/12 | -26678 / 2774 | 27, worst -2.806 - contradicts |

At the two SIMPLE ratios the summary TNS and the path tables agree exactly.
At the two awkward ones they contradict each other by two orders of
magnitude - 22.5 MHz claims 1129 failing endpoints while its path table
holds NONE - and the size of the discrepancy tracks the ratio's complexity
(6 edge pairs -> -1332, 12 -> -26678). That is consistent with the tool
enumerating launch/capture edge pairs across the common period while
report_timing collapses to one representative per endpoint, but the
mechanism is INFERRED. What is measured is the correlation.

Constraining every sys_clk <-> CLKOUTD crossing did NOT clear it (24.75 MHz
went from -21909/2629 to -26678/2774 with eight more exceptions applied), so
it is not the storage crossings.

**Consequence: do not ship an intermediate clock.** Not because the silicon
cannot run it - at 24.75 MHz the worst SAME-domain path was only -0.271 ns -
but because the report cannot be trusted to say so, and a bitstream signed
off on a number you cannot trust is the thing this whole exercise was
correcting. The usable rungs are 6.75, 13.5, 20.25 and 27 MHz.

27 MHz remains 0.839 ns short on 13 endpoints, all WCS -> WCS by the
microcode-JUMP and TVEC routes. Those are real; see commit 9dc8507 for why
they must not be constrained away.

Console: **115200 baud 7E1 on every variant** since 27-AUG-2026
(`UART_BAUD_RATE` is unconditional in `src/tang20k_defines.v:554`). The
physical baud is the `UART_BAUD_RATE` build constant alone; the microcode's BAUDV thumbwheel value (8 = 9600) is stored
by the SC2661 emulation but never used for bit timing, proven on the Nexys
and now here. **Silicon 26-AUG-2026: SINTRAN III boots on `fast20`,
banner + Watchdog in ~40 s, clean text on a 115200 7E1 console. Soaked
27-AUG: 4 unattended hours, 8/8 console probes.** All the python console tools
in this directory default to 115200 (`--baud 9600` for pre-27-AUG bitstreams).

### Measured on silicon, SINTRAN III booting from WD0

Cold boot each time (reflash, then `20500&`), driven by `measure_s3.py`.
`banner` = to `SINTRAN III RUNNING`; `watchdog` = to
`ERS/SINTRAN III Watchdog has started`, i.e. ready for login; `S3` = from the
CR that submits `S3` to its first output byte, after `SET-T-T,,93`.

All figures are SECONDS (decimal), not minutes:seconds. `2.4 sec` means two
point four seconds - S3 responds almost immediately at every clock. The
minute:second equivalents are given in brackets for the longer ones.

| CPU clock | banner | watchdog (login ready) | S3 first output |
|-----------|--------|------------------------|-----------------|
| 6.75 MHz  | 168.2 sec (2 min 48) | 539.3 sec (8 min 59) | 3.9 sec |
| 13.5 MHz  | 119.0 sec (1 min 59) | 480.1 sec (8 min 00) | 2.7 sec |
| 27 MHz    | 101.9 sec (1 min 42) | 451.9 sec (7 min 32) | 2.4 sec |

**Boot is NOT CPU-bound.** Four times the clock buys only 1.65x on the banner
and 1.19x on time-to-login. The banner->watchdog segment barely moves at all -
371 s, 361 s, 350 s - so that phase is essentially clock-independent. That is
consistent with it being disc-bound: the SD/storage stack deliberately runs off
the fixed 27 MHz crystal (`clk_stor = sys_clk`) regardless of the CPU clock,
because `sd_file_reader`'s identification divider is only in spec there.

**S3 starts in under 4 seconds at every clock.** A "slow S3 start" is therefore
not S3 being slow - it is almost certainly the machine still being in the long
post-banner phase, before the watchdog line says it is ready. Wait for the
watchdog before concluding anything about S3.

### Which variant to use

`full` (27 MHz) runs SINTRAN, LIST-FILES and S3, and is the fastest measured -
but it does NOT close timing (1667 setup violations against a 19.55 MHz Fmax),
so its margin over temperature and voltage is unquantified. `mid` (13.5 MHz)
closes with zero violations and gives most of the gain: 1.41x on the banner
against `slow`, versus 1.65x for `full`.

The `full` row predates both the 31-AUG storage-crossing exceptions and the
01-SEP WCS -> ACAL exception now in the `.sdc` (its comments give the proof),
so the `full` figure is a floor, not a verdict. `fast20` is the timing-clean
choice.

The debug dumper's baud divisor used to be a fixed `DELAY_FRAMES(1406)` that
was right only for `slow`; fixed 24-AUG-2026, it is now derived from
`BOARD_CLK_FREQ` and `UART_BAUD_RATE` (`src/ND120_TANG20K_TOP.v:1747`).

## LEDs (active low, pins 15-20; map of 07-AUG-2026)

| LED | Meaning |
|---|---|
| `led[0]` | **Storage BLOCK READ** - flashes ~150 ms per floppy/Winchester block read (`FDISK_REQ`/`WDISK_REQ` with WR low), solid under sustained reads |
| `led[1]` | **Storage BLOCK WRITE** - same stretcher, for block writes (WR high) |
| `led[2]` | A tape byte was served - the SD -> TAPE-400 path delivered data (`400$` working) |
| `led[3]` | `sd_status[0]` \ together: `00` = mount never ran, `01` = no card, |
| `led[4]` | `sd_status[1]` / `10` = mount/FAT error, `11` = SD-FAT OK (both lit) |
| `led[5]` | Heartbeat ~0.8 Hz - `clk_cpu` alive at all |

Reading it: `led[4]`+`led[3]` both lit = the whole SD-FAT chain works. After
`400$`, `led[2]` dark = the CPU never got tape bytes. `led[0]`/`led[1]` are
the disc activity lights: one flash per block, a steady glow during a
transfer burst. (Before 07-AUG, `led[0]`/`led[1]` were the bring-up
indicators tape-request-seen / SD-clock-seen; those are retired.)

## Storage build: SD-FAT + floppy + SMD (measured 3-AUG-2026)

The SD-FAT reader, the floppy at 1560 and the SMD disc at 1540 are all in one
bitstream and it places and routes. This is the build to use for disc work.

**Defines** (`src/tang20k_defines.v`, both active):

| Define | Effect |
|---|---|
| `TANG_FLOPPY` | floppy-only base build: `ND_FLOPPY_DMA` at 1560 + `nd_storage` client for `FLOPPY1.IMG`. **Drops the papertape** - `TANG_INC_TAPE` goes to 0, so `400$` is not available in this bitstream. |
| `TANG_SMD` | adds `ND_SMD` at 1540 with its own `ND_DMA_MASTER`, plus `nd_storage_disc_adapter` serving `SMD0.IMG` (client 3, slot 1376 blocks -> image limit 2,818,048 bytes). |

They resolve to `TANG_INC_FLOPPY = 1`, `TANG_INC_SMD = 1`, `TANG_INC_TAPE = 0`
in `src/ND120_TANG20K_TOP.v`, applied both to the core (which devices exist) and
to `nd_storage_devices` (which client the SD-FAT reader serves).

With either define set, the SD-FAT slimming cut `SDFAT_NO_STORAGE_CHECK` is
suppressed automatically - floppy and SMD do random access and writeback, so the
mount-time contiguity checker (`nd_storage_fatchk.v`) must stay in. That cut is
for the tape-only build.

**Measured utilization** (Gowin EDA flow, `VARIANT=slow`, 3-AUG-2026, from
`build/nd120_tang20k_build/impl/pnr/nd120_tang20k_build.rpt.html`):

| Resource | Used | % |
|---|---|---|
| LUT/ALU/ROM16 | 14464 (12955 LUT, 1509 ALU) | - |
| CLS | 9103/10368 | 88% |
| Register | 7579/15915 | 48% |
| - as Latch | 0/15552 | 0% |
| - as FF | 7529/15552 | 49% |
| BSRAM | 34 SP10 SDPB | 96% |
| DSP | 2 MULTALU36X18 | 9% |
| PLL | 1/2 | 50% |

Read those two numbers together: **BSRAM 96% and CLS 88%** is what "everything
fits, with nothing to spare" looks like on this board. The SMD's 1024x16 sector
buffer is the last BSRAM block; dropping `TANG_SMD` alone is the intended escape
hatch if something else needs one. **Register as Latch is 0** - no inferred
latches, which is a standing gate for every build here.

Floppy and SMD fit because both 2 KB sector buffers are synchronous-read (the
old asynchronous read ports could not map to BSRAM).

Build and program (Gowin EDA flow, Windows host):

```
.\gowin_build.ps1 -Variant slow      # or: make gowin VARIANT=slow
make load-gowin                      # SRAM  - gone at power-off
make flash-gowin                     # SPI flash - survives a power cut
```

Power-cycle the board after every loader operation before judging anything on
the console.

Note before flashing rather than loading: this build's SMD write path is live
(full aligned 1024-word blocks only; anything else answers `disk_err`), and a
flashed bitstream comes up on its own at every power-on, so it can write
`SMD0.IMG` on the card without anyone asking.

## Files here (legacy)

| File | Purpose |
|------|---------|
| `ND120_TOP.cst` | **STALE - Tang Nano 9K pinout** (clock pin 52, LEDs 10-16). Superseded by `src/nd120_tang20k.cst`. Kept only until the 9K is ever targeted; do not use for the 20K. |
| [`sdram-test/`](sdram-test/README.md) | **Standalone SDRAM bring-up test** - nand2mario controller + ND-120 UART (9600 8N1) reporting every read/write. Gowin EDA project + OSS Makefile + iverilog testbench. **PASSES on hardware** (2026-07-08, OSS-flow bitstream, **full 8 MB** write+verify OK). |
| [`sdram18-test/`](sdram18-test/) | **Standalone sdram18.v hardware test** - drives the ND-120 18-bit-word controller with the full build's exact 13.5 MHz slow-bring-up clocking (same PLL module). 4-word demo + full 2M-word write/verify over UART. **PASSES on hardware** (2026-07-09, OSS flow) - exonerates the controller; the deposit bug was full-build cross-domain timing (fixed; the handoff is in git history). |
| [`sdram-bridge/`](sdram-bridge/README.md) | **ND-120 sheet-49 SDRAM backend** - `MEM_RAM_49_SDRAM.v` maps the measured ND-120 DRAM protocol onto the SDRAM (2x-clock bridge, self-scheduled refresh, 2 banks = 4 MB). In the booting build (4 MB main memory). Design doc: [`../../docs/nd120-dram-memory.md`](../../docs/nd120-dram-memory.md). |

**Older Gowin EDA project:** `../../ND-120-Gowin/` (`ND-120-Gowin.gprj`). The
build scripts in this folder (`gowin_build.ps1`/`.tcl`, `Makefile`) use
`nd120_tang20k.gprj` instead; whether to delete the older project is an open
decision.

## Memory architecture (the key design point)

BSRAM (828 Kbit) is too small to hold **both** the microcode PROM (~512 Kbit) and
the WCS (~512 Kbit), unlike the Basys3. So:

| Memory | Where on Tang |
|--------|---------------|
| Microcode | **Bitstream-preloaded WCS** via `SKIP_WCS_LOAD` (see `../../docs/skip-wcs-load.md`); no PROM BRAM (never read once load is skipped). |
| Writable Control Store (WCS) | BSRAM (32 blocks) |
| Main memory | **8 MB SDRAM** via the [nand2mario Tang-Nano-20K controller](https://github.com/nand2mario/sdram-tang-nano-20k), through [`sdram-bridge/`](sdram-bridge/README.md) |

**BSRAM is the binding resource on this board** - 96% in the storage build
above. The one reclaim still open (repack the UUA half of the WCS, 8 blocks) is
analysed in [`BSRAM-BUDGET.md`](BSRAM-BUDGET.md), not implemented.

## Resource budget (what uses the GW2AR-18, measured 16-JUL-2026, OSS flow)

- BSRAM: the WCS is 32 of the 46 blocks (32 x IDT6168A_20 4096x4,
  `CPU_CS_WCS_21_22.v`); MMU page table + cache 8, MMU IMS1403 1, and each
  2 KB storage sector buffer 1. Main memory is in SDRAM (0 BSRAM); the CPU
  register file is LUT RAM. Reclaiming 8 WCS blocks: `BSRAM-BUDGET.md` Part 1.
- LUT: the SD-FAT/storage stack roughly doubled the LUT count (42% -> 88%
  on 16-JUL); `sd_file_reader` alone was about 8930 LUTs. By 28-SEP-2026 the
  OSS synthesis of the full CPU needs 107-109% LUT4 and no longer places
  (see "Two build flows"); the Gowin flow still fits. The FAT reader is
  shared by all devices, so another device adapter is cheap (~176 LUTs).
- Levers, with measured or estimated savings: `SDFAT_NO_LFN` (~1800 LUT,
  in use), mount-time contiguity checker (~1177 LUT, retired as a default
  07-AUG-2026), `SDFAT_NO_WRITE` (~1081 LUT, loses write-back),
  `N_CLIENTS` of nd_storage (LUT/CLS relief), WCS repack (-8 BSRAM, not done).
  Dropping FAT32 saves ~0 (the 32-bit cluster path serves FAT16 too).
  Subdirectory traversal does not exist (root only), so there is nothing to cut.

## On-chip debug

- **THE working method: [`TRACE-CAPTURE-GUIDE.md`](TRACE-CAPTURE-GUIDE.md)** -
  512-sample on-chip analyzer in the ND-120 top, dumped over the console UART;
  full build/capture/decode walkthrough. This is
  what cracked the memory-write bug.
- **GAO** (Gowin Analyzer Oscilloscope) - captures internal nets to BSRAM, read
  back over JTAG. But BSRAM is scarce here (WCS uses most of it), so GAO capture
  depth is shallow.
- **Preferred: UART debug streamer** (BSRAM-free) for full-length boot traces;
  fast Gowin roundtrip makes re-flashing to move probes cheap.

## Related docs

- [`TRACE-CAPTURE-GUIDE.md`](TRACE-CAPTURE-GUIDE.md) - on-chip trace capture + analysis how-to (this board).
- `../../docs/skip-wcs-load.md` - preloaded-WCS microcode (needed for the fit).
- `../../docs/build-defines.md` - the board-target define scheme.
- `../../docs/fpga-debug-methodology.md` - shared FPGA debug workflow.
