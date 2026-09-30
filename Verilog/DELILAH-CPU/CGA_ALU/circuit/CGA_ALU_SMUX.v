/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/ALU/SMUX                                                         **
** SMUX                                                                  **
**                                                                       **
** Page 45                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 10-NOV-2024                                            **
** Ronny Hansen                                                          **
**************************************************************************/

module CGA_ALU_SMUX (
    input [15:0] A_15_0,  //! DATA output 16 bit A, from register selected by LAA_3_0 (from CGA_WRF.A_15_0)
    input [15:0] B_15_0,  //! DATA output 16 bit B, from register selected by LBA_3_0 (from CGA_WRF.B_15_0)
    input [15:0] Q_15_0,
    input        SA,  //! Source A selector for ALU operations (from CGA_CPU_ALU_CONTR.SA)
    input        SB,  //! Source B selector for ALU operations (from CGA_CPU_ALU_CONTR.SB)

    output [15:0] S_15_0
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [15:0] s_b_15_0;
  wire [15:0] s_q_15_0;
  wire [15:0] s_a_15_0;
  wire [15:0] s_s_15_0_out;
  wire        s_gnd;
  wire        s_sa;
  wire        s_sb;

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_b_15_0[15:0] = B_15_0;
  assign s_a_15_0[15:0] = A_15_0;
  assign s_q_15_0[15:0] = Q_15_0;
  assign s_sa           = SA;
  assign s_sb           = SB;

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign S_15_0         = s_s_15_0_out[15:0];

  /*******************************************************************************
   ** Here all in-lined components are defined                                   **
   *******************************************************************************/

  // Ground
  assign s_gnd          = 1'b0;


  /*******************************************************************************
   ** Here all sub-circuits are defined                                          **
   *******************************************************************************/
   MUX41P MUXS15 (
      .A (s_sa),
      .B (s_sb),
      .D0(s_q_15_0[15]),
      .D1(s_b_15_0[15]),
      .D2(s_gnd),
      .D3(s_a_15_0[15]),
      .Z (s_s_15_0_out[15])
  );

  MUX41P MUXS14 (
      .A (s_sa),
      .B (s_sb),
      .D0(s_q_15_0[14]),
      .D1(s_b_15_0[14]),
      .D2(s_gnd),
      .D3(s_a_15_0[14]),
      .Z (s_s_15_0_out[14])
  );

  MUX41P MUXS13 (
      .A (s_sa),
      .B (s_sb),
      .D0(s_q_15_0[13]),
      .D1(s_b_15_0[13]),
      .D2(s_gnd),
      .D3(s_a_15_0[13]),
      .Z (s_s_15_0_out[13])
  );
  MUX41P MUXS12 (
      .A (s_sa),
      .B (s_sb),
      .D0(s_q_15_0[12]),
      .D1(s_b_15_0[12]),
      .D2(s_gnd),
      .D3(s_a_15_0[12]),
      .Z (s_s_15_0_out[12])
  );

  MUX41P MUXS11 (
      .A (s_sa),
      .B (s_sb),
      .D0(s_q_15_0[11]),
      .D1(s_b_15_0[11]),
      .D2(s_gnd),
      .D3(s_a_15_0[11]),
      .Z (s_s_15_0_out[11])
  );

  MUX41P MUXS10 (
      .A (s_sa),
      .B (s_sb),
      .D0(s_q_15_0[10]),
      .D1(s_b_15_0[10]),
      .D2(s_gnd),
      .D3(s_a_15_0[10]),
      .Z (s_s_15_0_out[10])
  );

  MUX41P MUXS9 (
      .A (s_sa),
      .B (s_sb),
      .D0(s_q_15_0[9]),
      .D1(s_b_15_0[9]),
      .D2(s_gnd),
      .D3(s_a_15_0[9]),
      .Z (s_s_15_0_out[9])
  );

  MUX41P MUXS8 (
      .A (s_sa),
      .B (s_sb),
      .D0(s_q_15_0[8]),
      .D1(s_b_15_0[8]),
      .D2(s_gnd),
      .D3(s_a_15_0[8]),
      .Z (s_s_15_0_out[8])
  );

  MUX41P MUXS7 (
      .A (s_sa),
      .B (s_sb),
      .D0(s_q_15_0[7]),
      .D1(s_b_15_0[7]),
      .D2(s_gnd),
      .D3(s_a_15_0[7]),
      .Z (s_s_15_0_out[7])
  );

  MUX41P MUXS6 (
      .A (s_sa),
      .B (s_sb),
      .D0(s_q_15_0[6]),
      .D1(s_b_15_0[6]),
      .D2(s_gnd),
      .D3(s_a_15_0[6]),
      .Z (s_s_15_0_out[6])
  );

  MUX41P MUXS5 (
      .A (s_sa),
      .B (s_sb),
      .D0(s_q_15_0[5]),
      .D1(s_b_15_0[5]),
      .D2(s_gnd),
      .D3(s_a_15_0[5]),
      .Z (s_s_15_0_out[5])
  );

  MUX41P MUXS4 (
      .A (s_sa),
      .B (s_sb),
      .D0(s_q_15_0[4]),
      .D1(s_b_15_0[4]),
      .D2(s_gnd),
      .D3(s_a_15_0[4]),
      .Z (s_s_15_0_out[4])
  );

  MUX41P MUXS3 (
      .A (s_sa),
      .B (s_sb),
      .D0(s_q_15_0[3]),
      .D1(s_b_15_0[3]),
      .D2(s_gnd),
      .D3(s_a_15_0[3]),
      .Z (s_s_15_0_out[3])
  );

  MUX41P MUXS2 (
      .A (s_sa),
      .B (s_sb),
      .D0(s_q_15_0[2]),
      .D1(s_b_15_0[2]),
      .D2(s_gnd),
      .D3(s_a_15_0[2]),
      .Z (s_s_15_0_out[2])
  );

  MUX41P MUXS1 (
      .A (s_sa),
      .B (s_sb),
      .D0(s_q_15_0[1]),
      .D1(s_b_15_0[1]),
      .D2(s_gnd),
      .D3(s_a_15_0[1]),
      .Z (s_s_15_0_out[1])
  );

  MUX41P MUXS0 (
      .A (s_sa),
      .B (s_sb),
      .D0(s_q_15_0[0]),
      .D1(s_b_15_0[0]),
      .D2(s_gnd),
      .D3(s_a_15_0[0]),
      .Z (s_s_15_0_out[0])
  );



endmodule
