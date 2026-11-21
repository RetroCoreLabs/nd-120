# ND-120 on the Microsoft Azure FPGA card (X930613-001)

**Status: RUNS IN SIMULATION, NOT BUILT.** The whole machine (2 MB board,
console and disks over PCIe) boots in Verilator and boots a floppy image
served by the simulated PC (`make -C sim vtest`, `vtest-disk`). A Quartus
project exists (`nd120_azure.qsf`, stand-in part `5SGSMD5K2F40I3L`) but
does not build yet: the PCIe hard block, the clock PLL and checked pins
are missing, and a bitstream needs a paid Quartus licence.

## The card: what is known, and where it comes from

Every line below names its source. Three kinds of statement are kept
apart: **official** (an Intel/Altera document), **community** (people who
took the card apart - nearly all of it from one person, Ruurd Keizer, who
writes devops.lol and keeps `ruurdk/storey-peak`, plus j-marjanovic's pin
file), and **NOT FOUND**. No Microsoft schematic or datasheet for the card
has been found, so nothing here is checked against one, and nothing is
checked against our own card yet.

Sources: **[BOM]** <https://github.com/ruurdk/storey-peak/blob/main/BOM.md>
(part list read from chip markings) - **[SP]**
<https://github.com/ruurdk/storey-peak> - **[QSF]**
<https://github.com/j-marjanovic/pp-sp-reference-design/blob/master/project/otma_bringup.qsf>
and **[SDC]** `.../constraints/timing.sdc` in the same repo (a test design
shared by Pikes Peak and Storey Peak) - **[DL]**
<https://devops.lol/azure-fpga/> - **[FW]**
<https://github.com/ruurdk/storey-peak/blob/main/firmware/README.md>
(flash read-out) - **[C213]** <https://github.com/corundum/corundum/issues/213> -
**[PP]** <https://github.com/wirebond/catapult_v2_pikes_peak> (the sister
card) - **[DO]** Altera *Stratix V Device Overview*, SV51001, 2015.10.01
(Intel's copy: <https://www.intel.com/content/www/us/en/docs/programmable/683258/current/stratix-v-family-plan.html>;
read from a mirror because intel.com returned 404).

### Identity

| Item | Value | Source |
|---|---|---|
| Product | Microsoft Azure FPGA card, part X930613-001, PCB DAT6MTHUEB0 | label on Ronny's card |
| Codename | "Storey Peak", Microsoft Catapult v2 | community: [DL], [SP], [C213] |
| Sister card | "Pikes Peak" - its PCB, heatsink and mezzanine PCIe do NOT apply to this card | community: [PP] |

### The FPGA

| Item | Value | Source |
|---|---|---|
| Marking on the chip | `5SGSKF40I3LNAC` - a custom Microsoft marking, not in Intel's catalogue | community, as text: [SP], [DL], [PP]. No source describes a photo of the chip top that we have looked at |
| What the marking decodes to | `5SGS` Stratix V GS, `K` 36 transceivers, `F40` 1517-ball FineLine BGA, `I` industrial (-40 to 100 °C), `L` low power, `N` lead-free | official code scheme: [DO] Figure 2 p.20 |
| What it does NOT say | the variant letter (M/E), the family member (D5), the transceiver speed digit; `3` is probably the core speed grade by position (a guess); `AC` is not in Altera's scheme | [DO] Figure 2 |
| JTAG ID | `0x029070dd`, IR length 10; Quartus lists it as `5SGSMD5H(1|2|3)` / `5SGSMD5K1` | community: [DL], [PP]. Intel's ID table could not be read (404), so NOT checked officially |
| Two PCIe hard blocks | yes, two x8 links (PCIE1, PCIE2, each its own reset pin) - a catalogue D5 "M" part has ONE; Quartus's device data disables the second, needs a patch (docs/00-plan.md) | community: [DL], [QSF]; one per "M" part: [DO] |

**Catalogue Stratix V GS D5 figures** - official, from [DO] Table 4 pp.7-8.
They are the figures for the stand-in part. **That the custom chip has the
same numbers is NOT confirmed** (only the JTAG ID points to D5).

