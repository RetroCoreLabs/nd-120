/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/MAC/DECODE                                                       **
** INCREMENT                                                             **
**                                                                       **
** Page 25-28                                                            **
** SHEET 1-4                                                             **
**                                                                       **
** Last reviewed: 10-NOV-2024                                            **
** Ronny Hansen                                                          **
***************************************************************************/

module CGA_MAC_DECODE (
    input       sysclk,   //! FPGA system clock (P2: MCLK_EN capture)
    input       MCLK_EN,  //! MCLK clock-enable pulse (FPGA_FF_MODE, else 0)

    input [4:0] CSCOMM_4_0,  //! Microcode: Commands (5 bits) (from CGA_MAC.CSCOMM_4_0)
    input [1:0] CSMIS_1_0,  //! Microcode: Misc  (2 bits) (from CGA_MAC.CMIS_1_0)
    input       LCSN,     //! Instruction Load Control Signal (from CGA_MAC.ILCSN)
    input       MCLK,     //! Master CLock (from CGA_MAC.MCLK)
    input       WR3,      //! Enable write to WR3 (B register) (from WR_15_0) (from CGA_WRF.WR3)
    input       WR7,      //! Enable write to WR7 (X register) (from WR_15_0) (from CGA_WRF.WR7)

    output ADDSEL,
    output CDS,           //! If false all 16 bits of CD is added. If true, only the low 8 bits are added. (to CGA_MAC_ADD.CDS)
    output CDSEL,
    output EXMN,
    output HOLD,
    output LLDEXM,
    output LLDPCR,
    output LLDSEG,
    output NLCASEL,
    output PB,            //! Select ALU register B (to CGA_MAC_ADD.PB)
    output PLCA,          //! Select ALU Load Control Address (to CGA_MAC_ADD.PLCA)
    output PRB,           //! Select Microcode register B (to CGA_MAC_ADD.PRB)
    output PSEL,
    output PX,            //! Select ALU register X (to CGA_MAC_ADD.PX)
    output SAPT,
    output SPTN
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [1:0] s_csmis_1_0;
  wire [4:0] s_cscomm_4_0;
  wire       s_addsel_n_out;
  wire       s_addsel_out;
  wire       s_cds_out;
  wire       s_cdsel_n_out;
  wire       s_cdsel_out;
  wire       s_cscomm_0_n;
  wire       s_cscomm_0;
  wire       s_cscomm_1_n;
  wire       s_cscomm_1;
  wire       s_cscomm_2_n;
  wire       s_cscomm_2;
  wire       s_cscomm_3_n;
  wire       s_cscomm_3;
  wire       s_cscomm_4_n;
  wire       s_cscomm_4;
  wire       s_csmis_0_n;
  wire       s_csmis_0;
  wire       s_csmis_1_n;
  wire       s_csmis_1;
  wire       s_exm_n_out;
  wire       s_gates1_out;
  wire       s_gates10_out;
  wire       s_gates11_out;
  wire       s_gates13_out;
  wire       s_gates15_out;
  wire       s_gates16_out;
  wire       s_gates17_out;
  wire       s_gates18_out;
  wire       s_gates19_out;
  wire       s_gates20_out;
  wire       s_gates21_out;
  wire       s_gates22_out;
  wire       s_gates23_out;
  wire       s_gates24_out;
  wire       s_gates26_out;
  wire       s_gates28_out;
  wire       s_gates29_out;
  wire       s_gates3_out;
  wire       s_gates30_out;
  wire       s_gates31_out;
  wire       s_gates32_out;
  wire       s_gates34_out;
  wire       s_gates36_out;
  wire       s_gates37_out;
  wire       s_gates38_out;
  wire       s_gates39_out;
  wire       s_gates4_out;
  wire       s_gates40_out;
  wire       s_gates42_out;
  wire       s_gates44_out;
  wire       s_gates45_out;
  wire       s_gates46_out;
  wire       s_gates48_out;
  wire       s_gates49_out;
  wire       s_gates5_out;
  wire       s_gates50_out;
  wire       s_gates51_out;
  wire       s_gates52_out;
  wire       s_gates53_out;
  wire       s_gates54_out;
  wire       s_gates55_out;
  wire       s_gates56_out;
  wire       s_gates57_out;
  wire       s_gates58_out;
  wire       s_gates59_out;
  wire       s_gates6_out;
  wire       s_gates8_out;
  wire       s_gates9_out;
  wire       s_hold_n_out;
  wire       s_hold_out;
  wire       s_lcs_n;
  wire       s_lldexm_out;
  wire       s_lldpcr_out;
  wire       s_lldseg_out;
  wire       s_mclk;
  wire       s_nlcasel_n_out;
  wire       s_nlcasel_out;
  wire       s_pb_out;
  wire       s_plca_n_out;
  wire       s_plca_out;
  wire       s_pn_n_out;
  wire       s_prb_n_out;
  wire       s_prb_out;
  wire       s_psel_out;
  wire       s_px_n_out;
  wire       s_px_out;
  wire       s_sapt_out;
  wire       s_spt_n_out;
  wire       s_wr3_n;
  wire       s_wr3;
  wire       s_wr7_n;
  wire       s_wr7;

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_csmis_1_0[1:0]  = CSMIS_1_0;
  assign s_cscomm_4_0[4:0] = CSCOMM_4_0;
  assign s_wr3             = WR3;
  assign s_mclk            = MCLK;
  assign s_lcs_n           = LCSN;
  assign s_wr7             = WR7;

  // P2 (docs/plan-fix-unconstrained-clocks.md): in FF mode the MCLK-
  // clocked register captures on posedge sysclk gated by MCLK_EN
  // (aligned to the MCLK rise) instead of clocking on the routed net.
`ifdef FPGA_FF_MODE
  localparam MCLK_CE = 1;
`else
  localparam MCLK_CE = 0;
`endif

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign ADDSEL            = s_addsel_out;
  assign CDS               = s_cds_out;
  assign CDSEL             = s_cdsel_out;
  assign EXMN              = s_exm_n_out;
  assign HOLD              = s_hold_out;
  assign LLDEXM            = s_lldexm_out;
  assign LLDPCR            = s_lldpcr_out;
  assign LLDSEG            = s_lldseg_out;
  assign NLCASEL           = s_nlcasel_out;
  assign PB                = s_pb_out;
  assign PLCA              = s_plca_out;
  assign PRB               = s_prb_out;
  assign PSEL              = s_psel_out;
  assign PX                = s_px_out;
  assign SAPT              = s_sapt_out;
  assign SPTN              = s_spt_n_out;

  /*******************************************************************************
   ** Here all in-lined components are defined                                   **
   *******************************************************************************/

  // NOT Gate
  assign s_pb_out          = ~s_pn_n_out;
  assign s_px_out          = ~s_px_n_out;
  assign s_prb_out         = ~s_prb_n_out;
  assign s_cdsel_out       = ~s_cdsel_n_out;
  assign s_addsel_out      = ~s_addsel_n_out;
  assign s_nlcasel_out     = ~s_nlcasel_n_out;
  assign s_hold_out        = ~s_hold_n_out;
  assign s_plca_out        = ~s_plca_n_out;
  assign s_wr7_n           = ~s_wr7;
  assign s_wr3_n           = ~s_wr3;
  assign s_psel_out        = ~s_gates51_out;
  assign s_cscomm_0        = ~s_cscomm_4_0[0];
  assign s_cscomm_1        = ~s_cscomm_4_0[1];
  assign s_cscomm_2        = ~s_cscomm_4_0[2];
  assign s_cscomm_3        = ~s_cscomm_4_0[3];
  assign s_cscomm_4        = ~s_cscomm_4_0[4];
  assign s_csmis_0         = ~s_csmis_1_0[0];
  assign s_csmis_1         = ~s_csmis_1_0[1];
  assign s_cscomm_0_n      = ~s_cscomm_0;
  assign s_cscomm_1_n      = ~s_cscomm_1;
  assign s_cscomm_2_n      = ~s_cscomm_2;
  assign s_cscomm_3_n      = ~s_cscomm_3;
  assign s_cscomm_4_n      = ~s_cscomm_4;
  assign s_csmis_0_n       = ~s_csmis_0;
  assign s_csmis_1_n       = ~s_csmis_1;

  /*******************************************************************************
   ** Here all normal components are defined                                     **
   *******************************************************************************/
  NAND_GATE_4_INPUTS #(
      .BubblesMask(4'h0)
  ) GATES_1 (
      .input1(s_cscomm_2),
      .input2(s_cscomm_0_n),
      .input3(s_csmis_1_n),
      .input4(s_csmis_0),
      .result(s_gates1_out)
  );

  NAND_GATE_4_INPUTS #(
      .BubblesMask(4'h0)
  ) GATES_2 (
      .input1(s_wr3_n),
      .input2(s_csmis_0_n),
      .input3(s_csmis_1),
      .input4(s_cscomm_0),
      .result(s_pn_n_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_3 (
      .input1(s_cscomm_3_n),
      .input2(s_csmis_1_n),
      .result(s_gates3_out)
  );

  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_4 (
      .input1(s_cscomm_3_n),
      .input2(s_cscomm_2),
      .input3(s_cscomm_0_n),
      .result(s_gates4_out)
  );

  // 31-JUL-2026: input3 was s_cscomm_4 - a transcription error vs the DELILAH
  // schematic (CGA/MAC/DECODE sheet 1 of 4, page 25: the third input of this
  // ND3 taps the ICSMIS0 row). The term is the SPT mask for APT requests
  // (CSCOMM 0o34/0o35 with CSMIS=1); without it SPT and SAPT assert together
  // on RDRQ,APT / WRRQ,APT and the PTSEL JK (J=SPT, K=SAPT) TOGGLES instead
  // of selecting APT - from an APT state it flips to PT, the dest first-touch
  // protection check reads the wrong page table and raises a spurious level-14
  // page fault that kills the in-flight write (INSTRUCTION-C03 Cx:
  // "MOVEW APT ==> APT" drops the destination page-boundary word).
  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_5 (
      .input1(s_cscomm_3_n),
      .input2(s_csmis_1),
      .input3(s_csmis_0_n),
      .result(s_gates5_out)
  );

  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_6 (
      .input1(s_cscomm_3),
      .input2(s_cscomm_2),
      .input3(s_cscomm_0_n),
      .result(s_gates6_out)
  );

  NAND_GATE_4_INPUTS #(
      .BubblesMask(4'h0)
  ) GATES_7 (
      .input1(s_wr7_n),
      .input2(s_csmis_0_n),
      .input3(s_gates6_out),
      .input4(s_gates9_out),
      .result(s_px_n_out)
  );

  NAND_GATE_6_INPUTS #(
      .BubblesMask({2'b00, 4'h0})
  ) GATES_8 (
      .input1(s_csmis_0_n),
      .input2(s_cscomm_4_n),
      .input3(s_csmis_1),
      .input4(s_cscomm_0),
      .input5(s_cscomm_1_n),
      .input6(s_cscomm_2),
      .result(s_gates8_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_9 (
      .input1(s_cscomm_0),
      .input2(s_csmis_1),
      .result(s_gates9_out)
  );

  NAND_GATE_6_INPUTS #(
      .BubblesMask({2'b00, 4'h0})
  ) GATES_10 (
      .input1(s_csmis_0_n),
      .input2(s_cscomm_4_n),
      .input3(s_csmis_1),
      .input4(s_cscomm_1),
      .input5(s_cscomm_2_n),
      .input6(s_cscomm_3_n),
      .result(s_gates10_out)
  );

  NAND_GATE_5_INPUTS #(
      .BubblesMask({1'b0, 4'h0})
  ) GATES_11 (
      .input1(s_csmis_1),
      .input2(s_cscomm_0_n),
      .input3(s_cscomm_2),
      .input4(s_cscomm_3_n),
      .input5(s_cscomm_4_n),
      .result(s_gates11_out)
  );

  NAND_GATE_5_INPUTS #(
      .BubblesMask({1'b0, 4'h0})
  ) GATES_12 (
      .input1(s_gates8_out),
      .input2(s_gates10_out),
      .input3(s_gates11_out),
      .input4(s_gates15_out),
      .input5(s_gates17_out),
      .result(s_sapt_out)
  );

  NAND_GATE_4_INPUTS #(
      .BubblesMask(4'h0)
  ) GATES_13 (
      .input1(s_gates6_out),
      .input2(s_gates9_out),
      .input3(s_wr7),
      .input4(s_csmis_0_n),
      .result(s_gates13_out)
  );

  NOR_GATE_4_INPUTS #(
      .BubblesMask(4'hF)
  ) GATES_14 (
      .input1(s_gates13_out),
      .input2(s_gates16_out),
      .input3(s_gates18_out),
      .input4(s_gates19_out),
      .result(s_prb_n_out)
  );

  NAND_GATE_5_INPUTS #(
      .BubblesMask({1'b0, 4'h0})
  ) GATES_15 (
      .input1(s_csmis_1_n),
      .input2(s_cscomm_0),
      .input3(s_cscomm_2),
      .input4(s_cscomm_3_n),
      .input5(s_cscomm_4_n),
      .result(s_gates15_out)
  );

  NAND_GATE_4_INPUTS #(
      .BubblesMask(4'h0)
  ) GATES_16 (
      .input1(s_wr3),
      .input2(s_csmis_0_n),
      .input3(s_csmis_1),
      .input4(s_cscomm_0),
      .result(s_gates16_out)
  );

  NAND_GATE_5_INPUTS #(
      .BubblesMask({1'b0, 4'h0})
  ) GATES_17 (
      .input1(s_csmis_0_n),
      .input2(s_cscomm_0),
      .input3(s_cscomm_2),
      .input4(s_cscomm_3_n),
      .input5(s_cscomm_4_n),
      .result(s_gates17_out)
  );

  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_18 (
      .input1(s_cscomm_0_n),
      .input2(s_cscomm_2_n),
      .input3(s_csmis_0),
      .result(s_gates18_out)
  );

  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_19 (
      .input1(s_cscomm_0_n),
      .input2(s_cscomm_3_n),
      .input3(s_csmis_0),
      .result(s_gates19_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_20 (
      .input1(s_cscomm_3),
      .input2(s_cscomm_1),
      .result(s_gates20_out)
  );

  NAND_GATE_6_INPUTS #(
      .BubblesMask({2'b00, 4'h0})
  ) GATES_21 (
      .input1(s_csmis_0),
      .input2(s_csmis_1_n),
      .input3(s_cscomm_0),
      .input4(s_cscomm_1_n),
      .input5(s_cscomm_2_n),
      .input6(s_cscomm_4_n),
      .result(s_gates21_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_22 (
      .input1(s_cscomm_3_n),
      .input2(s_cscomm_2_n),
      .result(s_gates22_out)
  );

  NAND_GATE_5_INPUTS #(
      .BubblesMask({1'b0, 4'h0})
  ) GATES_23 (
      .input1(s_csmis_0),
      .input2(s_csmis_1_n),
      .input3(s_cscomm_0),
      .input4(s_cscomm_3_n),
      .input5(s_cscomm_4_n),
      .result(s_gates23_out)
  );

  NAND_GATE_4_INPUTS #(
      .BubblesMask(4'h0)
  ) GATES_24 (
      .input1(s_cscomm_3),
      .input2(s_cscomm_2),
      .input3(s_csmis_1_n),
      .input4(s_cscomm_0),
      .result(s_gates24_out)
  );

  NOR_GATE_4_INPUTS #(
      .BubblesMask(4'hF)
  ) GATES_25 (
      .input1(s_gates21_out),
      .input2(s_gates23_out),
      .input3(s_gates26_out),
      .input4(s_gates30_out),
      .result(s_cdsel_n_out)
  );

  NAND_GATE_4_INPUTS #(
      .BubblesMask(4'h0)
  ) GATES_26 (
      .input1(s_cscomm_4_n),
      .input2(s_cscomm_1),
      .input3(s_cscomm_2),
      .input4(s_cscomm_3),
      .result(s_gates26_out)
  );

  NAND_GATE_8_INPUTS #(
      .BubblesMask(8'h00)
  ) GATES_27 (
      .input1(s_gates20_out),
      .input2(s_cscomm_4_n),
      .input3(s_gates22_out),
      .input4(s_gates24_out),
      .input5(s_gates28_out),
      .input6(s_gates29_out),
      .input7(s_gates31_out),
      .input8(s_gates32_out),
      .result(s_addsel_n_out)
  );

  NAND_GATE_4_INPUTS #(
      .BubblesMask(4'h0)
  ) GATES_28 (
      .input1(s_csmis_0),
      .input2(s_cscomm_2_n),
      .input3(s_cscomm_1_n),
      .input4(s_csmis_1_n),
      .result(s_gates28_out)
  );

  NAND_GATE_4_INPUTS #(
      .BubblesMask(4'h0)
  ) GATES_29 (
      .input1(s_cscomm_3_n),
      .input2(s_cscomm_0),
      .input3(s_csmis_1_n),
      .input4(s_csmis_0),
      .result(s_gates29_out)
  );

  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_30 (
      .input1(s_cscomm_4_n),
      .input2(s_cscomm_2_n),
      .input3(s_cscomm_3_n),
      .result(s_gates30_out)
  );

  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_31 (
      .input1(s_cscomm_3_n),
      .input2(s_cscomm_0_n),
      .input3(s_csmis_1_n),
      .result(s_gates31_out)
  );

  NAND_GATE_4_INPUTS #(
      .BubblesMask(4'h0)
  ) GATES_32 (
      .input1(s_cscomm_2_n),
      .input2(s_cscomm_1_n),
      .input3(s_cscomm_0_n),
      .input4(s_csmis_1_n),
      .result(s_gates32_out)
  );

  NAND_GATE_6_INPUTS #(
      .BubblesMask({2'b00, 4'h0})
  ) GATES_33 (
      .input1(s_cscomm_3_n),
      .input2(s_cscomm_0_n),
      .input3(s_cscomm_2),
      .input4(s_csmis_1_n),
      .input5(s_cscomm_4_n),
      .input6(s_gates34_out),
      .result(s_nlcasel_n_out)
  );

  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_34 (
      .input1(s_csmis_1_n),
      .input2(s_csmis_0),
      .input3(s_cscomm_1_n),
      .result(s_gates34_out)
  );

  NOR_GATE #(
      .BubblesMask(2'b11)
  ) GATES_35 (
      .input1(s_cscomm_4_n),
      .input2(s_gates36_out),
      .result(s_hold_n_out)
  );

  NAND_GATE_6_INPUTS #(
      .BubblesMask({2'b00, 4'h0})
  ) GATES_36 (
      .input1(s_cscomm_2),
      .input2(s_cscomm_1_n),
      .input3(s_csmis_1_n),
      .input4(s_gates37_out),
      .input5(s_gates38_out),
      .input6(s_gates39_out),
      .result(s_gates36_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_37 (
      .input1(s_csmis_1_n),
      .input2(s_csmis_0_n),
      .result(s_gates37_out)
  );

  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_38 (
      .input1(s_cscomm_3),
      .input2(s_cscomm_0_n),
      .input3(s_csmis_1_n),
      .result(s_gates38_out)
  );

  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_39 (
      .input1(s_cscomm_3_n),
      .input2(s_cscomm_0),
      .input3(s_csmis_1_n),
      .result(s_gates39_out)
  );

  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_40 (
      .input1(s_csmis_0_n),
      .input2(s_cscomm_0_n),
      .input3(s_cscomm_3_n),
      .result(s_gates40_out)
  );

  NOR_GATE #(
      .BubblesMask(2'b11)
  ) GATES_41 (
      .input1(s_gates40_out),
      .input2(s_gates42_out),
      .result(s_cds_out)
  );

  NAND_GATE_4_INPUTS #(
      .BubblesMask(4'h0)
  ) GATES_42 (
      .input1(s_csmis_0_n),
      .input2(s_cscomm_0_n),
      .input3(s_cscomm_2_n),
      .input4(s_cscomm_3),
      .result(s_gates42_out)
  );

  NAND_GATE_6_INPUTS #(
      .BubblesMask({2'b00, 4'h0})
  ) GATES_43 (
      .input1(s_csmis_0_n),
      .input2(s_csmis_1_n),
      .input3(s_cscomm_1),
      .input4(s_cscomm_2_n),
      .input5(s_cscomm_3_n),
      .input6(s_cscomm_4_n),
      .result(s_exm_n_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_44 (
      .input1(s_csmis_0_n),
      .input2(s_cscomm_0),
      .result(s_gates44_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_45 (
      .input1(s_cscomm_2),
      .input2(s_cscomm_1),
      .result(s_gates45_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_46 (
      .input1(s_cscomm_3_n),
      .input2(s_cscomm_0_n),
      .result(s_gates46_out)
  );

  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_47 (
      .input1(s_gates44_out),
      .input2(s_gates46_out),
      .input3(s_gates49_out),
      .result(s_plca_n_out)
  );

  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_48 (
      .input1(s_cscomm_2),
      .input2(s_cscomm_1_n),
      .input3(s_cscomm_0_n),
      .result(s_gates48_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_49 (
      .input1(s_cscomm_2_n),
      .input2(s_cscomm_0_n),
      .result(s_gates49_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_50 (
      .input1(s_csmis_1),
      .input2(s_cscomm_1_n),
      .result(s_gates50_out)
  );

  NAND_GATE_7_INPUTS #(
      .BubblesMask({3'b000, 4'h0})
  ) GATES_51 (
      .input1(s_gates45_out),
      .input2(s_gates48_out),
      .input3(s_gates50_out),
      .input4(s_cscomm_3),
      .input5(s_gates52_out),
      .input6(s_gates53_out),
      .input7(s_cscomm_4_n),
      .result(s_gates51_out)
  );

  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_52 (
      .input1(s_cscomm_2),
      .input2(s_csmis_1_n),
      .input3(s_csmis_0),
      .result(s_gates52_out)
  );

  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_53 (
      .input1(s_cscomm_2_n),
      .input2(s_cscomm_1_n),
      .input3(s_cscomm_0),
      .result(s_gates53_out)
  );

  NAND_GATE_8_INPUTS #(
      .BubblesMask(8'h00)
  ) GATES_54 (
      .input1(s_lcs_n),
      .input2(s_csmis_0_n),
      .input3(s_csmis_1_n),
      .input4(s_cscomm_0_n),
      .input5(s_cscomm_1),
      .input6(s_cscomm_2),
      .input7(s_cscomm_3),
      .input8(s_cscomm_4_n),
      .result(s_gates54_out)
  );

  NAND_GATE_8_INPUTS #(
      .BubblesMask(8'h00)
  ) GATES_55 (
      .input1(s_lcs_n),
      .input2(s_csmis_0),
      .input3(s_csmis_1),
      .input4(s_cscomm_0),
      .input5(s_cscomm_1),
      .input6(s_cscomm_2),
      .input7(s_cscomm_3),
      .input8(s_cscomm_4_n),
      .result(s_gates55_out)
  );

  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_56 (
      .input1(s_cscomm_3),
      .input2(s_cscomm_2),
      .input3(s_cscomm_1),
      .result(s_gates56_out)
  );

  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_57 (
      .input1(s_cscomm_3_n),
      .input2(s_cscomm_2_n),
      .input3(s_cscomm_1_n),
      .result(s_gates57_out)
  );

  NAND_GATE_8_INPUTS #(
      .BubblesMask(8'h00)
  ) GATES_58 (
      .input1(s_lcs_n),
      .input2(s_cscomm_4),
      .input3(s_cscomm_3),
      .input4(s_cscomm_2_n),
      .input5(s_cscomm_1_n),
      .input6(s_cscomm_0),
      .input7(s_csmis_1_n),
      .input8(s_csmis_0_n),
      .result(s_gates58_out)
  );

  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_59 (
      .input1(s_cscomm_2),
      .input2(s_csmis_1),
      .input3(s_csmis_0_n),
      .result(s_gates59_out)
  );

  NAND_GATE_8_INPUTS #(
      .BubblesMask(8'h00)
  ) GATES_60 (
      .input1(s_gates56_out),
      .input2(s_gates57_out),
      .input3(s_cscomm_4_n),
      .input4(s_gates59_out),
      .input5(s_gates1_out),
      .input6(s_gates3_out),
      .input7(s_gates4_out),
      .input8(s_gates5_out),
      .result(s_spt_n_out)
  );


  /*******************************************************************************
   ** Here all sub-circuits are defined                                          **
   *******************************************************************************/

  R41P_EN #(.USE_ENABLE(MCLK_CE)) DECODE_R41 (
      .sysclk(sysclk),
      .EN(MCLK_EN),
      .A  (s_gates54_out),
      .B  (s_gates55_out),
      .C  (s_gates58_out),
      .CP (s_mclk),
      .D  (1'b0),
      .QA (),
      .QAN(s_lldexm_out),
      .QB (),
      .QBN(s_lldseg_out),
      .QC (),
      .QCN(s_lldpcr_out),
      .QD (),
      .QDN()
  );

endmodule
