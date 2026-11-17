/*****************************************************************************
**  nd_pcie_console_tb.v                                                    **
**                                                                          **
**  Path: Verilog/fpga/azure-x930613/sim/nd_pcie_console_tb.v               **
**                                                                          **
**  The PCIe console block (../rtl/nd_pcie_console.v) driven from a         **
**  simulated PC on its register bus. The ND side is the board's real      **
**  serial pair, wired in a loop: bytes the PC writes go out through       **
**  console_uart_tx (8N1, what the CPU's SC2661 receives) and come straight **
**  back through console_uart_rx (7E1, what every board uses on the CPU's  **
**  TXD line - bit 7 is software parity). So the loop stands in for a CPU   **
**  that echoes every 7-bit character.                                      **
**                                                                          **
**  Checks:                                                                 **
**   (1) VERSION reads kind 1, layout 1.                                    **
**   (2) empty queue: RXDATA has bit 8 clear, STATUS counts 0 / all free.   **
**   (3) loop: a 40-character string written to TXDATA comes back on       **
**       RXDATA, every byte, in order; STATUS counts match on the way.      **
**   (4) PC -> ND queue full: the write is dropped and ERRS[1] set; the     **
**       bytes already queued still all reach the ND side.                  **
**   (5) ND -> PC overflow: bytes from the ND with no reader set ERRS[0],   **
**       the queue keeps the FIRST bytes, nothing is overwritten.           **
**   (6) ERRS clears on writing 1 and only the bit written.                 **
**   (7) unused offset reads 0.                                             **
**  (4)-(6) use a second instance with 8-byte queues, ND side driven by the **
**  testbench directly so the overflow is exact.                            **
**                                                                          **
**  Verdict: TB_RESULT: PASS / TB_RESULT: FAIL                              **
*****************************************************************************/

