# CGA_MIC Simulation & Testbenches

Testbenches for `Verilog/DELILAH-CPU/CGA_MIC/circuit/` (the project convention:
a `sim/` folder next to the module).

## Self-checking unit tests (iverilog)

Each target below is registered in `Verilog/tests/run_all_tests.sh` and runs
under `make test`. Most build the testbench more than once - in the default
mode and with `-DFPGA_FF_MODE` and/or `-DUSE_TRANSPARENT_LATCHES` - see the
`Makefile` for the exact builds.

| Target | Testbench | Module under test |
|--------|-----------|-------------------|
| `make test-masel-basic`   | `CGA_MIC_MASEL_tb.v`        | MASEL (address source select) |
| `make test-mic-csel`      | `CGA_MIC_CSEL_tb.v`         | CSEL |
| `make test-mic-incount`   | `CGA_MIC_INCOUNT_tb.v`      | INCOUNT |
| `make test-mic-iinc`      | `CGA_MIC_IINC_tb.v`         | IINC (NEXT = IW + 1) |
| `make test-mic-ipos`      | `CGA_MIC_IPOS_tb.v`         | IPOS (final address mux, trap-vector override) |
| `make test-mic-stackbit`  | `CGA_MIC_STACK_BIT_tb.v`    | return stack, one bit |
| `make test-mic-stackbit12`| `CGA_MIC_STACK_BIT12_tb.v`  | return stack, bit 12 |
| `make test-mic-stack`     | `CGA_MIC_STACK_tb.v`        | return stack |
| `make test-mic-wcareg`    | `CGA_MIC_WCAREG_tb.v`       | WCA register |
| `make test-mic-repeat`    | `CGA_MIC_MASEL_REPEAT_tb.v` | MASEL repeat register |
| `make test-mic-condreg`   | `CGA_MIC_CONDREG_tb.v`      | condition register |
| `make test-mic-top`       | `CGA_MIC_tb.v`              | whole CGA_MIC next-address machine |

## Exploratory MASEL race testbenches (not pass/fail)

```bash
make test-masel-cycle    # MASEL_cycle_tb.v
make test-masel-iw       # MASEL_iw_capture_tb.v
make test-masel          # both, plus test-masel-basic
```

These two print EXPECTED FAIL lines on purpose: they model the FPGA race
where SC5/SC6 and MCLK change on the same sysclk edge. They are not in the
registry for that reason (`run_all_tests.sh`, "NOT in the registry").

- `MASEL_cycle_tb.v` - the full microcode address cycle including the IINC
  feedback loop (NEXT = IW + 1): sequential NEXT, JMP target capture (13-bit
  address from the CSBIT fields), RETURN (from the stack), REPEAT (IW feeds
  back to itself), SC5/SC6 races, a 1-sysclk active phase, and IW/W
  stability while MCLK=1.
- `MASEL_iw_capture_tb.v` - regIW capture timing, with a parallel
  negedge-sysclk variant (V_NEG) for side-by-side comparison.

Both write VCD files (`MASEL_cycle_tb.vcd`, `MASEL_iw_capture_tb.vcd`) for GTKWave.

## Full CGA_MIC test (Verilator)

```bash
make all    # compile + run + open GTKWave (mic.gtkw)
make run    # compile + run (no GTKWave)
```
