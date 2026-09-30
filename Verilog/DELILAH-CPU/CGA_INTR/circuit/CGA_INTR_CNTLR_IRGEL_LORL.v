

/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/INTR/CNTLR/IRGEL/LORL                                            **
** LO RL                                                                 **
**                                                                       **
** Page 92                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 10-NOV-2024                                            **
** Ronny Hansen                                                          **
***************************************************************************/


module CGA_INTR_CNTLR_IRGEL_LORL (
    input       sysclk,   //! FPGA system clock (P2: MCLK_EN capture)
    input       MCLK_EN,  //! MCLK clock-enable pulse (FPGA_FF_MODE, else 0)

    input       D,
    input       E,
    input       LODET,
    input [2:0] LOVEC_2_0,  //! Lo vector (same net as CGA_INTR_CNTLR_IRGEL_VMUX.LOVEC_2_0)
    input       LOVGES,
    input       MCLK,     //! Master Clock (from CGA_INTR.MCLK)
    input       RDN,
    input       S,

    output LIENABN,
    output LIRQ,
    output LOGAS,
    output LOGASN,
    output LOPASSALL,
    output LVE            //! Lo vector Enable (to CGA_INTR_CNTLR_IRGEL_VMUX.LVE)
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [2:0] s_lovec_2_0;
  wire       s_d;
  wire       s_e;
  wire       s_int_req_enable_q_n;
  wire       s_int_req_enable_q /* synthesis syn_keep=1 */;  // GAO probe net - see fpga/tang-nano-20k/GAO-HOWTO.md
  wire       s_lienab_n_out;
  wire       s_lirq_out;
  wire       s_lodet;
  wire       s_logas_n_out;
  wire       s_logas_out;
  wire       s_lopassall_n;
  wire       s_lopassall_out;
  wire       s_lovges;
  wire       s_lve_out;
  wire       s_mclk;
  wire       s_rd_n;
  wire       s_s;

  /*******************************************************************************
   ** The module functionality is described here                                 **
   *******************************************************************************/

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_lovec_2_0[2:0] = LOVEC_2_0;
  assign s_d              = D;
  assign s_rd_n           = RDN;
  assign s_e              = E;
  assign s_mclk           = MCLK;
  assign s_lodet          = LODET;
  assign s_s              = S;
  assign s_lovges         = LOVGES;

  // P2 (docs/plan-fix-unconstrained-clocks.md): in FF mode the MCLK-
  // clocked registers capture on posedge sysclk gated by MCLK_EN
  // (aligned to the MCLK rise) instead of clocking on the routed net.
`ifdef FPGA_FF_MODE
  localparam MCLK_CE = 1;
`else
  localparam MCLK_CE = 0;
`endif

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign LIENABN          = s_lienab_n_out;
  assign LIRQ             = s_lirq_out;
  assign LOGAS            = s_logas_out;
  assign LOGASN           = s_logas_n_out;
  assign LOPASSALL        = s_lopassall_out;
  assign LVE              = s_lve_out;

  /*******************************************************************************
   ** Here all in-lined components are defined                                   **
   *******************************************************************************/

  // NOT Gate
  assign s_logas_out      = ~s_logas_n_out;

  // NOT Gate
  assign s_lienab_n_out   = ~s_rd_n;

  // NOT Gate
  assign s_lopassall_out  = ~s_lopassall_n;

  /*******************************************************************************
   ** Here all normal components are defined                                     **
   *******************************************************************************/
  NAND_GATE_4_INPUTS #(
      .BubblesMask(4'h0)
  ) GATES_1 (
      .input1(s_lve_out),
      .input2(s_lovec_2_0[2]),
      .input3(s_lovec_2_0[1]),
      .input4(s_lovec_2_0[0]),
      .result(s_logas_n_out)
  );

  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) GATES_2 (
      .input1(s_rd_n),
      .input2(s_lodet),
      .input3(s_lovges),
      .result(s_lopassall_n)
  );

  AND_GATE #(
      .BubblesMask(2'b11)
  ) GATES_3 (
      .input1(s_lopassall_n),
      .input2(s_int_req_enable_q_n),
      .result(s_lirq_out)
  );

  // Vector-claim must be gated by the interrupt-request-enable FF (Am2914
  // ground truth: a claim after DISIN must not fire even with requests
  // pending and the mask open - the post-MCL mask is all-enabled by design).
  AND_GATE_3_INPUTS #(
      .BubblesMask(3'b111)
  ) GATES_4 (
      .input1(s_lopassall_n),
      .input2(s_s),
      .input3(s_int_req_enable_q_n),
      .result(s_lve_out)
  );


  /*******************************************************************************
   ** Here all sub-circuits are defined                                          **
   *******************************************************************************/

  // MCLK domain (CGA_INTR.MCLK, rising edge)
  SCAN_FF_EN #(.USE_ENABLE(MCLK_CE)) INT_REQ_ENABLE_FF (
      .sysclk(sysclk),
      .EN(MCLK_EN),
      .CLK(s_mclk),
      .D  (s_e),
      .Q  (s_int_req_enable_q),
      .QN (s_int_req_enable_q_n),
      .TE (s_d),
      .TI (s_int_req_enable_q)
  );

endmodule
