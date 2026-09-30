/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/ALU/OUTMUX/IDBS                                                  **
** IDBS MUX                                                              **
**                                                                       **
** Page 55                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 9-FEB-2025                                             **
** Ronny Hansen                                                          **
***************************************************************************/

module CGA_ALU_OUTMUX_IDBS (
    input       sysclk,     //! FPGA system clock (P2: ALUCLK_EN capture)
    input       ALUCLK_EN,  //! ALUCLK clock-enable pulse (FPGA_FF_MODE, else 0)
    input       ALUCLK,     //! ALU clock signal (from CPU_PROC_CGA_33.ALUCLK)
    input       ALUD2N,     //! ALU Data 2, active low signal (from CGA_CPU_ALU_CONTR.ALUD2N)
    input [4:0] CSIDBS_4_0,  //! Control Store Bits (from CPU_PROC_CGA_33.CSBITS[41:37])

    output EA,
    output EAARG,
    output EABARG,
    output EARG,
    output EBARG,
    output EBMG,
    output EDBR,
    output EF,
    output EFIDB,
    output EGPRH,
    output EGPRL,
    output EGPRS,
    output ESTS,
    output ESWAP
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [4:0] s_csidbs_4_0;
  wire       _ef_n_out;
  wire       s_aluclk;
  wire       s_alud2_n;
  wire       s_alud2;
  wire       s_and_csidbs4n_csidbs3;
  wire       s_and_idbs3n_idbs4n;
  wire       s_csidbs0_n;
  wire       s_csidbs2_n;
  wire       s_csidbs3_n;
  wire       s_csidbs4_n;
  wire       s_ea_n_out;
  wire       s_ea_out;
  wire       s_eaarg_n_out;
  wire       s_eaarg_out;
  wire       s_eabarg_out;
  wire       s_earg_n_out;
  wire       s_earg_out;
  wire       s_ebarg_out;
  wire       s_ebmg_n_out;
  wire       s_ebmg_out;
  wire       s_edbr_n_out;
  wire       s_edbr_out;
  wire       s_edidb_n_out;
  wire       s_edidb_out;
  wire       s_ef_out;
  wire       s_egprh_out;
  wire       s_egprl_out;
  wire       s_egprs_out;
  wire       s_ests_n_out;
  wire       s_ests_out;
  wire       s_eswap_n_out;
  wire       s_eswap_out;
  wire       s_r1_a;
  wire       s_r1_b;
  wire       s_r1_c;
  wire       s_r1_d;
  wire       s_r1_e;
  wire       s_r1_f;
  wire       s_r1_g;
  wire       s_r1_h;
  wire       s_r1_qan_out;
  wire       s_r2_a;
  wire       s_r2_b_n;
  wire       s_r2_b;
  wire       s_r2_c;
  wire       s_r2_d;
  wire       s_r2_e;

  /*******************************************************************************
   ** The module functionality is described here                                 **
   *******************************************************************************/

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_csidbs_4_0[4:0] = CSIDBS_4_0;
  assign s_aluclk          = ALUCLK;

  // P2b (docs/plan-fix-unconstrained-clocks.md): in FF mode the ALUCLK-
  // clocked registers capture on posedge sysclk gated by ALUCLK_EN
  // (aligned to the ALUCLK rise) instead of clocking on the routed net.
`ifdef FPGA_FF_MODE
  localparam ALUCLK_CE = 1;
`else
  localparam ALUCLK_CE = 0;
`endif

  assign s_alud2_n         = ALUD2N;

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign EA                = s_ea_out;
  assign EAARG             = s_eaarg_out;
  assign EABARG            = s_eabarg_out;
  assign EARG              = s_earg_out;
  assign EBARG             = s_ebarg_out;
  assign EBMG              = s_ebmg_out;
  assign EDBR              = s_edbr_out;
  assign EF                = s_ef_out;
  assign EFIDB             = s_edidb_out;
  assign EGPRH             = s_egprh_out;
  assign EGPRL             = s_egprl_out;
  assign EGPRS             = s_egprs_out;
  assign ESTS              = s_ests_out;
  assign ESWAP             = s_eswap_out;

  /*******************************************************************************
   ** Here all in-lined components are defined                                   **
   *******************************************************************************/

  // NOT Gate
  assign s_r2_b_n          = ~s_r2_b;
  assign s_eaarg_out       = ~s_eaarg_n_out;
  assign s_edidb_out       = ~s_edidb_n_out;
  assign s_earg_out        = ~s_earg_n_out;
  assign s_ests_out        = ~s_ests_n_out;
  assign s_eswap_out       = ~s_eswap_n_out;
  assign s_ebmg_out        = ~s_ebmg_n_out;
  assign s_edbr_out        = ~s_edbr_n_out;
  assign s_alud2           = ~s_alud2_n;
  assign s_ea_out          = ~s_ea_n_out;
  assign s_ef_out          = ~_ef_n_out;
  assign s_csidbs4_n       = ~s_csidbs_4_0[4];
  assign s_csidbs3_n       = ~s_csidbs_4_0[3];
  assign s_csidbs2_n       = ~s_csidbs_4_0[2];
  assign s_csidbs0_n       = ~s_csidbs_4_0[0];

  /*******************************************************************************
   ** Here all normal components are defined                                     **
   *******************************************************************************/
  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_1 (
      .input1(s_r1_g),
      .input2(s_r2_a),
      .result(s_r2_b)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_2 (
      .input1(s_r1_c),
      .input2(s_r2_e),
      .result(s_r2_d)
  );

  NAND_GATE_8_INPUTS #(
      .BubblesMask(8'h00)
  ) GATES_3 (
      .input1(s_r1_b),
      .input2(s_r1_c),
      .input3(s_r1_d),
      .input4(s_r1_e),
      .input5(s_r1_f),
      .input6(s_r1_h),
      .input7(s_r2_b_n),
      .input8(s_r2_e),
      .result(s_r2_c)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_4 (
      .input1(s_alud2),
      .input2(s_r1_qan_out),
      .result(s_ea_n_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_5 (
      .input1(s_alud2_n),
      .input2(s_r1_qan_out),
      .result(_ef_n_out)
  );

  AND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_6 (
      .input1(s_csidbs4_n),
      .input2(s_csidbs_4_0[3]),
      .result(s_and_csidbs4n_csidbs3)
  );

  NAND_GATE_5_INPUTS #(
      .BubblesMask({1'b0, 4'h0})
  ) GATES_7 (
      .input1(s_csidbs_4_0[4]),
      .input2(s_csidbs3_n),
      .input3(s_csidbs2_n),
      .input4(s_csidbs_4_0[1]),
      .input5(s_csidbs0_n),
      .result(s_r2_e)
  );

  AND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_8 (
      .input1(s_csidbs3_n),
      .input2(s_csidbs4_n),
      .result(s_and_idbs3n_idbs4n)
  );


  /*******************************************************************************
   ** Here all sub-circuits are defined                                          **
   *******************************************************************************/

  ND38GLP IDBS_G1 (
      .A (s_csidbs_4_0[0]),
      .B (s_csidbs_4_0[1]),
      .C (s_csidbs_4_0[2]),
      .G (s_and_idbs3n_idbs4n),
      .Z0(s_r1_a),
      .Z1(s_r1_b),
      .Z2(s_r1_c),
      .Z3(s_r1_d),
      .Z4(s_r1_e),
      .Z5(),
      .Z6(s_r1_f),
      .Z7()
  );

  ND38GLP IDBS_G2 (
      .A (s_csidbs_4_0[0]),
      .B (s_csidbs_4_0[1]),
      .C (s_csidbs_4_0[2]),
      .G (s_and_csidbs4n_csidbs3),
      .Z0(s_r1_g),
      .Z1(s_r1_h),
      .Z2(),
      .Z3(),
      .Z4(s_r2_a),
      .Z5(),
      .Z6(),
      .Z7()
  );


  R81_EN #(.USE_ENABLE(ALUCLK_CE)) IDBS_R1 (
      .sysclk(sysclk),
      .EN (ALUCLK_EN),
      .CP (s_aluclk),
      .A  (s_r1_a),
      .B  (s_r1_b),
      .C  (s_r1_c),
      .D  (s_r1_d),
      .E  (s_r1_e),
      .F  (s_r1_f),
      .G  (s_r1_g),
      .H  (s_r1_h),
      .QA (),
      .QAN(s_r1_qan_out),
      .QB (s_ebmg_n_out),
      .QBN(),
      .QC (),
      .QCN(s_egprh_out),
      .QD (s_edbr_n_out),
      .QDN(),
      .QE (s_earg_n_out),
      .QEN(),
      .QF (s_ests_n_out),
      .QFN(),
      .QG (),
      .QGN(s_ebarg_out),
      .QH (s_eswap_n_out),
      .QHN()
  );


  R81_EN #(.USE_ENABLE(ALUCLK_CE)) IDBS_R2 (
      .sysclk(sysclk),
      .EN (ALUCLK_EN),
      .CP (s_aluclk),
      .A  (s_r2_a),
      .B  (s_r2_b),
      .C  (s_r2_c),
      .D  (s_r2_d),
      .E  (s_r2_e),
      .F  (1'b0),
      .G  (1'b0),
      .H  (1'b0),
      .QA (s_eaarg_n_out),
      .QAN(),
      .QB (s_eabarg_out),
      .QBN(),
      .QC (s_edidb_n_out),
      .QCN(),
      .QD (s_egprl_out),
      .QDN(),
      .QE (),
      .QEN(s_egprs_out),
      .QF (),
      .QFN(),
      .QG (),
      .QGN(),
      .QH (),
      .QHN()
  );


endmodule
