# Nexys 4 DDR extensions: microSD, then DDR2 main memory

**Full path:** `Verilog/fpga/nexys4ddr/EXTENSIONS-PLAN.md`
**Date:** 19-AUG-2026. **Status: HISTORICAL (02-SEP-2026).** Both extensions are DONE and proven on silicon - the microSD/FAT stack and DDR2 main memory both ship in the deployed Nexys build that boots SINTRAN III. This document is kept for the DDR2 latency-budget rationale that RTL comments cite (`ddr2/MEM_RAM_49_DDR2.v`, `ddr2/nd_ddr2_port.v`, `sd-fat-test/nd_memtest_ddr2.v`, `build.tcl`) and for the board's SD facts; the finished work lists, the 20-AUG status and the acceptance lists were cut 28-SEP-2026 (git history keeps them). Read it as the original plan, not current status.

The first build in this folder is a Basys3 clone on a bigger part: BRAM main
memory (24 KB), 16.667 MHz, UART console. This document covers the two things
the Nexys 4 DDR has that the Basys3 does not - an on-board **microSD slot** and
**128 MiB of DDR2** - in the order they should be done.

Order it was done in: SD first (a port of a stack already proven on silicon),
then DDR2 (the hard one).

---

## Stage 1 - microSD

### What already exists

The whole SD/FAT stack is board-independent and lives in
`Verilog/SD-FAT/circuit/` (`sd_file_reader.v`, `sd_writer.v`,
`nd_storage*.v`). It is **hardware-proven on the Tang Nano 20K**: read and
write, including 4-bit bus transfers. The Basys3 has the same stack running
off an SD Pmod (`../basys3/sd-fat-test/`), so the Xilinx side is proven too.

The Tang ND-120 top-level (`../tang-nano-20k/src/ND120_TANG20K_TOP.v`) wires
the CPU build in **1-bit mode**: `sd_clk`, bidirectional `sd_cmd`,
bidirectional `sd_dat0`, with a `*_oe` tristate pattern at the top level.

### What is Nexys-specific

1. **Slot power.** The reference manual (section 12) is explicit: after
   configuration the on-board microcontroller relinquishes the SD bus, and
   *"the SD_RESET signal needs to be actively driven low by the FPGA to power
   the microSD card slot"* - without it the slot is dead and every SD command
   times out. (Since 27-AUG-2026 the design also power-cycles the slot at
   configuration, reset and master clear - see `HISTORY.md`.)
2. **Pins** (Digilent master XDC, already listed commented-out in
   `nd120_nexys4ddr.xdc`): `SD_SCK B1`, `SD_CMD C1`, `SD_DAT C2/E1/F1/D2`,
   `SD_CD A1` (card detect), `SD_RESET E2`.
3. **Pull-ups.** CMD and DAT0-3 must idle high when released, and DAT3 must be
   high at CMD0 to keep the card in SD mode. Use the FPGA internal pull-ups
   (`PULLUP true` in the XDC) exactly as the Basys3 SD test does, so the design
   does not depend on what the board fits. DAT1/DAT2 are unused in 1-bit mode
   and must still idle high.
4. **Clock.** `sd_file_reader.v` derives its identification clock by a
   **hardcoded** divide (`INIT_HALF=99`, i.e. clk/198), which must land in the
   SD spec's 100-400 kHz window. At the default 16.667 MHz CPU clock that is
   84 kHz - **below spec**. This is a real constraint, not a detail: either
   clock the SD block from a separate MMCM output near 27 MHz (as the Basys3
   SD test does: 27.027 MHz -> ~137 kHz), or raise the CPU clock. **Recommended:
   a dedicated 27 MHz MMCM output for the SD/storage domain**, so SD stays at
   its proven divisors no matter what `clk=` the CPU is built with.

---

## Stage 2 - DDR2 main memory

### The requirement, stated exactly

Any main-memory backend must satisfy the sheet-49 contract in
`../../docs/nd120-dram-memory.md`. The part that decides this whole stage is
the **read deadline**, measured over 25,008 accesses with an identical
signature every time (N = OSC cycle of RAS fall):

