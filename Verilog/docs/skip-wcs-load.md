# SKIP_WCS_LOAD — Preload the WCS and Skip the Microcode Load Phase

**Full path:** `Verilog/docs/skip-wcs-load.md`
**Last updated:** 2026-09-28

How to preload the Writable Control Store (WCS) directly and skip the ~573K-cycle
runtime microcode load, behind one compile-time define `SKIP_WCS_LOAD`. Derived
from a full trace of the LCS_n load state machine, the WCS RAM structure, and the
PROM->WCS data format.

## Why do this
- **Faster boot + faster sim** — removes Phase 1 (the `CSA` ramp 0->017777, ~573K
  sim ticks *every run*).
- **Tang Nano 20K fit** — if the load is skipped, the microcode PROM
  (`CPU_CS_PROM_19`) is never read, so its ~512 Kbit BRAM can be dropped. Combined
  with the WCS staying in BSRAM, this is what makes the microcode fit the Tang's
  828 Kbit (see `fpga/tang-nano-20k/BSRAM-BUDGET.md`).
- **NOT a timing fix** — it removes a load phase, not a slow path. It is the
  default on every FPGA build: Nexys, Tang, Basys3, MiSTer, MEGA65, QMTECH
  and Cmod A7.

## How the load phase works (so we can skip it safely)

The load is a **pure hardware sequence**, not microcode:
- The `LCS` latch in `PAL/PAL_44403C.v:73-83` is **set by `MR` (master reset)** ->
  `LCS_n=0` = loading.
- While loading, the CGA sequencer's hardware counter ramps the microaddress
  0->017777; at each step PROM data (`BLCS_n=0` selects PROM) flows PROM -> TCV ->
  WCS, written by the `LCS`-gated write strobe (`PAL_44305D.v:59-60`).
- Loading ends when the address wraps 017777->0 (the `LUA12` 1->0 edge): the only
  latch combination not held, so `LCS<=0` -> `LCS_n=1` = execute.
- At execute, the microcode PC starts at **0** (`CGA_MIC_MASEL.v:143-149`,
  `regIW<=0` on `MR_n`). Address `o02001` is **not** RTL — it is the branch target
  inside the microword at WCS address 0. So after load, PC=0 -> microcode ->
  o02001.

**Key insight for skipping:** force the `LCS` latch to never set. Then `LCS_n=1`
from cycle 0, `BLCS_n=1` (PROM disconnected, normal WCS path), the hardware ramp
never runs, and the load write-strobe is dead. **`MR_n` must still fire** (it
resets `regIW->0`, presets the counter, and drives all master-clear init). PC
starts at 0 and the pre-loaded microword at 0 branches to o02001 exactly as after
a real load.

## The WCS is 32 discrete RAM chips (not one array)

`CPU_CS_WCS_21_22.v` instantiates **32 `IDT6168A_20` chips** (each 4096x4):
- 2 banks: `16C..31C` = lower (LUA 0..4095), `16D..31D` = upper (LUA 4096..8191)
  (bank selected by `LUA12` via `ELOW_n`/`EUPP_n`).
- 16 nibble slices per bank: chip `16+j` holds bits `[63-4j : 60-4j]`
  (`16`->[63:60] ... `31`->[3:0]).
- 1-cycle registered read latency is **load-bearing** (a combinational read breaks
  the TVEC dispatch loop) — preload must not change it.

So the preload needs the 64-bit image demuxed into 32 nibble-wide 4096-deep files.

## Data format (PROM -> 64-bit microword) — verified

- `AM27256_45132L.hex` = LO byte (7:0), `AM27256_45133L.hex` = HI byte (15:8),
  each 32768 bytes, byte index `idx = LUA*4 + RF`.
- 16-bit read `P(LUA,RF) = (hi[idx]<<8) | lo[idx]`.
- 64-bit word `= { P(RF=3), P(RF=2), P(RF=1), P(RF=0) }` (RF=0 -> [15:0],
  RF=3 -> [63:48]); straight concatenation, **no bit remapping** PROM->TCV->WCS.

## Generator (done, validated)

`Code/Microcode/gen_wcs_image.py` produces, into
`Code/Microcode/wcs/`:
- `wcs_image.hex` — 8192 x 64-bit (unified; for inspection / a single-BRAM WCS).
- `wcs_<16..31><C|D>.hex` — 32 per-chip nibble files (4096 x 4-bit each).

