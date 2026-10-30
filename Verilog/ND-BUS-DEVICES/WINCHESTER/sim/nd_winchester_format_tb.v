/*****************************************************************************
**  nd_winchester_format_tb.v                                               **
**                                                                          **
**  WRITE FORMAT (M5) DATA SIDE, against nd100x device_winchester.c         **
**  WD_OP_WRITE_FORMAT:                                                     **
**                                                                          **
**   - the address fields are DMA-read from memory, two words per sector,   **
**     for word count / 2 sectors, at most one track (9 sectors here);      **
**   - the memory address moves on by the words read and the word count    **
**     goes down by them; the block address stays;                          **
**   - the arm's cylinder is NOT checked (M5 formats the track under the    **
**     arm), but a block address outside the drive is an address mismatch   **
**     (b8) that ends later, with no memory cycle and the registers left as **
**     loaded;                                                              **
**   - a failed field read ends the format with DMA channel error b11 and   **
**     the registers left as loaded;                                        **
**   - a word count of 0 reads nothing and ends normally.                   **
**                                                                          **
**  The fields themselves are not kept (no address-field table, nd100x      **
**  BUGS.md W2; Verilog/TODO.md), so nothing here checks a later transfer   **
**  against them.                                                           **
**                                                                          **
**  The word count register is write-only on this card, so the bench reads  **
**  it from the DUT (dut.s_word_cnt); the memory address and the block      **
**  address are read through +0 and +6 as a guest would.                    **
*****************************************************************************/

