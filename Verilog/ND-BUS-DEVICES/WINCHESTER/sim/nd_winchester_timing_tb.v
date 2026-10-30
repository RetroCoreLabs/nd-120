/*****************************************************************************
**  nd_winchester_timing_tb.v                                               **
**                                                                          **
**  Full path:                                                              **
**    Verilog/ND-BUS-DEVICES/WINCHESTER/sim/nd_winchester_timing_tb.v       **
**                                                                          **
**  REAL DRIVE TIMING (ND_WINCHESTER FAST = 0).                             **
**                                                                          **
**  With FAST = 0 an operation keeps the controller ACTIVE for as long as   **
**  the drive takes. The model is nd100x device_winchester.c "DRIVE        **
**  TIMING", from the Micropolis 1320 series figures: track-to-track seek   **
**  6 ms, average 28 ms, maximum 62 ms, 3600 rpm. This bench computes what  **
**  each operation must take with nd100x's own formulas (wd_seek_ticks,     **
**  wd_transfer_ticks), written out again here independently of the RTL -  **
**  multiply first, divide once - and checks the RTL against them:          **
**                                                                          **
**   - seeks of 0, 1, 100, 341 (the knee), 500 and 942 cylinders, a stroke  **
**     clamped at the last cylinder, and RTZ from cylinder 1023 and from 0; **
**   - a read: it must end when its last sector has passed the head, i.e.   **
**     with the disc at (first sector + sectors) * sector time, whatever    **
**     the phase was when it started;                                       **
**   - an address mismatch: it ends after the one sector it looked for.     **
**                                                                          **
**  The time is measured as the number of clocks the controller reads       **
**  ACTIVE (dut.s_active), so it is the time a guest polling the status     **
**  would see. TOL clocks of slack cover the completion state's own clock.  **
**                                                                          **
**  CLK_HZ is 3 MHz here, not a board's clock, to keep the run short; the   **
**  formulas scale with it. FAST = 1 (the default) is covered by every      **
**  other bench in this folder.                                             **
*****************************************************************************/

