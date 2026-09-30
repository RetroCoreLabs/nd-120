/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/INTR/CNTLR                                                       **
** INTERRUPT CONTROLLER                                                  **
**                                                                       **
** Page 77                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 10-NOV-2024                                            **
** Ronny Hansen                                                          **
***************************************************************************/
module CGA_INTR_CNTLR (
    input        sysclk,   //! FPGA system clock (P2: MCLK_EN capture)
    input        MCLK_EN,  //! MCLK clock-enable pulse (FPGA_FF_MODE, else 0)

    input        EPIC,     //! Enable PIC (Programmable Interrupt Controller) signal (from CGA_INTR.EPIC)
    input [15:0] FIDBO_15_0,  //! FIDB , 16-bit (from CGA_INTR.FIDBO_15_0)
    input [15:0] IREQ_15_0_N,
    input [ 3:0] LAA_3_0,  //! Latched Address A, 4-bit (from CGA_INTR.LAA_3_0)
    input        MCLK,     //! Master Clock (from CGA_INTR.MCLK)

    output        EPICMASKN,  //! EPIC Mask, active low (to CGA_INTR.EPICMASKN)
    output        HIGSN,   //! High Speed signal, active low (to CGA_INTR.HIGSN)
    output        IRQN,
    output        LOGSN,   //! Logical Segment Number, active low (to CGA_INTR.LOGSN)
    output        PD,      //! Power Down signal (to CGA_INTR.PD)
    output [15:0] PICMASK_15_0,  //! PIC Mask, 16-bit (to CGA_INTR.PICMASK_15_0)
    output [ 2:0] PICS_2_0,  //! PIC Select, 3-bit (to CGA_INTR.PICS_2_0)
    output [ 2:0] PICV_2_0,  //! PIC Vector, 3-bit (to CGA_INTR.PICV_2_0)
    output [15:0] XMIREQ_15_0_N   //! DEBUG: masked interrupt-request vector (active low) that drives the grant
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [ 2:0] s_fidbo_2_0;
  wire [ 2:0] s_hivec_2_0;
  wire [ 2:0] s_hx_2_0_n;
  wire [ 2:0] s_hx_2_0;
  wire [ 2:0] s_lx_2_0_n;
  wire [ 2:0] s_lx_2_0;
  wire [ 2:0] s_lovec_2_0;
  wire [ 2:0] s_pics_2_0_out;
  wire [ 2:0] s_picv_2_0_out;
  wire [ 3:0] s_laa_3_0;
  wire [15:0] s_clrq_15_0;
  wire [15:0] s_din_15_0;
  wire [15:0] s_fidbo_15_0;
  wire [15:0] s_ireq_15_0_n;
  wire [15:0] s_mireq_15_0;
  wire [15:0] s_picmask_15_0_out;
  wire        s_a;
  wire        s_b;
  wire        s_c;
  wire        s_d;
  wire        s_e;
  wire        s_epic;
  wire        s_epicmask_n_out;
  wire        s_g;
  wire        s_h;
  wire        s_hidet;
  wire        s_hif;
  wire        s_highs_n_out;
  wire        s_hik;
  wire        s_hipassall;
  wire        s_hivges;
  wire        s_irq_n_out;
  wire        s_j;
  wire        s_l;
  wire        s_lodet;
  wire        s_lof;
  wire        s_logs_n_out;
  wire        s_lok;
  wire        s_lopasall;
  wire        s_lovges;
  wire        s_m;
  wire        s_mclk_n;
  wire        s_mclk;
  wire        s_n;
  wire        s_oem;
  wire        s_oes_n;
  wire        s_pd_out;
  wire        s_s;


  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_laa_3_0[3:0]      = LAA_3_0;
  assign s_ireq_15_0_n[15:0] = IREQ_15_0_N;
  assign s_fidbo_15_0[15:0]  = FIDBO_15_0;
  assign s_mclk              = MCLK;
  assign s_epic              = EPIC;

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign EPICMASKN           = s_epicmask_n_out;
  assign HIGSN               = s_highs_n_out;
  assign IRQN                = s_irq_n_out;
  assign LOGSN               = s_logs_n_out;
  assign PD                  = s_pd_out;
  assign PICMASK_15_0        = s_picmask_15_0_out[15:0];
  assign XMIREQ_15_0_N       = s_mireq_15_0[15:0];
  assign PICS_2_0            = s_pics_2_0_out[2:0];
  assign PICV_2_0            = s_picv_2_0_out[2:0];

  /*******************************************************************************
   ** Here all wiring is defined                                                 **
   *******************************************************************************/
  // FIDBO -> status-write value (feeds VECGEN.FIDBO_2_0 -> HISIN/LOSIN).
  assign s_fidbo_2_0[0]      = s_fidbo_15_0[0];
  assign s_fidbo_2_0[1]      = s_fidbo_15_0[1];
  assign s_fidbo_2_0[2]      = s_fidbo_15_0[2];

  /*******************************************************************************
   ** Here all in-lined components are defined                                   **
   *******************************************************************************/

  // NOT Gate
  assign s_mclk_n            = ~s_mclk;

  /*******************************************************************************
   ** Here all normal components are defined                                     **
   *******************************************************************************/
  Multiplexer_bus_2 #(
      .nrOfBits(16)
  ) PLEXERS_1 (
      .muxIn_0(s_fidbo_15_0[15:0]),
      .muxIn_1(s_picmask_15_0_out[15:0]),
      .muxOut(s_din_15_0[15:0]),
      .sel(s_oem)
  );


  /*******************************************************************************
   ** Here all sub-circuits are defined                                          **
   *******************************************************************************/

  CGA_INTR_CNTLR_VECGEN VECGEN (
      .sysclk(sysclk),
      .MCLK_EN(MCLK_EN),
      .FIDBO3(s_fidbo_15_0[3]),
      .FIDBO4(s_fidbo_15_0[4]),
      .FIDBO_2_0(s_fidbo_2_0[2:0]),
      .G(s_g),
      .HIDET(s_hidet),
      .HIF(s_hif),
      .HIGSN(s_highs_n_out),
      .HIVEC_2_0(s_hivec_2_0[2:0]),
      .HIVGES(s_hivges),
      .HX_2_0(s_hx_2_0[2:0]),
      .HX_2_0_N(s_hx_2_0_n[2:0]),
      .LODET(s_lodet),
      .LOF(s_lof),
      .LOGSN(s_logs_n_out),
      .LOVEC_2_0(s_lovec_2_0[2:0]),
      .LOVGES(s_lovges),
      .LX_2_0(s_lx_2_0[2:0]),
      .LX_2_0_N(s_lx_2_0_n[2:0]),
      .MCLK(s_mclk),
      .MIREQ_15_0_N(s_mireq_15_0[15:0]),
      .N(s_n),
      .OESN(s_oes_n),
      .PICS_2_0(s_pics_2_0_out[2:0])
  );

  CGA_INTR_CNTLR_CLR CLR_CLEAR_CONTROL (
      .CLRQ_15_0(s_clrq_15_0[15:0]),
      .DIN_15_8(s_din_15_0[15:8]),
      .DIN_7_0(s_din_15_0[7:0]),
      .HIK(s_hik),
      .HX_2_0(s_hx_2_0[2:0]),
      .HX_2_0_N(s_hx_2_0_n[2:0]),
      .J(s_j),
      .LOK(s_lok),
      .LX_2_0(s_lx_2_0[2:0]),
      .LX_2_0_N(s_lx_2_0_n[2:0])
  );

  CGA_INTR_CNTLR_IRGEL IRGEL (
      .sysclk(sysclk),
      .MCLK_EN(MCLK_EN),
      .D(s_d),
      .E(s_e),
      .FIDB03(s_fidbo_15_0[3]),
      .FIDB04(s_fidbo_15_0[4]),
      .H(s_h),
      .HIDET(s_hidet),
      .HIGSN(s_highs_n_out),
      .HIPASSALL(s_hipassall),
      .HIVEC_2_0(s_hivec_2_0[2:0]),
      .HIVGES(s_hivges),
      .IRQN(s_irq_n_out),
      .L(s_l),
      .LODET(s_lodet),
      .LOGSN(s_logs_n_out),
      .LOPASSALL(s_lopasall),
      .LOVEC_2_0(s_lovec_2_0[2:0]),
      .LOVGES(s_lovges),
      .M(s_m),
      .MCLK(s_mclk),
      .N(s_n),
      .PD(s_pd_out),
      .PICV_2_0(s_picv_2_0_out[2:0]),
      .S(s_s)
  );

  CGA_INTR_CNTLR_MDCD MDCD (
      .sysclk(sysclk),
      .MCLK_EN(MCLK_EN),
      .A(s_a),
      .B(s_b),
      .C(s_c),
      .D(s_d),
      .E(s_e),
      .EPIC(s_epic),
      .EPICMASKN(s_epicmask_n_out),
      .G(s_g),
      .H(s_h),
      .HIF(s_hif),
      .HIK(s_hik),
      .HIPASSALL(s_hipassall),
      .J(s_j),
      .L(s_l),
      .LAA_3_0(s_laa_3_0[3:0]),
      .LOF(s_lof),
      .LOK(s_lok),
      .LOPASSALL(s_lopasall),
      .M(s_m),
      .MCLK(s_mclk),
      .N(s_n),
      .OEM(s_oem),
      .OESN(s_oes_n),
      .S(s_s)
  );

  CGA_INTR_CNTLR_IRQ IRQ (
      .sysclk(sysclk),
      .MCLK_EN(MCLK_EN),
      .A(s_a),
      .B(s_b),
      .C(s_c),
      .CLRQ_15_0(s_clrq_15_0[15:0]),
      .CPN(s_mclk_n),
      .DIN_15_0(s_din_15_0[15:0]),
      .IREQ_15_0_N(s_ireq_15_0_n[15:0]),
      .MCLK(s_mclk),
      .MIREQ_15_0_N(s_mireq_15_0[15:0]),
      .PICMASK_15_0(s_picmask_15_0_out[15:0])
  );

endmodule
