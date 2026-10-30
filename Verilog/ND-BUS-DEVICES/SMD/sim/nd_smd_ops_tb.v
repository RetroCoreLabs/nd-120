/*****************************************************************************
**  nd_smd_ops_tb.v                                                         **
**                                                                          **
**  The SMD operations the other benches do not reach, each checked        **
**  against what nd100x (device_smd.c) does:                                **
**                                                                          **
**   - Load ECC Control (+7 with CWR = 1) takes ONE write on the 15 MHz    **
**     card, and does not move the memory address / word count flip-flop;  **
**   - test mode (control bit 3): M0 writes the pattern generator's words   **
**     052525, 125252, ... to memory and ends with data error b9; M3        **
**     compares memory with the same stream, a mismatch ends it at that     **
**     word with b10, b9 and b12;                                           **
**   - Write Format (M5): the address fields are DMA-read from memory, two  **
**     words per sector, a whole number of tracks, and the address and word **
**     registers are left as loaded; a word count that is not a whole       **
**     number of tracks (or zero) is a timeout (b6) at once; an address     **
**     outside the drive is a mismatch with no memory cycle;                **
**   - M1 with a failed memory read ends at once with b12 only;             **
**   - M8 ends at once, M9 drops the unit selection, codes 10-15 stay       **
**     active until a device clear (BUGS.md S10);                           **
**   - a GO on a not-specified unit does not clear the last illegal load.   **
**                                                                          **
**  The DUT's DMA port is answered directly by a small memory model, with   **
**  an error on one chosen address. FAST = 1 (the default) with a short     **
**  DELAY_TICKS.                                                            **
*****************************************************************************/

