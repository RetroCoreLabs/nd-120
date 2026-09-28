# Nexys 4 DDR build warnings - what they mean, ranked

> **Historical reference (kept).** Taken from an early 12.5 MHz build log;
> counts and the WNS figure are from that run, not the deployed build. The
> board now boots SINTRAN and is deployed. The interpretation of each warning
> code - especially the inferred timing-loop exceptions - still holds and is
> why this analysis is kept.

**Full path:** `Verilog/fpga/nexys4ddr/BUILD-WARNINGS-ANALYSIS.md`
**Source log:** `Verilog/fpga/nexys4ddr/nd120_clk12.log` (the build that passed
timing: 46 loops, WNS +1.460 ns at 12.5 MHz)
**Date:** 20-AUG-2026

Every count below was taken from that log. Where a claim could not be checked
from the source it is marked **UNVERIFIED** rather than guessed.

| Code | Count | Severity |
|---|---|---|
| `[Synth 8-295]` timing loop | 46 | critical - known, tracked separately |
| `[DRC LUTLP-1]` combinational loop | 12 | critical - downgraded to build |
| `[Synth 8-326]` **inferred exception to break timing loop** | 12 | **see 1** |
| `[Place 30-568]` LUT driving a clock pin | 1 | **see 2** |
| `[Synth 8-7137]` Set and reset at same priority | 11 | **see 3** |
| `[Synth 8-6014]` unused sequential element removed | 22 | see 4 |
| `[Synth 8-7129]` port unconnected / no load | 100 | see 5 |
| `[Synth 8-7023]` fewer connections than declared | 3 | see 5 |
| `[Synth 8-6849]` ram_style="block" infeasible -> LUTRAM | 6 | see 6 |
| `[Synth 8-4767]` RAM implemented in registers | 1 | see 6 |
| `[Synth 8-6901]` identifier used before declaration | 21 | see 7 |
| `[Synth 8-3917]` port driven by constant | 12 | benign - see 8 |
| `[Synth 8-7071]` unconnected primitive port | 21 | benign - see 8 |
| `[Vivado 12-13650]` IP moved from original location | 1 | benign - see 8 |
| `[Constraints 18-548]` invalid DRIVE value | 1 | see 8 |

---

## 1. `[Synth 8-326]` - the WNS number is not what it looks like

```
WARNING: [Synth 8-326] inferred exception to break timing loop:
    'set_disable_timing i_0/CORE/CPU_BOARD/CPU/i_0/i_270 -from I1 -to O'
    ... also i_155, i_172, i_189
```

**This is the most important warning in the log, and it is only a Warning.**

Vivado could not analyse the combinational rings, so it **switched timing
analysis off** on four cells inside `CPU/i_0` - `set_disable_timing` from input
I1 to output O. Those arcs are then invisible to `report_timing_summary`.

So `WNS: +1.460 ns` does not mean every path was checked and passed. It means
every path **that was still being timed** passed. Four arcs in the middle of the
CGA data bus were excluded from the question.

**Consequence:** the +1.460 ns figure is a lower bound on the problem, not a
guarantee of correctness, and it cannot be used to argue the clock could be
raised. It also means a build can "pass timing" and still fail on silicon in
exactly the region that was disabled.

**Fix:** the same one as the loops - break the ring in RTL. When
`[Synth 8-295]` reaches zero, `[Synth 8-326]` goes with it and the timing
number becomes meaningful. Nothing else makes that number trustworthy.

---

## 2. `[Place 30-568]` - a J-K flip-flop clocked by an error signal

```
WARNING: [Place 30-568] A LUT 'CORE/CPU_BOARD/MEM/DATA/CHIP_1H/s_currentState_i_2'
is driving clock pin of 1 registers.
    CORE/CPU_BOARD/MEM/DATA/MEMORY_5/s_currentState_reg {FDRE}
```

Traced to source - `Verilog/CPU-BOARD-3202/circuit/MEM_DATA_46.v:191`:

```verilog
J_K_FLIPFLOP #(
    .InvertClockEnable(1)
) MEMORY_5 (
    .clock(s_lerr_n_out),      // <-- combinational parity-error signal
    .j(s_power),
    .k(s_gnd),
    ...
    .qBar(s_lperr_n_out),
```

`s_lerr_n_out` is a parity-error output from `CHIP_1H`, produced by fabric
logic. Using it as a clock makes it a routed clock net: unconstrained, and a
hold-time race decided by placement rather than by design.

**Why this one is worth attention:** the file already contains the fix for the
*neighbouring* problem. `MEM_DATA_46.v:238-247` converts the `AM29833A` parity
capture away from `posedge RDATA` when `FPGA_FF_MODE` is set, with a comment
naming the exact hazard ("fabric-routed clock net on FPGA (unconstrained,
hold-race lottery)"). **`MEMORY_5` was not included in that conversion**, so the
hazard the comment describes is still present a few lines below it, in the same
module, in the same build mode.

This sits directly in the parity-error path that commits `148594d` and `6d95b09`
were about.

**Status: FIXED (commit `202c606`, 25-AUG-2026).** In `FPGA_FF_MODE`,
`MEM_DATA_46.v:177-201` now replaces `MEMORY_4`/`MEMORY_5` with the same
sysclk edge capture the `AM29833A` uses; latch mode keeps the J-K chips.

---

## 3. `[Synth 8-7137]` - sim and hardware can disagree, 11 registers

```
Register s_cb_reg[0..N] in module ND_FLOPPY_DMA has both Set and reset with
same priority. This may cause simulation mismatches.
```

