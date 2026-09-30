# Bitstream release plan

Decided 26-AUG-2026 (Ronny): GitHub Releases carry ready-built bitstreams so
nobody has to install Vivado or Gowin EDA to run the ND-120. Binaries never
enter git history. The disc image is NOT distributed - instructions only.
Every release file runs the console at 115200 7E1 (Ronny, 26-AUG); filenames
carry board + clock + baud; release notes carry each artifact's source commit
and timing/silicon verdict, and link the quickstarts.

Release 1 (tag `bitstreams-2026-08`, four Nexys/Tang files + `SHA256SUMS`) is
published; its record is the release body on GitHub. Release 2 (tag
`bitstreams-2026-09`) is live and its body is
[`RELEASE-NOTES-release2.md`](RELEASE-NOTES-release2.md) - that file owns the
artifact table and the SHA-256 list.

## Staging (scripted, not hand-typed)

The canonical download names (`board_clock_baud`) live in
`fpga/release-manifest.txt`; `fpga/stage-release.sh` copies a build output into
`fpga/release-staging/` (gitignored) under its release name and regenerates
`SHA256SUMS`. Every board's build tool emits a generic name
(`nd120_nexys4ddr.bit`, `nd120_mega65_r6.cor`, ...) - the clock/baud name is
put on here, at staging, for all boards the same way. Build a config, then run
`./stage-release.sh <release-name>` (`--list` prints the valid names). This
replaces the hand-rename that once shipped a MEGA65 `.cor` named for a build it
was not.

## Release 2 - still open (checked against the release notes 28-SEP-2026)

- `nd120_nexys4ddr_33MHz_115200.bit` - REFRESH with the embedded box font,
  the Left-arrow fix and the cache ON; build 30 boots and both are confirmed
  on hardware. Re-verify, stage, attach.
- `nd120_tang20k_fast20_20MHz_115200.fs` - REFRESH with the embedded font.
  Build, verify, stage, attach.
- Then regenerate and re-upload `SHA256SUMS` (never on its own).

Rules that still apply: a row is attached only when BUILT and
SILICON-VERIFIED (glyphs render, arrow keys work on the real board). The
exception (Ronny, 02-SEP-2026) is a board that is not on this desk - the
MEGA65 cores and the QMTECH `.bit` go out labelled "not yet run" and the
quickstart tells the first testers what to report.

## How users load them

**Nexys 4 DDR - the "copy two files" path:**
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

## Open questions (parked)

- Basys3/Cmod A7 artifacts (OPCOM-only demos).
- CI-built releases: not done, by decision. Release bitstreams are built
  locally with the vendor tools and checked on the boards; GitHub Actions
  only runs the tests (the Tang OSS bitstream job was removed 30-SEP-2026).
