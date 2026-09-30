/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/MAC/ADD/FASTADD                                                  **
** ADD                                                                   **
**                                                                       **
** Page 30                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 10-NOV-2024                                            **
** Ronny Hansen                                                          **
***************************************************************************/

module CGA_MAC_FASTADD (
    input [ 7:0] CDE_15_8,
    input [ 7:0] CD_7_0,  //! CPU data (Added to the selected register) (from CGA_MAC_ADD.CD_15_0[7:0])
    input [15:0] PRP_15_0,

    output [15:0] ADD_15_0  //! Addition result output (to CGA_MAC_ADD.ADD_15_0)
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [7:0] s_cd_7_0;
  wire [7:0] s_cde_15_8;
  wire [15:0] s_add_15_0_out;
  wire [15:0] s_prp_15_0;

  wire s_carryout_lo; // Carry from the low-8 bits adder to the high-8 bits addder

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_cd_7_0[7:0]    = CD_7_0;
  assign s_cde_15_8[7:0]  = CDE_15_8;
  assign s_prp_15_0[15:0] = PRP_15_0;

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign ADD_15_0         = s_add_15_0_out[15:0];

  /*******************************************************************************
   ** Here all normal components are defined                                     **
   *******************************************************************************/
  Adder #(
      .extendedBits(9),
      .nrOfBits(8)
  ) ARITH_1 (
      .carryIn(1'b0),
      .carryOut(s_carryout_lo),
      .dataA(s_cd_7_0[7:0]),
      .dataB(s_prp_15_0[7:0]),
      .result(s_add_15_0_out[7:0])
  );

  Adder #(
      .extendedBits(9),
      .nrOfBits(8)
  ) ARITH_2 (
      .carryIn(s_carryout_lo),
      .carryOut(),
      .dataA(s_cde_15_8[7:0]),
      .dataB(s_prp_15_0[15:8]),
      .result(s_add_15_0_out[15:8])
  );


endmodule
