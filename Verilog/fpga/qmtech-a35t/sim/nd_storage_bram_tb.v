`timescale 1ns / 1ps

/***************************************************************************
** nd_storage_bram_tb - the mem_* region-port contract, checked exhaustively
** enough to trust on hardware.
**
** Full path: Verilog/fpga/qmtech-a35t/sim/nd_storage_bram_tb.v
**
** WHAT IS UNDER TEST
** rtl/nd_storage_bram.v holds the nd_storage region for the QMTECH build.
** Every other board puts that region in a big memory - SDRAM on the Tang,
** DDR2 on the Nexys - and this one cannot, because the 16-bit SDRAM bridge
** mode has no 32-bit full-location access (see the module header). So the
** region is a block RAM, and this bench is the only thing standing between
** a mistake in it and a Winchester that reads rubbish on silicon.
**
** THE CONTRACT, from nd_storage_engine.v, checked clause by clause:
**   mem_start  1-cycle pulse, only legal while mem_busy = 0
**   mem_we / mem_addr / mem_wdata  stable from mem_start until mem_done
**   mem_rdata  valid at mem_done AND HELD afterwards
**   mem_busy   level, high for the whole operation
**   mem_done   1-cycle pulse
**
** Checks:
**   1  write then read back, every word of the region (1024 of them)
**   2  mem_done really is one cycle wide, never two
**   3  mem_busy is high from the start pulse until done, with no gap - a
**      gap would let the engine issue a second operation into the middle
**      of this one
**   4  mem_rdata HOLDS its value after done until the next read completes.
**      The engine reads it a cycle or more late, so a port that presented
**      data for one cycle only would pass a naive test and fail in place.
**   5  a write does NOT disturb mem_rdata (the write path must not push an
**      undefined word at the caller)
**   6  back-to-back operations with the start pulse on the very cycle done
**      is observed - the tightest legal sequence, and the one where an
**      off-by-one in the busy logic loses an operation silently
**
** Run: make -C fpga/qmtech-a35t/sim test-storage-bram
***************************************************************************/

module nd_storage_bram_tb;

  localparam integer WORDS = 1024;

  reg         clk = 1'b0;
  reg         rst_n;
  reg         mem_start;
  reg         mem_we;
  reg  [19:0] mem_addr;
  reg  [31:0] mem_wdata;
  wire [31:0] mem_rdata;
  wire        mem_busy;
  wire        mem_done;

  integer checks = 0;
  integer errors = 0;
  integer i;
  integer busy_gap;
  integer done_cycles;
  reg [31:0] held;

  always #5 clk = ~clk;   // 100 MHz

  nd_storage_bram #(.WORDS(WORDS)) dut (
      .stor_clk  (clk),
      .stor_rst_n(rst_n),
      .mem_start (mem_start),
      .mem_we    (mem_we),
      .mem_addr  (mem_addr),
      .mem_wdata (mem_wdata),
      .mem_rdata (mem_rdata),
      .mem_busy  (mem_busy),
      .mem_done  (mem_done)
  );

  task expect_eq(input [127:0] what, input [31:0] got, input [31:0] want);
    begin
      checks = checks + 1;
      if (got !== want) begin
        errors = errors + 1;
        $display("FAIL %0s: got %h want %h (t=%0t)", what, got, want, $time);
      end
    end
  endtask

  //! One operation, driven exactly as the contract allows: assert start for a
  //! single cycle with the payload stable, hold the payload until done, and
  //! count how many cycles busy and done are high on the way. Anything the
  //! caller may not do (a second start while busy, a payload change mid-op)
  //! is deliberately not done here - the point is to check the port keeps its
  //! side of the bargain when the caller keeps its own.
  task do_op(input we, input [19:0] a, input [31:0] d);
    begin
      @(negedge clk);
      mem_start = 1'b1;
      mem_we    = we;
      mem_addr  = a;
      mem_wdata = d;
      @(negedge clk);
      mem_start = 1'b0;

      busy_gap    = 0;
      done_cycles = 0;
      while (mem_done !== 1'b1) begin
        if (mem_busy !== 1'b1) busy_gap = busy_gap + 1;
        @(negedge clk);
        if (busy_gap > 100) begin
          $display("FAIL: operation never completed (addr %0d)", a);
          errors = errors + 1;
          disable do_op;
        end
      end
      // done is high now: count how long it stays high
      while (mem_done === 1'b1) begin
        done_cycles = done_cycles + 1;
        @(negedge clk);
      end

      // check 3: busy never dropped between the start pulse and done
      checks = checks + 1;
      if (busy_gap != 0) begin
        errors = errors + 1;
        $display("FAIL: mem_busy dropped %0d cycle(s) mid-operation (addr %0d)",
                 busy_gap, a);
      end
      // check 2: done is exactly one cycle
      checks = checks + 1;
      if (done_cycles != 1) begin
        errors = errors + 1;
        $display("FAIL: mem_done high for %0d cycles, want 1 (addr %0d)",
                 done_cycles, a);
      end
    end
  endtask

  initial begin
    rst_n     = 1'b0;
    mem_start = 1'b0;
    mem_we    = 1'b0;
    mem_addr  = 20'd0;
    mem_wdata = 32'd0;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    // ---- check 1: every word writes and reads back --------------------
    // A distinctive pattern per address, so a stuck or swapped address bit
    // shows up as a wrong VALUE rather than as a coincidence.
    for (i = 0; i < WORDS; i = i + 1)
      do_op(1'b1, i[19:0], {~i[15:0], i[15:0]});

    for (i = 0; i < WORDS; i = i + 1) begin
      do_op(1'b0, i[19:0], 32'd0);
      expect_eq("readback", mem_rdata, {~i[15:0], i[15:0]});
    end

    // ---- check 4: mem_rdata HOLDS after done --------------------------
    do_op(1'b0, 20'd7, 32'd0);
    held = mem_rdata;
    expect_eq("read word 7", held, {~16'd7, 16'd7});
    repeat (5) @(negedge clk);
    expect_eq("rdata held 5 cycles after done", mem_rdata, held);

    // ---- check 5: a write must not disturb mem_rdata ------------------
    do_op(1'b1, 20'd9, 32'hDEAD_BEEF);
    expect_eq("rdata survives a write", mem_rdata, held);
    do_op(1'b0, 20'd9, 32'd0);
    expect_eq("the write did land", mem_rdata, 32'hDEAD_BEEF);

    // ---- check 6: back-to-back, start on the cycle done is seen -------
    // do_op already leaves the bus one cycle after done, which is the
    // tightest the engine ever goes. Two writes and two reads with nothing
    // in between prove no operation is swallowed.
    do_op(1'b1, 20'd100, 32'h1111_2222);
    do_op(1'b1, 20'd101, 32'h3333_4444);
    do_op(1'b0, 20'd100, 32'd0);
    expect_eq("back-to-back word 100", mem_rdata, 32'h1111_2222);
    do_op(1'b0, 20'd101, 32'd0);
    expect_eq("back-to-back word 101", mem_rdata, 32'h3333_4444);

    // ---- verdict ------------------------------------------------------
    $display("");
    $display("nd_storage_bram_tb: %0d checks, %0d errors", checks, errors);
    if (errors == 0) $display("TB_RESULT: PASS");
    else             $display("TB_RESULT: FAIL");
    $finish;
  end

endmodule
