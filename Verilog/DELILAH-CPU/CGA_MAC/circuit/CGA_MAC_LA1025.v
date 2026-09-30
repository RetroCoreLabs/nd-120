/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/MAC/LA1025                                                       **
** ADD                                                                   **
**                                                                       **
** Page 40                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 02-FEB-2025                                            **
** Ronny Hansen                                                          **
**                                                                       **
** 02-FEB-2025 - Refactored and removed input bus PCR_15_0_N.            **
**               (Use bus PCR_15_0 only)                                 **
***************************************************************************/


module CGA_MAC_LA1025 (
    input        sysclk,   //! FPGA system clock (P2: MCLK_EN capture)
    input        MCLK_EN,  //! MCLK clock-enable pulse (FPGA_FF_MODE, else 0)

    input        A10,
    input        A1617,
    input        A1619,
    input        A1819,
    input        B1819,
    input        B1821,
    input        BB10,        //! no PONI + DOUBLE + SHADOW + MREQ
    input        C10,         //! no PONI + DOUBLE + SHADOW + not MREQ
    input        D1617,
    input        E1617,
    input        F1617,
    input [15:0] ICA_15_0,
    input        MCLK,     //! Master CLock (from CGA_MAC.MCLK)
    input [15:0] PCR_15_0,  //! Program Counter Register bits 15 to 0 (same net as CGA_MAC.PCR_15_0)
    input [ 7:0] SEG_7_0,
    input [ 1:0] XPT_1_0,


    output        ECCRHIN,
    output [13:0] LA_23_10  //! Latch Address bits 23 to 10 (to CGA_MAC.LA_23_10)
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [15:0] s_ica_15_0;
  wire [15:0] s_ica_input;
  wire [13:0] s_la_23_10_out;
  wire [15:0] s_pcr_15_0;
  wire [ 1:0] s_xpt_1_0;
  wire [ 7:0] s_seg_7_0;
  wire        s_a10;
  wire        s_a1617;
  wire        s_a1619;
  wire        s_a1819;
  wire        s_b1819;
  wire        s_b1821;
  wire        s_bb10;
  wire        s_ila10_b;
  wire        s_ila11_b;
  wire        s_ila12_b;
  wire        s_ila13_b;
  wire        s_ila14_b;
  wire        s_ila15_b;
  wire        s_c10;
  wire        s_d1617;
  wire        s_e1617;
  wire        s_eccrhi_n_out;
  wire        s_ila16_d_z;
  wire        s_ila17_d_z;
  wire        s_f1617;
  wire        s_ica_10_n;
  wire        s_ica_9_n;
  wire        s_ila10_a;
  wire        s_ila11_a;
  wire        s_ila12_a;
  wire        s_ila13_a;
  wire        s_ila14_a;
  wire        s_ila15_a;
  wire        s_ica6_7_z;
  wire        s_ila17_a_z;
  wire        s_ila10;
  wire        s_ila11;
  wire        s_ila12;
  wire        s_ila13;
  wire        s_ila14;
  wire        s_ila15;
  wire        s_ila16_b_z;
  wire        s_ila16_c_z;
  wire        s_ila16;
  wire        s_ila17_b_z;
  wire        s_ila17_c_z;
  wire        s_ila17;
  wire        s_ila18_a_z;
  wire        s_ila18_b_z;
  wire        s_ila18;
  wire        s_ila19_a_z;
  wire        s_ila19_b_z;
  wire        s_ila19;
  wire        s_ila20_n;
  wire        s_ila21_n;
  wire        s_ila22_n;
  wire        s_ila23_n;
  wire        s_la10_n;
  wire        s_la11_n;
  wire        s_la12_n;
  wire        s_la13_n;
  wire        s_la14_n;
  wire        s_mclk;

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/


  //assign s_ica_15_0[15:0]   = ICA_15_0;
  assign s_ica_input[15:0]   = ICA_15_0;
  assign s_pcr_15_0[15:0]   = PCR_15_0;
  assign s_xpt_1_0[1:0]     = XPT_1_0;
  assign s_seg_7_0[7:0]     = SEG_7_0;
  assign s_a10              = A10;
  assign s_a1617            = A1617;
  assign s_a1619            = A1619;
  assign s_a1819            = A1819;
  assign s_b1819            = B1819;
  assign s_b1821            = B1821;
  assign s_bb10             = BB10;
  assign s_c10              = C10;
  assign s_d1617            = D1617;
  assign s_e1617            = E1617;
  assign s_f1617            = F1617;
  assign s_mclk             = MCLK;

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
  assign ECCRHIN            = s_eccrhi_n_out;
  assign LA_23_10           = s_la_23_10_out[13:0];

  /*******************************************************************************
   ** Here all in-lined components are defined                                   **
   *******************************************************************************/

  // NOT Gate
  assign s_ica_9_n          = ~s_ica_15_0[9];
  assign s_ica_10_n         = ~s_ica_15_0[10];


  // Code to make LINTER _not_ complain about bits not read in PCR bits 15 and 6:0
  (* keep = "true", DONT_TOUCH = "true" *) wire [7:0] unused_PCR_bits;
  assign unused_PCR_bits[7:0] = { s_pcr_15_0[15], s_pcr_15_0[6:0]};


  /*******************************************************************************
   ** Implementation                                                            **
   *******************************************************************************/

   // Need to delay the ICA signal change
   // TODO: Review to see if the delay can be latched on posedge sysclk
   reg [15:0] regICA;

   always@(s_ica_input)
   begin
     regICA <= s_ica_input;
   end
   assign s_ica_15_0 = regICA;
   
  // *** ILA 23 ***

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) ILA23_NAND (
      .input1(s_seg_7_0[7]),
      .input2(s_a1617),
      .result(s_ila23_n)
  );

  // *** ILA 22 ***

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) ILA22_NAND (
      .input1(s_seg_7_0[6]),
      .input2(s_a1617),
      .result(s_ila22_n)
  );

  // *** ILA 21 ***

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) ILA21_NAND (
      .input1(s_seg_7_0[5]),
      .input2(s_b1821),
      .result(s_ila21_n)
  );

  // *** ILA 20 ***

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) ILA20_NAND (
      .input1(s_seg_7_0[4]),
      .input2(s_b1821),
      .result(s_ila20_n)
  );

  // *** ILA 19 ***

  A02 ILA19A (
      .A(s_a1619),
      .B(~s_pcr_15_0[14]),  // PCR 14n
      .C(s_seg_7_0[3]),      // SEG 3
      .D(s_b1821),
      .Z(s_ila19_a_z)
  );

  A02 ILA19B (
      .A(s_ica_10_n),        // ICA 10n
      .B(s_a1819),
      .C(~s_pcr_15_0[10]),   // PCR 10n
      .D(s_b1819),
      .Z(s_ila19_b_z)
  );

  OR_GATE #(
      .BubblesMask(2'b11)
  ) ILA19_OR (
      .input1(s_ila19_a_z),
      .input2(s_ila19_b_z),
      .result(s_ila19)
  );

  // *** ILA 18 ***

  A02 ILA18A (
      .A(s_a1619),
      .B(~s_pcr_15_0[13]),  // PCR 13n
      .C(~s_pcr_15_0[9]),   // PCR 9n
      .D(s_b1819),
      .Z(s_ila18_a_z)
  );

  A02 ILA18B (
      .A(s_seg_7_0[2]),  // SEG 2
      .B(s_b1821),
      .C(s_ica_9_n),  // ICA 9n
      .D(s_a1819),
      .Z(s_ila18_b_z)
  );

  OR_GATE #(
      .BubblesMask(2'b11)
  ) ILA18_OR (
      .input1(s_ila18_a_z),
      .input2(s_ila18_b_z),
      .result(s_ila18)
  );

  // *** ILA 17 ***


  A02 ILA17A (
      .A(s_ica_15_0[7]),
      .B(s_a10),
      .C(s_ica_15_0[8]),
      .D(s_bb10),
      .Z(s_ila17_a_z)
  );

  A02 ILA17B (
      .A(s_pcr_15_0[12]),  // PCR 12
      .B(s_a1619),
      .C(s_seg_7_0[1]),    // SEG 1
      .D(s_a1617),
      .Z(s_ila17_b_z)
  );

  A02 ILA17C (
      .A(s_pcr_15_0[10]),  // PCR 10
      .B(s_d1617),
      .C(s_pcr_15_0[8]),   // PCR 8
      .D(s_e1617),
      .Z(s_ila17_c_z)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) ILA17D (
      .input1(s_xpt_1_0[1]),  // XPT 1
      .input2(s_f1617),
      .result(s_ila17_d_z)
  );


  OR_GATE_4_INPUTS #(
      .BubblesMask(4'hF)
  ) ILA17_OR (
      .input1(s_ila17_a_z),
      .input2(s_ila17_b_z),
      .input3(s_ila17_c_z),
      .input4(s_ila17_d_z),
      .result(s_ila17)
  );

  // *** ILA 16 ***

  A02 ILA16A (
      .A(s_ica_15_0[6]),  // ICA 6
      .B(s_a10),
      .C(s_ica_15_0[7]),  // ICA 7
      .D(s_bb10),
      .Z(s_ica6_7_z)
  );

  A02 ILA16B (
      .A(s_pcr_15_0[11]),  // PCR 11
      .B(s_a1619),
      .C(s_seg_7_0[0]),    // SEG 0
      .D(s_a1617),
      .Z(s_ila16_b_z)
  );


  A02 ILA16C (
      .A(s_pcr_15_0[9]),  //PCR 9
      .B(s_d1617),
      .C(s_pcr_15_0[7]),  // PCR 7
      .D(s_e1617),
      .Z(s_ila16_c_z)
  );


  NAND_GATE #(
      .BubblesMask(2'b00)
  ) ILA16D (
      .input1(s_xpt_1_0[0]),  // XPT 0
      .input2(s_f1617),
      .result(s_ila16_d_z)
  );

  OR_GATE_4_INPUTS #(
      .BubblesMask(4'hF)
  ) GATES_21 (
      .input1(s_ica6_7_z),
      .input2(s_ila16_b_z),
      .input3(s_ila16_c_z),
      .input4(s_ila16_d_z),
      .result(s_ila16)
  );


  // *** ILA 15 ***

  A02 ILA15A (
      .A(s_ica_15_0[5]),
      .B(s_a10),
      .C(s_ica_15_0[6]),
      .D(s_bb10),
      .Z(s_ila15_a)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) ILA15B (
      .input1(s_ica_15_0[15]),
      .input2(s_c10),
      .result(s_ila15_b)
  );


  OR_GATE #(
      .BubblesMask(2'b11)
  ) ILA15_OR (
      .input1(s_ila15_a),
      .input2(s_ila15_b),
      .result(s_ila15)
  );


  // *** ILA 14 ***
  A02 ILA14A (
      .A(s_ica_15_0[4]),
      .B(s_a10),
      .C(s_ica_15_0[5]),
      .D(s_bb10),
      .Z(s_ila14_a)
  );
  NAND_GATE #(
      .BubblesMask(2'b00)
  ) ILA14B (
      .input1(s_ica_15_0[14]),
      .input2(s_c10),
      .result(s_ila14_b)
  );

  OR_GATE #(
      .BubblesMask(2'b11)
  ) ILA14_OR (
      .input1(s_ila14_a),
      .input2(s_ila14_b),
      .result(s_ila14)
  );

  // *** ILA 13 ***

  A02 ILA13A (
      .A(s_ica_15_0[3]),
      .B(s_a10),
      .C(s_ica_15_0[4]),
      .D(s_bb10),
      .Z(s_ila13_a)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) ILA13B (
      .input1(s_ica_15_0[13]),
      .input2(s_c10),
      .result(s_ila13_b)
  );

  OR_GATE #(
      .BubblesMask(2'b11)
  ) ILA13_OR (
      .input1(s_ila13_a),
      .input2(s_ila13_b),
      .result(s_ila13)
  );

  // *** ILA 12 ***

  A02 ILA12A (
      .A(s_ica_15_0[2]),
      .B(s_a10),
      .C(s_ica_15_0[3]),
      .D(s_bb10),
      .Z(s_ila12_a)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) ILA12B (
      .input1(s_ica_15_0[12]),
      .input2(s_c10),
      .result(s_ila12_b)
  );

  OR_GATE #(
      .BubblesMask(2'b11)
  ) ILA12_OR (
      .input1(s_ila12_a),
      .input2(s_ila12_b),
      .result(s_ila12)
  );


  // *** ILA 11 ***

  A02 ILA11A (
      .A(s_ica_15_0[1]),
      .B(s_a10),
      .C(s_ica_15_0[2]),
      .D(s_bb10),
      .Z(s_ila11_a)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_3 (
      .input1(s_ica_15_0[11]),
      .input2(s_c10),
      .result(s_ila11_b)
  );

  OR_GATE #(
      .BubblesMask(2'b11)
  ) ILA11_OR (
      .input1(s_ila11_a),
      .input2(s_ila11_b),
      .result(s_ila11)
  );


  // *** ILA 10 ***

  A02 ILA10A (
      .A(s_ica_15_0[0]),
      .B(s_a10),
      .C(s_ica_15_0[1]),
      .D(s_bb10),
      .Z(s_ila10_a)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) ILA10B (
      .input1(s_ica_15_0[10]),
      .input2(s_c10),
      .result(s_ila10_b)
  );

  OR_GATE #(
      .BubblesMask(2'b11)
  ) ILA10_OR (
      .input1(s_ila10_a),
      .input2(s_ila10_b),
      .result(s_ila10)
  );

  // *******************













  NAND_GATE_6_INPUTS #(
      .BubblesMask({2'b00, 4'h0})
  ) GATES_23 (
      .input1(s_la_23_10_out[5]),
      .input2(s_la10_n),
      .input3(s_la11_n),
      .input4(s_la12_n),
      .input5(s_la13_n),
      .input6(s_la14_n),
      .result(s_eccrhi_n_out)
  );




  // *** LATCHES ***


  // ** HIGH-LATCH (LA_23-18)**
  R81_EN #(.USE_ENABLE(MCLK_CE)) R_LA_H (
      .sysclk(sysclk),
      .EN(MCLK_EN),
      .CP(s_mclk),

      .A  (1'b0),
      .B  (1'b0),
      .C  (s_ila23_n),
      .D  (s_ila22_n),
      .E  (s_ila21_n),
      .F  (s_ila20_n),
      .G  (s_ila19),
      .H  (s_ila18),
      .QA (),
      .QAN(),
      .QB (),
      .QBN(),
      .QC (),
      .QCN(s_la_23_10_out[13]),
      .QD (),
      .QDN(s_la_23_10_out[12]),
      .QE (),
      .QEN(s_la_23_10_out[11]),
      .QF (),
      .QFN(s_la_23_10_out[10]),
      .QG (s_la_23_10_out[9]),
      .QGN(),
      .QH (s_la_23_10_out[8]),
      .QHN()
  );

  // ** LOW-LATCH (LA_17-10)**
  R81_EN #(.USE_ENABLE(MCLK_CE)) R_LA_L (
      .sysclk(sysclk),
      .EN(MCLK_EN),
      .CP(s_mclk),

      .A  (s_ila17),
      .B  (s_ila16),
      .C  (s_ila15),
      .D  (s_ila14),
      .E  (s_ila13),
      .F  (s_ila12),
      .G  (s_ila11),
      .H  (s_ila10),
      .QA (s_la_23_10_out[7]),
      .QAN(),
      .QB (s_la_23_10_out[6]),
      .QBN(),
      .QC (s_la_23_10_out[5]),
      .QCN(),
      .QD (s_la_23_10_out[4]),
      .QDN(s_la14_n),
      .QE (s_la_23_10_out[3]),
      .QEN(s_la13_n),
      .QF (s_la_23_10_out[2]),
      .QFN(s_la12_n),
      .QG (s_la_23_10_out[1]),
      .QGN(s_la11_n),
      .QH (s_la_23_10_out[0]),
      .QHN(s_la10_n)
  );

endmodule
