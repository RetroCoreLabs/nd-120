/**************************************************************************
** TESTBENCH: ND_DMA_MASTER read-data capture vs foreign bus transients  **
**                                                                       **
** Regression bench for the Nexys 4 DDR floppy fault root-caused         **
** 23-AUG-2026: while a DMA read waits for BDRY, the CPU board's BIF     **
** transceiver briefly presents the CPU's current local-bus word (an     **
** instruction fetch) on BD - a 2-tick "foreign transient" - before      **
** memory drives the real answer. The master's capture-the-last-driven-  **
** value logic kept that transient whenever the true data was ZERO,      **
** because a zero word drives ~0 = 24'hFFFFFF on this inverted bus and   **
** is indistinguishable from idle. The floppy controller then fetched    **
** garbage command blocks (diskAddress 0 -> 004151 = a polling-loop      **
** STA opcode) and every floppy operation failed with error oct 20.      **
**                                                                       **
** The fix (ND_DMA_MASTER.v ST_DATA): discard the captured value after   **
** TWO consecutive undriven-bus ticks while BDRY_n is still high. The    **
** 2-tick filter protects the legitimate release gap: the board may      **
** release its data drivers up to one tick before the visible BDRY edge. **
**                                                                       **
** Waveforms here replay the shapes MEASURED in the Verilator trace of   **
** the failing system (docs: fpga/nexys4ddr/HANDOFF-floppy-dma-          **
** investigation.md PART 0, retired - git c4896a4):                      **
**   T1 zero word, 2-tick foreign transient        -> must read 0        **
**      (THE BUG: the pre-fix RTL returns the transient here)            **
**   T2 nonzero word, transient right before data  -> real data          **
**   T3 nonzero word, driver release 1 tick early  -> real data          **
**   T4 zero word, clean bus                       -> 0                  **
**   T5 nonzero word presented only AT the edge    -> real data          **
**      (standalone-tb data timing: the fallback ~BD path)               **
**   T6 write while garbage flickers on the bus    -> memory gets wdata  **
**   T7 zero word, transient then LONG idle        -> 0                  **
**   T8 two transients back to back, then data     -> real data          **
**   T9 zero word, 3-tick transient                -> 0                  **
**                                                                       **
** Verdict line: TB_RESULT: PASS / TB_RESULT: FAIL                       **
**                                                                       **
** Last reviewed: 23-AUG-2026                                            **
** Ronny Hansen                                                          **
***************************************************************************/

