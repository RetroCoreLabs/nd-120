
/**************************************************************************
** ND120 CPU, MM&M                                                       **
** CPU/PROC/CGA                                                          **
**  BusDriver16                                                          **
**                                                                       **
** SHEET 4 of 8 (Page 5 in PDF)                                          **
**                                                                       **
** Last reviewed: 6-FEB-2025                                             **
** Ronny Hansen                                                          **
***************************************************************************/



module BusDriver16 (
    input wire EN,  // Enable = FALSE => A to IO, Enable=TRUE => IO to A
    input wire TN,  // Test enable

    input  wire [15:0] A_15_0_IN,  // Data inputA (Connect to internal FIDBO data bus))
    output wire [15:0] A_15_0_OUT, // A output  (Connect to internal XFIDBI data bus)

    input wire[15:0]   IO_15_0_IN,    // IN and OUT to XFIDB data bus (Connect to EXTERNAL _XFIDB_ data bus)
    output wire [15:0] IO_15_0_OUT  //! FIDB output bus (to CPU_PROC_CGA_33.FIDB_15_0_OUT)
);

  reg [15:0] IO_reg;  // Internal data register
  reg [15:0] A_reg;  // Internal data register

  //assign ZI_15_0 = TN ?  IO_15_0 : 16'b0; // Probably the correct implementation ? In test moode we should be isolated ?
  //assign ZI_15_0 = TN ?  internalData : 16'b0; // Probably the correct implementation ? In test moode we should be isolated ?

  // Fixed: Use blocking assignments and ensure all signals assigned in all paths to prevent latch inference
  always @(*) begin
    // Default assignments to prevent latch inference
    IO_reg = 16'b0;
    A_reg = 16'b0;

    if (!EN) begin
      // Write A to IO
      IO_reg = A_15_0_IN;
    end else begin
      // Read IO to A
      A_reg = IO_15_0_IN;
    end
  end

  // Bidirectional data operation
  assign IO_15_0_OUT = TN ? ((!EN) ? IO_reg : 16'b0) : 16'b0;
  assign A_15_0_OUT  = IO_15_0_IN; //A_reg; // A is always read from IO

endmodule
