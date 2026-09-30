/**************************************************************************
** ND120 CPU, MM&M                                                       **
** BIF/DPATH/PPNLBD                                                      **
** BIF PPN TO LBD                                                        **
** SHEET 14  of 50                                                       **
**                                                                       **
** Last reviewed: 09-NOV-2024                                            **
** Ronny Hansen                                                          **
***************************************************************************/

module BIF_DPATH_PPNLBD_14 (
    input sysclk,  //! System clock (used only for the FF-mode strobe edge-capture)
    input [13:0] PPN_23_10,  //! Physical Page Number (from BIF_DPATH_9.PPN_23_10)
    input [ 9:0] CA_9_0,  //! Control Store Address (from BIF_DPATH_9.CA_9_0)

    input EADR_n,  //! Enable External Address (from BIF_DPATH_9.EADDR_n)
    input ECREQ,   //! Enable CPU Request (from BIF_DPATH_9.ECREQ)

    output [23:0] LBD_23_0_OUT
);

  reg [23:0] Q_reg;  // Internal register

  // P3 (docs/plan-fix-unconstrained-clocks.md): ECREQ is a CPU-request
  // strobe, not a clock. In FF mode capture on a sysclk-detected ECREQ
  // rise instead of clocking on the routed net.
`ifdef FPGA_FF_MODE
  reg ecreq_d = 1'b0;
  always @(posedge sysclk) begin
    ecreq_d <= ECREQ;
    if (ECREQ && !ecreq_d) Q_reg <= {PPN_23_10[13:0], CA_9_0[9:0]};
  end
`else
  // Latch data on rising edge of CK
  always @(posedge ECREQ) begin
    Q_reg <= {PPN_23_10[13:0], CA_9_0[9:0]};
  end
`endif

  assign LBD_23_0_OUT = EADR_n ? 24'b0 : Q_reg;
endmodule
