/**************************************************************************
** ND120 CPU, MM&M                                                       **
** CGA/WRF/RBLOCK/LR16                                                   **
** WRF: Working Register File                                            **
** (PDF page 63)                                                         **
**                                                                       **
** Last reviewed: 9-FEB-2025                                             **
** Ronny Hansen                                                          **
***************************************************************************/


module CGA_WRF_RBLOCK_LR16 (
    // System input signals
    input sysclk,    // System clock in FPGA
    input sys_rst_n, // System reset in FPGA

    input        ALUCLK_EN,  //! ALUCLK clock-enable pulse (FPGA_FF_MODE, else 0)
    input        ALUCLK,  //! To clock the operation (from CGA_WRF_RBLOCK.ALUCLK)
    input [15:0] RB_15_0,  //! Register B DATA (Destination) for WRITE. 16 bits to select register(s) (from CGA_WRF_RBLOCK.RB_15_0)
    input        WR,

    output [15:0] LR_15_0,
    output [15:0] R_15_0
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire        s_aluclk;
  wire        s_lreg_latch;
  wire        s_wr;
  wire [15:0] s_lr_15_0_out;
  wire [15:0] s_r_15_0_out;
  wire [15:0] s_rb_15_0;
  wire [15:0] s_ir_15_0;

  /*******************************************************************************
   ** The module functionality is described here                                 **
   *******************************************************************************/

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_rb_15_0[15:0] = RB_15_0;
  assign s_aluclk        = ALUCLK;

  // P2b (docs/plan-fix-unconstrained-clocks.md): in FF mode the ALUCLK-
  // clocked registers capture on posedge sysclk gated by ALUCLK_EN
  // (aligned to the ALUCLK rise) instead of clocking on the routed net.
`ifdef FPGA_FF_MODE
  localparam ALUCLK_CE = 1;
`else
  localparam ALUCLK_CE = 0;
`endif

  assign s_wr            = WR;

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign LR_15_0         = s_lr_15_0_out[15:0];
  assign R_15_0          = s_r_15_0_out[15:0];

  /*******************************************************************************
   ** Here all in-lined components are defined                                   **
   *******************************************************************************/

  // Latch signal <= /ALUCLK * WR
  assign s_lreg_latch    = ~s_aluclk & s_wr;


  /*******************************************************************************
   ** Here all sub-circuits are defined                                         **
   *******************************************************************************/

   /* Input RB (15:0) or output signal R(15:0) muxed to internal signal         */
   /* s_ir_n based on value of s_wr                                             */
   /* To the left in the schematich diagram on page 63                          */

   MUX24P MUX_15_12 (
      .A  (s_wr),

      .D00(s_r_15_0_out[15]),
      .D01(s_r_15_0_out[14]),
      .D02(s_r_15_0_out[13]),
      .D03(s_r_15_0_out[12]),

      .D10(s_rb_15_0[15]),
      .D11(s_rb_15_0[14]),
      .D12(s_rb_15_0[13]),
      .D13(s_rb_15_0[12]),

      .Z0 (s_ir_15_0[15]),
      .Z1 (s_ir_15_0[14]),
      .Z2 (s_ir_15_0[13]),
      .Z3 (s_ir_15_0[12])
  );

  MUX24P MUX_11_8 (
      .A  (s_wr),

      .D00(s_r_15_0_out[11]),
      .D01(s_r_15_0_out[10]),
      .D02(s_r_15_0_out[9]),
      .D03(s_r_15_0_out[8]),

      .D10(s_rb_15_0[11]),
      .D11(s_rb_15_0[10]),
      .D12(s_rb_15_0[9]),
      .D13(s_rb_15_0[8]),

      .Z0 (s_ir_15_0[11]),
      .Z1 (s_ir_15_0[10]),
      .Z2 (s_ir_15_0[9]),
      .Z3 (s_ir_15_0[8])
  );

  MUX24P MUX_7_4 (
      .A  (s_wr),

      .D00(s_r_15_0_out[7]),
      .D01(s_r_15_0_out[6]),
      .D02(s_r_15_0_out[5]),
      .D03(s_r_15_0_out[4]),

      .D10(s_rb_15_0[7]),
      .D11(s_rb_15_0[6]),
      .D12(s_rb_15_0[5]),
      .D13(s_rb_15_0[4]),

      .Z0 (s_ir_15_0[7]),
      .Z1 (s_ir_15_0[6]),
      .Z2 (s_ir_15_0[5]),
      .Z3 (s_ir_15_0[4])
  );

  MUX24P MUX_3_0 (
      .A  (s_wr),

      .D00(s_r_15_0_out[3]),
      .D01(s_r_15_0_out[2]),
      .D02(s_r_15_0_out[1]),
      .D03(s_r_15_0_out[0]),

      .D10(s_rb_15_0[3]),
      .D11(s_rb_15_0[2]),
      .D12(s_rb_15_0[1]),
      .D13(s_rb_15_0[0]),

      .Z0 (s_ir_15_0[3]),
      .Z1 (s_ir_15_0[2]),
      .Z2 (s_ir_15_0[1]),
      .Z3 (s_ir_15_0[0])
  );



  /* IR15-0 clocked to R(15:0) REG. In the middle of the schematich diagram on page 63 */

  // verilator lint_off UNUSED
  // verilator lint_off UNDRIVEN
  // verilator lint_off PINCONNECTEMPTY

  R81_EN #(.USE_ENABLE(ALUCLK_CE)) R_15_8 (

      .sysclk(sysclk),

      .EN(ALUCLK_EN),
      .A (s_ir_15_0[15]),
      .B (s_ir_15_0[14]),
      .C (s_ir_15_0[13]),
      .D (s_ir_15_0[12]),
      .E (s_ir_15_0[11]),
      .F (s_ir_15_0[10]),
      .G (s_ir_15_0[9]),
      .H (s_ir_15_0[8]),
      .CP(s_aluclk),

      .QA (s_r_15_0_out[15]),
      .QAN(),
      .QB (s_r_15_0_out[14]),
      .QBN(),
      .QC (s_r_15_0_out[13]),
      .QCN(),
      .QD (s_r_15_0_out[12]),
      .QDN(),
      .QE (s_r_15_0_out[11]),
      .QEN(),
      .QF (s_r_15_0_out[10]),
      .QFN(),
      .QG (s_r_15_0_out[9]),
      .QGN(),
      .QH (s_r_15_0_out[8]),
      .QHN()
  );

  R81_EN #(.USE_ENABLE(ALUCLK_CE)) R_7_0 (

      .sysclk(sysclk),

      .EN(ALUCLK_EN),
      .A(s_ir_15_0[7]),
      .B(s_ir_15_0[6]),
      .C(s_ir_15_0[5]),
      .D(s_ir_15_0[4]),
      .E(s_ir_15_0[3]),
      .F(s_ir_15_0[2]),
      .G(s_ir_15_0[1]),
      .H(s_ir_15_0[0]),

      .CP(s_aluclk),

      .QA (s_r_15_0_out[7]),
      .QAN(),
      .QB (s_r_15_0_out[6]),
      .QBN(),
      .QC (s_r_15_0_out[5]),
      .QCN(),
      .QD (s_r_15_0_out[4]),
      .QDN(),
      .QE (s_r_15_0_out[3]),
      .QEN(),
      .QF (s_r_15_0_out[2]),
      .QFN(),
      .QG (s_r_15_0_out[1]),
      .QGN(),
      .QH (s_r_15_0_out[0]),
      .QHN()
  );

  /* IR15-0 LATCHED to LR(15:0) LREG. To the right of the schematich diagram on page 63 */
  /* Latch signal (s_lreg_latch) = /ALUCLK * WR (s_aluclk_n & s_wr)                     */
  L8 L_15_8
  (
    // Input signals
    .sysclk(sysclk),                          // System clock in FPGA
    .sys_rst_n(sys_rst_n),                    // System reset in FPGA

    .L  (s_lreg_latch),

    .A  (s_ir_15_0[15]),
    .B  (s_ir_15_0[14]),
    .C  (s_ir_15_0[13]),
    .D  (s_ir_15_0[12]),
    .E  (s_ir_15_0[11]),
    .F  (s_ir_15_0[10]),
    .G  (s_ir_15_0[9]),
    .H  (s_ir_15_0[8]),

    .QA (s_lr_15_0_out[15]),
    .QAN(),
    .QB (s_lr_15_0_out[14]),
    .QBN(),
    .QC (s_lr_15_0_out[13]),
    .QCN(),
    .QD (s_lr_15_0_out[12]),
    .QDN(),
    .QE (s_lr_15_0_out[11]),
    .QEN(),
    .QF (s_lr_15_0_out[10]),
    .QFN(),
    .QG (s_lr_15_0_out[9]),
    .QGN(),
    .QH (s_lr_15_0_out[8]),
    .QHN(),
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


  L8 L_7_0
  (
    // Input signals
    .sysclk(sysclk),                          // System clock in FPGA
    .sys_rst_n(sys_rst_n),                    // System reset in FPGA

    .L  (s_lreg_latch),

    .A  (s_ir_15_0[7]),
    .B  (s_ir_15_0[6]),
    .C  (s_ir_15_0[5]),
    .D  (s_ir_15_0[4]),
    .E  (s_ir_15_0[3]),
    .F  (s_ir_15_0[2]),
    .G  (s_ir_15_0[1]),
    .H  (s_ir_15_0[0]),

    .QA (s_lr_15_0_out[7]),
    .QAN(),
    .QB (s_lr_15_0_out[6]),
    .QBN(),
    .QC (s_lr_15_0_out[5]),
    .QCN(),
    .QD (s_lr_15_0_out[4]),
    .QDN(),
    .QE (s_lr_15_0_out[3]),
    .QEN(),
    .QF (s_lr_15_0_out[2]),
    .QFN(),
    .QG (s_lr_15_0_out[1]),
    .QGN(),
    .QH (s_lr_15_0_out[0]),
    .QHN(),
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
