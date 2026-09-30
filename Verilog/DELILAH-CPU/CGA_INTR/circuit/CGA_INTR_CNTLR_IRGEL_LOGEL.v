/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/INTR/CNTLR/IRGEL/LOGEL                                           **
** LOGEL                                                                 **
**                                                                       **
** Page 94                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 10-NOV-2024                                            **
** Ronny Hansen                                                          **
***************************************************************************/


module CGA_INTR_CNTLR_IRGEL_LOGEL (
    input sysclk,   //! FPGA system clock (P2: MCLK_EN capture)
    input MCLK_EN,  //! MCLK clock-enable pulse (FPGA_FF_MODE, else 0)

    input FIDB04,   //! FIDB (from CGA_INTR.FIDBO_15_0[4])
    input L,
    input LIENABN,
    input LOGAS,
    input M,
    input MCLK,     //! Master Clock (from CGA_INTR.MCLK)
    input N,

    output LOGSN    //! Logical Segment Number, active low (to CGA_INTR.LOGSN)
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire s_d;
  wire s_fidbo4;
  wire s_l_n;
  wire s_l;
  wire s_lienab_n;
  wire s_logas;
  wire s_logs_n_out;
  wire s_m;
  wire s_mclk;
  wire s_n;
  wire s_nand_fidbo4_l_m;
  wire s_nand_lienabn_n;
  wire s_nand_ln_m_logsn;
  wire s_nand_logas_n;

  /*******************************************************************************
   ** The module functionality is described here                                 **
   *******************************************************************************/

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_fidbo4 = FIDB04;
  assign s_l = L;
  assign s_lienab_n = LIENABN;
  assign s_logas = LOGAS;
  assign s_m = M;
  assign s_mclk = MCLK;
  assign s_n = N;

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
  assign LOGSN = s_logs_n_out;

  /*******************************************************************************
   ** Here all in-lined components are defined                                   **
   *******************************************************************************/

  // NOT Gate
  assign s_l_n = ~s_l;

  /*******************************************************************************
   ** Here all normal components are defined                                     **
   *******************************************************************************/
  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_1 (
      .input1(s_fidbo4),
      .input2(s_l),
      .input3(s_m),
      .result(s_nand_fidbo4_l_m)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_2 (
      .input1(s_logas),
      .input2(s_n),
      .result(s_nand_logas_n)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_3 (
      .input1(s_lienab_n),
      .input2(s_n),
      .result(s_nand_lienabn_n)
  );

  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_4 (
      .input1(s_l_n),
      .input2(s_m),
      .input3(s_logs_n_out),
      .result(s_nand_ln_m_logsn)
  );

  OR_GATE_4_INPUTS #(
      .BubblesMask(4'hF)
  ) GATES_5 (
      .input1(s_nand_fidbo4_l_m),
      .input2(s_nand_logas_n),
      .input3(s_nand_lienabn_n),
      .input4(s_nand_ln_m_logsn),
      .result(s_d)
  );

  // MCLK domain (CGA_INTR.MCLK, rising edge)
  D_FLIPFLOP_EN #(
      .USE_ENABLE(MCLK_CE)
  ) MEMORY_6 (
      .sysclk(sysclk),
      .EN(MCLK_EN),
      .clock(s_mclk),
      .d(s_d),
      .preset(1'b0),
      .q(s_logs_n_out),
      .qBar(),
      .reset(1'b0),
      .tick(1'b1)
  );


endmodule
