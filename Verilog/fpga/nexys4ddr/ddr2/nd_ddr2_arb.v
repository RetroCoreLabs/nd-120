/****************************************************************************
** nd_ddr2_arb - two clients on one nd_ddr2_port                            **
**                                                                         **
** Client A: ND-120 main memory (MEM_RAM_49_DDR2) - bottom 4 MiB region.   **
** Client B: nd_ddr2_storage - region at REGION_BASE_UNITS (64 MiB in).    **
** Regions never overlap, so the arbiter only serializes access, it never  **
** translates addresses.                                                   **
**                                                                         **
** Everything is in the ui_clk domain. Each client already holds           **
** req_valid until req_ready and runs ONE operation at a time, so the      **
** arbiter is a plain two-way lock: grab the port for whichever client     **
** asks (ties alternate between the clients), hold it until that           **
** operation's rsp_valid, then free it. rsp_valid is steered back to the   **
** owning client only.                                                     **
**                                                                         **
** Fairness: when BOTH clients ask in the same idle cycle, the grant goes  **
** to the one that did NOT run last, so a back-to-back stream from one     **
** client (every CPU write is a write-through) cannot starve the other.    **
** A lone requester is granted immediately either way.                     **
**                                                                         **
** Watchdog: an operation holding the grant for 2^WDOG_BITS ui_clk cycles  **
** (default 2^16 = 874 us at 75 MHz, orders of magnitude past any MIG      **
** refresh/ZQ blackout) sets the sticky dbg_stuck flag. The grant is NOT   **
** released and no response is faked: a made-up completion handed to       **
** MEM_RAM_49_DDR2 mid-operation is the 25-AUG stale-word corruption       **
** class all over again. The flag turns a silent freeze into a             **
** diagnosable one.                                                        **
**                                                                         **
** Orphan responses: rsp_valid with no grant held is steered to nobody by  **
** construction; sticky dbg_orphan records that it happened at all.        **
**                                                                         **
** Last reviewed: 25-AUG-2026                                              **
** Ronny Hansen                                                            **
*****************************************************************************/
`default_nettype none

module nd_ddr2_arb #(
    parameter WDOG_BITS = 16   // sticky dbg_stuck after 2^WDOG_BITS cycles
) (
    input wire ui_clk,                  //! 75 MHz - the domain of every port signal below (from nd_ddr2_port.ui_clk)
    input wire ui_rst,

    // client A: main memory
    input  wire          a_req_valid,
    input  wire          a_req_we,
    input  wire [ 26:0]  a_req_addr,
    input  wire [127:0]  a_req_wdata,
    input  wire [ 15:0]  a_req_wmask,
    output wire          a_req_ready,
    output wire          a_rsp_valid,
    output wire [127:0]  a_rsp_rdata,

    // client B: storage region
    input  wire          b_req_valid,
    input  wire          b_req_we,
    input  wire [ 26:0]  b_req_addr,
    input  wire [127:0]  b_req_wdata,
    input  wire [ 15:0]  b_req_wmask,
    output wire          b_req_ready,
    output wire          b_rsp_valid,
    output wire [127:0]  b_rsp_rdata,

    // downstream: nd_ddr2_port
    output wire          req_valid,
    output wire          req_we,
    output wire [ 26:0]  req_addr,
    output wire [127:0]  req_wdata,
    output wire [ 15:0]  req_wmask,
    input  wire          req_ready,
    input  wire          rsp_valid,
    input  wire [127:0]  rsp_rdata,

    // debug/health (sticky until ui_rst; for ILA probes or an LED)
    output reg           dbg_stuck,     // an op held the grant past the watchdog
    output reg           dbg_orphan,    // rsp_valid arrived with no grant held
    output wire [ 1:0]   dbg_grant      // current grant state
);

  localparam G_IDLE = 2'd0;
  localparam G_A    = 2'd1;
  localparam G_B    = 2'd2;

  reg [1:0]           grant;
  reg                 last_was_a;   // fairness: a tie goes to the other one
  reg [WDOG_BITS-1:0] wdog;

  assign dbg_grant = grant;

  always @(posedge ui_clk) begin
    if (ui_rst) begin
      grant      <= G_IDLE;
      last_was_a <= 1'b0;
      wdog       <= {WDOG_BITS{1'b0}};
      dbg_stuck  <= 1'b0;
      dbg_orphan <= 1'b0;
    end else begin
      case (grant)
        G_IDLE: begin
          wdog <= {WDOG_BITS{1'b0}};
          if (a_req_valid && b_req_valid) begin
            // both waiting: whoever did NOT run last goes first
            if (last_was_a) grant <= G_B;
            else            grant <= G_A;
          end else if (a_req_valid) grant <= G_A;
          else if (b_req_valid)     grant <= G_B;
          // a response with no owner would be steered to nobody - record it
          if (rsp_valid) dbg_orphan <= 1'b1;
        end
        // hold the port until the owning operation completes
        G_A:
        if (rsp_valid) begin
          grant      <= G_IDLE;
          last_was_a <= 1'b1;
        end else begin
          wdog <= wdog + 1'b1;
          if (&wdog) dbg_stuck <= 1'b1;
        end
        G_B:
        if (rsp_valid) begin
          grant      <= G_IDLE;
          last_was_a <= 1'b0;
        end else begin
          wdog <= wdog + 1'b1;
          if (&wdog) dbg_stuck <= 1'b1;
        end
        default: grant <= G_IDLE;
      endcase
    end
  end

  wire sel_a = (grant == G_A);
  wire sel_b = (grant == G_B);

  assign req_valid = (sel_a & a_req_valid) | (sel_b & b_req_valid);
  assign req_we    = sel_a ? a_req_we : b_req_we;
  assign req_addr  = sel_a ? a_req_addr : b_req_addr;
  assign req_wdata = sel_a ? a_req_wdata : b_req_wdata;
  assign req_wmask = sel_a ? a_req_wmask : b_req_wmask;

  assign a_req_ready = sel_a & req_ready;
  assign b_req_ready = sel_b & req_ready;

  assign a_rsp_valid = sel_a & rsp_valid;
  assign b_rsp_valid = sel_b & rsp_valid;
  assign a_rsp_rdata = rsp_rdata;
  assign b_rsp_rdata = rsp_rdata;

endmodule

`default_nettype wire
