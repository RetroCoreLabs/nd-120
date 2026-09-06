/****************************************************************************
** Lint-only stubs for the Xilinx clocking primitives                      **
**                                                                         **
** Full path: Verilog/fpga/qmtech-a35t/rtl/lint_stubs.v                    **
**                                                                         **
** FOR `make lint` ONLY. This file is NOT in build.tcl's source list and    **
** must never be: Vivado supplies the real MMCME2_BASE and BUFG from its    **
** UNISIM library, and handing it these hollow versions instead would give  **
** a bitstream with no clock at all.                                        **
**                                                                         **
** Verilator has no UNISIM library, so without stubs it stops at "Cannot    **
** find file containing module: 'MMCME2_BASE'" and never reaches the CPU -  **
** which turns a useful lint into a check that only ever reports the same   **
** two missing primitives. With them, lint covers the whole design.         **
**                                                                         **
** The behaviour modelled is only enough to keep lint honest about          **
** connectivity and widths: outputs are driven so nothing reads a floating  **
** net, and the MMCM reports locked. No frequency, no phase, no jitter -    **
** the timing these parts actually provide is the Vivado build's business.  **
**                                                                         **
** Ronny Hansen                                                            **
*****************************************************************************/
`default_nettype none

//! Global clock buffer. Real one buffers; this one wires straight through.
module BUFG (
    input  wire I,
    output wire O
);
  assign O = I;
endmodule

//! Mixed-mode clock manager, base version. The stub passes the input clock
//! to every output unchanged and holds LOCKED high; the parameters are
//! accepted and ignored, so a wrong divider is a Vivado-time error and not
//! something lint could ever catch. Ports match the 7-series primitive so a
//! mistyped or missing connection in the top level IS caught.
module MMCME2_BASE #(
    parameter BANDWIDTH        = "OPTIMIZED",
    parameter real CLKFBOUT_MULT_F  = 5.000,
    parameter real CLKFBOUT_PHASE   = 0.000,
    parameter real CLKIN1_PERIOD    = 0.000,
    parameter real CLKOUT0_DIVIDE_F = 1.000,
    parameter integer CLKOUT1_DIVIDE = 1,
    parameter integer CLKOUT2_DIVIDE = 1,
    parameter integer CLKOUT3_DIVIDE = 1,
    parameter integer CLKOUT4_DIVIDE = 1,
    parameter integer CLKOUT5_DIVIDE = 1,
    parameter integer CLKOUT6_DIVIDE = 1,
    parameter real CLKOUT0_PHASE = 0.000,
    parameter real CLKOUT1_PHASE = 0.000,
    parameter real CLKOUT2_PHASE = 0.000,
    parameter real CLKOUT3_PHASE = 0.000,
    parameter real CLKOUT4_PHASE = 0.000,
    parameter real CLKOUT5_PHASE = 0.000,
    parameter real CLKOUT6_PHASE = 0.000,
    parameter real CLKOUT0_DUTY_CYCLE = 0.500,
    parameter integer DIVCLK_DIVIDE = 1,
    parameter CLKOUT4_CASCADE = "FALSE",
    parameter STARTUP_WAIT     = "FALSE",
    parameter real REF_JITTER1 = 0.010
) (
    output wire CLKOUT0,
    output wire CLKOUT0B,
    output wire CLKOUT1,
    output wire CLKOUT1B,
    output wire CLKOUT2,
    output wire CLKOUT2B,
    output wire CLKOUT3,
    output wire CLKOUT3B,
    output wire CLKOUT4,
    output wire CLKOUT5,
    output wire CLKOUT6,
    output wire CLKFBOUT,
    output wire CLKFBOUTB,
    output wire LOCKED,
    input  wire CLKIN1,
    input  wire CLKFBIN,
    input  wire PWRDWN,
    input  wire RST
);
  assign CLKOUT0  = CLKIN1;
  assign CLKOUT1  = CLKIN1;
  assign CLKOUT2  = CLKIN1;
  assign CLKOUT3  = CLKIN1;
  assign CLKOUT4  = CLKIN1;
  assign CLKOUT5  = CLKIN1;
  assign CLKOUT6  = CLKIN1;
  assign CLKFBOUT = CLKIN1;
  assign CLKOUT0B  = ~CLKIN1;
  assign CLKOUT1B  = ~CLKIN1;
  assign CLKOUT2B  = ~CLKIN1;
  assign CLKOUT3B  = ~CLKIN1;
  assign CLKFBOUTB = ~CLKIN1;
  assign LOCKED    = 1'b1;

  /* verilator lint_off UNUSEDSIGNAL */
  wire unused = &{1'b0, CLKFBIN, PWRDWN, RST};
  /* verilator lint_on UNUSEDSIGNAL */
endmodule

`default_nettype wire
