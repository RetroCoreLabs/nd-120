/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/ALU/RALU/LOGOP                                                   **
** LOGOP                                                                 **
**                                                                       **
** Page 48                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 10-NOV-2024                                            **
** Ronny Hansen                                                          **
**************************************************************************/

module CGA_ALU_RALU_LOGOP (
    input        ALU14,  //! ALU Instruction - bit 4 (from CGA_CPU_ALU_RALU.ALUI4)
    input [15:0] A_15_0,
    input        FSEL,  //! Function Select (1=Logic function (XOR), 0=OR/AND/NOT) (from CGA_CPU_ALU_RALU.FSEL)
    input [15:0] S_15_0,

    output [15:0] LF_15_0
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [15:0] s_s_15_0;
  wire [15:0] s_a_15_0;
  wire [15:0] s_lf_15__out;
  wire        s_alu14;
  wire        s_fsel;
  wire        s_gnd;

  /*******************************************************************************
   ** The module functionality is described here                                 **
   *******************************************************************************/

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_s_15_0[15:0] = S_15_0;
  assign s_a_15_0[15:0] = A_15_0;
  assign s_alu14        = ALU14;
  assign s_fsel         = FSEL;

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign LF_15_0        = s_lf_15__out[15:0];

  /*******************************************************************************
   ** Here all in-lined components are defined                                   **
   *******************************************************************************/

  // Ground
  assign s_gnd          = 1'b0;

  /*******************************************************************************
   ** Here all sub-circuits are defined                                          **
   *******************************************************************************/

  MUX41P MUXLF15 (
      .A (s_a_15_0[15]),
      .B (s_s_15_0[15]),
      .D0(s_gnd),
      .D1(s_alu14),
      .D2(s_alu14),
      .D3(s_fsel),
      .Z (s_lf_15__out[15])
  );

  MUX41P MUXLF14 (
      .A (s_a_15_0[14]),
      .B (s_s_15_0[14]),
      .D0(s_gnd),
      .D1(s_alu14),
      .D2(s_alu14),
      .D3(s_fsel),
      .Z (s_lf_15__out[14])
  );

  MUX41P MUXLF13 (
      .A (s_a_15_0[13]),
      .B (s_s_15_0[13]),
      .D0(s_gnd),
      .D1(s_alu14),
      .D2(s_alu14),
      .D3(s_fsel),
      .Z (s_lf_15__out[13])
  );

  MUX41P MUXLF12 (
      .A (s_a_15_0[12]),
      .B (s_s_15_0[12]),
      .D0(s_gnd),
      .D1(s_alu14),
      .D2(s_alu14),
      .D3(s_fsel),
      .Z (s_lf_15__out[12])
  );

  MUX41P MUXLF11 (
      .A (s_a_15_0[11]),
      .B (s_s_15_0[11]),
      .D0(s_gnd),
      .D1(s_alu14),
      .D2(s_alu14),
      .D3(s_fsel),
      .Z (s_lf_15__out[11])
  );

  MUX41P MUXLF10 (
      .A (s_a_15_0[10]),
      .B (s_s_15_0[10]),
      .D0(s_gnd),
      .D1(s_alu14),
      .D2(s_alu14),
      .D3(s_fsel),
      .Z (s_lf_15__out[10])
  );

  MUX41P MUXLF9 (
      .A (s_a_15_0[9]),
      .B (s_s_15_0[9]),
      .D0(s_gnd),
      .D1(s_alu14),
      .D2(s_alu14),
      .D3(s_fsel),
      .Z (s_lf_15__out[9])
  );

  MUX41P MUXLF8 (
      .A (s_a_15_0[8]),
      .B (s_s_15_0[8]),
      .D0(s_gnd),
      .D1(s_alu14),
      .D2(s_alu14),
      .D3(s_fsel),
      .Z (s_lf_15__out[8])
  );

  MUX41P MUXLF7 (
      .A (s_a_15_0[7]),
      .B (s_s_15_0[7]),
      .D0(s_gnd),
      .D1(s_alu14),
      .D2(s_alu14),
      .D3(s_fsel),
      .Z (s_lf_15__out[7])
  );

  MUX41P MUXLF6 (
      .A (s_a_15_0[6]),
      .B (s_s_15_0[6]),
      .D0(s_gnd),
      .D1(s_alu14),
      .D2(s_alu14),
      .D3(s_fsel),
      .Z (s_lf_15__out[6])
  );

  MUX41P MUXLF5 (
      .A (s_a_15_0[5]),
      .B (s_s_15_0[5]),
      .D0(s_gnd),
      .D1(s_alu14),
      .D2(s_alu14),
      .D3(s_fsel),
      .Z (s_lf_15__out[5])
  );



  MUX41P MUXLF4 (
      .A (s_a_15_0[4]),
      .B (s_s_15_0[4]),
      .D0(s_gnd),
      .D1(s_alu14),
      .D2(s_alu14),
      .D3(s_fsel),
      .Z (s_lf_15__out[4])
  );

  MUX41P MUXLL3 (
      .A (s_a_15_0[3]),
      .B (s_s_15_0[3]),
      .D0(s_gnd),
      .D1(s_alu14),
      .D2(s_alu14),
      .D3(s_fsel),
      .Z (s_lf_15__out[3])
  );

  MUX41P MUXLF2 (
      .A (s_a_15_0[2]),
      .B (s_s_15_0[2]),
      .D0(s_gnd),
      .D1(s_alu14),
      .D2(s_alu14),
      .D3(s_fsel),
      .Z (s_lf_15__out[2])
  );

  MUX41P MUXLF1 (
      .A (s_a_15_0[1]),
      .B (s_s_15_0[1]),
      .D0(s_gnd),
      .D1(s_alu14),
      .D2(s_alu14),
      .D3(s_fsel),
      .Z (s_lf_15__out[1])
  );

  MUX41P MUXLF0 (
      .A (s_a_15_0[0]),
      .B (s_s_15_0[0]),
      .D0(s_gnd),
      .D1(s_alu14),
      .D2(s_alu14),
      .D3(s_fsel),
      .Z (s_lf_15__out[0])
  );


endmodule
