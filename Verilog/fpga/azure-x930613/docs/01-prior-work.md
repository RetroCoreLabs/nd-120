# Prior work - people who programmed these cards

What other people did with the Microsoft Catapult v2 Stratix V cards:
**Storey Peak** (PCIe card, X930613-001 - this board) and **Pikes Peak**
(mezzanine card, X900563-001, same FPGA family). Every source below was
read in full (not from search snippets) unless marked. Nothing here was
measured on our card.

**The one fact that matters for licensing: no source says which Quartus
licence was used.** No author mentions buying a Standard licence, a free
one, or the evaluation. The only licence sentences found are about other
things (see j-marjanovic parts 3 and 4).

## Summary

| Source | Card | Quartus version | Licence stated? | What ran |
|---|---|---|---|---|
| [devops.lol azure-fpga](https://www.devops.lol/azure-fpga/) | Storey Peak | Standard, no number | not stated | Nios II bring-up test, LiteX SoC to its BIOS |
| [devops.lol fpga-adventures](https://www.devops.lol/fpga-adventures/) | overview | not stated | not stated | nothing described |
| [j-marjanovic part 1](https://j-marjanovic.io/stratix-v-accelerator-card-from-ebay.html), [part 2](https://j-marjanovic.io/stratix-v-accelerator-card-from-ebay-part-2.html) | Pikes Peak | not stated | not stated | power-up; PCIe enumerated, only 2.5 GT/s x1 |
| [j-marjanovic part 3](https://j-marjanovic.io/stratix-v-accelerator-card-from-ebay-part-3.html) | Pikes Peak | not stated | only GPL v2 for his own JTAG code | LED blink, JTAG reads, Nios II |
| [j-marjanovic part 4](https://j-marjanovic.io/stratix-v-accelerator-card-from-ebay-part-4.html) | Pikes Peak | not stated | "evaluated for an hour" - the 40G Ethernet IP, not Quartus | 40G Ethernet link to an Intel X710 |
| [pp-sp-reference-design `.qsf`](https://raw.githubusercontent.com/ruurdk/pp-sp-reference-design/master/project/otma_bringup.qsf) | see below | 19.1.0 Standard | not stated | Nios II, DDR3, PCIe design |
| [jtag-quartus-ft232h](https://github.com/j-marjanovic/jtag-quartus-ft232h) | both | 15.0 / 19.1 (example paths) | GPL-3.0 (the repo itself) | JTAG programming |
| [sv_second_pcie_hip_windows](https://github.com/ruurdk/sv_second_pcie_hip_windows) | Storey Peak | 22.1std (from an example path only) | not stated | second PCIe hard IP placed |
| [wirebond/catapult_v2_pikes_peak](https://github.com/wirebond/catapult_v2_pikes_peak) | Pikes Peak | "no support for such part in Quartus Prime 18.0" | not stated | OpenOCD ID check |
| [corundum #213](https://github.com/corundum/corundum/issues/213) | both | not stated ("installed and patched") | not stated | builds only, nothing reported running |

Searches of Hackaday, Reddit, ServeTheHome, EEVblog, Hacker News and YouTube
found no further write-ups.

## devops.lol (Ruurd Keizer) - the Storey Peak write-up

- Quartus Prime Standard on Windows ("as Lite and Pro don't support this
  Stratix V part"); LiteX under WSL.
- **Device chosen in Quartus: `5SGSMD5K2F40I3L`**, the nearest listed part
  to the real custom `5SGSKF40I3LNAC`. (The reference `.qsf` below uses
  `5SGSMD5K1F40C1`; docs/00-plan.md has used that one - which of the two
  is right for our card is not settled.)
- The reference design needs BOTH PCIe hard blocks; stock Quartus allows
  one. Fixed with a replacement `ddb_dev.dll` (his first try, DLL
  injection, was flagged as a virus by Windows).
- Saved the factory image first: as `.jic` from Quartus, and by reading
  the flash chip with a CH341a programmer and a test clip. **Do the same
  before loading anything on our card.**
- Loading: FT232H driver swapped to WinUSB with Zadig; OpenOCD run once to
  set the chip up
  (`openocd -f interface/ftdi/um232h.cfg -c "adapter speed 2000; transport select jtag; jtag newtap auto0 tap -irlen 10 -expected-id 0x029070dd; init; exit;"`);
  his JTAG library in Quartus `bin64`; then Quartus Programmer. The
  Quartus JTAG server got in the way: he turned it off in Component
  Services and stopped `jtagserver.exe`.
- He loaded a design built for the OTHER card's pins by mistake; no damage
  was seen.
- No GPIO pins: the UART goes out over the I2C pins of a QSFP cage, via a
  re-soldered SFP28 module in a QSFP+ adapter. (Our plan uses the PCIe
  console instead.)
- **Unsolved: the DDR3 controller hung the LiteX CPU** once on its bus.

## The two stand-in parts compared

Source: an answer from ChatGPT that Ronny passed on. **Not checked
against an Altera datasheet** - treat every number as a claim until it is.
Its prices come from FPGAKey's single-piece catalogue; no in-stock price
was found at Mouser or Digi-Key for either part (Digi-Key lists the
replacement 5SGSMD5K2F40I3LG at USD 18,222, zero stock).

| | `5SGSMD5K2F40I3L` (devops.lol) | `5SGSMD5K1F40C1` (reference `.qsf`) |
|---|---|---|
| Catalogue price, one bare chip | USD 8,109-9,010 | USD 11,057-12,286 |
| Core speed grade | 3 | 1 (faster) |
| Serial transceivers | 36 x 12.5 Gb/s max | 36 x 14.1 Gb/s max |
| Core voltage | 0.85 V | 0.90 V |
| Temperature grade | industrial | commercial |
| Lifecycle | obsolete | obsolete |

Same for both (same claim): 457,000 logic elements, 172,600 ALMs, about
690,000 registers, **2,014 M20K block RAMs**, 3,180 18x18 multipliers
(1,590 at 27x27), **one PCIe hard IP block**, 696 user I/Os, 1,517-ball
40 x 40 mm BGA.

What follows from it for this board (my reading, not measured):

- **Speed grade.** The real chip's marking `5SGSKF40I3LNAC` ends in `I3L`,
  like `5SGSMD5K2F40I3L` - industrial, speed grade 3, 0.85 V. Building for
  `5SGSMD5K1F40C1` (speed grade 1) would let Quartus time the design
  against a FASTER chip than the one on the card, so its timing report
  would be too optimistic. Unless the card is shown to be speed grade 1,
  `5SGSMD5K2F40I3L` is the safer choice for V5. Not decided.
- **Block RAM.** 2,014 x 20 Kbit is about 40 Mbit, about 5 MB - enough for
  the plan's 2 MB of ND memory in block RAM, if the custom part has the
  same RAM as the stand-in (not checked).
- **"One PCIe hard IP block"** matches the stock Quartus device database
  (the second one is the block the `ddb_dev` / LD_PRELOAD shim unlocks).
  Whether the silicon has two is what that shim relies on; the card's x8+x8
  wiring says it does.

## j-marjanovic.io (Jan Marjanovic) - Pikes Peak, four parts

- Part 1: FPGA markings removed; the FPGA configures itself from flash in
  about 1 s; a 12 V current-limit switch stayed off and was bypassed.
- Part 2: EEPROM names the card "PPFPGA", X900563-001; built an adapter for
  the server tray connector (first version: connector rotated, TX/RX
  swapped); enumerated as "Microsoft Corporation Device b100" but trained
  only at 2.5 GT/s x1.
- Part 3: **JTAG ID `0x029070dd`, IR length 10**; Quartus shows the chip as
  `5SGSMD5H(1|2|3)|5SGSMD5K1`. Wrote the FT232H Quartus cable library.
  **Clocks: a 125 MHz oscillator; an IDT8N4Q001 gives 644.53125 MHz on
  CLK_R_REFCLK5 (pins T7/T6), reprogrammed by him to 156.25 MHz.** LED
  blink, System Console over JTAG, Nios II over the JTAG UART.
- Part 4: 40G Ethernet at 40 Gbps to an Intel X710, eye scan on all four
  lanes, SignalTap captured an ARP packet. "Without an appropriate license
  this IP can be evaluated for an hour" - about the Ethernet IP only.

## The reference design's `.qsf` (pin facts)

From `project/otma_bringup.qsf` in `ruurdk/pp-sp-reference-design`, a fork
of j-marjanovic's Pikes Peak design. **Not checked: whether these pins are
the same on Storey Peak** - the repo is named for both cards, but the
`.qsf` came from the Pikes Peak work. Check against the card before using.

| Signal | Pins | Standard |
|---|---|---|
| Device | `5SGSMD5K1F40C1` | `LAST_QUARTUS_VERSION 19.1.0 Standard Edition` |
| CLK_125M | M23 | SSTL-135 |
| PCIe reference clocks | AF6/AF5, AF34/AF35 | HCSL |
| QSFP oscillator clock | T7/T6 | LVDS |
| 8 LEDs | A11, A10, B10, C10, C9, C8, B8, A8 | 2.5 V |
| DDR3 | 72 DQ, 9 DQS, 16 address lines, RZQ on B34 | |
| I2C | IDT clock chip N7/P7; QSFP0 AB24/AC24; QSFP1 AA25/AB25; temperature sensors AW26/AV26 | |
| UART | none in the file | |

## Tools

- [jtag-quartus-ft232h](https://github.com/j-marjanovic/jtag-quartus-ft232h)
  (Linux): build with cmake, copy `libjtag_hw_otma.so` into Quartus
  `linux64`, udev rule for USB ID 0403:6014. OpenOCD must be run first
  every time - the library does not set the chip up itself. A 26 MB
  bitstream loads in 3 min 51 s at 2 MHz, 1 min 54 s at 20 MHz.
- [sv_second_pcie_hip_windows](https://github.com/ruurdk/sv_second_pcie_hip_windows):
  replacement `ddb_dev.dll` built in Visual Studio 2022; the original is
  renamed `ddb_dev_orig.dll`. The Linux version
  ([sv_second_pcie_hip](https://github.com/ruurdk/sv_second_pcie_hip))
  uses LD_PRELOAD; not opened in this pass.
- wirebond: OpenOCD over the FT232H with TCK D0, TDI D1, TDO D2, TMS D3;
  also a USB ByteBlaster soldered to test points. `docs/fpga_io.xlsx` did
  not open.

## Not read

- `jtag-quartus-ft232h-windows` (the blog spells the link "ft323h").
- The full raw README of the j-marjanovic reference design (only a summary
  came back).
- No j-marjanovic part 5 was found.
