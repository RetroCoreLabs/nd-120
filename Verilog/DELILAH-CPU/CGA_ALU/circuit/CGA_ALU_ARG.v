
/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/ALU/ARG                                                          **
** ARG REGISTER                                                          **
**                                                                       **
** Page 53                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 30-JAN-2025                                            **
** Ronny Hansen                                                          **
***************************************************************************/

module CGA_ALU_ARG (
    input        sysclk,     //! FPGA system clock (P2: ALUCLK_EN capture)
    input        ALUCLK_EN,  //! ALUCLK clock-enable pulse (FPGA_FF_MODE, else 0)
    input        ALUCLK,     //! ALU clock signal (from CPU_PROC_CGA_33.ALUCLK)
    input [15:0] CSBIT_15_0,  //! Control Store Bits (from CPU_PROC_CGA_33.CSBITS[15:0])

    output [15:0] ARG_15_0
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [15:0] s_csbits_15_0;
  wire        s_aluclk;

  reg [15:0] regArg;

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_csbits_15_0[15:0] = CSBIT_15_0;
  assign s_aluclk            = ALUCLK;

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
   assign ARG_15_0            = regArg;

  /*******************************************************************************
   ** Here all sub-circuits are defined                                          **
   *******************************************************************************/

  // P2b (docs/plan-fix-unconstrained-clocks.md): in FF mode capture on
  // posedge sysclk gated by ALUCLK_EN (aligned to the ALUCLK rise)
  // instead of clocking on the routed net.
`ifdef FPGA_FF_MODE
  /* verilator lint_off UNUSEDSIGNAL */
  wire unused_aluclk = s_aluclk;
  /* verilator lint_on UNUSEDSIGNAL */
  always @(posedge sysclk) begin
    if (ALUCLK_EN) regArg <= s_csbits_15_0;
  end
`else
  /* verilator lint_off UNUSEDSIGNAL */
  wire unused_en = sysclk & ALUCLK_EN;
  /* verilator lint_on UNUSEDSIGNAL */
  always @(posedge s_aluclk) begin
    regArg <= s_csbits_15_0;
  end
`endif


endmodule
