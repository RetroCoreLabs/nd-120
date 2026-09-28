# Quickstart - ND-120 on the Digilent Nexys 4 DDR (Nexys A7-100T)

Run the 1988 Norsk Data ND-120 on this board from a ready-built bitstream -
no FPGA toolchain needed. Two deployment paths: **USB** (proven, used for
every build in this repo) and **microSD card** (verified end to end on our
hardware 27-AUG-2026 - see the note in that section).

What you need:

- Digilent Nexys 4 DDR (also sold as Nexys A7-100T)
- A micro-USB cable (the PROG/UART port powers the board and carries both
  programming and the serial console)
- A microSD card, FAT32 (for the disc image - and, on the SD path, the
  bitstream too)
- A serial terminal program (picocom, PuTTY, TeraTerm, ...)
- A bitstream from the GitHub Release. The filename tells you the CPU
  clock; the console is 115200 on every release file:
  - `nd120_nexys4ddr_45MHz_115200.bit` - fast build (45.45 MHz CPU)
  - `nd120_nexys4ddr_16MHz_115200.bit` - safe build (16.667 MHz CPU,
    large timing margin - try this one if the fast build misbehaves)

## Console settings (both paths)

The machine talks **115200 baud, 7 data bits, EVEN parity, 1 stop bit**,
no flow control - the same setting for every release bitstream.

```
picocom -b 115200 -y e -d 7 -p 1 /dev/ttyUSB1
```

PuTTY: Serial, 115200, 7 data bits, parity Even, 1 stop bit, flow
control None. On Windows the board's COM port appears when the USB cable
is plugged in (Device Manager -> Ports).

If every character shows as `?` or accented garbage, the terminal is
open at 8N1 - the parity bit is being read as data. Fix the framing,
not the cable.

## Path 1: USB (proven)

### 1a. Volatile load over JTAG - gone at power-off

Best for trying things out. Two tool options:

**Vivado Lab Tools** (free, no licence, ~3 GB; or any full Vivado):

1. Install "Vivado Lab Edition" from AMD/Xilinx.
2. Open Hardware Manager -> Open target -> Auto connect.
3. Program device -> pick the downloaded `.bit` -> Program.

This is exactly what this repo's own flow does
(`nexys4ddr/program_only.tcl`), so it is the path with hundreds of
successful uses behind it.

**openFPGALoader** (small, open source; in oss-cad-suite, or
`apt install openfpgaloader` / `brew install openfpgaloader`):

```
openFPGALoader --detect                 # confirm it sees the board
openFPGALoader -b nexys_a7 <file>.bit   # volatile SRAM load
```

Not yet exercised on this board in this project - if `-b nexys_a7` is
not accepted by your version, `--detect` prints the FTDI cable and
`--list-boards` the supported names.

### 1b. Persistent - write the onboard QSPI flash, survives power-off

```
cd Verilog/fpga/nexys4ddr
vivado -mode batch -source flash.tcl -tclargs nd120_nexys4ddr.bit
```

Then set jumper **JP1 to QSPI** and the board boots the ND-120 at every
power-on with no PC attached. (By hand in the Hardware Manager: Add
Configuration Memory Device on the xc7a100t and pick
**`s25fl128sxxxxxx0-spi-x1_x2_x4`** - the board carries a Spansion
S25FL128**S**, and the similarly named S25FL128**L** is a different chip.)

**This ERASES whatever was in the flash, which on a factory board is
Digilent's demo application.** Save it first if you want it back:

```
vivado -mode batch -source readback_qspi.tcl -tclargs demo.bin 16777216
```

and put it back later with `restore_qspi.tcl`. This repo already carries one
board's demo in `fpga/nexys4ddr/qspi_factory_backup.zip`. Full detail, and why
the flash part must be named rather than wildcarded, is in
`fpga/nexys4ddr/README.md` under "QSPI flash: the demo, and putting it back".

To go back to a plain board, restore the demo or move JP1 back to JTAG.

### 2. Disc image and boot

1. Copy a Winchester disc image onto the FAT32 microSD (root directory)
   and insert it. The image is **not** part of the release - it contains
   SINTRAN III, which is not this project's to distribute. The ND software
   preservation community keeps images; `ndtool` builds and inspects them.
2. Open the terminal (settings above). You are at the machine's OPCOM
   console - that is the no-image smoke test: press ENTER and the
   microprogram answers. This proves the bitstream and the console.
3. Boot the operating system: type `20500&`
4. First output within ~30 s, `SINTRAN III RUNNING` and the Watchdog
   banner shortly after. Log in and enjoy 1988.

## Path 2: microSD card - no software on the PC at all

> **VERIFIED WORKING end to end (27-AUG-2026)** with bitstreams built
> after the fix-sd-card change: the FPGA configures itself from the
> card AND boots SINTRAN from the same card afterwards. Bitstreams older
> than 27-AUG-2026 give OPCOM only on this path (the fix and its history:
> the 27-AUG row in `HISTORY.md`).
> Reference: `nexys4ddr/docs/nexys4ddr_rm.pdf`, Figure 3 and
> section 3.3.

1. Format the microSD FAT32. Copy **both** files to the root directory:
   - **exactly ONE `.bit`** file (the config controller picks the `.bit`
     it finds - two on one card is asking for the wrong one)
   - the Winchester disc image
2. Set **two** jumpers (both verified on hardware):
   - **JP1** ("MODE", the header up by the DONE LED): move the blue
     jumper cap to the **far-right position, covering pins 3 and 4** -
     that is "USB/SD". The factory default is pins 1 and 2, which is a
     different mode - the cap MUST be moved.
   - **JP2** ("MEDIA SELECT", down by the microSD slot): set to the
     **SD** side (it chooses between a USB pen drive and the microSD).
3. Insert the card and power-cycle (or press the **PROG** button).
4. Watch the LEDs: **BUSY** steady = the controller is reading the card
   and configuring the FPGA; **DONE** lights when configuration
   succeeded. A slow BUSY pulse means no usable medium was found -
   check the card and JP2. A `.bit` built for a different FPGA part is
   rejected automatically.
5. Open the terminal (settings above) and continue from the OPCOM smoke
   test - the machine is running with no software installed on the PC.

## Troubleshooting

| Symptom | Cause |
|---|---|
| Terminal shows `?`-garbage | 8N1 framing - set 7 bits, EVEN parity, 1 stop bit |
| Nothing on the terminal at all | Wrong baud (release builds are all 115200; bitstreams older than 26-AUG-2026 were 9600), or wrong COM/tty (on Linux usually `/dev/ttyUSB1`) |
| OPCOM answers, `20500&` prints nothing | No disc image on the card, image not in the FAT root, or card not FAT32 |
| Board dark after power-cycle | The JTAG load (path 1a) is volatile - use 1b (QSPI) or path 2 (SD) for persistence |
| BUSY pulses slowly, no config from SD | JP2 not on the SD side, card not FAT32, or no `.bit` in the root |
| Configures from SD but was not supposed to | JP1 cap left on pins 3-4 - move it back to the JTAG position |
| LD16 lit red | The DDR2 watchdog tripped - power-cycle; if it repeats, report it with the LED/7-segment state (`nexys4ddr/DEBUG-PANEL.md`) |