| Item | D5 |
|---|---|
| Logic | 457K logic elements, 172,600 ALMs, 690K registers |
| Block RAM (M20K) | **2,014 blocks, 39 Mbit** |
| Small RAM (MLAB) | 640 bits each ([DO] Table 1); total for D5 NOT FOUND |
| Multipliers | 3,180 of 18x18, or 1,590 of 27x27 (DSP block count NOT FOUND) |
| Transceivers | 36 in the F40 package, up to 14.1 Gbit/s ([DO] Table 7: 12.5 for backplane) |
| PCIe hard IP | 1 per "M" part, Gen1/2/3, up to x8 |
| User I/O, F40 | 696 (174 LVDS pairs); 24 fractional PLLs |
| Core voltage | 0.85 V or 0.9 V ([DO] Table 1). Which grade uses which: from datasheet mirrors only, NOT checked officially |

What this means for the ND-120 build: the 2 MB main memory is 1M words
x 16 bits = 16 Mbit, about 1,024 M20K blocks (planned, not yet measured
in a fit report) - half of the catalogue part's 2,014.

### Memory and flash on the card

| Item | Value | Source |
|---|---|---|
| DDR3 chips | 9 x SK Hynix H5TC4G83BFR, 4 Gbit each, DDR3L 1.35 V, at U46/48/50/52/54/56/58/60/64 | community: [BOM] (written "HSTC4G83BFR", a typo) |
| DDR3 bus | 72 bits = 64 data + 8 ECC, pins SSTL-135 (1.35 V), 9 strobe pairs | community: [SP], [PP], [QSF] |
| DDR3 size | 9 x 4 Gbit = 4.5 GB raw, 4 GB usable with ECC | arithmetic; also [C213] |
| DDR3 speed | NOT FOUND for this card (the speed letters after "BFR" were not read). A distributor lists the part as 1866 MT/s, x8 width from the name - not checked in Hynix's datasheet | - |
| Used by the ND-120? | **No.** This build keeps main memory in block RAM; DDR3 is a later option | this repo |
| Config flash | Micron N25Q256A (256 Mbit = 32 MB serial NOR), SOIC-16, at U2; the FPGA loads from it at power-up | community: [BOM], [FW] (flashrom read-out), [DL] |
| Flash mode (x1 or x4) | NOT FOUND | - |
| Other memory | ST 128-kbit I2C EEPROM at U16 (address 0x51) | community: [BOM] |

### Clocks

| Item | Value | Source |
|---|---|---|
| Main oscillator | 125 MHz (TXC, OSC2), pin M23 | community: [BOM], [QSF] |
| QSFP clock | IDT8N4Q001 programmable, 644.53125 MHz at power-up, pins T7/T6, I2C 0x6E | community: [BOM], [QSF], [SDC] |
| PCIe reference | 2 x 100 MHz, pins AF6/AF5 and AF34/AF35, through a Pericom PI6CEQ200 (U9) | community: [QSF], [SDC], [BOM] |
| 12 MHz crystal Y1 | probably the FT232H's - a guess | [BOM] says "12 MHz?" |

### Connections

| Item | Value | Source |
|---|---|---|
| PCIe | x16 edge connector, wired as two Gen3 x8 links; the PC's slot must support splitting (bifurcation) | community: [SP], [BOM], [C213] |
| Network | 2 x QSFP+ 40G cages, straight to FPGA transceivers, 4 lanes each | community: [BOM], [SP], [QSF]. [C213] says "SFP+", which the others contradict |
| USB / JTAG | FTDI FT232H (U3); OpenOCD drives it as a JTAG cable; a TI TS3USB221 switch (U75) picks between internal USB J3 and external CN1; JTAG header J5 | community: [BOM], [DL], [C213] |
| Console / GPIO | none - devops.lol ran a UART over a QSFP cage's I2C pins | community: [DL] |
| LEDs | 8 on A8 B8 C8 C9 C10 B10 A10 A11 (2.5 V) in the shared pin file - **not confirmed on Storey Peak** | community: [QSF] |
| Buttons | NOT FOUND | - |

### Power and other chips

