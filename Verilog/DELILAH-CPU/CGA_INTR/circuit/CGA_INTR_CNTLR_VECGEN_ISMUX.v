/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/INTR/CNTLR/VECGEN/ISMUX                                          **
** ISMUX                                                                 **
**                                                                       **
** Page 85                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 10-NOV-2024                                            **
** Ronny Hansen                                                          **
***************************************************************************/

module CGA_INTR_CNTLR_VECGEN_ISMUX (
    input [2:0] FIDBO_2_0,  //! FIDB (from CGA_INTR.FIDBO_15_0[2:0])
    input       HIGSN,
    input [2:0] HISTAT_2_0,
    input       LOGSN,
    input [2:0] LOSTAT_2_0,
    input       OESN,

    output [2:0] HISIN_2_0,
    output [2:0] LOSIN_2_0
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [2:0] s_lostat_2_0;
  wire [2:0] s_losin_2_0_out;
  wire [2:0] s_fidbo_2_0;
  wire [2:0] s_histat_2_0;
  wire [2:0] s_hisin_2_0_out;
  wire       s_gates10_out;
  wire       s_gates11_out;
  wire       s_gates12_out;
  wire       s_gates13_out;
  wire       s_gates14_out;
  wire       s_gates15_out;
  wire       s_gates16_out;
  wire       s_gates17_out;
  wire       s_gates18_out;
  wire       s_gates19_out;
  wire       s_gates20_out;
  wire       s_gates7_n_out;
  wire       s_gates7_out;
  wire       s_gates8_n_out;
  wire       s_gates8_out;
  wire       s_gates9_out;
  wire       s_higs_n;
  wire       s_higs; 
  wire       s_logs_n;
  wire       s_oes_n;
  wire       s_oes;

  /*******************************************************************************
   ** The module functionality is described here                                 **
   *******************************************************************************/

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_lostat_2_0[2:0] = LOSTAT_2_0;
  assign s_fidbo_2_0[2:0]  = FIDBO_2_0;
  assign s_histat_2_0[2:0] = HISTAT_2_0;
  assign s_logs_n          = LOGSN;
  assign s_oes_n           = OESN;
  assign s_higs_n          = HIGSN;

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign HISIN_2_0         = s_hisin_2_0_out[2:0];
  assign LOSIN_2_0         = s_losin_2_0_out[2:0];

  /*******************************************************************************
   ** Here all in-lined components are defined                                   **
   *******************************************************************************/

  // NOT Gate
  assign s_higs            = ~s_higs_n;
  assign s_oes             = ~s_oes_n;
  assign s_gates8_n_out    = ~s_gates8_out;
  assign s_gates7_n_out    = ~s_gates7_out;

  /*******************************************************************************
   ** Here all normal components are defined                                     **
   *******************************************************************************/
  OR_GATE #(
      .BubblesMask(2'b11)
  ) GATES_1 (
      .input1(s_gates9_out),
      .input2(s_gates10_out),
      .result(s_losin_2_0_out[2])
  );

  OR_GATE #(
      .BubblesMask(2'b11)
  ) GATES_2 (
      .input1(s_gates11_out),
      .input2(s_gates12_out),
      .result(s_losin_2_0_out[1])
  );

  OR_GATE #(
      .BubblesMask(2'b11)
  ) GATES_3 (
      .input1(s_gates13_out),
      .input2(s_gates14_out),
      .result(s_losin_2_0_out[0])
  );

  OR_GATE #(
      .BubblesMask(2'b11)
  ) GATES_4 (
      .input1(s_gates15_out),
      .input2(s_gates16_out),
      .result(s_hisin_2_0_out[2])
  );

  OR_GATE #(
      .BubblesMask(2'b11)
  ) GATES_5 (
      .input1(s_gates17_out),
      .input2(s_gates18_out),
      .result(s_hisin_2_0_out[1])
  );

  OR_GATE #(
      .BubblesMask(2'b11)
  ) GATES_6 (
      .input1(s_gates19_out),
      .input2(s_gates20_out),
      .result(s_hisin_2_0_out[0])
  );

  AND_GATE #(
      .BubblesMask(2'b11)
  ) GATES_7 (
      .input1(s_logs_n),
      .input2(s_oes_n),
      .result(s_gates7_out)
  );

  AND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_8 (
      .input1(s_higs),
      .input2(s_oes),
      .result(s_gates8_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_9 (
      .input1(s_lostat_2_0[2]),
      .input2(s_gates7_out),
      .result(s_gates9_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_10 (
      .input1(s_fidbo_2_0[2]),
      .input2(s_gates7_n_out),
      .result(s_gates10_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_11 (
      .input1(s_lostat_2_0[1]),
      .input2(s_gates7_out),
      .result(s_gates11_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_12 (
      .input1(s_fidbo_2_0[1]),
      .input2(s_gates7_n_out),
      .result(s_gates12_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_13 (
      .input1(s_lostat_2_0[0]),
      .input2(s_gates7_out),
      .result(s_gates13_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_14 (
      .input1(s_fidbo_2_0[0]),
      .input2(s_gates7_n_out),
      .result(s_gates14_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_15 (
      .input1(s_histat_2_0[2]),
      .input2(s_gates8_out),
      .result(s_gates15_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_16 (
      .input1(s_fidbo_2_0[2]),
      .input2(s_gates8_n_out),
      .result(s_gates16_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_17 (
      .input1(s_histat_2_0[1]),
      .input2(s_gates8_out),
      .result(s_gates17_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_18 (
      .input1(s_fidbo_2_0[1]),
      .input2(s_gates8_n_out),
      .result(s_gates18_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_19 (
      .input1(s_histat_2_0[0]),
      .input2(s_gates8_out),
      .result(s_gates19_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_20 (
      .input1(s_fidbo_2_0[0]),
      .input2(s_gates8_n_out),
      .result(s_gates20_out)
  );


endmodule
