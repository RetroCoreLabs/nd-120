# ND-120 on the Microsoft Azure FPGA card (X930613-001)

**Status: RUNS IN SIMULATION, NOT BUILT.** The whole machine (2 MB board,
console and disks over PCIe) boots in Verilator and boots a floppy image
served by the simulated PC (`make -C sim vtest`, `vtest-disk`). A Quartus
project exists (`nd120_azure.qsf`, stand-in part `5SGSMD5K2F40I3L`) but
does not build yet: the PCIe hard block, the clock PLL and checked pins
are missing, and a bitstream needs a paid Quartus licence.

Card facts, as given by Ronny - **not yet independently
verified against a datasheet or the physical card**:

| Item | Value |
|---|---|
| Product name | Microsoft Azure FPGA 40GbE QSFP+ PCIe |
| Part number | X930613-001 |
| PCB part number | DAT6MTHUEB0 |
| FPGA | Altera (Intel) **Stratix V GS** |
| Main memory | 4 GB DDR3, ECC |
| Network | 2x QSFP+ / 40GbE |
| Host interface | PCIe Gen3 x16 |

The exact Stratix V GS variant, the board's clocking and its debug access
have not been checked against a datasheet or the physical card - the table
above is Ronny's own numbers.

A third-party blog, [devops.lol](https://www.devops.lol/) (see Links,
below), identifies this same part number (X930613-001) as the **Microsoft
"Storey Peak" board (Catapult v2)** and gives more specific numbers. A
second, unsourced report added more detail; every checkable
claim in it was run against independent sources: a GitHub issue on the
`corundum` project (corundum/corundum#213), the community
reverse-engineering repo [`ruurdk/storey-peak`](https://github.com/ruurdk/storey-peak),
and [theretroweb.com](https://theretroweb.com/expansioncards/s/microsoft-azure-x930613-001-fpga-card).
Results below - **confirmed** means at least two independent sources
agree; **unverified** means only the unsourced report claims it and no
other source was found:

| Item | Value | Status |
|---|---|---|
| Codename | "Storey Peak" (Microsoft Catapult v2) | confirmed (devops.lol, corundum#213, theretroweb) |
| FPGA part | custom **5SGSKF40I3LNAC**, Stratix V GS, DSP-optimized, dual PCIe hard IP | confirmed (devops.lol, ruurdk/storey-peak) |
| PCIe | **physical x16 edge connector, but wired as two bifurcated Gen3 x8 links** - the host motherboard's BIOS **must support PCIe bifurcation** on that slot or only one x8 link (or none) will come up | confirmed (corundum#213, ruurdk/storey-peak) - resolves the x16-vs-dual-x8 mismatch between Ronny's numbers and devops.lol above: it's genuinely both, and bifurcation support is a new hard requirement not in either original report |
| Memory | **4 GB usable ECC** (4.5 GB raw before ECC), DDR3L, 72-bit bus (64 data + 8 ECC), 9x SK Hynix `H5TC4G83BFR` chips | confirmed (corundum#213, ruurdk/storey-peak) |
| Debug access | on-board **FTDI FT232H**, USB-to-JTAG, **no PCB modification or external programmer needed** - Quartus/OpenOCD can use it via community driver/library work | confirmed (devops.lol, corundum#213, ruurdk/storey-peak) |
| Toolchain | **Quartus Prime Standard required** - Quartus Lite's free tier stops at Cyclone V/MAX 10 (which is why the `mister/` DE10-Nano board in this repo gets free tooling and this one doesn't) | confirmed - Stratix V is absent from every Lite device list checked, and Quartus's own Docker image tagged `-all` was pulled and queried directly: it ships only Cyclone V + MAX 10 device files, zero Stratix V |
| GPIO | **none** on the standard interfaces - devops.lol's author rewired a UART through the QSFP+ module's I2C pins to get any general-purpose signal off the board | devops.lol only, unverified elsewhere |
| Onboard flash size | the unsourced report claimed "~256 Mbit (32 MB) NOR flash" for persistent config | **unverified - no source found for this number**, treat as a guess until checked against the board itself or a schematic |
| Logic capacity (~457K LE / ~172K ALM / ~40 Mbit BRAM) | the unsourced report gave these as "approximate capacity" | **unverified** - 457K LE appears in devops.lol too, but the ALM and BRAM numbers have no independent source |
| Known issues (devops.lol author's) | dual-PCIe-IP selection needed DLL shimming on Windows; Nios II/Eclipse toolchain flaky; DDR3 bus deadlocks were hit building a LiteX-based SoC | devops.lol only, unverified elsewhere |

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
| [`docs/01-prior-work.md`](docs/01-prior-work.md) | What other people did with these cards: devices chosen, tools, pin and clock facts, problems - none says which licence they used |
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
