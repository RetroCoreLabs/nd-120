`timescale 1ns / 1ps
`default_nettype none

/**************************************************************************
** TESTBENCH: ND_WINCHESTER - EXHAUSTIVE IOX ADDRESS DECODE, READ-MUX     **
** MAP, and the IDENT GRANT DAISY-CHAIN.                                  **
**                                                                       **
** DUT: Verilog/ND-BUS-DEVICES/WINCHESTER/                                **
**        circuit/ND_WINCHESTER.v                                        **
**                                                                       **
** WHY THIS BENCH EXISTS ALONGSIDE THE TEN OTHERS IN THIS DIRECTORY      **
**   nd_winchester_iox_tb.v already covers the register protocol, the    **
**   status constants and the section 4.1 interrupt probe. What it does  **
**   NOT cover, and what this bench adds, is pure wiring:                **
**                                                                       **
**   1. ADDRESS DECODE, EXHAUSTIVELY. The existing bench probes exactly  **
**      four addresses (base, base+7, base+8, o1540). This one drives    **
**      all 65536 values of iox_addr and requires iox_sel to be 1 for    **
**      precisely the eight addresses o500..o507 and 0 for the other     **
**      65528 - and requires iox_rdata to be ZERO on every one of those  **
**      65528, which is the repo's OR-bus rule (a disabled output drives **
**      0, never z, because the device read buses are OR-ed together).   **
**      A single wrong bit in the compare at ND_WINCHESTER.v:262 either  **
**      widens the claim into another card's block (the floppy is at     **
**      o1560, the SMD at o1540) or narrows it so half this card's own   **
**      registers stop answering; four sample points cannot see that.    **
**                                                                       **
**   2. THE IDENT GRANT DAISY-CHAIN. ident_grant_out is not referenced   **
**      ANYWHERE in the ten existing Winchester benches. It is the       **
**      output that lets the next card on level 11 - the floppy, ident   **
**      021 - ever be identified. This bench sweeps all 16 ident_level   **
**      values with and without grant_in, with and without a pending     **
**      interrupt, and pins ident_hit, ident_code AND ident_grant_out    **
**      for every one of those 64 combinations against the equations at  **
**      ND_WINCHESTER.v:411-415.                                         **
**                                                                       **
**   3. int_pending ONE-HOT. The existing bench only ever inspects bit 1.**
**      All four bits are checked here, so a level constant wired to the **
**      wrong bit of the vector at :407-410 fails.                       **
**                                                                       **
**   4. THE IS_3038 STRAP. Status bit 13 is the card identity (:387,     **
**      :393): constant 1 on the 3041, the live read/write gate on the   **
**      3038. Only the 3041 default is instantiated by the other         **
**      benches, so a second DUT with IS_3038=1 is instantiated here.    **
**                                                                       **
** WHERE THE REFERENCE MODEL COMES FROM                                  **
**   Read off the NETLIST of ND_WINCHESTER.v, not from the ND-11.019     **
**   card manual and not from either C model:                            **
**     262  s_addressed = (iox_addr[15:3] == BASE_ADDR[15:3])            **
**     263  iox_sel     = s_addressed        (no iox_rd/iox_wr term)     **
**     423-440 read mux, gated by s_rd_here = iox_rd && s_addressed:     **
**            +0 memory address half selected by s_ma_read_ff            **
**            +2 constant 0 ("IOX 502 Not used")                         **
**            +4 status, +6 block address, +1/+3/+5/+7 constant 0        **
**     407-415 int_pending / ident_hit / ident_code / ident_grant_out    **
**                                                                       **
** PINNED RTL BEHAVIOUR (recorded, not asserted to be correct)           **
**   N1. iox_sel is asserted by ADDRESS ALONE - it does not require      **
**       iox_rd or iox_wr. The bench checks that explicitly with both    **
**       strobes low, because that is what :263 says and a consumer      **
**       that treats iox_sel as "an access is happening" would be wrong. **
**   N2. Read address +2 returns a constant 0, which is indistinguish-   **
**       able from "not addressed" on the data lines. Only iox_sel       **
**       separates the two cases.                                        **
**   N3. The read alternator s_ma_read_ff advances at the END of an      **
**       access (:270-292), so the exhaustive sweep is run with the      **
**       clock STOPPED - no edges, no side effects, and the +0 half      **
**       stays the low 16 bits throughout.                               **
**                                                                       **
** BUILD MODES: ND_WINCHESTER.v has no FPGA_FF_MODE ifdef. The make      **
** target still builds and runs it a second time with -DFPGA_FF_MODE to  **
** demonstrate the results are identical.                                **
**                                                                       **
** HOW TO RUN                                                            **
**   cd Verilog/ND-BUS-DEVICES/WINCHESTER/sim && make test-wd-decode     **
**                                                                       **
** Ronny Hansen                                                          **
** 20-AUG-2026                                                           **
***************************************************************************/

