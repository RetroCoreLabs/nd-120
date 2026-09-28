# Devices: Block (disks) and Character (console), with the PDP2011 Case Study

Reference for how the shipped core serves storage and console: floppy/Winchester/
tape as image files on the Linux side, the console on the machine's own screen and
keyboard, microcode uploaded from the HPS at core load. All links verified
2026-07-08.

What actually shipped: five OSD mount slots (floppy 0/1, Winchester 0/1, paper
tape) served over the block interface by `rtl/nd_storage_hps.v`; a clean-room
TDV2200 terminal on the MiSTer's own screen + keyboard (shared with the MEGA65
port); and 4 MB main memory in the DE10-Nano SDRAM add-on module. Sections 2 and
5 keep, in short, the reference material that informed those choices (trimmed
28-SEP-2026; the full case study is in git history).

## 1. Block devices — the hps_io protocol

Source of truth: `sys/hps_io.sv`
(https://raw.githubusercontent.com/MiSTer-devel/Template_MiSTer/master/sys/hps_io.sv)
and the official overview
(https://mister-devel.github.io/MkDocs_MiSTer/developer/hps_io/).

When the user mounts an image via an `S` menu slot, Linux opens the file and from
then on services sector requests from your logic. Per-drive signals (arrays sized
by the `VDNUM` parameter, up to 10 drives; up to 4 images mounted simultaneously per
the porting docs):

| Signal | Dir (core view) | Width | Meaning |
|---|---|---|---|
| `img_mounted[n]` | in | 1 | pulses when slot n (un)mounts |
| `img_readonly` | in | 1 | valid during img_mounted pulse |
| `img_size` | in | 64 | bytes; 0 = unmounted. valid during pulse |
| `sd_lba[n]` | out | 32 | block number to transfer |
| `sd_blk_cnt[n]` | out | 6 | blocks-1 per request (total <= 16 KB) |
| `sd_rd[n]` / `sd_wr[n]` | out | 1 | request read / write |
| `sd_ack[n]` | in | 1 | high while Linux services the request |
| `sd_buff_addr` | in | 13 (8-bit) / 12 (16-bit) | address into YOUR buffer RAM |
| `sd_buff_dout` | in | 8/16 | data from image (reads) |
| `sd_buff_wr` | in | 1 | write strobe for sd_buff_dout |
| `sd_buff_din[n]` | out | 8/16 | data to image (writes) |

Protocol: raise `sd_rd[n]` with `sd_lba[n]` valid → Linux polls, asserts
`sd_ack[n]`, streams the sector through the buffer port (the comments say the port
is designed for a 2-port altsyncram — you supply a small dual-port BRAM as the
sector buffer) → drop your request on ack. Block size defaults to 512 bytes
(`BLKSZ` parameter). The disk image is a **flat sequence of blocks** — exactly what
a file on the SD card provides.

## 2. Case study: how PDP2011 does its disks (short)

PDP2011 (https://github.com/MiSTer-Enhanced/PDP2011_MiSTer) did not rewrite its
disk controllers for MiSTer: its RK11/RL11/RH70 controllers speak SPI-SD
natively, and the port puts the framework's `sys/sd_card.sv` SD-card emulator
between each controller's SPI pins and `hps_io`. Lesson taken for the ND-120:
drive `sd_lba/sd_rd/sd_wr/sd_buff_*` directly with a sector-level handshake -
the SPI layer is baggage from PDP2011's standalone-FPGA origin. Two tricks worth
copying: the mount pulse makes a controller present/absent at runtime, and an OSD
option can redirect a controller to the physical secondary SD slot.

## 3. File upload (ioctl) — the microcode path

From `hps_io.sv` (same source): the `F` menu entries and boot files arrive as a
byte/word stream:

- `ioctl_download` — high during transfer; `ioctl_index[15:0]` — which menu entry
  (F1 → 1...; `boot.rom` auto-loads as index 0 at core start);
- `ioctl_wr` strobe + `ioctl_addr[26:0]` + `ioctl_dout[7:0 or 15:0]`;
- `ioctl_wait` — throttle the stream if your write port is slow;
- `ioctl_file_ext[31:0]` — the actual extension picked;
- upload in the other direction exists too (`ioctl_upload`/`ioctl_din`) — could
  dump machine state or memory to a file for offline diffing against Verilator.

ND-120 use: replace baked-in `AM27256_45132L.hex` / WCS hex init with an ioctl
receiver that writes the WCS/EPROM RAMs while holding the CPU in MCL. Name the file
`boot.rom` in `/media/fat/games/ND120/` and index-0 auto-load gives "microcode
loads at core start" with no user action. **[the exact boot.rom per-core folder
lookup is standard practice via the games path
(https://mister-devel.github.io/MkDocs_MiSTer/cores/paths/) — verify the filename
convention on first use]**

## 4. Character devices — OPCOM console and beyond

Three options, all real (validated):

1. **Framework UART** (recommended first): `emu` has
   `UART_RXD/TXD/CTS/RTS/DTR/DSR`. Per the official emu docs
   (https://mister-devel.github.io/MkDocs_MiSTer/developer/emu/ and the wiki emu
   page): "Serial is passed to the linux arm side of the MiSTer. On the arm side,
   software decides what to do with the data. ie: send it to shell, ppp, MIDI,
   etc." — enabled/configured by the `UART<speeds>` token in the CONF_STR header
   (PDP2011: `"PDP2011;UART19200;"`). Wire the ND-120 current-loop/UART console
   (OPCOM) here; on the Linux side you attach a terminal to it via the OSD.
2. **User port as raw UART**: `USER_IN[6:0]`/`USER_OUT[6:0]` on the I/O board's
   USB3-style user port (open-drain; set USER_OUT bit to 1 to read USER_IN) — a
   direct cable to a USB-serial adapter, independent of the Linux side. Good as a
   debug side-channel.
3. **Built-in video terminal** (later, and very much in the ND spirit): PDP2011
   ships a VT100/VT105 (`rtl/vt.vhd` + `rtl/vga.vhd` + `rtl/ps2.vhd`) rendered via
   the framework video chain, with an OSD switch choosing whether the console
   KL11 talks to the on-screen VT or the external UART. An ND "Tandberg terminal
   on HDMI + USB keyboard" would follow exactly that pattern; `hps_io` provides
   `ps2_key` for the keyboard. Video helpers:
   https://mister-devel.github.io/MkDocs_MiSTer/developer/video_mixer/

PDP2011 instantiates four KL11 serial units and muxes unit 0/1 between the VT and
the external UART with one status bit — a good template for OPCOM + extra ND
terminal ports.

## 5. Main memory (shipped: 4 MB in the SDRAM module)

The shipped core puts 4 MB (2M words) of main memory in the DE10-Nano SDRAM
add-on module (WCS in block RAM, cache off), on the Tang Nano 20K SDRAM bridge.
The documented fallback is the HPS DDR3 through the `DDRAM_*` emu ports (as
ao486 uses it): higher, variable latency, no add-on board, and the porting docs
warn it needs careful reset handling.

## Device checklist

- [ ] Microcode loads from the HPS at core load, CPU boots to OPCOM.
- [ ] Main memory in the SDRAM module passes the memory test that runs in Verilator.
- [ ] A disc image mounts from the OSD; the controller reads sector 0 (verify by
      checksumming the same file over ssh).
- [ ] SINTRAN boots from a mounted Winchester image.

---

## Addendum, 27-AUG-2026 - the built-in terminal, and why we cannot vendor PDP2011's

PDP2011's VT100/VT105 terminal files carry a **non-commercial-use-only**
header (Sytse van Slooten, 2008-2021), which is NOT the repo's GPL-2.0
`LICENSE` and cannot be mixed into this MIT repo.

Decision (carried out): the terminal was re-implemented clean-room, using
PDP2011 only as a feature checklist, and shared with the MEGA65 port. The
shipped console is a TDV2200 terminal on the MiSTer's own screen + keyboard
(box-drawing font and keyboard confirmed on hardware 02-SEP-2026), not a VT100.
Terminal core: [`../../../Terminals/`](../../../Terminals/).
