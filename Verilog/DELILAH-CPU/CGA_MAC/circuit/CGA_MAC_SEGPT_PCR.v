/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/MAC/SEGPT/PCR                                                    **
** PCR REGISTER                                                          **
**                                                                       **
** Page 37                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 9-FEB-2025                                             **
** Ronny Hansen                                                          **
**                                                                       **
** 02-FEB-2025 - Refactored and renamed FIDBO_15_7_2_0 to FIDBO_15_0     **
**               Refactored and merged output PCR_14_13_10_9_N and       **
**               PCR_15_7_2_0 to PCR_15_0                                **
***************************************************************************/


module CGA_MAC_SEGPT_PCR (
    // System input signals
    input sysclk,    // System clock in FPGA
    input sys_rst_n, // System reset in FPGA

    // Input signals
    input [15:0] FIDBO_15_0,  //! FIDBO output from previous stage (from CGA_MAC.FIDBO_15_0)
    input        LLDPCR,
    input        MCLKN,

    // Output signals
    output [15:0] PCR_15_0,  //! Program Counter Register bits 15 to 0 (to CGA_MAC.PCR_15_0)

    // Registered readback tap (21-AUG-2026): same stored value as PCR_15_0
    // but taken from the L8/L4 register (QA_R taps), WITHOUT the FF-mode
    // transparent bypass. Feeds ONLY the IDBCTL/SEL6 IDB readback - this
    // cuts the combinational IDB ring FIDBO -> PCR -> SEL6 -> FIDBI ->
    // OUTMUX(EFIDB) -> FIDBO. All other consumers keep PCR_15_0.
    output [15:0] PCR_RB_15_0  //! registered readback tap for IDBCTL/SEL6 (loop cut) (to CGA_MAC_SEGPT.PCR_RB_15_0)
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [15:0] s_pcr_15_0_out;
  wire [15:0] s_pcr_rb_15_0_out;
  wire [15:0] s_fidbo_15_0;
  wire        s_gates1_out;
  wire        s_lldpcr;
  wire        s_mclk_n;

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_fidbo_15_0[15:0]     = FIDBO_15_0;
  assign s_mclk_n               = MCLKN;
  assign s_lldpcr               = LLDPCR;

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign PCR_15_0               = s_pcr_15_0_out[15:0];
  assign PCR_RB_15_0            = s_pcr_rb_15_0_out[15:0];

  // Bits 6:3 is PIL (current program level), and is not set here.
  assign s_pcr_15_0_out[6:3] = 4'b0000;
  assign s_pcr_rb_15_0_out[6:3] = 4'b0000;

  // Code to make LINTER not complain about bits not read in FIDBO 6:3
  (* keep = "true", DONT_TOUCH = "true" *) wire [4:0] unused_FIDBO_bits;
  assign unused_FIDBO_bits[4:0] = s_fidbo_15_0[6:3];

  /*******************************************************************************
   ** Here all normal components are defined                                     **
   *******************************************************************************/
  AND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_1 (
      .input1(s_mclk_n),
      .input2(s_lldpcr),
      .result(s_gates1_out)
  );


  /*******************************************************************************
   ** Here all sub-circuits are defined                                          **
   *******************************************************************************/

  L8 PCR_HI (
    // Input signals
    .sysclk(sysclk),                          // System clock in FPGA
    .sys_rst_n(sys_rst_n),                    // System reset in FPGA

    .A  (s_fidbo_15_0[15]),
    .B  (s_fidbo_15_0[14]),
    .C  (s_fidbo_15_0[13]),
    .D  (s_fidbo_15_0[12]),
    .E  (s_fidbo_15_0[11]),
    .F  (s_fidbo_15_0[10]),
    .G  (s_fidbo_15_0[9]),
    .H  (s_fidbo_15_0[8]),
    .L  (s_gates1_out),
    .QA (s_pcr_15_0_out[15]),
    .QAN(),
    .QB (s_pcr_15_0_out[14]),
    .QBN(),
    .QC (s_pcr_15_0_out[13]),
    .QCN(),
    .QD (s_pcr_15_0_out[12]),
    .QDN(),
    .QE (s_pcr_15_0_out[11]),
    .QEN(),
    .QF (s_pcr_15_0_out[10]),
    .QFN(),
    .QG (s_pcr_15_0_out[9]),
    .QGN(),
    .QH (s_pcr_15_0_out[8]),
    .QHN(),
    .QA_R(s_pcr_rb_15_0_out[15]),
    .QB_R(s_pcr_rb_15_0_out[14]),
    .QC_R(s_pcr_rb_15_0_out[13]),
    .QD_R(s_pcr_rb_15_0_out[12]),
    .QE_R(s_pcr_rb_15_0_out[11]),
    .QF_R(s_pcr_rb_15_0_out[10]),
    .QG_R(s_pcr_rb_15_0_out[9]),
    .QH_R(s_pcr_rb_15_0_out[8])
  );



  L4 PCR_LO
  (
    // Input signals
    .sysclk(sysclk),                          // System clock in FPGA
    .sys_rst_n(sys_rst_n),                    // System reset in FPGA

    .L  (s_gates1_out),

    .A  (s_fidbo_15_0[7]),
    .B  (s_fidbo_15_0[2]),
    .C  (s_fidbo_15_0[1]),
    .D  (s_fidbo_15_0[0]),

    .QA (s_pcr_15_0_out[7]),
    .QAN(),
    .QB (s_pcr_15_0_out[2]),
    .QBN(),
    .QC (s_pcr_15_0_out[1]),
    .QCN(),
    .QD (s_pcr_15_0_out[0]),
    .QDN(),
    .QA_R(s_pcr_rb_15_0_out[7]),
    .QB_R(s_pcr_rb_15_0_out[2]),
    .QC_R(s_pcr_rb_15_0_out[1]),
    .QD_R(s_pcr_rb_15_0_out[0])
  );

endmodule
