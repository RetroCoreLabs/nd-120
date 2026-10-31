/****************************************************************************
** TESTBENCH: replay the ORACLE's IOX sequence against ND_WINCHESTER.v     **
**                                                                         **
** Captured 05-AUG-2026 from the nd100x C model                            **
** (src/devices/winchester/deviceWinchester.c) with ND100X_WD_DEBUG=1,     **
** running DISC-TEMA J02 "DU-DI-C" on DISC-74MB-1, unit 0, cylinder 0,     **
** surface 0, sector 0, amount 1 - the exact operation that fails on the   **
** Tang with "Memory address Register not as expected".                    **
**                                                                         **
** The oracle's trace, verbatim, is the specification here:                **
**                                                                         **
**   IOX WRITE 503 reg=3 value=0        load block address                 **
**   IOX WRITE 501 reg=1 value=1        memory address, HI 8 bits first    **
**   IOX WRITE 501 reg=1 value=0        memory address, LO 16 second       **
**   IOX WRITE 507 reg=7 value=1000     word count = 512                   **
**   IOX WRITE 505 reg=5 value=5        activate + M0 Read, interrupt on   **
**   -> GO M0-Read unit=0 C/H/S=0/0/0 LBA=0 WC=512 core=200000             **
**   IOX READ  504 reg=4 -> 60005       status while active                **
**   IOX READ  504 reg=4 -> 60010       status: finished                   **
**   IOX READ  500 reg=0 -> 1000        MAR low  (0x0200 = 512)            **
**   IOX READ  500 reg=0 -> 1           MAR high (0x01)                    **
**                                                                         **
** 0x10000 + 512 words = 0x10200, read back LOW first then HIGH. The Tang  **
** returns the right 512 data words and the identical status word 060010,  **
** so the divergence is confined to those last two reads.                  **
**                                                                         **
** The backends are deliberately trivial: the DMA responder acks every     **
** request one cycle later and counts the words, and the disk responder    **
** completes every chunk. Neither can influence the memory address         **
** register, which is the point - anything this bench catches is inside    **
** ND_WINCHESTER.v.                                                        **
**                                                                         **
** Verdict: TB_RESULT: PASS / TB_RESULT: FAIL <reason>                     **
**                                                                         **
** Ronny Hansen                                                            **
*****************************************************************************/
`timescale 1ns / 1ps

module nd_winchester_oracle_tb;

  localparam [15:0] BASE = 16'o000500;

  localparam R_READ_MA    = 16'd0;
  localparam R_LOAD_MA    = 16'd1;
  localparam R_LOAD_BLOCK = 16'd3;
  localparam R_STATUS     = 16'd4;
  localparam R_CONTROL    = 16'd5;
  localparam R_LOAD_WC    = 16'd7;

  // What the oracle put on the bus, and what it read back.
  localparam [15:0] MA_HI_IN   = 16'o000001;   // first  IOX 501
  localparam [15:0] MA_LO_IN   = 16'o000000;   // second IOX 501
  localparam [15:0] WORD_COUNT = 16'o001000;   // 512
  localparam [15:0] CTRL_GO    = 16'o000005;   // activate + M0 read + int en
  localparam [15:0] MA_LO_EXP  = 16'o001000;   // first  IOX 500 after the op
  localparam [15:0] MA_HI_EXP  = 16'o000001;   // second IOX 500 after the op

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
  reg         dma_ack = 1'b0;
  wire        disk_start, disk_req, disk_wr;
  wire [15:0] disk_blkaddr1, disk_blkaddr2;
  wire [2:0]  disk_unit;
  wire [10:0] disk_wordcount;
  reg         disk_done = 1'b0;
  reg         force_disk_err = 1'b0;
  // WHY the forced failure happened. CARDIO is the storage stack's
  // "the card answered wrongly" reason, which ND_WINCHESTER maps onto its
  // own b9 CRC error - the bit this bench already expected before reason
  // codes existed, so the oracle comparison is unchanged.
  reg [3:0]   force_err_code = 4'd2;   // NDS_ERR_CARDIO
  wire [15:0] dbuf_rdata;

  // E_DELAY counts one per sysclk; keep it short so the bench is quick.
  ND_WINCHESTER #(.DELAY_TICKS(32'd20)) dut (
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
      .dma_rdata     (16'hA5A5),
      .dma_ack       (dma_ack),
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
      .disk_err_in   (force_disk_err),
      .disk_err_code (force_err_code),
      .dbuf_addr     (10'd0),
      .dbuf_wdata    (16'd0),
      .dbuf_we       (1'b0),
      .dbuf_rdata    (dbuf_rdata)
  );

  assign dbuf_rdata = 16'd0;

  // ---- trivial backends ---------------------------------------------------
  // DMA: ack one cycle after the request, and record every address seen.
  integer dma_words = 0;
  reg [23:0] dma_first = 24'hFFFFFF;
  reg [23:0] dma_last  = 24'd0;
  always @(posedge sysclk) begin
    dma_ack <= 1'b0;
    if (dma_req && !dma_ack) begin
      dma_ack   <= 1'b1;
      dma_words = dma_words + 1;
      if (dma_first == 24'hFFFFFF) dma_first = dma_addr;
      dma_last = dma_addr;
    end
  end

  // Disk: every chunk completes two cycles later.
  integer disk_ops = 0;
  reg [1:0] disk_dly = 2'd0;
  always @(posedge sysclk) begin
    disk_done <= 1'b0;
    if (disk_req) begin
      disk_dly <= 2'd2;
      disk_ops = disk_ops + 1;
    end else if (disk_dly != 2'd0) begin
      disk_dly <= disk_dly - 2'd1;
      if (disk_dly == 2'd1) disk_done <= 1'b1;
    end
  end

  // ---- helpers ------------------------------------------------------------
  integer errors = 0;

  // BUS-ACCURATE CAPTURE. ND_BUS_SLAVE.v:109-112 makes iox_rd/iox_wr
  // SINGLE-CYCLE strobes, and it latches the read data with a non-blocking
  // assignment at the clock edge (ND_BUS_SLAVE.v:151-152):
  //
  //     if (iox_rd) BD_23_0_n_IN <= ~{8'h00, iox_rdata};
  //
  // so the master sees the value iox_rdata held DURING the strobe cycle, not
  // whatever it becomes after the device's own edge-triggered side effects
  // land. Sampling with a blocking read after the edge is one delta cycle
  // late and reports failures that the real bus never sees - this bench got
  // that wrong once. Mirror the slave instead.
  localparam integer STROBE_CLKS = 1;

  reg [15:0] bus_capture = 16'd0;
  always @(posedge sysclk) if (iox_rd) bus_capture <= iox_rdata;

  task iox_write(input [15:0] a, input [15:0] d);
    begin
      @(posedge sysclk);
      iox_addr  <= a;
      iox_wdata <= d;
      iox_wr    <= 1'b1;
      repeat (STROBE_CLKS) @(posedge sysclk);
      iox_wr    <= 1'b0;
      @(posedge sysclk);
    end
  endtask

  task iox_read(input [15:0] a, output [15:0] d);
    begin
      @(posedge sysclk);
      iox_addr <= a;
      iox_rd   <= 1'b1;
      repeat (STROBE_CLKS) @(posedge sysclk);
      iox_rd   <= 1'b0;
      @(posedge sysclk);
      d = bus_capture;
    end
  endtask

  task ck_rd(input [15:0] a, input [15:0] want, input [1023:0] msg);
    reg [15:0] g;
    begin
      iox_read(a, g);
      if (g !== want) begin
        $display("FAIL: %0s: got %o want %o (oracle)", msg, g, want);
        errors = errors + 1;
      end else $display("[ ok ] %0s -> %o", msg, g);
    end
  endtask

  task wait_finish;
    integer g2;
    reg [15:0] s2;
    begin
      g2 = 0; s2 = 16'd0;
      while (g2 < 200000 && !(s2[3] && !s2[2])) begin
        iox_read(BASE + R_STATUS, s2);
        g2 = g2 + 1;
      end
    end
  endtask

  task check_eq(input [15:0] got, input [15:0] want, input [1023:0 ] msg);
    begin
      if (got !== want) begin
        $display("FAIL: %0s: got %o want %o", msg, got, want);
        errors = errors + 1;
      end else begin
        $display("[ ok ] %0s = %o", msg, got);
      end
    end
  endtask

  // ---- the replay ---------------------------------------------------------
  reg [15:0] st, ma_lo, ma_hi;
  integer guard;
  initial begin
    repeat (5) @(posedge sysclk);
    sys_rst_n = 1;
    repeat (5) @(posedge sysclk);

    // ---- FULL replay of the oracle's 33-operation trace -----------------
    // Only the tail was replayed before, which assumed the FPGA reaches the
    // failing read down the same path. It may not: a single status word that
    // differs earlier sends DISC-TEMA somewhere else. So every read the
    // oracle logged is checked against the oracle's own value.
    // op3 / op5 / op7 have b14 (on cylinder) SET. The capture above came from
    // the older nd100x model, which read NOT on cylinder until the M7 at
    // op12 (020010 / 020010 / 020011). The current model starts on cylinder,
    // as master clear puts the heads on cylinder 0 (ND-11.015.01 sec 3.4.8,
    // 5.5), and a real 3041 with a 1325 read 060011 after its first control
    // word 000011 with no return to zero before it (../oracle/README.md).
    //
    // On that real card control word 100000 then read back 070010: bit 12,
    // "not used" in sec 3.5, is TR00, the selected drive's Track 000 line
    // (sec 7.9/7.11). It reads 1 whenever unit 0 is on cylinder 0 outside test
    // mode (control b3), so 070010 below, and 060011 only after 000011, which
    // sets test mode and selects no drive. The older nd100x captures this
    // bench was first built from read 0 in b12 because nd100x tied it to 0.
    ck_rd(BASE + R_READ_MA, 16'o000000, "op1  RD +0");
    iox_write(BASE + R_CONTROL, 16'o100000);
    ck_rd(BASE + R_STATUS, 16'o070010, "op3  RD +4");
    iox_write(BASE + R_CONTROL, 16'o000000);
    ck_rd(BASE + R_STATUS, 16'o070010, "op5  RD +4");
    iox_write(BASE + R_CONTROL, 16'o000011);
    ck_rd(BASE + R_STATUS, 16'o060011, "op7  RD +4");
    iox_write(BASE + R_CONTROL, 16'o000010);
    iox_write(BASE + R_CONTROL, 16'o000020);
    iox_write(BASE + R_LOAD_WC, 16'o000000);
    iox_write(BASE + R_CONTROL, 16'o034005);       // GO
    wait_finish;
    ck_rd(BASE + R_STATUS, 16'o070011, "op13 RD +4");
    iox_write(BASE + R_CONTROL, 16'o000000);
    ck_rd(BASE + R_STATUS, 16'o070010, "op15 RD +4");
    ck_rd(BASE + R_STATUS, 16'o070010, "op16 RD +4");
    iox_write(BASE + R_CONTROL, 16'o000020);
    iox_write(BASE + R_CONTROL, 16'o000020);
    ck_rd(BASE + R_STATUS, 16'o070010, "op19 RD +4");
    iox_write(BASE + R_CONTROL, 16'o000020);
    iox_write(BASE + R_CONTROL, 16'o000020);
    iox_write(BASE + R_LOAD_WC, 16'o000000);

    iox_write(BASE + R_LOAD_BLOCK, 16'd0);
    iox_write(BASE + R_LOAD_MA,    MA_HI_IN);   // HI 8 first
    iox_write(BASE + R_LOAD_MA,    MA_LO_IN);   // LO 16 second
    iox_write(BASE + R_LOAD_WC,    WORD_COUNT);
    iox_write(BASE + R_CONTROL,    CTRL_GO);

    // wait for the operation to finish (status bit 2 clear, bit 3 set)
    guard = 0;
    st = 16'd0;
    while (guard < 200000 && !(st[3] && !st[2])) begin
      iox_read(BASE + R_STATUS, st);
      guard = guard + 1;
    end
    if (!(st[3] && !st[2])) begin
      $display("TB_RESULT: FAIL operation never finished (last status %o)", st);
      $finish;
    end
    $display("status at finish = %o (oracle: 060010)", st);

    // the two reads that fail on silicon
    iox_read(BASE + R_READ_MA, ma_lo);
    iox_read(BASE + R_READ_MA, ma_hi);

    check_eq(ma_lo, MA_LO_EXP, "MAR read 1 (low 16)");
    check_eq(ma_hi, MA_HI_EXP, "MAR read 2 (high 8)");

    if (dma_words !== 512) begin
      $display("FAIL: %0d DMA words transferred (want 512)", dma_words);
      errors = errors + 1;
    end else begin
      $display("[ ok ] 512 DMA words, first addr %o last addr %o",
               dma_first, dma_last);
    end

    // ---- the silicon failure: a probe that ends in ADDRESS MISMATCH must
    // not leave the low/high select flip-flop in the wrong phase ------------
    // DISC-TEMA probes out-of-range addresses to exercise status bit 8. That
    // completion is a FinishOperation in both C models (wd_finish_operation
    // -> wd_clear_flipflops + wd_sync_registers). When the RTL skipped it the
    // transfer and the status word stayed correct, and the fault surfaced
    // only later as swapped IOX 500 reads.
    //
    // The order below is what gives this teeth. A status read is itself a
    // flip-flop reset condition, so ANY status read between the probe and the
    // MAR reads hides the bug completely - which is why the first version of
    // this check passed on the broken RTL too. So: leave the alternator on an
    // ODD count first, then probe, then read the MAR with nothing in between,
    // and only check status bit 8 at the very end.
    iox_write(BASE + R_LOAD_MA, MA_HI_IN);
    iox_write(BASE + R_LOAD_MA, MA_LO_IN);
    iox_read(BASE + R_READ_MA, ma_lo);    // ONE read: alternator now on HI
    check_eq(ma_lo, MA_LO_IN, "MAR read before the probe");

    iox_write(BASE + R_LOAD_BLOCK, 16'hFFFF);          // far past the last cyl
    iox_write(BASE + R_LOAD_WC,    WORD_COUNT);
    iox_write(BASE + R_CONTROL,    CTRL_GO);
    repeat (40) @(posedge sysclk);

    // No status read here - the probe itself must have reset the alternator.
    iox_write(BASE + R_LOAD_MA, MA_HI_IN);
    iox_write(BASE + R_LOAD_MA, MA_LO_IN);
    iox_read(BASE + R_READ_MA, ma_lo);
    iox_read(BASE + R_READ_MA, ma_hi);
    check_eq(ma_lo, MA_LO_IN, "MAR read 1 after an address-mismatch probe");
    check_eq(ma_hi, MA_HI_IN, "MAR read 2 after an address-mismatch probe");

    iox_read(BASE + R_STATUS, st);
    if (!st[8]) begin
      $display("FAIL: out-of-range GO did not set address mismatch (b8), status %o", st);
      errors = errors + 1;
    end else begin
      $display("[ ok ] out-of-range GO set address mismatch, status = %o", st);
    end

    // ---- error path: a transfer that FAILS must still leave the registers
    // in their end-of-transfer state ---------------------------------------
    // Both C models end every operation, including a failed one, through
    // wd_finish_operation() -> wd_sync_registers(): address advanced by the
    // words that DID move, count zero. The RTL's err_active task published
    // neither, so after a media error the MAR still read back whatever the
    // guest had loaded.
    iox_write(BASE + R_LOAD_BLOCK, 16'd0);
    iox_write(BASE + R_LOAD_MA,    MA_HI_IN);
    iox_write(BASE + R_LOAD_MA,    MA_LO_IN);
    iox_write(BASE + R_LOAD_WC,    WORD_COUNT);
    force_disk_err = 1'b1;
    iox_write(BASE + R_CONTROL,    CTRL_GO);
    guard = 0;
    st = 16'd0;
    while (guard < 200000 && !(st[3] && !st[2])) begin
      iox_read(BASE + R_STATUS, st);
      guard = guard + 1;
    end
    force_disk_err = 1'b0;
    if (!st[9]) begin
      $display("FAIL: injected media error did not set CRC error (b9), status %o", st);
      errors = errors + 1;
    end
    iox_read(BASE + R_READ_MA, ma_lo);
    iox_read(BASE + R_READ_MA, ma_hi);
    // Nothing was transferred before the failure, so the address is unchanged
    // - but it must have been PUBLISHED by the finish, not merely left over.
    check_eq(ma_hi, MA_HI_IN, "MAR high after a failed transfer");

    // ---- ACTIVE and FINISHED must never both be set ---------------------
    // Straight from the silicon trace (ND120_WD_TRACE_DUMP, 05-AUG-2026):
    // DISC-TEMA issues GO, polls status and sees active, then writes a
    // NON-ACTIVATING control word while the operation is still running. The
    // RTL treated that word as proof the card was idle and raised b3, so the
    // next status read returned 060014 - b2 (active) and b3 (finished) at
    // once. The oracle's status set for the whole run is 020010 / 020011 /
    // 060011 / 060010 / 060005; b2 and b3 are mutually exclusive in every one.
    // The C models cannot hit this because their GO is synchronous.
    iox_write(BASE + R_LOAD_BLOCK, 16'd0);
    iox_write(BASE + R_LOAD_MA,    MA_HI_IN);
    iox_write(BASE + R_LOAD_MA,    MA_LO_IN);
    iox_write(BASE + R_LOAD_WC,    WORD_COUNT);
    iox_write(BASE + R_CONTROL,    CTRL_GO);
    iox_read(BASE + R_STATUS, st);
    if (!st[2]) begin
      $display("FAIL: not active straight after GO (status %o) - the rest of this check is meaningless", st);
      errors = errors + 1;
    end
    iox_write(BASE + R_CONTROL, 16'o000000);   // non-activating, mid-transfer
    iox_read(BASE + R_STATUS, st);
    if (st[2] && st[3]) begin
      $display("FAIL: status %o reports ACTIVE and FINISHED at once - no real card can", st);
      errors = errors + 1;
    end else $display("[ ok ] mid-transfer control word did not fake FINISHED (status %o)", st);
    wait_finish;

    // ---- the block address moves on by the sectors a transfer dealt with --
    // Inferred from the SINTRAN driver (WINCHESTER:NPL IERR "A-1=:ADMIA"),
    // nd100x BUGS.md W7 and wd_advance_block_address: the sector field moves
    // on by the number of sectors the word count touched. 1024 words from
    // sector 3 = 2 sectors, so the register reads sector 5 afterwards; a
    // count that ends inside a sector still counts that sector (513 words =
    // 2 sectors too).
    iox_write(BASE + R_LOAD_BLOCK, 16'd3);
    iox_write(BASE + R_LOAD_MA,    MA_HI_IN);
    iox_write(BASE + R_LOAD_MA,    MA_LO_IN);
    iox_write(BASE + R_LOAD_WC,    16'd1024);
    iox_write(BASE + R_CONTROL,    CTRL_GO);
    wait_finish;
    iox_read(BASE + 16'd6, st);
    check_eq(st, 16'd5, "block address after 1024 words from sector 3");
    iox_write(BASE + R_LOAD_BLOCK, 16'd3);
    iox_write(BASE + R_LOAD_WC,    16'd513);
    iox_write(BASE + R_CONTROL,    CTRL_GO);
    wait_finish;
    iox_read(BASE + 16'd6, st);
    check_eq(st, 16'd5, "block address after 513 words from sector 3 (whole sectors)");

    // ---- M2 read parity: no memory cycles, counters run through ---------
    // Sec 3.4.3 "No data transfer to the computer memory is performed"; the
    // memory address still ends at start + word count and the word count at 0
    // (nd100x BUGS.md W8: DISC-TEMA J02 PARITY-CHECK reads the address back
    // after every M2). 1536 words = 3 sectors in two chunks (1024 + 512), so
    // the chunk step of the M2 path is covered too.
    iox_write(BASE + R_LOAD_BLOCK, 16'd0);
    iox_write(BASE + R_LOAD_MA,    MA_HI_IN);
    iox_write(BASE + R_LOAD_MA,    MA_LO_IN);
    iox_write(BASE + R_LOAD_WC,    16'd1536);
    dma_words = 0;
    guard = disk_ops;
    iox_write(BASE + R_CONTROL,    16'o010005);   // M2 (2 << 11), activate, int enable
    wait_finish;
    iox_read(BASE + R_STATUS, st);
    if (st[4]) begin
      $display("FAIL: M2 reported an error, status %o", st);
      errors = errors + 1;
    end
    if (dma_words !== 0) begin
      $display("FAIL: M2 made %0d DMA cycles (sec 3.4.3: none)", dma_words);
      errors = errors + 1;
    end else $display("[ ok ] M2 made no DMA cycles");
    if (disk_ops - guard !== 2) begin
      $display("FAIL: M2 read %0d chunks off the disc, want 2 (1024 + 512 words)",
               disk_ops - guard);
      errors = errors + 1;
    end else $display("[ ok ] M2 read its 2 chunks off the disc");
    iox_read(BASE + R_READ_MA, ma_lo);
    iox_read(BASE + R_READ_MA, ma_hi);
    check_eq(ma_lo, 16'd1536, "M2: memory address low = start + 1536");
    check_eq(ma_hi, MA_HI_IN, "M2: memory address high unchanged");
    check_eq(dut.s_word_cnt, 16'd0, "M2: word count 0 at the end");
    iox_read(BASE + 16'd6, st);
    check_eq(st, 16'd3, "M2: block address moved on by 3 sectors");

    if (errors == 0)
      $display("TB_RESULT: PASS (Winchester MAR writeback matches the oracle)");
    else $display("TB_RESULT: FAIL %0d errors", errors);
    $finish;
  end

  initial begin
    #20_000_000;
    $display("TB_RESULT: FAIL absolute watchdog");
    $finish;
  end

endmodule
