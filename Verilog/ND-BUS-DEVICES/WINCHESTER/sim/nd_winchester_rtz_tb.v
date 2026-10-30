/*****************************************************************************
**  nd_winchester_rtz_tb.v                                                  **
**                                                                          **
**  Full path:                                                              **
**    Verilog/ND-BUS-DEVICES/WINCHESTER/sim/nd_winchester_rtz_tb.v          **
**                                                                          **
**  RTZ OBSERVABILITY. An M7 return-to-zero must stay readable as ACTIVE    **
**  (status b2) long enough for the guest to see it.                        **
**                                                                          **
**  WHY THIS BENCH EXISTS - 09-AUG-2026, from silicon.                      **
**                                                                          **
**  The nd100x oracle (oracle/fsi-lifi-nd100x-old-model.trace, the older    **
**  nd100x model; see oracle/README.md) is a capture of the                 **
**  File System Investigator opening the Winchester on a machine where it   **
**  WORKS. Its opening sequence is:                                         **
**                                                                          **
**      READ  +4 status  -> 020000     idle                                 **
**      WRITE +5 control =  034005     M7 return-to-zero                    **
**      READ  +4 status  -> 060005     <-- ACTIVE, seek still running       **
**      READ  +4 status  -> 060011     on cylinder, finished                **
**                                                                          **
**  On the Tang the same session produces:                                  **
**                                                                          **
**      READ  +4 status  -> 020000                                          **
**      WRITE +5 control =  034005                                          **
**      irq                                                                 **
**      READ  +4 status  -> 060011     <-- already finished, ACTIVE never   **
**                                         observed by the guest            **
**                                                                          **
**  Every value matches the oracle EXCEPT that the guest never catches the  **
**  operation running. ND_WINCHESTER.v gives an RTZ whose arm is already at **
**  cylinder 0 a fixed 8-tick completion instead of DELAY_TICKS, and at     **
**  power-on the arm IS at cylinder 0 - so the very first RTZ any guest     **
**  issues completes in about a microsecond.                                **
**                                                                          **
**  The existing oracle bench cannot see this. It checks ACTIVE only after  **
**  CTRL_GO (a data transfer, not an RTZ), and it reads status with ZERO    **
**  latency - on the very next bus cycle. A real guest cannot do that: it   **
**  executes several instructions between writing the control word and      **
**  getting its first status read onto the bus.                             **
**                                                                          **
**  GUEST_POLL_CLKS is that latency, and it is a measurement, not a guess.  **
**  The Tang runs the CPU/bus domain at 6.75 MHz (BOARD_CLK_FREQ in         **
**  fpga/tang-nano-20k/src/tang20k_defines.v, slow variant), so one clock   **
**  is ~148 ns. A single ND-100 IOX instruction is several microcode steps, **
**  and the guest issues at least a control write and a status read back to **
**  back. 100 clocks is ~15 us - a deliberately CONSERVATIVE lower bound on **
**  how soon any real driver can poll. If ACTIVE is gone before then, no    **
**  guest can ever observe the operation.                                   **
**                                                                          **
**  This bench does NOT assert which completion delay is correct. It        **
**  asserts only what the oracle proves: the guest must be able to see the  **
**  operation running.                                                      **
*****************************************************************************/