`timescale 1ns / 1ps

module ND_DMA_MASTER_STALE_CAPTURE_tb;

  reg sysclk = 0;
  reg sys_rst_n = 0;
  always #10 sysclk = ~sysclk;

  // client side
  reg         c_req = 0, c_wr = 0;
  reg  [23:0] c_addr = 0;
  reg  [15:0] c_wdata = 0;
  wire [15:0] c_rdata;
  wire        c_ack, c_err, c_busy;

  // bus side
  wire        breq_n;
  reg         bmem_n = 1;
  reg         grant_n = 1;
  wire [23:0] m_bd_out_n;
  reg  [23:0] slave_bd_n = 24'hFFFFFF;
  wire [23:0] bd_bus_n = m_bd_out_n & slave_bd_n;
  wire        bapr_n, binput_n, bdap_n;
  reg         bdry_n = 1;

  ND_DMA_MASTER #(.TIMEOUT_TICKS(16'd400), .BINPUT_HOLD(0),
                  .EARLY_REREQ(0)) u_master (
      .sysclk(sysclk), .sys_rst_n(sys_rst_n),
      .dma_req(c_req), .dma_wr(c_wr), .dma_addr(c_addr), .dma_wdata(c_wdata),
      .dma_rdata(c_rdata), .dma_ack(c_ack), .dma_err(c_err), .dma_busy(c_busy),
      .BREQ_n(breq_n),
      .INGRANT_n(grant_n), .OUTGRANT_n(),
      .BMEM_n(bmem_n),
      .BD_23_0_n_OUT(m_bd_out_n), .BD_23_0_n_IN(bd_bus_n),
      .BAPR_n(bapr_n), .BINPUT_n(binput_n), .BDAP_n(bdap_n),
      .BDRY_n(bdry_n)
  );

  integer errors = 0;

  task check(input cond, input [255:0] what);
    begin
      if (!cond) begin
        errors = errors + 1;
        $display("FAIL: %0s (time %0t)", what, $time);
      end
    end
  endtask

  task step;  // one bus tick, drive on negedge like the protocol bench
    begin
      @(negedge sysclk);
    end
  endtask

  // BCU front half: grant the request and swallow the address phase
  task grant_and_take_address;
    integer guard;
    begin
      guard = 0;
      while (breq_n !== 1'b0 && guard < 100) begin step; guard = guard + 1; end
      check(breq_n === 1'b0, "BREQ never asserted");
      step; step;                 // arbitration delay
      bmem_n  = 1'b0;
      grant_n = 1'b0;
      guard = 0;
      while (bapr_n !== 1'b0 && guard < 100) begin step; guard = guard + 1; end
      check(bapr_n === 1'b0, "BAPR never asserted");
      guard = 0;                  // wait for the data phase
      while (bdap_n !== 1'b0 && guard < 100) begin step; guard = guard + 1; end
      check(bdap_n === 1'b0, "BDAP never asserted");
    end
  endtask

  // BCU tail half: BDRY handshake and bus release
  task finish_cycle;
    integer guard;
    begin
      bdry_n  = 1'b0;
      grant_n = 1'b1;
      guard = 0;
      while (bdap_n !== 1'b1 && guard < 100) begin step; guard = guard + 1; end
      check(bdap_n === 1'b1, "BDAP never released");
      bdry_n     = 1'b1;
      slave_bd_n = 24'hFFFFFF;
      bmem_n     = 1'b1;
      guard = 0;
      while (c_ack !== 1'b1 && guard < 100) begin step; guard = guard + 1; end
      check(c_ack === 1'b1, "transfer never completed");
      step;
    end
  endtask

  // One scripted READ: idle, optional foreign transient, optional mid idle,
  // data window, optional early release, then BDRY. data_at_edge=1 presents
  // the data only together with BDRY and holds it (standalone-tb shape).
  task scripted_read(
      input [23:0] addr,
      input [15:0] transient_val, input integer transient_ticks,
      input integer idle_mid_ticks,
      input [15:0] data_val, input integer data_ticks,
      input integer release_gap,      // idle ticks between data and BDRY
      input data_at_edge,
      input [15:0] expect_val,
      input [255:0] what);
    integer k;
    begin
      c_wr = 0; c_addr = addr; c_req = 1;
      step;
      c_req = 0;
      grant_and_take_address();
      for (k = 0; k < 12; k = k + 1) step;          // idle head (measured)
      if (transient_ticks > 0) begin
        slave_bd_n = ~{8'd0, transient_val};        // foreign word
        for (k = 0; k < transient_ticks; k = k + 1) step;
      end
      if (idle_mid_ticks > 0) begin
        slave_bd_n = 24'hFFFFFF;
        for (k = 0; k < idle_mid_ticks; k = k + 1) step;
      end
      if (data_at_edge) begin
        slave_bd_n = ~{8'd0, data_val};             // data + BDRY together
      end else begin
        slave_bd_n = ~{8'd0, data_val};             // data window
        for (k = 0; k < data_ticks; k = k + 1) step;
        slave_bd_n = 24'hFFFFFF;                    // release before edge
        for (k = 0; k < release_gap; k = k + 1) step;
      end
      finish_cycle();
      if (data_at_edge) slave_bd_n = 24'hFFFFFF;
      check(c_err === 1'b0, "unexpected bus error");
      if (c_rdata !== expect_val) begin
        errors = errors + 1;
        $display("FAIL: %0s: rdata %06o expected %06o (time %0t)",
                 what, c_rdata, expect_val, $time);
      end else begin
        $display("ok:   %0s -> %06o", what, c_rdata);
      end
    end
  endtask

  // TRAIN read: n_bursts of (2 driven ticks + 1 idle tick), a 6-tick gap,
  // then a ZERO data word (drives the idle pattern) up to BDRY.
  task train_read(input [23:0] addr, input [15:0] tval, input integer n_bursts,
                  input [15:0] expect_val, input [255:0] what);
    integer k;
    begin
      c_wr = 0; c_addr = addr; c_req = 1;
      step;
      c_req = 0;
      grant_and_take_address();
      for (k = 0; k < 4; k = k + 1) step;
      for (k = 0; k < n_bursts; k = k + 1) begin
        slave_bd_n = ~{8'd0, tval + k[15:0]};
        step; step;
        slave_bd_n = 24'hFFFFFF;
        step;
      end
      for (k = 0; k < 6; k = k + 1) step;    // memory-access gap, zero data
      finish_cycle();
      check(c_err === 1'b0, "unexpected bus error (train)");
      if (c_rdata !== expect_val) begin
        errors = errors + 1;
        $display("FAIL: %0s: rdata %06o expected %06o", what, c_rdata, expect_val);
      end else begin
        $display("ok:   %0s -> %06o", what, c_rdata);
      end
    end
  endtask

  // One scripted WRITE with garbage flicker: the slave records what the
  // master drives at the BDAP window (writes must ignore bus noise).
  task scripted_write(input [23:0] addr, input [15:0] wdata,
                      input [255:0] what);
    reg [15:0] got;
    begin
      c_wr = 1; c_addr = addr; c_wdata = wdata; c_req = 1;
      step;
      c_req = 0;
      grant_and_take_address();
      step; step;
      got = ~bd_bus_n[15:0];                        // slave samples the data
      finish_cycle();
      c_wr = 0;
      check(c_err === 1'b0, "unexpected bus error (write)");
      if (got !== wdata) begin
        errors = errors + 1;
        $display("FAIL: %0s: memory saw %06o expected %06o", what, got, wdata);
      end else begin
        $display("ok:   %0s -> %06o", what, got);
      end
    end
  endtask

  initial begin
`ifdef DUMPFILE
    $dumpfile("ND_DMA_MASTER_STALE_CAPTURE_tb.vcd");
    $dumpvars(0, ND_DMA_MASTER_STALE_CAPTURE_tb);
