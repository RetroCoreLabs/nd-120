# Tang Nano 20K — BSRAM budget: what uses it, how to get more, what will not fit

> **Status (checked 28-SEP-2026).** Written 14-JUL-2026.
>
> - **Part 1** - reclaim **8 blocks** by repacking the UUA half of the WCS.
>   **Still open, not implemented** (`CPU_CS_WCS_21_22.v` still instantiates
>   32 `IDT6168A_20` chips). Optional; do it when you need the space.
> - **Part 2** - the floppy / SMD sector-buffer sync-read refactor. **DONE**
>   (commit `cd9b94f`, 23-JUL-2026): `ND_FLOPPY_DMA.v` and `ND_SMD.v` each hold
>   one synchronous-read buffer, and both devices are in the Tang storage build
>   (BSRAM 96%, measured 3-AUG-2026 - see `README.md`, "Storage build").
>
> The block counts in "The situation" are the 10-JUL-2026 build, before the
> storage devices went in.

## The situation

The Tang Nano 20K build is BSRAM-bound and nothing else is close. From the PnR
report of 10-JUL-2026
(`build/nd120_tang20k_build/impl/pnr/nd120_tang20k_build.rpt.txt`,
part `GW2AR-LV18QN88C8/I7`, device GW2AR-18, 828 Kbit BSRAM = 46 blocks):

| Resource | Used | Util |
|---|---|---|
| Logic (LUT/ALU/ROM16) | 6157 / 20736 | 30% |
| Registers | 1872 / 15915 | 12% |
| — as latch | 0 | 0% |
| CLS | 3842 / 10368 | 38% |
| **BSRAM** | **41 / 46 (34 SP + 7 SDPB)** | **90%** |
| DSP | 0 | 0% |
| PLL | 1 / 2 | 50% |

**Five free blocks.** Logic and registers have enormous headroom; BSRAM is the
only thing standing between this build and any new feature that needs storage.

**Where the 41 blocks go.** Traced through the synthesis netlist
(`impl/gwsynthesis/nd120_tang20k_build.vg`), not guessed:

- **32 blocks** are `idt_memory_array` — i.e. `Verilog/Shared/support/IDT6168A_20.v`,
  the 4096x4 SRAM chip model, instantiated 32 times in
  `Verilog/CPU-BOARD-3202/circuit/CPU_CS_WCS_21_22.v`. This is the Writable
  Control Store: **78% of all BSRAM on the device**.
- **9 blocks** (2 SP + 7 SDPB) are the `tmm_` / `am_` / `ims_` arrays.

Main memory costs **zero** BSRAM here — it lives on the embedded 8 MB SDRAM die
via `sdram-bridge/MEM_RAM_49_SDRAM.v`. This is the opposite of the Basys3 build,
where 58% of BRAM goes to a 24 KB main RAM. On Tang, the BSRAM problem *is* the
microcode problem.

---

# Part 1 — Reclaim 8 blocks: repack the UUA half of the WCS

## The measured facts

`CPU_CS_WCS_21_22.v` instantiates 32 `IDT6168A_20` chips as two independent
64-bit-wide, 4096-deep banks, read every microcycle at two different addresses
and OR'd together:

```verilog
input  [11:0] LUA_11_0;   // addresses the 16 "_C" chips  (CHIP_16C .. CHIP_31C)
input  [11:0] UUA_11_0;   // addresses the 16 "_D" chips  (CHIP_16D .. CHIP_31D)
assign CSBITS_63_0_OUT = s_lua_csbits_out[63:0] | s_uua_csbits_out[63:0];
```

The two banks turn out to be completely different in how full they are. Measured
from the preload images in this directory (`wcs_16C.hex` .. `wcs_31D.hex`, one
file per chip, 4096 lines of one hex nibble each):

- **LUA (`_C` chips): all 4096 words carry real microcode.** Highest non-zero
  address per chip ranges 3007..4095, and across the bank it is 4095. **There is
  no slack in LUA. It cannot be shrunk.**
- **UUA (`_D` chips): real microcode occupies only words 0..1355.** From 1356 to
  4095 — 2740 words, two thirds of the bank — every `_D` chip holds a *generated
  default fill*, verified with no exceptions:

| chip | content for `UUA_11_0` >= 1356 |
|---|---|
| `wcs_29D` | `addr[11:8]` |
| `wcs_30D` | `addr[7:4]` |
| `wcs_31D` | `addr[3:0]` |
| `wcs_26D` | constant `1` |
| all other `_D` chips | `0` |

