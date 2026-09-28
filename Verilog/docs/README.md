# Verilog/docs - index

Design notes, references, open plans and solved-problem write-ups for the
ND-120 Verilog work. Every tracked file in this folder is listed below once.
Links are relative to this folder (repo-root path `Verilog/docs/<file>`).

The one-line hooks say what each file is for. They are not a re-check of its
claims: open the file, and trust the RTL and the cited manuals over any
summary. Finished work is kept only as a short root-cause record; the full
history of any deleted handoff or plan is in git.

## Start here

- [`nd120-facts.md`](nd120-facts.md) - the machine invariants that keep
  getting re-derived (address spaces, console registers, interrupt sources,
  WCS layout, board differences, software behaviour), each with its source.
- [`build-defines.md`](build-defines.md) - every build option: Verilog
  defines, sim make variables, per-board build arguments (Nexys, Tang,
  Basys3, MiSTer, MEGA65, QMTECH, Cmod A7), runSim environment variables.
- [`PREREQUISITES.md`](PREREQUISITES.md) - every tool the repo needs, how to
  install it and how to check it.
- [`RETRACTED.md`](RETRACTED.md) - claims that were believed and then
  disproved; read before trusting an old doc or code comment.
- [`SIGNALS.md`](SIGNALS.md) - evidence-tagged dictionary of the cycle and
  control-store signals (what each is, who drives it, how we know).

## Bus protocol - IOX / IDENT / DMA

- [`nd100-bus-deck.pptx`](nd100-bus-deck.pptx) - 16-slide deck covering all
  bus phases: IOX read/write, IDENT poll, DMA read/write, the recovery gap,
  and CPU-vs-DMA arbitration. Verbatim ND-06.016.01 manual text on each
  slide; the timing waveforms are drawn reconstructions - trust the RTL and
  the manual over the drawing.
- [`nd100-bus-dma.md`](nd100-bus-dma.md) - the ND-100 bus and DMA spec from
  ND-06.016.01 (section 10.8 is the BREQ lifecycle). Read before touching
  `../ND-BUS-DEVICES/DMA/circuit/ND_DMA_MASTER.v`.
- [`device-address-map.md`](device-address-map.md) - base address, ident
  and interrupt level of every Verilog ND-bus device.
- [`nd100x-device-semantics.md`](nd100x-device-semantics.md) - nd100x device
  semantics (interrupts, IDENT, floppy, SMD) used as a first reference for
  the Verilog devices.

Device READMEs and validation plans that build on the above:
`../ND-BUS-DEVICES/README.md`, `../floppyTester/PLAN-P3-dma-master-validation.md`,
`../floppyTester/CONFORMANCE.md`.

## Storage - SD card, floppy, SMD, Winchester, tape

- [`nd-storage-interface-spec.md`](nd-storage-interface-spec.md) - the
  client-port contract of the SD storage block as built (block cache, direct
  tape/floppy, write-through, FAT walk).
- [`nd-storage-design.md`](nd-storage-design.md) - as-built design of
  `nd_storage`: region map, engine with FAT-chain walk, mount, block cache,
  adapters, byte order, clock crossing, ports.
- [`sd-bpun-device-plan.md`](sd-bpun-device-plan.md) - reference: tape-400
  register spec and BPUN format, how an IOX reaches a bus device, SD slot
  pins.
- [`sd-cmd18-block-gap-research.md`](sd-cmd18-block-gap-research.md) - SD
  spec timing facts for CMD18/CMD25 bursts, the `sd_writer` fixes taken, and
  the SD speed facts.
- [`fat-reader-slimming-plan.md`](fat-reader-slimming-plan.md) - measured LUT
  breakdown of `sd_file_reader` and the slimming levers (two done, one not
  applicable, raw-LBA boot open).
- [`verilator-sd-storage-boot.md`](verilator-sd-storage-boot.md) - booting
  SINTRAN in Verilator through the real SD/FAT stack (`probe-wd-sd`).
- [`usb-storage-options.md`](usb-storage-options.md) - option study for USB
  flash storage (CH376 / MAX3421E / soft CPU / none); not decided.
- [`floppy-3112-register-spec-ND-11.021.md`](floppy-3112-register-spec-ND-11.021.md) -
  manual-quoted register spec of the 3106/3112 floppy controller (two
  status words).
- [`floppy-review-findings.md`](floppy-review-findings.md) - the open items
  from the 12-JUL floppy review.