`endif
    repeat (4) @(negedge sysclk);
    sys_rst_n = 1;
    repeat (4) @(negedge sysclk);

    // T1 - THE BUG: zero word behind a 2-tick CPU transient (the exact
    // measured shape: transient runs straight into the zero-data window,
    // which is electrically identical to idle). Pre-fix rdata = 004151.
    scripted_read(24'o0003001, 16'o004151, 2, 0, 16'o000000, 8, 0, 0,
                  16'o000000, "T1 zero word after 2-tick transient");

    // T2 - nonzero word, transient runs straight into the data window
    scripted_read(24'o0003000, 16'o165562, 2, 0, 16'o007400, 6, 0, 0,
                  16'o007400, "T2 nonzero word after transient");

    // T3 - nonzero word with the documented 1-tick early driver release
    scripted_read(24'o0003003, 16'o000000, 0, 0, 16'o061100, 6, 1, 0,
                  16'o061100, "T3 nonzero word, 1-tick release gap");

    // T4 - clean zero word
    scripted_read(24'o0003002, 16'o000000, 0, 0, 16'o000000, 8, 0, 0,
                  16'o000000, "T4 clean zero word");

    // T5 - data presented only AT the BDRY edge (fallback capture path)
    scripted_read(24'o0003005, 16'o000000, 0, 0, 16'o000002, 0, 0, 1,
                  16'o000002, "T5 data at the BDRY edge");

    // T6 - write: data comes from the master, bus noise must not matter
    scripted_write(24'o0003006, 16'o020032, "T6 write unaffected");

    // T7 - zero word: transient, then a LONG undriven stretch
    scripted_read(24'o0003004, 16'o156475, 2, 10, 16'o000000, 4, 0, 0,
                  16'o000000, "T7 zero word, transient then long idle");

    // T8 - two back-to-back transients, then real data
    scripted_read(24'o0003000, 16'o123456, 2, 0, 16'o007400, 6, 0, 0,
                  16'o007400, "T8 transient train then data");

    // T9 - zero word behind a 3-tick transient
    scripted_read(24'o0003001, 16'o104151, 3, 0, 16'o000000, 8, 0, 0,
                  16'o000000, "T9 zero word after 3-tick transient");

    // T10 - zero word behind a TRAIN of transients (2 driven + 1 idle,
    // repeating): a busy CPU flickers repeatedly, so an idle-count that
    // RESETS on each new flicker never reaches its discard threshold.
    // The bounded freshness window rejects the train regardless.
    train_read(24'o0003002, 16'o004151, 6, 16'o000000,
               "T10 zero word after transient train");

    if (errors == 0) $display("TB_RESULT: PASS");
    else             $display("TB_RESULT: FAIL (%0d errors)", errors);
    $finish;
  end

  initial begin
    #200000;
    $display("FAIL: global watchdog");
    $display("TB_RESULT: FAIL");
    $finish;
  end

endmodule