In other words: **the top two thirds of the UUA bank stores the address of the
word itself, plus one constant bit.** That is not data. It is computable from
`UUA_11_0` with no storage and essentially no logic.

The totals cross-check against the independently-known microcode size:

```
LUA  4096 words x 8 bytes = 32768 bytes
UUA  1356 words x 8 bytes = 10848 bytes
                   TOTAL  = 43616 bytes
```

which matches the known figure of ~43612 bytes to within 4 bytes. Two
independent routes to the same boundary, so the 1356 split is trustworthy.

### Reproducing the measurement

Run from this directory (`Verilog/fpga/tang-nano-20k/`) with a python.org
Python on Windows (not the Microsoft Store one), or `/usr/bin/python3` under WSL.

```python
# 1. Per-chip used depth: which bank has slack?
import glob, os, re
def load(p):
    return [int(l.strip(), 16) for l in open(p) if l.strip() and not l.startswith('//')]
for p in sorted(glob.glob('wcs_*.hex')):
    m = re.match(r'wcs_(\d+)([CD])\.hex$', os.path.basename(p))
    if not m:                      # skips wcs_image.hex
        continue
    v  = load(p)
    hi = max([i for i, x in enumerate(v) if x], default=-1)
    print("%-14s depth=%d highest_nonzero=%d" % (os.path.basename(p), len(v), hi))
```

```python
# 2. Prove the UUA fill above 1356 is exactly the address + a constant bit.
def load(p):
    return [int(l.strip(), 16) for l in open(p) if l.strip() and not l.startswith('//')]
d31, d30, d29, d26 = (load('wcs_%dD.hex' % n) for n in (31, 30, 29, 26))
lo = 1356
assert all(d31[a] == (a       & 0xF) for a in range(lo, 4096))   # addr[3:0]
assert all(d30[a] == ((a >> 4) & 0xF) for a in range(lo, 4096))  # addr[7:4]
assert all(d29[a] == ((a >> 8) & 0xF) for a in range(lo, 4096))  # addr[11:8]
assert all(d26[a] == 1                for a in range(lo, 4096))  # constant 1
print("UUA fill confirmed: addr-ramp + const from %d..4095" % lo)
```

## The trap: narrowing the chips saves nothing

**Do not simply change `IDT6168A_20` from 4096 deep to 2048 deep and expect to
save blocks. That saves exactly zero.**

A Gowin BSRAM18 is 18 Kbit, and its configurations are 16Kx1, 8Kx2, 4Kx4, 2Kx9,
1Kx18, 512x36. Each `IDT6168A_20` chip needs its own independently addressable
4-bit port, so it consumes one whole block whether it is 4096x4 (16 Kbit, 89% of
the block used) or 2048x4 (8 Kbit, 44% used). Sixteen chips means sixteen blocks
either way. The depth reduction just wastes half of each block instead of a
tenth.

The saving comes **only** from abandoning the sixteen-separate-4-bit-chips
structure for the UUA bank and packing it as one wide array.

## The plan

Rebuild the UUA half as a single **2048 deep x 64 bit** array. That is 128 Kbit.
In 2Kx9 mode a BSRAM18 gives 9 bits per block, so 8 blocks yield 72 bits >= 64.

**16 blocks -> 8 blocks. Net saving: 8 BSRAM, about 17% of the device.
41 -> 33 blocks, 90% -> ~72%.**

Two pieces of work:

1. **Pack the storage.** Replace `CHIP_16D`..`CHIP_31D` (16 x `IDT6168A_20`) with
   one 2048x64 synchronous RAM. It must keep the exact timing contract of
   `IDT6168A_20` — posedge-clk, write-first, **1 sysclk read latency**. See the
   warning below; that latency is not negotiable.
2. **Generate the fill.** For `UUA_11_0 >= 1356`, bypass the RAM and return the
   computed pattern instead:
   - the `29D` nibble position <- `UUA_11_0[11:8]`
   - the `30D` nibble position <- `UUA_11_0[7:4]`
   - the `31D` nibble position <- `UUA_11_0[3:0]`
   - the `26D` bit position <- `1`
   - every other bit <- `0`

   Register the generated value through the same pipeline stage as the RAM output
   so both paths have identical 1-sysclk latency, otherwise you reintroduce
   exactly the divergence `IDT6168A_20.v` was unified to remove.

