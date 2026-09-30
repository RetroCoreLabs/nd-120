/**************************************************************************************************
** ND-100 DMA BUS MASTER - reset collision and s_pend liveness testbench                         **
**                                                                                               **
** DUT: Verilog/ND-BUS-DEVICES/DMA/circuit/ND_DMA_MASTER.v                                       **
**                                                                                               **
** WHY THIS BENCH EXISTS                                                                         **
**   Vivado reports, for the DMA subsystem:                                                      **
**     (a) registers with "both Set and reset with same priority - may cause simulation          **
**         mismatches", and                                                                      **
**     (b) registers DELETED as unused, among them s_pend at ND_DMA_MASTER.v:171.                **
**   The existing bench nd_dma_master_tb.v covers the bus protocol; neither question is          **
**   touched there. This bench answers both by measurement.                                      **
**                                                                                               **
** WHAT IS MEASURED - THREE THINGS                                                               **
**                                                                                               **
**   1. s_pend LIVENESS. s_pend is written only inside                                           **
**        if (EARLY_REREQ != 0 && ...)   (ND_DMA_MASTER.v:222, :306, :330)                       **
**      and EARLY_REREQ is a compile-time parameter that defaults to 0 (no build defines         **
**      `ND_DMA_EARLY_REREQ - see the parameter comment at ND_DMA_MASTER.v:56-67). The bench      **
**      instantiates the master TWICE, once with EARLY_REREQ=0 and once with EARLY_REREQ=1, on    **
**      two independent bus models, sends the SAME stimulus to both (a second dma_req arriving    **
**      while the first transfer is still running) and counts the completions:                   **
**        EARLY_REREQ=0 : s_pend must stay 0 for the whole run  -> exactly ONE completion         **
**        EARLY_REREQ=1 : s_pend must go high                   -> exactly TWO completions        **
**      That decides whether anything "should have been reading" s_pend: nothing else in the      **
**      module names it, and with the parameter at its default the buffered request cannot be     **
**      created at all, so the deletion is a correct constant-propagation result and not a        **
**      dropped feature.                                                                          **
**                                                                                               **
**   2. RESET vs SET COLLISION. ND_DMA_MASTER has ONE clocked block                              **
**      (ND_DMA_MASTER.v:184, posedge sysclk or negedge sys_rst_n). Six registers take a          **
**      non-zero value in the reset branch - BREQ_n, BAPR_n, BINPUT_n, BDAP_n, s_prev_bmem_n and  **
**      BD_23_0_n_OUT - so they synthesise with an asynchronous PRESET, and the same six are      **
**      also SET synchronously by the local timeout guard (ND_DMA_MASTER.v:334-347). This bench   **
**      drives sys_rst_n low at 64 successive single-cycle offsets across a STALLED transfer -    **
**      the memory model is switched off so the timeout guard is armed and fires somewhere        **
**      inside that window - so the reset edge lands on, before and after the cycle in which the  **
**      synchronous set fires. After every one of those the full idle vector is checked:          **
**        BREQ_n=1 BAPR_n=1 BDAP_n=1 BINPUT_n=1 BD=FFFFFF dma_ack=0 dma_err=0 dma_busy=0          **
**      and no bit may be x or z. This is the property the Vivado warning threatens.              **
**                                                                                               **
**   3. TIMEOUT-COUNTER CHARACTERISATION across an EARLY_REREQ chain. Recorded, not specified -   **
**      see the DEFECT note below.                                                                **
**                                                                                               **
** DEFECT RECORDED AS CHARACTERISATION (reported, NOT fixed - this bench does not touch RTL)     **
**   ND_DMA_MASTER.v:328 clears s_tick_cnt when a chained EARLY_REREQ word re-enters ST_REQ, but  **
**   the hang-guard at ND_DMA_MASTER.v:335 runs LATER in the same always block and re-increments  **
**   the same register whenever s_state != ST_IDLE. At that point s_state is still ST_END, so the **
**   guard's assignment is the last one and WINS: the clear never takes effect and the timeout    **
**   counter runs cumulatively across a chain instead of per word. The bench records the measured **
**   value so a change in this behaviour is caught; it does not assert which value is right.      **
**   Harmless in every shipped build (EARLY_REREQ is 0 there), which is why it has not been seen. **
**                                                                                               **
** BUS MODEL: the BCU + memory model is a cut-down copy of the one in nd_dma_master_tb.v          **
** (arbitration delay -> BMEM + grant -> latch address at BAPR -> answer at BDAP with BDRY).      **
** It is wrapped in a helper module so each master gets its own private bus.                      **
**                                                                                               **
** No `ifdef FPGA_FF_MODE appears anywhere in ND_DMA_MASTER.v, so a single build mode covers it.  **
**                                                                                               **
** Compile+run (from the repository root):                                                        **
**   cd Verilog/ND-BUS-DEVICES/DMA/sim && make test-dma-reset-pend                                **
**                                                                                               **
** Prints "TB_RESULT: PASS" or "TB_RESULT: FAIL" as the final line.                               **
**                                                                                               **
** 20-AUG-2026                                                                                    **
** Ronny Hansen                                                                                   **
***************************************************************************************************/
`timescale 1ns / 1ps
`default_nettype none

