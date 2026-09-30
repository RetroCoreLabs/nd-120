/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/INTR/IRSRC                                                       **
** Interrupt Source                                                      **
**                                                                       **
** Page 76                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 10-NOV-2024                                            **
** Ronny Hansen                                                          **
***************************************************************************/

module CGA_INTR_IRSRC (
    input        BINT10N,  //! Bus Interrupt 10, active low (from CGA_INTR.BINT10N)
    input        BINT11N,  //! Bus Interrupt 11, active low (from CGA_INTR.BINT11N)
    input        BINT12N,  //! Bus Interrupt 12, active low (from CGA_INTR.BINT12N)
    input        BINT13N,  //! Bus Interrupt 13, active low (from CGA_INTR.BINT13N)
    input        BINT15N,  //! Bus Interrupt 15, active low (from CGA_INTR.BINT15N)
    input        EMPIDN,  //! Interrupt Disable (EPIC.LDMPIE->set mask reg:inh all ints) (from CGA_INTR.EMPIDN)
    input [15:0] FIDBO_15_0,  //! FIDB , 16-bit (from CGA_INTR.FIDBO_15_0)
    input        IOXERRN,  //! IO Exception Error, active low (from CGA_INTR.IOXERRN)
    input        MORN,  //! MOR signal, active low (Memory Error) (from CGA_INTR.MORN)
    input        PARERRN,  //! Parity Error, active low (from CGA_INTR.PARERRN)
    input        POWFAILN,  //! Power Failure, active low (from CGA_INTR.POWFAILN)
    input        Z,  //! Error flag from ALU (from CGA_INTR.Z)

    output [15:0] IREQ_15_0_N
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [15:0] s_ireq_15_0_n_out;
  wire [15:0] s_fidbo_15_0;
  wire        s_bint10_n;
  wire        s_bint11_n;
  wire        s_bint12_n;
  wire        s_bint13_n;
  wire        s_bint15_n;
  wire        s_empid_n;
  wire        s_empid;
  wire        s_gates1_out;
  wire        s_gates14_out;
  wire        s_gates15_out;
  wire        s_gates16_out;
  wire        s_gates2_out;
  wire        s_gates4_out;
  wire        s_gates5_out;
  wire        s_gates6_out;
  wire        s_gates7_out;
  wire        s_gates9_out;
  wire        s_ioxerr_n;
  wire        s_mor_n;
  wire        s_parerr_n;
  wire        s_powfail_n;
  wire        s_z_n;
  wire        s_z;

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_fidbo_15_0[15:0] = FIDBO_15_0;
  assign s_bint10_n         = BINT10N;
  assign s_bint11_n         = BINT11N;
  assign s_bint12_n         = BINT12N;
  assign s_bint13_n         = BINT13N;
  assign s_bint15_n         = BINT15N;
  assign s_empid_n          = EMPIDN;
  assign s_ioxerr_n         = IOXERRN;
  assign s_mor_n            = MORN;
  assign s_parerr_n         = PARERRN;
  assign s_powfail_n        = POWFAILN;
  assign s_z                = Z;

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign IREQ_15_0_N        = s_ireq_15_0_n_out[15:0];

  /*******************************************************************************
   ** Here all in-lined components are defined                                   **
   *******************************************************************************/

  // NOT Gate
  assign s_z_n              = ~s_z;

  // NOT Gate
  assign s_empid            = ~s_empid_n;

  /*******************************************************************************
   ** Here all normal components are defined                                     **
   *******************************************************************************/
  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_1 (
      .input1(s_fidbo_15_0[0]),
      .input2(s_empid),
      .result(s_gates1_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_2 (
      .input1(s_fidbo_15_0[15]),
      .input2(s_empid),
      .result(s_gates2_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_3 (
      .input1(s_fidbo_15_0[14]),
      .input2(s_empid),
      .result(s_ireq_15_0_n_out[14])
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_4 (
      .input1(s_fidbo_15_0[13]),
      .input2(s_empid),
      .result(s_gates4_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_5 (
      .input1(s_fidbo_15_0[12]),
      .input2(s_empid),
      .result(s_gates5_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_6 (
      .input1(s_fidbo_15_0[11]),
      .input2(s_empid),
      .result(s_gates6_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_7 (
      .input1(s_fidbo_15_0[10]),
      .input2(s_empid),
      .result(s_gates7_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_8 (
      .input1(s_fidbo_15_0[9]),
      .input2(s_empid),
      .result(s_ireq_15_0_n_out[9])
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_9 (
      .input1(s_fidbo_15_0[8]),
      .input2(s_empid),
      .result(s_gates9_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_10 (
      .input1(s_fidbo_15_0[7]),
      .input2(s_empid),
      .result(s_ireq_15_0_n_out[7])
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_11 (
      .input1(s_fidbo_15_0[6]),
      .input2(s_empid),
      .result(s_ireq_15_0_n_out[6])
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_12 (
      .input1(s_fidbo_15_0[5]),
      .input2(s_empid),
      .result(s_ireq_15_0_n_out[5])
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_13 (
      .input1(s_fidbo_15_0[4]),
      .input2(s_empid),
      .result(s_ireq_15_0_n_out[4])
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_14 (
      .input1(s_fidbo_15_0[3]),
      .input2(s_empid),
      .result(s_gates14_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_15 (
      .input1(s_fidbo_15_0[2]),
      .input2(s_empid),
      .result(s_gates15_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_16 (
      .input1(s_fidbo_15_0[1]),
      .input2(s_empid),
      .result(s_gates16_out)
  );

  NOR_GATE #(
      .BubblesMask(2'b11)
  ) GATES_17 (
      .input1(s_gates16_out),
      .input2(s_bint11_n),
      .result(s_ireq_15_0_n_out[1])
  );

  NOR_GATE #(
      .BubblesMask(2'b11)
  ) GATES_18 (
      .input1(s_gates1_out),
      .input2(s_bint10_n),
      .result(s_ireq_15_0_n_out[0])
  );

  NOR_GATE #(
      .BubblesMask(2'b11)
  ) GATES_19 (
      .input1(s_gates2_out),
      .input2(s_bint15_n),
      .result(s_ireq_15_0_n_out[15])
  );

  NOR_GATE #(
      .BubblesMask(2'b11)
  ) GATES_20 (
      .input1(s_gates4_out),
      .input2(s_powfail_n),
      .result(s_ireq_15_0_n_out[13])
  );

  NOR_GATE #(
      .BubblesMask(2'b11)
  ) GATES_21 (
      .input1(s_gates5_out),
      .input2(s_mor_n),
      .result(s_ireq_15_0_n_out[12])
  );

  NOR_GATE #(
      .BubblesMask(2'b11)
  ) GATES_22 (
      .input1(s_gates6_out),
      .input2(s_parerr_n),
      .result(s_ireq_15_0_n_out[11])
  );

  NOR_GATE #(
      .BubblesMask(2'b11)
  ) GATES_23 (
      .input1(s_gates7_out),
      .input2(s_ioxerr_n),
      .result(s_ireq_15_0_n_out[10])
  );

  NOR_GATE #(
      .BubblesMask(2'b11)
  ) GATES_24 (
      .input1(s_gates9_out),
      .input2(s_z_n),
      .result(s_ireq_15_0_n_out[8])
  );

  NOR_GATE #(
      .BubblesMask(2'b11)
  ) GATES_25 (
      .input1(s_gates14_out),
      .input2(s_bint13_n),
      .result(s_ireq_15_0_n_out[3])
  );

  NOR_GATE #(
      .BubblesMask(2'b11)
  ) GATES_26 (
      .input1(s_gates15_out),
      .input2(s_bint12_n),
      .result(s_ireq_15_0_n_out[2])
  );


endmodule
