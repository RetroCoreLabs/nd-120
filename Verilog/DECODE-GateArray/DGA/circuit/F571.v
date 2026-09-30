/**************************************************************************
** ND120 DGA (Decode Gate Array)                                         **
** DECODE/DGA                                                            **
**                                                                       **
** NEC F571 - 2 TO 1 MULTIPLEXER                                         **
**                                                                       **
** Last reviewed: 20-MAY-2024                                            **
** Ronny Hansen                                                          **
***************************************************************************/

module F571 (
    input A,
    input D0,
    input D1,
    input ENB_N,  //! tied to 0 (in DECODE_DGA_COMM, DECODE_DGA_POW)

    output Y
);

  wire s_enb_n;
  wire s_A;
  wire s_enb;
  wire s_d0;
  wire s_d1;
  wire s_y;


  // Assign inputs
  assign s_enb_n = ENB_N;
  assign s_A     = A;
  assign s_d0    = D0;
  assign s_d1    = D1;

  // Assign outputs
  assign Y       = s_y;

  // Implementation
  assign s_enb   = ~s_enb_n;

  Multiplexer_2_w_enable PLEXERS_1 (
      .enable(s_enb),
      .muxIn_0(s_d0),
      .muxIn_1(s_d1),
      .muxOut(s_y),
      .sel(s_A)
  );


endmodule
