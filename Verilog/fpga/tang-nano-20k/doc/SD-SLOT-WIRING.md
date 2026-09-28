# Tang Nano 20K microSD slot - wiring, settled

> **Question closed 25-AUG-2026.** All four SD data lines DAT0-DAT3 ARE
> routed from the microSD socket to FPGA pins. A 4-bit SD bus is possible
> on this board, and has been measured working on it. Any 4-bit failure
> is a logic or integration fault, never missing board wiring.

Read from the **Sipeed Tang Nano 20K schematic**, sheet `MICRO SD CARD`,
connector **J7** (title block: Size A4, Date 2023-06-13, Rev 1.22 - the
file is published as "v1.3"). A copy of the schematic is vendored next
to this file as `tang_nano_20k_schematic_v1.3.pdf` so the evidence stays
with the repo.

## J7 - Micro SD Card socket

| J7 pin | Card signal | Net          | FPGA pin | Series / pull-up |
|--------|-------------|--------------|----------|------------------|
| 1      | DAT2        | `SDIO_D2`    | **80**   | R53 10K to +3V3  |
| 2      | DAT3/CD     | `SDIO_D3`    | **81**   | R54 10K to +3V3  |
| 3      | CMD         | `SDIO_CMD`   | **82**   | R55 10K to +3V3  |
| 4      | VDD         | +3V3         | -        | C26 4.7uF        |
| 5      | CLK         | `SDIO_CLK`   | **83**   | R49 22R series   |
| 6      | VSS         | GND          | -        | -                |
| 7      | DAT0        | `SDIO_D0`    | **84**   | R56 10K to +3V3  |
| 8      | DAT1        | `SDIO_D1`    | **85**   | R57 10K to +3V3  |
| 9 / 10 | DET_B / DET_A | card detect | -       | -                |

Consequences that follow directly from the table:

- **Every data line reaches the FPGA.** DAT1, DAT2 and DAT3 are ordinary
  FPGA I/O on pins 85, 80 and 81. Nothing about the board prevents
  4-bit operation.
- **The pull-ups are on the board (R53-R57, 10K).** That is why the
  constraint file sets `PULL_MODE=NONE` on all six SD pins: a released
  pad idles high through the external resistor. It is also why DAT3 is
  high at CMD0, which is what keeps the card out of SPI mode.
- **DAT3 doubles as the card-detect pin** at the socket (`DAT3/CD`).
  It still goes to FPGA pin 81; the separate DET_A/DET_B switch pins
  are the mechanical detect and are not used by this design.
- **CLK has a 22R series resistor (R49)** - normal edge-rate damping,
  no functional restriction.
- **`SDIO_D1` (pin 85) and `SDIO_D2` (pin 80) are also brought out to
  the 20-pin edge header.** Leave that header unloaded when running the
  4-bit bus; anything plugged in sits on two of the four data lines.
- The six SD nets are shared with the BL616 companion chip. Stock BL616
  firmware tri-states them; a reflashed BL616 can disturb the bus.

## Proof that 4-bit works on this physical slot

Not an inference from the schematic - a measurement on this board:

- `Verilog/fpga/tang-nano-20k/sd-fat-test/`, 12-JUL-2026, real 32 GB
  SDHC FAT32 card, menus 6/7 (1000 x 2048 bytes through `IO.DAT`):
  **WRITE 3418 KB/s, READ 5981 KB/s** over DAT3..DAT0, against a
  137 KB/s 1-bit baseline. The full FAT walk (`LIST` freescan and
  `CHECK` over a 75 MB image) ran over 4-bit as well.
  Recorded in `Verilog/fpga/tang-nano-20k/sd-fat-test/README.md`.
- MiSTeryNano runs 4-bit at 16 MHz on this same slot with the same
  `PULL_MODE=NONE` configuration.

## The one silicon trap on these pins

Yosys will silently drop a tristate if the pad is not written as a
**single** ternary. This bit DAT1-3 once already (12-JUL-2026): a
nested-ternary "park high" expression became an always-driving OBUF, the
FPGA fought the card through every 4-bit read data phase, and all 4-bit
reads failed on silicon while simulating perfectly.

Required form, at the top-level pad only:

```verilog
assign sd_dat1 = oe ? val : 1'bz;
```

Guarded by the `test-tristate` netlist gate (yosys proc+tribuf audit)
plus the runtime contention assertions in the harnesses. If a 4-bit
build misbehaves, check the netlist pad direction before anything else.

## Current state in the ND-120 build

`Verilog/fpga/tang-nano-20k/src/ND120_TANG20K_TOP.v` instantiates
`nd_storage` with `USE_4BIT(0)`. The pins are constrained
(`src/nd120_tang20k.cst`), the pads use the single-ternary form and the
netlist shows them as `IOBUF`, but `USE_4BIT=1` does not reach the
SINTRAN banner. Since the board wiring is settled by the table above and
the slot is proven at 4-bit by `sd-fat-test`, the remaining difference
is the integration: in `sd-fat-test` the engine owns the card, while in
`nd_storage` the reader and writer share it through the mount FSM and
`s_phase_write`. That is where to look - not at the board.