The fill boundary 1356 is not a power of two, so the comparator is a real 12-bit
compare rather than a bit test. Rounding the RAM up to 2048 while keeping the
*fill* boundary at 1356 is fine — words 1356..2047 then exist in RAM but are
never read, because the generator wins for any address >= 1356. Keeping the RAM
at 2048 rather than 1356 costs nothing (the block count is set by the 2Kx9 mode)
and keeps the address decode trivial.

### Do not touch the LUA bank

LUA is 4096 x 64 = 256 Kbit. At 4Kx4 that is 16 blocks, and 256/18 = 14.2 means
16 blocks is already at the practical minimum for that depth. It is optimally
packed today and all 4096 words are live. Leave it alone.

## Before you build Part 1

### The good news for this board specifically

In general the WCS is writable at runtime, and the `wcs_*.hex` files are only the
preload path — on the normal boot path the CPU's own WCS loader writes the
control store from the AM27256 PROM images, so the preload images would not
necessarily describe what actually ends up in the store.

**That does not apply to the Tang build.** `src/tang20k_defines.v` sets:

```verilog
// Bitstream-preloaded WCS; the runtime microcode load phase is skipped and
// the microcode PROM is never read (required to fit the 828 Kbit BSRAM)
`define SKIP_WCS_LOAD
```

With `SKIP_WCS_LOAD` the runtime load phase never runs and the PROM is never
read, so **on Tang the hex images in this directory *are* the WCS content,
authoritatively.** The measured 1356 boundary and the address-ramp fill are not a
proxy for the real thing — they are the real thing, and a generated fill is
bit-exact by construction. This is the main reason the repack is attractive on
this target and would be far riskier on Basys3, which does run the loader.

`SKIP_WCS_LOAD` is already implemented and verified in Verilator — a preloaded
WCS boots byte-identical to the normal load. See `../../docs/skip-wcs-load.md`.

### What still needs checking

1. **Does anything write the UUA bank at runtime *after* load?** `SKIP_WCS_LOAD`
   removes the boot-time loader, but the write strobes (`WU0_n`..`WU3_n`,
   `EUPP_n`) still exist in `CPU_CS_WCS_21_22.v`. If microcode ever writes the
   control store during normal operation, a read-side generator would silently
   defeat those writes for addresses >= 1356. **Not verified.** Check whether
   `EUPP_n` + `WU*_n` are ever asserted post-load with `UUA_11_0 >= 1356`; a
   Verilator assertion on that condition over a full boot + selftest run would
   settle it cheaply.
2. **Which CSBITS fields are the `29D`/`30D`/`31D` nibbles and the `26D` bit?**
   Less critical — since the generator reproduces the preload exactly, you do not
   strictly need to know what the fields *mean*. But knowing would let you confirm
   the interpretation below and make the RTL self-documenting.

**An inference that has NOT been verified:** a next-address field pointing at
*itself*, plus one flag bit, reads like a spin/trap default for unimplemented
microcode entries — implying the CPU never legitimately executes in that range
and the fill is pure safety net. **That is a guess**, and the CSBITS field
assignment has not been traced. It does not block the repack (a bit-exact
generator is correct either way), but do not go writing it into other docs as
fact.

### The 1-cycle read latency is load-bearing for CORRECTNESS

The header comment in `Verilog/Shared/support/IDT6168A_20.v` documents that
zero-delay reads collapse the WCS feedback loop (WCS -> CSBITS -> SC5/SC6 ->
regREP -> regW -> CSA -> LUA -> WCS), causing the TVEC dispatch chain
o000017 -> o000016 -> o002001 to resolve in delta time and o000016 LDLC to be
skipped. **Read that comment before touching this module.** Any repack must
preserve posedge-clk, write-first, 1-cycle-read semantics exactly.

---

# Part 2 — Device buffers (floppy / SMD): sync-read refactor (DONE)

**Done in commit `cd9b94f` (23-JUL-2026).** BSRAM is synchronous-read only. The
floppy-DMA and SMD 2 KB sector buffers (`reg [15:0] s_buffer[0:1023]`, one
1Kx18 block each) used to have three asynchronous read ports at independent
addresses; Gowin cannot map that to BSRAM, and as registers one buffer would
exceed the device's 15552 FFs (the `ND_SMD.v` comment records 43k LUT4
measured standalone). Both are now a simple dual-port RAM: one muxed write
port and one registered read port whose address follows the active consumer
(see the comments above `s_buffer` in `ND_FLOPPY_DMA.v` and `ND_SMD.v`). The
same template is `Verilog/Shared/support/IDT6168A_20.v`, and the same fix
serves Basys3 (RAMB18 has the same constraint).

**Still open:** `Verilog/ND-BUS-DEVICES/FLOPPY/circuit/ND_FLOPPY_PIO.v:94`
still reads its buffer asynchronously (lines 171 and 182). It is not in any
Tang build today; decide whether it needs the same treatment or stays
Verilator-only before it goes on a board.

---

# Alternatives considered and rejected

**Move the running WCS to SDRAM.** No. The WCS is read twice per microcycle at
two independent addresses for 128 bits total, and it is a *dependent* load — the
next `LUA` is computed from the current microinstruction, so it is pointer
chasing that cannot be prefetched or pipelined. The `sdram18.v` controller is
single-port, 32-bit, "data read latency is 4 cycles, read/write take 5 cycles, no
overlap", auto-precharge every op. One microinstruction fetch would take ~4 ops
~= 20 cycles ~= 370 ns at 54 MHz against the 37 ns available at 27 MHz, before
counting refresh stalls and contention with main memory, which already owns that
port. On top of the ~10x slowdown it would introduce a third, uncharacterised
timing regime into the exact sequencer where the FPGA boot bug already lives.

**Load the microcode from SD card to save BSRAM.** This does not save BSRAM. It
changes where the microcode *comes from*, not where it *lives*; the blocks are
consumed by the store being readable every cycle. Worth doing on its own merits —
the seam already exists (`SKIP_WCS_LOAD`), the SD/FAT stack is proven on real
Tang silicon, and it would let microcode change without a re-synth — but it is a
workflow win, not a resource win. Do not conflate the two.

**Put the device sector buffers in SDRAM.** Not analysed. Unlike the WCS this is
not obviously wrong — sector buffers are streamed, not pointer-chased, so the
latency may be tolerable — but the SDRAM port is already shared between main
memory and the `nd_storage` disk-image cache in the upper 4 MB (see
`ND_SDRAM_PACK16` in `src/tang20k_defines.v`). If Part 2's 2 blocks ever become
unaffordable, this is where to look next.

---

# Budget summary

| | blocks (10-JUL build) | after Part 1 | note |
|---|---|---|---|
| WCS LUA (`_C`) | 16 | 16 | all 4096 words live, already optimal, do not touch |
| WCS UUA (`_D`) | 16 | **8** | only 1356 words live; rest is a computable addr ramp |
| `tmm_` / `am_` / `ims_` | 9 | 9 | untouched |
| **subtotal** | **41 (90%)** | **33 (~72%)** | |

The storage build since added the floppy and SMD buffers and more (96% on
3-AUG-2026). Part 1 is still the way to buy room for whatever comes next.

# References

- `Verilog/CPU-BOARD-3202/circuit/CPU_CS_WCS_21_22.v` — the WCS, 32 chip instances
- `Verilog/Shared/support/IDT6168A_20.v` — 4096x4 chip model; **read the timing
  comment before changing anything**. Also the canonical BRAM-inference template
  for Part 2.
- `Verilog/fpga/tang-nano-20k/wcs_*.hex` — per-chip preload images (`_C` = LUA,
  `_D` = UUA)
- `Verilog/ND-BUS-DEVICES/FLOPPY-DMA/circuit/ND_FLOPPY_DMA.v` — 2 KB buffer (sync read)
- `Verilog/ND-BUS-DEVICES/SMD/circuit/ND_SMD.v` — 2 KB buffer (sync read)
- `Verilog/ND-BUS-DEVICES/FLOPPY/circuit/ND_FLOPPY_PIO.v` — 2 KB buffer, line 94
- `build/nd120_tang20k_build/impl/pnr/nd120_tang20k_build.rpt.txt` — PnR resource
  report quoted above
- `build/nd120_tang20k_build/impl/gwsynthesis/nd120_tang20k_build.vg` — netlist;
  source of the 32-vs-9 BSRAM attribution
- `sdram-bridge/sdram18.v` — SDRAM controller timing quoted in rejected alternatives
- `src/tang20k_defines.v` — `SKIP_WCS_LOAD`, `MAIN_RAM_SDRAM`, `ND_SDRAM_PACK16`
