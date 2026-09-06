# Bitstream release plan

Decided 26-AUG-2026 (Ronny): GitHub Releases carry ready-built bitstreams so
nobody has to install Vivado or Gowin EDA to run the ND-120. Disc image is
NOT distributed - instructions only. Four bitstreams in release 1. The
Nexys SD-card config path gets a hardware verification BEFORE it is
documented as the primary path.

## What ships in release 1

Attached to a GitHub Release on a tagged commit (binaries never enter git
history):

ALL releases run the console at 115200 7E1 (Ronny, 26-AUG) - one terminal
setting for every file, no per-file baud confusion:

| File | Board | CPU clock | Status behind it |
|---|---|---|---|
| `nd120_nexys4ddr_45MHz_115200.bit` | Nexys 4 DDR | 45.45 MHz | **refreshed 27-AUG with the SD power-cycle fix** (WNS +0.064); silicon-verified four ways: JTAG boot, MACL-then-boot, SD-card-config-then-boot, **4-hour soak 8/8 probes** |
| `nd120_nexys4ddr_16MHz_115200.bit` | Nexys 4 DDR | 16.667 MHz | safe build with the SD power-cycle fix; **boot-checked on silicon 27-AUG** |
| `nd120_tang20k_fast20_20MHz_115200.fs` | Tang Nano 20K | 20.25 MHz | boots SINTRAN, timing-clean; **4-hour soak 8/8 probes (27-AUG)** |
| `nd120_tang20k_slow_6.75MHz_115200.fs` | Tang Nano 20K | 6.75 MHz | safe build; **boot-checked on silicon 27-AUG** (Watchdog in 106 s) |
| `SHA256SUMS` | - | - | checksums of the four above |

Filenames still carry board + clock + baud. Release notes state each
artifact's source commit SHA and timing verdict, and link the quickstarts.
Staging area for the artifacts before the GitHub Release:
`fpga/release-staging/` (gitignored).

**Staging is scripted, not hand-typed.** The canonical download names
(`board_clock_baud`) live in `fpga/release-manifest.txt`; `fpga/stage-release.sh`
copies a build output into `release-staging/` under its release name and
regenerates `SHA256SUMS`. Every board's build tool emits a generic name
(`nd120_nexys4ddr.bit`, `nd120_mega65_r6.cor`, ...) - the clock/baud name is
put on here, at staging, for all boards the same way. Build a config, then run
`./stage-release.sh <release-name>` (`--list` prints the valid names). This
replaces the hand-rename that once shipped a MEGA65 `.cor` named for a build it
was not.

## Release 2 - in preparation (02-SEP-2026)

Adds the MiSTer and MEGA65 boards, and REFRESHES the Nexys/Tang binaries to
pick up the terminal work landed 01/02-SEP: the real TDV2200 box-drawing font
(set 2 from RetroCore, embedded in font_rom.v so no board reads a loose hex),
the Left-arrow key fix, and the fourth power-on banner line (board / clock /
cache). Same rule as release 1: 115200 console, filenames carry board + clock,
release notes carry the source commit SHA and the timing/silicon verdict.

Binaries are NOT staged yet - the rows below are placeholders. Each is filled
in only when its binary is BUILT and SILICON-VERIFIED (the box glyphs render
and the arrow keys work on the real board), then dropped into
`fpga/release-staging/`.

