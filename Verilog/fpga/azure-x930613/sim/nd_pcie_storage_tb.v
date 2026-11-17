/*****************************************************************************
**  nd_pcie_storage_tb.v                                                    **
**                                                                          **
**  Path: Verilog/fpga/azure-x930613/sim/nd_pcie_storage_tb.v               **
**                                                                          **
**  The Azure disk path end to end, from the ND storage client port to the  **
**  image file on the PC:                                                   **
**    client checks -> nd_storage_hps (MiSTer, unchanged)                   **
**                  -> nd_pcie_storage (../rtl, the new block)              **
**                  -> pc_storage_model (the PC program, over the BAR bus)  **
**  The checks are those of fpga/mister/sim/nd_storage_hps_tb.v, copied     **
**  with the HPS model replaced, so both boards are held to the same rules: **
**   (1) unmounted slot -> NOTOPEN at once, the PC never sees a request     **
**   (2) open_req / open_ok / open_err / size_bytes follow the mount        **
**   (3) read a block: 1024 words, in order, big-endian pairs of the file   **
**   (4) write a block: the file holds the words big-endian; read back      **
**   (5) write to read-only -> WRPROT, no PC traffic                        **
**   (6) past EOF -> RANGE, no PC traffic                                   **
**   (7) two clients at once: both complete, no cross-talk                  **
**   (8) unmount: NOTOPEN again, other mounts survive                       **
**  Plus the PC model's rule counter (LBA moved, request left up after      **
**  START, ERRS set) must end at zero. The PCIe clock is 125 MHz here.      **
**                                                                          **
**  Verdict: TB_RESULT: PASS / TB_RESULT: FAIL                              **
*****************************************************************************/

`timescale 1ns / 1ps
`include "nd_storage_status.vh"

