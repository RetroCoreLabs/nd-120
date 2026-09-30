/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/ALU/STS                                                          **
** STS REGISTER                                                          **
**                                                                       **
** Page 51                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 1-DEC-2024                                             **
** Ronny Hansen                                                          **
***************************************************************************/


module CGA_ALU_STS (
    input        sysclk,     //! FPGA system clock (P2: ALUCLK_EN capture)
    input        ALUCLK_EN,  //! ALUCLK clock-enable pulse (FPGA_FF_MODE, else 0)
    input        ALUCLK,     //! ALU clock signal (from CPU_PROC_CGA_33.ALUCLK)
    input        CRY,        //! Carry Out (from CGA_CPU_ALU_RALU.CRY)
    input [ 1:0] CSTS_1_0,   //! Control Store status outputs (2-bit) (from CGA_CPU_ALU_CONTR.CSTS_1_0)
    input [15:0] FIDBO_15_0,
    input        LDPILN,     //! Load PIL negated (from CGA_DCD.LDPILN)
    input        MI,         //! Microinstruction/Memory interface indicator (from CGA_CPU_ALU_CONTR.MI)
    input        OVF,        //! Overflow Flag (from CGA_CPU_ALU_RALU.OVF)

    output [15:0] STS_15_0
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [ 1:0] s_csts_1_0;
  wire [15:0] s_sts_15_0_out;
  wire [15:0] s_fidbo_15_0;
  wire        s_aluclk;
  wire        s_cry;
  wire        s_csts_0_n;
  wire        s_csts_1_n;
  wire        s_gates1_out;
  wire        s_gates2_out;
  wire        s_ists_4;
  wire        s_ists_5;
  wire        s_ists_6;
  wire        s_ists_7;
  wire        s_ldpil_n;
  wire        s_mi;
  wire        s_ovf_n;
  wire        s_ovf;
  wire        s_sts_0_n;
  wire        s_sts_1_n;
  wire        s_sts_2_n;
  wire        s_sts_3_n;
  wire        s_sts_4_n;
  wire        s_sts_5_n;
  wire        s_sts_6_n;
  wire        s_sts_7_n;
  wire        s_sts_8_n;
  wire        s_sts_9_n;
  wire        s_sts_10_n;
  wire        s_sts_11_n;
  wire        s_sts_12_n;
  wire        s_sts_13_n;
  wire        s_sts_14_n;
  wire        s_sts_15_n;

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_csts_1_0[1:0]    = CSTS_1_0;
  assign s_fidbo_15_0[15:0] = FIDBO_15_0;
  assign s_ldpil_n          = LDPILN;
  assign s_aluclk           = ALUCLK;

  // P2b (docs/plan-fix-unconstrained-clocks.md): in FF mode the ALUCLK-
  // clocked registers capture on posedge sysclk gated by ALUCLK_EN
  // (aligned to the ALUCLK rise) instead of clocking on the routed net.
`ifdef FPGA_FF_MODE
  localparam ALUCLK_CE = 1;
`else
  localparam ALUCLK_CE = 0;
`endif

  assign s_ovf              = OVF;
  assign s_mi               = MI;
  assign s_cry              = CRY;

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign STS_15_0           = s_sts_15_0_out[15:0];

  /*******************************************************************************
   ** Here all in-lined components are defined                                   **
   *******************************************************************************/

  // NOT Gate
  assign s_sts_15_0_out[0]  = ~s_sts_0_n;
  assign s_sts_15_0_out[1]  = ~s_sts_1_n;
  assign s_sts_15_0_out[2]  = ~s_sts_2_n;
  assign s_sts_15_0_out[3]  = ~s_sts_3_n;
  assign s_sts_15_0_out[4]  = ~s_sts_4_n;
  assign s_sts_15_0_out[5]  = ~s_sts_5_n;
  assign s_sts_15_0_out[6]  = ~s_sts_6_n;
  assign s_sts_15_0_out[7]  = ~s_sts_7_n;
  assign s_sts_15_0_out[8]  = ~s_sts_8_n;
  assign s_sts_15_0_out[9]  = ~s_sts_9_n;
  assign s_sts_15_0_out[10] = ~s_sts_10_n;
  assign s_sts_15_0_out[11] = ~s_sts_11_n;
  assign s_sts_15_0_out[12] = ~s_sts_12_n;
  assign s_sts_15_0_out[13] = ~s_sts_13_n;
  assign s_sts_15_0_out[14] = ~s_sts_14_n;
  assign s_sts_15_0_out[15] = ~s_sts_15_n;

  assign s_ovf_n            = ~s_ovf;
  assign s_csts_1_n         = ~s_csts_1_0[1];
  assign s_csts_0_n         = ~s_csts_1_0[0];

  /*******************************************************************************
   ** Here all normal components are defined                                     **
   *******************************************************************************/
  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_1 (
      .input1(s_ovf_n),
      .input2(s_sts_5_n),
      .result(s_gates1_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_2 (
      .input1(s_csts_1_0[1]),
      .input2(s_csts_1_0[0]),
      .result(s_gates2_out)
  );


  /*******************************************************************************
   ** Here all sub-circuits are defined                                          **
   *******************************************************************************/

  MUX41P STS7_MUX (
      .A (s_csts_1_n),
      .B (s_csts_0_n),
      .D0(s_fidbo_15_0[7]),
      .D1(s_sts_15_0_out[7]),
      .D2(s_mi),
      .D3(s_sts_15_0_out[7]),
      .Z (s_ists_7)
  );

  MUX31LP STS6_MUX (
      .A (s_csts_1_n),
      .B (s_csts_0_n),
      .D0(s_fidbo_15_0[6]),
      .D1(s_cry),
      .D2(s_sts_15_0_out[6]),
      .ZN(s_ists_6)
  );

  MUX31LP STS5_MUX (
      .A (s_csts_1_n),
      .B (s_csts_0_n),
      .D0(s_fidbo_15_0[5]),
      .D1(s_gates1_out),
      .D2(s_sts_15_0_out[5]),
      .ZN(s_ists_5)
  );

  MUX31LP STS4_MUX (
      .A (s_csts_1_n),
      .B (s_csts_0_n),
      .D0(s_fidbo_15_0[4]),
      .D1(s_ovf),
      .D2(s_sts_15_0_out[4]),
      .ZN(s_ists_4)
  );



  R41P_EN #(.USE_ENABLE(ALUCLK_CE)) STS_REG_MID (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CP(s_aluclk),
      .A  (s_ists_7),
      .B  (s_ists_6),
      .C  (s_ists_5),
      .D  (s_ists_4),
      .QA (),
      .QAN(s_sts_7_n),
      .QB (s_sts_6_n),
      .QBN(),
      .QC (s_sts_5_n),
      .QCN(),
      .QD (s_sts_4_n),
      .QDN()
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) STS15_FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_fidbo_15_0[15]),
      .Q  (),
      .QN (s_sts_15_n),
      .TE (s_ldpil_n),
      .TI (s_sts_15_0_out[15])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) STS14_FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_fidbo_15_0[14]),
      .Q  (),
      .QN (s_sts_14_n),
      .TE (s_ldpil_n),
      .TI (s_sts_15_0_out[14])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) STS13_FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_fidbo_15_0[13]),
      .Q  (),
      .QN (s_sts_13_n),
      .TE (s_ldpil_n),
      .TI (s_sts_15_0_out[13])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) STS12_FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_fidbo_15_0[12]),
      .Q  (),
      .QN (s_sts_12_n),
      .TE (s_ldpil_n),
      .TI (s_sts_15_0_out[12])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) STS11_FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_fidbo_15_0[11]),
      .Q  (),
      .QN (s_sts_11_n),
      .TE (s_ldpil_n),
      .TI (s_sts_15_0_out[11])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) STS10_FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_fidbo_15_0[10]),
      .Q  (),
      .QN (s_sts_10_n),
      .TE (s_ldpil_n),
      .TI (s_sts_15_0_out[10])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) STS9_FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_fidbo_15_0[9]),
      .Q  (),
      .QN (s_sts_9_n),
      .TE (s_ldpil_n),
      .TI (s_sts_15_0_out[9])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) STS8_FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_fidbo_15_0[8]),
      .Q  (),
      .QN (s_sts_8_n),
      .TE (s_ldpil_n),
      .TI (s_sts_15_0_out[8])
  );

  // 7-4?

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) STS3_FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_fidbo_15_0[3]),
      .Q  (),
      .QN (s_sts_3_n),
      .TE (s_gates2_out),
      .TI (s_sts_15_0_out[3])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) STS2_FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_fidbo_15_0[2]),
      .Q  (),
      .QN (s_sts_2_n),
      .TE (s_gates2_out),
      .TI (s_sts_15_0_out[2])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) STS1_FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_fidbo_15_0[1]),
      .Q  (),
      .QN (s_sts_1_n),
      .TE (s_gates2_out),
      .TI (s_sts_15_0_out[1])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) STS0_FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_fidbo_15_0[0]),
      .Q  (),
      .QN (s_sts_0_n),
      .TE (s_gates2_out),
      .TI (s_sts_15_0_out[0])
  );



endmodule