| File | Board | Format | CPU clock | Status |
|---|---|---|---|---|
| `nd120_nexys4ddr_33MHz_115200.bit` | Nexys 4 DDR | `.bit` | 33.333 MHz | REFRESH - box font + left arrow + embedded font, cache ON; build 30 boots and both are confirmed on hardware. Re-verify + stage. |
| `nd120_tang20k_fast20_20MHz_115200.fs` | Tang Nano 20K | `.fs` | 20.25 MHz | REFRESH - rebuild with the embedded font; Tang is TDV via the same core. Build + verify. |
| `nd120_mister_<clk>_115200.rbf` | MiSTer (DE10-Nano) | `.rbf` | TBD | NEW - TDV2200 console wired (font page 2 box glyphs + TDV keyboard). Quartus binaries land later today; verify glyphs + keys on hardware, then stage. |
| `nd120_mega65_rev3_13MHz_115200.cor` | MEGA65 R3 / R3A | `.cor` | 13.33 MHz | NEW - **REBUILT 04-SEP-2026 (raw microcode word, RUN/STOP = EXIT), timing-clean (WNS +0.093 / WHS +0.032 ns), stamp `3e1f90c+ 04-Sep-2026 09:46`; NOT silicon-verified - no MEGA65 here.** Whole machine: CPU, 4 MB in the HyperRAM (Nexys cache seam + Avalon port), TDV2200 console on the MEGA65 keyboard/screen, floppy 0/1 + Winchester 0/1 + tape on the framework's virtual drives. Staged, and **uploaded to the live release 05-SEP-2026** replacing the 02-SEP core. |
| `nd120_mega65_r6_20MHz_115200.cor` | MEGA65 R4/R5/R6 | `.cor` | 20 MHz | NEW - **REBUILT 04-SEP-2026 (same sources: raw microcode word, RUN/STOP = EXIT), timing-clean (WNS +0.249 / WHS +0.002 ns), stamp `bc612ad+ 04-Sep-2026 09:25`; NOT silicon-verified.** As above with the 4 MB in the 64 MB SDRAM (the MiSTer sheet-49 bridge). Built for R6; R4/R5 rebuild with `BOARD=r4`/`r5` (same memory, different top). Staged, and **uploaded to the live release 05-SEP-2026** replacing the 02-SEP core. |
| `nd120_qmtech_a35t_20MHz_115200.bit` | QMTECH XC7A35T SDRAM core board | `.bit` | 20 MHz | NEW - **BUILT 04-SEP-2026, timing met (WNS +4.645 ns), 0 errors, 12,619/20,800 LUTs, 22/50 BRAM; NOT silicon-verified - the board has never loaded it.** Whole machine: CPU, 4 MB in the board's 32 MB SDRAM through the sheet-49 bridge in 16-bit mode, SD card + serial console on header JP3, storage uncached. Loading is JTAG-only and volatile (no USB data path, no SD-config, no flash flow). Staged locally under its long name; **deliberately NOT attached to the release** until someone has run it on a board. |
| `SHA256SUMS` | - | - | - | checksums of the above, regenerated when the set is final |

Notes:
- MiSTer binaries are `.rbf` (the DE10-Nano config format); MEGA65 are `.cor`.
- **The QMTECH is the second board in this release that nobody has run**, for
  the same stated reason as the MEGA65 cores: the release is the verification
  channel. It differs in one way worth calling out in the release notes -
  its console and SD card are on **jumper wires to a raw 2x25 header**, not a
  connector, so a first tester has real wiring to do and one fact
  (which JP3 pin is ground) to measure that this project has not measured.
  `QUICKSTART-qmtech-a35t.md` says exactly that and asks for it back.
- MEGA65 ships TWO cores because the hardware revisions differ (R3: HyperRAM
  only; R4/R5/R6: SDRAM) and the flash menu refuses a wrong-model `.cor`.
  Exception to the silicon-verified rule (Ronny, 02-SEP-2026): there is no
  MEGA65 on this desk, so the release IS the verification channel - the
  cores go out labelled "not yet run on a MEGA65" with
  `QUICKSTART-mega65.md` telling the first testers what to report. The
  `.cor` header carries the same build stamp as the on-screen banner.
- The MEGA65 "115200" in the filename is the console UART bridge inside the
  core (7E1 receive, as on the MiSTer); there is no serial port on the
  MEGA65, the console is the machine's own screen and keyboard.
- The font is now EMBEDDED in font_rom.v (generated by make_font.py), so every
  board's binary carries the correct glyphs with nothing to copy per board -
  see the font note in build.tcl / font_rom.v.

## How users load them

**Nexys 4 DDR - the "copy two files" path (pending one verification):**
the board's own config controller loads a `.bit` from a FAT microSD at
power-on (Digilent reference manual, JP1 jumper set to USB/SD). Our design
then uses the same card for the disc image, so ONE card carries both:

1. Format microSD as FAT32; copy the `.bit` and the disc image to the root.
2. Move jumper JP1 to USB/SD (one-time).
3. Insert card, power on, open the terminal. No software installed at all.

VERIFIED 26-AUG-2026 on the board (Ronny): config from the card succeeds
and the SD stack mounts the disc image afterwards - one card carries
both. Two jumpers: JP1 cap to pins 3-4 ("USB/SD") AND JP2 to the SD
side. Fallback path: Vivado Lab Tools or openFPGALoader over USB-JTAG.

