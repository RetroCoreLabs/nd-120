# Quickstart - ND-120 on the QMTECH XC7A35T SDRAM core board

Run the 1988 Norsk Data ND-120 on this board from a ready-built bitstream.

> **READ THIS FIRST. This bitstream has never been run on a board.** It was
> built 04-SEP-2026, meets timing with +4.645 ns of margin and has zero
> errors, but no QMTECH board has yet loaded it. Everything below is written
> from the schematic, the vendor manual and the build - not from a boot. If
> you are the first person to try it, you are the verification channel: what
> to look for is under "What a good first boot looks like", and what to
> report is at the bottom.

What you need:

- QMTECH XC7A35T SDRAM core board (`XC7A35T-1CSG325C`, 32 MB SDRAM)
- **A Xilinx Platform Cable USB II** (or any Xilinx-compatible JTAG cable).
  This board has **no USB data path at all** - the Mini USB socket is power
  only - so JTAG is the only way in.
- A Mini USB cable for power
- **A 3.3 V USB-to-serial adapter** for the console. There is no on-board
  UART either; the console goes out on header pins.
- An SD card module: a Digilent **Pmod MicroSD** or **Pmod SD**, plus jumper
  wires. The board has no SD slot, and JP3 is a plain 2x25 header, not a
  Pmod connector - so this is a wiring job, not a plug-in job.
- A microSD card, FAT32, for the disc images
- A serial terminal program (picocom, PuTTY, TeraTerm, RetroTerm, ...)
- The bitstream `nd120_qmtech_a35t_20MHz_115200.bit` from the GitHub Release

Three things this board does NOT have, all of which change the routine you
may know from the Nexys or the Tang: no USB-serial, no SD slot, and no
SD-card configuration path. Programming is JTAG only, and it is **volatile** -
a power cycle wipes the FPGA and you program it again.

## 1. Wire the console and the SD card to header JP3

JP3 is the 2x25 2.54 mm header. Its net names in the schematic are `IO_<pin>`,
so the net name IS the FPGA pin - the table below is read straight off
schematic sheet 2.

| What | JP3 pin | FPGA pin | Goes to |
|---|---|---|---|
| console TX (FPGA out) | 5 | `F18` | adapter **RX** |
| console RX (FPGA in) | 6 | `G17` | adapter **TX** |
| card CLK / SCK | 7 | `E18` | Pmod pin 4 |
| card CMD / MOSI | 8 | `F17` | Pmod pin 2 |
| card DAT0 / MISO | 9 | `D18` | Pmod pin 3 |
| card DAT1 | 10 | `E17` | Pmod pin 7 |
| card DAT2 | 11 | `C17` | Pmod pin 8 |
| card DAT3 / ~CS | 12 | `C18` | Pmod pin 1 |
| 3V3 for the card | 2 | (power rail) | Pmod pin 6 (or 12) |
| ground | see below | | Pmod pin 5 (or 11), and the adapter's GND |

The Pmod side of that mapping (pin 1 = ~CS/DAT3, 2 = MOSI/CMD, 3 = MISO/DAT0,
4 = SCK, 5 and 11 = GND, 6 and 12 = VCC, 7 = DAT1, 8 = DAT2, 9 = card detect,
10 = unused) is the Digilent Pmod MicroSD / Pmod SD mapping, the same one the
Cmod A7 port uses. Check it against your own module's datasheet before
wiring - it costs a minute and a wrong VCC pin costs a card.

### The same thing as a picture

The two connectors, drawn as you look down on them. Only the top of JP3 is
shown - pins 13 to 50 are not used by this build.

```
   QMTECH JP3  (2x25)                      Digilent Pmod MicroSD / Pmod SD (2x6)
   pin 1 is marked on the silkscreen       pin 1 is marked on the board

        odd        even                    +------------------------------+
      +------+   +------+                  |  1    2    3    4    5    6  |
   1  | 5V   |   | 3V3  |  2 ----------,   | ~CS  MOSI MISO SCK  GND  VCC |
      +------+   +------+              |   |                              |
   3  | GND? |   | GND? |  4  <-- meter|   |  7    8    9   10   11   12  |
      +------+   +------+     these    |   | DAT1 DAT2  CD   NC  GND  VCC |
   5  | F18  |   | G17  |  6   four    |   +------------------------------+
      +------+   +------+              |
   7  | E18  |   | F17  |  8           |
      +------+   +------+              |
   9  | D18  |   | E17  | 10           |
      +------+   +------+              |
  11  | C17  |   | C18  | 12           |
      +------+   +------+              |
  13  |  .   |   |  .   | 14           |
       ......      ......              |
  21  | GND? |   | GND? | 22  <-- and  |
      +------+   +------+       these  |
       ......      ......              |
  49  |  .   |   |  .   | 50           |
      +------+   +------+              |
                                       |
   JP3 pin 2  (3V3) --------------------'-------------> Pmod pin 6   VCC

   JP3 pin 7   E18  ------------------------------->  Pmod pin 4   SCK
   JP3 pin 8   F17  ------------------------------->  Pmod pin 2   MOSI / CMD
   JP3 pin 9   D18  <-------------------------------  Pmod pin 3   MISO / DAT0
   JP3 pin 10  E17  <------------------------------>  Pmod pin 7   DAT1
   JP3 pin 11  C17  <------------------------------>  Pmod pin 8   DAT2
   JP3 pin 12  C18  ------------------------------->  Pmod pin 1   ~CS / DAT3
   JP3 ground  ????  ------------------------------>  Pmod pin 5   GND

                          ... and the console adapter:

   JP3 pin 5   F18  ------------------------------->  adapter  RX
   JP3 pin 6   G17  <-------------------------------  adapter  TX
   JP3 ground  ????  ------------------------------>  adapter  GND
```

