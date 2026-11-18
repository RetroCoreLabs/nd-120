//============================================================================
//! Full-machine FLOPPY BOOT test for the Azure card top (Verilator --timing)
//!
//! Path: Verilog/fpga/azure-x930613/sim/nd120_azure_disk_tb.v
//! Run:  make -C Verilog/fpga/azure-x930613/sim vtest-disk  (vtest.sh disk)
//!
//! The bench plays the PC with BOTH of its jobs on the one PCIe window:
//!   - pc_storage_model serves a floppy image on slot 0 (floppy drive 0)
//!     through nd_pcie_storage, as the PC program will;
//!   - the console loop reads the console queue and types commands.
//! They share the bus through the model's hold/idle handshake, so only one
//! of them drives it at a time (one PC program, two jobs).
//!
//! THE IMAGE is the one the runSim floppy gate uses (tests/gen_fboot_img.py,
//! made by vtest.sh): a minimal BPUN boot stream whose program, loaded at
//! 0o2000, stores 0o77 at 0o2012 and stops (SAA 77 / STA +11 / WAIT).
//!
//! PASS needs all of:
//!   1  MOPC's '#' arrives through the PCIe console;
//!   2  '1560&' (boot from floppy) is typed through it;
//!   3  the PC model served at least one read on slot 0 - the CPU's floppy
//!      controller really asked the PC for the image;
//!   4  main memory then holds the program at 0o2000..0o2002 and 0o77 at
//!      0o2012 - the image's code was loaded AND executed;
//!   5  the model saw no protocol violation and the console lost no byte.
//!
//! Prints "TB_RESULT: PASS" or "TB_RESULT: FAIL".
//============================================================================

`timescale 1ns / 1ps
`default_nettype none

