/*****************************************************************************
**  nd_smd_timing_tb.v                                                      **
**                                                                          **
**  REAL DRIVE TIMING (ND_SMD FAST = 0).                                    **
**                                                                          **
**  With FAST = 0 the SMD card and its drives take as long as nd100x says   **
**  (device_smd.c "THE DRIVE'S TIMING", the CDC 976x figures: 3600 r/min,   **
**  seek one track 6 ms, average 30 ms, full stroke 55 ms). This bench      **
**  works out what each operation must take with nd100x's own formulas     **
**  (smd_seek_ticks, smd_transfer_ticks, the Write Format timing in         **
**  execute_go), written out again here independently of the RTL, and      **
**  checks the RTL against them:                                            **
**                                                                          **
**   - a drive's seek (M4) of 0, 1, 100, 274 (the knee), 300 and 747        **
**     cylinders, and a Return To Zero (M7) from cylinder 822: the time     **
**     the unit reads NOT on cylinder. The controller's own operation must  **
**     end at once (measured on silicon: SINTRAN polls only about 17,000    **
**     cycles after an M4);                                                 **
**   - a transfer on the cylinder the arm is on: it must end as its last    **
**     sector has passed the head, whatever the phase was when it started;  **
**   - a transfer with a seek: the seek, then the wait for the sector, then **
**     the sectors - again it ends as the last sector has passed;           **
**   - Write Format (M5): the wait for the index (sector 0), then one       **
**     revolution per track;                                                **
**   - a test-mode transfer: the flat floor (nd100x IODELAY_HDD_SMD);       **
**   - Seek Complete Search (M6) with no seek given: the 500 ms timeout;    **
**     with a seek given: until the unit's heads arrive.                    **
**                                                                          **
**  Times are counted in clocks the controller reads ACTIVE (dut.s_active), **
**  or the unit reads off cylinder, so they are what a guest polling the    **
**  status would see. TOL clocks of slack cover the states' own clocks.     **
**                                                                          **
**  CLK_HZ is 3 MHz here, not a board's clock, to keep the run short; the   **
**  formulas scale with it. FAST = 1 (the default) is covered by every      **
**  other bench in this folder. The card is strapped as the single-write    **
**  (ECC) type so each register loads in one write; the timing does not     **
**  depend on the strap.                                                    **
*****************************************************************************/

