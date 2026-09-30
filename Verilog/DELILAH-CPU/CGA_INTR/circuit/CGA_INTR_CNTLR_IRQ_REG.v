/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/INTR/CNTLR/IRQ/REG                                               **
** INTERRUPT CONTROLLER REGISTER                                         **
**                                                                       **
**                                                                       **
** Interrupt latches                                                     **
** Page 78                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** 15-JUL-2026: all 16 request bits swapped from RQBIT (async            **
** cross-coupled SR latch) to the loop-free RQBIT_V2 - equivalence       **
** proved in ../sim/CGA_INTR_CNTLR_IRQ_REG_RQBIT_V2_tb.v.                **
**                                                                       **
** Last reviewed: 15-JUL-2026                                            **
** Ronny Hansen                                                          **
***************************************************************************/

module CGA_INTR_CNTLR_IRQ_REG (
    input        sysclk,   //! FPGA system clock (P2: MCLK_EN capture)
    input        MCLK_EN,  //! MCLK clock-enable pulse (FPGA_FF_MODE, else 0)

    input [15:0] CLRQ_15_0,
    input        CPN,
    input [15:0] IRQ_15_0_N,
    input        MCLK,     //! Master Clock (from CGA_INTR.MCLK)

    output [15:0] LREQ_15_0

);
  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [15:0] s_clrq_15_0;
  wire [15:0] s_irq_15_0_n;
  wire [15:0] s_lreq_15_0_out;
  wire        s_cp_n;
  wire        s_mclk;

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_clrq_15_0[15:0]  = CLRQ_15_0;
  assign s_irq_15_0_n[15:0] = IRQ_15_0_N;
  assign s_mclk             = MCLK;
  assign s_cp_n             = CPN;

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign LREQ_15_0          = s_lreq_15_0_out[15:0];

  /*******************************************************************************
   ** Here all sub-circuits are defined                                          **
   *******************************************************************************/

  CGA_INTR_CNTLR_IRQ_REG_RQBIT_V2 RQBIT_0 (
      .CLR(s_clrq_15_0[0]),
      .sysclk(sysclk),
      .MCLK_EN(MCLK_EN),
      .CP (s_mclk),
      .CPN(s_cp_n),
      .INR(s_lreq_15_0_out[0]),
      .PN (s_irq_15_0_n[0])
  );

  CGA_INTR_CNTLR_IRQ_REG_RQBIT_V2 RQBIT_1 (
      .CLR(s_clrq_15_0[1]),
      .sysclk(sysclk),
      .MCLK_EN(MCLK_EN),
      .CP (s_mclk),
      .CPN(s_cp_n),
      .INR(s_lreq_15_0_out[1]),
      .PN (s_irq_15_0_n[1])
  );

  CGA_INTR_CNTLR_IRQ_REG_RQBIT_V2 RQBIT_2 (
      .CLR(s_clrq_15_0[2]),
      .sysclk(sysclk),
      .MCLK_EN(MCLK_EN),
      .CP (s_mclk),
      .CPN(s_cp_n),
      .INR(s_lreq_15_0_out[2]),
      .PN (s_irq_15_0_n[2])
  );

  CGA_INTR_CNTLR_IRQ_REG_RQBIT_V2 RQBIT_3 (
      .CLR(s_clrq_15_0[3]),
      .sysclk(sysclk),
      .MCLK_EN(MCLK_EN),
      .CP (s_mclk),
      .CPN(s_cp_n),
      .INR(s_lreq_15_0_out[3]),
      .PN (s_irq_15_0_n[3])
  );

  CGA_INTR_CNTLR_IRQ_REG_RQBIT_V2 RQBIT_4 (
      .CLR(s_clrq_15_0[4]),
      .sysclk(sysclk),
      .MCLK_EN(MCLK_EN),
      .CP (s_mclk),
      .CPN(s_cp_n),
      .INR(s_lreq_15_0_out[4]),
      .PN (s_irq_15_0_n[4])
  );

  CGA_INTR_CNTLR_IRQ_REG_RQBIT_V2 RQBIT_5 (
      .CLR(s_clrq_15_0[5]),
      .sysclk(sysclk),
      .MCLK_EN(MCLK_EN),
      .CP (s_mclk),
      .CPN(s_cp_n),
      .INR(s_lreq_15_0_out[5]),
      .PN (s_irq_15_0_n[5])
  );

  CGA_INTR_CNTLR_IRQ_REG_RQBIT_V2 RQBIT_6 (
      .CLR(s_clrq_15_0[6]),
      .sysclk(sysclk),
      .MCLK_EN(MCLK_EN),
      .CP (s_mclk),
      .CPN(s_cp_n),
      .INR(s_lreq_15_0_out[6]),
      .PN (s_irq_15_0_n[6])
  );

  CGA_INTR_CNTLR_IRQ_REG_RQBIT_V2 RQBIT_7 (
      .CLR(s_clrq_15_0[7]),
      .sysclk(sysclk),
      .MCLK_EN(MCLK_EN),
      .CP (s_mclk),
      .CPN(s_cp_n),
      .INR(s_lreq_15_0_out[7]),
      .PN (s_irq_15_0_n[7])
  );

  CGA_INTR_CNTLR_IRQ_REG_RQBIT_V2 RQBIT_8 (
      .CLR(s_clrq_15_0[8]),
      .sysclk(sysclk),
      .MCLK_EN(MCLK_EN),
      .CP (s_mclk),
      .CPN(s_cp_n),
      .INR(s_lreq_15_0_out[8]),
      .PN (s_irq_15_0_n[8])
  );

  CGA_INTR_CNTLR_IRQ_REG_RQBIT_V2 RQBIT_9 (
      .CLR(s_clrq_15_0[9]),
      .sysclk(sysclk),
      .MCLK_EN(MCLK_EN),
      .CP (s_mclk),
      .CPN(s_cp_n),
      .INR(s_lreq_15_0_out[9]),
      .PN (s_irq_15_0_n[9])
  );

  CGA_INTR_CNTLR_IRQ_REG_RQBIT_V2 RQBIT_10 (
      .CLR(s_clrq_15_0[10]),
      .sysclk(sysclk),
      .MCLK_EN(MCLK_EN),
      .CP (s_mclk),
      .CPN(s_cp_n),
      .INR(s_lreq_15_0_out[10]),
      .PN (s_irq_15_0_n[10])
  );

  CGA_INTR_CNTLR_IRQ_REG_RQBIT_V2 RQBIT_11 (
      .CLR(s_clrq_15_0[11]),
      .sysclk(sysclk),
      .MCLK_EN(MCLK_EN),
      .CP (s_mclk),
      .CPN(s_cp_n),
      .INR(s_lreq_15_0_out[11]),
      .PN (s_irq_15_0_n[11])
  );

  CGA_INTR_CNTLR_IRQ_REG_RQBIT_V2 RQBIT_12 (
      .CLR(s_clrq_15_0[12]),
      .sysclk(sysclk),
      .MCLK_EN(MCLK_EN),
      .CP (s_mclk),
      .CPN(s_cp_n),
      .INR(s_lreq_15_0_out[12]),
      .PN (s_irq_15_0_n[12])
  );

  CGA_INTR_CNTLR_IRQ_REG_RQBIT_V2 RQBIT_13 (
      .CLR(s_clrq_15_0[13]),
      .sysclk(sysclk),
      .MCLK_EN(MCLK_EN),
      .CP (s_mclk),
      .CPN(s_cp_n),
      .INR(s_lreq_15_0_out[13]),
      .PN (s_irq_15_0_n[13])
  );

  CGA_INTR_CNTLR_IRQ_REG_RQBIT_V2 RQBIT_14 (
      .CLR(s_clrq_15_0[14]),
      .sysclk(sysclk),
      .MCLK_EN(MCLK_EN),
      .CP (s_mclk),
      .CPN(s_cp_n),
      .INR(s_lreq_15_0_out[14]),
      .PN (s_irq_15_0_n[14])
  );

  CGA_INTR_CNTLR_IRQ_REG_RQBIT_V2 RQBIT_15 (
      .CLR(s_clrq_15_0[15]),
      .sysclk(sysclk),
      .MCLK_EN(MCLK_EN),
      .CP (s_mclk),
      .CPN(s_cp_n),
      .INR(s_lreq_15_0_out[15]),
      .PN (s_irq_15_0_n[15])
  );


endmodule
