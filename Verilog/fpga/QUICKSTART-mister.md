# Quickstart - ND-120 on the MiSTer (DE10-Nano)

Run the 1988 Norsk Data ND-120 CPU on a MiSTer (Terasic DE10-Nano, or the
Retro Remake **MiSTer Pi** clone - same Cyclone V SoC, the core is the same
`.rbf` either way). No FPGA toolchain needed - just the ready-built `.rbf`
from the [Releases page](https://github.com/RetroCoreLabs/nd-120/releases).

**Verified on real hardware (DE10-Nano, 02-SEP-2026):** boots to OPCOM, boots
SINTRAN III from a mounted Winchester image, CPU self-test passes (green `G`
lamp), and the TDV2200 box-drawing font and keyboard work.

## What you need

- A MiSTer setup that already runs (DE10-Nano + SDRAM module + the standard
  MiSTer SD card - see https://mister-devel.github.io/MkDocs_MiSTer/). The
  **SDRAM module is required**: the ND-120's 4 MB main memory lives in it.
- The core file `nd120_mister_20MHz_115200.rbf` from the release.
- A Winchester (hard-disc) image for SINTRAN - **not** in the release; see
  "The disc image" below.

## 1. Copy the core to the SD card

Put the `.rbf` in the MiSTer's **Computer** section so it shows up in the menu:

```
/media/fat/_Computer/nd120_mister_20MHz_115200.rbf
```

Copy it over the network (`scp`/Samba) or by taking the SD card to a PC. The
underscore-prefixed `_Computer` folder is the standard MiSTer convention for
the OSD's "Computer" section.

## 2. Load the core

Power on the MiSTer, press **F12** to open the OSD (on-screen menu), go to
**Computer**, and pick **ND120**. Loading a core reprograms the FPGA - it is
flash-free and safe. (Over the network you can also load it without the menu:
`ssh root@<mister-ip> 'echo "load_core /media/fat/_Computer/nd120_mister_20MHz_115200.rbf" > /dev/MiSTer_cmd'`.)

## 3. What you see, and how to boot

The console is the **MiSTer's own screen and keyboard** - a full TDV2200
terminal. The CPU's serial line is also on the HPS `/dev/ttyS1` at **115200,
7 data bits, EVEN parity, 1 stop bit** if you want a logger.

1. At power-on you get the four-line banner (core / console / build stamp /
   board + clock + memory), the operator panel across the bottom, and the CPU
   **`G` lamp lit green** once the self-test passes.
2. You land at the OPCOM `#` monitor. That alone is the "it works" smoke test -
   the machine is alive even with no disc.
3. To boot SINTRAN, **mount a Winchester image** in the OSD (F12 -> the disc /
   mount slot), then at the `#` prompt type:

   ```
   &
   ```

   SINTRAN loads from the image and comes up; log in and run programs.

## The disc image

Not in the release (instructions only). The machine needs a Winchester image
(a SINTRAN system disc); mount it from the OSD. Point at the ND software
preservation community for images, and at `ndtool` for building/inspecting
them. A core with no image still reaches OPCOM (step 2).

## Troubleshooting

| Symptom | Fix |
|---|---|
| ND120 not in the menu | The `.rbf` must be in `/media/fat/_Computer/`; browse the Computer section so the menu re-reads the folder |
| Nothing on screen / no banner | Check the MiSTer's own video is up (HDMI); loading the core reboots the ARM side, so give it a few seconds |
| Banner shows but no green `G` | Self-test did not pass - report it (see below) |
| Boxes/lines look like letters | That is the box-drawing font; if it is wrong, report the exact characters |
| `&` does nothing at `#` | No Winchester image mounted - mount one in the OSD first |

## What to report

If something is off, the useful facts are: does the four-line banner render
(including the box-drawing lines), does the `G` lamp go green, does OPCOM
answer at `#`, does `&` boot SINTRAN from a mounted image, and does the
keyboard type correctly. The MiSTer core's own detailed notes are in
`Verilog/fpga/mister/README.md` and `Verilog/fpga/mister/docs/`.
