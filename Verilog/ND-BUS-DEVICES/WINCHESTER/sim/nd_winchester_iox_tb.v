/**************************************************************************
** TESTBENCH: ND_WINCHESTER - register protocol, status and IDENT         **
**                                                                       **
** The register-level bench for the ST506/8-inch Winchester controller.   **
** It drives the SAME behaviour that the two host-gated C implementations **
** are cross-checked on (the shared conformance sequence in nd100x        **
** tests/wd_conformance_seq.h and the portable core's copy), so a         **
** divergence between the RTL and the C models shows up here rather than  **
** on silicon.                                                           **
**                                                                       **
** What it covers, and why each one is here:                              **
**   1. identity: 500-507, ident 1, level 11 (sec 3.1)                    **
**   2. memory address: writes HI-then-LO, reads LO-then-HI (sec 3.2).    **
**      The asymmetry is the single easiest thing in this card to get     **
**      wrong.                                                            **
**   3. all FOUR flip-flop reset conditions (sec 3.2): master clear,      **
**      device clear, a status read, and ACTIVATION. The fourth is the    **
**      one implementations forget.                                       **
**   4. word count loads in a SINGLE access - THE property that           **
**      distinguishes this card from the 15 MHz SMD and the reason the    **
**      ND-120 mass-storage microcode works here at all.                  **
**   5. block address split: cylinder b15-5, sector b4-0 (sec 3.3)        **
**   6. status constants: b15 always 0 (not the 10 Mb controller),        **
**      b13 always 1 on the 3041; b12 is TR00 (sec 7.11), 1 on cyl 0   **
**   7. the interrupt / IDENT probe of sec 4.1 - the TPE CONFIGURATION    **
**      sequence. The C port shipped once without it and TPE reported     **
**      "No identcode found on level 11D, expected identcode : 1B", so    **
**      this is the one case that must never regress silently.            **
**   8. M6 must NOT activate (sec 3.4)                                    **
**   9. +2 reads 0 - "IOX 502 Not used" in the sec 3.1 table. Both C      **
**      models modelled a readable sector counter here until a            **
**      cross-check sent us back to the manual.                           **
**  10. write-only registers read 0                                       **
**                                                                       **
** Verdict line: TB_RESULT: PASS / TB_RESULT: FAIL                       **
**                                                                       **
** Ronny Hansen                                                          **
***************************************************************************/

