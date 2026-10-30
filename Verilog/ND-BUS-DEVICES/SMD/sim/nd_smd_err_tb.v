/**************************************************************************
** TESTBENCH: ND_SMD - ILLEGAL / ERROR path conformance                   **
**                                                                       **
** The other three SMD benches only ever exercise LEGAL sequences:        **
** nd_smd_iox_tb never issues a GO at all (control bit 2 stays 0), and    **
** nd_smd_tb / nd_smd_p2_tb drive well-formed transfers. Nothing tested   **
** what the controller does when the GUEST MISBEHAVES, so two real bugs   **
** lived in the register decode with every gate green:                    **
**   - +7 (Load Word Counter) had no illegal-load check at all            **
**   - +5 (Load Control Word) dropped the write silently instead of       **
**     raising b5, and blocked DEVICE CLEAR while the controller was      **
**     active - the one escape a stuck controller has                     **
** This bench closes that blind spot.                                     **
**                                                                       **
** Rules under test (ND-11.020.01 sec 2.5 / sec 2.6, ND-11.013.01A):     **
**   b5 "Illegal load" = "Load of ANY register while status bit 2 is      **
**   true". It is a STATUS FLAG ONLY: the running operation continues     **
**   (b2 stays 1), the write is ignored, the drive does NOT go            **
**   not-ready (b13) and does NOT leave the cylinder (b14). It applies    **
**   to all four loadable registers: +1 core address, +3 block address,   **
**   +5 control word, +7 word counter.                                    **
**                                                                       **
**   Device clear (control word b4) is the "programmed master clear" and  **
**   must ALWAYS reach the controller, including while it is active -     **
**   it clears b2 and the error bits.                                     **
**                                                                       **
** Method: a Seek Complete Search (M6) with no seek given holds the       **
** controller active until its 500 ms timeout, with no disk backend       **
** involved (nd100x: the search has nothing to find). The DUT is given a  **
** small CLK_HZ so that 500 ms is a short window of sysclks. Register     **
** writes are issued inside that window. NOT M4 or M7: both end the       **
** controller's operation at once (nd100x finish_operation) and leave the **
** drive moving, which is the off-cylinder case of section 8.             **
**                                                                       **
** Off cylinder (nd100x load_is_illegal, the DISC-TEMA manual's b5 "load  **
** while the unit is NOT ON CYLINDER"): after an M4 the unit's heads move **
** for DELAY_TICKS; a load of +1, +3 or +7 in that time is an illegal     **
** load although the controller is not active, while the control word    **
** stays loadable. When the heads arrive the unit is on cylinder and its  **
** seek-complete bit is set.                                              **
**                                                                       **
** Verdict line: TB_RESULT: PASS / TB_RESULT: FAIL                       **
**                                                                       **
** Ronny Hansen                                                          **
***************************************************************************/

