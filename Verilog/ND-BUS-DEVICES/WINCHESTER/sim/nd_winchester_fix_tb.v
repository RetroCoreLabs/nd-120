/***************************************************************************
** nd_winchester_fix_tb - ND_WINCHESTER behaviours found by reading the    **
** RTL against the nd100x oracle (device_winchester.c) and the manual      **
** ND-11.015.01. One block per defect; each block FAILS on the RTL as it    **
** was before the fix.                                                     **
**                                                                         **
**   1. the GO-time range check uses the head of THAT control word         **
**   2. a non-activating control word while active does not raise the      **
**      interrupt line (sec 4.1: line = b3 AND b0, and b3 is 0 while       **
**      active)                                                            **
**   3. test mode (control b3) does not skip the range check               **
**   4. unit and head sent to the backend are latched at activation        **
**   5. device clear while the backend owes a done: the next disk          **
**      operation waits for it; device clear + GO in one word runs the     **
**      GO on the CLEARED registers                                        **
**   6. a zero-step seek takes the same delay as any other seek            **
**   7. a read/write/compare while a return to zero runs sets status b5    **
**      (sec 3.5) and is refused                                           **
**                                                                         **
** Sources: 1, 3, 4, 5, 6 are fidelity to the oracle, 2 and 7 to the       **
** manual (sec 4.1, sec 3.5).                                              **
**                                                                         **
** Verdict line: TB_RESULT: PASS / TB_RESULT: FAIL                         **
***************************************************************************/