module nd120_azure_disk_tb;

  reg clk_cpu = 1'b0;  always #25.000 clk_cpu = ~clk_cpu;   // 20 MHz
  reg clk_pc  = 1'b0;  always #4.000  clk_pc  = ~clk_pc;    // 125 MHz

  reg rst_n = 1'b0;

  wire [11:0] p_addr;
  wire        p_wr, p_rd;
  wire [31:0] p_wdata;
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

  // ---- the two jobs and who owns the bus ----------------------------------
  wire [8:0]  m_addr;
  wire        m_wr, m_rd;
  wire [31:0] m_wdata;
  wire        m_idle;
  integer     n_reads, n_writes, violations;
  // held from time 0: the model must not touch the bus while the PCIe side
  // is still in reset (a read then never gets its rvalid)
  reg         hold = 1'b1;

  reg  [11:0] c_addr = 12'd0;
  reg         c_wr = 1'b0, c_rd = 1'b0;
  reg  [31:0] c_wdata = 32'd0;

  // slot 0 image: 64 KB is plenty - the boot stream is in block 0, and the
  // model answers 0 past the end of its array
  localparam integer IMG_BYTES = 65536;

  pc_storage_model #(.VDNUM(5), .IMG_BYTES(IMG_BYTES), .POLL_CYCLES(40)) PC (
      .clk       (clk_pc),
      .addr      (m_addr),
      .wr        (m_wr),
      .wdata     (m_wdata),
      .rd        (m_rd),
      .rdata     (p_rdata),
      .rvalid    (p_rvalid),
      .hold      (hold),
      .idle      (m_idle),
      .n_reads   (n_reads),
      .n_writes  (n_writes),
      .violations(violations)
  );

  // console region 0o0000, disk region 0o1000 (pcie_bar_bus)
  wire console_owns = hold && m_idle;
  assign p_addr  = console_owns ? c_addr  : {3'b001, m_addr};
  assign p_wr    = console_owns ? c_wr    : m_wr;
  assign p_rd    = console_owns ? c_rd    : m_rd;
  assign p_wdata = console_owns ? c_wdata : m_wdata;

  reg [31:0] rv;
  task take_bus;
    begin
      hold = 1'b1;
      wait (m_idle);
      @(posedge clk_pc);
    end
  endtask
  task give_bus;
    begin
      @(posedge clk_pc);
      hold = 1'b0;
      wait (!m_idle);
    end
  endtask
  task pread(input [11:0] a);
    begin
      @(posedge clk_pc); c_addr <= a; c_rd <= 1'b1;
      @(posedge clk_pc); c_rd <= 1'b0;
      while (!p_rvalid) @(posedge clk_pc);
      rv = p_rdata;
    end
  endtask
  task pwrite(input [11:0] a, input [31:0] d);
    begin
      @(posedge clk_pc); c_addr <= a; c_wdata <= d; c_wr <= 1'b1;
      @(posedge clk_pc); c_wr <= 1'b0;
    end
  endtask

  localparam [11:0] CON_RXDATA = 12'o0010, CON_TXDATA = 12'o0014, CON_ERRS = 12'o0020;

  // ---- console job: drain the queue, type what 'to_type' holds ------------
  integer rx_count = 0, hash_count = 0;
  reg     con_stop = 1'b0;
  reg [8*8-1:0] to_type;
  integer n_to_type = 0, k;

  initial begin : console_loop
    wait (rst_n);
    repeat (20) @(posedge clk_pc);
    while (!con_stop) begin
      take_bus;
      if (n_to_type > 0) begin
        // one character per pass, MOPC reads slower than we can type
        pwrite(CON_TXDATA, {24'd0, to_type[8*n_to_type-1 -: 8]});
        n_to_type = n_to_type - 1;
      end
      pread(CON_RXDATA);
      give_bus;
      if (rv[8]) begin
        rx_count = rx_count + 1;
        if (rv[7:0] == 8'o43) hash_count = hash_count + 1;
        if (rv[7:0] >= 8'o40 && rv[7:0] < 8'o177) $write("%c", rv[7:0]);
        else $write("<%03o>", rv[7:0]);
        $fflush;
      end else begin
        repeat (2000) @(posedge clk_pc);
      end
    end
  end

  // ---- the test -------------------------------------------------------------
  integer errors = 0;
  integer t;
  reg [15:0] w0, w1, w2, w10;

  initial begin
    $display("TB: Azure top, floppy boot from a PC-served image (slot 0)");
    $readmemh("fboot.hex", PC.img, 0, IMG_BYTES - 1);
    #1000;
    rst_n = 1'b1;
    repeat (4) @(posedge clk_pc);
    hold = 1'b0;          // the PC side is out of reset: the model may run

    // mount: the image's full size, so the floppy adapter sees the real format
    PC.mount(0, 32'd1261568, 1'b1);
    $display("TB: image mounted on slot 0");

    t = 0;
    while (hash_count == 0 && t < 60_000) begin   // 6 s
      #100_000;
      t = t + 1;
    end
    if (hash_count == 0) begin
      $display("FAIL: no OPCOM prompt within 6 s (%0d console bytes)", rx_count);
      $display("TB_RESULT: FAIL (no prompt)");
      $finish;
    end
    $display("");
    $display("TB: OPCOM prompt seen after %0d x 100 us; typing 1560&", t);
    #20_000_000;
    to_type   = "1560&";
    n_to_type = 5;

    // wait for the program to have run: its store lands at 0o2012
    t = 0;
    while (DUT.CORE.CPU_BOARD.MEM.RAM.mem[20'o2012] != 16'o77 && t < 30_000) begin   // 3 s
      #100_000;
      t = t + 1;
    end
    $display("");
    $display("TB: %0d floppy read(s) served by the PC, %0d write(s)", n_reads, n_writes);

    w0  = DUT.CORE.CPU_BOARD.MEM.RAM.mem[20'o2000];
    w1  = DUT.CORE.CPU_BOARD.MEM.RAM.mem[20'o2001];
    w2  = DUT.CORE.CPU_BOARD.MEM.RAM.mem[20'o2002];
    w10 = DUT.CORE.CPU_BOARD.MEM.RAM.mem[20'o2012];
    $display("TB: RAM @002000: %06o %06o %06o, @002012: %06o", w0, w1, w2, w10);

    if (n_reads == 0) begin
      $display("FAIL: the floppy controller never asked the PC for a block");
      errors = errors + 1;
    end
    if (w0 != 16'o170477 || w1 != 16'o004011 || w2 != 16'o151000) begin
      $display("FAIL: the boot program is not in memory at 0o2000");
      errors = errors + 1;
    end
    if (w10 != 16'o77) begin
      $display("FAIL: 0o2012 is not 0o77 - the loaded program did not run");
      errors = errors + 1;
    end
    if (violations != 0) begin
      $display("FAIL: %0d PC-side protocol violations", violations);
      errors = errors + 1;
    end

    con_stop = 1'b1;
    #200_000;
    take_bus;
    pread(CON_ERRS);
    give_bus;
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
