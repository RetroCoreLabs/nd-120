/**************************************************************************
** F595 transparency testbench - PINPOINT the sibling of the ACAL bug.    **
**                                                                        **
** The NEC F595 is a GATED TRANSPARENT R/S LATCH: while the gate G is      **
** high, Q follows S/R combinationally (ZERO latency); when G is low it    **
** holds. F595.v implements that under `ifdef VERILATOR_SIM` (always @*)   **
** but uses a 1-cycle `posedge sysclk` FF under `else` (FPGA). F595.v's    **
** own comment warns the lag "would cause TVEC=016 to miss the first       **
** FETCH step after COMM.CONTINUE" - the same class of silicon bug as      **
** CPU_CS_ACAL_17 (fixed 19-JUL).                                          **
**                                                                         **
** This tb asserts the ZERO-LATENCY transparency: with G=1, asserting S    **
** must drive Q=1 in the SAME evaluation, no clock edge. Compiled in FPGA  **
** mode (NO VERILATOR_SIM) it exercises the `else` branch:                 **
**   - on the CURRENT 1-cycle-lag FF code it FAILS (Q lags),               **
**   - on a transparent-latch fix it PASSES.                               **
** So it PINPOINTS whether the FPGA branch violates the latch semantics.   **
**                                                                         **
** Repo path:                                                             **
**  Verilog/DECODE-GateArray/DGA/sim/                                     **
**  F595_transparency_tb.v                                                **
***************************************************************************/
`timescale 1ns / 1ps
`default_nettype none

module F595_transparency_tb;

  reg  sysclk = 0;
  reg  sys_rst_n = 1;
  reg  H01_S = 0;   // Set
  reg  H02_R = 0;   // Reset
  reg  H03_G = 0;   // Gate
  wire N01_Q;
  wire N02_QB;

  integer errors = 0;

  F595 DUT (
      .sysclk(sysclk), .sys_rst_n(sys_rst_n),
      .H01_S(H01_S), .H02_R(H02_R), .H03_G(H03_G),
      .N01_Q(N01_Q), .N02_QB(N02_QB)
  );

  always #5 sysclk = ~sysclk;

  task chk;
    input got; input exp; input [255:0] label;
    begin
      if (got !== exp) begin
        $display("FAIL: %0s  Q=%b expected %b", label, got, exp);
        errors = errors + 1;
      end else
        $display("  ok : %0s  Q=%b", label, got);
    end
  endtask

  initial begin
    // release reset, settle
    sys_rst_n = 0; #12; sys_rst_n = 1; #8;

    // Open the gate and assert SET. Transparent latch => Q=1 WITHOUT a clock.
    // (The FPGA 1-cycle-lag FF leaves Q=0 here until the next posedge = FAIL.)
    H03_G = 1; H02_R = 0; H01_S = 1;
    #2;                                   // combinational settle only, NO clock edge
    chk(N01_Q, 1'b1, "SET with gate open tracks Q=1 IMMEDIATELY (zero latency)");

    // Assert RESET (still gate open) - Q=0 immediately.
    H01_S = 0; H02_R = 1;
    #2;
    chk(N01_Q, 1'b0, "RESET with gate open tracks Q=0 IMMEDIATELY (zero latency)");

    // Back to SET, immediate again (this is the COMM.CONTINUE-style back-to-back
    // change that the FPGA lag corrupts).
    H02_R = 0; H01_S = 1;
    #2;
    chk(N01_Q, 1'b1, "SET again (back-to-back) tracks Q=1 IMMEDIATELY");

    // Close the gate: Q must HOLD even if S/R change.
    H03_G = 0; H01_S = 0; H02_R = 1;
    #2;
    chk(N01_Q, 1'b1, "gate closed -> HOLD Q=1 (input change ignored)");

    if (errors == 0)
      $display("TB_RESULT: PASS  (F595 FPGA branch is a zero-latency transparent latch)");
    else
      $display("TB_RESULT: FAIL  (%0d error(s) - F595 FPGA branch LAGS; latch semantics violated)", errors);
    $finish;
  end

  initial begin #100000; $display("TB_RESULT: FAIL (timeout)"); $finish; end

endmodule

`default_nettype wire