`timescale 1ns / 1ps

module nd_winchester_iox_tb;

  localparam [15:0] BASE = 16'o000500;

  // Long enough that a GO stays active across many IOX cycles, short enough
  // that the bench finishes quickly. E_DELAY counts down one per sysclk.
  localparam [31:0] LONG_DELAY = 32'd2000;

  // Status bit positions (see the s_status assembly in ND_WINCHESTER.v).
  localparam SB_BIT15    = 15;
  localparam SB_ONCYL    = 14;
  localparam SB_CONTRID  = 13;
  localparam SB_NOTUSED  = 12;
  localparam SB_DMAERR   = 11;
  localparam SB_ADDRMISM = 8;
  localparam SB_FAULT    = 7;
  localparam SB_INCLOR   = 4;
  localparam SB_FINISHED = 3;
  localparam SB_ACTIVE   = 2;
  localparam SB_ERRINTEN = 1;
  localparam SB_INTEN    = 0;

  // Register offsets.
  localparam R_READ_MA    = 16'd0;
  localparam R_LOAD_MA    = 16'd1;
  localparam R_READ_SECT  = 16'd2;
  localparam R_LOAD_BLOCK = 16'd3;
  localparam R_STATUS     = 16'd4;
  localparam R_CONTROL    = 16'd5;
  localparam R_READ_BLOCK = 16'd6;
  localparam R_LOAD_WC    = 16'd7;

  // Control-word bits.
  localparam CW_INT_EN   = 16'h0001;
  localparam CW_ERR_INT  = 16'h0002;
  localparam CW_ACTIVE   = 16'h0004;
  localparam CW_TEST     = 16'h0008;
  localparam CW_DEVCLR   = 16'h0010;
  localparam CW_UNIT     = 16'h0200;
  localparam CW_DIR      = 16'h4000;

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

  reg         ident_strobe    = 1'b0;
  reg  [3:0]  ident_level     = 4'd0;
  reg         ident_grant_in  = 1'b0;
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

  integer errors = 0;
  integer checks = 0;

  task check(input cond, input [1023:0] msg);
    begin
      checks = checks + 1;
      if (!cond) begin
        errors = errors + 1;
        $display("  FAIL: %0s", msg);
      end
    end
  endtask

  task check_eq(input [15:0] got, input [15:0] want, input [1023:0] msg);
    begin
      checks = checks + 1;
      if (got !== want) begin
        errors = errors + 1;
        $display("  FAIL: %0s - expected %06o, got %06o", msg, want, got);
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
    end
  endtask

  // Present an IDENT on the given level with the daisy-chain grant in, and
  // report the code this card answers (0 = not mine, pass the chain on).
  task do_ident(input [3:0] level, output [15:0] code);
    begin
      @(negedge sysclk);
      ident_level    = level;
      ident_grant_in = 1'b1;
      ident_strobe   = 1'b1;
      #1 code = ident_code;
      @(posedge sysclk);
      @(negedge sysclk);
      ident_strobe   = 1'b0;
      ident_grant_in = 1'b0;
      repeat (2) @(negedge sysclk);
    end
  endtask

  reg [15:0] d;
  reg [15:0] code;

  initial begin
    $display("=== ND_WINCHESTER register / status / IDENT bench ===");

    master_clear;

    // ---- 1. identity and address decode (sec 3.1) --------------------
    @(negedge sysclk);
    iox_addr = BASE;
    #1 check(iox_sel === 1'b1, "the card claims its base address");
    iox_addr = BASE + 16'd7;
    #1 check(iox_sel === 1'b1, "the card claims base+7");
    iox_addr = BASE + 16'd8;
    #1 check(iox_sel === 1'b0, "the card does NOT claim base+8");
    iox_addr = 16'o001540;
    #1 check(iox_sel === 1'b0, "the card does NOT claim the SMD block");
    iox_addr = 16'd0;

    // ---- 2. memory address: write HI-then-LO, read LO-then-HI --------
    iox_write(BASE + R_LOAD_MA, 16'h0012);   // first write  -> HI 8
    iox_write(BASE + R_LOAD_MA, 16'h3456);   // second write -> LO 16
    iox_read(BASE + R_READ_MA, d);
    check_eq(d, 16'h3456, "first MA read returns the LOW 16 bits");
    iox_read(BASE + R_READ_MA, d);
    check_eq(d, 16'h0012, "second MA read returns the HIGH 8 bits");
    iox_read(BASE + R_READ_MA, d);
    check_eq(d, 16'h3456, "a third MA read wraps back to the LOW word");

    // ---- 3a. a status read resets the write flip-flop (sec 3.2) ------
    iox_write(BASE + R_LOAD_MA, 16'h0077);   // leaves the FF mid-sequence
    iox_read(BASE + R_STATUS, d);            // reset condition #3
    iox_write(BASE + R_LOAD_MA, 16'h0011);   // must be taken as HI again
    iox_write(BASE + R_LOAD_MA, 16'h2222);
    iox_read(BASE + R_READ_MA, d);
    check_eq(d, 16'h2222, "after a status read the LO word is right");
    iox_read(BASE + R_READ_MA, d);
    check_eq(d, 16'h0011, "after a status read the HI byte is right");

    // ---- 3b. a device clear resets the write flip-flop ---------------
    iox_write(BASE + R_LOAD_MA, 16'h0077);
    iox_write(BASE + R_CONTROL, CW_DEVCLR);  // reset condition #2
    iox_write(BASE + R_LOAD_MA, 16'h0033);
    iox_write(BASE + R_LOAD_MA, 16'h4444);
    iox_read(BASE + R_READ_MA, d);
    check_eq(d, 16'h4444, "after a device clear the LO word is right");
    iox_read(BASE + R_READ_MA, d);
    check_eq(d, 16'h0033, "after a device clear the HI byte is right");

    // ---- 3c. a master clear resets it too ----------------------------
    iox_write(BASE + R_LOAD_MA, 16'h0077);
    master_clear;                            // reset condition #1
    iox_write(BASE + R_LOAD_MA, 16'h0055);
    iox_write(BASE + R_LOAD_MA, 16'h6666);
    iox_read(BASE + R_READ_MA, d);
    check_eq(d, 16'h6666, "after a master clear the LO word is right");
    iox_read(BASE + R_READ_MA, d);
    check_eq(d, 16'h0055, "after a master clear the HI byte is right");

    // ---- 4. word count is a SINGLE access ----------------------------
    // On a two-access card the second write would land in a HI byte. Here it
    // must REPLACE. This is what makes the ND-120 mass-storage load work.
    iox_write(BASE + R_LOAD_WC, 16'o002000);
    check_eq(dut.s_word_cnt, 16'o002000, "word count 002000 loaded in ONE write");
    iox_write(BASE + R_LOAD_WC, 16'o000777);
    check_eq(dut.s_word_cnt, 16'o000777, "a second write REPLACES, no HI latch");

    // ---- 5. block address split (sec 3.3) ----------------------------
    iox_write(BASE + R_LOAD_BLOCK, (16'd17 << 5) | 16'd6);
    check_eq({5'd0, dut.w_cyl}, 16'd17, "cylinder from block address b15-5");
    check_eq({11'd0, dut.w_sector}, 16'd6, "sector from block address b4-0");
    iox_read(BASE + R_READ_BLOCK, d);
    check_eq(d, (16'd17 << 5) | 16'd6, "+6 reads the block address back");
    iox_write(BASE + R_LOAD_BLOCK, 16'hFFFF);
    check_eq({5'd0, dut.w_cyl}, 16'h07FF, "cylinder is 11 bits wide");
    check_eq({11'd0, dut.w_sector}, 16'h001F, "sector is 5 bits wide");

    // ---- 6. status constants (sec 3.5) -------------------------------
    master_clear;
    iox_read(BASE + R_STATUS, d);
    check(d[SB_BIT15] === 1'b0,
          "status b15 always 0 - distinguishes from the 10 Mb controller");
    // b12 is TR00, the selected drive's Track 000 line (sec 7.9/7.11):
    // master clear leaves unit 0 selected, out of test mode, on cylinder 0.
    check(d[SB_NOTUSED] === 1'b1, "status b12 = TR00, 1 on cylinder 0 after master clear");
    check(d[SB_CONTRID] === 1'b1, "3041: status b13 always 1");
    check(d !== 16'd0, "status is readable straight after master clear");

    // ---- 9. +2 is Not used (sec 3.1 table) ---------------------------
    iox_read(BASE + R_READ_SECT, d);
    check_eq(d, 16'd0, "+2 is Not used - reads 0");

    // ---- 10. write-only registers read 0 -----------------------------
    iox_read(BASE + R_LOAD_MA, d);
    check_eq(d, 16'd0, "+1 is write-only, reads 0");
    iox_read(BASE + R_LOAD_BLOCK, d);
    check_eq(d, 16'd0, "+3 is write-only, reads 0");
    iox_read(BASE + R_CONTROL, d);
    check_eq(d, 16'd0, "+5 is write-only, reads 0");
    iox_read(BASE + R_LOAD_WC, d);
    check_eq(d, 16'd0, "+7 is write-only, reads 0");

    // ---- 7. the sec 4.1 interrupt / IDENT probe ----------------------
    // "If the controller is ready for an operation (status bit 3 = 1), and
    //  interrupt is enabled (status bit 0 ...), the interrupt signal BINT11
    //  will be active ... The IDENT code may now be read by an IDENT PL11."
    master_clear;
    check(int_pending[1] === 1'b0, "level 11 quiet after master clear");

    iox_write(BASE + R_CONTROL, CW_INT_EN);   // arm on an IDLE controller
    iox_read(BASE + R_STATUS, d);
    check(d[SB_FINISHED] === 1'b1, "idle controller reports ready (b3)");
    check(d[SB_INTEN]    === 1'b1, "interrupt-enable reaches status b0");
    check(int_pending[1] === 1'b1,
          "ready + enabled asserts BINT11 on an idle controller");

    do_ident(4'd11, code);
    check_eq(code, 16'o000001, "IDENT PL11 answers with ident code 1");
    check(int_pending[1] === 1'b0, "IDENT cleared the interrupt line");

    do_ident(4'd11, code);
    check_eq(code, 16'd0, "a second IDENT with nothing pending stays silent");

    // A wrong-level IDENT is never answered and never clears the line.
    // Level 11 is shared with the floppy (ident 021) and the SMD card (017).
    iox_write(BASE + R_CONTROL, CW_INT_EN);
    check(int_pending[1] === 1'b1, "interrupt re-armed");
    do_ident(4'd10, code);
    check_eq(code, 16'd0, "IDENT on level 10 is not answered");
    do_ident(4'd13, code);
    check_eq(code, 16'd0, "IDENT on level 13 is not answered");
    check(int_pending[1] === 1'b1,
          "a wrong-level IDENT left level 11 pending");
    do_ident(4'd11, code);
    check_eq(code, 16'o000001, "IDENT PL11 finally answers");

    // Device clear AND interrupt enable in ONE control word: the clear must
    // not swallow the interrupt update. An early return there is the bug that
    // made TPE report "No identcode found on level 11D".
    iox_write(BASE + R_CONTROL, CW_DEVCLR | CW_INT_EN);
    check(int_pending[1] === 1'b1,
          "device clear + interrupt enable in one word still interrupts");

    // Dropping the enable takes the line away again.
    iox_write(BASE + R_CONTROL, 16'd0);
    check(int_pending[1] === 1'b0, "clearing the enable drops BINT11");

    // ---- 8. M6 must NOT be activated (sec 3.4) -----------------------
    master_clear;
    iox_write(BASE + R_CONTROL, (16'd6 << 11) | CW_ACTIVE);
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ACTIVE] === 1'b0,
          "M6 load-control-bits is never activated - b2 must stay 0");
    check(d[SB_FINISHED] === 1'b1,
          "M6 leaves the controller READY, not wedged not-ready");

    // ---- activation is flip-flop reset condition #4 (sec 3.2) --------
    // M4 seek needs no disk backend: it completes through E_DELAY.
    master_clear;
    iox_write(BASE + R_LOAD_WC, 16'd0);
    iox_write(BASE + R_LOAD_MA, 16'h0099);     // FF left mid-sequence
    iox_write(BASE + R_CONTROL, CW_ACTIVE | (16'd4 << 11));
    repeat (LONG_DELAY + 100) @(posedge sysclk);
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ACTIVE] === 1'b0, "M4 seek completed");
    check(d[SB_FINISHED] === 1'b1, "M4 seek reports finished");

    iox_write(BASE + R_LOAD_MA, 16'h0044);     // must be taken as HI again
    iox_write(BASE + R_LOAD_MA, 16'h5555);
    iox_read(BASE + R_READ_MA, d);
    check_eq(d, 16'h5555, "activation re-synchronised the MA write FF (LO)");
    iox_read(BASE + R_READ_MA, d);
    check_eq(d, 16'h0044, "activation re-synchronised the MA write FF (HI)");

    // ---- M4 is a RELATIVE STEP seek (sec 3.4.5) ----------------------
    master_clear;
    iox_write(BASE + R_LOAD_WC, 16'd100);
    iox_write(BASE + R_CONTROL, CW_ACTIVE | CW_DIR | (16'd4 << 11));
    repeat (LONG_DELAY + 100) @(posedge sysclk);
    check_eq(dut.s_cyl_pos[0], 16'd100, "M4 out: arm stepped away from cylinder 0");

    iox_write(BASE + R_LOAD_WC, 16'd30);
    iox_write(BASE + R_CONTROL, CW_ACTIVE | (16'd4 << 11));  // b14 = 0: inwards
    repeat (LONG_DELAY + 100) @(posedge sysclk);
    check_eq(dut.s_cyl_pos[0], 16'd70, "M4 in: arm stepped towards cylinder 0");

    iox_write(BASE + R_LOAD_WC, 16'd5000);
    iox_write(BASE + R_CONTROL, CW_ACTIVE | (16'd4 << 11));
    repeat (LONG_DELAY + 100) @(posedge sysclk);
    check_eq(dut.s_cyl_pos[0], 16'd0, "M4: arm clamps at cylinder 0, no wrap");

    // Each unit has its OWN arm - the card has exactly two.
    iox_write(BASE + R_LOAD_WC, 16'd42);
    iox_write(BASE + R_CONTROL, CW_ACTIVE | CW_DIR | CW_UNIT | (16'd4 << 11));
    repeat (LONG_DELAY + 100) @(posedge sysclk);
    check_eq(dut.s_cyl_pos[1], 16'd42, "unit 1 has its own arm position");
    check_eq(dut.s_cyl_pos[0], 16'd0,  "unit 0's arm did not move");

    // ---- M7 return to zero -------------------------------------------
    iox_write(BASE + R_CONTROL, CW_ACTIVE | CW_UNIT | (16'd7 << 11));
    repeat (LONG_DELAY + 100) @(posedge sysclk);
    check_eq(dut.s_cyl_pos[1], 16'd0, "M7 returned unit 1's arm to cylinder 0");

    // ---- an out-of-range block address is an address mismatch --------
    master_clear;
    iox_write(BASE + R_LOAD_MA, 16'd0);
    iox_write(BASE + R_LOAD_MA, 16'h0100);
    iox_write(BASE + R_LOAD_BLOCK, 16'd20);      // sector 20, drive has 9
    iox_write(BASE + R_LOAD_WC, 16'd512);
    iox_write(BASE + R_CONTROL, CW_ACTIVE);      // M0 read
    // The mismatch ends LATER, not inside the activating IOX: the SINTRAN
    // driver reads status straight after the activate and takes "not active"
    // as an error of its own (WINCHESTER:NPL WDACT, "CONTROLLER NOT ACTIVE
    // AFTER ACTIVATE"). Same rule as nd100x wd_end_later.
    repeat (20) @(posedge sysclk);
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ACTIVE]   === 1'b1, "address mismatch: still active straight after the activate");
    repeat (LONG_DELAY + 100) @(posedge sysclk);
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ADDRMISM] === 1'b1, "sector past the end of a track mismatches");
    check(d[SB_INCLOR]   === 1'b1, "address mismatch feeds the inclusive OR");
    check(d[SB_ACTIVE]   === 1'b0, "address mismatch terminates the operation");
    check(d[SB_FINISHED] === 1'b1, "a failed operation has still FINISHED");

    // Test mode does NOT bypass the bounds check. The RTL used to skip it and
    // cited sec 3.4, which only gives the test-mode control word and says
    // nothing about skipping a check; the oracle checks in test mode too.
    master_clear;
    iox_write(BASE + R_LOAD_BLOCK, 16'd20);
    iox_write(BASE + R_LOAD_WC, 16'd0);          // zero-length: no backend
    iox_write(BASE + R_CONTROL, CW_ACTIVE | CW_TEST);
    repeat (LONG_DELAY + 100) @(posedge sysclk);
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ADDRMISM] === 1'b1,
          "test mode still checks the address bounds");

    // ---- master clear: both arms on cylinder 0 -----------------------
    // Sec 3.4.8 "Return to zero by pushing the master clear button", sec 5.5
    // "Pushing Master Clear will position the heads to cylinder 0".
    master_clear;
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ONCYL] === 1'b1, "master clear: unit 0 on cylinder");
    iox_write(BASE + R_CONTROL, CW_UNIT);        // select unit 1, no activate
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ONCYL] === 1'b1, "master clear: unit 1 on cylinder");

    // ---- on cylinder drops while M4 moves the arm --------------------
    // Sec 3.4.5: a seek "is completed when the heads are settled over the
    // correct tracks".
    master_clear;
    iox_write(BASE + R_LOAD_WC, 16'd3);
    iox_write(BASE + R_CONTROL, CW_ACTIVE | CW_DIR | (16'd4 << 11));
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ACTIVE] === 1'b1 && d[SB_ONCYL] === 1'b0,
          "M4: active and not on cylinder while the heads travel");
    repeat (LONG_DELAY + 100) @(posedge sysclk);
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ACTIVE] === 1'b0 && d[SB_ONCYL] === 1'b1,
          "M4: on cylinder again once it has finished");

    // ---- M7 drops on cylinder too -------------------------------------
    iox_write(BASE + R_CONTROL, CW_ACTIVE | (16'd7 << 11));
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ONCYL] === 1'b0, "M7: not on cylinder while moving home");
    repeat (LONG_DELAY + 100) @(posedge sysclk);
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ONCYL] === 1'b1 && dut.s_cyl_pos[0] == 16'd0,
          "M7: on cylinder 0 once it has finished");

    // ---- M4 out stops on the last cylinder, not past it ----------------
    // GEO_MAX_CYL (1024) is the number of cylinders, so the last is 1023.
    iox_write(BASE + R_LOAD_WC, 16'd5000);
    iox_write(BASE + R_CONTROL, CW_ACTIVE | CW_DIR | (16'd4 << 11));
    repeat (LONG_DELAY + 100) @(posedge sysclk);
    check_eq(dut.s_cyl_pos[0], 16'd1023, "M4 out: arm stops on the last cylinder (1023)");

    // ---- a transfer needs the arm on its cylinder ----------------------
    // Sec 2.2 "The software driver must do a seek to the correct cylinder
    // prior to a read or write operation"; sec 4.4 phase 2 compares the
    // address fields under the heads. Arm at 0, block address on cylinder 3,
    // sector 4: nothing found, mismatch, and the block address moves on by
    // the one sector it failed on (nd100x BUGS.md W7, the driver's
    // "A-1=:ADMIA").
    master_clear;
    iox_write(BASE + R_LOAD_BLOCK, (16'd3 << 5) | 16'd4);
    iox_write(BASE + R_LOAD_WC, 16'd512);
    iox_write(BASE + R_CONTROL, CW_ACTIVE);      // M0 read
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ACTIVE] === 1'b1, "arm off cylinder: still active straight after the activate");
    repeat (LONG_DELAY + 100) @(posedge sysclk);
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ADDRMISM] === 1'b1 && d[SB_ACTIVE] === 1'b0 && d[SB_FINISHED] === 1'b1,
          "arm on cylinder 0, block on cylinder 3: address mismatch, finished");
    iox_read(BASE + R_READ_BLOCK, d);
    check_eq(d, (16'd3 << 5) | 16'd5,
             "after the mismatch the block address points one past the failing sector");
    check(disk_req === 1'b0 && dut.s_disk_out === 1'b0,
          "no backend request for a sector the card did not find");

    // ---- a transfer that runs off the arm's cylinder ---------------------
    // Arm at 0, head 7, sector 8 (the last sector of cylinder 0), 2 sectors
    // (1024 words): the first is found, the second would be on cylinder 1.
    master_clear;
    iox_write(BASE + R_LOAD_BLOCK, 16'd8);
    iox_write(BASE + R_LOAD_WC, 16'd1024);
    iox_write(BASE + R_CONTROL, CW_ACTIVE | (16'd7 << 5));
    repeat (LONG_DELAY + 100) @(posedge sysclk);
    iox_read(BASE + R_STATUS, d);
    check(d[SB_ADDRMISM] === 1'b1, "a transfer that runs off the arm's cylinder mismatches");
    iox_read(BASE + R_READ_BLOCK, d);
    check_eq(d, 16'd10, "run off the cylinder: block address moved on by found (1) + 1");

    // ---- device clear keeps the block address -------------------------
    // WINCHESTER:NPL IERR gives a device clear and then reads the block
    // address to find the failing sector; master clear does clear it.
    iox_write(BASE + R_LOAD_BLOCK, 16'o012345);
    iox_write(BASE + R_CONTROL, CW_DEVCLR);
    iox_read(BASE + R_READ_BLOCK, d);
    check_eq(d, 16'o012345, "device clear keeps the block address");
    master_clear;
    iox_read(BASE + R_READ_BLOCK, d);
    check_eq(d, 16'd0, "master clear clears the block address");

    if (errors == 0)
      $display("=== %0d checks passed ===\nTB_RESULT: PASS", checks);
    else
      $display("=== %0d of %0d checks FAILED ===\nTB_RESULT: FAIL",
               errors, checks);
    $finish;
  end

  // Watchdog: a wedge must fail loudly, not hang the suite.
  initial begin
    #20_000_000;
    $display("  FAIL: testbench watchdog - the DUT wedged");
    $display("TB_RESULT: FAIL");
    $finish;
  end

endmodule