module nd_winchester_decode_tb;

  localparam integer EXPECTED_CHECKS = 131494;

  localparam [15:0] BASE = 16'o000500;

  // register offsets, as in nd_winchester_iox_tb.v
  localparam R_READ_MA    = 16'd0;
  localparam R_LOAD_MA    = 16'd1;
  localparam R_LOAD_BLOCK = 16'd3;
  localparam R_STATUS     = 16'd4;
  localparam R_CONTROL    = 16'd5;
  localparam R_READ_BLOCK = 16'd6;

  localparam CW_INT_EN = 16'h0001;

  reg sysclk    = 1'b0;
  reg sys_rst_n = 1'b0;

  reg  [15:0] iox_addr  = 16'd0;
  reg         iox_wr    = 1'b0;
  reg  [15:0] iox_wdata = 16'd0;
  reg         iox_rd    = 1'b0;
  wire [15:0] iox_rdata;
  wire        iox_sel;
  wire [19:0] trace_rec;
  wire        trace_we;
  wire        trace_done;
  wire [3:0]  int_pending;
  reg         ident_strobe   = 1'b0;
  reg  [3:0]  ident_level    = 4'd0;
  reg         ident_grant_in = 1'b0;
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

  // second DUT, 8 inch card - only its status is looked at
  wire [15:0] iox_rdata_3038;
  wire        iox_sel_3038;
  wire [19:0] trace_rec_3038;
  wire        trace_we_3038, trace_done_3038;
  wire [3:0]  int_pending_3038;
  wire        ident_grant_out_3038, ident_hit_3038;
  wire [15:0] ident_code_3038;
  wire        dma_req_3038, dma_wr_3038;
  wire [23:0] dma_addr_3038;
  wire [15:0] dma_wdata_3038;
  wire        disk_start_3038, disk_req_3038, disk_wr_3038;
  wire [15:0] disk_blkaddr1_3038, disk_blkaddr2_3038;
  wire [2:0]  disk_unit_3038;
  wire [10:0] disk_wordcount_3038;
  wire [15:0] dbuf_rdata_3038;

  integer checks = 0;
  integer errors = 0;
  integer cycles = 0;

  reg [15:0] rv;
  reg [15:0] status_reset;

  ND_WINCHESTER #(.DELAY_TICKS(32'd20)) dut (
      .sysclk        (sysclk),
      .sys_rst_n     (sys_rst_n),
      .iox_addr      (iox_addr),
      .iox_wr        (iox_wr),
      .iox_wdata     (iox_wdata),
      .iox_rd        (iox_rd),
      .iox_rdata     (iox_rdata),
      .iox_sel       (iox_sel),
      .trace_rec     (trace_rec),
      .trace_we      (trace_we),
      .trace_done    (trace_done),
      .int_pending   (int_pending),
      .ident_strobe  (ident_strobe),
      .ident_level   (ident_level),
      .ident_grant_in(ident_grant_in),
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
      .disk_err_code (4'd0),
      .dbuf_addr     (10'd0),
      .dbuf_wdata    (16'd0),
      .dbuf_we       (1'b0),
      .dbuf_rdata    (dbuf_rdata)
  );

  ND_WINCHESTER #(.DELAY_TICKS(32'd20), .IS_3038(1)) dut3038 (
      .sysclk        (sysclk),
      .sys_rst_n     (sys_rst_n),
      .iox_addr      (iox_addr),
      .iox_wr        (iox_wr),
      .iox_wdata     (iox_wdata),
      .iox_rd        (iox_rd),
      .iox_rdata     (iox_rdata_3038),
      .iox_sel       (iox_sel_3038),
      .trace_rec     (trace_rec_3038),
      .trace_we      (trace_we_3038),
      .trace_done    (trace_done_3038),
      .int_pending   (int_pending_3038),
      .ident_strobe  (1'b0),
      .ident_level   (4'd0),
      .ident_grant_in(1'b0),
      .ident_grant_out(ident_grant_out_3038),
      .ident_hit     (ident_hit_3038),
      .ident_code    (ident_code_3038),
      .dma_req       (dma_req_3038),
      .dma_wr        (dma_wr_3038),
      .dma_addr      (dma_addr_3038),
      .dma_wdata     (dma_wdata_3038),
      .dma_rdata     (16'd0),
      .dma_ack       (1'b0),
      .dma_err       (1'b0),
      .dma_busy      (1'b0),
      .disk_start    (disk_start_3038),
      .disk_req      (disk_req_3038),
      .disk_wr       (disk_wr_3038),
      .disk_blkaddr1 (disk_blkaddr1_3038),
      .disk_blkaddr2 (disk_blkaddr2_3038),
      .disk_unit     (disk_unit_3038),
      .disk_wordcount(disk_wordcount_3038),
      .disk_done     (1'b0),
      .disk_err_in   (1'b0),
      .disk_err_code (4'd0),
      .dbuf_addr     (10'd0),
      .dbuf_wdata    (16'd0),
      .dbuf_we       (1'b0),
      .dbuf_rdata    (dbuf_rdata_3038)
  );

  initial begin
    $dumpfile("nd_winchester_decode_tb.vcd");
    $dumpvars(0, nd_winchester_decode_tb);
  end

  initial begin
    #6000000;
    $display("FAIL WATCHDOG: not finished after 6000000 ns (%0d clocks)", cycles);
    $display(" checks run : %0d", checks);
    $display(" failures   : %0d", errors + 1);
    $display("TB_RESULT: FAIL");
    $finish;
  end

  // The clock is stepped explicitly, so the exhaustive sweep can run with
  // no clock edges at all (see pinned behaviour N3).
  task tick;
    begin
      #10 sysclk = 1'b1;
      #10 sysclk = 1'b0;
      cycles = cycles + 1;
    end
  endtask

  task ck;
    input [255:0] name;
    input [31:0]  got;
    input [31:0]  exp;
    begin
      checks = checks + 1;
      if (got !== exp) begin
        errors = errors + 1;
        if (errors < 40)
          $display("FAIL %0s at t=%0t: got %0h expected %0h", name, $time, got, exp);
      end
    end
  endtask

  task master_clear;
    begin
      sys_rst_n = 1'b0;
      iox_rd = 1'b0; iox_wr = 1'b0; iox_addr = 16'd0; iox_wdata = 16'd0;
      ident_strobe = 1'b0; ident_grant_in = 1'b0; ident_level = 4'd0;
      repeat (3) tick;
      sys_rst_n = 1'b1;
      repeat (2) tick;
    end
  endtask

  task iox_write;
    input [15:0] a;
    input [15:0] d;
    begin
      iox_addr  = a;
      iox_wdata = d;
      iox_wr    = 1'b1;
      #1;
      tick;
      tick;
      iox_wr = 1'b0;
      #1;
      tick;
    end
  endtask

  // combinational peek - no clock edge, so the read alternator does not move
  task peek;
    input [15:0] a;
    begin
      iox_addr = a;
      iox_rd   = 1'b1;
      #1;
      rv = iox_rdata;
      iox_rd = 1'b0;
      #1;
    end
  endtask

  integer i, g, irqcase;
  reg exp_hit, exp_gout;
  reg [15:0] exp_code;
  reg irq_armed;

  initial begin
    $display("=====================================================");
    $display(" ND_WINCHESTER - exhaustive decode / read map / IDENT chain");
    $display("=====================================================");

    master_clear;

    // ---------------------------------------------------------------
    // 0. reference values for the sweep, established independently.
    //    After a master clear nothing is on cylinder and no error is
    //    latched, so on a 3041 the ONLY status bit set is b13, the card
    //    identity constant (ND_WINCHESTER.v:387-393).
    // ---------------------------------------------------------------
    peek(BASE + R_STATUS);
    ck("S0_STATUS_AFTER_MASTER_CLEAR", rv, 16'h2000);
    status_reset = 16'h2000;

    // 3038 strap: b13 is the live read/write gate, which is 0 when idle
    iox_addr = BASE + R_STATUS; iox_rd = 1'b1; #1;
    ck("S0_3038_B13_IS_NOT_CONSTANT_ONE", iox_rdata_3038[13], 1'b0);
    ck("S0_3041_B13_IS_CONSTANT_ONE",     iox_rdata[13],      1'b1);
    ck("S0_3038_B15_ZERO",                iox_rdata_3038[15], 1'b0);
    ck("S0_3038_B12_ZERO",                iox_rdata_3038[12], 1'b0);
    iox_rd = 1'b0; #1;

    // load distinguishable contents into the two readable data registers
    iox_write(BASE + R_LOAD_MA,    16'h0012);   // first write  -> HI 8
    iox_write(BASE + R_LOAD_MA,    16'h3456);   // second write -> LO 16
    iox_write(BASE + R_LOAD_BLOCK, 16'hA5C3);   // block address

    peek(BASE + R_READ_BLOCK);
    ck("S0_BLOCK_READBACK", rv, 16'hA5C3);
    peek(BASE + R_STATUS);
    ck("S0_STATUS_UNCHANGED_BY_LOADS", rv, status_reset);

    // ---------------------------------------------------------------
    // 1. EXHAUSTIVE 16-bit address sweep, clock stopped.
    //    Two checks per address: iox_sel and iox_rdata.
    // ---------------------------------------------------------------
    for (i = 0; i < 65536; i = i + 1) begin
      iox_addr = i[15:0];
      iox_rd   = 1'b1;
      #1;
      if (i[15:3] == BASE[15:3]) begin
        ck("D1_SEL_MUST_BE_ONE", iox_sel, 1'b1);
        case (i[2:0])
          3'd0: ck("D1_R0_MEMADDR_LOW", iox_rdata, 16'h3456);
          3'd4: ck("D1_R4_STATUS",      iox_rdata, status_reset);
          3'd6: ck("D1_R6_BLOCKADDR",   iox_rdata, 16'hA5C3);
          // +2 "not used" and +1/+3/+5/+7 write-only all read 0
          default: ck("D1_ZERO_REG", iox_rdata, 16'd0);
        endcase
      end else begin
        ck("D1_SEL_MUST_BE_ZERO",         iox_sel,   1'b0);
        ck("D1_FOREIGN_READS_MUST_BE_0",  iox_rdata, 16'd0);
      end
      iox_rd = 1'b0;
    end
    #1;

    // N1: iox_sel follows the ADDRESS alone, with both strobes low
    for (i = 0; i < 8; i = i + 1) begin
      iox_addr = BASE + i[15:0];
      iox_rd = 1'b0; iox_wr = 1'b0;
      #1;
      ck("D2_SEL_WITHOUT_STROBE", iox_sel, 1'b1);
      ck("D2_RD_LOW_DRIVES_ZERO", iox_rdata, 16'd0);
    end
    iox_addr = BASE + 16'd8; #1;
    ck("D2_SEL_ZERO_JUST_ABOVE_BLOCK", iox_sel, 1'b0);
    iox_addr = BASE - 16'd1; #1;
    ck("D2_SEL_ZERO_JUST_BELOW_BLOCK", iox_sel, 1'b0);
    iox_addr = 16'd0; #1;

    // both cards decode the same block - they are alternatives, never
    // fitted together (see the DUT header)
    iox_addr = BASE + 16'd3; #1;
    ck("D2_3038_DECODES_SAME_BLOCK", iox_sel_3038, 1'b1);
    iox_addr = 16'o001560; #1;
    ck("D2_3038_IGNORES_FLOPPY_BLOCK", iox_sel_3038, 1'b0);
    ck("D2_3041_IGNORES_FLOPPY_BLOCK", iox_sel,      1'b0);
    iox_addr = 16'o001540; #1;
    ck("D2_3041_IGNORES_SMD_BLOCK", iox_sel, 1'b0);
    iox_addr = 16'd0; #1;

    // ---------------------------------------------------------------
    // 2. int_pending vector: the level-11 card must drive bit 1 and
    //    only bit 1 (ND_WINCHESTER.v:407-410).
    // ---------------------------------------------------------------
    master_clear;
    ck("I1_QUIET_AFTER_CLEAR", int_pending, 4'd0);
    iox_write(BASE + R_CONTROL, CW_INT_EN);
    ck("I1_ONEHOT_LEVEL11", int_pending, 4'b0010);

    // ---------------------------------------------------------------
    // 3. IDENT: all 16 levels x grant_in x pending, checking hit, code
    //    AND the daisy-chain output. Reference equations at :411-415:
    //      answer   = strobe & grant_in & (level==11) & irq
    //      code     = answer ? IDENT_CODE : 0
    //      grant_out= grant_in & !answer
    // ---------------------------------------------------------------
    for (irqcase = 0; irqcase < 2; irqcase = irqcase + 1) begin
      master_clear;
      irq_armed = (irqcase == 1);
      if (irq_armed) iox_write(BASE + R_CONTROL, CW_INT_EN);
      ck("I2_ARMED_STATE", int_pending[1], irq_armed);

      for (g = 0; g < 2; g = g + 1) begin
        for (i = 0; i < 16; i = i + 1) begin
          ident_strobe   = 1'b1;
          ident_grant_in = g[0];
          ident_level    = i[3:0];
          #1;
          exp_hit  = (g[0] === 1'b1) && (i == 11) && irq_armed;
          exp_code = exp_hit ? 16'o000001 : 16'd0;
          exp_gout = g[0] && !exp_hit;
          ck("I3_HIT",       ident_hit,       exp_hit);
          ck("I3_CODE",      ident_code,      exp_code);
          ck("I3_GRANT_OUT", ident_grant_out, exp_gout);
          ident_strobe = 1'b0;
          #1;
          // with the strobe low nothing may be answered, and the grant
          // must still pass straight through to the next card
          ck("I3_NO_STROBE_NO_HIT",  ident_hit,       1'b0);
          ck("I3_NO_STROBE_CODE_0",  ident_code,      16'd0);
          ck("I3_NO_STROBE_GRANT",   ident_grant_out, g[0]);
          ident_grant_in = 1'b0;
          #1;
        end
      end
    end

    // answering an IDENT clears the line, so the NEXT card gets the grant
    master_clear;
    iox_write(BASE + R_CONTROL, CW_INT_EN);
    ident_level = 4'd11; ident_grant_in = 1'b1; ident_strobe = 1'b1; #1;
    ck("I4_ANSWERS",            ident_hit,       1'b1);
    ck("I4_SWALLOWS_THE_GRANT", ident_grant_out, 1'b0);
    tick;
    ident_strobe = 1'b0; #1;
    tick;
    ident_strobe = 1'b1; #1;
    ck("I4_SECOND_IDENT_SILENT",  ident_hit,       1'b0);
    ck("I4_GRANT_PASSES_ON",      ident_grant_out, 1'b1);
    ck("I4_LINE_CLEARED",         int_pending,     4'd0);
    ident_strobe = 1'b0; ident_grant_in = 1'b0; #1;

    if (checks !== EXPECTED_CHECKS) begin
      errors = errors + 1;
      $display("FAIL CHECK_COUNT: ran %0d checks, expected %0d", checks, EXPECTED_CHECKS);
    end

    $display("-----------------------------------------------------");
    $display(" clock edges : %0d", cycles);
    $display(" checks run  : %0d", checks);
    $display(" failures    : %0d", errors);
    if (errors == 0) $display("TB_RESULT: PASS");
    else             $display("TB_RESULT: FAIL");
    $display("=====================================================");
    $finish;
  end

endmodule

`default_nettype wire