`timescale 1ns / 1ps

module nd_winchester_rtz_tb;

  localparam [15:0] BASE = 16'o000500;

  localparam R_STATUS  = 16'd4;
  localparam R_CONTROL = 16'd5;

  // M7 return-to-zero, unit 0, interrupt enabled - the exact control word the
  // File System Investigator writes, taken from the oracle trace.
  localparam [15:0] CTRL_RTZ = 16'o034005;

  // See the header: a conservative floor on the guest's first poll.
  localparam integer GUEST_POLL_CLKS = 100;

  // Long enough that a moving seek is unambiguously observable, short enough
  // to keep the bench quick. The silicon value is 8 ms of clocks.
  localparam [31:0] TB_DELAY_TICKS = 32'd2000;

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

  ND_WINCHESTER #(.DELAY_TICKS(TB_DELAY_TICKS)) dut (
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
      // dbuf_rdata is an OUTPUT (ND_WINCHESTER.v:192) and this bench does not
      // read the sector buffer. Left unconnected on purpose - driving it from
      // the bench would fight the DUT.
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

  integer errors = 0;

  // Mirror ND_BUS_SLAVE's capture - see the note in nd_winchester_oracle_tb.v.
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

  // Free-running clock counter so the ACTIVE window can be reported in clocks
  // rather than in bus transactions, which vary in length.
  integer clkcount = 0;
  always @(posedge sysclk) clkcount = clkcount + 1;

  reg [15:0] st;
  integer t_go, t_last_active, t_finished;
  integer polls;

  initial begin
    $display("=== Winchester RTZ observability ===");
    repeat (6) @(posedge sysclk);
    sys_rst_n = 1;
    repeat (6) @(posedge sysclk);

    // Power-on state: the arm is at cylinder 0, which is exactly the case the
    // File System Investigator hits on its first RTZ.
    iox_read(BASE + R_STATUS, st);
    $display("[info] status before the RTZ = %o", st);
    if (st[2]) begin
      $display("FAIL: controller reports ACTIVE before any operation was issued");
      errors = errors + 1;
    end

    // Issue the RTZ and then watch the status register, recording the last
    // moment ACTIVE is still readable.
    iox_write(BASE + R_CONTROL, CTRL_RTZ);
    t_go          = clkcount;
    t_last_active = -1;
    t_finished    = -1;
    polls         = 0;

    while ((t_finished < 0) && (polls < 20000)) begin
      iox_read(BASE + R_STATUS, st);
      polls = polls + 1;
      if (st[2]) t_last_active = clkcount;
      if (st[3]) t_finished    = clkcount;
      if (st[2] && st[3]) begin
        $display("FAIL: status %o reports ACTIVE and FINISHED at once", st);
        errors = errors + 1;
      end
    end

    if (t_finished < 0) begin
      $display("FAIL: the RTZ never reported FINISHED after %0d polls", polls);
      errors = errors + 1;
    end else begin
      $display("[info] RTZ finished %0d clocks after the control word",
               t_finished - t_go);
    end

    if (t_last_active < 0) begin
      $display("FAIL: ACTIVE (status b2) was NEVER observable during the RTZ.");
      $display("      The oracle's guest reads 060005 here - see the header.");
      errors = errors + 1;
    end else begin
      $display("[info] ACTIVE last observed %0d clocks after the control word",
               t_last_active - t_go);
      if ((t_last_active - t_go) < GUEST_POLL_CLKS) begin
        $display("FAIL: ACTIVE window is %0d clocks, shorter than the %0d-clock",
                 t_last_active - t_go, GUEST_POLL_CLKS);
        $display("      floor on a guest's first poll. No real driver can see");
        $display("      this operation run. Silicon symptom: the File System");
        $display("      Investigator reads 060011 where the oracle reads 060005.");
        errors = errors + 1;
      end else begin
        $display("[ ok ] ACTIVE observable for %0d clocks (>= %0d required)",
                 t_last_active - t_go, GUEST_POLL_CLKS);
      end
    end

    // The RTZ must still finish on cylinder 0 with the completion bit set.
    iox_read(BASE + R_STATUS, st);
    if (!st[14]) begin
      $display("FAIL: not on cylinder after the RTZ (status %o)", st);
      errors = errors + 1;
    end else $display("[ ok ] on cylinder after the RTZ (status %o)", st);

    if (errors == 0)
      $display("TB_RESULT: PASS (RTZ stays observable to the guest)");
    else
      $display("TB_RESULT: FAIL (%0d error(s))", errors);
    $finish;
  end

endmodule