`timescale 1ns / 1ps

module nd_winchester_fix_tb;

  localparam [15:0] BASE = 16'o000500;
  localparam [31:0] LONG_DELAY = 32'd2000;

  localparam SB_RTZVIOL  = 5;
  localparam SB_ADDRMISM = 8;
  localparam SB_INCLOR   = 4;
  localparam SB_FINISHED = 3;
  localparam SB_ACTIVE   = 2;

  localparam R_LOAD_MA    = 16'd1;
  localparam R_LOAD_BLOCK = 16'd3;
  localparam R_STATUS     = 16'd4;
  localparam R_CONTROL    = 16'd5;
  localparam R_LOAD_WC    = 16'd7;

  localparam CW_INT_EN   = 16'h0001;
  localparam CW_ACTIVE   = 16'h0004;
  localparam CW_TEST     = 16'h0008;
  localparam CW_DEVCLR   = 16'h0010;
  localparam CW_UNIT     = 16'h0200;
  localparam [15:0] OP_RTZ  = 16'd7 << 11;
  localparam [15:0] OP_SEEK = 16'd4 << 11;

  function [15:0] head(input [3:0] h);
    head = {12'd0, h} << 5;
  endfunction

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
  wire        disk_start, disk_req, disk_wr;
  wire [15:0] disk_blkaddr1, disk_blkaddr2;
  wire [2:0]  disk_unit;
  wire [10:0] disk_wordcount;
  wire [15:0] dbuf_rdata;
  reg         disk_done = 1'b0;

  ND_WINCHESTER #(.DELAY_TICKS(LONG_DELAY)) dut (
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
      .dma_rdata     (16'd0),
      .dma_ack       (1'b0),
      .dma_err       (1'b0),
      .dma_busy      (1'b0),
      .disk_start    (disk_start),
      .disk_req      (disk_req),
      .disk_wr       (disk_wr),
      .disk_blkaddr1 (disk_blkaddr1),
      .disk_blkaddr2 (disk_blkaddr2),
      .disk_unit     (disk_unit),
      .disk_wordcount(disk_wordcount),
      .disk_done     (disk_done),
      .disk_err_in   (1'b0),
      .disk_err_code (4'd0),
      .dbuf_addr     (10'd0),
      .dbuf_wdata    (16'd0),
      .dbuf_we       (1'b0),
      .dbuf_rdata    (dbuf_rdata)
  );

  integer errors = 0;
  integer checks = 0;
  integer reqs   = 0;     // backend requests seen since the last master clear
  always @(posedge sysclk) if (disk_req) reqs = reqs + 1;

  task check(input cond, input [1023:0] msg);
    begin
      checks = checks + 1;
      if (!cond) begin
        errors = errors + 1;
        $display("  FAIL: %0s", msg);
      end
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

  task iox_write(input [15:0] a, input [15:0] data);
    begin
      @(negedge sysclk);
      iox_addr  = a;
      iox_wdata = data;
      iox_wr    = 1'b1;
      @(negedge sysclk);
      iox_wr    = 1'b0;
    end
  endtask

  task master_clear;
    begin
      @(negedge sysclk);
      sys_rst_n = 1'b0;
      repeat (3) @(negedge sysclk);
      sys_rst_n = 1'b1;
      repeat (2) @(negedge sysclk);
      reqs = 0;
    end
  endtask

  // The backend answers: a one-clock done pulse.
  task backend_done;
    begin
      @(negedge sysclk);
      disk_done = 1'b1;
      @(negedge sysclk);
      disk_done = 1'b0;
    end
  endtask

  reg [15:0] d;

  initial begin
    repeat (4) @(negedge sysclk);
    sys_rst_n = 1'b1;
    repeat (4) @(negedge sysclk);

    // ---- 1. range check uses the head of THIS control word -----------------
    // Drive has 8 heads (0-7). A GO that carries head 12 must mismatch even
    // though the PREVIOUS head register held 0; a GO that carries head 1 must
    // not mismatch just because the previous word left head 12 behind.
    master_clear;
    iox_write(BASE + R_LOAD_BLOCK, 16'd0);
    iox_write(BASE + R_LOAD_WC, 16'd0);                 // no backend needed
    iox_write(BASE + R_CONTROL, CW_ACTIVE | head(4'd12));
    repeat (20) @(posedge sysclk);
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ADDRMISM] === 1'b1, "1: head 12 in the GO word is out of range");

    master_clear;
    iox_write(BASE + R_LOAD_BLOCK, 16'd0);
    iox_write(BASE + R_LOAD_WC, 16'd0);
    iox_write(BASE + R_CONTROL, head(4'd12));           // non-activating: leaves head 12
    iox_write(BASE + R_CONTROL, CW_ACTIVE | head(4'd1));
    repeat (LONG_DELAY + 100) @(posedge sysclk);
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ADDRMISM] === 1'b0, "1: a valid head in the GO word is not rejected for the old head");

    // ---- 2. no interrupt while active ---------------------------------------
    master_clear;
    iox_write(BASE + R_CONTROL, CW_ACTIVE | OP_RTZ);    // RTZ: active for a long time
    repeat (10) @(posedge sysclk);
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ACTIVE] === 1'b1, "2: set-up: RTZ is running");
    iox_write(BASE + R_CONTROL, CW_INT_EN);             // non-activating, enable on
    repeat (10) @(posedge sysclk);
    check(dut.s_irq === 1'b0, "2: interrupt line stays low while the card is active");
    repeat (LONG_DELAY + 100) @(posedge sysclk);
    check(dut.s_irq === 1'b1, "2: interrupt rises at completion (b3 AND b0)");

    // ---- 3. test mode does not skip the range check -------------------------
    master_clear;
    iox_write(BASE + R_LOAD_BLOCK, 16'd20);             // sector 20 > 8
    iox_write(BASE + R_LOAD_WC, 16'd0);
    iox_write(BASE + R_CONTROL, CW_ACTIVE | CW_TEST);
    repeat (20) @(posedge sysclk);
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ADDRMISM] === 1'b1, "3: test mode still range-checks");

    // ---- 4. unit and head are latched at activation -------------------------
    master_clear;
    iox_write(BASE + R_LOAD_BLOCK, 16'd0);
    iox_write(BASE + R_LOAD_WC, 16'd1000);
    iox_write(BASE + R_CONTROL, CW_ACTIVE | head(4'd2));            // M0, unit 0, head 2
    repeat (10) @(posedge sysclk);
    check(reqs == 1, "4: set-up: the backend request went out");
    iox_write(BASE + R_CONTROL, CW_UNIT | head(4'd5));              // later word: unit 1, head 5
    repeat (4) @(posedge sysclk);
    check(disk_unit === 3'd0, "4: backend unit stays at the unit the GO selected");
    check(disk_blkaddr1[11:8] === 4'd2, "4: backend head stays at the head the GO carried");

    // ---- 5a. device clear while the backend owes a done ---------------------
    master_clear;
    iox_write(BASE + R_LOAD_BLOCK, 16'd0);
    iox_write(BASE + R_LOAD_WC, 16'd1000);
    iox_write(BASE + R_CONTROL, CW_ACTIVE);             // request 1 goes out, no done yet
    repeat (10) @(posedge sysclk);
    iox_write(BASE + R_CONTROL, CW_DEVCLR);             // cut the operation short
    iox_write(BASE + R_LOAD_BLOCK, 16'd0);
    iox_write(BASE + R_LOAD_WC, 16'd1000);
    iox_write(BASE + R_CONTROL, CW_ACTIVE);             // new read, backend still owes a done
    repeat (10) @(posedge sysclk);
    check(reqs == 1, "5a: no second backend request while the first done is owed");
    backend_done;                                       // the stale done
    repeat (10) @(posedge sysclk);
    check(reqs == 2, "5a: the new request goes out once the backend is quiet");
    check(dut.s_eng === 3'd1, "5a: the stale done did not end the new operation's disk read");

    // ---- 5b. device clear + GO in one word runs on the cleared registers ----
    master_clear;
    iox_write(BASE + R_LOAD_MA, 16'd0);
    iox_write(BASE + R_LOAD_MA, 16'o001000);
    iox_write(BASE + R_LOAD_BLOCK, 16'd0);
    iox_write(BASE + R_LOAD_WC, 16'd512);
    iox_write(BASE + R_CONTROL, CW_ACTIVE | CW_DEVCLR);
    repeat (LONG_DELAY + 100) @(posedge sysclk);
    check(reqs == 0, "5b: a GO sent with a device clear sees the cleared (zero) word count");
    iox_read(BASE + R_STATUS, d);
    check(d[SB_FINISHED] === 1'b1 && d[SB_ACTIVE] === 1'b0, "5b: the zero-length operation completed");

    // ---- 6. a zero-step seek takes the full delay ---------------------------
    master_clear;
    iox_write(BASE + R_LOAD_WC, 16'd0);
    iox_write(BASE + R_CONTROL, CW_ACTIVE | OP_SEEK);
    repeat (200) @(posedge sysclk);
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ACTIVE] === 1'b1, "6: a zero-step seek is still running after 200 clocks");
    repeat (LONG_DELAY + 100) @(posedge sysclk);
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ACTIVE] === 1'b0 && d[SB_FINISHED] === 1'b1, "6: a zero-step seek completes");

    // ---- 7. read during RTZ sets b5 and is refused --------------------------
    master_clear;
    iox_write(BASE + R_CONTROL, CW_ACTIVE | OP_RTZ);
    repeat (10) @(posedge sysclk);
    iox_write(BASE + R_LOAD_BLOCK, 16'd0);
    iox_write(BASE + R_LOAD_WC, 16'd512);
    iox_write(BASE + R_CONTROL, CW_ACTIVE);             // M0 read during RTZ
    repeat (10) @(posedge sysclk);
    iox_read(BASE + R_STATUS, d);
    check(d[SB_RTZVIOL] === 1'b1, "7: read during RTZ sets b5");
    check(d[SB_INCLOR]  === 1'b1, "7: b5 feeds the inclusive OR");
    check(d[SB_ACTIVE]  === 1'b1, "7: the return to zero carries on");
    check(reqs == 0, "7: the refused read sent no backend request");
    repeat (LONG_DELAY + 100) @(posedge sysclk);
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ACTIVE] === 1'b0 && d[SB_FINISHED] === 1'b1, "7: the return to zero completed");
    check(d[SB_RTZVIOL] === 1'b1, "7: b5 stays set until the next activation");
    // a seek during RTZ is not a read/write: no violation
    master_clear;
    iox_write(BASE + R_CONTROL, CW_ACTIVE | OP_RTZ);
    repeat (10) @(posedge sysclk);
    iox_read(BASE + R_STATUS, d);
    check(d[SB_RTZVIOL] === 1'b0, "7: b5 is clear when no read/write was attempted");

    if (errors == 0)
      $display("=== %0d checks passed ===\nTB_RESULT: PASS", checks);
    else
      $display("=== %0d of %0d checks FAILED ===\nTB_RESULT: FAIL",
               errors, checks);
    $finish;
  end

  initial begin
    #40_000_000;
    $display("  FAIL: testbench watchdog - the DUT hung");
    $display("TB_RESULT: FAIL");
    $finish;
  end

endmodule
