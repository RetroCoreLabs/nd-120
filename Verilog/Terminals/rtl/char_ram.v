//============================================================================
//! Character RAM - one 16-bit cell per screen position, true dual port
//!
//! Part of the board-independent terminal core (Verilog/Terminals/).
//!
//! Cell layout:
//!     [ 7:0] character code, indexes the font ROM
//!     [15:8] attributes. Stage A uses only bit 8 (reverse video); the rest
//!            are reserved so the width never has to change when the VT100
//!            attributes arrive (see the plan, Stage B).
//!
//! Port A is terminal_ctrl's side: writes, plus a read the VT100 scroll-
//! region copy engine uses (read one cell, write it a row over - two clocks
//! per cell). Port B is the read side owned by the pixel pipeline in
//! text_screen. One clock of read latency, registered outputs - that is what
//! infers a block RAM rather than LUTs. Port A's read returns the OLD value
//! on a same-address write (read-first); the copy engine never depends on
//! that - it reads and writes different addresses.
//!
//! 80 x 24 x 2 bytes = 3840 bytes. On the Nexys 4 DDR's xc7a100t (~607 KB of
//! block RAM) that is noise; stated here so nobody has to wonder.
//!
//! Both ports are on the same clock (the pixel clock). Bytes arriving from the
//! CPU cross into that domain BEFORE this module - see terminal_top.v.
//!
//! Written 27-AUG-2026.
//============================================================================

`default_nettype none

module char_ram #(
    parameter integer COLS  = 80,
    parameter integer ROWS  = 24,
    parameter integer AWIDTH = 11   //! ceil(log2(80*24 = 1920)) = 11
) (
    input wire clk,  //! pixel clock (from nd120_console_mega65.clk and others)

    // Port A (terminal_ctrl): write, plus the copy engine's read
    input  wire              we,
    input  wire [AWIDTH-1:0] waddr,
    input  wire [      15:0] wdata,
    input  wire [AWIDTH-1:0] raddr2,
    output reg  [      15:0] rdata2,

    // Port B (pixel pipeline): read only
    input  wire [AWIDTH-1:0] raddr,
    output reg  [      15:0] rdata
);

  localparam integer CELLS = COLS * ROWS;

  (* ram_style = "block" *)
  reg [15:0] s_cells[0:CELLS-1];

  // Simulation starts with a blank screen of spaces. On real hardware the
  // power-up contents are whatever the tool put there, so terminal_ctrl clears
  // the screen on reset regardless - this initial block only stops a fresh
  // testbench rendering X's before the first clear finishes.
  integer i;
  initial begin
    for (i = 0; i < CELLS; i = i + 1) s_cells[i] = {8'h00, 8'h20};
  end

  always @(posedge clk) begin
    if (we) s_cells[waddr] <= wdata;
    rdata2 <= s_cells[raddr2];
    rdata  <= s_cells[raddr];
  end

endmodule

`default_nettype wire