`timescale 1ns / 1ps

module nd_smd_timing_tb;

  localparam [15:0] BASE = 16'o001540;
  localparam R_STATUS = 16'd4;
  localparam R_CTRL   = 16'd5;
  localparam R_BLOCK  = 16'd3;
  localparam R_WC     = 16'd7;
  localparam R_CORE   = 16'd1;

  localparam [15:0] CW_GO   = 16'h0004;
  localparam [15:0] CW_TEST = 16'h0008;
  localparam [15:0] CW_CWR  = 16'h8000;
  localparam [15:0] CW_CLR  = 16'h0010;
  // Operation code in b11-14: M0 = 0, M4 = 4, M5 = 5, M6 = 6, M7 = 7.
  localparam [15:0] OP_READ   = 16'h0000;
  localparam [15:0] OP_SEEK   = 16'h2000;
  localparam [15:0] OP_FORMAT = 16'h2800;
  localparam [15:0] OP_SEARCH = 16'h3000;
  localparam [15:0] OP_RTZ    = 16'h3800;

  localparam integer CLK_HZ = 3_000_000;
  localparam integer SPT    = 18;
  localparam integer CYLS   = 823;
  localparam integer TOL    = 3;

  // nd100x's figures, in this bench's clock.
  localparam integer T_MS        = CLK_HZ / 1000;
  localparam integer T_SEEK_ONE  = 6  * T_MS;
  localparam integer T_SEEK_AVG  = 30 * T_MS;
  localparam integer T_SEEK_FULL = 55 * T_MS;
  localparam integer T_SECTOR    = (CLK_HZ / 60) / SPT;
  localparam integer T_REV       = T_SECTOR * SPT;
  localparam integer T_MIN       = CLK_HZ / 50_000;
  localparam integer T_TIMEOUT   = CLK_HZ / 2;

  // nd100x smd_seek_ticks, written out again (multiply first, divide once).
  function integer seek_exp(input integer distance);
    integer full, third;
    begin
      full  = CYLS - 1;
      third = full / 3;
      if (distance <= 0)
        seek_exp = 0;
      else if (distance <= third)
        seek_exp = T_SEEK_ONE + ((T_SEEK_AVG - T_SEEK_ONE) * (distance - 1)) / (third - 1);
      else begin
        if (distance > full) distance = full;
        seek_exp = T_SEEK_AVG + ((T_SEEK_FULL - T_SEEK_AVG) * (distance - third)) / (full - third);
      end
    end
  endfunction
  // A drive's own seek: nd100x gives a seek of no distance its 10-tick floor.
  function integer arm_exp(input integer distance);
    arm_exp = (distance == 0) ? T_MIN : seek_exp(distance);
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
  reg         dma_ack = 1'b0;
  wire        disk_start, disk_req, disk_wr;
  wire [15:0] disk_blkaddr1, disk_blkaddr2;
  wire [2:0]  disk_unit;
  wire [10:0] disk_wordcount;
  reg         disk_done = 1'b0;

  ND_SMD #(.DELAY_TICKS(32'd10), .CLK_HZ(CLK_HZ), .FAST(1'b0),
           .HAS_WC_FLIPFLOP(0)) dut (
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
      .disk_err_in   (1'b0),
      .disk_err_code (4'd0),
      .dbuf_addr     (10'd0),
      .dbuf_wdata    (16'd0),
      .dbuf_we       (1'b0),
      .dbuf_rdata    ()
  );

  // DMA: every request answered on the next clock.
  always @(posedge sysclk) begin
    dma_ack <= 1'b0;
    if (dma_req && !dma_ack) dma_ack <= 1'b1;
  end

  // Disk backend: done two clocks after a request (the data is not looked at).
  reg [1:0] disk_dly = 2'd0;
  always @(posedge sysclk) begin
    disk_done <= 1'b0;
    if (disk_req) disk_dly <= 2'd2;
    else if (disk_dly != 2'd0) begin
      disk_dly <= disk_dly - 2'd1;
      if (disk_dly == 2'd1) disk_done <= 1'b1;
    end
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

  // Clocks the controller reads ACTIVE, and clocks unit 0 / unit 1 read off
  // cylinder, counted while they do.
  integer active_clks = 0;
  integer off0_clks   = 0;
  always @(posedge sysclk) begin
    if (dut.s_active)     active_clks = active_clks + 1;
    if (!dut.s_on_cyl[0]) off0_clks   = off0_clks + 1;
  end

  integer errors = 0;
  integer got, rot_end;
  reg [15:0] st;

  // Load block address I (head/sector) and II (cylinder), and the word count.
  task load(input [15:0] cyl, input [7:0] head, input [7:0] sec, input [15:0] wc);
    begin
      iox_write(BASE + R_CTRL, CW_CWR);           // CWR = 1, no GO
      iox_write(BASE + R_BLOCK, cyl);
      iox_write(BASE + R_CTRL, 16'h0000);         // CWR = 0
      iox_write(BASE + R_BLOCK, {head, sec});
      iox_write(BASE + R_WC, wc);
      iox_write(BASE + R_CORE, 16'o010000);
    end
  endtask

  // Give a control word and wait for the operation to end; `got` is how long
  // it read ACTIVE and `rot_end` where the disc was when it ended.
  task run_op(input [15:0] cw);
    integer guard;
    begin
      active_clks = 0;
      iox_write(BASE + R_CTRL, cw | CW_GO);
      guard = 0;
      while (dut.s_active && guard < 2_000_000) begin
        @(posedge sysclk);
        guard = guard + 1;
      end
      rot_end = dut.r_rot;
      got = active_clks;
      if (dut.s_active) begin
        $display("FAIL: control word %o never finished", cw);
        errors = errors + 1;
      end
    end
  endtask

  task expect_time(input [8*48-1:0] what, input integer want);
    begin
      if (got < want || got > want + TOL) begin
        $display("FAIL: %0s took %0d clocks, nd100x's formula gives %0d", what, got, want);
        errors = errors + 1;
      end else
        $display("[ ok ] %0s: %0d clocks (formula %0d)", what, got, want);
    end
  endtask

  // The time must lie in [lo, hi] (a transfer's rotation wait is unknown
  // in advance; expect_rot pins it).
  task expect_range(input [8*48-1:0] what, input integer lo, input integer hi);
    begin
      if (got < lo || got > hi + TOL) begin
        $display("FAIL: %0s took %0d clocks, outside %0d .. %0d", what, got, lo, hi);
        errors = errors + 1;
      end else
        $display("[ ok ] %0s: %0d clocks (%0d .. %0d)", what, got, lo, hi);
    end
  endtask

  // The disc must stand at `sector` times the sector time when the
  // operation ends, within TOL clocks either way round the revolution.
  task expect_rot(input [8*48-1:0] what, input integer sector);
    integer want, diff;
    begin
      want = (sector * T_SECTOR) % T_REV;
      diff = rot_end - want;
      if (diff < 0) diff = -diff;
      if (diff > T_REV / 2) diff = T_REV - diff;
      if (diff > TOL) begin
        $display("FAIL: %0s ended with the disc at %0d, sector %0d starts at %0d",
                 what, rot_end, sector, want);
        errors = errors + 1;
      end else
        $display("[ ok ] %0s ended as sector %0d came under the head (disc at %0d)",
                 what, sector, rot_end);
    end
  endtask

  // Initiate Seek on unit 0 to `cyl`: the controller ends at once, the unit
  // reads off cylinder for the drive's seek time.
  task seek(input integer cyl, input integer moves, input [8*48-1:0] what);
    integer guard;
    begin
      load(cyl[15:0], 8'd0, 8'd0, 16'd0);
      off0_clks = 0;
      run_op(OP_SEEK);
      if (got > TOL) begin
        $display("FAIL: %0s kept the controller active %0d clocks", what, got);
        errors = errors + 1;
      end
      guard = 0;
      while (!dut.s_on_cyl[0] && guard < 1_000_000) begin
        @(posedge sysclk);
        guard = guard + 1;
      end
      @(posedge sysclk);
      got = off0_clks;
      // The drop and the rise each take a clock of their own.
      expect_time(what, arm_exp(moves) + 1);
      iox_read(BASE + 16'd2, st);       // seek condition
      if (!st[0]) begin
        $display("FAIL: after %0s the seek-complete bit of unit 0 is not set (%o)", what, st);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    $display("=== SMD real drive timing (FAST = 0), CLK_HZ = %0d ===", CLK_HZ);
    $display("[info] sector %0d clocks, revolution %0d, seek 6/30/55 ms = %0d/%0d/%0d",
             T_SECTOR, T_REV, T_SEEK_ONE, T_SEEK_AVG, T_SEEK_FULL);
    repeat (6) @(posedge sysclk);
    sys_rst_n = 1;
    repeat (6) @(posedge sysclk);
    iox_write(BASE + R_CTRL, 16'h0000);  // leave boot mode, select unit 0

    // ---- the drive's own seeks (the arm starts on cylinder 0) ----
    seek(0,   0,   "M4 seek of 0 cylinders");
    seek(1,   1,   "M4 seek of 1 cylinder");          // arm 1
    seek(101, 100, "M4 seek of 100 cylinders");       // arm 101
    seek(375, 274, "M4 seek of 274 (the knee)");      // arm 375
    seek(75,  300, "M4 seek of 300 cylinders in");    // arm 75
    seek(822, 747, "M4 seek of 747 cylinders");       // arm 822

    // Return To Zero from the last cylinder: a full stroke home; on
    // cylinder again without a new seek-complete bit is checked in
    // nd_smd_err_tb.v.
    load(16'd0, 8'd0, 8'd0, 16'd0);
    off0_clks = 0;
    run_op(OP_RTZ);
    if (got > TOL) begin
      $display("FAIL: M7 kept the controller active %0d clocks", got);
      errors = errors + 1;
    end
    while (!dut.s_on_cyl[0]) @(posedge sysclk);
    @(posedge sysclk);
    got = off0_clks;
    expect_time("M7 return to zero from cylinder 822", arm_exp(822) + 1);

    // ---- a transfer on the arm's cylinder ----
    // Let the disc turn to an arbitrary phase, then read 2 sectors from
    // sector 3 of cylinder 0: it ends as sector 5 comes round, between 2 and
    // 2 + 18 sector times after the GO.
    repeat (12345) @(posedge sysclk);
    load(16'd0, 8'd0, 8'd3, 16'd1024);
    run_op(OP_READ);
    expect_rot("M0 of sectors 3-4", 5);
    expect_range("M0 of 2 sectors, no seek", 2 * T_SECTOR, 2 * T_SECTOR + T_REV);

    // ---- a transfer with a seek: cylinder 100 sector 7, one sector ----
    repeat (777) @(posedge sysclk);
    load(16'd100, 8'd1, 8'd7, 16'd512);
    run_op(OP_READ);
    expect_rot("M0 after a seek, sector 7", 8);
    expect_range("M0 with a seek of 100", seek_exp(100) + T_SECTOR,
                 seek_exp(100) + T_SECTOR + T_REV);
    // The transfer left the arm on cylinder 100: a seek there moves nothing.
    seek(100, 0, "M4 to where the transfer left the arm");

    // ---- Write Format: two tracks of cylinder 100, then with a seek ----
    repeat (4321) @(posedge sysclk);
    load(16'd100, 8'd0, 8'd0, 16'd72);    // 2 tracks x 18 sectors x 2 words
    run_op(OP_FORMAT);
    expect_rot("M5 of 2 tracks", 0);
    expect_range("M5 of 2 tracks, no seek", 2 * T_REV, 3 * T_REV);
    iox_read(BASE + R_STATUS, st);
    if (st[6] || st[12]) begin
      $display("FAIL: M5 of 2 tracks ended with timeout or abnormal completion (%o)", st);
      errors = errors + 1;
    end
    load(16'd300, 8'd0, 8'd0, 16'd36);    // 1 track, a seek of 200
    run_op(OP_FORMAT);
    expect_rot("M5 after a seek", 0);
    expect_range("M5 of 1 track with a seek of 200", seek_exp(200) + T_REV,
                 seek_exp(200) + 2 * T_REV);

    // ---- a test-mode transfer: the flat floor ----
    load(16'd0, 8'd0, 8'd0, 16'd2);
    run_op(OP_READ | CW_TEST);
    expect_time("test-mode M0 of 2 words", T_MIN);
    iox_write(BASE + R_CTRL, 16'h0000);   // test mode off

    // ---- Seek Complete Search ----
    // A seek given: M4 to cylinder 0 (the arm is on 300), then M6 at once.
    // The search ends when the heads arrive, just under the seek time after
    // the M6 (the M4 came a few clocks earlier).
    load(16'd0, 8'd0, 8'd0, 16'd0);
    iox_write(BASE + R_CTRL, OP_SEEK | CW_GO);
    run_op(OP_SEARCH);
    expect_range("M6 waiting for a seek of 300", seek_exp(300) - 20, seek_exp(300));
    iox_read(BASE + R_STATUS, st);
    if (st[6] || st[12]) begin
      $display("FAIL: M6 with a seek given ended with a timeout (%o)", st);
      errors = errors + 1;
    end
    // No seek given (a device clear forgets them): the 500 ms timeout.
    iox_write(BASE + R_CTRL, CW_CLR);
    iox_write(BASE + R_CTRL, 16'h0000);
    run_op(OP_SEARCH);
    expect_time("M6 with no seek: the timeout", T_TIMEOUT);
    iox_read(BASE + R_STATUS, st);
    if (!st[6] || !st[12]) begin
      $display("FAIL: M6 with no seek did not end with b6 and b12 (%o)", st);
      errors = errors + 1;
    end

    if (errors == 0)
      $display("TB_RESULT: PASS (real drive timing follows the nd100x model)");
    else
      $display("TB_RESULT: FAIL (%0d error(s))", errors);
    $finish;
  end

endmodule
