/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/MAC/SEGPT/SEG                                                    **
** SEGMENT REGISTER                                                      **
**                                                                       **
** Page 36                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 9-FEB-2025                                             **
** Ronny Hansen                                                          **
***************************************************************************/
module CGA_MAC_SEGPT_SEG (
    // System input signals
    input sysclk,    // System clock in FPGA
    input sys_rst_n, // System reset in FPGA

    // Input signals
    input [7:0] FIDBO_7_0,  //! FIDBO output from previous stage (from CGA_MAC.FIDBO_15_0[7:0])
    input       LLDSEG,
    input       MCLKN,

    // Output signal
    output       SEGZN,
    output [7:0] SEG_7_0
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [7:0] s_fidbo_7_0;
  wire [7:0] s_seg_7_0_n_out;
  wire [7:0] s_seg_7_0_out;

  wire       s_gates2_out;
  wire       s_lldseg;
  wire       s_mclk_n;
  wire       s_segz_n_out;

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_fidbo_7_0[7:0] = FIDBO_7_0;
  assign s_mclk_n         = MCLKN;
  assign s_lldseg         = LLDSEG;

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign SEGZN            = s_segz_n_out;
  assign SEG_7_0          = s_seg_7_0_out[7:0];

  /*******************************************************************************
   ** Here all normal components are defined                                     **
   *******************************************************************************/
  NAND_GATE_8_INPUTS #(
      .BubblesMask(8'h00)
  ) GATES_1 (
      .input1(s_seg_7_0_n_out[0]),
      .input2(s_seg_7_0_n_out[1]),
      .input3(s_seg_7_0_n_out[2]),
      .input4(s_seg_7_0_n_out[3]),
      .input5(s_seg_7_0_n_out[4]),
      .input6(s_seg_7_0_n_out[5]),
      .input7(s_seg_7_0_n_out[6]),
      .input8(s_seg_7_0_n_out[7]),
      .result(s_segz_n_out)
  );

  AND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_2 (
      .input1(s_mclk_n),
      .input2(s_lldseg),
      .result(s_gates2_out)
  );


  /*******************************************************************************
   ** Here all sub-circuits are defined                                          **
   *******************************************************************************/

  L8 SEG_L
  (
    // Input signals
    .sysclk(sysclk),                          // System clock in FPGA
    .sys_rst_n(sys_rst_n),                    // System reset in FPGA

    .A  (s_fidbo_7_0[0]),
    .B  (s_fidbo_7_0[1]),
    .C  (s_fidbo_7_0[2]),
    .D  (s_fidbo_7_0[3]),
    .E  (s_fidbo_7_0[4]),
    .F  (s_fidbo_7_0[5]),
    .G  (s_fidbo_7_0[6]),
    .H  (s_fidbo_7_0[7]),
    .L  (s_gates2_out),
    .QA (s_seg_7_0_out[0]),
    .QAN(s_seg_7_0_n_out[0]),
    .QB (s_seg_7_0_out[1]),
    .QBN(s_seg_7_0_n_out[1]),
    .QC (s_seg_7_0_out[2]),
    .QCN(s_seg_7_0_n_out[2]),
    .QD (s_seg_7_0_out[3]),
    .QDN(s_seg_7_0_n_out[3]),
    .QE (s_seg_7_0_out[4]),
    .QEN(s_seg_7_0_n_out[4]),
    .QF (s_seg_7_0_out[5]),
    .QFN(s_seg_7_0_n_out[5]),
    .QG (s_seg_7_0_out[6]),
    .QGN(s_seg_7_0_n_out[6]),
    .QH (s_seg_7_0_out[7]),
    .QHN(s_seg_7_0_n_out[7]),
    // registered-value taps: deliberately unconnected here -
    // the transparent output is the wanted one (see L8/L4 header).
    .QA_R(),
    .QB_R(),
    .QC_R(),
    .QD_R(),
    .QE_R(),
    .QF_R(),
    .QG_R(),
    .QH_R()
  );

endmodule