- [`HANDOFF-floppy-pio-c-and-csharp-fixes.md`](HANDOFF-floppy-pio-c-and-csharp-fixes.md) -
  open work order for the PIO floppy models in the nd100x (C) and RetroCore
  (C#) repositories.
- [`BUG-tape400-sd-level12-storm.md`](BUG-tape400-sd-level12-storm.md) -
  solved: the C tape model never raised its interrupt lines and printed per
  byte.

## CPU - microcode, instructions, interrupts

- [`boot-golden-spec.md`](boot-golden-spec.md) - the microcode boot flow
  phase by phase, and how to spot a boot divergence in a trace.
- [`INSTRUCTION-verifier-TPE-run.md`](INSTRUCTION-verifier-TPE-run.md) - how
  to run the TPE INSTRUCTION verifier from the floppy, the expected banner
  and test groups, the sim-only RTC hazard.
- [`CATALOGUE-benign-oracle-differences.md`](CATALOGUE-benign-oracle-differences.md) -
  known harmless differences (B1-B7) when comparing our traces with nd100x,
  and the compare rules.
- [`MPY-dynamic-overflow-rootcause.md`](MPY-dynamic-overflow-rootcause.md) -
  solved: MPY overflow was the QREG MUXQ15 D3 wiring; regeneration hazard,
  probe recipe.
- [`SHIFT-serial-input-rootcause.md`](SHIFT-serial-input-rootcause.md) -
  solved: shift serial-input bug; the deliberate nd100x difference and the
  regeneration hazard.
- [`RUN-level14-livelock-analysis.md`](RUN-level14-livelock-analysis.md) -
  solved: the level-14 livelock (Am2914 status fence) and the IIC mis-decode
  (FIDBO swap); the RUN area itself is still not proven.
- [`am2914-command-model.md`](am2914-command-model.md) - the Am2914 interrupt
  controller command model behind the CGA_INTR sequence testbenches.
- [`48bit-float-not-configured.md`](48bit-float-not-configured.md) - why the
  48-BITS-FLOATING test area is N/A: our PROM microcode is the 32-bit float
  option.
- [`PAL-AUDIT-2026-07-30.md`](PAL-AUDIT-2026-07-30.md) - equation-by-equation
  audit of every PAL against its PALASM source; five transcription errors,
  all fixed.
- [`serial-binload-300.md`](serial-binload-300.md) - the `300$` serial
  binary loader: what works, and why it is parked.
- [`sim-io-capture-and-clocking-lessons.md`](sim-io-capture-and-clocking-lessons.md) -
  lessons from the `300$` hunt: SC2661 registered read, delay slots in CSA
  traces, microcode source to PROM hex.

## Clocking, latches and FPGA debugging

- [`fpga-debug-methodology.md`](fpga-debug-methodology.md) - step-by-step
  method for a board-vs-sim divergence, and the traps that cost time.
- [`hw-timing-vs-verilog.md`](hw-timing-vs-verilog.md) - the designer's
  timing intent against the Verilog model.
- [`clock-enable-refactor.md`](clock-enable-refactor.md) - solved: how the
  CYC_36 CPU clocks became clean flip-flop clocks; the latch-vs-edge rules.
- [`plan-fix-unconstrained-clocks.md`](plan-fix-unconstrained-clocks.md) -
  the net-by-net conversion of the 17 rogue clock nets (phases P1-P4 are
  cited from the RTL); solved 10-JUL, P5 still open.
- [`latch-inventory.md`](latch-inventory.md) - map of the CGA datapath
  latches and the latch-model fix (solved 07-JUL).
- [`skip-wcs-load.md`](skip-wcs-load.md) - `SKIP_WCS_LOAD`: preloading the
  WCS instead of the runtime PROM load; board and sim image sets.
- [`backwiring-prom-installation-number.md`](backwiring-prom-installation-number.md) -
  the backwiring PROM / installation number and how SINTRAN reads it.
- [`ILA-PROBE-SEMANTICS.md`](ILA-PROBE-SEMANTICS.md) - rules for reading
  Nexys ILA captures.
- [`COLOR-STANDARDS.md`](COLOR-STANDARDS.md) - colour rules for generated
  diagrams, waveforms and build output.

## Memory - DRAM, parity, board backends

- [`nd120-dram-memory.md`](nd120-dram-memory.md) - how sheet 49 and the DRAM
  protocol work, and how each board's memory backend maps them.
- [`nd120-parity-analysis.md`](nd120-parity-analysis.md) - memory parity:
  computed, never stored; what is still not checked.
- [`basys3-memory-speed-validation.md`](basys3-memory-speed-validation.md) -
  memory timing budget per board and the clock each memory backend can
  reach.

## Nexys 4 DDR - cache and panel

- [`CACHE-STATUS.md`](CACHE-STATUS.md) - solved 31-AUG: the CPU cache, how a
  hit works, the four faults and their fixes, what was ruled out, test
  results, how to run CACHE-1X0-A00 in Verilator.
- [`PLAN-cache-and-panel.md`](PLAN-cache-and-panel.md) - open panel and
  cache items: meters not faithful, `-tclargs ila` dead, ruler highlight,
  44155A listing question.
- [`panel-clock-68705.md`](panel-clock-68705.md) - the MC68705/MM58274 panel
  clock (TRR PANC / TRA PANS): wiring, how to enable it, how it was
  verified, the two DGA panel bugs.
- [`HANDOFF-cga-idb-ring-cut.md`](HANDOFF-cga-idb-ring-cut.md) - the CGA IDB
  combinational ring: analysis, cuts tried, what a proper fix needs (open).

## MiSTer

- [`PLAN-mister-storage.md`](PLAN-mister-storage.md) - MiSTer OSD storage:
  open board checks, decisions, and the HPS block contract.
- [`mister-microcode-loop.md`](mister-microcode-loop.md) - solved 01-SEP: the
  MiSTer WCS read took two clocks (altsyncram); now the `QUARTUS_RAM_INFER`
  arm and its equivalence gate.
