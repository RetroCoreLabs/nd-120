/**********************************************************************************************************
** ND120 PALASM CODE CONVERTED TO VERILOG                                                                **
**                                                                                                       **
** Component PAL 44445B                                                                                  **
**                                                                                                       **
** Last reviewed: 14-DEC-2024                                                                            **
** Ronny Hansen                                                                                          **
***********************************************************************************************************/


// PAL16R4
// ADGD 18/8/86
// 44445B,9G,CADEC
// CPU ADDRESS DECODER FOR 4MB MEMORY

// PCB 3202D sheet 45:
//
// PAL input signal CGNT_n is connected to PAL OE_n pin
//     input signal CLK is connectec to PAL CK pin

module PAL_44445B (
    input CK,   //! Clock signal
    input OE_n, //! OUTPUT ENABLE (active-low) for Q0-Q3

    input WRITE,   //! I0 - WRITE - Write to memory
    input IORQ_n,  //! I1 - IORQ_n - IO Request
    input MOFF_n,  //! I2 - MOFF_n - Memory Off
    //  input PPN19,        //! I3 - PPN19  // Not in use in logic. Uncomment when needed.
    input PPN20,   //! I4 - PPN20
    input PPN21,   //! I5 - PPN21
    input PPN22,   //! I6 - PPN22
    input PPN23,   //! I7 - PPN23

    output MSIZE0_n,  //! B0_n - MSIZE0_n (not connected?)
    output CLRQ_n,    //! B1_n - CLRQ_n
    output CRQ_n,     //! B2_n - CRQ_n
    input  ECREQ,     //! B3_n - ECREQ

    output BANK2,    //! Q0_n - BANK2
    output BANK1,    //! Q1_n - BANK1
    output BANK0,    //! Q2_n - BANK0
    output MWRITE_n  //! Q3_n - MWRITE_n
);

  // Inverted input signals
  wire PPN20_n = ~PPN20;
  wire PPN21_n = ~PPN21;
  wire PPN22_n = ~PPN22;
  wire PPN23_n = ~PPN23;
  wire MOFF = ~MOFF_n;
  wire IORQ = ~IORQ_n;

  // Internal registers
  reg  BANK0_n_reg;
  reg  BANK1_n_reg;
  reg  BANK2_n_reg;
  reg  MWRITE_reg;



  //**** Sequential logic triggered on the rising edge of CLK ****
  always @(posedge CK) begin

    // Logic for BANK0, BANK1, BANK2
    BANK0_n_reg <= PPN21 | PPN20;
    BANK2_n_reg <= PPN21 | PPN20_n;
    BANK1_n_reg <= PPN21_n | PPN20;

    // Logic for MWRITE
    MWRITE_reg  <= WRITE;
  end

  // Tri-state control for Q outputs
  // High-impedance state when OE_n is high (active-low)
  assign BANK2 = OE_n ? 1'b0 : ~BANK2_n_reg;
  assign BANK1 = OE_n ? 1'b0 : ~BANK1_n_reg;
  assign BANK0 = OE_n ? 1'b0 : ~BANK0_n_reg;
  assign MWRITE_n = OE_n ? 1'b1 : ~MWRITE_reg; // High-Z gives 1 (signal is negated)


  //**** Syncronous logic (always running) ****
  // Note: comments from original printout was "chopped of" in the PALASM print, thats why they are semi-missing

  // ND120_ONBOARD_2MB: the 2 MB variant of this board. DERIVED, NOT FROM A PAL
  // DUMP. Real 3202D boards were fitted with 2, 4 or 6 MB (the size display
  // described in MEM_ADEC_45.v: 100 = 2 MB, 200 = 4 MB, 300 = 6 MB); the
  // equations in this file are the 4 MB programming. The 2 MB form here keeps
  // only the first 2 MB block (address bit 20 = 0, BANK0), following the
  // original listing's own note that each address line in the decode covers
  // one block ("EACH LINE R...", "THE 4MB (2M..." in PAL_44445B). Above 2 MB
  // the board then does not answer and the CPU raises memory out of range, as
  // a 2 MB board would. Only the Azure build defines it
  // (Verilog/fpga/azure-x930613/docs/00-plan.md).
`ifdef ND120_ONBOARD_2MB
  // 2 MB (derived): the second line (PPN20 = 1, the upper 2 MB) is gone, so
  // those addresses are not local and go to the bus (CRQ) instead
  assign CLRQ_n = ~(ECREQ & IORQ_n & PPN23_n & PPN22_n & PPN21_n & PPN20_n & MOFF_n);
  assign CRQ_n = ~((ECREQ & IORQ) |
      (ECREQ & MOFF) | (ECREQ & PPN23) | (ECREQ & PPN22) | (ECREQ & PPN21) | (ECREQ & PPN20));
`else
  // Logic for CLRQ_n (active-low)
  assign CLRQ_n = ~(
      (ECREQ & IORQ_n & PPN23_n & PPN22_n & PPN21_n & PPN20_n & MOFF_n) | // EACH LINE R
      // TO ALLOW MA
      (ECREQ & IORQ_n & PPN23_n & PPN22_n & PPN21_n & PPN20 & MOFF_n)  // IN THE ADDR
                                                                       // THE 4MB (2M
                                                                       // NEED NO HOL
      );

  // Logic for CRQ_n (active-low)
  assign CRQ_n = ~((ECREQ & IORQ) |  // ECREQ WILL HOLD UNTIL
      (ECREQ & MOFF) | (ECREQ & PPN23) | (ECREQ & PPN22) | (ECREQ & PPN21));



`endif

  // MSIZE0 is always high (VCC)
  assign MSIZE0_n = 0;  // Output 0 (Signal is negated)

endmodule
