# ND-BUS seam gate (RTL ⟷ portable C core, in Verilator)

**Status: WORKING, validated 2026-07-19.** `make` prints `TB_RESULT: PASS` (6/6).

This is the first gate that proves the **portable C device cores** behave
correctly when driven through the **authoritative Verilog bus seam**
(`../circuit/ND_BUS_SLAVE.v`) — with **no ND-100 CPU and no hardware**, so it
runs in CI. It is the Verilator twin of the Tang-20K `nd-bus-test` exerciser:
the exerciser generates the same IOX cycles from a UART menu on silicon; here a
scripted C++ harness generates them in simulation.

## What it does

`nd_bus_gate.cpp`:
1. Instantiates the Verilated `ND_BUS_SLAVE`.
2. Drives the **CPU side** (BAPR/BIOXE/BINACK/BD…) to issue real IOX read/write
   cycles.
3. Bridges the **device side** (`iox_addr/wr/wdata/rd/rdata`, `int_pending`,
   `ident_*`) to a real `nd_lineprinter` core — **the "one C++ adapter"** from
   `NDModulE/docs/rtl-gate-plan.md`. `iox_wr`→`write()`, `iox_rd`→`iox_rdata`
   from `read()`, `interrupt_bits`→`int_pending`, `ident_strobe`→`ident()`.
4. Asserts the core's behaviour end-to-end through the RTL: a printed byte
   reaches the paper, status reads back, and enabling the interrupt makes the
   RTL assert BINT10.

Char devices gate first (no DMA infra), per the gate plan. Next: terminal
(rx/tx), then a full IDENT cycle, then wire `ND_DMA_MASTER` for the DMA devices
(floppy/SMD), then turn the scripted driver into the UART-menu exerciser for the
Tang rig.

## Build / run

```sh
make                 # normal `verilator` on PATH (WSL/Linux)
```

The C cores come from `$(NDDEVICECORE)`, which defaults to the nd-120
submodule `Verilog/ND-BUS-DEVICES/portable` (`Makefile`: `NDDEVICECORE ?=
../../portable`). Run `git submodule update --init` first if it is empty.
On Windows the oss-cad-suite perl `verilator` wrapper does not work; set
`VERILATOR_ROOT` and `PATH` to your oss-cad-suite install and run
`make VERILATOR=verilator_bin.exe`.

## TODO to make this the real gate

- Register in the machine-checkable test harness `Verilog/tests/run_all_tests.sh`
  (it already emits `TB_RESULT: PASS`; not registered as of 28-SEP-2026).
- Add terminal + IDENT + DMA (ND_DMA_MASTER) coverage.
