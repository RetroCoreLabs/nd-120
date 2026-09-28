# Azure FPGA (X930613-001) - plan

**Status: not started.** No Quartus project, no PCIe endpoint Verilog, no
console driver exist yet anywhere in this repo. Everything below the
"Open questions" section is a **design intent**, written from facts
verified against multiple independent sources (see
[`../README.md`](../README.md)) - it is not a working procedure yet.

## Open questions (blocking everything else)

1. **Does Ronny have the physical card, and a host machine confirmed
   compatible?** CONFIRMED 31-AUG-2026: the reported host (i7-12700,
   ASUS PRIME Z690-P WIFI D4) has its CPU-connected slot
   (`PCIEX16(G5)_1`) explicitly listed as supporting **2 (X8+X8)**
   bifurcation in ASUS's own official "Intel 600 Series" bifurcation
   table (linked from ASUS support FAQ #1037507, cross-checked against
   the real E19403 user manual pulled from ASUS's CDN - both agree). That
   slot is normally occupied by the GTX 1080, so using it for this card
   means either swapping the GPU out or finding a second, GPU-free x16
   physical slot elsewhere in the case. The chipset-connected slots are
   electrically x4-only per the same manual - not sufficient for this
   card's dual-x8 requirement.
   Still open: (a) the actual BIOS menu path to turn bifurcation on -
   ASUS frames it around their Hyper M.2 card, not a generic PCIe device,
   so the toggle needs to be found by hand in the real BIOS; (b) whether
   a non-Hyper-M.2 PCIe device negotiates correctly across that split -
   electrically it should (x8/x8 is standard PCIe), but this is unproven
   until the card is actually seated and tested.

   **GPU relocation (31-AUG-2026, from the real E19403 manual, page
   1-7):** the board has 4 physical x16-length slots. Slot 1
   (`PCIEX16(G5)`, CPU-connected, currently holds the GTX 1080) is the
   only one that's electrically x16 and the only one that bifurcates to
   x8+x8 - it has to be freed for the Azure card. Slots 2-4
   (`PCIEX16(G3)_1`, `PCIEX16(G4)`, `PCIEX16(G3)_2`) are all chipset-fed
   and capped at x4 electrical. Per the layout diagram, slot 2 sits with
   almost no gap under slot 1 - too tight for two cards with coolers.
   **Slot 3 (`PCIEX16(G4)`) is the better destination for the GPU** (real
   clearance from slot 1 in the diagram); slot 4 has even more room if
   slot 3 turns out tight in the actual case. Moving the GPU there drops
   it to PCIe 3.0 x4 - a real bandwidth cut, not benchmarked for this
   card here. The manual also states: *"If you want to use two or more
   high-end PCI Express x16 cards, use a PSU with 1000W power or
   above"* - Ronny's PSU wattage is unconfirmed, check before doing this.
2. Primary source for the card's specs beyond what's now cross-verified -
   ideally the card in hand, or `ruurdk/pp-sp-reference-design` for the
   FPGA pinout (see Links in `../README.md`).
3. Confirm Quartus Prime **Standard** is available/licensed - Quartus
   Lite does not list this custom Stratix V part.
   **Docker route TESTED and RULED OUT (31-AUG-2026):** pulled the
   official `alterafpga/quartus-std:25.1std-all` image (5.64 GB) and
   queried it directly (`get_family_list` in `quartus_sh`) rather than
   trusting the tag name. Despite being called "-all", it only has
   **Cyclone V** and **MAX 10** device files installed - zero Stratix V
   parts (`STRATIXV_COUNT: 0`, measured). No `stratixv` tag exists on
   Docker Hub for this image either (only `-all`, `-cyclonev`,
   `-max10`). **Next thing to try instead: the native Windows/Linux
   Quartus Prime Standard installer**, which lets you pick device-support
   packages explicitly at install time - that's the standard path to get
   Stratix V, and hasn't been tried yet.
4. Onboard NOR flash size - still unverified (see README) - decides
   whether persistent (power-on) configuration is possible at all, or
   whether every session starts with a fresh JTAG load.
5. Whether the community JTAG tooling (`ruurdk/storey-peak`,
   j-marjanovic's FT232H-as-JTAG work) works as-is on Ronny's setup, or
   needs porting/rebuilding.

## Planned workflow (design intent - NOTHING below is built)

### Build

- New Quartus Prime Standard project in this folder, targeting the
  standard-catalog equivalent part `5SGSMD5K1F40C1` in place of the real
  custom marking `5SGSKF40I3LNAC` - now confirmed by two independent
  sources (devops.lol and `ruurdk/sv_second_pcie_hip`'s own README title).
- **Second PCIe hard IP is deliberately disabled by Quartus's stock
  device database for this part** (confirmed, `ruurdk/sv_second_pcie_hip`
  README) - Microsoft had it fused/flagged off. Getting the full
  bifurcated x8+x8 (not just one x8 link) requires an `LD_PRELOAD` shim
  that patches a symbol in `libddb_dev.so` to force global ID `1174964`
  ("forbidden PCIe block") to report enabled, then launching Quartus
  itself under that preload. Source + working C code:
  <https://github.com/ruurdk/sv_second_pcie_hip> (Linux) /
  `sv_second_pcie_hip_windows` (Windows variant, not yet checked).
- **Licensing (31-AUG-2026, re-checked directly with an Altera source):**
  intel.com and altera.com themselves blocked every direct fetch attempt
  (bot protection, both curl and the fetch tool - the archived copy
  found was also temporarily down), so this is confirmed via an
  **official Altera distributor's own FAQ** (Macnica), not Altera's page
  directly: *"A free 30-day evaluation of all the features of Quartus
  Prime Standard Edition"* - broader than earlier assumed, the eval
  unlocks the full feature set, not just synthesis/fitter/timing. The
  only thing blocked: *"generation of files for programming is not
  supported"* (no `.sof`/`.pof`/`.jic` output) - matches the earlier
  finding, now from a second source. **New caveat: "the evaluation
  function cannot be reused on the same computer"** - the 30-day clock
  is a one-time thing per machine, not something to reset and restart
  freely, so don't burn it carelessly on early experiments.
  Not confirmed: whether device-family selection or the second-HIP
  `LD_PRELOAD` unlock are themselves license-gated - no source checked
  states this explicitly either way, this is inference only.
  Separately: none of the primary hobbyist sources (j-marjanovic's blog
  series, devops.lol) mention licensing at all anywhere - scanned every
  part, zero hits - so it's unknown whether they used a paid license, a
  work license, or ran unlicensed themselves.
- **Open-source alternative to Quartus: checked, does not exist for this
  chip (31-AUG-2026).** Yosys's two Intel/Altera synthesis backends were
  read directly: `synth_intel` covers only MAX 10/Cyclone 10 LP/Cyclone
  IV(E); `synth_intel_alm` (the modern ALM-architecture backend) covers
  **Cyclone V only** - Stratix V isn't in either device list, and neither
  backend has an open-source place-and-route step behind it (no
  `nextpnr` integration for Altera, unlike the Tang Nano's mature
  yosys+nextpnr+apicula Gowin flow). Separately confirmed: none of the
  hobbyist sources use or mention an open-source alternative anywhere -
  OpenOCD appears only as the FT232H JTAG initializer, not a
  synthesis/PnR substitute. LiteX (mentioned only in the earlier
  unsourced report, not the primary hobbyist sources) is a SoC
  build-automation framework, not a synthesis/PnR replacement - its own
  Altera backend still calls out to Quartus, so it doesn't avoid the
  licensing requirement either. **Quartus Prime Standard remains the
  only road to synthesizing anything for this chip.**
- Real-world Quartus versions seen in use by the hobbyist repos:
  `$HOME/altera/15.0/quartus/linux64` and
  `/opt/intelFPGA/19.1/quartus/linux64` paths appear in
  `jtag-quartus-ft232h`'s README - so 15.0 and 19.1 are proven working
  versions, not necessarily the newest 25.1 checked earlier in this plan.
- Reuse the existing shared Verilog tree unchanged
  (`Verilog/DELILAH-CPU/`, `Verilog/CPU-BOARD-3202/`, etc.) - only a new
  board-specific top level and Quartus IP instantiation live here, same
  split every other board folder already follows.
- Quartus IP catalog for the two vendor-specific hard blocks this board
  needs that no other board in this repo has: **PCIe hard IP** (Gen3 x8;
  only one of the two bifurcated links needs to be brought up first) and
  a **DDR3 EMIF/UniPHY core** for the 9-chip, 72-bit ECC memory (see
  README for the confirmed chip list).
- Study `ruurdk/storey-peak` and `ruurdk/pp-sp-reference-design` first -
  they may already have a working PCIe-IP Quartus config for this exact
  part, which would save re-deriving pin/IP settings from scratch.

### Flash (load the bitstream)

- Quartus does not recognize the onboard FTDI FT232H as a USB-Blaster
  out of the box. Confirmed working recipe from
  `ruurdk/jtag-quartus-ft232h`'s own README (Linux): (1) run **OpenOCD
  once** to initialize the FT232H's MPSSE mode
  (`openocd -f interface/ftdi/um232h.cfg -c "adapter speed 2000;
  transport select jtag; jtag newtap auto0 tap -irlen 10 -expected-id
  0x029070dd; init; exit;"`), which also confirms the JTAG IDCODE
  `0x029070dd` matches this Stratix V part; (2) build and copy
  `libjtag_hw_otma.so` into Quartus's `linux64` plugin directory; (3) add
  a udev rule (vendor `0403`, product `6014`) so the USB device is
  accessible without root. A Windows variant
  (`jtag-quartus-ft232h-windows`) exists too, not yet checked in this
  plan.
- A JTAG `.sof` load is **volatile** - gone at power-cycle, same as
  every other board here. Whether a persistent (power-on) config path
  exists depends on open question 4 above (flash size unverified).

### Console (this board has no UART - has to be built new)

No board in this repo currently has a PCIe-based console; every other
target uses a direct UART. For this card, OPCOM's usual direct-UART path
has nowhere to attach (open GPIO question in the README), so the console
has to ride PCIe instead:

- FPGA side: a small register block behind the PCIe hard IP's BAR
  (exact BAR/offset layout is an **open design decision**, not yet made -
  a TX FIFO + RX FIFO + status register is the obvious shape, but this
  needs designing, not assuming).
- Host side: a small Windows/Linux program that maps the BAR and
  bridges it to a terminal (stdin/stdout, or a TCP/Telnet listener like
  RetroTerm already speaks to other ND machines) - this does not exist
  yet and would be new code, not a port of anything in this repo.
- The `corundum` project (referenced in corundum#213, which documents
  this exact card) already has a working PCIe driver stack for Storey
  Peak-class cards worth reading before writing one from scratch.

## Next step

Answer open questions 1-5 above - starting with #1 (bifurcation support
on Ronny's actual motherboard), since if that's a dead end the rest of
this plan doesn't matter until either the BIOS supports it or a
different host motherboard is used.