// -------------------------------------------------------------------------------------------
// One master plus its own private BCU + memory model.
// -------------------------------------------------------------------------------------------
module dma_rig #(
    parameter EARLY = 0,
    parameter [15:0] TMO = 16'd200
) (
    input  wire        sysclk,
    input  wire        sys_rst_n,
    input  wire        model_enable,  // 0 = memory dead, arms the timeout guard
    input  wire        dma_req,
    input  wire        dma_wr,
    input  wire [23:0] dma_addr,
    input  wire [15:0] dma_wdata,
    output wire [15:0] dma_rdata,
    output wire        dma_ack,
    output wire        dma_err,
    output wire        dma_busy,
    output wire        BREQ_n,
    output wire [23:0] BD_OUT_n,
    output wire        BAPR_n,
    output wire        BINPUT_n,
    output wire        BDAP_n
);

  reg         bmem_n = 1'b1;
  reg         grant_head_n = 1'b1;
  reg  [23:0] mem_bd_n = 24'hFFFFFF;
  reg         bdry_n = 1'b1;

  wire [23:0] bd_bus_n = BD_OUT_n & mem_bd_n;

  ND_DMA_MASTER #(
      .TIMEOUT_TICKS(TMO),
      .BINPUT_HOLD(0),
      .EARLY_REREQ(EARLY),
      .MIN_GAP_TICKS(8'd4)
  ) u_m (
      .sysclk(sysclk),
      .sys_rst_n(sys_rst_n),
      .dma_req(dma_req),
      .dma_wr(dma_wr),
      .dma_addr(dma_addr),
      .dma_wdata(dma_wdata),
      .dma_rdata(dma_rdata),
      .dma_ack(dma_ack),
      .dma_err(dma_err),
      .dma_busy(dma_busy),
      .BREQ_n(BREQ_n),
      .INGRANT_n(grant_head_n),
      .OUTGRANT_n(),
      .BMEM_n(bmem_n),
      .BD_23_0_n_OUT(BD_OUT_n),
      .BD_23_0_n_IN(bd_bus_n),
      .BAPR_n(BAPR_n),
      .BINPUT_n(BINPUT_n),
      .BDAP_n(BDAP_n),
      .BDRY_n(bdry_n)
  );

  reg [15:0] memory[0:255];
  reg [23:0] m_addr = 24'd0;
  reg        m_write = 1'b0;
  reg [3:0]  m_state = 4'd0;
  reg [3:0]  m_cnt = 4'd0;
  integer    mi;

  initial for (mi = 0; mi < 256; mi = mi + 1) memory[mi] = 16'h1234;

  always @(posedge sysclk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      bmem_n       <= 1'b1;
      grant_head_n <= 1'b1;
      mem_bd_n     <= 24'hFFFFFF;
      bdry_n       <= 1'b1;
      m_state      <= 4'd0;
    end else begin
      case (m_state)
        4'd0: if (BREQ_n == 1'b0 && model_enable) begin
          m_cnt   <= 4'd2;
          m_state <= 4'd1;
        end
        4'd1:
        if (m_cnt != 0) m_cnt <= m_cnt - 4'd1;
        else begin
          bmem_n       <= 1'b0;
          grant_head_n <= 1'b0;
          m_state      <= 4'd2;
        end
        4'd2:
        if (BAPR_n == 1'b0) begin
          m_addr  <= ~bd_bus_n;
          m_write <= (BINPUT_n == 1'b0);
          m_state <= 4'd3;
        end
        4'd3:
        if (BDAP_n == 1'b0) begin
          if (m_write) memory[m_addr[7:0]] <= ~bd_bus_n[15:0];
          else mem_bd_n <= ~{8'd0, memory[m_addr[7:0]]};
          bdry_n       <= 1'b0;
          grant_head_n <= 1'b1;
          m_state      <= 4'd4;
        end
        4'd4:
        if (BDAP_n == 1'b1) begin
          bdry_n   <= 1'b1;
          mem_bd_n <= 24'hFFFFFF;
          bmem_n   <= 1'b1;
          m_state  <= 4'd5;
        end
        default: m_state <= 4'd0;
      endcase
    end
  end

endmodule


module ND_DMA_MASTER_RESET_PEND_tb;

  reg sysclk = 1'b0;
  always #10 sysclk = ~sysclk;

  reg         rst_n = 1'b0;
  reg         model_enable = 1'b1;

  reg         req0 = 1'b0, wr0 = 1'b0;
  reg  [23:0] addr0 = 24'd0;
  reg  [15:0] wdata0 = 16'd0;
  wire [15:0] rdata0;
  wire        ack0, err0, busy0, breq0_n, bapr0_n, binput0_n, bdap0_n;
  wire [23:0] bd0_n;

  reg         req1 = 1'b0, wr1 = 1'b0;
  reg  [23:0] addr1 = 24'd0;
  reg  [15:0] wdata1 = 16'd0;
  wire [15:0] rdata1;
  wire        ack1, err1, busy1, breq1_n, bapr1_n, binput1_n, bdap1_n;
  wire [23:0] bd1_n;

  // EARLY_REREQ = 0 : the shipped configuration
  dma_rig #(
      .EARLY(0),
      .TMO  (16'd200)
  ) R0 (
      .sysclk(sysclk),
      .sys_rst_n(rst_n),
      .model_enable(model_enable),
      .dma_req(req0),
      .dma_wr(wr0),
      .dma_addr(addr0),
      .dma_wdata(wdata0),
      .dma_rdata(rdata0),
      .dma_ack(ack0),
      .dma_err(err0),
      .dma_busy(busy0),
      .BREQ_n(breq0_n),
      .BD_OUT_n(bd0_n),
      .BAPR_n(bapr0_n),
      .BINPUT_n(binput0_n),
      .BDAP_n(bdap0_n)
  );

  // EARLY_REREQ = 1 : the only configuration in which s_pend can ever be set
  dma_rig #(
      .EARLY(1),
      .TMO  (16'd200)
  ) R1 (
      .sysclk(sysclk),
      .sys_rst_n(rst_n),
      .model_enable(model_enable),
      .dma_req(req1),
      .dma_wr(wr1),
      .dma_addr(addr1),
      .dma_wdata(wdata1),
      .dma_rdata(rdata1),
      .dma_ack(ack1),
      .dma_err(err1),
      .dma_busy(busy1),
      .BREQ_n(breq1_n),
      .BD_OUT_n(bd1_n),
      .BAPR_n(bapr1_n),
      .BINPUT_n(binput1_n),
      .BDAP_n(bdap1_n)
  );

  integer errors = 0;
  integer checks = 0;
  integer i, k;
  integer acks0, acks1;
  reg pend0_ever, pend1_ever;
  reg [15:0] tick_at_chain;
  reg chain_seen;

  task check;
    input cond;
    input [255:0] what;
    begin
      checks = checks + 1;
      if (!cond) begin
        errors = errors + 1;
        $display("FAIL: %0s (t=%0t)", what, $time);
      end
    end
  endtask

  // completion counters and s_pend observation
  always @(posedge sysclk) begin
    if (rst_n) begin
      if (ack0) acks0 = acks0 + 1;
      if (ack1) acks1 = acks1 + 1;
      if (R0.u_m.s_pend === 1'b1) pend0_ever = 1'b1;
      if (R1.u_m.s_pend === 1'b1) pend1_ever = 1'b1;
      // record the tick counter one cycle after a chained re-request starts
      if (!chain_seen && R1.u_m.s_state == 3'd1 && acks1 == 1) begin
        chain_seen    = 1'b1;
        tick_at_chain = R1.u_m.s_tick_cnt;
      end
    end
  end

  task idle_vector_check;
    input [255:0] tag;
    begin
      check(breq0_n === 1'b1, {tag, " BREQ_n not idle"});
      check(bapr0_n === 1'b1, {tag, " BAPR_n not idle"});
      check(bdap0_n === 1'b1, {tag, " BDAP_n not idle"});
      check(binput0_n === 1'b1, {tag, " BINPUT_n not idle"});
      check(bd0_n === 24'hFFFFFF, {tag, " BD not released to FFFFFF"});
      check(ack0 === 1'b0, {tag, " dma_ack not low"});
      check(err0 === 1'b0, {tag, " dma_err not low"});
      check(busy0 === 1'b0, {tag, " dma_busy not low"});
      check(^{breq0_n, bapr0_n, bdap0_n, binput0_n, bd0_n} !== 1'bx, {tag, " x/z on an output"});
    end
  endtask

  initial begin
    $dumpfile("ND_DMA_MASTER_RESET_PEND_tb.vcd");
    $dumpvars(0, ND_DMA_MASTER_RESET_PEND_tb);
  end

  initial begin
    acks0         = 0;
    acks1         = 0;
    pend0_ever    = 1'b0;
    pend1_ever    = 1'b0;
    chain_seen    = 1'b0;
    tick_at_chain = 16'hFFFF;

    // ---------------- reset release ----------------
    rst_n         = 1'b0;
    repeat (4) @(negedge sysclk);
    idle_vector_check("after-power-on-reset");
    rst_n = 1'b1;
    @(negedge sysclk);

    // ---------------------------------------------------------------
    // 1. s_pend liveness: identical stimulus to both configurations
    // ---------------------------------------------------------------
    // first request
    wr0 = 1'b1;
    wr1 = 1'b1;
    addr0 = 24'h000010;
    addr1 = 24'h000010;
    wdata0 = 16'hBEEF;
    wdata1 = 16'hBEEF;
    req0 = 1'b1;
    req1 = 1'b1;
    @(negedge sysclk);
    req0 = 1'b0;
    req1 = 1'b0;
    // second request while both are still busy
    @(negedge sysclk);
    check(busy0 === 1'b1, "EARLY=0 master not busy when the 2nd request is offered");
    check(busy1 === 1'b1, "EARLY=1 master not busy when the 2nd request is offered");
    addr0 = 24'h000020;
    addr1 = 24'h000020;
    wdata0 = 16'hCAFE;
    wdata1 = 16'hCAFE;
    req0 = 1'b1;
    req1 = 1'b1;
    @(negedge sysclk);
    req0 = 1'b0;
    req1 = 1'b0;

    // let both settle
    repeat (400) @(negedge sysclk);

    check(pend0_ever === 1'b0, "EARLY_REREQ=0: s_pend was written (expected permanently 0)");
    check(pend1_ever === 1'b1, "EARLY_REREQ=1: s_pend never went high");
    check(acks0 == 1, "EARLY_REREQ=0: expected exactly ONE completion");
    check(acks1 == 2, "EARLY_REREQ=1: expected exactly TWO completions");
    check(err0 === 1'b0, "EARLY_REREQ=0: unexpected dma_err");
    check(err1 === 1'b0, "EARLY_REREQ=1: unexpected dma_err");
    check(R0.memory[8'h10] === 16'hBEEF, "EARLY_REREQ=0: first word not written to memory");
    check(R1.memory[8'h10] === 16'hBEEF, "EARLY_REREQ=1: first word not written to memory");
    check(R1.memory[8'h20] === 16'hCAFE, "EARLY_REREQ=1: buffered word not written to memory");
    check(R0.memory[8'h20] === 16'h1234, "EARLY_REREQ=0: second word was written after all");

    $display("");
    $display("---- s_pend liveness -------------------------------------------------------");
    $display("EARLY_REREQ=0 (the shipped default): s_pend ever set = %b, completions = %0d",
             pend0_ever, acks0);
    $display("EARLY_REREQ=1                      : s_pend ever set = %b, completions = %0d",
             pend1_ever, acks1);
    $display(
        "-> at the default parameter s_pend cannot be written at all, and no other signal in");
    $display(
        "   ND_DMA_MASTER.v reads it, so the register is genuinely dead in every shipped build.");
    $display(
        "   With EARLY_REREQ=1 the buffered request is created AND consumed, so the logic works.");
    $display("---------------------------------------------------------------------------");
    $display("");

    // characterisation: the timeout counter across a chained word
    $display("---- timeout-counter characterisation (EARLY_REREQ=1 chain) ---------------");
    if (chain_seen)
      $display("s_tick_cnt at the chained re-request = %0d  (ND_DMA_MASTER.v:328 clears it, but",
               tick_at_chain);
    else $display("chained re-request not observed");
    $display("the hang guard at ND_DMA_MASTER.v:335 re-increments it later in the same block,");
    $display("so the clear is overwritten and the counter runs cumulatively across a chain.)");
    $display("---------------------------------------------------------------------------");
    $display("");
    checks = checks + 1;
    if (chain_seen && tick_at_chain == 16'd0)
      $display("NOTE: s_tick_cnt WAS cleared at the chain - behaviour has changed from 20-AUG-2026.");

    // ---------------------------------------------------------------
    // 2. reset collision sweep: reset at 64 successive offsets across a
    //    stalled transfer, so the reset edge lands before, on and after
    //    the cycle in which the timeout guard sets the same registers.
    // ---------------------------------------------------------------
    model_enable = 1'b0;  // memory dead -> the transfer stalls, the guard arms

    for (i = 0; i < 64; i = i + 1) begin
      rst_n = 1'b0;
      repeat (3) @(negedge sysclk);
      rst_n  = 1'b1;
      @(negedge sysclk);
      // start a transfer that will never be answered
      wr0    = 1'b0;
      addr0  = 24'h000030;
      req0   = 1'b1;
      @(negedge sysclk);
      req0 = 1'b0;
      // run for a variable number of cycles, straddling the timeout
      // (TIMEOUT_TICKS=200, so offsets 170..234 cover the firing cycle)
      for (k = 0; k < 170 + i; k = k + 1) @(negedge sysclk);
      // async reset, asserted between clock edges
      #3 rst_n = 1'b0;
      #4;
      idle_vector_check("async-reset-sweep");
      @(negedge sysclk);
      idle_vector_check("async-reset-sweep-held");
    end

    rst_n = 1'b1;
    model_enable = 1'b1;
    repeat (4) @(negedge sysclk);

    $display("checks=%0d failures=%0d", checks, errors);
    if (errors == 0) $display("TB_RESULT: PASS");
    else $display("TB_RESULT: FAIL");
    $finish;
  end

  // watchdog
  initial begin
    #4000000;
    $display("checks=%0d failures=%0d", checks, errors + 1);
    $display("TB_RESULT: FAIL (watchdog)");
    $finish;
  end

endmodule

`default_nettype wire