Reading the arrows: `--->` is the FPGA driving, `<---` is the FPGA listening,
`<-->` is a line that goes both ways (unused in 1-bit mode, but still wired).
Note the console pair **crosses over** - the FPGA's transmit goes to the
adapter's receive. Getting that backwards gives a completely silent terminal
with everything else looking healthy, and it is the most common first mistake.

`????` is the ground pin nobody has confirmed yet. Read the next section
before you connect it.

Two things the drawing cannot tell you, so check them on the board:

- **Which physical row is odd and which is even.** The drawing puts the odd
  numbers on the left because that is how the schematic lists them; whether
  that is left or right in your hand depends on which way round you are
  holding the board. Find the **pin 1 marker on the silkscreen** and count
  from there. Counting from the wrong end puts 5 V where you meant 3V3.
- **Your Pmod's own pin 1.** Same rule - the marker on the module wins over
  any drawing.

### Ground - the one thing to confirm with a meter before you wire anything

**JP3 pin 1 is the USB 5 V rail and pin 2 is 3V3.** Do not put a signal on
either.

**Which JP3 pin is ground is NOT VERIFIED.** The schematic's own text names
the 5 V and 3V3 rails on pins 1 and 2, and pins **3, 4, 21 and 22 carry no
I/O net name**, which makes those four the ground candidates - but that is
read out of a PDF text extraction, not confirmed, and this document does not
state it as fact.

Confirm it yourself in thirty seconds, because the board hands you a known
ground to measure against: **the 6-pin JTAG header (J1) has a GND pin**
(manual section 2.2.4, Figure 2-3). Put a meter in continuity mode with one
probe on that JTAG GND and the other on JP3 pin 3, then 4, 21, 22. The one
that beeps is your ground.

Do not skip this. **A card powered from 3V3 with no shared ground simply does
not answer**, and that failure looks exactly like a bad card, a bad image, or
broken logic - you can lose a day to it.

### Two more wiring notes

- **The build uses 1-bit SD mode**, so only CLK, CMD and DAT0 carry traffic.
  Wire all four data lines anyway: DAT1 and DAT2 must idle high, and DAT3
  doubles as the card's chip select while the card is being initialised.
- **Keep the jumper wires short.** These are 20 MHz-class signals on flying
  leads with no ground plane between them. If the card is unreliable, wire
  length is the first suspect, and running a ground wire alongside the card
  bundle helps.

## 2. Connect the JTAG cable and power

1. Attach the Platform Cable USB II to the 6-pin JTAG header (J1). The pin
   order and the flying-lead colours are in the vendor manual, section 2.2.4,
   Figure 2-3 - use it rather than guessing; the header carries VREF and GND
   as well as the four JTAG signals.
2. Plug the Mini USB cable in for power. LED **D2** lights: 3.3 V is present.
3. Insert the microSD into the Pmod.

## 3. Load the bitstream

**Volatile, every time.** This board has no SD-config path (that is a Nexys
feature) and no `.mcs` flash flow is written for it yet, so the bitstream
lives in the FPGA until you cut power. Programming takes a few seconds, so
this is less painful than it sounds.

**With Vivado or the free Vivado Lab Tools, from the GUI:**

1. Open the Hardware Manager, *Open Target -> Auto Connect*. The board must
   enumerate as **`xc7a35t`**. If nothing appears, the cable, its driver or
   board power is the problem - not the bitstream.
2. Right-click the device, *Program Device*, pick
   `nd120_qmtech_a35t_20MHz_115200.bit`, Program.
3. LED **D3** (`FPGA_DONE`) lights when configuration succeeds.

**Or from the command line, in this repository:**

```
cd Verilog/fpga/qmtech-a35t
vivado -mode batch -source build.tcl                    # build + program over JTAG
vivado -mode batch -source build.tcl -tclargs -noburn   # build only, no board needed
```

