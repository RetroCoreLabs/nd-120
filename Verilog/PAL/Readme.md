# Verilog implementation of PAL

## Verilog

In this folder you find all the verilog code for the PAL chips

## Verilator test code

In the subfolders named pr PAL you find makefile, and C test code that together with Verilator tests the PAL. GTKWave is needed to view the output.

## Automated tests

`sim/` holds the self-checking PAL testbenches (`make test-all`, `make test-pal-provenance` and the per-PAL targets); they are registered in `Verilog/tests/run_all_tests.sh` and run under `make test`. How each PAL model is checked against its original PALASM listing is described in [PROVENANCE.md](PROVENANCE.md).

## Design documents 

The code is based on the original [design documents](https://github.com/RetroCoreLabs/nd-120/tree/main/DesignDocuments/PAL-Code) and the PALASM code is manually converted to Verilog
