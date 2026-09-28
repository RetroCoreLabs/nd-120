//============================================================================
//! Equivalence-check driver for MEM_RAM_49_BLOCKRAM (31-AUG-2026) - same
//! purpose and method as IDT6168A_20_equiv_tb.v: drive the REAL DRAM
//! protocol (RAS/CAS/AA phases) with a deterministic sequence, log every
//! cycle, run once plain and once with -DQUARTUS_RAM_INFER=1, diff
//! (Shared/support/sim/run_quartus_ram_equiv.sh).
//!
//! SELF-CHECK (28-SEP-2026). Identical logs only prove the two arms agree -
//! they can agree on a wrong answer. So each run ALSO checks every read
//! window against a plain model: the word last written to {bank, row, col},
//! with both parity bits made again as ODD parity (parity is never stored),
//! CORR_n high, and 0 on the pins outside a read window. "TB_RESULT: PASS"
//! only when every check matched AND enough reads of written words were
//! checked to mean something, else "TB_RESULT: FAIL".
//! run_quartus_ram_equiv.sh needs PASS from both arms before it diffs.
//!
//! Fixed the same day: access() took the bank as a 1-bit input, so the
//! "bank 2" accesses went to bank 0 and bank 2 was never touched. And a
//! negative $random % 3 picked no bank at all. Both are fixed below.
//!
//! Run: make test-mem-ram-equiv   (in this directory)
//============================================================================

