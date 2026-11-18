/**********************************************************************************************************
** ND120 PALASM CODE CONVERTED TO VERILOG                                                                **
**                                                                                                       **
** Component PAL 44446B                                                                                  **
**                                                                                                       **
** Last reviewed: 22-MAR-2025                                                                            **
** Ronny Hansen                                                                                          **
***********************************************************************************************************/


// PAL16R4
// ADGD 18/8/86
// 44446B, 6G, BADEC
// DMA ADDRESS DECODE FOR 4MB MEMORY

// PCB 3202D sheet 45:
//
// PAL input signal BGNT_n is connected to PAL OE_n pin
//     input signal DBAPR is connectec to PAL CK pin (AND I0)


module PAL_44446B (
    input CK,   //! Clock signal (connected to DBAPR)
    input OE_n, //! OUTPUT ENABLE (active-low) for Q0-Q3 (connected to BGNT_n)

    input DBAPR,     //! I0 - DBAPR (Data Bus Address PResent)
    input MOFF_n,    //! I1 - MOFF_n (memory OFF)
    input BINPUT_n,  //! I2 - IBINPUT_n (Bus Input)
    input BMEM_n,    //! I3 - BMEM_n
    input BD20_n,    //! I4 - BD20_n
    input BD21_n,    //! I5 - BD21_n
    input BD22_n,    //! I6 - BD22_n
    input BD23_n,    //! I7 - BD23_n

    output AOK,       //! B0_n - AOK  (Address OK)
    output DDBAPR,    //! B1_n - DDBAPR (Delayed Data Bus Address Present)
    output MSIZE1_n,  //! B2_n - MSIZE1_n (not connected?)
    //  input  BD19_n,      //! B3_n - BD19_n (not in use)

    output BANK2,    //! Q0_n - BANK2
    output BANK1,    //! Q1_n - BANK1
    output BANK0,    //! Q2_n - BANK0
    output MWRITE_n  //! Q3_n - MWRITE_n
);

  // Inverted input signals
  wire BD20 = ~BD20_n;
  wire BD21 = ~BD21_n;
  wire BD22 = ~BD22_n;
  wire BD23 = ~BD23_n;
  wire MOFF = ~MOFF_n;
  wire BINPUT = ~BINPUT_n;


  // Internal registers
  reg  BANK0_n_reg;
  reg  BANK1_n_reg;
  reg  BANK2_n_reg;
  reg  MWRITE_reg;


  //**** Sequential logic triggered on the rising edge of CLK ****
  always @(posedge CK) begin

    // Logic for BANK0, BANK1, BANK2
    BANK0_n_reg <= BD21 | BD20;
    BANK2_n_reg <= BD21 | BD20_n;
    BANK1_n_reg <= BD21_n | BD20;

    // Logic for MWRITE
    MWRITE_reg  <= BINPUT;

  end

  // Tri-state control for Q outputs
  // High-impedance state when OE_n is high (active-low)
  assign BANK2 = OE_n ? 1'b0 : ~BANK2_n_reg;
  assign BANK1 = OE_n ? 1'b0 : ~BANK1_n_reg;
  assign BANK0 = OE_n ? 1'b0 : ~BANK0_n_reg;
  assign MWRITE_n = OE_n ? 1'b0 : ~MWRITE_reg;

  //**** Syncronous logic (always running) ****

  // Logic for AOK
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
  assign AOK = ~(BMEM_n | BD23 | BD22 | BD21 | BD20 | MOFF);  // 2 MB (derived)
`else
  assign AOK = ~(BMEM_n | BD23 | BD22 | BD21 | MOFF);  // 4 MB
`endif

  // Logic for DDBAPR_n (active-low)
  assign DDBAPR = DBAPR;


  // MSIZE1 is always low (GND) => MSIZE1_n is always HIGH
  assign MSIZE1_n = 1;  // Active-low representation of a constant low signal



endmodule

/*
DESCRIPTION

; 2/1-860LB: BOTH SIDES OF MWRITE EQUATION INVERTED
; 8/1-87JLB: NEW INPUT /MOFF TO DISBLE THE WHOLE MEMORY, BD18 AND BD19 REMOVED.
; 300387 JLB: BLRQ ASSUMED DATA HOLD TIME AFTER TRAILING EDGF OF BAPR !
; CHANGED TO AOK

; 180587 M3202B
; 060687 JLB: SWAPPED BANK1 AND BANK2 TO PROVIDE ENOUGH SPACE FOR PACKAGES.
*/
