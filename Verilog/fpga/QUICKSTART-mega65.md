# Quickstart - ND-120 on the MEGA65

Run the 1988 Norsk Data ND-120 minicomputer on a MEGA65 from a ready-built
core file - no FPGA toolchain, no cables, no PC software. The core is the
whole machine: the ND-120 CPU board with 4 MB of memory, a Tandberg TDV2200
terminal on the MEGA65's own keyboard and screen, and two floppy drives, two
Winchester discs and a paper-tape reader served from image files on the SD
card. It boots SINTRAN III from a Winchester image.

> **Status: built and simulated, NOT YET RUN ON A MEGA65.**
> Every part of this core has run on a DE10-Nano (MiSTer) or a Nexys 4 DDR
> or passes its testbench, but this combination has never met a real MEGA65.
> If you have one, you are the test - see "What to report" at the end. Keep
> a copy of your disc images.

Built into both cores, nothing to configure:

- **The console.** The TDV2200 terminal runs inside the core on the MEGA65's
  own keyboard and screen. No serial cable, no PC and no terminal program
  are needed; the `115200` in the file name is the internal link between
  the CPU and the terminal.
- **The panel clock** (the MC68705 real-time clock), so SINTRAN can set and
  read the time. The operator panel's `UP:` field is time since reset, not
  this clock.

What you need:

- A MEGA65 (R3/R3A, or R4/R5/R6) and its keyboard and a monitor (VGA or
  HDMI - both work)
- A micro-SD card, FAT32
- The core file for YOUR board revision from the GitHub Release:
  - `nd120_mega65_rev3_13MHz_115200.cor` - R3 / R3A (most machines bought
    before 2024): main memory in the 8 MB HyperRAM, CPU at 13.33 MHz
  - `nd120_mega65_r6_20MHz_115200.cor` - R6 (machines shipped 2024 or
    later, serial numbers above 1000), also R4/R5: main memory in the
    64 MB SDRAM, CPU at 20 MHz
- A Winchester disc image with SINTRAN III (not part of the release - it is
  Norsk Data's software; the ND preservation community keeps images and
  `ndtool` builds and inspects them). Floppy and paper-tape images are
  optional.