`timescale 1ns / 1ps

module nd_pcie_console_tb;

  integer errors = 0;

  reg clk = 0;
  always #4 clk = ~clk;  // 125 MHz, a PCIe user clock rate
  reg rst_n = 0;

  task check(input cond, input [1023:0] what);
    begin
      if (!cond) begin
        errors = errors + 1;
        $display("  FAIL: %0s", what);
      end
    end
  endtask

  // ======================= instance A: the serial loop ====================
  reg  [8:0]  a_addr = 0;
  reg         a_wr = 0, a_rd = 0;
  reg  [31:0] a_wdata = 0;
  wire [31:0] a_rdata;
  wire        a_rvalid;
  wire        a_nd_valid;
  wire [7:0]  a_nd_data;
  wire        a_to_valid, a_to_ready;
  wire [7:0]  a_to_data;
  wire        line;  // the serial line: tx -> rx

  nd_pcie_console #(.DEPTH_LOG2(9)) dut_a (
      .clk(clk), .rst_n(rst_n),
      .addr(a_addr), .wr(a_wr), .wdata(a_wdata), .rd(a_rd), .rdata(a_rdata), .rvalid(a_rvalid),
      .nd_valid(a_nd_valid), .nd_data(a_nd_data),
      .to_nd_valid(a_to_valid), .to_nd_data(a_to_data), .to_nd_ready(a_to_ready));

  // 16 clocks per bit keeps the test short; the framing is the board's
  console_uart_tx #(.CLK_HZ(125_000_000), .BAUD(115200), .DATA_BITS(8), .PARITY(1'b0)) utx (
      .clk(clk), .rst_n(rst_n), .divisor_ovr(16'd16),
      .byte_valid(a_to_valid), .byte_data(a_to_data), .ready(a_to_ready), .txd(line));
  console_uart_rx #(.CLK_HZ(125_000_000), .BAUD(115200), .DATA_BITS(7), .PARITY(1'b1)) urx (
      .clk(clk), .rst_n(rst_n), .divisor_ovr(16'd16),
      .rxd(line), .byte_valid(a_nd_valid), .byte_data(a_nd_data));

  // ======================= instance B: small queues =======================
  reg  [8:0]  b_addr = 0;
  reg         b_wr = 0, b_rd = 0;
  reg  [31:0] b_wdata = 0;
  wire [31:0] b_rdata;
  wire        b_rvalid;
  reg         b_nd_valid = 0;
  reg  [7:0]  b_nd_data = 0;
  wire        b_to_valid;
  wire [7:0]  b_to_data;
  reg         b_to_ready = 0;

  nd_pcie_console #(.DEPTH_LOG2(3)) dut_b (
      .clk(clk), .rst_n(rst_n),
      .addr(b_addr), .wr(b_wr), .wdata(b_wdata), .rd(b_rd), .rdata(b_rdata), .rvalid(b_rvalid),
      .nd_valid(b_nd_valid), .nd_data(b_nd_data),
      .to_nd_valid(b_to_valid), .to_nd_data(b_to_data), .to_nd_ready(b_to_ready));

  // bytes instance B handed to the ND side
  reg [7:0] b_seen[0:63];
  integer   b_nseen = 0;
  always @(posedge clk) if (b_to_valid) begin
    check(b_to_ready, "to_nd_valid raised while the transmitter was busy");
    b_seen[b_nseen] = b_to_data;
    b_nseen = b_nseen + 1;
  end

  // ======================= PC bus tasks ===================================
  reg [31:0] rv;
  task a_read(input [8:0] ad);
    begin
      @(posedge clk); a_addr <= ad; a_rd <= 1'b1;
      @(posedge clk); a_rd <= 1'b0;
      while (!a_rvalid) @(posedge clk);
      rv = a_rdata;
    end
  endtask
  task a_write(input [8:0] ad, input [31:0] d);
    begin
      @(posedge clk); a_addr <= ad; a_wdata <= d; a_wr <= 1'b1;
      @(posedge clk); a_wr <= 1'b0;
    end
  endtask
  task b_read(input [8:0] ad);
    begin
      @(posedge clk); b_addr <= ad; b_rd <= 1'b1;
      @(posedge clk); b_rd <= 1'b0;
      while (!b_rvalid) @(posedge clk);
      rv = b_rdata;
    end
  endtask
  task b_write(input [8:0] ad, input [31:0] d);
    begin
      @(posedge clk); b_addr <= ad; b_wdata <= d; b_wr <= 1'b1;
      @(posedge clk); b_wr <= 1'b0;
    end
  endtask

  localparam [8:0] VERSION = 9'o000, STATUS = 9'o004, RXDATA = 9'o010,
                   TXDATA = 9'o014, ERRS = 9'o020;

  reg [8*40:1] msg;
  reg [7:0]    got[0:63];
  integer i, n, tries, bad;

  initial begin
    msg = "SINTRAN III - VSX/500 M   @ echo test 42";
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);

    // ---------------- (1) ----------------
    $display("(1) VERSION");
    a_read(VERSION);
    check(rv == {8'd0, 8'd1, 16'd1}, "VERSION must be kind 1, layout 1");

    // ---------------- (2) ----------------
    $display("(2) empty queues");
    a_read(RXDATA);
    check(rv[8] == 1'b0, "RXDATA on an empty queue must have bit 8 clear");
    a_read(STATUS);
    check(rv[15:0] == 16'd0, "STATUS: nothing waiting");
    check(rv[31:16] == 16'd512, "STATUS: all 512 places free");

    // ---------------- (3) ----------------
    $display("(3) 40 characters through the serial loop");
    for (i = 0; i < 40; i = i + 1) a_write(TXDATA, {24'd0, msg[8*(40-i) -: 8]});
    a_read(STATUS);
    check(rv[31:16] <= 16'd512 - 16'd38, "STATUS: the written bytes occupy the queue");
    n = 0; tries = 0;
    while ((n < 40) && (tries < 200000)) begin
      a_read(RXDATA);
      if (rv[8]) begin got[n] = rv[7:0]; n = n + 1; end
      tries = tries + 1;
    end
    check(n == 40, "all 40 characters must come back");
    bad = 0;
    for (i = 0; i < n; i = i + 1) if (got[i] != msg[8*(40-i) -: 8]) bad = bad + 1;
    check(bad == 0, "characters must come back unchanged and in order");
    a_read(STATUS);
    check(rv == {16'd512, 16'd0}, "STATUS after the loop: empty both ways");
    a_read(ERRS);
    check(rv == 32'd0, "no error bits after a clean run");

    // ---------------- (4) ----------------
    $display("(4) PC -> ND queue full");
    b_to_ready = 0;                              // transmitter "busy": nothing drains
    for (i = 0; i < 9; i = i + 1) b_write(TXDATA, 8'o101 + i);  // 9 into 8 places
    b_read(STATUS);
    check(rv[31:16] == 16'd0, "STATUS: no place free");
    b_read(ERRS);
    check(rv[1] == 1'b1, "ERRS[1] must be set by the dropped write");
    check(rv[0] == 1'b0, "ERRS[0] must not be set by a TXDATA problem");
    b_to_ready = 1;                              // let it drain
    tries = 0;
    while ((b_nseen < 8) && (tries < 1000)) begin @(posedge clk); tries = tries + 1; end
    repeat (20) @(posedge clk);
    check(b_nseen == 8, "exactly the 8 queued bytes reach the ND side");
    bad = 0;
    for (i = 0; i < 8; i = i + 1) if (b_seen[i] != 8'o101 + i) bad = bad + 1;
    check(bad == 0, "queued bytes reach the ND in order, the 9th is the one dropped");

    // ---------------- (5) ----------------
    $display("(5) ND -> PC overflow");
    for (i = 0; i < 10; i = i + 1) begin
      @(posedge clk); b_nd_valid <= 1'b1; b_nd_data <= 8'o141 + i;
      @(posedge clk); b_nd_valid <= 1'b0;
    end
    b_read(STATUS);
    check(rv[15:0] == 16'd8, "STATUS: 8 bytes waiting");
    b_read(ERRS);
    check(rv[0] == 1'b1, "ERRS[0] must be set by the lost bytes");
    bad = 0;
    for (i = 0; i < 8; i = i + 1) begin
      b_read(RXDATA);
      if (rv != {23'd0, 1'b1, 8'o141 + i[7:0]}) bad = bad + 1;
    end
    check(bad == 0, "the queue keeps the FIRST 8 bytes, in order");
    b_read(RXDATA);
    check(rv[8] == 1'b0, "and then it is empty");

    // ---------------- (6) ----------------
    $display("(6) ERRS clear");
    b_write(ERRS, 32'd1);
    b_read(ERRS);
    check(rv[1:0] == 2'b10, "writing 1 to bit 0 clears only bit 0");
    b_write(ERRS, 32'd2);
    b_read(ERRS);
    check(rv[1:0] == 2'b00, "writing 1 to bit 1 clears bit 1");

    // ---------------- (7) ----------------
    $display("(7) unused offset");
    b_read(9'o400 - 9'o004);
    check(rv == 32'd0, "unused offset reads 0");

    if (errors == 0) $display("TB_RESULT: PASS");
    else             $display("TB_RESULT: FAIL (%0d)", errors);
    $finish;
  end

  initial begin
    #20_000_000;
    $display("TB_RESULT: FAIL (watchdog)");
    $finish;
  end

endmodule
