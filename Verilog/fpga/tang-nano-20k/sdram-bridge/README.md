# ND-120 sheet-49 SDRAM backend (Tang Nano 20K)

**Full path:** `Verilog/fpga/tang-nano-20k/sdram-bridge/`

> **Status: protocol-validated in simulation.** The testbench replays the
> *measured* ND-120 DRAM protocol (2000-access random soak + directed tests)
> against the bridge and a behavioral SDRAM model - data correct and held
> through the deadline, parity round-trips (including deliberately bad
> parity), refresh never gaps beyond 15.7 us. **Now wired into the full ND-120
> Tang build as main memory** (2 banks = 4 MB, packed 16-bit `ND_SDRAM_PACK16`):
> the Tang Nano 20K boots SINTRAN III from it on real silicon (24-AUG-2026).

Drop-in replacement for the sheet-49 RAM (`CPU-BOARD-3202/circuit/MEM_RAM_49.v`)
that maps the ND-120's DRAM protocol onto the Tang Nano 20K's 8 MB embedded
SDRAM. Design rationale, measured protocol, timing budget and frequency plan:
[`../../../docs/nd120-dram-memory.md`](../../../docs/nd120-dram-memory.md)
(section 6). The SDRAM controller itself was hardware-validated first in
[`../sdram-test/`](../sdram-test/README.md) (full 8 MB write+verify passes on
the board).

## Files

| File | Purpose |
|------|---------|
| `MEM_RAM_49_SDRAM.v` | The bridge: sheet-49 interface in the OSC domain, SDRAM controller on a 2x clock; refresh self-scheduled (post-access slot + idle watchdog) |
| `sdram18.v` | 18-bit-word variant of the nand2mario controller (one ND word per 32-bit SDRAM word; word addressing; all-lane writes). Apache-2.0, adapted - see `../sdram-test/src/LICENSE.nand2mario` |
| `sim/mem_ram_49_sdram_tb.v` | Protocol testbench (measured 6-cycle signature, mirror model, refresh cadence checks) |
| `sim/Makefile` | `make test` -> expects `TB_RESULT: PASS` (reuses `../sdram-test/sim/sdram_model.v`) |

## Key design facts

- **Timing** (N = OSC cycle of RAS rise, clk2x = 2x OSC, edge-aligned, from the
  same rPLL): row captured at fast edge 2N+1, column at 2N+3, read issued at
  2N+3 -> `data_ready` at 2N+8 = **OSC N+4**, registered and held while CAS is
  high. Writes capture `DD_17_0_IN` at 2N+5. Verified against the protocol's
  fixed no-wait-state deadline.
- **Capacity:** 2M x 18-bit words = BANK0 + BANK1 (4 MB). BANK2 reads as 0 /
  never written, so the ND-120's boot-time memory sizing sees two banks.
- **Refresh is generated here** - the board logic's refresh chain (DGA `XRFN`)
  is inactive (measured). Primary: one auto-refresh in the guaranteed-idle slot
  right after each access when the 15 us timer has expired. Backup: idle
  watchdog (~1.2 us of no access). A watchdog refresh colliding with an
  incoming access delays read data by up to ~2.5 OSC cycles - rare (requires
  the CPU to have been idle) and flagged as a validation point for the full
  build.
- **Parity is stored, not recomputed** (2 extra bits per word) so the
  self-test's deliberate bad-parity writes behave exactly like real chips.

## Integration

Wired into the Tang build under `MAIN_RAM_SDRAM` (set by `src/tang20k_defines.v`);
Verilator and the Xilinx builds never see this folder. Two things still worth
knowing: the SDRAM ports auto-connect in Gowin EDA but the OSS flow needs
`../sdram-test/src/sdram_pins_oss.cst`, and `CLK2X_FREQ` = 2x `BOARD_CLK_FREQ`
(ceiling with the current controller timing parameters: OSC ~33 MHz / SDRAM
~66 MHz).

## Run the testbench

```bash
cd Verilog/fpga/tang-nano-20k/sdram-bridge/sim
make test    # iverilog; prints TB_RESULT: PASS
```

Registered gates (all in `Verilog/tests/run_all_tests.sh`): `test` (legacy
18-bit words), `test-pack16` (`ND_SDRAM_PACK16`: two ND words per 32-bit
location, DQM lane-masked writes, computed parity), `test-pack16-part`
(reduced CPU partition via `CPU_PART_ROWS`), `test-storage-port`
(`ND_STORAGE_PORT`: the nd_storage device mem port - see below).

## Storage device port (`ND_STORAGE_PORT`, requires `ND_SDRAM_PACK16`)

`MEM_RAM_49_SDRAM` optionally exposes the nd_storage mem port of
`docs/nd-storage-design.md` section 5.2 (`stor_clk` domain:
`mem_start`/`mem_we`/`mem_addr[19:0]`/`mem_wdata[31:0]`/`mem_rdata[31:0]`/
`mem_busy`/`mem_done`, toggle-CDC into clk2x). Device ops move whole 32-bit
locations through sdram18's `acc32`/`din32`/`dout32` path and are granted
exactly like refresh - in the guaranteed-idle B_POST slot after each CPU
access, in B_TAIL during absent-row accesses, and in B_IDLE behind the idle
watchdog guard, always behind refresh priority - so CPU accesses always win
and the measured protocol timing is untouched (the `test-storage-port` gate
runs device traffic concurrently with the CPU replay soak and re-checks the
N+4 deadline on every access). The grant issues half-word address
`{1'b1, mem_addr, 1'b0}`: the forced leading 1 pins all device traffic to
the upper (storage) half of the chip - it physically cannot reach CPU
memory. Without the define the module is bit-identical to the plain pack16
build.
