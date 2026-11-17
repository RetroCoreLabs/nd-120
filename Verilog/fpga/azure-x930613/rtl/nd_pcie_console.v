//============================================================================
//! nd_pcie_console - the ND-120 console as registers the PC reads and writes
//!
//! Board: Microsoft Azure FPGA card X930613-001 (Verilog/fpga/azure-x930613).
//!
//! WHY. The card has no serial pins, so the console reaches the PC through
//! the PCIe slot instead (docs/00-plan.md, step V1). This block holds two byte
//! queues; a PC program reads and writes them through a BAR and turns them
//! into a telnet port.
//!
//! WHERE IT SITS. On the ND side this is a BYTE interface, the same one every
//! other board's terminal core uses: bytes the CPU sent come in from
//! console_uart_rx (deserialised off the CPU's real TXD pin), bytes for the
//! CPU go out to console_uart_tx (serialised onto the CPU's real RXD pin). The
//! CPU's own SC2661 UART therefore runs unchanged - nothing here replaces it.
//!
//! THE REGISTER BUS (shared with nd_pcie_storage, written by pcie_bar_bus):
//!   addr   byte offset inside this block, 32-bit registers
//!   wr     one cycle: write wdata to addr
//!   rd     one cycle: read addr; rdata is valid on the cycle rvalid is high
//!   rvalid one cycle, exactly ONE cycle after rd here
//! The master issues one access at a time: no new rd before rvalid.
//!
//! REGISTERS (byte offsets, octal):
//!   0o000 VERSION  R   [31:24] 0, [23:16] block kind = 1 (console),
//!                      [15:0] layout version = 1
//!   0o004 STATUS   R   [15:0]  bytes waiting from the ND (ND -> PC queue)
//!                      [31:16] free places in the PC -> ND queue
//!   0o010 RXDATA   R   pops one byte sent by the ND: [8] = 1 a byte was
//!                      there, [7:0] the byte. [8] = 0: queue empty, nothing
//!                      popped.
//!   0o014 TXDATA   W   [7:0] one byte for the ND. Written while the queue is
//!                      full, the byte is dropped and ERRS[1] is set.
//!   0o020 ERRS     R/W [0] the ND -> PC queue overflowed: bytes from the ND
//!                          were lost because the PC did not read in time
//!                      [1] a TXDATA write found the queue full
//!                      Reading shows the bits; writing 1 clears that bit.
//!   other offsets  R   0, W ignored
//! Nothing is lost silently: every dropped byte leaves a sticky bit.
//!
//! One clock domain: the PCIe user clock. console_uart_rx resynchronises the
//! CPU's TXD line itself, and the SC2661 samples RXD on its own clock, so the
//! serial lines are the only crossing to the CPU domain.
//============================================================================