**Tang Nano 20K - one command, once:** the SD slot goes to fabric pins,
not to configuration, so there is no SD-config on this board. Instead:

1. Install openFPGALoader (in oss-cad-suite; also `apt install
   openfpgaloader` / `brew install openfpgaloader`).
2. `openFPGALoader -b tangnano20k -f nd120_tang20k_<...>.fs` - the `-f`
   writes onboard SPI flash, so the board boots the ND-120 at every
   power-on from then on, no PC needed.
3. Disc image on the microSD, terminal on the second USB serial port.
   Alternative for Windows-only users: the Gowin Programmer GUI.

**QMTECH XC7A35T - JTAG only, and volatile:** this board has no USB data
path (the Mini USB socket is power only), no SD-card configuration path and
no flash flow, so there is no "copy a file" route at all:

1. Wire the console and an SD Pmod to header JP3 on jumper wires - the board
   has neither an on-board UART nor an SD slot. Pin table in the quickstart.
2. Program `nd120_qmtech_a35t_20MHz_115200.bit` over the 6-pin JTAG header
   with a Xilinx Platform Cable USB II, from the Vivado Hardware Manager or
   the free Vivado Lab Tools.
3. Re-program after every power cycle - the FPGA does not keep it.

**Disc image (both boards):** NOT in the release (Ronny, decision 1).
The quickstarts explain what the machine needs (a Winchester image on the
card's FAT root), point at the ND software preservation community for
images, and at `ndtool` for building/inspecting them. A bitstream without
an image still comes up in OPCOM - the quickstart shows that as the
"it works" smoke test.

## Documents to write

| File | Content |
|---|---|
| `fpga/QUICKSTART-nexys4ddr.md` | **WRITTEN 26-AUG** - both deployment paths (USB volatile/QSPI-persistent + microSD config with an UNVERIFIED banner and the test checklist), terminal settings, OPCOM smoke test, `20500&`, troubleshooting |
| `fpga/QUICKSTART-tang-nano-20k.md` | **WRITTEN 26-AUG** - openFPGALoader install matrix, persistent `-f` flash, WSL usbipd note, second-serial-port console, boot walkthrough, troubleshooting |
| `fpga/QUICKSTART-qmtech-a35t.md` | **WRITTEN 04-SEP** - JTAG-only volatile loading (Platform Cable USB II, Hardware Manager or Lab Tools), the JP3 wiring table for the console and an SD Pmod, the meter check for the unverified ground pin, 7E1 console test, first-boot checklist, troubleshooting, and what a first tester should report back |
| Release-notes template | **WRITTEN 02-SEP** as `fpga/RELEASE-NOTES-release2.md` (Release 2, tag `bitstreams-2026-09`): source commit `b09302e`, artifact table with the MEGA65 rows filled + SHA-256, the "not yet run on a MEGA65" caveat, quickstart links, changed-since-Release-1 list. Nexys/Tang/MiSTer rows marked pending until built. |

Terminal settings table (both quickstarts): 7 data bits, EVEN parity,
1 stop bit, no flow control; baud from the filename. Example lines for
picocom and PuTTY.

## Work list, in order

1. DONE 26-AUG (Ronny, on the board): SD-config verified working - JP1
   cap on pins 3-4 (far right, "USB/SD"; factory default is 1-2) AND JP2
   on the SD side; FPGA configures from the card and the ND-120 boots
   from the same card. Quickstart Path 2 updated with the verified steps.
2. Rebuild the four release bitstreams from ONE tagged commit (the safe
   Nexys build needs a rebuild at clk 16 - the current .bit on disk is
   45.45 MHz; the Tang slow build likewise) and record each build's own
   timing verdict.
3. Write the two quickstarts, walk them once as a user would.
4. Tag, create the GitHub Release, attach files + SHA256SUMS, paste notes.
5. Add a "Releases" pointer to the main `README.md` and `fpga/README.md`.

## Open questions (parked, not blocking release 1)

- Release cadence/naming: date tag chosen at step 4: `bitstreams-2026-08`.
- Basys3/Cmod A7 artifacts (OPCOM-only demos) - maybe release 2.
- CI-built releases: blocked (Vivado size/licence in CI; OSS Tang flow
  still blocked by the comb loops). Revisit after the IDB ring cut.
