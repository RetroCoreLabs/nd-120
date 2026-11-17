/*****************************************************************************
**  pcie_bar_bus_tb.v                                                       **
**                                                                          **
**  Path: Verilog/fpga/azure-x930613/sim/pcie_bar_bus_tb.v                  **
**                                                                          **
**  The PC's path into the board, as the board top will wire it:            **
**    testbench (the PC) -> pcie_hip_wrap (simulation version)              **
**                       -> pcie_bar_bus -> nd_pcie_console                 **
**                                       -> nd_pcie_storage                 **
**  The storage block's ND side is tied off here (its own test covers it):  **
**  no requests, and the write-buffer word it reads back is a fixed value.  **
**                                                                          **
**  Checks:                                                                 **
**   (1) the console answers at 0o0000 (VERSION kind 1), the storage block  **
**       at 0o1000 (VERSION kind 2, 5 slots).                               **
**   (2) the empty part of the window (0o2000 and up) reads 0 and a write   **
**       there reaches neither block.                                       **
**   (3) console bytes both ways through the window.                        **
**   (4) the storage block's slow DATA read: busy stays high until its      **
**       rvalid, and the value arrives.                                     **
**   (5) an access sent while busy is NOT passed on (the console queue does **
**       not see a write sent during a storage read).                       **
**   (6) the storage block's registers are reached with the window offset   **
**       removed (SIZE_LO written at 0o1024 reads back at 0o1024).          **
**                                                                          **
**  Verdict: TB_RESULT: PASS / TB_RESULT: FAIL                              **
*****************************************************************************/

