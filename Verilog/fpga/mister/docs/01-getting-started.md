# Getting Started (hardware, MiSTer install, dev environment)

Setup reference: a working MiSTer you can ssh into, and a dev machine that can
compile the core. If you only want to run the ready-built `.rbf`, use
[`../../QUICKSTART-mister.md`](../../QUICKSTART-mister.md) instead - this doc is
for setting up a build/debug environment.

All links verified 2026-07-08.

## 1. Hardware checklist

From the official requirements page
(https://mister-devel.github.io/MkDocs_MiSTer/setup/requirements/):

- **Terasic DE10-Nano** — you have this (the "MiSTer PI" is a DE10-Nano). MiSTer is
  designed and tested on this exact board.
- **MicroSD card**, 4 GB minimum (bigger is better — disk images live here too).
- **USB OTG adapter or USB hub add-on** — the DE10-Nano's micro-USB OTG port needs an
  adapter before any USB device (keyboard!) works. No keyboard = no OSD navigation.
- **USB keyboard**, HDMI display.
- Strongly recommended by the docs: **SDRAM add-on board** (many cores require it;
  for the ND-120 it is one of the two main-memory options — see
  [05-devices-block-char.md](05-devices-block-char.md)), a ~21.5 mm heatsink for the
  SoC, and wired ethernet.
- Cables you'll want for development: a **mini-USB cable** for the on-board
  USB-Blaster II JTAG port (next to HDMI) — used for SignalTap and direct core
  upload from Quartus (see [06-debugging.md](06-debugging.md)).

DE10-Nano board manual and schematic are linked from the official developer links
page: https://mister-devel.github.io/MkDocs_MiSTer/developer/links/

## 2. Install MiSTer on the SD card

Official page: https://mister-devel.github.io/MkDocs_MiSTer/setup/software/

1. Download the **Mr. Fusion** installer image (linked from that page; it's a small
   image from its GitHub releases).
2. Flash it to the microSD with balenaEtcher (or Win32 Disk Imager).
3. Insert the card into the slot on the **bottom of the DE10-Nano** (NOT the slot on
   an I/O add-on board, if you get one later).
4. Power on and wait several minutes. Install is done when the OSD menu with a fuzzy
   static background appears on HDMI.

Then run the updater — official page:
https://mister-devel.github.io/MkDocs_MiSTer/setup/updater/

- Press **F12** for the OSD, go to **Scripts**, run the **downloader** script.
- This fetches cores and system files. First run is slow. Wired ethernet preferred;
  WiFi is possible via a setup script you pre-copy into the SD's scripts folder.

Spend an evening as a *user*: load a computer core (e.g. C64 or the PDP-11), mount a
disk image from the OSD, get a feel for what your ND-120 core should behave like.

## 3. Network access to the MiSTer

Official page: https://mister-devel.github.io/MkDocs_MiSTer/advanced/network/

- SSH, FTP and SFTP run **by default**. Credentials: user **root**, password **1**.
- The SD card contents are mounted at **/media/fat**.
- Transfers must be binary mode (relevant for FTP; scp/sftp are fine).
- Samba/CIFS and NFS shares can be mounted into `/media/fat/cifs` via helper
  scripts; Tailscale, static IP, hostname are all covered on that page.
- Caveat from the same page: all MiSTers ship with the same default MAC address
  (`02:03:04:05:06:07`) — change it if you ever have two on one network.

Quick test from WSL2:

```bash
ssh root@<mister-ip>        # password: 1
ls /media/fat
```

## 4. Dev machine: Docker build environment (recommended)

The whole toolchain runs headless in Docker under WSL2 — no Windows-host dance.

- Image: **raetro/quartus:17.0** (Docker Hub: https://hub.docker.com/r/raetro/quartus,
  source: https://github.com/raetro/sdk-docker-fpga). The `17.0` tag contains
  **Quartus v17.0.2.602** — exactly the version MiSTer mandates. There is also a
  `mister` alias tag that maps to 17.0. The image is ~6 GB.
- Alternative wrapper: https://github.com/JupSys/quartus-mister — ships a `quartus`
  shell script so you can run `quartus quartus_sh --flow compile my.qpf`; also
  supports remote JTAG via `JTAG_SERVER`/`JTAG_PASSWD` env vars.

```bash
docker pull raetro/quartus:17.0
# sanity check:
docker run --rm raetro/quartus:17.0 quartus_sh --version
```

Practical WSL2 notes **[inferred from experience, not from a doc]**: keep the core
project on the ext4 side of WSL2 (not on a Windows drive under `/mnt/`) for sane compile times, and
give WSL enough RAM in `.wslconfig` — a Cyclone V fit wants 8+ GB.

## 5. Dev machine: native Quartus Lite 17.0.2 (optional, needed for GUI work)

You will eventually want the Quartus **GUI** for two things: generating the PLL IP
and using SignalTap (see [06-debugging.md](06-debugging.md)). Options: install
natively on Linux/WSL2, or on Windows.

- Direct Linux download (link published on the official developer links page,
  verified live): 
  https://downloads.intel.com/akdlm/software/acdsinst/17.0std.2/602/ib_tar/Quartus-lite-17.0.2.602-linux.tar
  (~8.2 GiB, complete combined installer — Quartus + device files, no separate
  update step needed). A Windows tar is listed on the same links page.
- **No license needed** for Lite (validated guide:
  https://fisherxue.github.io/QuartusModelSimSetupLinux/).
- Known issue on modern Ubuntu: missing **libpng12**. Fix (validated:
  https://www.linuxuprising.com/2018/05/fix-libpng12-0-missing-in-ubuntu-1804.html):

  ```bash
  sudo add-apt-repository ppa:linuxuprising/libpng12
  sudo apt update && sudo apt install libpng12-0
  ```
- For JTAG from Linux, udev rules are needed (rules text in
  [06-debugging.md](06-debugging.md)); under WSL2 you attach the blaster with
  `usbipd` exactly like the Basys3/Tang FTDI workflow you already use.

## 6. Learning resources (all validated)

Read/watch in roughly this order:

1. **Official developer docs index** — start with these four pages:
   - Compiling: https://mister-devel.github.io/MkDocs_MiSTer/developer/mistercompile/
   - The emu module: https://mister-devel.github.io/MkDocs_MiSTer/developer/emu/
   - Porting guide (closest to "bring your own Verilog"):
     https://mister-devel.github.io/MkDocs_MiSTer/developer/porting/
   - Config string: https://mister-devel.github.io/MkDocs_MiSTer/developer/conf_str/
2. **Template_MiSTer** — read the README and `Template.sv` top to bottom:
   https://github.com/MiSTer-devel/Template_MiSTer
3. **alanswx's tutorials** — hands-on lessons (basic cores, DDRAM graphics,
   SDRAM/DDRAM audio): https://github.com/alanswx/Tutorials_MiSTer
4. **pram0d's FPGA core development series** (part 1 validated):
   https://pram0d.com/2022/07/26/fpga-core-development-series-part-1/
5. **PDP2011 MiSTer core** — the case study for everything ND-120 needs:
   https://github.com/MiSTer-Enhanced/PDP2011_MiSTer
6. **Useful snippets** (clock-enable dividers, fractional CE generator, ioctl
   tricks): https://mister-devel.github.io/MkDocs_MiSTer/developer/snippets/
7. Community: forum https://misterfpga.org/ — developer section is "Development for
   MiSTer" at https://misterfpga.org/viewforum.php?f=28 (the site rejects
   non-browser user agents; use a real browser). Official Discord invite (from the
   docs site footer): https://discord.com/invite/misterfpga/

## Setup checklist

- [ ] MiSTer boots to OSD, downloader has run, an existing core loads and runs.
- [ ] `ssh root@mister` works from your dev machine.
- [ ] `docker run --rm raetro/quartus:17.0 quartus_sh --version` prints 17.0.2.
- [ ] You can compile the project with Docker (see [02-building.md](02-building.md)).
