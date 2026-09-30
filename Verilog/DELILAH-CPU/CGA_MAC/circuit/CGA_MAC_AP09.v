/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/MAC/AP09                                                         **
** AP09                                                                  **
**                                                                       **
** Page 31                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 14-DEC-2024                                            **
** Ronny Hansen                                                          **
***************************************************************************/

module CGA_MAC_AP09 (
    // System input signals
    input sysclk,    // System clock in FPGA
    input sys_rst_n, // System reset in FPGA

    // Input signals
    input        ADDSEL,
    input [15:0] ADD_15_0,  //! Addition result output (from CGA_MAC_ADD.ADD_15_0)
    input        CDSEL,
    input [15:0] CD_15_0,  //! Command/Data bus (from CPU_PROC_CGA_33.CD_15_0)
    input        ECCRHIN,
    input        HOLD,
    input        MCLK,  //! Master CLock (from CGA_MAC.MCLK)
    input        MCLK_EN,     //! MCLK clock-enable pulse (FPGA_FF_MODE, else 0)
    input        NLCASEL,
    input [15:0] PR_15_0,  //! ALU P Register (from CGA_MAC.PR_15_0)
    input        PSEL,

    // Output signals
    output        ECCR,  //! Error Correction Code Register (to CGA_MAC.ECCR)
    output [15:0] ICA_15_0,
    output [15:0] LCA_15_0,  //! ALU Load Control Address (to CGA_MAC_ADD.LCA_15_0)
    output [ 9:0] MCA_9_0,  //! Microcode Address bits 9 to 0 (to CGA_MAC.MCA_9_0)
    output [15:0] NLCA_15_0  //! Next Latch Address bits 15 to 0 (to CGA_MAC.NLCA_15_0)
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [15:0] s_add_15_0;
  wire [15:0] s_lca_15_0_out;
  wire [ 9:0] s_mca_9_0_out;
  wire [15:0] s_ica_15_0_out;
  wire [15:0] s_cd_15_0;
  wire [15:0] s_pr_15_0;
  wire [15:0] s_nlca_15_0_out;
  wire        s_addsel;
  wire        s_cdsel;
  wire        s_eccr_out;
  wire        s_eccrhi_n;
  wire        s_hold;
  wire        s_ica0a_n;
  wire        s_ica0b_n;
  wire        s_ica10a_n;
  wire        s_ica10b_n;
  wire        s_ica11a_n;
  wire        s_ica11b_n;
  wire        s_ica12a_n;
  wire        s_ica12b_n;
  wire        s_ica13a_n;
  wire        s_ica13b_n;
  wire        s_ica14a_n;
  wire        s_ica14b_n;
  wire        s_ica15a_n;
  wire        s_ica15b_n;
  wire        s_ica1a_n;
  wire        s_ica1b_n;
  wire        s_ica2a_n;
  wire        s_ica2b_n;
  wire        s_ica3a_n;
  wire        s_ica3b_n;
  wire        s_ica4a_n;
  wire        s_ica4b_n;
  wire        s_ica5a_n;
  wire        s_ica5b_n;
  wire        s_ica6a_n;
  wire        s_ica6b_n;
  wire        s_ica7a_n;
  wire        s_ica7b_n;
  wire        s_ica8a_n;
  wire        s_ica8b_n;
  wire        s_ica9a_n;
  wire        s_ica9b_n;
  wire        s_mclk;
  wire        s_nlca0_n;
  wire        s_nlca1_n;
  wire        s_nlca10_n;
  wire        s_nlca11_n;
  wire        s_nlca12_n;
  wire        s_nlca13_n;
  wire        s_nlca14_n;
  wire        s_nlca15_n;
  wire        s_nlca2_n;
  wire        s_nlca3_n;
  wire        s_nlca4_n;
  wire        s_nlca5_n;
  wire        s_nlca6_n;
  wire        s_nlca7_n;
  wire        s_nlca8_n;
  wire        s_nlca9_n;
  wire        s_nlcasel;
  wire        s_psel;

  /*******************************************************************************
   ** The module functionality is described here                                 **
   *******************************************************************************/

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_add_15_0[15:0] = ADD_15_0;
  assign s_cd_15_0[15:0]  = CD_15_0;
  assign s_pr_15_0[15:0]  = PR_15_0;
  assign s_mclk           = MCLK;
  assign s_eccrhi_n       = ECCRHIN;
  assign s_addsel         = ADDSEL;
  assign s_cdsel          = CDSEL;
  assign s_psel           = PSEL;
  assign s_nlcasel        = NLCASEL;
  assign s_hold           = HOLD;

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign ECCR             = s_eccr_out;
  assign ICA_15_0         = s_ica_15_0_out[15:0];
  assign LCA_15_0         = s_lca_15_0_out[15:0];
  assign MCA_9_0          = s_mca_9_0_out[9:0];
  assign NLCA_15_0        = s_nlca_15_0_out[15:0];

  /*******************************************************************************
   ** Here all normal components are defined                                     **
   *******************************************************************************/

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_5 (
      .input1(s_nlcasel),
      .input2(s_nlca_15_0_out[0]),
      .result(s_nlca0_n)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_6 (
      .input1(s_nlcasel),
      .input2(s_nlca_15_0_out[1]),
      .result(s_nlca1_n)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_1 (
      .input1(s_nlcasel),
      .input2(s_nlca_15_0_out[2]),
      .result(s_nlca2_n)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_2 (
      .input1(s_nlcasel),
      .input2(s_nlca_15_0_out[3]),
      .result(s_nlca3_n)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_3 (
      .input1(s_nlcasel),
      .input2(s_nlca_15_0_out[4]),
      .result(s_nlca4_n)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_4 (
      .input1(s_nlcasel),
      .input2(s_nlca_15_0_out[5]),
      .result(s_nlca5_n)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_7 (
      .input1(s_nlcasel),
      .input2(s_nlca_15_0_out[6]),
      .result(s_nlca6_n)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_8 (
      .input1(s_nlcasel),
      .input2(s_nlca_15_0_out[7]),
      .result(s_nlca7_n)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_9 (
      .input1(s_nlcasel),
      .input2(s_nlca_15_0_out[8]),
      .result(s_nlca8_n)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_10 (
      .input1(s_nlcasel),
      .input2(s_nlca_15_0_out[9]),
      .result(s_nlca9_n)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_11 (
      .input1(s_nlcasel),
      .input2(s_nlca_15_0_out[10]),
      .result(s_nlca10_n)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_12 (
      .input1(s_nlcasel),
      .input2(s_nlca_15_0_out[11]),
      .result(s_nlca11_n)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_13 (
      .input1(s_nlcasel),
      .input2(s_nlca_15_0_out[12]),
      .result(s_nlca12_n)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_14 (
      .input1(s_nlcasel),
      .input2(s_nlca_15_0_out[13]),
      .result(s_nlca13_n)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_15 (
      .input1(s_nlcasel),
      .input2(s_nlca_15_0_out[14]),
      .result(s_nlca14_n)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_16 (
      .input1(s_nlcasel),
      .input2(s_nlca_15_0_out[15]),
      .result(s_nlca15_n)
  );

  OR_GATE_3_INPUTS #(
      .BubblesMask(3'b111)
  ) GATES_20 (
      .input1(s_ica0a_n),
      .input2(s_ica0b_n),
      .input3(s_nlca0_n),
      .result(s_ica_15_0_out[0])
  );

  OR_GATE_3_INPUTS #(
      .BubblesMask(3'b111)
  ) GATES_21 (
      .input1(s_ica1a_n),
      .input2(s_ica1b_n),
      .input3(s_nlca1_n),
      .result(s_ica_15_0_out[1])
  );

  OR_GATE_3_INPUTS #(
      .BubblesMask(3'b111)
  ) GATES_22 (
      .input1(s_ica2a_n),
      .input2(s_ica2b_n),
      .input3(s_nlca2_n),
      .result(s_ica_15_0_out[2])
  );

  OR_GATE_3_INPUTS #(
      .BubblesMask(3'b111)
  ) GATES_17 (
      .input1(s_ica3a_n),
      .input2(s_ica3b_n),
      .input3(s_nlca3_n),
      .result(s_ica_15_0_out[3])
  );

  OR_GATE_3_INPUTS #(
      .BubblesMask(3'b111)
  ) GATES_18 (
      .input1(s_ica4a_n),
      .input2(s_ica4b_n),
      .input3(s_nlca4_n),
      .result(s_ica_15_0_out[4])
  );

  OR_GATE_3_INPUTS #(
      .BubblesMask(3'b111)
  ) GATES_19 (
      .input1(s_ica5a_n),
      .input2(s_ica5b_n),
      .input3(s_nlca5_n),
      .result(s_ica_15_0_out[5])
  );

  OR_GATE_3_INPUTS #(
      .BubblesMask(3'b111)
  ) GATES_23 (
      .input1(s_ica6a_n),
      .input2(s_ica6b_n),
      .input3(s_nlca6_n),
      .result(s_ica_15_0_out[6])
  );

  OR_GATE_3_INPUTS #(
      .BubblesMask(3'b111)
  ) GATES_24 (
      .input1(s_ica7a_n),
      .input2(s_ica7b_n),
      .input3(s_nlca7_n),
      .result(s_ica_15_0_out[7])
  );

  OR_GATE_3_INPUTS #(
      .BubblesMask(3'b111)
  ) GATES_25 (
      .input1(s_ica8a_n),
      .input2(s_ica8b_n),
      .input3(s_nlca8_n),
      .result(s_ica_15_0_out[8])
  );

  OR_GATE_3_INPUTS #(
      .BubblesMask(3'b111)
  ) GATES_26 (
      .input1(s_ica9a_n),
      .input2(s_ica9b_n),
      .input3(s_nlca9_n),
      .result(s_ica_15_0_out[9])
  );

  OR_GATE_3_INPUTS #(
      .BubblesMask(3'b111)
  ) GATES_27 (
      .input1(s_ica10a_n),
      .input2(s_ica10b_n),
      .input3(s_nlca10_n),
      .result(s_ica_15_0_out[10])
  );

  OR_GATE_3_INPUTS #(
      .BubblesMask(3'b111)
  ) GATES_28 (
      .input1(s_ica11a_n),
      .input2(s_ica11b_n),
      .input3(s_nlca11_n),
      .result(s_ica_15_0_out[11])
  );

  OR_GATE_3_INPUTS #(
      .BubblesMask(3'b111)
  ) GATES_29 (
      .input1(s_ica12a_n),
      .input2(s_ica12b_n),
      .input3(s_nlca12_n),
      .result(s_ica_15_0_out[12])
  );

  OR_GATE_3_INPUTS #(
      .BubblesMask(3'b111)
  ) GATES_30 (
      .input1(s_ica13a_n),
      .input2(s_ica13b_n),
      .input3(s_nlca13_n),
      .result(s_ica_15_0_out[13])
  );

  OR_GATE_3_INPUTS #(
      .BubblesMask(3'b111)
  ) GATES_31 (
      .input1(s_ica14a_n),
      .input2(s_ica14b_n),
      .input3(s_nlca14_n),
      .result(s_ica_15_0_out[14])
  );

  OR_GATE_3_INPUTS #(
      .BubblesMask(3'b111)
  ) GATES_32 (
      .input1(s_ica15a_n),
      .input2(s_ica15b_n),
      .input3(s_nlca15_n),
      .result(s_ica_15_0_out[15])
  );


  /*******************************************************************************
   ** Here all sub-circuits are defined                                          **
   *******************************************************************************/

  // ICA - 0
  A02 ICA0A (      
      .A(s_lca_15_0_out[0]),
      .B(s_hold),
      .C(s_pr_15_0[0]),
      .D(s_psel),
      .Z(s_ica0a_n)
  );

  A02 ICA0B (
      .A(s_addsel),
      .B(s_add_15_0[0]),
      .C(s_cdsel),
      .D(s_cd_15_0[0]),
      .Z(s_ica0b_n)
  );

 // ICA - 1
  A02 ICA1A (
      .A(s_lca_15_0_out[1]),
      .B(s_hold),
      .C(s_pr_15_0[1]),
      .D(s_psel),
      .Z(s_ica1a_n)
  );

  A02 ICA1B (
      .A(s_addsel),
      .B(s_add_15_0[1]),
      .C(s_cd_15_0[1]),
      .D(s_cdsel),
      .Z(s_ica1b_n)
  );

// ICA - 2
  A02 ICA2A (
      .A(s_lca_15_0_out[2]),
      .B(s_hold),
      .C(s_pr_15_0[2]),
      .D(s_psel),
      .Z(s_ica2a_n)
  );

  A02 ICA2B (
      .A(s_addsel),
      .B(s_add_15_0[2]),
      .C(s_cd_15_0[2]),
      .D(s_cdsel),
      .Z(s_ica2b_n)
  );

// ICA - 3
  A02 ICA3A (
      .A(s_lca_15_0_out[3]),
      .B(s_hold),
      .C(s_pr_15_0[3]),
      .D(s_psel),
      .Z(s_ica3a_n)
  );

  A02 ICA3B (
      .A(s_addsel),
      .B(s_add_15_0[3]),
      .C(s_cd_15_0[3]),
      .D(s_cdsel),
      .Z(s_ica3b_n)
  );

// ICA - 4
  A02 ICA4A (
      .A(s_lca_15_0_out[4]),
      .B(s_hold),
      .C(s_pr_15_0[4]),
      .D(s_psel),
      .Z(s_ica4a_n)
  );

  A02 ICA4B (
      .A(s_addsel),
      .B(s_add_15_0[4]),
      .C(s_cd_15_0[4]),
      .D(s_cdsel),
      .Z(s_ica4b_n)
  );

// ICA - 5
  A02 ICA5A (
      .A(s_lca_15_0_out[5]),
      .B(s_hold),
      .C(s_pr_15_0[5]),
      .D(s_psel),
      .Z(s_ica5a_n)
  );

  A02 ICA5B (
      .A(s_addsel),
      .B(s_add_15_0[5]),
      .C(s_cd_15_0[5]),
      .D(s_cdsel),
      .Z(s_ica5b_n)
  );

// ICA - 6
  A02 ICA6A (
      .A(s_lca_15_0_out[6]),
      .B(s_hold),
      .C(s_pr_15_0[6]),
      .D(s_psel),
      .Z(s_ica6a_n)
  );

  A02 ICA6B (
      .A(s_addsel),
      .B(s_add_15_0[6]),
      .C(s_cd_15_0[6]),
      .D(s_cdsel),
      .Z(s_ica6b_n)
  );

  // ICA - 7
  A02 ICA7A (
      .A(s_lca_15_0_out[7]),
      .B(s_hold),
      .C(s_pr_15_0[7]),
      .D(s_psel),
      .Z(s_ica7a_n)
  );

  A02 ICA7B (
      .A(s_addsel),
      .B(s_add_15_0[7]),
      .C(s_cd_15_0[7]),
      .D(s_cdsel),
      .Z(s_ica7b_n)
  );

// ICA - 8
  A02 ICA8A (
      .A(s_lca_15_0_out[8]),
      .B(s_hold),
      .C(s_pr_15_0[8]),
      .D(s_psel),
      .Z(s_ica8a_n)
  );

  A02 ICA8B (
      .A(s_addsel),
      .B(s_add_15_0[8]),
      .C(s_cd_15_0[8]),
      .D(s_cdsel),
      .Z(s_ica8b_n)
  );

// ICA - 9
  A02 ICA9A (
      .A(s_lca_15_0_out[9]),
      .B(s_hold),
      .C(s_pr_15_0[9]),
      .D(s_psel),
      .Z(s_ica9a_n)
  );

  A02 ICA9B (
      .A(s_addsel),
      .B(s_add_15_0[9]),
      .C(s_cd_15_0[9]),
      .D(s_cdsel),
      .Z(s_ica9b_n)
  );

// ICA - 10
  A02 ICA10A (
      .A(s_lca_15_0_out[10]),
      .B(s_hold),
      .C(s_pr_15_0[10]),
      .D(s_psel),
      .Z(s_ica10a_n)
  );

  A02 ICA10B (
      .A(s_addsel),
      .B(s_add_15_0[10]),
      .C(s_cd_15_0[10]),
      .D(s_cdsel),
      .Z(s_ica10b_n)
  );

// ICA - 11
  A02 ICA11A (
      .A(s_lca_15_0_out[11]),
      .B(s_hold),
      .C(s_pr_15_0[11]),
      .D(s_psel),
      .Z(s_ica11a_n)
  );

  A02 ICA11B (
      .A(s_addsel),
      .B(s_add_15_0[11]),
      .C(s_cd_15_0[11]),
      .D(s_cdsel),
      .Z(s_ica11b_n)
  );

// ICA - 12
  A02 ICA12A (
      .A(s_lca_15_0_out[12]),
      .B(s_hold),
      .C(s_pr_15_0[12]),
      .D(s_psel),
      .Z(s_ica12a_n)
  );

  A02 ICA12B (
      .A(s_addsel),
      .B(s_add_15_0[12]),
      .C(s_cd_15_0[12]),
      .D(s_cdsel),
      .Z(s_ica12b_n)
  );

// ICA - 13
  A02 ICA13A (
      .A(s_lca_15_0_out[13]),
      .B(s_hold),
      .C(s_pr_15_0[13]),
      .D(s_psel),
      .Z(s_ica13a_n)
  );

  A02 ICA13B (
      .A(s_addsel),
      .B(s_add_15_0[13]),
      .C(s_cd_15_0[13]),
      .D(s_cdsel),
      .Z(s_ica13b_n)
  );

// ICA - 14
  A02 ICA14A (
      .A(s_lca_15_0_out[14]),
      .B(s_hold),
      .C(s_pr_15_0[14]),
      .D(s_psel),
      .Z(s_ica14a_n)
  );

  A02 ICA14B (
      .A(s_addsel),
      .B(s_add_15_0[14]),
      .C(s_cd_15_0[14]),
      .D(s_cdsel),
      .Z(s_ica14b_n)
  );

// ICA - 15
  A02 ICA15A (
      .A(s_lca_15_0_out[15]),
      .B(s_hold),
      .C(s_pr_15_0[15]),
      .D(s_psel),
      .Z(s_ica15a_n)
  );

  A02 ICA15B (
      .A(s_addsel),
      .B(s_add_15_0[15]),
      .C(s_cd_15_0[15]),
      .D(s_cdsel),
      .Z(s_ica15b_n)
  );

 // CALC A
  CGA_MAC_APOS_CALCA CALCA
  (
    // System Input signals
    .sysclk(sysclk),                          // System clock in FPGA
    .sys_rst_n(sys_rst_n),                    // System reset in FPGA

    .MCLK(s_mclk),
    .MCLK_EN(MCLK_EN),

    .ECCR(s_eccr_out),
    .ECCRHIN(s_eccrhi_n),
    .ICA_15_0(s_ica_15_0_out[15:0]),
    .LCA_15_0(s_lca_15_0_out[15:0]),
    .MCA_9_0(s_mca_9_0_out[9:0])
  );

  // A INC
  CGA_MAC_APOS_INC AINC (
      .LCA_15_0 (s_lca_15_0_out[15:0]),
      .NLCA_15_0(s_nlca_15_0_out[15:0])
  );

endmodule
