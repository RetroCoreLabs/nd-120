//============================================================================
//! Full-machine boot test for the Azure card top (Verilator --timing)
//!
//! Path: Verilog/fpga/azure-x930613/sim/nd120_azure_top_tb.v
//! Run:  make -C Verilog/fpga/azure-x930613/sim vtest   (runs vtest.sh)
//!
//! The whole Azure machine - CPU, 3202D board in its 2 MB form with block-RAM
//! main memory, the console and disk blocks, the PCIe window split, the
//! PCIe wrapper's simulation version - booted, with this bench playing the
//! PC. The bench sees the console ONLY through the PCIe registers, exactly
//! as the PC program will (docs/00-plan.md, steps V4 and V6).
//!
//! THE ORACLE is MOPC itself, as in the MEGA65 and Tang machine benches: it
//! prints a '#' prompt once the CPU is up, and a RETURN typed at that prompt
//! makes it print a fresh '#'. So the pass criterion is "the CPU answered
//! through the PCIe console both ways", not "a byte moved".
//!   step 1  a '#' arrives on the console queue (CPU -> PC works)
//!   step 2  RETURN written to the console queue gets a new '#' back
//!           (PC -> CPU works, and MOPC is alive)
//! Also checked at the end: the console's error bits are 0 (no byte lost in
//! either direction).
//!
//! Clocks: clk_cpu 20 MHz (as the MEGA65 R6 and MiSTer), the PCIe side
//! 125 MHz (the PCIE_CLK_HZ default of the top).
//!
//! Prints "TB_RESULT: PASS" or "TB_RESULT: FAIL".
//============================================================================

`timescale 1ns / 1ps
`default_nettype none

module nd120_azure_top_tb;

  reg clk_cpu = 1'b0;  always #25.000 clk_cpu = ~clk_cpu;   // 20 MHz
  reg clk_pc  = 1'b0;  always #4.000  clk_pc  = ~clk_pc;    // 125 MHz

  reg rst_n = 1'b0;

  reg  [11:0] p_addr = 12'd0;
  reg         p_wr = 1'b0, p_rd = 1'b0;
  reg  [31:0] p_wdata = 32'd0;
  wire [31:0] p_rdata;
  wire        p_rvalid, p_busy;
  wire [7:0]  pcie_tx;
  wire [6:0]  led;
  wire        run_n;

  nd120_azure_top #(.PCIE_CLK_HZ(125_000_000)) DUT (
      .clk_cpu     (clk_cpu),
      .cpu_rst_n   (rst_n),
      .pcie_refclk (1'b0),
      .pcie_perst_n(1'b1),
      .pcie_rx     (8'd0),
      .pcie_tx     (pcie_tx),
      .LED         (led),
      .RUN_n       (run_n),
      .sim_clk     (clk_pc),
      .sim_rst_n   (rst_n),
      .sim_addr    (p_addr),
      .sim_wr      (p_wr),
      .sim_wdata   (p_wdata),
      .sim_rd      (p_rd),
      .sim_rdata   (p_rdata),
      .sim_rvalid  (p_rvalid),
      .sim_busy    (p_busy)
  );

  // ---- the PC's register access ------------------------------------------
  reg [31:0] rv;
  task pread(input [11:0] a);
    begin
      @(posedge clk_pc); p_addr <= a; p_rd <= 1'b1;
      @(posedge clk_pc); p_rd <= 1'b0;
      while (!p_rvalid) @(posedge clk_pc);
      rv = p_rdata;
    end
  endtask
  task pwrite(input [11:0] a, input [31:0] d);
    begin
      @(posedge clk_pc); p_addr <= a; p_wdata <= d; p_wr <= 1'b1;
      @(posedge clk_pc); p_wr <= 1'b0;
    end
  endtask

  localparam [11:0] CON_VERSION = 12'o0000, CON_RXDATA = 12'o0010,
                    CON_TXDATA = 12'o0014, CON_ERRS = 12'o0020;

  // ---- the PC program's console loop: drain the queue, echo to the log ----
  integer rx_count = 0;
  integer hash_count = 0;
  reg     pc_stop = 1'b0;
  reg     pc_busy = 1'b0;   // the main block uses the bus only while this is low
  reg     want_cr = 1'b0;

  initial begin : pc_loop
    wait (rst_n);
    repeat (20) @(posedge clk_pc);
    while (!pc_stop) begin
      pc_busy = 1'b1;
      if (want_cr) begin
        pwrite(CON_TXDATA, 32'o15);       // RETURN
        want_cr = 1'b0;
      end
      pread(CON_RXDATA);
      pc_busy = 1'b0;
      if (rv[8]) begin
        rx_count = rx_count + 1;
        if (rv[7:0] == 8'o43) hash_count = hash_count + 1;
        if (rv[7:0] >= 8'o40 && rv[7:0] < 8'o177) $write("%c", rv[7:0]);
        else $write("<%03o>", rv[7:0]);
        $fflush;
      end else begin
        repeat (200) @(posedge clk_pc);   // nothing waiting: poll again later
      end
    end
  end

  integer errors = 0;
  integer t, hashes_before;

  initial begin
    $display("TB: Azure top, 2 MB block-RAM main memory, console over the simulated PCIe window");
    #1000;
    rst_n = 1'b1;

    // the window answers at all
    wait (!pc_busy);
    $display("TB: booting (waiting for '#')...");

    t = 0;
    while (hash_count == 0 && t < 60_000) begin   // 60000 x 100 us = 6 s
      #100_000;
      t = t + 1;
    end
    if (hash_count == 0) begin
      $display("");
      $display("FAIL: no OPCOM prompt within 6 s (RUN_n=%0d, %0d console bytes)", run_n, rx_count);
      $display("TB_RESULT: FAIL (no prompt)");
      $finish;
    end
    $display("");
    $display("TB: OPCOM prompt seen after %0d x 100 us (%0d bytes so far)", t, rx_count);

    // let the prompt line settle, then type RETURN through the PCIe console
    #20_000_000;
    hashes_before = hash_count;
    want_cr = 1'b1;
    t = 0;
    while (hash_count == hashes_before && t < 5_000) begin   // 0.5 s
      #100_000;
      t = t + 1;
    end
    $display("");
    if (hash_count == hashes_before) begin
      $display("FAIL: RETURN typed through the PCIe console got no new '#'");
      errors = errors + 1;
    end else begin
      $display("TB: RETURN answered with a new '#' after %0d x 100 us", t);
    end

    pc_stop = 1'b1;
    #10_000;
    pread(CON_ERRS);
    if (rv[1:0] != 2'b00) begin
      $display("FAIL: console error bits = %0b (bytes were lost)", rv[1:0]);
      errors = errors + 1;
    end

    if (errors == 0) $display("TB_RESULT: PASS");
    else             $display("TB_RESULT: FAIL (%0d)", errors);
    $finish;
  end

endmodule

`default_nettype wire