`timescale 1ns / 1ps

module nd_winchester_format_tb;

  localparam [15:0] BASE      = 16'o000500;
  localparam R_MEMADDR = 16'd0;
  localparam R_LOADADR = 16'd1;
  localparam R_BLOCK   = 16'd3;
  localparam R_STATUS  = 16'd4;
  localparam R_CONTROL = 16'd5;
  localparam R_BLKRD   = 16'd6;
  localparam R_WORDCNT = 16'd7;

  // GO (b2) with M5 (b11-13 = 5), head 0, unit 0.
  localparam [15:0] CW_FORMAT = 16'o024004;
  localparam [15:0] CW_CLEAR  = 16'o000020;

  // Memory address 03 040000 (HI 003, LO 040000).
  localparam [15:0] LOAD_HI = 16'o000003;
  localparam [15:0] LOAD_LO = 16'o040000;
  localparam [23:0] START   = {8'o003, 16'o040000};

  reg sysclk = 0;
  reg sys_rst_n = 0;
  always #10 sysclk = ~sysclk;

  reg  [15:0] iox_addr  = 16'd0;
  reg         iox_wr    = 1'b0;
  reg  [15:0] iox_wdata = 16'd0;
  reg         iox_rd    = 1'b0;
  wire [15:0] iox_rdata;
  wire        iox_sel;
  wire [3:0]  int_pending;

  wire        dma_req, dma_wr;
  wire [23:0] dma_addr;
  wire [15:0] dma_wdata;
  reg  [15:0] dma_rdata = 16'd0;
  reg         dma_ack = 1'b0;
  reg         dma_err = 1'b0;

  wire        disk_start, disk_req, disk_wr;
  wire [15:0] disk_blkaddr1, disk_blkaddr2;
  wire [2:0]  disk_unit;
  wire [10:0] disk_wordcount;

  ND_WINCHESTER #(.DELAY_TICKS(32'd10)) dut (
      .sysclk        (sysclk),
      .sys_rst_n     (sys_rst_n),
      .iox_addr      (iox_addr),
      .iox_wr        (iox_wr),
      .iox_wdata     (iox_wdata),
      .iox_rd        (iox_rd),
      .iox_rdata     (iox_rdata),
      .iox_sel       (iox_sel),
      .int_pending   (int_pending),
      .ident_strobe  (1'b0),
      .ident_level   (4'd0),
      .ident_grant_in(1'b0),
      .ident_grant_out(),
      .ident_hit     (),
      .ident_code    (),
      .dma_req       (dma_req),
      .dma_wr        (dma_wr),
      .dma_addr      (dma_addr),
      .dma_wdata     (dma_wdata),
      .dma_rdata     (dma_rdata),
      .dma_ack       (dma_ack),
      .dma_err       (dma_err),
      .dma_busy      (1'b0),
      .disk_start    (disk_start),
      .disk_req      (disk_req),
      .disk_wr       (disk_wr),
      .disk_blkaddr1 (disk_blkaddr1),
      .disk_blkaddr2 (disk_blkaddr2),
      .disk_unit     (disk_unit),
      .disk_wordcount(disk_wordcount),
      .disk_done     (1'b0),
      .disk_err_in   (1'b0),
      .disk_err_code (4'd0),
      .dbuf_addr     (10'd0),
      .dbuf_wdata    (16'd0),
      .dbuf_we       (1'b0),
      .dbuf_rdata    ()
  );

  // Memory: every request answered on the next clock; a read of `bad_addr`
  // fails (dma_err) while bad_on. Reads, writes and disc requests counted.
  reg  [23:0] bad_addr = 24'd0;
  reg         bad_on   = 1'b0;
  integer     n_rd = 0, n_wr = 0, n_disk = 0;
  reg  [23:0] first_rd, last_rd;
  always @(posedge sysclk) begin
    dma_ack <= 1'b0;
    dma_err <= 1'b0;
    if (dma_req && !dma_ack) begin
      dma_ack <= 1'b1;
      if (bad_on && dma_addr == bad_addr) dma_err <= 1'b1;
      dma_rdata <= dma_addr[15:0] ^ 16'o052525;
      if (dma_wr) n_wr = n_wr + 1;
      else begin
        if (n_rd == 0) first_rd = dma_addr;
        last_rd = dma_addr;
        n_rd = n_rd + 1;
      end
    end
    if (disk_req) n_disk = n_disk + 1;
  end

  reg [15:0] bus_capture = 16'd0;
  always @(posedge sysclk) if (iox_rd) bus_capture <= iox_rdata;

  task iox_write(input [15:0] a, input [15:0] d);
    begin
      @(posedge sysclk);
      iox_addr  <= a;
      iox_wdata <= d;
      iox_wr    <= 1'b1;
      @(posedge sysclk);
      iox_wr    <= 1'b0;
      @(posedge sysclk);
    end
  endtask

  task iox_read(input [15:0] a, output [15:0] d);
    begin
      @(posedge sysclk);
      iox_addr <= a;
      iox_rd   <= 1'b1;
      @(posedge sysclk);
      iox_rd   <= 1'b0;
      @(posedge sysclk);
      d = bus_capture;
    end
  endtask

  integer errors = 0;
  task check(input cond, input [1023:0] msg);
    begin
      if (!cond) begin
        errors = errors + 1;
        $display("FAIL: %0s", msg);
      end
    end
  endtask

  reg [15:0] st, lo, hi, blk;

  task wait_finished;
    integer polls;
    begin
      polls = 0;
      st = 16'd0;
      while (!st[3] && polls < 20000) begin
        iox_read(BASE + R_STATUS, st);
        polls = polls + 1;
      end
      check(st[3], "the format never reported FINISHED");
    end
  endtask

  // Load block address, memory address and word count, then give M5.
  // Returns with the status read at the end in `st`.
  task format(input [15:0] block, input [15:0] wc);
    begin
      iox_write(BASE + R_BLOCK,   block);
      iox_read(BASE + R_STATUS,   st);        // flip-flop on "first"
      iox_write(BASE + R_LOADADR, LOAD_HI);
      iox_write(BASE + R_LOADADR, LOAD_LO);
      iox_write(BASE + R_WORDCNT, wc);
      n_rd = 0; n_wr = 0; n_disk = 0;
      iox_write(BASE + R_CONTROL, CW_FORMAT);
      wait_finished;
    end
  endtask

  task read_memaddr(output [23:0] a);
    begin
      iox_read(BASE + R_STATUS,  st);
      iox_read(BASE + R_MEMADDR, lo);
      iox_read(BASE + R_MEMADDR, hi);
      a = {hi[7:0], lo};
    end
  endtask

  reg [23:0] ma;

  // One good format: `wc` loaded, `nread` field words expected, the word
  // count left at `wc_after`.
  task good(input [15:0] block, input [15:0] wc, input integer nread,
            input [15:0] wc_after, input [8*40-1:0] what);
    begin
      format(block, wc);
      check(!st[8] && !st[11] && !st[4], {what, ": no error bit"});
      check(n_rd == nread, {what, ": wrong number of field words read"});
      if (nread > 0) begin
        check(first_rd == START, {what, ": the first field word is not at the memory address"});
        check(last_rd == START + nread - 1, {what, ": the field words are not consecutive"});
      end
      check(n_wr == 0, {what, ": wrote to memory"});
      check(n_disk == 0, {what, ": made a disc request"});
      read_memaddr(ma);
      check(ma == START + nread, {what, ": memory address did not move on by the words read"});
      check(dut.s_word_cnt == wc_after, {what, ": word count not lowered by the words read"});
      iox_read(BASE + R_BLKRD, blk);
      check(blk == block, {what, ": the block address moved"});
      $display("%0s: %0d field words read, memory address %o, word count %0d",
               what, n_rd, ma, dut.s_word_cnt);
    end
  endtask

  initial begin
    $display("=== Winchester Write Format (M5) data side ===");
    repeat (6) @(posedge sysclk);
    sys_rst_n = 1;
    repeat (6) @(posedge sysclk);

    // A whole track (9 sectors x 2 words), on cylinder 3 with the arm on 0:
    // M5 runs no arm-on-cylinder check.
    good((16'd3 << 5), 16'd18, 18, 16'd0,  "M5 of one track");
    good(16'd0,        16'd10, 10, 16'd0,  "M5 of 5 sectors");
    // More fields than the track has sectors: one track's worth (BUGS.md W2).
    good(16'd0,        16'd40, 18, 16'd22, "M5 of 40 words");
    // An odd count: whole sectors only.
    good(16'd0,        16'd7,  6,  16'd1,  "M5 of 7 words");
    good(16'd0,        16'd0,  0,  16'd0,  "M5 of 0 words");

    // Outside the drive (cylinder 1500 of 1024): mismatch b8, ending LATER
    // (active straight after the GO), nothing read, registers as loaded.
    iox_write(BASE + R_BLOCK,   (16'd1500 << 5));
    iox_read(BASE + R_STATUS,   st);
    iox_write(BASE + R_LOADADR, LOAD_HI);
    iox_write(BASE + R_LOADADR, LOAD_LO);
    iox_write(BASE + R_WORDCNT, 16'd18);
    n_rd = 0;
    iox_write(BASE + R_CONTROL, CW_FORMAT);
    iox_read(BASE + R_STATUS, st);
    check(st[2], "M5 outside the drive: still active straight after the GO");
    wait_finished;
    check(st[8], "M5 outside the drive: address mismatch b8");
    check(n_rd == 0, "M5 outside the drive: read field words");
    read_memaddr(ma);
    check(ma == START, "M5 outside the drive: memory address moved");
    check(dut.s_word_cnt == 16'd18, "M5 outside the drive: word count changed");

    // A failed field read (the fourth word): b11, registers as loaded.
    bad_addr = START + 24'd3;
    bad_on   = 1'b1;
    format(16'd0, 16'd18);
    bad_on   = 1'b0;
    check(st[11], "M5 with a failed field read: DMA channel error b11");
    check(!st[8], "M5 with a failed field read: no address mismatch");
    check(n_rd == 4, "M5 with a failed field read: did not stop at the failed word");
    read_memaddr(ma);
    check(ma == START, "M5 with a failed field read: memory address moved");
    check(dut.s_word_cnt == 16'd18, "M5 with a failed field read: word count changed");

    // The next good format starts clean (activation clears b11).
    good(16'd0, 16'd18, 18, 16'd0, "M5 after the failed one");

    if (errors == 0)
      $display("TB_RESULT: PASS (Write Format reads its fields as nd100x does)");
    else
      $display("TB_RESULT: FAIL (%0d error(s))", errors);
    $finish;
  end

endmodule