`timescale 1ns / 1ps

module pcie_bar_bus_tb;

  integer errors = 0;
  task check(input cond, input [1023:0] what);
    begin
      if (!cond) begin
        errors = errors + 1;
        $display("  FAIL: %0s", what);
      end
    end
  endtask

  reg clk = 0;
  always #4 clk = ~clk;  // 125 MHz
  reg rst_n = 0;

  // ---- the PC side ----
  reg  [11:0] p_addr = 0;
  reg         p_wr = 0, p_rd = 0;
  reg  [31:0] p_wdata = 0;
  wire [31:0] p_rdata;
  wire        p_rvalid, p_busy;

  // ---- wrapper <-> window split ----
  wire        u_clk, u_rst_n;
  wire [11:0] b_addr;
  wire        b_wr, b_rd, b_rvalid, b_busy;
  wire [31:0] b_wdata, b_rdata;
  wire [7:0]  tx_unused;

  pcie_hip_wrap HIP (
      .pcie_refclk(1'b0), .pcie_perst_n(1'b1), .pcie_rx(8'd0), .pcie_tx(tx_unused),
      .user_clk(u_clk), .user_rst_n(u_rst_n),
      .addr(b_addr), .wr(b_wr), .wdata(b_wdata), .rd(b_rd),
      .rdata(b_rdata), .rvalid(b_rvalid), .busy(b_busy),
      .sim_clk(clk), .sim_rst_n(rst_n),
      .sim_addr(p_addr), .sim_wr(p_wr), .sim_wdata(p_wdata), .sim_rd(p_rd),
      .sim_rdata(p_rdata), .sim_rvalid(p_rvalid), .sim_busy(p_busy));

  wire [8:0]  c_addr, s_addr;
  wire        c_wr, c_rd, c_rvalid, s_wr, s_rd, s_rvalid, s_busy;
  wire [31:0] c_wdata, c_rdata, s_wdata, s_rdata;

  pcie_bar_bus BAR (
      .clk(u_clk), .rst_n(u_rst_n),
      .addr(b_addr), .wr(b_wr), .wdata(b_wdata), .rd(b_rd),
      .rdata(b_rdata), .rvalid(b_rvalid), .busy(b_busy),
      .con_addr(c_addr), .con_wr(c_wr), .con_wdata(c_wdata), .con_rd(c_rd),
      .con_rdata(c_rdata), .con_rvalid(c_rvalid),
      .sto_addr(s_addr), .sto_wr(s_wr), .sto_wdata(s_wdata), .sto_rd(s_rd),
      .sto_rdata(s_rdata), .sto_rvalid(s_rvalid));

  // ---- console, ND side driven by the testbench ----
  reg        nd_valid = 0;
  reg  [7:0] nd_data = 0;
  wire       to_valid;
  wire [7:0] to_data;
  reg  [7:0] to_seen[0:15];
  integer    n_to = 0;
  always @(posedge clk) if (to_valid) begin to_seen[n_to] = to_data; n_to = n_to + 1; end

  nd_pcie_console CON (
      .clk(u_clk), .rst_n(u_rst_n),
      .addr(c_addr), .wr(c_wr), .wdata(c_wdata), .rd(c_rd), .rdata(c_rdata), .rvalid(c_rvalid),
      .nd_valid(nd_valid), .nd_data(nd_data),
      .to_nd_valid(to_valid), .to_nd_data(to_data), .to_nd_ready(1'b1));

  // ---- storage, ND side tied off ----
  wire [4:0]  img_mounted, sd_ack;
  wire        img_readonly, sd_buff_wr;
  wire [63:0] img_size;
  wire [12:0] sd_buff_addr;
  wire [15:0] sd_buff_dout;

  nd_pcie_storage #(.N_SLOTS(5)) STO (
      .clk(u_clk), .rst_n(u_rst_n),
      .addr(s_addr), .wr(s_wr), .wdata(s_wdata), .rd(s_rd),
      .rdata(s_rdata), .rvalid(s_rvalid), .busy(s_busy),
      .img_mounted(img_mounted), .img_readonly(img_readonly), .img_size(img_size),
      .sd_lba(160'd0), .sd_blk_cnt(30'd0), .sd_rd(5'd0), .sd_wr(5'd0), .sd_ack(sd_ack),
      .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout),
      .sd_buff_din(16'o123456), .sd_buff_wr(sd_buff_wr));

  // ---- PC bus tasks ----
  reg [31:0] rv;
  integer    busy_cycles;
  task pread(input [11:0] a);
    integer t;
    begin
      @(posedge clk); p_addr <= a; p_rd <= 1'b1;
      @(posedge clk); p_rd <= 1'b0;
      t = 0; busy_cycles = 0;
      while (!p_rvalid && t < 50) begin
        if (p_busy) busy_cycles = busy_cycles + 1;
        @(posedge clk); t = t + 1;
      end
      check(p_rvalid, "every read gets an rvalid");
      rv = p_rdata;
    end
  endtask
  task pwrite(input [11:0] a, input [31:0] d);
    begin
      @(posedge clk); p_addr <= a; p_wdata <= d; p_wr <= 1'b1;
      @(posedge clk); p_wr <= 1'b0;
    end
  endtask

  integer i;

  initial begin
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);

    $display("(1) both blocks answer at their offsets");
    pread(12'o0000);
    check(rv == {8'd0, 8'd1, 16'd1}, "console VERSION at 0o0000");
    pread(12'o1000);
    check(rv == {8'd5, 8'd2, 16'd1}, "storage VERSION at 0o1000 (5 slots)");

    $display("(2) the empty part of the window");
    pread(12'o2000);
    check(rv == 32'd0, "0o2000 reads 0");
    pread(12'o7774);
    check(rv == 32'd0, "0o7774 reads 0");
    pwrite(12'o2014, 32'o101);            // console TXDATA offset, wrong region
    pwrite(12'o3024, 32'd99);             // storage SIZE_LO offset, wrong region
    repeat (10) @(posedge clk);
    check(n_to == 0, "a write to the empty window must not reach the console");
    pread(12'o1024);
    check(rv == 32'd0, "a write to the empty window must not reach the storage block");

    $display("(3) console bytes both ways");
    pwrite(12'o0014, 32'o110);            // 'H'
    pwrite(12'o0014, 32'o151);            // 'i'
    repeat (20) @(posedge clk);
    check(n_to == 2 && to_seen[0] == 8'o110 && to_seen[1] == 8'o151,
          "bytes written at 0o0014 reach the ND side in order");
    @(posedge clk); nd_valid <= 1'b1; nd_data <= 8'o132;
    @(posedge clk); nd_valid <= 1'b0;
    pread(12'o0010);
    check(rv == {23'd0, 1'b1, 8'o132}, "a byte from the ND reads at 0o0010");

    $display("(4) the slow storage DATA read");
    pwrite(12'o1010, 32'h100);            // XFER START, slot 0
    pread(12'o1014);
    check(rv == 32'o123456, "DATA read returns the write-buffer word");
    check(busy_cycles >= 2, "busy must cover the whole slow read");

    $display("(5) an access during busy is held back");
    @(posedge clk); p_addr <= 12'o1014; p_rd <= 1'b1;
    @(posedge clk); p_rd <= 1'b0;
    // send a console write while the storage read is open
    p_addr <= 12'o0014; p_wdata <= 32'o170; p_wr <= 1'b1;
    @(posedge clk); p_wr <= 1'b0;
    while (!p_rvalid) @(posedge clk);
    repeat (20) @(posedge clk);
    check(n_to == 2, "a write sent during busy must not be passed on");
    pread(12'o1040);
    check(rv == 32'd0, "the storage block saw no access during its own busy");
    pwrite(12'o1010, 32'h200);            // XFER END

    $display("(6) offsets inside the storage region");
    pwrite(12'o1024, 32'd16384);
    pread(12'o1024);
    check(rv == 32'd16384, "SIZE_LO written at 0o1024 reads back there");
    pread(12'o0024);
    check(rv == 32'd0, "and the console's own 0o024 is untouched (unused there)");

    if (errors == 0) $display("TB_RESULT: PASS");
    else             $display("TB_RESULT: FAIL (%0d)", errors);
    $finish;
  end

  initial begin
    #2_000_000;
    $display("TB_RESULT: FAIL (watchdog)");
    $finish;
  end

endmodule
