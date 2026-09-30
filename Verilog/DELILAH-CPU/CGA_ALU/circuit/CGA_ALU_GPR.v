/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/ALU/GPR                                                          **
**                                                                       **
** Page 50                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 20-DEC-2024                                            **
** Ronny Hansen                                                          **
***************************************************************************/

module CGA_ALU_GPR (
    input        sysclk,     //! FPGA system clock (P2: ALUCLK_EN capture)
    input        ALUCLK_EN,  //! ALUCLK clock-enable pulse (FPGA_FF_MODE, else 0)
    input        ALUCLK,     //! ALU clock signal (from CPU_PROC_CGA_33.ALUCLK)
    input [15:0] CD_15_0,    //! Command/Data bus (from CPU_PROC_CGA_33.CD_15_0)
    input [15:0] FIDBO_15_0,
    input [ 2:0] GPRC_2_0,   //! General-Purpose Register Code (3-bit) (from CGA_CPU_ALU_CONTR.GPRC_2_0)
    input        GPRLI,      //! General-Purpose Register Load Indicator (from CGA_CPU_ALU_CONTR.GPRLI)

    output        DGPR0N,  //! Detect GPR0 is set. 
    output [15:0] GPR_15_0
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [15:0] s_cd_15_0;
  wire [15:0] s_gpr_15_0_out;
  wire [ 2:0] s_gprc_2_0;
  wire [15:0] s_fidbo_15_0;
  wire        s_aluclk;
  wire        s_dgpr0_n_out;
  wire        s_gnd;
  wire        s_gpr0m;
  wire        s_gpr10m;
  wire        s_gpr11m;
  wire        s_gpr12m;
  wire        s_gpr13m;
  wire        s_gpr14m;
  wire        s_gpr15m;
  wire        s_gpr1m;
  wire        s_gpr2m;
  wire        s_gpr3m;
  wire        s_gpr4m;
  wire        s_gpr5m;
  wire        s_gpr6m;
  wire        s_gpr7m;
  wire        s_gpr8m;
  wire        s_gpr9m;
  wire        s_gprli;

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_cd_15_0[15:0]    = CD_15_0;
  assign s_gprc_2_0[2:0]    = GPRC_2_0;
  assign s_fidbo_15_0[15:0] = FIDBO_15_0;
  assign s_aluclk           = ALUCLK;

  // P2b (docs/plan-fix-unconstrained-clocks.md): in FF mode the ALUCLK-
  // clocked registers capture on posedge sysclk gated by ALUCLK_EN
  // (aligned to the ALUCLK rise) instead of clocking on the routed net.
`ifdef FPGA_FF_MODE
  localparam ALUCLK_CE = 1;
`else
  localparam ALUCLK_CE = 0;
`endif

  assign s_gprli            = GPRLI;

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign DGPR0N             = s_dgpr0_n_out;
  assign GPR_15_0           = s_gpr_15_0_out[15:0];

  /*******************************************************************************
   ** Here all in-lined components are defined                                   **
   *******************************************************************************/

  // Ground
  assign s_gnd              = 1'b0;


  /*******************************************************************************
   ** Here all normal components are defined                                     **
   *******************************************************************************/
  D_FLIPFLOP_EN #(
      .USE_ENABLE(ALUCLK_CE)
  ) MEMORY_1 (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .clock(s_aluclk),
      .d(s_dgpr0_n_out),
      .preset(1'b0),
      .q(),
      .qBar(s_gpr_15_0_out[0]),
      .reset(1'b0),
      .tick(1'b1)
  );


  /*******************************************************************************
   ** Here all sub-circuits are defined                                          **
   *******************************************************************************/


  /*** 16 bit MUX41 ***/

  MUX41P GPR15M (
      .A (s_gprc_2_0[0]),
      .B (s_gprc_2_0[1]),
      .D0(s_fidbo_15_0[15]),
      .D1(s_cd_15_0[15]),
      .D2(s_gnd),
      .D3(s_gpr_15_0_out[14]),
      .Z (s_gpr15m)
  );

  MUX41P GPR14M (
      .A (s_gprc_2_0[0]),
      .B (s_gprc_2_0[1]),
      .D0(s_fidbo_15_0[14]),
      .D1(s_cd_15_0[14]),
      .D2(s_gpr_15_0_out[15]),
      .D3(s_gpr_15_0_out[13]),
      .Z (s_gpr14m)
  );

  MUX41P GPR13M (
      .A (s_gprc_2_0[0]),
      .B (s_gprc_2_0[1]),
      .D0(s_fidbo_15_0[13]),
      .D1(s_cd_15_0[13]),
      .D2(s_gpr_15_0_out[14]),
      .D3(s_gpr_15_0_out[12]),
      .Z (s_gpr13m)
  );

  MUX41P GPR12M (
      .A (s_gprc_2_0[0]),
      .B (s_gprc_2_0[1]),
      .D0(s_fidbo_15_0[12]),
      .D1(s_cd_15_0[12]),
      .D2(s_gpr_15_0_out[13]),
      .D3(s_gpr_15_0_out[11]),
      .Z (s_gpr12m)
  );

  MUX41P GPR11M (
      .A (s_gprc_2_0[0]),
      .B (s_gprc_2_0[1]),
      .D0(s_fidbo_15_0[11]),
      .D1(s_cd_15_0[11]),
      .D2(s_gpr_15_0_out[12]),
      .D3(s_gpr_15_0_out[10]),
      .Z (s_gpr11m)
  );

  MUX41P GPR10M (
      .A (s_gprc_2_0[0]),
      .B (s_gprc_2_0[1]),
      .D0(s_fidbo_15_0[10]),
      .D1(s_cd_15_0[10]),
      .D2(s_gpr_15_0_out[11]),
      .D3(s_gpr_15_0_out[9]),
      .Z (s_gpr10m)
  );

  MUX41P GPR9M (
      .A (s_gprc_2_0[0]),
      .B (s_gprc_2_0[1]),
      .D0(s_fidbo_15_0[9]),
      .D1(s_cd_15_0[9]),
      .D2(s_gpr_15_0_out[10]),
      .D3(s_gpr_15_0_out[8]),
      .Z (s_gpr9m)
  );

  MUX41P GPR8M (
      .A (s_gprc_2_0[0]),
      .B (s_gprc_2_0[1]),
      .D0(s_fidbo_15_0[8]),
      .D1(s_cd_15_0[8]),
      .D2(s_gpr_15_0_out[9]),
      .D3(s_gpr_15_0_out[7]),
      .Z (s_gpr8m)
  );

  MUX41P GPR7M (
      .A (s_gprc_2_0[0]),
      .B (s_gprc_2_0[1]),
      .D0(s_fidbo_15_0[7]),
      .D1(s_cd_15_0[7]),
      .D2(s_gpr_15_0_out[8]),
      .D3(s_gpr_15_0_out[6]),
      .Z (s_gpr7m)
  );

  MUX41P GPR6M (
      .A (s_gprc_2_0[0]),
      .B (s_gprc_2_0[1]),
      .D0(s_fidbo_15_0[6]),
      .D1(s_cd_15_0[6]),
      .D2(s_gpr_15_0_out[7]),
      .D3(s_gpr_15_0_out[5]),
      .Z (s_gpr6m)
  );

  MUX41P GPR5M (
      .A (s_gprc_2_0[0]),
      .B (s_gprc_2_0[1]),
      .D0(s_fidbo_15_0[5]),
      .D1(s_cd_15_0[5]),
      .D2(s_gpr_15_0_out[6]),
      .D3(s_gpr_15_0_out[4]),
      .Z (s_gpr5m)
  );

  MUX41P GPR4M (
      .A (s_gprc_2_0[0]),
      .B (s_gprc_2_0[1]),
      .D0(s_fidbo_15_0[4]),
      .D1(s_cd_15_0[4]),
      .D2(s_gpr_15_0_out[5]),
      .D3(s_gpr_15_0_out[3]),
      .Z (s_gpr4m)
  );

  MUX41P GPR3M (
      .A (s_gprc_2_0[0]),
      .B (s_gprc_2_0[1]),
      .D0(s_fidbo_15_0[3]),
      .D1(s_cd_15_0[3]),
      .D2(s_gpr_15_0_out[4]),
      .D3(s_gpr_15_0_out[2]),
      .Z (s_gpr3m)
  );

  MUX41P GPR2M (
      .A (s_gprc_2_0[0]),
      .B (s_gprc_2_0[1]),
      .D0(s_fidbo_15_0[2]),
      .D1(s_cd_15_0[2]),
      .D2(s_gpr_15_0_out[3]),
      .D3(s_gpr_15_0_out[1]),
      .Z (s_gpr2m)
  );

  MUX41P GPR1M (
      .A (s_gprc_2_0[0]),
      .B (s_gprc_2_0[1]),
      .D0(s_fidbo_15_0[1]),
      .D1(s_cd_15_0[1]),
      .D2(s_gpr_15_0_out[2]),
      .D3(s_gpr_15_0_out[0]),
      .Z (s_gpr1m)
  );

  MUX41P GPR0M (
      .A (s_gprc_2_0[0]),
      .B (s_gprc_2_0[1]),
      .D0(s_fidbo_15_0[0]),
      .D1(s_cd_15_0[0]),
      .D2(s_gpr_15_0_out[1]),
      .D3(s_gprli),
      .Z (s_gpr0m)
  );

  /*** FF for DGPR0_n ***/

// Need to add a delayed latch here, as there is in the SCAN_FF's to not loose bit 0
// TODO: Convert to FF clocked with FPGA main clock

  reg s_gpr0m_delayed; 
  always@(s_gpr0m)
  begin
    s_gpr0m_delayed <= s_gpr0m;
  end
  MUX21LP GPR0M21 (
      .A (s_gpr0m_delayed),
      .B (s_gpr_15_0_out[0]),
      .S (s_gprc_2_0[2]),
      .ZN(s_dgpr0_n_out)
  );

  /*** 16 bit SCAN_FF ***/

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) GPR15FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_gpr15m),
      .Q  (s_gpr_15_0_out[15]),
      .QN (),
      .TE (s_gprc_2_0[2]),
      .TI (s_gpr_15_0_out[15])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) GPR14FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_gpr14m),
      .Q  (s_gpr_15_0_out[14]),
      .QN (),
      .TE (s_gprc_2_0[2]),
      .TI (s_gpr_15_0_out[14])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) GPR13FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_gpr13m),
      .Q  (s_gpr_15_0_out[13]),
      .QN (),
      .TE (s_gprc_2_0[2]),
      .TI (s_gpr_15_0_out[13])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) GPR12FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_gpr12m),
      .Q  (s_gpr_15_0_out[12]),
      .QN (),
      .TE (s_gprc_2_0[2]),
      .TI (s_gpr_15_0_out[12])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) GPR11FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_gpr11m),
      .Q  (s_gpr_15_0_out[11]),
      .QN (),
      .TE (s_gprc_2_0[2]),
      .TI (s_gpr_15_0_out[11])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) GPR10FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_gpr10m),
      .Q  (s_gpr_15_0_out[10]),
      .QN (),
      .TE (s_gprc_2_0[2]),
      .TI (s_gpr_15_0_out[10])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) GPR9FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_gpr9m),
      .Q  (s_gpr_15_0_out[9]),
      .QN (),
      .TE (s_gprc_2_0[2]),
      .TI (s_gpr_15_0_out[9])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) GPR8FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_gpr8m),
      .Q  (s_gpr_15_0_out[8]),
      .QN (),
      .TE (s_gprc_2_0[2]),
      .TI (s_gpr_15_0_out[8])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) GPR7FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_gpr7m),
      .Q  (s_gpr_15_0_out[7]),
      .QN (),
      .TE (s_gprc_2_0[2]),
      .TI (s_gpr_15_0_out[7])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) GPR6FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_gpr6m),
      .Q  (s_gpr_15_0_out[6]),
      .QN (),
      .TE (s_gprc_2_0[2]),
      .TI (s_gpr_15_0_out[6])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) GPR5FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_gpr5m),
      .Q  (s_gpr_15_0_out[5]),
      .QN (),
      .TE (s_gprc_2_0[2]),
      .TI (s_gpr_15_0_out[5])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) GPR4FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_gpr4m),
      .Q  (s_gpr_15_0_out[4]),
      .QN (),
      .TE (s_gprc_2_0[2]),
      .TI (s_gpr_15_0_out[4])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) GPR3FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_gpr3m),
      .Q  (s_gpr_15_0_out[3]),
      .QN (),
      .TE (s_gprc_2_0[2]),
      .TI (s_gpr_15_0_out[3])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) GPR2FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_gpr2m),
      .Q  (s_gpr_15_0_out[2]),
      .QN (),
      .TE (s_gprc_2_0[2]),
      .TI (s_gpr_15_0_out[2])
  );

  SCAN_FF_EN #(.USE_ENABLE(ALUCLK_CE)) GPR1FF (
      .sysclk(sysclk),
      .EN(ALUCLK_EN),
      .CLK(s_aluclk),
      .D  (s_gpr1m),
      .Q  (s_gpr_15_0_out[1]),
      .QN (),
      .TE (s_gprc_2_0[2]),
      .TI (s_gpr_15_0_out[1])
  );

endmodule