| Item | Value | Source |
|---|---|---|
| Regulators | EC7100VQI (core), ER2120QI x3, ER2105DI, EN2342QI x2, EY1602 | community: [BOM] |
| Input | ES1010SI 12 V hot-swap controller - 12 V input implied, connector NOT FOUND | community: [BOM] |
| Power draw | NOT FOUND | - |
| Monitors | TI INA219 current monitor (I2C 0x41), temperature sensor "T411" (U5, 0x4C; TMP411 is a guess from the marking) | community: [BOM] |
| Other | NXP I2C repeater (U74); unidentified markings "AUPK U610", "F DG06A", "MX 6", "70H"; no CPLD or microcontroller found | community: [BOM] |

This is a much harder bring-up target than any board currently in this
repo: a non-catalog FPGA part, Quartus Prime Standard (not Lite/Pro), a
motherboard BIOS bifurcation requirement, no confirmed GPIO, and a
JTAG/UART bridge over a repurposed FTDI chip instead of a normal header.

> **Hobbyist warning: no free way to build the bitstream was found.**
> The Stratix V needs Quartus Prime Standard, whose licence is paid
> (SW-ONE-QUARTUS, about USD 3,645). Without it the design can
> be simulated, and the 30-day evaluation can check fit and timing, but
> the file that is loaded into the card (`.sof`) cannot be made. Every
> other board in this repo builds with free tools. Details and sources:
> [`docs/00-plan.md`](docs/00-plan.md), "Build".

## Why this board is a different shape from every other target

Every other board in `Verilog/fpga/` is a hobbyist devboard: it has a
UART or USB-JTAG console, a keyboard/VGA path, or an SD card, and it
powers up and runs standalone. This card is a datacenter PCIe accelerator:

- **Toolchain is different.** Every other Altera/Intel target here
  ([`../mister/`](../mister/README.md)) is Cyclone V under Quartus Lite.
  Stratix V needs full **Quartus Prime** (Standard or Pro) - Quartus Lite
  does not support Stratix V. Licensing/availability of that toolchain is
  unconfirmed.
- **No console.** Confirmed no GPIO on the standard interfaces, so OPCOM
  (the direct-UART path every other board uses first) has nowhere to
  attach - a console has to be built over PCIe instead. See
  [`docs/00-plan.md`](docs/00-plan.md) for the design intent.
- **Config is volatile via JTAG, persistence unverified.** A JTAG `.sof`
  load is volatile like every other board here. Whether onboard flash
  supports power-on auto-config is unverified - the flash-size claim in
  the table above has no confirmed source.