`timescale 1ns / 1ps

module nd_smd_err_tb;

  localparam [15:0] BASE = 16'o001540;

  // The drive's seek time (FAST = 1: every drive movement takes DELAY_TICKS).
  localparam [31:0] LONG_DELAY = 32'd2000;
  // sysclk frequency given to the DUT: the M6 timeout is CLK_HZ / 2 = 2000
  // sysclks, long enough that a GO stays active across many IOX cycles,
  // short enough that the bench finishes quickly.
  localparam integer TB_CLK_HZ = 4000;

  // status bit positions (see the s_status assembly in ND_SMD.v)
  localparam SB_CWR      = 15;
  localparam SB_ONCYL    = 14;
  localparam SB_NOTREADY = 13;
  localparam SB_ILLEGAL  = 5;
  localparam SB_INCLOR   = 4;
  localparam SB_RFT      = 3;
  localparam SB_ACTIVE   = 2;

  reg sysclk = 0;
  reg sys_rst_n = 0;
  always #10 sysclk = ~sysclk;

  reg  [15:0] iox_addr  = 16'd0;
  reg         iox_wr    = 1'b0;
  reg  [15:0] iox_wdata = 16'd0;
  reg         iox_rd    = 1'b0;
  wire [15:0] iox_rdata;
  wire [3:0]  int_pending;
  wire        ident_grant_out, ident_hit;
  wire [15:0] ident_code;

  wire        dma_req, dma_wr;
  wire [23:0] dma_addr;
  wire [15:0] dma_wdata;
  wire        disk_start, disk_req, disk_wr;
  wire [15:0] disk_blkaddr1, disk_blkaddr2;
  wire [2:0]  disk_unit;
  wire [10:0] disk_wordcount;
  wire [15:0] dbuf_rdata;

  ND_SMD #(.HAS_WC_FLIPFLOP(1), .DELAY_TICKS(LONG_DELAY), .CLK_HZ(TB_CLK_HZ)) dut (
      .sysclk        (sysclk),
      .sys_rst_n     (sys_rst_n),
      .iox_addr      (iox_addr),
      .iox_wr        (iox_wr),
      .iox_wdata     (iox_wdata),
      .iox_rd        (iox_rd),
      .iox_rdata     (iox_rdata),
      .int_pending   (int_pending),
      .ident_strobe  (1'b0),
      .ident_level   (4'd0),
      .ident_grant_in(1'b0),
      .ident_grant_out(ident_grant_out),
      .ident_hit     (ident_hit),
      .ident_code    (ident_code),
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
      .disk_done     (1'b0),
      .disk_err_in   (1'b0),
      .dbuf_addr     (10'd0),
      .dbuf_wdata    (16'd0),
      .dbuf_we       (1'b0),
      .dbuf_rdata    (dbuf_rdata)
  );

  integer errors = 0;
  task check(input cond, input [1023:0] msg);
    begin
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

  // Leave boot mode / select a unit with a NON-GO control word.
  task select_unit(input [2:0] unit);
    reg [15:0] cw;
    begin
      cw       = 16'd0;
      cw[9:7]  = unit;
      iox_write(BASE + 16'd5, cw);
    end
  endtask

  // GO with op M6 (seek complete search) on unit 0 and no seek given: no
  // disk backend needed, the engine waits in E_SEARCH for the timeout with
  // b2 held high. (M4 and M7 would complete at once.)
  task go_seek;
    reg [15:0] cw;
    begin
      cw        = 16'd0;
      cw[2]     = 1'b1;      // activate
      cw[14:11] = 4'd6;      // M6 seek complete search
      iox_write(BASE + 16'd5, cw);
    end
  endtask

  // Device clear (control word b4) - the programmed master clear.
  task device_clear;
    reg [15:0] cw;
    begin
      cw    = 16'd0;
      cw[4] = 1'b1;
      iox_write(BASE + 16'd5, cw);
    end
  endtask

  reg [15:0] st;

  // One illegal-load case: with the controller active, write `data` to
  // register `off` and assert the full b5 contract.
  task illegal_load_case(input [15:0] off, input [15:0] data, input [1023:0] name);
    begin
      go_seek;
      iox_read(BASE + 16'd4, st);
      check(st[SB_ACTIVE], {name, " : precondition - controller must be active after GO"});
      check(!st[SB_ILLEGAL], {name, " : precondition - b5 must start clear"});

      iox_write(BASE + off, data);

      iox_read(BASE + 16'd4, st);
      check(st[SB_ILLEGAL],   {name, " : b5 (illegal load) must be set"});
      check(st[SB_INCLOR],    {name, " : b4 (inclusive OR) must follow b5"});
      check(st[SB_ACTIVE],    {name, " : b2 must STAY set - the operation continues"});
      check(!st[SB_NOTREADY], {name, " : b13 must NOT be set - illegal load is not a drive fault"});
      check(st[SB_ONCYL],     {name, " : b14 must stay set - the arm does not move"});

      device_clear;
      iox_read(BASE + 16'd4, st);
      check(!st[SB_ILLEGAL], {name, " : device clear must clear b5"});
      check(!st[SB_ACTIVE],  {name, " : device clear must clear b2"});
    end
  endtask

  initial begin
    sys_rst_n = 1'b0;
    repeat (4) @(negedge sysclk);
    sys_rst_n = 1'b1;
    repeat (2) @(negedge sysclk);

    $display("ND_SMD illegal / error path conformance");

    // Leave boot mode and select unit 0 (also puts it on-cylinder).
    select_unit(3'd0);

    // =================================================================
    // 1-4. Illegal load on EVERY loadable register while active.
    //      +7 and +5 are the two that were unchecked; +1 and +3 are here
    //      so the rule is pinned for all four, not just the fixed pair.
    // =================================================================
    illegal_load_case(16'd1, 16'h1234, "+1 core address");
    illegal_load_case(16'd3, 16'h0400, "+3 block address");
    illegal_load_case(16'd7, 16'h0200, "+7 word counter");

    // +5 control word: a non-device-clear control word while active must
    // raise b5 AND be discarded. The attempted word sets CWR (b15) and
    // int-enable (b0), so a status read proves whether it took effect.
    go_seek;
    iox_read(BASE + 16'd4, st);
    check(st[SB_ACTIVE], "+5 control word : precondition - active after GO");
    check(!st[SB_CWR],   "+5 control word : precondition - CWR starts clear");

    iox_write(BASE + 16'd5, 16'h8001);   // b15 CWR + b0 int-enable, no b4

    iox_read(BASE + 16'd4, st);
    check(st[SB_ILLEGAL], "+5 control word : b5 (illegal load) must be set");
    check(st[SB_ACTIVE],  "+5 control word : b2 must stay set");
    check(!st[SB_CWR],    "+5 control word : the discarded write must NOT change CWR");
    check(!st[0],         "+5 control word : the discarded write must NOT enable interrupts");

    // =================================================================
    // 5. DEVICE CLEAR WHILE ACTIVE must get through. This is the escape
    //    hatch: if +5 were rejected wholesale while active (as it was),
    //    a stuck controller could never be recovered by software.
    // =================================================================
    device_clear;
    iox_read(BASE + 16'd4, st);
    check(!st[SB_ACTIVE],   "device clear while active : b2 must be cleared");
    check(!st[SB_ILLEGAL],  "device clear while active : b5 must be cleared");
    check(!st[SB_INCLOR],   "device clear while active : b4 must be cleared");
    check(!st[SB_RFT],      "device clear while active : b3 (RFT) must be low");

    // =================================================================
    // 6. A LEGAL load after the controller goes idle must still work -
    //    the illegal-load rule must not leave the register decode stuck
    //    rejecting writes once b2 has dropped.
    // =================================================================
    select_unit(3'd0);
    iox_read(BASE + 16'd4, st);
    check(!st[SB_ACTIVE],  "post-clear : controller must be idle");
    iox_write(BASE + 16'd3, 16'h0400);   // block address, legal now
    iox_read(BASE + 16'd4, st);
    check(!st[SB_ILLEGAL], "post-clear : a legal load must NOT raise b5");

    // =================================================================
    // 7. GO on a NOT-SPECIFIED unit (b9 set = units 4-7, no drive) must
    //    raise hardware error b7 and must NOT leave the controller active
    //    - the stuck-active class of bug.
    // =================================================================
    begin : not_specified_unit
      reg [15:0] cw;
      cw        = 16'd0;
      cw[2]     = 1'b1;        // activate
      cw[9:7]   = 3'd4;        // unit 4 - does not exist
      cw[14:11] = 4'd0;        // M0 read
      iox_write(BASE + 16'd5, cw);

      iox_read(BASE + 16'd4, st);
      check(st[7],            "not-specified unit : b7 (hardware error) must be set");
      check(!st[SB_ACTIVE],   "not-specified unit : b2 must NOT stay set");
      check(st[SB_NOTREADY],  "not-specified unit : b13 must be set");
    end

    // =================================================================
    // 8. OFF CYLINDER. An Initiate Seek (M4) ends the controller's
    //    operation at once; the unit's heads then move for DELAY_TICKS.
    //    A data-register load in that time is an illegal load with b2 at 0
    //    (nd100x load_is_illegal); the control word stays loadable. The
    //    heads' arrival sets on-cylinder and the unit's seek-complete bit.
    // =================================================================
    begin : off_cylinder
      reg [15:0] sc;
      device_clear;
      iox_write(BASE + 16'd5, 16'h8000);   // CWR = 1, unit 0, no GO
      iox_write(BASE + 16'd3, 16'd100);    // block address II = cylinder 100
      iox_write(BASE + 16'd5, 16'h2004);   // GO, M4, unit 0, CWR = 0
      iox_read(BASE + 16'd4, st);
      check(!st[SB_ACTIVE],  "M4 : the controller's operation ends at once (b2 = 0)");
      check(st[SB_RFT],      "M4 : b3 (finished) is set at once");
      check(!st[SB_ONCYL],   "M4 : the unit drops on-cylinder (b14 = 0)");
      iox_read(BASE + 16'd2, sc);
      check(!sc[0],          "M4 : no seek-complete bit before the heads arrive");

      iox_write(BASE + 16'd3, 16'o000400); // block address I while off cylinder
      iox_read(BASE + 16'd4, st);
      check(st[SB_ILLEGAL],  "off cylinder : +3 load is an illegal load (b5)");
      check(st[12],          "off cylinder : the illegal load sets b12");
      check(!st[SB_ACTIVE],  "off cylinder : b2 stays 0");

      iox_write(BASE + 16'd5, 16'h0001);   // control word, int-enable, no GO
      iox_read(BASE + 16'd4, st);
      check(st[0],           "off cylinder : the control word is still loaded (b0 = 1)");

      repeat (LONG_DELAY + 20) @(negedge sysclk);
      iox_read(BASE + 16'd4, st);
      check(st[SB_ONCYL],    "M4 : on cylinder again when the heads arrive");
      iox_read(BASE + 16'd2, sc);
      check(sc[0],           "M4 : seek-complete bit 0 set when the heads arrive");
      check(!sc[11],         "M4 : no seek error");

      // M6 now finds the seek it was given: it ends at once, without the
      // timeout, and the GO clears the old b5 / b12.
      iox_write(BASE + 16'd5, 16'h3004);   // GO, M6, unit 0
      repeat (4) @(negedge sysclk);
      iox_read(BASE + 16'd4, st);
      check(!st[SB_ACTIVE],  "M6 after M4 : ends when it sees the seek-complete bit");
      check(!st[6],          "M6 after M4 : no timeout (b6)");
      check(!st[12],         "M6 after M4 : no abnormal completion (b12)");
      check(!st[SB_ILLEGAL], "M6 after M4 : the GO cleared b5");
      iox_write(BASE + 16'd3, 16'o000400); // legal now
      iox_read(BASE + 16'd4, st);
      check(!st[SB_ILLEGAL], "on cylinder : +3 load is legal again");

      // Return To Zero on unit 1: on-cylinder drops, comes back, and NO
      // seek-complete bit (nd100x smd_rtz_end).
      iox_write(BASE + 16'd5, 16'h3884);   // GO, M7, unit 1  (7<<11 | 1<<7 | 4)
      iox_read(BASE + 16'd4, st);
      check(!st[SB_ACTIVE],  "M7 : the controller's operation ends at once");
      check(!st[SB_ONCYL],   "M7 : the unit drops on-cylinder");
      repeat (LONG_DELAY + 20) @(negedge sysclk);
      iox_read(BASE + 16'd4, st);
      check(st[SB_ONCYL],    "M7 : on cylinder again at cylinder 0");
      iox_read(BASE + 16'd2, sc);
      check(!sc[1],          "M7 : no seek-complete bit for unit 1");
    end

    // =================================================================
    // 9. M6 with no seek given: active for the whole 500 ms window, then
    //    the timeout, b6 with b12 (nd100x smd_timeout_end).
    // =================================================================
    device_clear;                        // forgets the seeks given
    select_unit(3'd0);
    go_seek;
    repeat (TB_CLK_HZ / 2 - 50) @(negedge sysclk);
    iox_read(BASE + 16'd4, st);
    check(st[SB_ACTIVE],   "M6 timeout : still active just before 500 ms");
    repeat (100) @(negedge sysclk);
    iox_read(BASE + 16'd4, st);
    check(!st[SB_ACTIVE],  "M6 timeout : not active after 500 ms");
    check(st[SB_RFT],      "M6 timeout : b3 set");
    check(st[6],           "M6 timeout : b6 (timeout) set");
    check(st[12],          "M6 timeout : b12 (abnormal completion) set");
    check(st[SB_INCLOR],   "M6 timeout : b4 follows b6");

    if (errors == 0)
      $display("TB_RESULT: PASS");
    else
      $display("TB_RESULT: FAIL (%0d checks failed)", errors);

    $finish;
  end

endmodule
