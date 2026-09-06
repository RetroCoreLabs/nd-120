# HANDOFF: QMTECH XC7A35T board bring-up

**Full path:** `Verilog/fpga/qmtech-a35t/HANDOFF-qmtech-a35t-bringup.md`
**Written:** 2026-07-08 (paused) — **resumed and superseded 2026-09-04**
**Priority:** this is now the SINTRAN-capable Artix-7 target.

> **READ THIS FIRST (04-SEP-2026).** Most of what follows was written while
> the board was parked, and two of its central claims are now WRONG:
>
> * **"The only real design work left is the 16-bit SDRAM bridge"** — that
>   bridge mode was written on 01-SEP-2026 for the DE10-Nano
>   (`ND_SDRAM_DQ16`), boots SINTRAN on the MiSTer and builds timing-clean
>   for the MEGA65 R6. It did not have to be written again. Stage 3 below is
>   done, by someone else, for a different board.
> * **"The next action is two one-command Vivado runs"** — the LED and
>   memory smoke tests are no longer the critical path. A FULL ND-120 build
>   now exists in this directory (top level, pin map, `build.tcl`), it lints
>   clean end to end, and it proves the clock and the programming chain by
>   booting. Run the smoke tests only if the full build fails in a way that
>   makes the board itself the suspect.
>
> There is ONE new constraint the old plan did not know about: the 16-bit
> bridge mode and the disc cache cannot both be used, because that mode drops
> the 32-bit access the cache's region port needs. The build works round it by
> running storage uncached. Full explanation, and the proper fix, are in
> [`README.md`](README.md) under "The 16-bit bridge and the disc cache".
>
> **Current state and the ordered next actions live in [`README.md`](README.md).**
> What is below is kept for the hardware facts, which are still good.

## One-paragraph state (2026-07-08, historical)

The board folder `Verilog/fpga/qmtech-a35t/` is fully scaffolded: verified
reference pin map, LED smoke test, and a port of the Basys3 standalone
memory test that **passes its iverilog testbench** (all 8 vectors, decoded
serial stream prints PASS). **Nothing has run on the physical board yet.**
The next action is two one-command Vivado runs on the Windows host with the
Xilinx Platform Cable USB II connected. After that, the only real design work
left is the 16-bit SDRAM bridge (stage 3 below).

## Why this board

Same FPGA die as the Basys3 (`xc7a35t`, CSG325 package, part
`xc7a35tcsg325-1`) - everything transfers 1:1 - plus 32 MB SDRAM, which
removes the Basys3's 24 KB BRAM main-memory limit. Target main memory:
**2 MB** (Ronny's requirement; 1M x 18-bit ND words = 4 MB of the chip).

## Hardware setup (verified against manual + schematic, both in `docs/`)

- Mini USB = **power only** (no USB data path on the board - QMTECH omits
  the FTDI bridge Digilent boards have).
- Everything else via the **Platform Cable USB II** on the 6-pin JTAG header:
  programming, SPI flash, ILA, VIO. Vivado hardware manager sees it exactly
  like the Basys3's onboard JTAG; the whole `../basys3/ila_*.tcl` workflow
  carries over.
- No UART anywhere. For the eventual OPCOM console: BSCANE2 JTAG-UART bridge,
  VIO char poking, or 2 header pins + external 3.3 V USB-serial dongle.
- Confirmed pins (schematic sheet 2/4; full map in
  [`board-pins.xdc`](board-pins.xdc)):
  50 MHz osc on `R2` (MRCC), keys `H18`(SW1)/`H17`(SW2) active-low,
  LEDs `C8`/`D8` **active-low**, 39 SDRAM pins.
- Gotcha: on headers JP2/JP3, **pin 1 = 5 V, pin 2 = 3V3**.

## What exists (all under `Verilog/fpga/qmtech-a35t/`)

| Item | State |
|------|-------|
| `board-pins.xdc` | Reference pin map, cross-checked schematic vs vendor XDCs. Copy from here. |
| `led-test/` | Stage 1. Verilator `-Wall` clean. `build.tcl` = synth+impl+bitstream+JTAG-program in one batch run. Expected on board: `led_n[0]` blinks 1 Hz, `led_n[1]` lights while SW1 (H18) held. |
| `mem-test/` | Stage 2. Port of `../basys3/mem-test/` - same FSM/vectors/`MEM_RAM_49`; 50 MHz MMCM (x20/60 -> 16.667 MHz); UART TX is an internal `mark_debug` net (ILA it if detail needed). LEDs: fast blink = running, 1 Hz blink = PASS, both solid = FAIL. **Sim passes** (`mem-test/sim/`, iverilog `-DNO_MMCM`). |
| `docs/` | Vendor user manual + schematic PDFs (md5-verified against the official GitHub repo) + `board-notes.md` = distilled analysis of both and of the vendor sample projects. |

## Exact next actions (in order)

1. **Windows host, board powered via Mini USB, Platform Cable on JTAG header:**
   `cd Verilog/fpga/qmtech-a35t/led-test` -> `vivado -mode batch -source build.tcl`
   - PASS = 1 Hz heartbeat + key echo. Wrong blink rate => clock assumption
     wrong; program fails => cable/target (check hw_server sees the cable).
2. Same in `mem-test/`. PASS = `led_n[0]` settles to 1 Hz blink. FAIL (both
   LEDs solid) would be *interesting* - same die as the Basys3 where this
   passes, so a failure means board-level (clock/MMCM), not logic.
3. **Stage 3 - the real work:** 16-bit SDRAM bridge variant of
   [`../tang-nano-20k/sdram-bridge/`](../tang-nano-20k/sdram-bridge/README.md).
   The Tang bridge stores one 18-bit ND word per **32-bit** SDRAM word; this
   chip (W9825G6KH-6) is **16 bits** wide, so two beats per ND word
   (data beat + parity beat), suggest mode-reg BL=2 instead of the Tang's
   single-word access - decide in the testbench. Reuse
   `sdram-bridge/sim/mem_ram_49_sdram_tb.v` (measured ND-120 protocol replay);
   timing budget is comfortable: vendor warrants CL=2 @ 100 MHz on this PCB
   (`docs/board-notes.md`), we need ~66 MHz. The vendor
   SDRAM sample has **no reusable controller** - already analyzed, don't
   re-mine it. Then a standalone hardware verify like
   `../tang-nano-20k/sdram-test/` before full integration.
4. **Stage 4:** full ND-120 build, 2 MB SDRAM main memory. Needs the Tang-style
   compile gate (`MAIN_RAM_SDRAM`-like define) wired for this board and an
   OPCOM console decision (BSCANE2 bridge recommended).

## Related memory/notes

- Auto-memory: `qmtech-a35t-board.md` (in Claude's memory dir) mirrors this.
- `README.md` - board folder overview (this folder).
- `../../docs/nd120-dram-memory.md` section 6 - measured ND-120 DRAM protocol the
  bridge must satisfy.
