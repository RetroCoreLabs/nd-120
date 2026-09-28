//============================================================================
//! Equivalence-check driver for IDT6168A_20 (31-AUG-2026).
//!
//! It drives a long, deterministic,
//! fixed-seed sequence (burst writes, burst reads, back-to-back same-address
//! writes, CE_n toggling mid-burst, address changes while WE_n stays low)
//! and dumps every cycle's inputs/outputs to a text log. Run this file
//! TWICE - once compiled plain (no defines: exercises the proven
//! plain-Verilog path) and once with -DQUARTUS_RAM_INFER=1 (exercises the
//! arm Quartus builds for the MiSTer) - then diff the two logs. Identical
//! logs = the two implementations are behaviorally equivalent for
//! everything this sequence covers. run_quartus_ram_equiv.sh does exactly
//! that. (Until 01-SEP-2026 the second run was the altsyncram megafunction
//! arm against a hand-written stub; both are gone - see IDT6168A_20.v.)
//!
//! SELF-CHECK (28-SEP-2026). Two identical logs only prove the two arms
//! agree - they can agree on a wrong answer. So each run ALSO checks every
//! cycle's output against a plain model of the chip, the one the reference
//! arm is written to: a registered read, one clock late, of what the array
//! held; 0 on the pin when the chip is not selected or is writing. The run
//! prints "TB_RESULT: PASS" only when every cycle matched AND enough reads of
//! written cells were checked to mean something, else "TB_RESULT: FAIL".
//! run_quartus_ram_equiv.sh needs PASS from both arms before it diffs.
//!
//! Run: make test-quartus-ram-equiv   (in this directory)
//============================================================================

`timescale 1ns / 1ps

module IDT6168A_20_equiv_tb;

  reg        clk = 0;
  reg        reset_n = 0;
  reg [11:0] A_11_0 = 0;
  reg        CE_n = 1;
  reg        WE_n = 1;
  reg [ 3:0] D_3_0_IN = 0;
  wire [3:0] D_3_0_OUT;

  integer logf;
  integer i;
  integer seed = 32'hC0FFEE;

  // The model the output is checked against. Unwritten cells stay x, and a
  // read of one must give x on the pin too (compared with !==), so an arm
  // that invents data for a cell nobody wrote is caught as well.
  reg     [3:0] model[0:4095];
  reg     [3:0] exp_out;
  integer       errors = 0;
  integer       checks = 0;       // cycles whose output was compared
  integer       known_reads = 0;  // reads of a cell that had been written

  always #5 clk = ~clk;

  IDT6168A_20 DUT (
      .clk      (clk),
      .reset_n  (reset_n),
      .A_11_0   (A_11_0),
      .CE_n     (CE_n),
      .WE_n     (WE_n),
      .D_3_0_IN (D_3_0_IN),
      .D_3_0_OUT(D_3_0_OUT)
  );

  task step;
    begin
      // What the pin must show after this edge: the cell read on this edge
      // when the chip is selected for a read, else 0. Worked out from the
      // inputs as they stand BEFORE the edge - the ones the edge samples.
      exp_out = (!CE_n && WE_n) ? model[A_11_0] : 4'b0000;
      if (!CE_n && WE_n && ((^model[A_11_0]) !== 1'bx)) known_reads = known_reads + 1;
      if (!CE_n && !WE_n) model[A_11_0] = D_3_0_IN;
      @(posedge clk);
      #1;
      checks = checks + 1;
      if (D_3_0_OUT !== exp_out) begin
        errors = errors + 1;
        if (errors <= 10)
          $display("FAIL: t=%0t CE=%b WE=%b A=%0o DOUT=%b expected %b", $time, CE_n, WE_n,
                   A_11_0, D_3_0_OUT, exp_out);
      end
      logf = $fopen("equiv_log.txt", "a");
      $fdisplay(logf, "%0d CE=%b WE=%b A=%0d DIN=%0d DOUT=%0d", $time, CE_n, WE_n, A_11_0,
                D_3_0_IN, D_3_0_OUT);
      $fclose(logf);
    end
  endtask

  initial begin
    logf = $fopen("equiv_log.txt", "w");
    $fclose(logf);

    reset_n = 0;
    CE_n    = 1;
    WE_n    = 1;
    repeat (4) step;
    reset_n = 1;

    // --- directed: single write then single read, same address -----------
    A_11_0   = 12'h010;
    D_3_0_IN = 4'hA;
    CE_n     = 0;
    WE_n     = 0;
    step;
    WE_n = 1;
    step;
    step;  // read latency

    // --- directed: burst write, sequential addresses, WE_n held low ------
    CE_n = 0;
    WE_n = 0;
    for (i = 0; i < 16; i = i + 1) begin
      A_11_0   = 12'h100 + i;
      D_3_0_IN = i[3:0] ^ 4'h5;
      step;
    end
    WE_n = 1;

    // --- burst read back the same addresses -------------------------------
    for (i = 0; i < 16; i = i + 1) begin
      A_11_0 = 12'h100 + i;
      step;
    end

    // --- back-to-back writes to the SAME address (repeat write) ----------
    A_11_0   = 12'h200;
    WE_n     = 0;
    D_3_0_IN = 4'h1;
    step;
    D_3_0_IN = 4'h2;
    step;
    D_3_0_IN = 4'h3;
    step;
    WE_n = 1;
    step;  // read back - should see 4'h3

    // --- CE_n toggling mid-burst (deselect for one cycle, then resume) ---
    A_11_0   = 12'h300;
    WE_n     = 0;
    D_3_0_IN = 4'h7;
    step;
    CE_n = 1;  // deselect - this cycle's write must NOT happen
    step;
    CE_n     = 0;
    D_3_0_IN = 4'h8;
    step;
    WE_n = 1;
    step;

    // --- address changes while reading (continuous re-read window) -------
    CE_n = 0;
    WE_n = 1;
    for (i = 0; i < 8; i = i + 1) begin
      A_11_0 = 12'h100 + i;
      step;
    end

    // --- pseudo-random stress: 500 cycles of randomized CE/WE/A/D --------
    for (i = 0; i < 500; i = i + 1) begin
      CE_n     = ($random(seed) % 5 == 0) ? 1'b1 : 1'b0;  // mostly selected
      WE_n     = ($random(seed) % 3 == 0) ? 1'b0 : 1'b1;  // occasional write
      A_11_0   = $random(seed) % 4096;
      D_3_0_IN = $random(seed) % 16;
      step;
    end

    CE_n = 1;
    step;
    step;

    $display("EQUIV_TB_DONE");
    $display("checked %0d cycles, %0d reads of written cells, %0d errors", checks,
             known_reads, errors);
    // The directed part alone reads back 2 + 16 + 1 + 1 + 8 = 28 written
    // cells, so a count below that means the sequence did not run as written.
    if (errors == 0 && checks > 500 && known_reads >= 28) $display("TB_RESULT: PASS");
    else $display("TB_RESULT: FAIL");
    $finish;
  end

endmodule