`timescale 1ns / 1ps

module MEM_RAM_49_BLOCKRAM_equiv_tb;

  localparam integer BANK_ADDR_BITS = 12;

  reg        sysclk = 0;
  reg        sys_rst_n = 0;
  reg [ 9:0] AA_9_0 = 0;
  reg        BANK0 = 0, BANK1 = 0, BANK2 = 0;
  reg        CAS = 0, RAS = 0;
  reg        MWRITE50_n = 1;
  reg [17:0] DD_17_0_IN = 0;
  wire [17:0] DD_17_0_OUT;
  wire       CORR_n;

  integer logf;
  integer seed = 32'hBADC0DE;

  // The model the read data is checked against, indexed {bank, low 12 bits
  // of {row, col}} - the same linear address the RAM uses. Unwritten words
  // stay x and must read back as x (compared with !==).
  reg     [15:0] model[0:(3 << BANK_ADDR_BITS)-1];
  reg     [17:0] exp_dd;
  integer        errors = 0;
  integer        checks = 0;       // samples whose output was compared
  integer        known_reads = 0;  // read windows on a word that was written
  integer        bank_hits[0:2];   // accesses per bank, to prove all three were used

  // {high byte, low byte} -> 18-bit word with odd parity, as the RAM makes it
  function [17:0] with_parity(input [15:0] d);
    with_parity = {~(^d[15:8]), d[15:8], ~(^d[7:0]), d[7:0]};
  endfunction

  task check_out(input [17:0] exp_d, input exp_corr, input [127:0] what);
    begin
      checks = checks + 1;
      if (DD_17_0_OUT !== exp_d || CORR_n !== exp_corr) begin
        errors = errors + 1;
        if (errors <= 10)
          $display("FAIL: t=%0t %0s DOUT=%o CORR_n=%b expected DOUT=%o CORR_n=%b", $time, what,
                   DD_17_0_OUT, CORR_n, exp_d, exp_corr);
      end
    end
  endtask

  always #5 sysclk = ~sysclk;

  MEM_RAM_49_BLOCKRAM #(
      .BANK_ADDR_BITS(BANK_ADDR_BITS),
      .NUM_BANKS(3)
  ) DUT (
      .sysclk    (sysclk),
      .sys_rst_n (sys_rst_n),
      .AA_9_0    (AA_9_0),
      .BANK0     (BANK0),
      .BANK1     (BANK1),
      .BANK2     (BANK2),
      .CAS       (CAS),
      .RAS       (RAS),
      .MWRITE50_n(MWRITE50_n),
      .DD_17_0_IN(DD_17_0_IN),
      .DD_17_0_OUT(DD_17_0_OUT),
      .CORR_n    (CORR_n)
  );

  task step;
    begin
      @(posedge sysclk);
      #1;
      logf = $fopen("mem_equiv_log.txt", "a");
      $fdisplay(logf, "%0d AA=%0d B=%b%b%b CAS=%b RAS=%b MWn=%b DIN=%0d DOUT=%0d CORR=%b", $time,
                AA_9_0, BANK0, BANK1, BANK2, CAS, RAS, MWRITE50_n, DD_17_0_IN, DD_17_0_OUT, CORR_n);
      $fclose(logf);
    end
  endtask

  // One full DRAM access: RAS captures row (=addr), then CAS window carries
  // the column; write or read chosen by MWRITE50_n. Mirrors the real
  // protocol comment in MEM_RAM_49_BLOCKRAM.v (row at RAS rising edge,
  // {row,col} linear address).
  integer midx;           // model index of this access
  reg     known;          // the word at midx has been written
  task access(input [9:0] row, input [9:0] col, input [1:0] bank_sel, input wr,
              input [17:0] wdata);
    begin
      BANK0 = (bank_sel == 0);
      BANK1 = (bank_sel == 1);
      BANK2 = (bank_sel == 2);
      bank_hits[bank_sel] = bank_hits[bank_sel] + 1;

      // {row, col} low BANK_ADDR_BITS bits, as MEM_RAM_49_BLOCKRAM's lin/a
      midx  = (bank_sel << BANK_ADDR_BITS) + ({row, col} & ((1 << BANK_ADDR_BITS) - 1));
      known = ((^model[midx]) !== 1'bx);
      exp_dd = with_parity(model[midx]);

      RAS      = 0;
      CAS      = 0;
      AA_9_0   = row;
      DD_17_0_IN = wdata;
      step;

      RAS = 1;  // rising edge captures row
      step;

      MWRITE50_n = !wr;
      AA_9_0     = col;
      CAS        = 1;  // window open now (RAS & CAS & bank)
      step;
      // A read shows the stored word with parity made again, CORR_n high
      // (x on both for a word nobody wrote). A write shows nothing.
      if (wr) check_out(18'o0, 1'b1, "write window, edge 1");
      else check_out(exp_dd, known ? 1'b1 : 1'bx, "read window, edge 1");
      step;  // hold the window a second cycle (continuous re-read case)
      if (wr) check_out(18'o0, 1'b1, "write window, edge 2");
      else check_out(exp_dd, known ? 1'b1 : 1'bx, "read window, edge 2");
      if (!wr && known) known_reads = known_reads + 1;
      // the write lands once; parity bits DD[8] and DD[17] are dropped
      if (wr) model[midx] = {wdata[16:9], wdata[7:0]};

      RAS = 0;
      CAS = 0;
      step;
      check_out(18'o0, 1'b1, "window closed");
      step;
    end
  endtask

  integer i;
  reg [9:0] r, c;
  reg [17:0] wd;

  initial begin
    logf = $fopen("mem_equiv_log.txt", "w");
    $fclose(logf);
    bank_hits[0] = 0;
    bank_hits[1] = 0;
    bank_hits[2] = 0;

    sys_rst_n = 0;
    repeat (4) step;
    sys_rst_n = 1;

    // directed: write then read back, same address, bank 0
    access(10'h010, 10'h020, 0, 1, 18'h1_5555);
    access(10'h010, 10'h020, 0, 0, 18'h0);

    // directed: burst writes across a bank, sequential columns
    for (i = 0; i < 8; i = i + 1) access(10'h030, 10'h000 + i, 1, 1, {14'd0, i[3:0]} ^ 18'h2_AAAA);
    for (i = 0; i < 8; i = i + 1) access(10'h030, 10'h000 + i, 1, 0, 18'h0);

    // directed: same row, alternating write/read, different banks
    access(10'h040, 10'h001, 2, 1, 18'h3_1234);
    access(10'h040, 10'h001, 2, 0, 18'h0);
    access(10'h040, 10'h001, 0, 1, 18'h0_4321);
    access(10'h040, 10'h001, 0, 0, 18'h0);

    // pseudo-random stress: 300 accesses, mixed read/write, random row/col/bank
    for (i = 0; i < 300; i = i + 1) begin
      r  = $random(seed) % 1024;
      c  = $random(seed) % 1024;
      wd = $random(seed) % 262144;
      // {} makes $random unsigned: a negative remainder picked no bank at all
      access(r, c, {$random(seed)} % 3, ($random(seed) % 2 == 0), wd);
    end

    $display("EQUIV_TB_DONE");
    $display("checked %0d samples, %0d reads of written words, accesses per bank %0d/%0d/%0d, %0d errors",
             checks, known_reads, bank_hits[0], bank_hits[1], bank_hits[2], errors);
    // The directed part alone reads back 1 + 8 + 1 + 1 = 11 written words;
    // fewer, or a bank never used, means the sequence did not run as written.
    if (errors == 0 && checks > 900 && known_reads >= 11 && bank_hits[0] > 0 && bank_hits[1] > 0
        && bank_hits[2] > 0)
      $display("TB_RESULT: PASS");
    else $display("TB_RESULT: FAIL");
    $finish;
  end

endmodule
