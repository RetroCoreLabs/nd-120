/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/MIC/INCOUNT                                                      **
** INCOUNT                                                               **
**                                                                       **
** Page 23                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 10-NOV-2024                                            **
** Ronny Hansen                                                          **
***************************************************************************/

module CGA_MIC_INCOUNT (
    input sysclk,   //! FPGA system clock (P2: MCLK_EN capture)
    input MCLK_EN,  //! MCLK clock-enable pulse (FPGA_FF_MODE, else 0)

    input CD0,      //! Data bus for communication (from CGA_MIC.CD_15_0[0])
    input CD1,      //! Data bus for communication (from CGA_MIC.CD_15_0[1])
    input EC,
    input LWCAN,    //! Latch WCA (from CGA_MIC.LWCAN)
    input MCLK,     //! Main clock signal (from CGA_MIC.MCLK)
    input MRN,      //! Memory read (from CGA_MIC.MRN)

    output CSWAN0,
    output CSWAN1
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire s_cd0;
  wire s_cd1;
  wire s_cswan0_out;
  wire s_cswan1_out;
  wire s_ec;
  wire s_ff6_qn_out;
  wire s_ff7_qn_out;
  wire s_gates1_out;
  wire s_gates2_out;
  wire s_gates3_out;
  wire s_lwca_n;
  wire s_mclk;
  wire s_mr_n;
  wire s_mr;
  wire s_plexers4_n_out;
  wire s_plexers4_out;
  wire s_plexers5_n_out;
  wire s_plexers5_out;

  /*******************************************************************************
   ** The module functionality is described here                                 **
   *******************************************************************************/

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_mclk           = MCLK;
  assign s_cd0            = CD0;
  assign s_mr_n           = MRN;
  assign s_cd1            = CD1;
  assign s_lwca_n         = LWCAN;
  assign s_ec             = EC;

  // P2 (docs/plan-fix-unconstrained-clocks.md): in FF mode the MCLK-
  // clocked registers capture on posedge sysclk gated by MCLK_EN
  // (aligned to the MCLK rise) instead of clocking on the routed net.
`ifdef FPGA_FF_MODE
  localparam MCLK_CE = 1;
`else
  localparam MCLK_CE = 0;
`endif

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign CSWAN0           = s_cswan0_out;
  assign CSWAN1           = s_cswan1_out;

  /*******************************************************************************
   ** Here all in-lined components are defined                                   **
   *******************************************************************************/

  // NOT Gate
  assign s_plexers4_n_out = ~s_plexers4_out;
  assign s_plexers5_n_out = ~s_plexers5_out;
  assign s_mr             = ~s_mr_n;

  /*******************************************************************************
   ** Here all normal components are defined                                     **
   *******************************************************************************/
  XOR_GATE_ONEHOT #(
      .BubblesMask(2'b00)
  ) GATES_1 (
      .input1(s_ec),
      .input2(s_ff6_qn_out),
      .result(s_gates1_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_2 (
      .input1(s_ff6_qn_out),
      .input2(s_ec),
      .result(s_gates2_out)
  );

  XNOR_GATE_ONEHOT #(
      .BubblesMask(2'b00)
  ) GATES_3 (
      .input1(s_gates2_out),
      .input2(s_ff7_qn_out),
      .result(s_gates3_out)
  );

  Multiplexer_2 PLEXERS_4 (
      .muxIn_0(s_cd0),
      .muxIn_1(s_gates1_out),
      .muxOut(s_plexers4_out),
      .sel(s_lwca_n)
  );

  Multiplexer_2 PLEXERS_5 (
      .muxIn_0(s_cd1),
      .muxIn_1(s_gates3_out),
      .muxOut(s_plexers5_out),
      .sel(s_lwca_n)
  );

  // MCLK domain: clocked on posedge s_mclk (async preset s_mr)
  D_FLIPFLOP_EN #(.USE_ENABLE(MCLK_CE), .ASYNC_RESET(1)
  ) MEMORY_6 (
      .sysclk(sysclk),
      .EN(MCLK_EN),
      .clock(s_mclk),
      .d(s_plexers4_n_out),
      .preset(s_mr),
      .q(s_cswan0_out),
      .qBar(s_ff6_qn_out),
      .reset(1'b0),
      .tick(1'b1)
  );

  // MCLK domain: clocked on posedge s_mclk (async preset s_mr)
  D_FLIPFLOP_EN #(.USE_ENABLE(MCLK_CE), .ASYNC_RESET(1)
  ) MEMORY_7 (
      .sysclk(sysclk),
      .EN(MCLK_EN),
      .clock(s_mclk),
      .d(s_plexers5_n_out),
      .preset(s_mr),
      .q(s_cswan1_out),
      .qBar(s_ff7_qn_out),
      .reset(1'b0),
      .tick(1'b1)
  );


endmodule
