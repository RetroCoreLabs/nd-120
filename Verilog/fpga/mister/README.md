# ND-120 MiSTer core (DE10-Nano / MiSTer Pi)

**Full path:** `Verilog/fpga/mister/`

The ND-120 CPU board running on the [MiSTer FPGA](https://mister-devel.github.io/MkDocs_MiSTer/)
platform. SINTRAN III boots on real hardware (DE10-Nano), verified 02-SEP-2026.

![ND-120 MiSTer boot screen at the MOPC `#` monitor](docs/images/boot-screen-mopc.png)

*The core on real hardware (DE10-Nano, 02-SEP-2026), at the `#` MOPC monitor
before SINTRAN is loaded: the four-line power-on banner (core / console / build
stamp / board+clock+memory), the operator panel across the bottom, and the CPU
`G` lamp lit green (self-test passed). Mount a Winchester image in the OSD and
type `&` at `#` to boot SINTRAN.*

For a user quickstart (copy the ready-built `.rbf`, load it, boot SINTRAN) see
**[`../QUICKSTART-mister.md`](../QUICKSTART-mister.md)**. The `docs/` folder is
the developer reference (building, deploy, OSD menu, block/char devices,
debugging, links); `docs/07-links.md` is the full validated link collection.

- **Board:** Terasic DE10-Nano, or the Retro Remake **MiSTer Pi** clone - same
  Intel Cyclone V SoC `5CSEBA6U23I7` (~110K LE fabric + dual-core ARM Cortex-A9
  "HPS" running Linux, 1 GB DDR3 on the HPS side). SDRAM is an add-on module on
  both (128 MB; the MiSTer Pi "Turbo Pack" bundles it). The core is the same
  `.rbf` either way - nothing in this folder is DE10- or Pi-specific.
- **What it is:** the full ND-120 CPU board, with floppy/Winchester/tape images
  served as files from the Linux (HPS) side over the MiSTer `hps_io`
  block-device protocol, the console on the machine's own screen and keyboard
  (a TDV2200 terminal), and microcode uploaded from the HPS at core load.

## Status (02-SEP-2026)

**SINTRAN III boots on real hardware (DE10-Nano).** The whole ND-120 machine
is in the build and running on silicon: it comes up at the `#` MOPC monitor
(the screenshot above), and with a Winchester image mounted in the OSD, `&`
boots SINTRAN. Verified this day on the board.

Shipping configuration of that build (stamp `e5bdea5+`):

| Item | Value |
|---|---|
| CPU clock | 20 MHz (PLL output) |
| Main memory | 4 MB (2M words) in the DE10-Nano SDRAM module, WCS in block RAM |
| Cache | off |
| Console | TDV2200, on the MiSTer's own screen + keyboard; also on the HPS `/dev/ttyS1` at 115200 7E1 (7 data bits, even parity, 1 stop bit) |
| Storage | floppy 0/1, Winchester 0/1, paper tape - mounted from the OSD |
| `output_files/nd120.rbf` | 3,173,376 bytes |

Confirmed working on the board: boot to OPCOM, SINTRAN boot from a mounted
Winchester, CPU self-test (green `G` lamp), the TDV2200 box-drawing font, and
the keyboard. This `.rbf` is the hardware-verified MiSTer artifact in
Release 2 (`../RELEASE-NOTES-release2.md`).

## Build

Quartus Prime Lite **17.0.2** exactly - MiSTer standardizes on it; newer
Quartus breaks the project files and buys nothing on Cyclone V. Nothing needs
installing on the host: the community image `raetro/quartus:17.0`
(<https://github.com/raetro/sdk-docker-fpga>) carries that version.

```bash
# from Verilog/fpga/mister/, in WSL (needs the docker daemon running)
make check     # is docker up, is the image pulled, is the project intact
make build     # font + microcode + banner, then -> output_files/nd120.rbf
make load      # scp the .rbf to the MiSTer  (MISTER=root@... to override)
```

The Quartus GUI is needed for **adding** PLL output clocks (that changes the
port list) and for SignalTap. It is NOT needed to change a PLL *frequency* -
that is a string parameter in the PLL IP under `rtl/pll/` which altera_pll
turns into counter settings at synthesis.

Deploy detail (scp + hot-load over `/dev/MiSTer_cmd`, JTAG, SD-card folders) is
in [docs/03-deploy-and-test.md](docs/03-deploy-and-test.md); the user-facing
copy-and-boot steps are in [`../QUICKSTART-mister.md`](../QUICKSTART-mister.md).

**Framework cost, for reference** (measured 27-AUG-2026 from the bare template,
before any ND-120 RTL - the floor every figure sits on):

| Resource | Framework alone | Device |
|---|---|---|
| ALMs | 7,232 | 41,910 (17%) |
| Block RAM | 59 | 553 |
| DSP | 33 | 112 |
| PLLs | 3 | 6 |

**Licence note (decided 27-AUG-2026, Ronny):** this repo is MIT; the MiSTer
framework in `sys/` is **GPL-2.0** (`LICENSE-MiSTer-framework-GPLv2`), and every
MiSTer core must ship `sys/` as-is, so the two licences sit in one repo. That is
accepted for now - it keeps the work in one place. Standard MiSTer practice is
one repo per core, so **if this core is ever released standalone, split it out
then.** The framework in `sys/` is copied as-is from Template_MiSTer and must
**never be edited** - framework updates erase changes.

## Reference cores

- [PDP2011_MiSTer](https://github.com/MiSTer-Enhanced/PDP2011_MiSTer) - a
  maintained MiSTer core of a 1970s minicomputer with disk images, a serial
  console AND a built-in VT100/VT105 terminal, switched by an OSD bit. The
  closest thing to what we built; dissected in
  [docs/05-devices-block-char.md](docs/05-devices-block-char.md). **Its
  terminal files are non-free (personal/non-commercial only) - reference only,
  never vendored.** Our TDV2200 terminal was re-implemented clean-room, shared
  with the MEGA65 port.
- ao486 - the DDR3 main-memory pattern.
- Template: <https://github.com/MiSTer-devel/Template_MiSTer>
- emu module: <https://mister-devel.github.io/MkDocs_MiSTer/developer/emu/>

## Bring-up history

The port was brought up in stages on Ronny's call (28-AUG-2026): this board
was made the priority because it sits on his desk, so a bad bitstream costs
minutes rather than the days a remote board (MEGA65) would cost, and because
its SDRAM add-on is ordinary SDR SDRAM on FPGA pins - the same interface shape
as the MEGA65's, so the memory backend (where the silicon-only bugs live) was
debugged here first and the MEGA65 inherits a path that has met real silicon.

The first build was the terminal console alone with no ND-120 in it, so a black
screen had one possible cause at a time; the full machine followed. That whole
sequence is done - SINTRAN boots on silicon (02-SEP-2026, `HISTORY.md`). The
WCS read-latency fix that made the CPU run is written up in
`Verilog/docs/mister-microcode-loop.md`; the other bring-up fixes are recorded
only in git history.