- **PCIe bifurcation is a new, real requirement - CONFIRMED SUPPORTED on
  Ronny's board.** The x16 edge connector is two bifurcated
  Gen3 x8 links, not a native x16 link. ASUS's own official bifurcation
  table (support FAQ #1037507) lists the PRIME Z690-P WIFI D4's
  CPU-connected slot (`PCIEX16(G5)_1`) as supporting **2 (X8+X8)** -
  cross-checked against the real E19403 user manual. That slot is
  normally occupied by the GTX 1080, so this still means either swapping
  the GPU out or finding a second GPU-free x16-physical slot; the
  chipset-connected slots on this board are x4-only and don't qualify.
  Still open: the actual BIOS menu path to enable it, and whether a
  non-Hyper-M.2 PCIe device (this card, not ASUS's own Hyper M.2 card)
  negotiates correctly across the split - electrically it should, but
  unproven until tested. See open question 1 in
  [`docs/00-plan.md`](docs/00-plan.md).
- **This does not appear to be a closed/locked platform** - multiple
  independent community projects (see Links) document working JTAG
  access and PCIe driver stacks for this exact card, which weighs against
  the "Microsoft-signed-only" concern raised earlier. Still confirm on
  Ronny's own card before relying on this.
- **No open-source escape from Quartus licensing - checked, confirmed
  absent.** Unlike the Tang Nano 20K's mature yosys+nextpnr+apicula Gowin
  flow in this same repo, Yosys's two Intel/Altera synthesis backends
  (`synth_intel`, `synth_intel_alm`) top out at Cyclone V - Stratix V
  isn't supported by either, and neither has an open place-and-route
  step behind it regardless. Quartus Prime Standard's 30-day unlicensed
  eval unlocks the full feature set (synthesis, fitter, timing) but not
  the final programming-file step, and it's a one-time window per
  machine, not resettable. Full detail and sourcing in
  [`docs/00-plan.md`](docs/00-plan.md).

## Before any Verilog work starts

See [`docs/00-plan.md`](docs/00-plan.md) for the numbered open-questions
list and the planned (not yet built) build/flash/console workflow.

## Files

| File | Purpose |
|---|---|
| [`docs/00-plan.md`](docs/00-plan.md) | Open questions, the licence findings, and the Verilog plan (what is still to build) |
| [`docs/01-prior-work.md`](docs/01-prior-work.md) | What other people did with these cards: devices chosen, tools, pin and clock facts, problems - none says which licence they used |
| [`docs/02-ddr3.md`](docs/02-ddr3.md) | The card's 4 GB DDR3: chips, speed, how a controller + cache would drive it, what code exists to reuse |
| `Makefile` | Standard board API placeholder - no build yet |
| `rtl/nd_pcie_console.v` | The console as PCIe registers (two byte queues); layout in the file header |
| `rtl/nd_pcie_storage.v` | Disk images served by the PC; drives the MiSTer `nd_storage_hps` block interface; layout in the file header |
| `rtl/pcie_bar_bus.v` | Splits the 4 KB PCIe register window: console at 0o0000, disks at 0o1000 |
| `rtl/pcie_hip_wrap.v` | The PCIe hard block behind a plain bus; simulation version only, the real-card version waits for V5 |
| `nd120_azure.qpf`, `.qsf`, `.sdc`, `files.qip` | The Quartus project; `files.qip` is also the Verilator test's file list |
| `rtl/nd120_azure_top.v` | The board top: CPU + 2 MB block-RAM board, console and disks over PCIe |
| `sim/` | iverilog tests: `make all` (`test-console`, `test-storage`, `test-bar`), all in the global suite; `make vtest` boots the whole machine in Verilator (in `make test-full`) |

## Links

| Link | What it is |
|---|---|
| <https://www.devops.lol/azure-fpga/> | Third-party blog: identifies X930613-001 as "Storey Peak" (Catapult v2), Stratix V GS `5SGSKF40I3LNAC`, JTAG/FTDI 232H debug bridge, no-GPIO/QSFP-I2C UART rewire, Quartus Prime Standard requirement |
| <https://www.devops.lol/fpga-adventures/> | Same author, broader context: how they source these ex-datacenter cards (2nd-hand market), a sibling board (Microsoft "Longs Peak" / Catapult v3, Arria 10 GT), and a QMTech Kintex-7 board for comparison |
| <https://github.com/ruurdk/storey-peak> | Community reverse-engineering repo for this exact card - JTAG-via-FT232H tooling, PCIe bifurcation confirmation, DDR3 chip-level detail. Read before writing any new Quartus/PCIe work |
| <https://github.com/ruurdk/pp-sp-reference-design> | FPGA pinout reference for Storey Peak / Pikes Peak, from the same author |
| <https://github.com/corundum/corundum/issues/213> | GitHub issue tracking a port of the `corundum` open-source PCIe NIC framework to this card family - independent confirmation of the PCIe/memory/JTAG facts above, and a working PCIe driver stack worth reading before building our own |
| <https://github.com/wirebond/catapult_v2_pikes_peak> | Sibling card (Pikes Peak, OCP mezzanine form factor, different part number) - same FPGA family, JTAG pin mapping documented |
| <https://theretroweb.com/expansioncards/s/microsoft-azure-x930613-001-fpga-card> | Card listing, used to cross-check the codename/part-number claim |
| <https://dlcdnets.asus.com/pub/ASUS/mb/LGA1700/PRIME_Z690-P_WIFI_D4/E19403_PRIME_Z690-P_WIFI_D4_V2_UM_WEB.pdf> | Real ASUS user manual (E19403, Rev V2) for Ronny's host board, pulled directly from ASUS's own CDN - confirms the expansion-slot table and the bifurcation footnote on the CPU x16 slot |
| <https://www.asus.com/support/faq/1037507/> | ASUS's official PCIe bifurcation compatibility FAQ - the linked "Intel 600 Series" table lists **PRIME Z690-P WIFI D4** by name with its CPU slot (`PCIEX16(G5)_1`) supporting **2 (X8+X8)** bifurcation, confirming Ronny's host motherboard can electrically support this card's PCIe interface |
| <https://github.com/ruurdk/jtag-quartus-ft232h> | Working driver + exact recipe for using the onboard FT232H as a Quartus JTAG interface on Linux (OpenOCD init, `libjtag_hw_otma.so`, udev rule) - confirms JTAG IDCODE `0x029070dd` matches this Stratix V part |
| <https://github.com/ruurdk/sv_second_pcie_hip> | Working `LD_PRELOAD` shim to unlock the second PCIe hard IP block, which Quartus's stock device database disables for this part by default - required for the full bifurcated x8+x8, not just one x8 link |
| <https://hub.docker.com/r/alterafpga/quartus-std> | Official Altera Quartus Prime Standard 25.1 Docker image - tested, the `-all` tag does NOT include Stratix V device files (only Cyclone V + MAX 10), ruling out this specific container as a build environment |
| <https://www.intel.com/content/www/us/en/software/programmable/quartus-prime/download.html> | Altera's Quartus download page - says Standard "requires a paid license" and lists Stratix V under it; Lite is free but stops at Cyclone V / MAX 10 / Cyclone 10 |
| <https://www.altera.com/downloads/fpga-development-tools/quartus-prime-standard-edition-design-software-version-25-1-windows> | Quartus Prime Standard 25.1 for Windows - free download with Stratix V device support; the licence is separate and paid |
| <https://www.intel.com/content/www/us/en/docs/programmable/683472/25-1/types-of-fpga-software-licenses.html> | Altera licence types (fixed / floating); Pro and Standard need a paid licence key |
| <https://www.altera.com/support/support-resources/licensing/q-and-a> | Altera Licensing Help Guide - fixed vs floating is chosen at purchase |
| <https://manuals.plus/intel/quartus-prime-design-software-manual> | Third-party listing giving Standard at USD 2,995 fixed / 3,995 floating - an OUT-OF-DATE price, see the PCN below |
| <https://cdrdv2-public.intel.com/808179/PCN118401-00.pdf> | Intel product change notice: the Standard licence part was replaced by SW-ONE-QUARTUS (Standard + Pro + Questa), USD 3,645 "subject to change" |
| <https://community.altera.com/discussions/quartus-prime/swr-quartus-se-fix-renewal-license/308507/replies/308508> | Intel staff: the Standard renewal licence was dropped for the same bundle |
| <https://community.altera.com/discussions/quartus-prime/can-someone-please-explain-the-new-one-part-number-quartus-licensing/253346> | SW-ONE-QUARTUS: fixed or floating is chosen after buying |
| <https://www.digikey.fi/en/products/detail/altera/SW-ONE-QUARTUS/15668225> | Digi-Key Finland listing, USD 3,645.02 without VAT (seen in a search snapshot, page not opened) |
| <https://www.digikey.ie/en/products/detail/altera/SW-ONE-QUARTUS/15668225> | Digi-Key Ireland listing, EUR 3,121.23 without VAT (search snapshot) |
| <https://www.mouser.dk/c/embedded-solutions/engineering-tools/development-software/?m=Altera> | Mouser Denmark, DKK 23,384.86 (search snapshot) |
| <https://community.altera.com/discussions/quartus-prime/quartus-prime-standard-purchase-eligiability/305181> | Forum question whether a private person may buy Standard - unanswered |
| <https://www.intel.com/content/www/us/en/developer/topic-technology/fpga-academic/membership.html> | Altera/Intel FPGA Academic Program membership: faculty and staff of universities, colleges and non-profit research institutes, academic e-mail required |
| <https://www.intel.com/content/www/us/en/docs/programmable/683472/22-3/university-program-software-licenses.html> | University Program software licences: licensed Standard and Pro for university labs |
| <https://community.altera.com/discussions/quartus-prime/quartus-academic-licence/306584> | Forum: students cannot be members; professors request the licences |
| <https://community.intel.com/t5/Intel-FPGA-University-Program/Temporary-licenses-for-students/m-p/1219069/highlight/true> | Forum: no temporary student licences |
| <https://community.intel.com/t5/Intel-FPGA-Software-Installation/Quartus-licence-for-educational-purposes/m-p/1577438> | Forum: the academic licence is for non-commercial use only |
| <https://community.intel.com/t5/Programmable-Devices/Need-help-identifying-an-FPGA-board/td-p/270803> | Forum: academics can ask Microsoft's academic programme for Catapult boards |
| <https://www.altera.com/products/devkit/po-3024/stratix-v-gs-dsp-development-kit> | Stratix V GS DSP dev kit, said to ship with a one-year Quartus licence (page refused direct fetches) |
| <https://www.macnica.co.jp/en/business/semiconductor/articles/intel/2063/> | Distributor (Macnica): one-year "Development Kit Edition" licence with the kits |
| <https://www.macnica.co.jp/en/business/semiconductor/articles/intel/2068/> | Macnica: Stratix V kits came with a one-year licence |
| <https://community.intel.com/t5/Intel-Quartus-Prime-Software/Can-t-generate-license-for-my-Altera-Stratix-V-Dev-board-valid/td-p/258760> | Second-hand Stratix V kit buyers: the licence form rejects the serial number |
| <https://community.intel.com/t5/Intel-Quartus-Prime-Software/Subscription-Expiration-date/m-p/1560044/highlight/true> | Intel: dev-kit licences do not last forever |
| <https://community.intel.com/t5/Programmable-Devices/One-year-time-limited-lincese/m-p/10308> | Forum: conflicting reports on what happens when the one-year kit licence ends |
| <https://community.altera.com/discussions/boards-and-dev-kits/quartus-development-kit-bundled-license/74195> | Forum thread on whether a kit licence works for other boards (page refused direct fetches; not answered here) |
| <https://microsites.altera.com/microsites/psg_microsites_migration/quartushelp/18.1/msgs/msgs/ecpt_license_outdated.htm> | Quartus help: a licence covers versions released before its maintenance end date |
| <https://community.altera.com/discussions/quartus-prime/subscription-expiration-date/318780> | Intel staff: a licence file with an expiry date stops on that date |
| <https://community.altera.com/discussions/quartus-prime/quartus-ii-no-sof-or-output-file-generated/303986> | Forum: the evaluation-mode refusal "Can't generate programming files ..." |
| <https://community.altera.com/discussions/fpga-device/-sof-not-generated/232957> | Forum: the same on a Stratix V board with the 30-day evaluation |
| <https://community.intel.com/t5/Intel-Quartus-Prime-Software/Quartus-Prime-Lite-with-NIOS2-Generates-Time-Limited-SOF-File/m-p/1301583> | `_time_limited.sof` is OpenCore Plus (IP-core trial), not a device-licence escape |
| <https://www.intel.com/content/www/us/en/support/programmable/articles/000089475.html> | Intel article on OpenCore Plus time-limited files |
| <https://community.altera.com/kb/knowledge-base/can-i-create-programming-files-for-production-stratix-v-series-devices-using-the/339214> | Stratix V production programming files need Quartus II 12.0 or later |
| <https://community.altera.com/discussions/fpga-device/quartus-ii-web-edition-for-stratix/285228> | Forum: the free Web Edition never supported the Stratix series |
| <https://community.altera.com/discussions/quartus-prime/which-stratix-devices-are-supported-by-quartus-ii-v14-web-edition/292899> | Forum: 14.0 Web Edition page listed Stratix V but the device files did not include it (unanswered; page refused direct fetches) |
| <https://www.intel.com/content/dam/www/central-libraries/us/en/documents/ss-quartussevswe-guide.pdf> | Intel Subscription vs Web Edition comparison guide |
| <https://community.intel.com/t5/Intel-Quartus-Prime-Software/Adding-Support-for-DE5-Net/m-p/1197444> | Forum: Quartus Standard 20.1 said to be the last with Stratix V |
| <https://www.intel.com/content/www/us/en/docs/programmable/683665/current/design-security.html> | Intel handbook: the Stratix V configuration format is proprietary |
| <https://github.com/wirebond/catapult_v2_pikes_peak> | Pikes Peak works with bitstreams built for 5SGSMD5H* / 5SGSMD5K*; Quartus 18.0 has no entry for the real part; licence not stated |
| <https://intel.com/content/www/us/en/developer/articles/news/devcloud-oneapi-eol-information.html> | Intel DevCloud end of life: discontinued 31-OCT-2024 |
| <https://community.altera.com/discussions/acceleration/is-intel-stratix-fpga-available-in-intel-devcloud/301698> | DevCloud FPGA nodes were Arria 10 and Stratix 10 |
| <https://www.intel.com/content/www/us/en/docs/programmable/683498/17-1/hosting-a-license-server-in-the-cloud.html> | Quartus Pro on Azure, bring your own licence (17.1 guide) |
| <https://community.intel.com/t5/Intel-FPGA-Software-Installation/What-are-the-advantages-of-purchasing-a-license-for-Quartus/td-p/1207530> | Forum: pay-as-you-go licensing in the Azure cloud |
| <https://www.intel.com/content/www/us/en/docs/programmable/683472/25-3/acquiring-free-no-cost-licenses.html> | Altera's free licences: Lite, Pro for Cyclone 10 GX / Agilex 5 E / Agilex 3, Questa Starter - no Stratix V |
| <https://community.altera.com/discussions/quartus-prime/quartus-prime-standard-19-1-evaluation-license-extension/242403> | Altera staff: the Standard 19.1 evaluation cannot be extended; go to a distributor |
| <https://community.intel.com/t5/Intel-Quartus-Prime-Software/How-can-I-request-an-extension-to-Quartus-Prime-Pro18-1-eval/td-p/221873> | Same for the Pro 18.1 evaluation |
| <https://intel.com/content/www/us/en/docs/programmable/683553/current/activating-your-software-license.html> | Kit licences are "valid only for one year" |
| <https://community.altera.com/discussions/quartus-prime/does-arria-10-soc-development-come-with-a-license-for-quartus-standard-edition-i/292206/replies/292208> | The Arria 10 SoC kit licence is for Pro |
| <https://www.microsoft.com/en-us/research/academic-program/project-catapult-academic-program/> | Microsoft Project Catapult academic programme: researchers, Stratix V machines at TACC, proposal to catapult@microsoft.com |
| <https://campustechnology.com/articles/2015/11/16/tacc-makes-microsoft-project-catapult-servers-available-to-academic-researchers.aspx> | 2015 report: free access if the code is shared |
| <https://j-marjanovic.io/stratix-v-accelerator-card-from-ebay.html> | j-marjanovic part 1 (Pikes Peak power-up) - all four parts analysed in `docs/01-prior-work.md` |
| <https://j-marjanovic.io/stratix-v-accelerator-card-from-ebay-part-2.html> | j-marjanovic part 2 (tray adapter, PCIe enumeration) |
| <https://j-marjanovic.io/stratix-v-accelerator-card-from-ebay-part-4.html> | j-marjanovic part 4 (40G Ethernet) |
| <https://raw.githubusercontent.com/ruurdk/pp-sp-reference-design/master/project/otma_bringup.qsf> | Reference design Quartus settings: device, Quartus 19.1.0 Standard, clock/LED/DDR3/I2C pins |
| <https://github.com/j-marjanovic/jtag-quartus-ft232h> | Original FT232H Quartus JTAG library (Linux) |
| <https://github.com/ruurdk/sv_second_pcie_hip_windows> | Windows replacement `ddb_dev.dll` for the second PCIe hard IP |
| <https://j-marjanovic.io/stratix-v-accelerator-card-from-ebay-part-3.html> | j-marjanovic blog, part 3: FT232H JTAG library used with Quartus Programmer on this card family; does not say which Quartus licence was used |
| <https://en.wikipedia.org/wiki/Quartus_Prime> | Overview of the Quartus editions; mentions free Pro licences for some device families, none found for Standard |
| <https://www.macnica.co.jp/en/business/semiconductor/support/faqs/intel/128229/> | Official Altera-distributor FAQ confirming Quartus Prime Standard's 30-day unlicensed evaluation terms (full features, no programming-file output, one-time per machine) - used because intel.com/altera.com themselves blocked direct fetches |