`timescale 1ns / 1ps

module nd_smd_ops_tb;

  localparam [15:0] BASE = 16'o001540;
  localparam R_CORE   = 16'd1;
  localparam R_SEEK   = 16'd2;
  localparam R_BLOCK  = 16'd3;
  localparam R_STATUS = 16'd4;
  localparam R_CTRL   = 16'd5;
  localparam R_WC     = 16'd7;

  localparam [15:0] CW_GO   = 16'h0004;
  localparam [15:0] CW_TEST = 16'h0008;
  localparam [15:0] CW_CLR  = 16'h0010;
  localparam [15:0] CW_CWR  = 16'h8000;

  reg sysclk = 0;
  reg sys_rst_n = 0;
  always #10 sysclk = ~sysclk;

  reg  [15:0] iox_addr  = 16'd0;
  reg         iox_wr    = 1'b0;
  reg  [15:0] iox_wdata = 16'd0;
  reg         iox_rd    = 1'b0;
  wire [15:0] iox_rdata;
  wire [3:0]  int_pending;

  wire        dma_req, dma_wr;
  wire [23:0] dma_addr;
  wire [15:0] dma_wdata;
  reg  [15:0] dma_rdata = 16'd0;
  reg         dma_ack   = 1'b0;
  reg         dma_err   = 1'b0;
  wire        disk_start, disk_req, disk_wr;
  wire [15:0] disk_blkaddr1, disk_blkaddr2;
  wire [2:0]  disk_unit;
  wire [10:0] disk_wordcount;

  ND_SMD #(.HAS_WC_FLIPFLOP(1), .DELAY_TICKS(32'd10)) dut (
      .sysclk        (sysclk),
      .sys_rst_n     (sys_rst_n),
      .iox_addr      (iox_addr),
      .iox_wr        (iox_wr),
      .iox_wdata     (iox_wdata),
      .iox_rd        (iox_rd),
      .iox_rdata     (iox_rdata),
      .iox_sel       (),
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

  // Memory: answers each request on the next clock. A request to
  // `bad_addr` is answered with dma_err (when bad_on). Reads and writes are
  // counted.
  reg  [15:0] mem [0:4095];
  reg  [23:0] bad_addr = 24'hFFFFFF;
  reg         bad_on   = 1'b0;
  integer     n_rd = 0, n_wr = 0;
  always @(posedge sysclk) begin
    dma_ack <= 1'b0;
    dma_err <= 1'b0;
    if (dma_req && !dma_ack) begin
      dma_ack <= 1'b1;
      if (bad_on && dma_addr == bad_addr) begin
        dma_err <= 1'b1;
      end else if (dma_wr) begin
        mem[dma_addr[11:0]] <= dma_wdata;
      end else begin
        dma_rdata <= mem[dma_addr[11:0]];
      end
      if (dma_wr) n_wr = n_wr + 1; else n_rd = n_rd + 1;
    end
  end

  task iox_write(input [15:0] a, input [15:0] d);
    begin
      @(negedge sysclk);
      iox_addr  = a;
      iox_wdata = d;
      iox_wr    = 1'b1;
      @(negedge sysclk);
      iox_wr    = 1'b0;
    end
  endtask

  task iox_read(input [15:0] a, output [15:0] d);
    begin
      @(negedge sysclk);
      iox_addr = a;
      iox_rd   = 1'b1;
      #1 d = iox_rdata;
      @(posedge sysclk);
      @(negedge sysclk);
      iox_rd   = 1'b0;
    end
  endtask

  integer errors = 0;
  task check(input cond, input [1023:0] msg);
    begin
      if (!cond) begin
        errors = errors + 1;
        $display("  FAIL: %0s", msg);
      end
    end
  endtask

  reg [15:0] st;

  // Load the 24-bit core address or word count on the flip-flop card: a
  // status read puts the flip-flop on "first", then the high and low writes.
  task load24(input [15:0] reg_off, input [23:0] v);
    begin
      iox_read(BASE + R_STATUS, st);
      iox_write(BASE + reg_off, {8'd0, v[23:16]});
      iox_write(BASE + reg_off, v[15:0]);
    end
  endtask

  task load_block(input [15:0] cyl, input [15:0] hs);
    begin
      iox_write(BASE + R_CTRL, CW_CWR);
      iox_write(BASE + R_BLOCK, cyl);
      iox_write(BASE + R_CTRL, 16'h0000);
      iox_write(BASE + R_BLOCK, hs);
    end
  endtask

  // Read back the 24-bit core address (CWR = 0) or word count (CWR = 1).
  task read24(input cwr, output [23:0] v);
    reg [15:0] lo, hi;
    begin
      iox_write(BASE + R_CTRL, 16'h0000);
      iox_read(BASE + R_STATUS, st);     // flip-flop on "first"
      iox_write(BASE + R_CTRL, cwr ? CW_CWR : 16'h0000);
      iox_read(BASE + 16'd0, lo);
      iox_read(BASE + 16'd0, hi);
      iox_write(BASE + R_CTRL, 16'h0000);
      v = {hi[7:0], lo};
    end
  endtask

  task wait_idle;
    integer guard;
    begin
      guard = 0;
      while (dut.s_active && guard < 100000) begin
        @(negedge sysclk);
        guard = guard + 1;
      end
      check(!dut.s_active, "the operation never ended");
    end
  endtask

  integer i, rd0;
  reg [23:0] v24;

  initial begin
    for (i = 0; i < 4096; i = i + 1) mem[i] = 16'o177777;
    repeat (4) @(negedge sysclk);
    sys_rst_n = 1'b1;
    repeat (2) @(negedge sysclk);
    $display("ND_SMD operations against nd100x");
    iox_write(BASE + R_CTRL, 16'h0000);  // leave boot mode, unit 0

    // ---- 1. ECC control: ONE write, flip-flop untouched ----
    iox_read(BASE + R_STATUS, st);       // flip-flop on "first"
    iox_write(BASE + R_CTRL, CW_CWR);
    iox_write(BASE + R_WC, 16'h0002);    // ECC control, bit 1 = force parity
    iox_write(BASE + R_CTRL, 16'h0000);
    iox_read(BASE + R_STATUS, st);
    check(st[7], "ECC control: one write with bit 1 must set b7 (hardware error 2)");
    check(dut.s_ma_wc_ff == 1'b0, "ECC control: the write must not toggle the flip-flop");
    iox_write(BASE + R_CTRL, CW_CLR);
    iox_write(BASE + R_CTRL, 16'h0000);
    iox_read(BASE + R_STATUS, st);
    check(!st[7], "device clear must clear b7");

    // ---- 2. test-mode M0: the pattern to memory, b9 at the end ----
    load_block(16'd0, 16'd0);
    load24(R_CORE, 24'o000100);
    load24(R_WC, 24'd5);
    iox_write(BASE + R_CTRL, CW_GO | CW_TEST);   // M0, test mode
    wait_idle;
    check(mem[12'o100] === 16'o052525, "test M0: word 0 must be 052525");
    check(mem[12'o101] === 16'o125252, "test M0: word 1 must be 125252");
    check(mem[12'o104] === 16'o052525, "test M0: word 4 must be 052525");
    check(mem[12'o105] === 16'o177777, "test M0: wrote past the word count");
    iox_read(BASE + R_STATUS, st);
    // ND-11.020.01 sec 4.4: a test-mode read reads status 041030 (on
    // cylinder, data error, inclusive OR, finished); control bit 3 reads
    // back nowhere in the status, so the word is exact.
    check(st === 16'o041030, "test M0: status must be 041030");
    read24(1'b0, v24);
    check(v24 === 24'o000105, "test M0: core address must step to 000105");
    read24(1'b1, v24);
    check(v24 === 24'd0, "test M0: word count must reach 0");

    // ---- 3. test-mode M3: compare with the pattern ----
    load24(R_CORE, 24'o000100);
    load24(R_WC, 24'd5);
    iox_write(BASE + R_CTRL, CW_GO | CW_TEST | 16'h1800);   // M3, test mode
    wait_idle;
    iox_read(BASE + R_STATUS, st);
    check(st[9] && !st[10] && !st[12], "test M3 equal: b9 only (no b10, no b12)");
    mem[12'o102] = 16'o000000;           // word 2 differs
    load24(R_CORE, 24'o000100);
    load24(R_WC, 24'd5);
    iox_write(BASE + R_CTRL, CW_GO | CW_TEST | 16'h1800);
    wait_idle;
    iox_read(BASE + R_STATUS, st);
    check(st[10], "test M3 mismatch: b10 (compare error)");
    check(st[9],  "test M3 mismatch: b9 (data error)");
    check(st[12], "test M3 mismatch: b12 (abnormal completion)");
    read24(1'b0, v24);
    check(v24 === 24'o000102, "test M3 mismatch: core address left on word 2");
    read24(1'b1, v24);
    check(v24 === 24'd3, "test M3 mismatch: word count left at 3");
    iox_write(BASE + R_CTRL, CW_CLR);
    iox_write(BASE + R_CTRL, 16'h0000);
    iox_read(BASE + R_STATUS, st);
    check(!st[9], "device clear must clear b9");

    // ---- 4. Write Format ----
    // 2 tracks of 18 sectors: 72 field words read from memory, registers
    // left as loaded, normal end.
    load_block(16'd10, 16'd0);
    load24(R_CORE, 24'o001000);
    load24(R_WC, 24'd72);
    rd0 = n_rd;
    iox_write(BASE + R_CTRL, CW_GO | 16'h2800);   // M5
    wait_idle;
    check(n_rd - rd0 == 72, "M5: must read 72 field words (2 per sector, 2 tracks)");
    iox_read(BASE + R_STATUS, st);
    check(!st[6] && !st[12] && !st[4], "M5 of 2 tracks: no error");
    check(st[3], "M5 of 2 tracks: b3 at the end");
    read24(1'b0, v24);
    check(v24 === 24'o001000, "M5: core address must stay as loaded");
    read24(1'b1, v24);
    check(v24 === 24'd72, "M5: word count must stay as loaded");
    // A failed field read is taken as 0 and the format goes on.
    bad_addr = 24'o001003; bad_on = 1'b1;
    rd0 = n_rd;
    iox_write(BASE + R_CTRL, CW_GO | 16'h2800);
    wait_idle;
    bad_on = 1'b0;
    check(n_rd - rd0 == 72, "M5 with a failed field read: must still read all 72");
    iox_read(BASE + R_STATUS, st);
    check(!st[12] && !st[11], "M5 with a failed field read: no error reported");
    // A count that is not a whole number of tracks: timeout at once.
    load24(R_WC, 24'd30);
    rd0 = n_rd;
    iox_write(BASE + R_CTRL, CW_GO | 16'h2800);
    iox_read(BASE + R_STATUS, st);
    check(!st[2], "M5 with 30 words: ends at once");
    check(st[6] && st[12], "M5 with 30 words: b6 (timeout) and b12");
    check(n_rd == rd0, "M5 with 30 words: no memory cycle");
    load24(R_WC, 24'd0);
    iox_write(BASE + R_CTRL, CW_GO | 16'h2800);
    iox_read(BASE + R_STATUS, st);
    check(st[6] && !st[2], "M5 with 0 words: timeout at once");
    // An address outside the drive: mismatch and seek error, no memory cycle.
    load24(R_WC, 24'd36);
    load_block(16'd823, 16'd0);          // cylinder 823 of 823
    rd0 = n_rd;
    iox_write(BASE + R_CTRL, CW_GO | 16'h2800);
    iox_read(BASE + R_STATUS, st);
    check(st[8] && st[12] && !st[2], "M5 outside the drive: b8, b12, ended");
    check(!st[13], "M5 outside the drive: the unit stays ready");
    check(n_rd == rd0, "M5 outside the drive: no memory cycle");
    iox_read(BASE + R_SEEK, st);
    check(st[11], "M5 outside the drive: seek error (seek condition b11)");

    // ---- 5. M1 with a failed memory read: b12 only, ends there ----
    iox_write(BASE + R_CTRL, CW_CLR);
    iox_write(BASE + R_CTRL, 16'h0000);
    load_block(16'd0, 16'd0);
    load24(R_CORE, 24'o002000);
    load24(R_WC, 24'd16);
    bad_addr = 24'o002003; bad_on = 1'b1;
    iox_write(BASE + R_CTRL, CW_GO | 16'h0800);   // M1
    wait_idle;
    bad_on = 1'b0;
    iox_read(BASE + R_STATUS, st);
    check(st[12], "M1 failed read: b12");
    check(!st[11] && !st[13] && !st[10], "M1 failed read: no b11, b13 or b10");
    check(st[3], "M1 failed read: b3 at the end");
    read24(1'b0, v24);
    check(v24 === 24'o002003, "M1 failed read: core address left on the failed word");

    // ---- 6. M8, M9, codes 10-15 ----
    iox_write(BASE + R_CTRL, CW_GO | 16'h4000);   // M8
    iox_read(BASE + R_STATUS, st);
    check(!st[2] && st[3], "M8: ends at once");
    iox_write(BASE + R_CTRL, CW_GO | 16'h4800);   // M9
    iox_read(BASE + R_STATUS, st);
    check(!st[2] && st[3], "M9: ends at once");
    check(st[13] && !st[14], "M9: no unit selected (b13 = 1, b14 = 0)");
    iox_write(BASE + R_CTRL, 16'h0000);           // select unit 0 again
    iox_write(BASE + R_CTRL, CW_GO | 16'h5000);   // code 10
    repeat (200) @(negedge sysclk);
    iox_read(BASE + R_STATUS, st);
    check(st[2], "code 10: stays active (nd100x, BUGS.md S10)");
    iox_write(BASE + R_CTRL, CW_CLR);
    iox_read(BASE + R_STATUS, st);
    check(!st[2], "code 10: a device clear ends it");

    // ---- 7. a GO on a not-specified unit keeps the last illegal load ----
    // The b5 comes from an off-cylinder load: M4 to cylinder 5, then +3
    // while the heads move (an active controller would reject the GO
    // itself as an illegal load).
    iox_write(BASE + R_CTRL, 16'h0000);
    load_block(16'd5, 16'd0);
    iox_write(BASE + R_CTRL, CW_GO | 16'h2000);   // M4
    iox_write(BASE + R_BLOCK, 16'd1);              // off cylinder: illegal
    iox_write(BASE + R_CTRL, CW_GO | 16'h0200);   // GO, M0, unit 4
    iox_read(BASE + R_STATUS, st);
    check(st[7], "not-specified unit: b7");
    check(st[5], "not-specified unit: the GO must not clear the last b5 (nd100x)");
    check(!st[2] && st[3], "not-specified unit: ends at once with b3");

    if (errors == 0)
      $display("TB_RESULT: PASS");
    else
      $display("TB_RESULT: FAIL (%0d checks failed)", errors);
    $finish;
  end

endmodule