The MEGA65 refuses a core built for another revision ("Core hardware model
mismatch!"), so the filename's `rev3`/`r6` must match your board. Not sure
which you have: hold **RESTORE** for about 2 seconds (the freezer opens),
press **HELP** - "MEGA65 MODEL" is on that screen.

## 1. Prepare the SD card

1. Format the micro-SD as FAT32 (the internal or the external slot both
   work).
2. Copy the `.cor` file onto it (anywhere).
3. Make a folder named `/nd120` (lower case, in the root of the card). Put
   your disc images in it: the Winchester image with SINTRAN III at least,
   and floppy and tape images if you have them. Writes go straight to the
   image files on the card, so keep a copy of your images.
4. Copy the settings file `nd120cfg` into `/nd120`. In this repository it is
   [`Verilog/fpga/mega65/sdcard/nd120/nd120cfg`](mega65/sdcard/nd120/nd120cfg).
   The `sdcard` folder there only holds the files to copy; it is not a
   folder on the card.

### About `nd120cfg`

- It is 35 bytes, all `0xFF`: "nothing saved yet". The core then starts
  with its factory defaults and writes your choices into the file each time
  you change a menu setting. That is how the settings survive a power cycle.
- The name must be exactly `nd120cfg`, with no extension. Do not edit it by
  hand.
- The core does **not** create it. If the file is missing, or is not exactly
  35 bytes, the core still runs, but it uses the defaults and saves nothing.

### The disc images

This guide uses the file names in the table below. They are a naming
convention, not a requirement: the core looks for no file name except
`nd120cfg`, so an image can have any name and any extension. The core's
file browser opens in `/nd120`, and you pick a file from the menu (**HELP**
key, section "Drives"). The menu line you pick it from decides which drive
it becomes.

| Type | File name in `/nd120` | Menu line | Notes |
|---|---|---|---|
| Winchester 0 | `WD0.IMG` | `Winch. 0:` | the SINTRAN III disc image; `20500&` boots from this one |
| Winchester 1 | `WD1.IMG` | `Winch. 1:` | optional |
| Floppy drive 0 | `FLOPPY1.IMG` | `Floppy 0:` | optional; 315392 bytes = 8-inch, 512 B/sector, any other size = 1.2 MB, 1024 B/sector |
| Floppy drive 1 | `FLOPPY2.IMG` | `Floppy 1:` | optional; same size rule |
| Paper tape | `BOOT.TAP` | `Tape:` | optional; read from byte 0 |

The names come from the shared SD storage code (`Verilog/SD-FAT/circuit/nd_storage.v`),
which the Tang Nano 20K and the other boards use. There the floppy image
`FLOPPY1.IMG` is drive 0 and `FLOPPY2.IMG` is drive 1, so the numbers differ
by one from the menu lines. The tape name is `BOOT.TAP` on the Tang; the
storage code's own default is `TAPE.BPUN`. The MEGA65 core does not enforce
any of these names.

This core has no SMD disc (`SMD0.IMG`, `1540&`): only the Winchester, floppy
and tape devices are built in.

Mounts are not remembered over a power cycle. Mount the images again from
the menu after every power-on.

## 2. Flash the core (standard MEGA65 procedure)

1. Insert the card. Power on while holding **NO SCROLL** - the core menu
   appears.
2. Press **CTRL + a slot number** (any slot except 0; keep slot 1 for the
   stock MEGA65 core), pick the `.cor` file.
3. **Do not reset or switch off until the confirmation message** - flashing
   takes a minute or two.
4. To run it: power on holding **NO SCROLL** and press the slot number. A
   plain power cycle returns to the stock core; nothing is permanent.

## 3. What you see, and how to boot

1. The framework's welcome page. Press **Space**.
2. A green 80x25 terminal with the power-on banner: `ND-120 ...`, a line
   with the git hash and build date, and a line saying `MEGA65 R3` or
   `MEGA65 R6` with the CPU clock and memory - that line identifies the
   build in any photo. Below the text: the operator panel (program level,
   lamps, MIPS).
3. **The case power LED is the CPU's verdict**: amber while the CPU runs
   its self-test, **green when it passed** (the same meaning as the CPU
   board's own green lamp). Amber that never turns green means the CPU did
   not come up.
4. Press **RETURN**. The microprogram answers with the OPCOM prompt. That
   is the no-disc smoke test: CPU, memory and console are alive.
5. Press **HELP** - the menu. Under **Drives**, mount your Winchester image
   on **Winch. 0** (and floppies / tape if you have them). Close the menu.
6. At the OPCOM prompt type `20500&` and RETURN. SINTRAN III boots from
   Winchester 0: first lines within about 30 seconds, then
   `SINTRAN III RUNNING` and the login. Floppy 0 boots with `1560&`.

The keyboard types what the MEGA65 keycaps say, shifted symbols included.
INST/DEL is Backspace, CLR/HOME is Home, the cursor keys and F1-F8 send the
TDV2200 codes, CAPS LOCK latches as the keycap does. **RUN/STOP is EXIT**
(the TDV2200's SLUTT key - how you leave a SINTRAN program); ALT+X is the
same key. The menu also sets the
text colour (green/amber/white/cyan), the operator panel on/off, the CPU
cache on/off and the HDMI mode. What each field of the operator panel
means: `Verilog/fpga/mega65/docs/01-using-the-core.md`, "Reading the
operator panel".

## Troubleshooting

| Symptom | Meaning |
|---|---|
| Flash menu says "Core hardware model mismatch!" | wrong revision's file - see above |
| Black screen, but HELP still opens the menu | the framework is alive, the ND-120 terminal is not - report it |
| Banner shows, RETURN gives no OPCOM prompt, power LED stays amber | the CPU did not pass its self-test - report it with the banner line |
| OPCOM answers, `20500&` prints nothing | no image mounted on Winch. 0, or the image is not a bootable SINTRAN disc |
| SINTRAN boots but feels slow | disc images are served by the framework's small firmware CPU reading the SD card; SINTRAN paging speed on that path is unmeasured - report timings |

## What to report (the first testers)

1. A **photo of the screen** with the banner, and one after `20500&` (the
   SINTRAN start-up text, or whatever happened instead).
2. The **power LED colour** after a few seconds (amber / green).
3. Which output: **VGA or HDMI**.
4. Your MEGA65 model.

If the screen stays black: does the **HELP** menu still appear? That tells
us whether the framework is alive and only the ND-120 is dark, or the whole
core failed. Please do not spend time debugging - what you saw is the data. The build's own facts (timing, what
is proven where) are in `Verilog/fpga/mega65/docs/00-plan.md`; the port
itself in `Verilog/fpga/mega65/README.md`.