Validated against the real PROMs: 8192 non-zero words; `word[0x0401]` (o02001) =
`1b80008780203050`. Re-run whenever the microcode hex changes.

**Two image sets (decided 02-SEP-2026).** The boards preload the raw PROM
words from `Code/Microcode/wcs/`. The simulators use
`gen_wcs_image.py --sim`, which writes `Code/Microcode/wcs-sim/` with the
2024 simulator patch of word 0o2002 (a 64x shorter power-on wait, nothing
else). `make test-microcode-sync` checks every copy against the set its
directory must hold. Details: `docs/nd120-facts.md`.

## Implementation (three RTL edits + build wiring)

1. **`Shared/support/IDT6168A_20.v`** — add preload capability:
   ```verilog
   parameter INIT_FILE = "";
   ...
   initial if (INIT_FILE != "") $readmemh(INIT_FILE, idt_memory_array);
   ```
   Preserves BRAM inference (Xilinx + Gowin) and the 1-cycle read latency.

2. **`CPU-BOARD-3202/circuit/CPU_CS_WCS_21_22.v`** — pass a per-chip `INIT_FILE`
   to each of the 32 instances, under the define:
   ```verilog
   `ifdef SKIP_WCS_LOAD
     `define WCS_INIT(f) .INIT_FILE(f)
   `else
     `define WCS_INIT(f) .INIT_FILE("")
   `endif
   ...
   IDT6168A_20 `WCS_INIT("wcs_16C.hex") CHIP_16C ( ... );   // etc. x32
   ```

3. **`PAL/PAL_44403C.v:73-83`** — never set the LCS latch when skipping:
   ```verilog
   `ifdef SKIP_WCS_LOAD
     LCS <= 1'b0;                 // LCS_n stays high (execute) from cycle 0
   `else
     if ( (MR) | (s_dma12_n & LUA12_n & LCS) | (DMA12 & LUA12 & LCS)
             | (s_dma12_n & LUA12 & LCS) ) LCS <= 1'b1;
     else LCS <= 1'b0;
   `endif
   ```

4. **Build wiring** — add `-DSKIP_WCS_LOAD` and put the 32 `wcs_*.hex` files on the
   `$readmemh` search path (copy into `sim/`, `runSim/`, and the Vivado/Gowin
   project dir, like the existing microcode hex). Keep `MR_n` untouched.

5. **(Tang bonus)** with `SKIP_WCS_LOAD`, also `ifdef` out the PROM BRAM in
   `CPU_CS_PROM_19.v` (never read) to reclaim ~512 Kbit.

## Validation
Run the sim with `-DSKIP_WCS_LOAD`:
- The Phase-1 load ramp (CSA 0->017777, ~cycles 16415..573403) must **vanish**.
- Execution must start at CSA=0 and reach `o02001` almost immediately, then follow
  the golden boot path (`docs/boot-golden-spec.md`) identically from there.
- Diff the post-o02001 CSA path against a normal-boot run: must match.

## Risks
- **Keep `MR_n` active** — only neutralise the `LCS` latch. Suppressing `MR_n`
  breaks `regIW` reset, counter preset, and master-clear init.
- **WCS must be preloaded** or the CPU executes garbage — tie the preload and the
  skip to the *same* define.
- **Start PC = 0, not o02001** — forcing PC to o02001 would skip the master-clear
  microcode at address 0.
- Confirm no consumer latches a "load happened" flag it later needs (`LCS_n`
  consumers — MMU, `PAL_44305D`, CGA `ILCSN` — all expect steady-state `LCS_n=1`
  post-load, so forcing it is fine).

## Source references
- `PAL/PAL_44403C.v:73-83,92,100` (LCS state machine)
- `CPU_CS_16.v:82,95,111-159` (PROM->TCV->WCS routing, WCS instance)
- `CPU_CS_WCS_21_22.v` (32 IDT6168A chips), `Shared/support/IDT6168A_20.v:58-59`
- `CGA_MIC_MASEL.v:143-149` (PC reset to 0), `CPU_CS_TCV_20.v:42-76` (RF->slice)
- `Code/Microcode/gen_wcs_image.py` (image generator)