`timescale 1ns / 1ps

module nd_winchester_timing_tb;

  localparam [15:0] BASE = 16'o000500;
  localparam R_STATUS     = 16'd4;
  localparam R_CONTROL    = 16'd5;
  localparam R_LOAD_BLOCK = 16'd3;
  localparam R_LOAD_WC    = 16'd7;

  localparam [15:0] CW_ACTIVE = 16'h0004;
  localparam [15:0] CW_DIR    = 16'h4000;   // M4: 1 = away from cylinder 0
  // Operation code in b11-13 (sec 3.4): M0 = 0, M4 = 4 << 11, M7 = 7 << 11.
  // 034005 is the File System Investigator's own RTZ word (oracle trace).
  localparam [15:0] OP_READ   = 16'o000000;
  localparam [15:0] OP_SEEK   = 16'o020000;
  localparam [15:0] OP_RTZ    = 16'o034000;

  localparam integer CLK_HZ = 3_000_000;
  localparam integer SPT    = 9;
  localparam integer CYLS   = 1024;
  localparam integer TOL    = 3;

  // nd100x's figures, in this bench's clock.
  localparam integer T_MS        = CLK_HZ / 1000;
  localparam integer T_SEEK_ONE  = 6  * T_MS;
  localparam integer T_SEEK_AVG  = 28 * T_MS;
  localparam integer T_SEEK_FULL = 62 * T_MS;
  localparam integer T_SECTOR    = (CLK_HZ / 60) / SPT;
  localparam integer T_REV       = T_SECTOR * SPT;
  localparam integer T_MIN       = CLK_HZ / 50_000;

  // nd100x wd_seek_ticks, written out again (multiply first, divide once).
  function integer seek_exp(input integer distance);
    integer full, third;
    begin
      full  = CYLS - 1;
      third = full / 3;
      if (distance <= 0)
        seek_exp = T_MIN;   // nd100x: 0, raised to its floor IODELAY_HDD
      else if (distance <= third)
        seek_exp = T_SEEK_ONE + ((T_SEEK_AVG - T_SEEK_ONE) * (distance - 1)) / (third - 1);
      else begin
        if (distance > full) distance = full;
        seek_exp = T_SEEK_AVG + ((T_SEEK_FULL - T_SEEK_AVG) * (distance - third)) / (full - third);
      end
    end
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

  ND_WINCHESTER #(.DELAY_TICKS(32'd10), .CLK_HZ(CLK_HZ), .FAST(1'b0)) dut (
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

  always @(posedge sysclk) begin
    dma_ack <= 1'b0;
    if (dma_req && !dma_ack) dma_ack <= 1'b1;
  end

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

  // Clocks the controller reads ACTIVE, counted while it does.
  integer active_clks = 0;
  always @(posedge sysclk) if (dut.s_active) active_clks = active_clks + 1;

  integer errors = 0;
  integer got, rot_end;
  reg [15:0] st;

  // Give a control word and wait for the operation to end; `got` is how long
  // it read ACTIVE and `rot_end` where the disc was when it ended.
  task run_op(input [15:0] cw);
    integer guard;
    begin
      active_clks = 0;
      iox_write(BASE + R_CONTROL, cw | CW_ACTIVE);
      guard = 0;
      while (dut.s_active && guard < 400_000) begin
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

  task expect_time(input [8*40-1:0] what, input integer want);
    begin
      if (got < want || got > want + TOL) begin
        $display("FAIL: %0s took %0d clocks, nd100x's formula gives %0d", what, got, want);
        errors = errors + 1;
      end else
        $display("[ ok ] %0s: %0d clocks (formula %0d)", what, got, want);
    end
  endtask

  // Seek `steps` cylinders (out = away from 0) and check the time against
  // the distance the arm really moves.
  task seek(input integer steps, input out, input integer moves, input [8*40-1:0] what);
    begin
      iox_write(BASE + R_LOAD_WC, steps[15:0]);
      run_op(OP_SEEK | (out ? CW_DIR : 16'd0));
      expect_time(what, seek_exp(moves));
      iox_read(BASE + R_STATUS, st);
      if (!st[14] || !st[3]) begin
        $display("FAIL: after %0s status %o is not finished and on cylinder", what, st);
        errors = errors + 1;
      end
    end
  endtask

  // The disc must stand at `sector` times the sector time when a transfer
  // ends, within TOL clocks either way round the revolution.
  task expect_rot(input [8*40-1:0] what, input integer sector);
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

  initial begin
    $display("=== Winchester real drive timing (FAST = 0), CLK_HZ = %0d ===", CLK_HZ);
    $display("[info] sector %0d clocks, revolution %0d, seek 6/28/62 ms = %0d/%0d/%0d",
             T_SECTOR, T_REV, T_SEEK_ONE, T_SEEK_AVG, T_SEEK_FULL);
    repeat (6) @(posedge sysclk);
    sys_rst_n = 1;
    repeat (6) @(posedge sysclk);

    // RTZ with the arm already home: nothing to travel, the floor.
    run_op(OP_RTZ);
    expect_time("RTZ at cylinder 0", T_MIN);

    // Let the disc turn to an arbitrary phase, then read 2 sectors from
    // sector 3 of cylinder 0 (the arm is there): the read ends as sector 5
    // comes round, and takes between 2 and 2 + 9 sector times.
    repeat (12345) @(posedge sysclk);
    iox_write(BASE + R_LOAD_BLOCK, 16'd3);
    iox_write(BASE + R_LOAD_WC, 16'd1024);
    run_op(OP_READ);
    expect_rot("read of sectors 3-4", 5);
    if (got < 2 * T_SECTOR || got > 2 * T_SECTOR + T_REV + TOL) begin
      $display("FAIL: read of 2 sectors took %0d clocks, outside %0d .. %0d",
               got, 2 * T_SECTOR, 2 * T_SECTOR + T_REV);
      errors = errors + 1;
    end else
      $display("[ ok ] read of 2 sectors: %0d clocks", got);

    // Address mismatch: cylinder 5 while the arm is on 0. The card looks for
    // sector 7 as it comes round and ends after it.
    repeat (777) @(posedge sysclk);
    iox_write(BASE + R_LOAD_BLOCK, (16'd5 << 5) | 16'd7);
    iox_write(BASE + R_LOAD_WC, 16'd512);
    run_op(OP_READ);
    iox_read(BASE + R_STATUS, st);
    if (!st[8]) begin
      $display("FAIL: no address mismatch reading cylinder 5 with the arm on 0 (status %o)", st);
      errors = errors + 1;
    end
    expect_rot("address mismatch at sector 7", 8);

    // An address outside the drive (cylinder 1500 of 1024): nd100x ends it
    // through wd_end_later - the flat floor - and leaves the block address
    // where it was (device_winchester.c, the geometry bound check).
    iox_write(BASE + R_LOAD_BLOCK, (16'd1500 << 5) | 16'd2);
    iox_write(BASE + R_LOAD_WC, 16'd512);
    run_op(OP_READ);
    expect_time("address outside the drive", T_MIN);
    if (dut.s_blkaddr != ((16'd1500 << 5) | 16'd2)) begin
      $display("FAIL: an out-of-range mismatch moved the block address to %o", dut.s_blkaddr);
      errors = errors + 1;
    end else
      $display("[ ok ] out-of-range mismatch left the block address alone");

    // Seeks along the curve.
    seek(0,    1, 0,    "seek of 0 cylinders");
    seek(1,    1, 1,    "seek of 1 cylinder");          // arm 1
    seek(100,  1, 100,  "seek of 100 cylinders");       // arm 101
    seek(341,  1, 341,  "seek of 341 (the knee)");      // arm 442
    seek(500,  1, 500,  "seek of 500 cylinders");       // arm 942
    seek(2000, 0, 942,  "seek in, stopped at 0");       // arm 0
    seek(2000, 1, 1023, "seek out, stopped at 1023");   // arm 1023

    // RTZ from the last cylinder: a full stroke home.
    run_op(OP_RTZ);
    expect_time("RTZ from cylinder 1023", seek_exp(1023));

    if (errors == 0)
      $display("TB_RESULT: PASS (real drive timing follows the nd100x model)");
    else
      $display("TB_RESULT: FAIL (%0d error(s))", errors);
    $finish;
  end

endmodule
