# Verilog code for DELILAH-CPU

The DELILAH CPU gate array (CGA). Each folder holds one block: `circuit/` is the
Verilog, `sim/` its testbenches, `doc/` the generated module pages.

| Folder      | Block |
|-------------|-------|
| CGA         | Top level of the gate array (DELILAH) |
| CGA_ALU     | ALU |
| CGA_DCD     | Decoder: microword COMM / IDBS / MIS fields to control signals |
| CGA_IDBCTL  | Internal data bus (IDB) control |
| CGA_INTR    | Interrupt controller |
| CGA_MAC     | Memory access controller |
| CGA_MIC     | Microcode controller (next-address logic, loop counter) - see `CGA_MIC/sim/README.md` |
| CGA_TESTMUX | Test multiplexer |
| CGA_TRAP    | Trap handler |
| CGA_WRF     | Register file |

## Tests

Every self-checking testbench for these blocks is registered in
`Verilog/tests/run_all_tests.sh` with its pass pattern; `make test` in
`Verilog/` runs them all. The CPU self-test and the instruction-verify
areas run on the whole machine - see
`Verilog/tests/instruction-verify/CAMPAIGN-STATUS.md`.
