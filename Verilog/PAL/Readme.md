# Verilog implementation of PAL

## Verilog

In this folder you find all the verilog code for the PAL chips

## Verilator test code

In the subfolders named pr PAL you find makefile, and C test code that together with Verilator tests the PAL. GTKWave is needed to view the output and to manually verify its functionality.
In the future I hope to make the tests more automated to validate that the PAL code works without a visual inspection.

## Design documents 

The code is based on the original [design documents](https://github.com/RetroCoreLabs/nd-120/tree/main/DesignDocuments/PAL-Code) and the PALASM code is manually converted to Verilog