- The column address is known at **N+1**.
- Read data must be valid and held **by the start of N+4**.
- **There are no wait states.** The PAL sequence has fixed length; the memory
  physically cannot stall the CPU (PAL comment: "NO WAIT STATE ON CPU TO
  MEMORY WRITE").

So the backend has **3 OSC cycles from column-known to data-valid**:

| CPU clock | 3-cycle budget |
|---|---|
| 16.667 MHz | 180 ns |
| 27.027 MHz | 111 ns |
| 33.333 MHz | 90 ns |
| 50 MHz | 60 ns |
| 100 MHz | 30 ns |

### Why DDR2 cannot simply be dropped in

MIG settings for this board, from the reference manual (Table 2): DDR2 SDRAM,
`MT47H64M16HR-25E`, 16-bit data width, 650 Mbps recommended (3077 ps clock
period), data mask enabled, chip select enabled, 50 ohm ODT, internal Vref.
At 650 Mbps with the standard 4:1 controller ratio the user interface runs at
**81.25 MHz - about 12.3 ns per `ui_clk` cycle**, so the 180 ns budget is
roughly **14 user-interface cycles**.

That is not enough for a guaranteed pass-through, and one number settles it:
`tRFC` for a 1 Gb DDR2 device is **127.5 ns**. A refresh that starts just
before a CPU read consumes most of the budget on its own, before command
arbitration, bank activate (`tRCD`), CAS latency and the return path are
counted. MIG read latency is also not a fixed constant - it depends on bank
state and arbitration. **A direct MIG-behind-sheet-49 bridge cannot be
promised to meet a hard, unstallable deadline.** Any plan that claims it does
is guessing.

### The three ways out

**A. BRAM working-set cache in front of DDR2 (recommended).**
Sheet-49 reads are served from a BRAM cache that always answers inside the
deadline; DDR2 is refilled/written back in the idle time the protocol
guarantees (RAS-to-RAS minimum is 11 OSC cycles, mode 17). The -100T has
~607 KB of BRAM, so a genuinely large cache fits. Cost: a miss still has to be
answered by the deadline, so this alone does not close the hole - it makes
misses rare, not impossible. Needs B as the fallback for a miss.

**B. Stall the CPU clock domain on a miss.**
In FF mode the entire CPU + bus core runs on one clock (`clk_cpu`), which is
exactly what makes this possible: hold the whole domain with a global clock
enable while DDR2 is fetched, and the ND-120 never sees a wait state because
time itself stops for it. Cost: the clock enable must reach **every** register
in the domain - mechanical but wide - and real-time behaviour shifts (the RTC
tick is derived from `BOARD_CLK_FREQ`, and SINTRAN is a real-time OS; the sim
work already showed how badly a wrong RTC timebase distorts it). Also the
UART and any SD traffic must NOT be stalled with the CPU.

**C. pack16 into a smaller, deterministic memory instead of DDR2.**
The Tang's proven contract (`ND_SDRAM_PACK16`: store the 16 data bits, drop
the 2 parity bits, regenerate parity on read) applied to something with fixed
latency. On this board there is no second external RAM, so this degenerates to
"BRAM only" - i.e. no gain over the first build except capacity from the
bigger part (~607 KB BRAM = up to ~300K ND words as pack16, versus 24 KB
today). **This is worth doing on its own** as an intermediate step: it is
deterministic, needs no MIG, and multiplies memory by more than 10x.

### Other DDR2 facts to respect

- The DDR2 pins live in a **1.8 V** HR bank; MIG generates their constraints -
  do not hand-write them into `nd120_nexys4ddr.xdc`.
- MIG needs its own reference/system clock inputs and produces its own
  `ui_clk`; that is a third clock domain, to be declared asynchronous to
  `sys_clk` and `clk_cpu` in `nd120_timing.xdc`.
- **Refresh is the backend's job.** The board logic has a refresh chain
  (DGA `XRFN` -> `REFRQ_n` -> `RGNT_n`), but a ~2.8 ms sim window measured
  **zero** refresh cycles, so nothing can be relied on from it. MIG handles
  DDR2 refresh internally - which is precisely why its latency is variable.
- Capacity: 128 MiB as pack16 = 64M ND words, far more than the ND-120's
  3-bank x 1M-word address space. Memory is not the limit; latency is.
