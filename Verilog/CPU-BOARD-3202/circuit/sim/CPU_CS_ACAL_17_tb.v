/**************************************************************************
** CPU_CS_ACAL_17 testbench - WCS read-address (LUA) transparent latch    **
**                                                                        **
** Regression test for the Tang Nano 20K boot-hang root cause (19-JUL):   **
** the FPGA build of CPU_CS_ACAL_17 previously used a plain posedge FF+CE  **
** for LUA, which lagged the WCS control-store READ ADDRESS by 1 cycle.    **
** Because LUA feeds the WCS BRAM combinationally, on a microcode JUMP     **
** (e.g. STZ at 06000 -> CONT at 0145) the stale LUA made the WCS return   **
** the WRONG microword, so the sequencer computed a garbage jump target    **
** (measured on silicon: CSBIT_11_0=0xC00=the address, s_jmpaddr=016000)   **
** and wedged at 06000 forever. The fix makes LUA a TRANSPARENT latch      **
** (mux + hold-FF) so it tracks CSA with ZERO latency when MACLK is high.  **
**                                                                         **
** This tb compiles the module in FPGA mode (NO VERILATOR_SIM define) so   **
** it exercises the FIXED `else` branch. It FAILS on the old lagging-FF    **
** code (LUA one cycle late after a jump) and PASSES on the fix.           **
**                                                                         **
** Repo path:                                                             **
**   Verilog/CPU-BOARD-3202/circuit/sim/                                  **
**   CPU_CS_ACAL_17_tb.v                                                  **
** Run: iverilog -g2012 -o /tmp/acal_tb CPU_CS_ACAL_17_tb.v \             **
**        ../CPU_CS_ACAL_17.v && vvp /tmp/acal_tb                         **
***************************************************************************/
`timescale 1ns / 1ps
`default_nettype none

module CPU_CS_ACAL_17_tb;

  reg         sysclk = 0;
  reg         CLK    = 0;
  reg  [12:0] CSA_12_0 = 0;
  reg  [ 9:0] CSCA_9_0 = 0;
  reg         MACLK  = 0;
  reg         PD1    = 0;
  wire [12:0] LUA_12_0;
  wire [11:0] UUA_11_0;

  integer errors = 0;

  CPU_CS_ACAL_17 DUT (
      .sysclk  (sysclk),
      .CLK     (CLK),
      .CSA_12_0(CSA_12_0),
      .CSCA_9_0(CSCA_9_0),
      .MACLK   (MACLK),
      .PD1     (PD1),
      .LUA_12_0(LUA_12_0),
      .UUA_11_0(UUA_11_0)
  );

  // 100 MHz sysclk (the hold-FF clock in FPGA mode)
  always #5 sysclk = ~sysclk;

  task tick;               // one full sysclk period
    begin @(posedge sysclk); #1; end
  endtask

  task check;
    input [12:0] got;
    input [12:0] exp;
    input [255:0] label;
    begin
      if (got !== exp) begin
        $display("FAIL: %0s  LUA=o%06o (0x%03X)  expected o%06o (0x%03X)",
                 label, got, got, exp, exp);
        errors = errors + 1;
      end else begin
        $display("  ok : %0s  LUA=o%06o", label, got);
      end
    end
  endtask

  initial begin
    PD1 = 0;
    CLK = 0;

    // ---- 1. Transparent while MACLK=1: LUA follows CSA immediately ----
    MACLK = 1;
    CSA_12_0 = 13'o000145;   // a control-store address
    #2;                      // combinational settle (no clock needed)
    check(LUA_12_0, 13'o000145, "transparent load 0145 (comb, no clock)");

    // give the hold-FF a clock so it also captures (for later hold test)
    tick;
    check(LUA_12_0, 13'o000145, "still 0145 after a clock");

    // ---- 2. THE REGRESSION: a JUMP while MACLK=1 must track with ZERO latency ----
    // Old buggy FF-lag code: LUA stays at the OLD address for 1 clock here.
    CSA_12_0 = 13'o006000;   // "jump" to a very different address
    #2;                      // combinational settle, NO clock edge yet
    check(LUA_12_0, 13'o006000,
          "JUMP 0145->06000 tracks IMMEDIATELY (zero latency) [regression]");

    // and the reverse jump, also immediate
    CSA_12_0 = 13'o000145;
    #2;
    check(LUA_12_0, 13'o000145, "JUMP 06000->0145 tracks IMMEDIATELY [regression]");

    // ---- 3. Hold when MACLK=0: LUA must NOT follow CSA ----
    // First capture a known value with MACLK=1 + a clock, then drop MACLK.
    CSA_12_0 = 13'o007777;
    MACLK = 1; #2; tick;               // hold-FF now holds 07777, output transparent
    check(LUA_12_0, 13'o007777, "load 07777 with MACLK=1");
    MACLK = 0; #2;                     // latch closed
    CSA_12_0 = 13'o001234;             // change input while closed
    #2; tick;                          // even with a clock, must NOT capture
    check(LUA_12_0, 13'o007777, "HOLD 07777 while MACLK=0 (input changed)");

    // ---- 4. Reopen: MACLK=1 -> immediately shows the new CSA ----
    MACLK = 1; #2;
    check(LUA_12_0, 13'o001234, "reopen MACLK=1 -> tracks 01234 immediately");

    // ---- 5. PD1 forces LUA to 0 ----
    PD1 = 1; #2;
    check(LUA_12_0, 13'o000000, "PD1=1 forces LUA=0");
    PD1 = 0; #2;
    check(LUA_12_0, 13'o001234, "PD1=0 restores transparent 01234");

    // ---- verdict ----
    if (errors == 0)
      $display("TB_RESULT: PASS  (CPU_CS_ACAL_17 LUA is a zero-latency transparent latch)");
    else
      $display("TB_RESULT: FAIL  (%0d error(s) - LUA is not tracking CSA correctly)", errors);
    $finish;
  end

  // safety timeout
  initial begin #100000; $display("TB_RESULT: FAIL (timeout)"); $finish; end

endmodule

`default_nettype wire