module nd_pcie_storage_tb;

  localparam integer N = 5;
  localparam integer IMG = 65536;

  integer errors = 0;

  reg clk_cpu = 0;
  reg clk_sys = 0;
  always #25.0 clk_cpu = ~clk_cpu;   // 20 MHz
  always #4 clk_sys = ~clk_sys;      // 125 MHz, the PCIe user clock
  initial #7 forever #12.5 ;        // (phase offset lives in the first edge)

  reg rst_n = 0;

  // ---- client side ---------------------------------------------------------
  reg  [N-1:0]    open_req = 0;
  wire [N-1:0]    open_ok, open_err, busy, done, err, buf_we;
  wire [N*32-1:0] size_bytes;
  reg  [N-1:0]    req = 0, wr = 0;
  reg  [N*16-1:0] block = 0;
  wire [N*4-1:0]  err_code;
  wire [N*10-1:0] buf_addr;
  wire [N*16-1:0] buf_wdata;
  reg  [N*16-1:0] buf_rdata;
  wire [N-1:0]    mounted;

  // ---- hps side -----------------------------------------------------------
  wire [N-1:0]    img_mounted;
  wire            img_readonly;
  wire [63:0]     img_size;
  wire [N*32-1:0] sd_lba;
  wire [N*6-1:0]  sd_blk_cnt;
  wire [N-1:0]    sd_rd, sd_wr, sd_ack;
  wire [12:0]     sd_buff_addr;
  wire [15:0]     sd_buff_dout, sd_buff_din;
  wire            sd_buff_wr;
  integer         n_reads, n_writes, violations;

  nd_storage_hps #(.N_CLIENTS(N), .BYTE_SWAP(1)) dut (
      .clk_cpu(clk_cpu), .rst_cpu_n(rst_n),
      .open_req(open_req), .open_ok(open_ok), .open_err(open_err), .size_bytes(size_bytes),
      .req(req), .wr(wr), .block(block), .busy(busy), .done(done), .err(err), .err_code(err_code),
      .buf_addr(buf_addr), .buf_wdata(buf_wdata), .buf_we(buf_we), .buf_rdata(buf_rdata),
      .clk_sys(clk_sys), .rst_sys_n(rst_n),
      .img_mounted(img_mounted), .img_readonly(img_readonly), .img_size(img_size),
      .sd_lba(sd_lba), .sd_blk_cnt(sd_blk_cnt), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack),
      .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din),
      .sd_buff_wr(sd_buff_wr),
      .mounted(mounted)
  );

  // the new block, and the PC program on its register bus
  wire [8:0]  bus_addr;
  wire        bus_wr, bus_rd, bus_rvalid, bus_busy;
  wire [31:0] bus_wdata, bus_rdata;

  nd_pcie_storage #(.N_SLOTS(N)) blk (
      .clk(clk_sys), .rst_n(rst_n),
      .addr(bus_addr), .wr(bus_wr), .wdata(bus_wdata), .rd(bus_rd),
      .rdata(bus_rdata), .rvalid(bus_rvalid), .busy(bus_busy),
      .img_mounted(img_mounted), .img_readonly(img_readonly), .img_size(img_size),
      .sd_lba(sd_lba), .sd_blk_cnt(sd_blk_cnt), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack),
      .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din),
      .sd_buff_wr(sd_buff_wr)
  );

  pc_storage_model #(.VDNUM(N), .IMG_BYTES(IMG)) pc (
      .clk(clk_sys),
      .addr(bus_addr), .wr(bus_wr), .wdata(bus_wdata), .rd(bus_rd),
      .rdata(bus_rdata), .rvalid(bus_rvalid),
      .n_reads(n_reads), .n_writes(n_writes), .violations(violations)
  );

  // ---- the client buffers: one 1024x16 per client, registered read like ----
  // every adapter (c_buf_rdata <= buf[c_buf_addr])
  reg [15:0] cbuf[0:N*1024-1];
  integer c, expect_addr[0:N-1], we_count[0:N-1], order_ok[0:N-1];
  always @(posedge clk_cpu) begin
    for (c = 0; c < N; c = c + 1) begin
      buf_rdata[c*16 +: 16] <= cbuf[c*1024 + buf_addr[c*10 +: 10]];
      if (buf_we[c]) begin
        cbuf[c*1024 + buf_addr[c*10 +: 10]] <= buf_wdata[c*16 +: 16];
        if (buf_addr[c*10 +: 10] != expect_addr[c]) order_ok[c] = 0;
        expect_addr[c] = expect_addr[c] + 1;
        we_count[c]    = we_count[c] + 1;
      end
    end
  end

  // PC-side traffic seen while a test expects none
  integer rd_seen, wr_seen;
  always @(posedge clk_sys) begin
    if (|sd_rd) rd_seen = rd_seen + 1;
    if (|sd_wr) wr_seen = wr_seen + 1;
  end

  // ---- helpers ---------------------------------------------------------------
  task check(input cond, input [1023:0] what);
    begin
      if (!cond) begin
        errors = errors + 1;
        $display("  FAIL: %0s", what);
      end
    end
  endtask

  // issue one request on client cl and wait for its done; returns err+code
  reg        r_err;
  reg [3:0]  r_code;
  integer    r_cycles;
  task op(input integer cl, input is_wr, input [15:0] blk);
    begin
      for (c = 0; c < N; c = c + 1) begin
        expect_addr[c] = 0; we_count[c] = 0; order_ok[c] = 1;
      end
      @(posedge clk_cpu);
      req[cl]           <= 1'b1;
      wr[cl]            <= is_wr;
      block[cl*16 +: 16] <= blk;
      @(posedge clk_cpu);
      req[cl] <= 1'b0;
      r_cycles = 0;
      while (!done[cl] && (r_cycles < 200000)) begin
        @(posedge clk_cpu);
        r_cycles = r_cycles + 1;
      end
      r_err  = err[cl];
      r_code = err_code[cl*4 +: 4];
      check(done[cl], "operation never completed (done-never)");
      @(posedge clk_cpu);
    end
  endtask

  // fill slot s of the model's file with a recognisable byte pattern
  task fill_image(input integer s, input [7:0] seed);
    integer b;
    begin
      for (b = 0; b < IMG; b = b + 1) pc.img[s*IMG + b] = seed ^ b[7:0] ^ b[15:8];
    end
  endtask

  // expected ND word w of block blk of slot s: big-endian pair
  function [15:0] exp_word(input integer s, input [15:0] blk, input integer w);
    begin
      exp_word = {pc.img[s*IMG + blk*2048 + 2*w], pc.img[s*IMG + blk*2048 + 2*w + 1]};
    end
  endfunction

  integer w, bad;

  initial begin
    for (c = 0; c < N; c = c + 1) begin
      expect_addr[c] = 0; we_count[c] = 0; order_ok[c] = 1;
    end
    for (w = 0; w < N*1024; w = w + 1) cbuf[w] = 16'h0000;
    rd_seen = 0; wr_seen = 0;
    buf_rdata = 0;

    repeat (5) @(posedge clk_cpu);
    rst_n = 1;
    repeat (10) @(posedge clk_cpu);

    // ---------------- (1) unmounted slot ----------------------------------
    $display("(1) request on an unmounted slot");
    rd_seen = 0; wr_seen = 0;
    op(0, 1'b0, 16'd0);
    check(r_err && (r_code == `NDS_ERR_NOTOPEN), "unmounted read must be err NOTOPEN");
    check(r_cycles < 50, "unmounted read must complete immediately");
    check((rd_seen == 0) && (wr_seen == 0), "unmounted read must not reach the PC");
    check(we_count[0] == 0, "unmounted read must move no data");

    // ---------------- (2) open semantics -----------------------------------
    $display("(2) open_req / open_ok / open_err / size_bytes");
    @(posedge clk_cpu); open_req[0] <= 1'b1; @(posedge clk_cpu); open_req[0] <= 1'b0;
    repeat (4) @(posedge clk_cpu);
    check(!open_ok[0] && open_err[0], "open of an unmounted slot must be open_err");
    fill_image(0, 8'hA5);
    pc.mount(0, 32'd16384, 1'b0);
    repeat (8) @(posedge clk_cpu);
    check(open_ok[0] && !open_err[0], "after mount: open_ok, not open_err");
    check(size_bytes[31:0] == 32'd16384, "size_bytes must be the mounted size");
    check(mounted[0] && !mounted[1], "mounted flag per slot");

    // ---------------- (3) read a block ---------------------------------------
    $display("(3) read block 3 of slot 0");
    op(0, 1'b0, 16'd3);
    check(!r_err, "read must not err");
    check(we_count[0] == 1024, "read must deliver exactly 1024 words");
    check(order_ok[0] == 1, "read words must arrive at addresses 0..1023 in order");
    bad = 0;
    for (w = 0; w < 1024; w = w + 1)
      if (cbuf[w] != exp_word(0, 16'd3, w)) bad = bad + 1;
    check(bad == 0, "read data must be the file's bytes as big-endian words");
    if (bad) $display("  first words got %04x %04x expected %04x %04x",
                      cbuf[0], cbuf[1], exp_word(0, 16'd3, 0), exp_word(0, 16'd3, 1));
    check(we_count[1] == 0, "no other client may receive data");
    check(n_reads == 1, "exactly one PC read transaction");
    check(sd_lba[31:0] == 32'd12, "sd_lba must be block*4");
    check(sd_blk_cnt[5:0] == 6'd3, "sd_blk_cnt must be 3 (4 x 512 bytes)");

    // ---------------- (4) write a block ------------------------------------
    $display("(4) write block 5 of slot 0");
    for (w = 0; w < 1024; w = w + 1) cbuf[w] = 16'h3000 + w;
    op(0, 1'b1, 16'd5);
    check(!r_err, "write must not err");
    check(n_writes == 1, "exactly one PC write transaction");
    bad = 0;
    for (w = 0; w < 1024; w = w + 1)
      if (exp_word(0, 16'd5, w) != (16'h3000 + w)) bad = bad + 1;
    check(bad == 0, "written file bytes must be the client's words, big-endian");
    if (bad) $display("  file has %02x%02x %02x%02x expected 3000 3001",
                      pc.img[5*2048], pc.img[5*2048+1], pc.img[5*2048+2], pc.img[5*2048+3]);
    // and read it back through the whole path
    for (w = 0; w < 1024; w = w + 1) cbuf[w] = 16'h0000;
    op(0, 1'b0, 16'd5);
    bad = 0;
    for (w = 0; w < 1024; w = w + 1) if (cbuf[w] != (16'h3000 + w)) bad = bad + 1;
    check(bad == 0, "write then read must round-trip");

    // ---------------- (5) read-only mount ----------------------------------
    $display("(5) write to a read-only mount");
    fill_image(1, 8'h5C);
    pc.mount(1, 32'd8192, 1'b1);
    repeat (8) @(posedge clk_cpu);
    rd_seen = 0; wr_seen = 0;
    op(1, 1'b1, 16'd0);
    check(r_err && (r_code == `NDS_ERR_WRPROT), "write to read-only must be WRPROT");
    check(wr_seen == 0, "write to read-only must not reach the PC");
    op(1, 1'b0, 16'd1);
    check(!r_err, "read of a read-only mount must work");
    bad = 0;
    for (w = 0; w < 1024; w = w + 1) if (cbuf[1024 + w] != exp_word(1, 16'd1, w)) bad = bad + 1;
    check(bad == 0, "read-only read data");

    // ---------------- (6) range -------------------------------------------
    $display("(6) range checks");
    rd_seen = 0; wr_seen = 0;
    op(1, 1'b0, 16'd4);                     // 8192 bytes = blocks 0..3
    check(r_err && (r_code == `NDS_ERR_RANGE), "read past EOF must be RANGE");
    check(rd_seen == 0, "read past EOF must not reach the PC");
    pc.mount(2, 32'd5000, 1'b0);            // 2.44 blocks: block 2 is partial
    repeat (8) @(posedge clk_cpu);
    op(2, 1'b1, 16'd2);
    check(r_err && (r_code == `NDS_ERR_RANGE), "write of a partial tail block must be RANGE");
    check(wr_seen == 0, "refused write must not reach the PC");
    op(2, 1'b1, 16'd1);
    check(!r_err, "write of a whole block inside the file is fine");

    // ---------------- (7) two clients at once -------------------------------
    $display("(7) two clients in the same cycle");
    fill_image(3, 8'h11);
    fill_image(4, 8'hEE);
    pc.mount(3, 32'd32768, 1'b0);
    pc.mount(4, 32'd32768, 1'b0);
    repeat (8) @(posedge clk_cpu);
    for (c = 0; c < N; c = c + 1) begin expect_addr[c] = 0; we_count[c] = 0; order_ok[c] = 1; end
    @(posedge clk_cpu);
    req[3] <= 1'b1; wr[3] <= 1'b0; block[3*16 +: 16] <= 16'd7;
    req[4] <= 1'b1; wr[4] <= 1'b0; block[4*16 +: 16] <= 16'd9;
    @(posedge clk_cpu);
    req[3] <= 1'b0; req[4] <= 1'b0;
    @(posedge clk_cpu);   // let the nonblocking latch land before looking
    check(busy[3] && busy[4], "both requests latched (busy)");
    r_cycles = 0;
    begin : wait2
      reg d3, d4;
      d3 = 0; d4 = 0;
      while (!(d3 && d4) && (r_cycles < 400000)) begin
        @(posedge clk_cpu);
        if (done[3]) begin d3 = 1; check(!err[3], "client 3 read errs"); end
        if (done[4]) begin d4 = 1; check(!err[4], "client 4 read errs"); end
        r_cycles = r_cycles + 1;
      end
      check(d3 && d4, "both clients must complete");
    end
    check((we_count[3] == 1024) && (we_count[4] == 1024), "both get 1024 words");
    check(order_ok[3] && order_ok[4], "both in order");
    bad = 0;
    for (w = 0; w < 1024; w = w + 1) begin
      if (cbuf[3*1024 + w] != exp_word(3, 16'd7, w)) bad = bad + 1;
      if (cbuf[4*1024 + w] != exp_word(4, 16'd9, w)) bad = bad + 1;
    end
    check(bad == 0, "each client got ITS file's block, no cross-talk");

    // ---------------- (8) unmount ----------------------------------------
    $display("(8) unmount");
    pc.unmount(0);
    repeat (8) @(posedge clk_cpu);
    check(!open_ok[0] && !mounted[0], "unmount must drop open_ok");
    rd_seen = 0;
    op(0, 1'b0, 16'd0);
    check(r_err && (r_code == `NDS_ERR_NOTOPEN), "read after unmount must be NOTOPEN");
    check(rd_seen == 0, "read after unmount must not reach the PC");
    // other slots unaffected
    check(open_ok[1] && open_ok[3], "other mounts survive an unmount");

    // ---------------- model rules --------------------------------------------
    check(violations == 0, "PC model rules violated (see PC MODEL lines)");

    if (errors == 0) $display("TB_RESULT: PASS");
    else             $display("TB_RESULT: FAIL (%0d)", errors);
    $finish;
  end

  // global watchdog
  initial begin
    #200_000_000;
    $display("TB_RESULT: FAIL (watchdog)");
    $finish;
  end

endmodule
