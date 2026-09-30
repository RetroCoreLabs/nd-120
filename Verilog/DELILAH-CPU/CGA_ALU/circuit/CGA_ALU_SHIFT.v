/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/ALU/SHIFT                                                        **
**                                                                       **
** Page 49                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 10-NOV-2024                                            **
** Ronny Hansen                                                          **
***************************************************************************/

module CGA_ALU_SHIFT (
    input        ALUI7,  //! ALU Instruction bit 7 output (from CGA_CPU_ALU_CONTR.ALUI7)
    input        ALUI8N,  //! ALU Instruction bit 8, active low output (from CGA_CPU_ALU_CONTR.ALUI8N)
    input [15:0] F_15_0,  //! Function Result (15:0) (from CGA_CPU_ALU_RALU.F_15_0)
    input        RLI,  //! Register Load Indicator signal (from CGA_CPU_ALU_CONTR.RLI)
    input        RRI,  //! Register Right Immediate control signal (from CGA_CPU_ALU_CONTR.RRI)

    output [15:0] RB_15_0
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [15:0] s_f_15_0;
  wire [15:0] s_rb15_0_out;

  wire        s_alui7;
  wire        s_alui8_n;
  wire        s_rb_0_n_out;
  wire        s_rb_1_n_out;
  wire        s_rb_10_n_out;
  wire        s_rb_11_n_out;
  wire        s_rb_12_n_out;
  wire        s_rb_13_n_out;
  wire        s_rb_14_n_out;
  wire        s_rb_15_n_out;
  wire        s_rb_2_n_out;
  wire        s_rb_3_n_out;
  wire        s_rb_4_n_out;
  wire        s_rb_5_n_out;
  wire        s_rb_6_n_out;
  wire        s_rb_7_n_out;
  wire        s_rb_8_n_out;
  wire        s_rb_9_n_out;
  wire        s_rli;
  wire        s_rri;


  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_f_15_0[15:0]   = F_15_0;
  assign s_alui8_n        = ALUI8N;
  assign s_rli            = RLI;
  assign s_rri            = RRI;
  assign s_alui7          = ALUI7;

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign RB_15_0          = s_rb15_0_out[15:0];

  /*******************************************************************************
   ** Here all in-lined components are defined                                   **
   *******************************************************************************/

  assign s_rb15_0_out[0]  = ~s_rb_0_n_out;
  assign s_rb15_0_out[1]  = ~s_rb_1_n_out;
  assign s_rb15_0_out[2]  = ~s_rb_2_n_out;
  assign s_rb15_0_out[3]  = ~s_rb_3_n_out;
  assign s_rb15_0_out[4]  = ~s_rb_4_n_out;
  assign s_rb15_0_out[5]  = ~s_rb_5_n_out;
  assign s_rb15_0_out[6]  = ~s_rb_6_n_out;
  assign s_rb15_0_out[7]  = ~s_rb_7_n_out;
  assign s_rb15_0_out[8]  = ~s_rb_8_n_out;
  assign s_rb15_0_out[9]  = ~s_rb_9_n_out;
  assign s_rb15_0_out[10] = ~s_rb_10_n_out;
  assign s_rb15_0_out[11] = ~s_rb_11_n_out;
  assign s_rb15_0_out[12] = ~s_rb_12_n_out;
  assign s_rb15_0_out[13] = ~s_rb_13_n_out;
  assign s_rb15_0_out[14] = ~s_rb_14_n_out;
  assign s_rb15_0_out[15] = ~s_rb_15_n_out;

  /*******************************************************************************
   ** Here all sub-circuits are defined                                          **
   *******************************************************************************/

  MUX31LP RB0MUX (
      .A (s_alui7),
      .B (s_alui8_n),
      .D0(s_f_15_0[1]),
      .D1(s_rli),
      .D2(s_f_15_0[0]),
      .ZN(s_rb_0_n_out)
  );

  MUX31LP RB1MUX (
      .A (s_alui7),
      .B (s_alui8_n),
      .D0(s_f_15_0[2]),
      .D1(s_f_15_0[0]),
      .D2(s_f_15_0[1]),
      .ZN(s_rb_1_n_out)
  );

  MUX31LP RB2MUX (
      .A (s_alui7),
      .B (s_alui8_n),
      .D0(s_f_15_0[3]),
      .D1(s_f_15_0[1]),
      .D2(s_f_15_0[2]),
      .ZN(s_rb_2_n_out)
  );

  MUX31LP RB3MUX (
      .A (s_alui7),
      .B (s_alui8_n),
      .D0(s_f_15_0[4]),
      .D1(s_f_15_0[2]),
      .D2(s_f_15_0[3]),
      .ZN(s_rb_3_n_out)
  );

  MUX31LP RB4MUX (
      .A (s_alui7),
      .B (s_alui8_n),
      .D0(s_f_15_0[5]),
      .D1(s_f_15_0[3]),
      .D2(s_f_15_0[4]),
      .ZN(s_rb_4_n_out)
  );

  MUX31LP RB5MUX (
      .A (s_alui7),
      .B (s_alui8_n),
      .D0(s_f_15_0[6]),
      .D1(s_f_15_0[4]),
      .D2(s_f_15_0[5]),
      .ZN(s_rb_5_n_out)
  );

  MUX31LP RB6MUX (
      .A (s_alui7),
      .B (s_alui8_n),
      .D0(s_f_15_0[7]),
      .D1(s_f_15_0[5]),
      .D2(s_f_15_0[6]),
      .ZN(s_rb_6_n_out)
  );

  MUX31LP RB7MUX (
      .A (s_alui7),
      .B (s_alui8_n),
      .D0(s_f_15_0[8]),
      .D1(s_f_15_0[6]),
      .D2(s_f_15_0[7]),
      .ZN(s_rb_7_n_out)
  );

  MUX31LP RB8MUX (
      .A (s_alui7),
      .B (s_alui8_n),
      .D0(s_f_15_0[9]),
      .D1(s_f_15_0[7]),
      .D2(s_f_15_0[8]),
      .ZN(s_rb_8_n_out)
  );

  MUX31LP RB9MUX (
      .A (s_alui7),
      .B (s_alui8_n),
      .D0(s_f_15_0[10]),
      .D1(s_f_15_0[8]),
      .D2(s_f_15_0[9]),
      .ZN(s_rb_9_n_out)
  );

  MUX31LP RB10MUX (
      .A (s_alui7),
      .B (s_alui8_n),
      .D0(s_f_15_0[11]),
      .D1(s_f_15_0[9]),
      .D2(s_f_15_0[10]),
      .ZN(s_rb_10_n_out)
  );

  MUX31LP RB11MUX (
      .A (s_alui7),
      .B (s_alui8_n),
      .D0(s_f_15_0[12]),
      .D1(s_f_15_0[10]),
      .D2(s_f_15_0[11]),
      .ZN(s_rb_11_n_out)
  );

  MUX31LP RB12MUX (
      .A (s_alui7),
      .B (s_alui8_n),
      .D0(s_f_15_0[13]),
      .D1(s_f_15_0[11]),
      .D2(s_f_15_0[12]),
      .ZN(s_rb_12_n_out)
  );

  MUX31LP RB13MUX (
      .A (s_alui7),
      .B (s_alui8_n),
      .D0(s_f_15_0[14]),
      .D1(s_f_15_0[12]),
      .D2(s_f_15_0[13]),
      .ZN(s_rb_13_n_out)
  );

  MUX31LP RB14MUX (
      .A (s_alui7),
      .B (s_alui8_n),
      .D0(s_f_15_0[15]),
      .D1(s_f_15_0[13]),
      .D2(s_f_15_0[14]),
      .ZN(s_rb_14_n_out)
  );

  MUX31LP RB15MUX (
      .A (s_alui7),
      .B (s_alui8_n),
      .D0(s_rri),
      .D1(s_f_15_0[14]),
      .D2(s_f_15_0[15]),
      .ZN(s_rb_15_n_out)
  );

endmodule
