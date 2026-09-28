
# Verilog code for DGA (Decode Gate Array)

| File                     | Description |
|--------------------------|-------------|
| [DECODE_DGA.v](DGA/circuit/DECODE_DGA.v)           | Top module of the DGA |
| [DECODE_DGA_COMM.v](DGA/circuit/DECODE_DGA_COMM.v) | Decode Internal Databus Commands |
| [DECODE_DGA_IDBS.v](DGA/circuit/DECODE_DGA_IDBS.v) | Decode Internal Databus SOURCE (IDBS). Generates ENABLE signals for the chips to be read or written |
| [DECODE_DGA_POW.v](DGA/circuit/DECODE_DGA_POW.v)   | POWER detection |
| [F091.v](DGA/circuit/F091.v)                       | NEC F091 - H,L LEVEL GENERATOR |
| [F103.v](DGA/circuit/F103.v)                       | NEC F103 - Inverter x3 signal drive |
| [F571.v](DGA/circuit/F571.v)                       | NEC F571 - 2 TO 1 MULTIPLEXER |
| [F595.v](DGA/circuit/F595.v)                       | NEC F595 - R/S Latch with Gated input |
| [F617.v](DGA/circuit/F617.v)                       | NEC F617 - D Flip-Flop with RB, SB |
| [F714.v](DGA/circuit/F714.v)                       | NEC F714 - T Flip-Flop with R, S |
| [F924.v](DGA/circuit/F924.v)                       | NEC F924 - 4-BIT D-TYPE FLIP-FLOP |

The FIFO controller, FIFO delay and FIFO data pages (`DECODE_DGA_PFIFC.v`,
`DECODE_DGA_PFIFC_DELAY.v`, `DECODE_DGA_PFIFD.v`) were written once and then
removed; `Verilog/Shared/support/FIFO_8BIT.v` replaces all three.

# Tests

The testbenches are in `DGA/sim/` (`*_tb.v`, one per module and one per NEC
cell); the ones that check themselves are registered in
`Verilog/tests/run_all_tests.sh`.

[GTKWave](DGA/readme.md)