`Verilog/ND-BUS-DEVICES/FLOPPY-DMA/circuit/ND_FLOPPY_DMA.v`.

When set and reset assert together, the simulator resolves by statement order
and the FPGA resolves by which primitive got inferred. **They can differ.** Any
floppy result proven in Verilator is therefore not automatically proof for
silicon, for these 11 bits.

Cheap to settle: give one a clear priority in the RTL, and add a testbench that
drives set and reset simultaneously.

---

## 4. `[Synth 8-6014]` - 22 registers written but never read

Examples:

| Register | File |
|---|---|
| `s_test_mode_reg` | `ND-BUS-DEVICES/FLOPPY-DMA/circuit/ND_FLOPPY_DMA.v:456` |
| `s_disk_to_reg` | `ND-BUS-DEVICES/FLOPPY-DMA/circuit/ND_FLOPPY_DMA.v:460` |
| `s_pend_reg` | `ND-BUS-DEVICES/DMA/circuit/ND_DMA_MASTER.v:171` |

Synthesis deleted them because nothing reads them. Each is either a feature that
was never wired up, or a signal that *should* be read and is not. `s_disk_to`
(disk timeout) and `s_pend` (pending) both sound like the second kind.

**UNVERIFIED** which of the 22 are harmless. Needs a read of each site.

---

## 5. `[Synth 8-7129]` x100 / `[Synth 8-7023]` x3 - unconnected ports

```
Port alloc_way[2] in module nd_storage_cache is either unconnected or has no load
instance 'u_reader' of module 'sd_file_reader' has 38 connections declared, but only 36 given
instance 'u_writer' of module 'sd_writer'      has 33 connections declared, but only 23 given
```

An unconnected **output** is harmless. An unconnected **input** floats, and in
synthesis becomes a constant chosen by the tool.

**UNVERIFIED - and deliberately so.** A first pass with a regex over the port
lists produced obviously wrong output (it matched the wrong module's ports
entirely), so no direction claim is made here. `sd_writer` missing 10 of 33
connections is the one to check first, because the SD write path is live
(`SDFAT_WRITE` is on and every `20500&` boot rewrites LBA 0).

---

## 6. RAM inference - `[Synth 8-6849]` x6, `[Synth 8-4767]` x1

```
Infeasible attribute ram_style = "block" for "CPU/PROC/registerBlock_reg" -> LUTRAM
Infeasible attribute ram_style = "block" for "CPU_BOARD/MEM/RAM/mem_reg"  -> LUTRAM
Trying to implement RAM 'mem_reg' in registers  [Shared/support/FIFO_8BIT.v:55]
```

Three different structures asked for block RAM and did not get it. The CPU
register file and part of main memory land in LUTs instead of BRAM, and
`FIFO_8BIT` lands in plain flip-flops - the most expensive option of the three.

Not currently blocking anything, and **the count is identical (6) in every build
today**, so it is not a new regression. It is spending LUTs on the board with the
most BRAM in the family, which is the wrong way round. The usual causes are a
combinational (asynchronous) read port or an async reset - both are listed in
the BSRAM notes already.

---

## 7. `[Synth 8-6901]` x21 - identifier used before its declaration

```
identifier 's_term_n' is used before its declaration [CPU-BOARD-3202/circuit/ND3202D.v:222]
identifier 's_ident_answer' used before declaration  [ND-BUS-DEVICES/WINCHESTER/circuit/ND_WINCHESTER.v:364]
```

Legal for nets in Verilog and it synthesises correctly. It matters for one
reason: an implicit 1-bit net is created if the name is ever **misspelled**, and
that failure is silent. Worth a cleanup pass, not urgent.

---

## 8. Benign, recorded so they are not re-investigated

- `[Synth 8-3917]` x12 - `dp`, `an[7:0]` driven by constant 1. The Nexys
  seven-segment digits we do not use, tied off. Correct.
- `[Synth 8-7071]` x21 - `CLKFBOUTB`, `CLKOUT0B` etc. unconnected on
  `MMCME2_BASE`. Inverted/unused outputs of a hard primitive. Correct.
- `[Synth 8-7023]` on `mmcm` - 9 of 18 connections given. Same thing; the rest
  take their defaults.
- `[Vivado 12-13650]` - `ddr.xci` referenced from `ddr2-test/ip/ddr/`, so IP
  outputs regenerate elsewhere. Expected: the DDR2 IP is deliberately shared
  from the test project rather than duplicated.
- `[Constraints 18-548]` - invalid `DRIVE` value `2'b00` in the SD-FAT source.
  Vivado ignores it. Cosmetic, but it is a real mistake in the attribute.

---

## What to do, in order (status 28-SEP-2026)

1. **Break the CGA ring in RTL.** It removes `8-295`, `LUTLP-1` and `8-326`
   together and makes the WNS number mean something. Owned by
   `Verilog/docs/HANDOFF-cga-idb-ring-cut.md`.
2. `MEMORY_5` in `MEM_DATA_46.v` - DONE (section 2).
3. **`ND_FLOPPY_DMA` set/reset priority** (section 3) and **the 22 deleted
   registers + the `sd_writer` connections** (section 4) - NOT re-checked since
   `ND_FLOPPY_DMA.v` was reworked; needs a fresh synthesis log read. Of the
   examples, `s_disk_to` is read today (`ND_FLOPPY_DMA.v:660`) and `s_pend` is
   only used when the `EARLY_REREQ` parameter is non-zero.
4. RAM inference and the cosmetic items whenever convenient.