From WSL, `make load` wraps the first of those and `make` the second (Vivado
runs on the Windows host; the Makefile delegates through `powershell.exe`).

`build.tcl` refuses to write a bitstream on negative slack, so a build that
completes is a build that met timing. It does downgrade the combinational-loop
DRC to a warning - see the board README for why, and what that costs.

## 4. Disc images on the card

Copy the images onto the FAT32 microSD, in the **root directory**, with
plain 8.3 names (the build strips long-filename support to save space):

| File | What it is |
|---|---|
| `BOOT.TAP` | boot tape image |
| `WD0.IMG` | Winchester disc 0 - this is the one SINTRAN boots from |
| `FLOPPY1.IMG` | floppy, optional |

The disc images are **not** part of the release: they contain SINTRAN III,
which is not this project's to distribute. The ND software preservation
community keeps images, and `ndtool` builds and inspects them.

A bitstream with no card at all still comes up in OPCOM - that is the smoke
test in the next step, and it is worth doing before you trust the wiring.

## 5. Test the console

**Settings: 115200 baud, 7 data bits, EVEN parity, 1 stop bit, no flow
control** - the same as every other board in this project.

```
picocom -b 115200 -y e -d 7 -p 1 /dev/ttyUSB0
```

(That 7E1 needs a word of explanation, because the RTL says 8N1 and both are
right: the emulated SC2661 frames **8 data bits, no parity, 1 stop bit** on
the wire, and SINTRAN puts an EVEN **software** parity bit in bit 7 of its
early boot text. Setting the terminal to 7E1 strips that bit and gives clean
text. An 8N1 terminal shows the boot banner with stray high-bit characters.)

Then, in order - each step proves one thing:

1. **Press ENTER.** OPCOM answers. That alone proves the bitstream loaded,
   the CPU is running, the clock is right, and both console wires are on the
   correct pins. **No card is needed for this**, which is why it comes first.
2. **Type `20500&`** to boot from the Winchester. Commands are **UPPERCASE**,
   and type at a human pace - OPCOM drops characters typed faster than about
   0.3 s apart and answers `?`, which looks like a fault and is not one.
3. SINTRAN's banner and the Watchdog line follow. Log in and enjoy 1988.

### What a good first boot looks like

- LED **D3** (`FPGA_DONE`) on right after programming.
- **`led_n[1]` = pin C8, the green one**, lit: the CPU passed self-test and is
  running. `led_n[0]` = pin D8 lit means error or halt.
  *(Caution: the two pin files in this board's folder disagree about which LED
  is which - `nd120_qmtech.xdc` follows the schematic, `board-pins.xdc` has
  them swapped. It only decides which of two LEDs blinks, but do not read a
  bring-up result as a fault on the strength of an LED alone.)*
- A prompt on ENTER within a second or two.
- After `20500&`: SINTRAN's banner, then `SINTRAN III RUNNING`.

### Troubleshooting

| Symptom | Most likely cause |
|---|---|
| Hardware Manager sees no device | JTAG cable driver, cable seating, or board not powered (D2 dark) |
| D3 (`FPGA_DONE`) never lights | Programming did not complete - re-run it and read the Vivado message, don't assume the bitstream |
| Terminal completely silent | TX/RX not crossed (adapter TX goes to JP3 pin 6), no shared ground, or wrong COM port |
| Text arrives as garbage | Wrong baud, or 8N1 instead of 7E1 |
| Text arrives with stray high-bit characters | 8N1 - set 7 data bits, EVEN parity |
| ENTER gets no reply but the LEDs look right | Console pins wired to the wrong JP3 pins - re-check pins 5 and 6 against the table |
| OPCOM answers, `20500&` prints nothing | No `WD0.IMG` in the card's FAT root, card not FAT32, or a long filename |
| Card silent, everything else fine | **Ground.** Re-do the meter check in step 1. Then wire length |
| `?` after a command you typed correctly | You typed it too fast - OPCOM drops characters. Retype slower |
| Design gone after a power cycle | Expected. Programming is volatile on this board; program it again |

### If it does not work at all

Two smaller test bitstreams exist in `Verilog/fpga/qmtech-a35t/` and are worth
building when the board itself becomes the suspect rather than the design:
`led-test/` (a 1 Hz heartbeat - proves clock and JTAG) and `mem-test/` (proves
the memory path). Both are written and pass in simulation; neither has run on
a board either.

### What to report back

Since nobody has run this yet, all of it is useful - including a plain "it
booted". Most useful of all:

- Did OPCOM answer on ENTER, and did `20500&` reach SINTRAN?
- **Which JP3 pin turned out to be ground?** That is the one fact in this
  document that is measured by you and by nobody before you.
- Which LED lit - and therefore whether `nd120_qmtech.xdc` or `board-pins.xdc`
  has the LED assignment the right way round.
- Anything about card reliability, with your wire lengths.
