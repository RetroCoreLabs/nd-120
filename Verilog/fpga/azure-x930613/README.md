# ND-120 on the Microsoft Azure FPGA card (X930613-001)

**Status: PAPER PLAN (31-AUG-2026).** No build files exist yet. This folder
only records the card's specs and the open questions that have to be
answered before any Verilog gets written.

Card facts, as given by Ronny (31-AUG-2026) - **not yet independently
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
second, unsourced report (31-AUG-2026) added more detail; every checkable
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
  Ronny's board (31-AUG-2026).** The x16 edge connector is two bifurcated
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
| [`docs/00-plan.md`](docs/00-plan.md) | Open questions, and the planned build/flash/PCIe-console workflow (design intent only - nothing built yet) |
| `Makefile` | Standard board API placeholder - no build yet |

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
| <https://hub.docker.com/r/alterafpga/quartus-std> | Official Altera Quartus Prime Standard 25.1 Docker image - tested 31-AUG-2026, the `-all` tag does NOT include Stratix V device files (only Cyclone V + MAX 10), ruling out this specific container as a build environment |
| <https://www.macnica.co.jp/en/business/semiconductor/support/faqs/intel/128229/> | Official Altera-distributor FAQ confirming Quartus Prime Standard's 30-day unlicensed evaluation terms (full features, no programming-file output, one-time per machine) - used because intel.com/altera.com themselves blocked direct fetches |