`default_nettype none

module nd_pcie_console #(
    parameter integer DEPTH_LOG2 = 9  //! 512 bytes per queue
) (
    input wire clk,    //! PCIe user clock (from pcie_hip_wrap.user_clk)
    input wire rst_n,  //! active-low reset in the same domain

    // ---- register bus (from pcie_bar_bus) ----
    input  wire [8:0]  addr,    //! byte offset in this block
    input  wire        wr,      //! one cycle: write
    input  wire [31:0] wdata,
    input  wire        rd,      //! one cycle: read
    output reg  [31:0] rdata,
    output reg         rvalid,  //! one cycle, one cycle after rd

    // ---- ND side: bytes the CPU sent (from console_uart_rx) ----
    input wire       nd_valid,  //! one cycle per received byte
    input wire [7:0] nd_data,

    // ---- ND side: bytes for the CPU (to console_uart_tx) ----
    output reg       to_nd_valid,  //! one cycle; only raised while to_nd_ready
    output reg [7:0] to_nd_data,
    input  wire      to_nd_ready   //! console_uart_tx idle
);

  localparam integer DEPTH = 1 << DEPTH_LOG2;
  localparam [8:0] A_VERSION = 9'o000, A_STATUS = 9'o004, A_RXDATA = 9'o010,
                   A_TXDATA = 9'o014, A_ERRS = 9'o020;

  // ---- ND -> PC queue --------------------------------------------------
  reg [7:0] up_mem[0:DEPTH-1];
  reg [DEPTH_LOG2:0] up_wp, up_rp;  // one extra bit tells full from empty
  wire [DEPTH_LOG2:0] up_count = up_wp - up_rp;
  wire up_full  = (up_count == DEPTH[DEPTH_LOG2:0]);
  wire up_empty = (up_count == 0);

  // ---- PC -> ND queue --------------------------------------------------
  reg [7:0] dn_mem[0:DEPTH-1];
  reg [DEPTH_LOG2:0] dn_wp, dn_rp;
  wire [DEPTH_LOG2:0] dn_count = dn_wp - dn_rp;
  wire dn_full  = (dn_count == DEPTH[DEPTH_LOG2:0]);
  wire dn_empty = (dn_count == 0);
  wire [DEPTH_LOG2:0] dn_free = DEPTH[DEPTH_LOG2:0] - dn_count;

  reg [1:0] errs;

  wire rd_pop = rd && (addr == A_RXDATA) && !up_empty;

  // queue memories: plain write port + registered read, which every tool
  // turns into block RAM
  always @(posedge clk) begin
    if (nd_valid && !up_full) up_mem[up_wp[DEPTH_LOG2-1:0]] <= nd_data;
    if (wr && (addr == A_TXDATA) && !dn_full) dn_mem[dn_wp[DEPTH_LOG2-1:0]] <= wdata[7:0];
  end

  // ---- the to-CPU side: one byte out each time the transmitter is idle --
  // The read of dn_mem is registered, so a byte is fetched first (dn_fetch)
  // and offered the cycle after. After offering, wait one cycle so 'ready'
  // has had time to drop (console_uart_tx goes busy on the cycle after it
  // accepts) before looking at it again.
  reg dn_fetch, dn_cool;
  reg [7:0] dn_q;
  always @(posedge clk) dn_q <= dn_mem[dn_rp[DEPTH_LOG2-1:0]];

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      up_wp       <= 0;
      up_rp       <= 0;
      dn_wp       <= 0;
      dn_rp       <= 0;
      errs        <= 2'b00;
      rdata       <= 32'd0;
      rvalid      <= 1'b0;
      to_nd_valid <= 1'b0;
      to_nd_data  <= 8'd0;
      dn_fetch    <= 1'b0;
      dn_cool     <= 1'b0;
    end else begin
      // ND -> PC: a byte arriving at a full queue is lost; say so
      if (nd_valid) begin
        if (!up_full) up_wp <= up_wp + 1'b1;
        else          errs[0] <= 1'b1;
      end

      // ---- register reads: one cycle ----
      rvalid <= rd;
      if (rd) begin
        case (addr)
          A_VERSION: rdata <= {8'd0, 8'd1, 16'd1};
          A_STATUS:  rdata <= {{(16 - DEPTH_LOG2 - 1){1'b0}}, dn_free,
                               {(16 - DEPTH_LOG2 - 1){1'b0}}, up_count};
          A_RXDATA:  rdata <= up_empty ? 32'd0
                                       : {23'd0, 1'b1, up_mem[up_rp[DEPTH_LOG2-1:0]]};
          A_ERRS:    rdata <= {30'd0, errs};
          default:   rdata <= 32'd0;
        endcase
      end
      if (rd_pop) up_rp <= up_rp + 1'b1;

      // ---- register writes ----
      if (wr) begin
        case (addr)
          A_TXDATA: begin
            if (!dn_full) dn_wp <= dn_wp + 1'b1;
            else          errs[1] <= 1'b1;
          end
          A_ERRS: errs <= errs & ~wdata[1:0];
          default: ;
        endcase
      end
      // a sticky bit set in the same cycle as a clear wins (the event is newer)
      if (nd_valid && up_full) errs[0] <= 1'b1;
      if (wr && (addr == A_TXDATA) && dn_full) errs[1] <= 1'b1;

      // ---- PC -> ND ----
      to_nd_valid <= 1'b0;
      dn_cool     <= 1'b0;
      if (dn_fetch) begin
        // dn_q now holds the byte at dn_rp
        to_nd_data  <= dn_q;
        to_nd_valid <= 1'b1;
        dn_rp       <= dn_rp + 1'b1;
        dn_fetch    <= 1'b0;
        dn_cool     <= 1'b1;
      end else if (!dn_cool && !to_nd_valid && to_nd_ready && !dn_empty) begin
        dn_fetch <= 1'b1;
      end
    end
  end

endmodule

`default_nettype wire
