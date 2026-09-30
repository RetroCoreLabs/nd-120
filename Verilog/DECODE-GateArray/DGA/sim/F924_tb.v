`timescale 1ns / 1ps
`default_nettype none

/**************************************************************************
** Testbench for F924 - NEC 4-BIT D-TYPE FLIP-FLOP (DGA standard cell)   **
** Verilog/DECODE-GateArray/DGA/circuit/                                 **
**   F924.v                                                              **
**                                                                       **
** WHAT IS VERIFIED                                                      **
**   F924 is a bare 4-bit register: four Shared/logisim D_FLIPFLOP       **
**   instances (InvertClockEnable=0, ACTIVE_ASYNC default 0, preset and  **
**   reset tied to constant 0, tick tied 1). It has no enable, no reset  **
**   and no ifdef, so ONE build mode covers every path in the cell.      **
**   Because it is used as the capture register on nearly every DGA      **
**   sheet, the only ways it can be wrong are WIRING ways, and those are **
**   exactly what this bench targets:                                    **
**     W1. per-bit data routing  D0_H01->N01_Q0 .. D3_H04->N04_Q3        **
**         (a swapped pair here would silently permute a whole decode    **
**         field on the parent sheet)                                    **
**     W2. per-bit complement routing N05_Q0B..N08_Q3B = ~N01_Q0..N04_Q3 **
**         at ALL times, including before the first clock                **
**     W3. bit independence - one D input may never disturb another bit  **
**     W4. edge sensitivity - capture on the RISING edge of C_H05 only;  **
**         a falling edge and a static D change must NOT change Q        **
**     W5. power-on state - the logisim D_FLIPFLOP initialises           **
**         s_currentState to 0, so at t=0 Q=0000 and QB=1111.            **
**                                                                       **
** WHERE THE REFERENCE MODEL COMES FROM                                  **
**   Read off the NETLIST, not from a drawing and not from an NEC        **
**   datasheet: F924.v lines 12-38 (port list) and 68-116 (the four      **
**   D_FLIPFLOP instances) give the map                                  **
**       MEMORY_1 d=D0_H01 q=N01_Q0 qBar=N05_Q0B                         **
**       MEMORY_2 d=D1_H02 q=N02_Q1 qBar=N06_Q1B                         **
**       MEMORY_3 d=D2_H03 q=N03_Q2 qBar=N07_Q2B                         **
**       MEMORY_4 d=D3_H04 q=N04_Q3 qBar=N08_Q3B                         **
**   and Shared/logisim/D_FLIPFLOP.v gen_sync gives                      **
**       always @(posedge clock) s_currentState <= d;                    **
**   The bench model is written independently as a 4-bit `expect_q` reg  **
**   updated by the testbench's own stimulus, never by reading the DUT.  **
**                                                                       **
** TEST PLAN                                                             **
**   A. t=0 power-on state (Q=0, QB=1) - 8 checks.                       **
**   B. EXHAUSTIVE state x data sweep: for all 16 current states and all **
**      16 D patterns, load the state, apply D, clock, check Q and QB.   **
**      256 transitions, 8 signal checks each.                           **
**   C. Walking-one and walking-zero on the D port from a known          **
**      opposite background - catches a stuck or shorted data pin that   **
**      the sweep could mask if two bits were swapped consistently...    **
**      (the sweep catches swaps too, this layer names the failing pin). **
**   D. Edge sensitivity: falling edge holds; D changes while the clock  **
**      is static hold; a second rising edge with unchanged D holds.     **
**   E. 2000-step fixed-seed xorshift32 soak, clock toggled irregularly  **
**      (some steps with no edge at all) against the independent model.  **
**                                                                       **
** HOW TO RUN                                                            **
**   cd Verilog/DECODE-GateArray/DGA/sim && make test-f924               **
**   or directly:                                                        **
**     iverilog -g2012 -y ../../../Shared/logisim -y ../../../Shared/support \
**              -y ../../../Shared/ndlib -y ../circuit -o F924_tb F924_tb.v \
**     && vvp -N F924_tb                                                 **
**                                                                       **
** Ronny Hansen                                                          **
** 20-AUG-2026                                                           **
***************************************************************************/

module F924_tb;

  localparam integer EXPECTED_CHECKS = 8 + 256*8 + 8*8 + 5*8 + 2000*8;

  reg  C_H05;
  reg  D0_H01, D1_H02, D2_H03, D3_H04;

  wire N01_Q0, N02_Q1, N03_Q2, N04_Q3;
  wire N05_Q0B, N06_Q1B, N07_Q2B, N08_Q3B;

  integer checks = 0;
  integer errors = 0;

  // independent model of the register contents
  reg [3:0] expect_q;

  F924 DUT (
      .C_H05 (C_H05),
      .D0_H01(D0_H01),
      .D1_H02(D1_H02),
      .D2_H03(D2_H03),
      .D3_H04(D3_H04),
      .N01_Q0(N01_Q0),
      .N02_Q1(N02_Q1),
      .N03_Q2(N03_Q2),
      .N04_Q3(N04_Q3),
      .N05_Q0B(N05_Q0B),
      .N06_Q1B(N06_Q1B),
      .N07_Q2B(N07_Q2B),
      .N08_Q3B(N08_Q3B)
  );

  initial begin
    $dumpfile("F924_tb.vcd");
    $dumpvars(0, F924_tb);
  end

  // watchdog - the DUT is combinational-plus-flops with no FSM, but a
  // build that never advances time must still fail loudly.
  initial begin
    #500000;
    $display("FAIL WATCHDOG: testbench did not finish in 500000 ns");
    $display(" checks run : %0d", checks);
    $display(" failures   : %0d", errors + 1);
    $display("TB_RESULT: FAIL");
    $finish;
  end

  task chk1;
    input [127:0] name;
    input         got;
    input         exp;
    begin
      checks = checks + 1;
      if (got !== exp) begin
        errors = errors + 1;
        if (errors < 25)
          $display("FAIL %0s at t=%0t: got %b expected %b", name, $time, got, exp);
      end
    end
  endtask

  // check all 8 outputs against expect_q, naming the exact pin that broke
  task check_all;
    input [127:0] tag;
    begin
      chk1({tag, "/N01_Q0"},  N01_Q0,  expect_q[0]);
      chk1({tag, "/N02_Q1"},  N02_Q1,  expect_q[1]);
      chk1({tag, "/N03_Q2"},  N03_Q2,  expect_q[2]);
      chk1({tag, "/N04_Q3"},  N04_Q3,  expect_q[3]);
      chk1({tag, "/N05_Q0B"}, N05_Q0B, ~expect_q[0]);
      chk1({tag, "/N06_Q1B"}, N06_Q1B, ~expect_q[1]);
      chk1({tag, "/N07_Q2B"}, N07_Q2B, ~expect_q[2]);
      chk1({tag, "/N08_Q3B"}, N08_Q3B, ~expect_q[3]);
    end
  endtask

  task set_d;
    input [3:0] d;
    begin
      D0_H01 = d[0];
      D1_H02 = d[1];
      D2_H03 = d[2];
      D3_H04 = d[3];
    end
  endtask

  // one rising edge of C_H05; the model captures what the pins hold
  task clk_rise;
    begin
      C_H05 = 1'b0; #2;
      C_H05 = 1'b1; #2;
      expect_q = {D3_H04, D2_H03, D1_H02, D0_H01};
      #1;
    end
  endtask

  task clk_fall;
    begin
      C_H05 = 1'b1; #2;
      C_H05 = 1'b0; #2;
      // model unchanged: falling edge must not capture
      #1;
    end
  endtask

  integer st, dv, b;
  reg [31:0] lfsr;
  reg [3:0] dnext;

  initial begin
    C_H05  = 1'b0;
    D0_H01 = 1'b0; D1_H02 = 1'b0; D2_H03 = 1'b0; D3_H04 = 1'b0;
    expect_q = 4'b0000;

    $display("=====================================================");
    $display(" F924 4-bit D flip-flop - wiring + edge testbench");
    $display("=====================================================");

    // ---- A. power-on state, before any clock edge --------------------
    #1;
    check_all("A_POWERON");

    // ---- B. exhaustive 16 states x 16 data patterns -------------------
    for (st = 0; st < 16; st = st + 1) begin
      for (dv = 0; dv < 16; dv = dv + 1) begin
        // force the register into state st
        set_d(st[3:0]);
        clk_rise;
        // now apply dv and capture it
        set_d(dv[3:0]);
        clk_rise;
        check_all("B_SWEEP");
      end
    end

    // ---- C. walking one / walking zero on the data port ---------------
    // background all-zero, walk a single 1: proves D<n> reaches Q<n>
    // and ONLY Q<n>.
    for (b = 0; b < 4; b = b + 1) begin
      set_d(4'b0000); clk_rise;
      set_d(4'b0001 << b); clk_rise;
      check_all("C_WALK1");
    end
    // background all-one, walk a single 0
    for (b = 0; b < 4; b = b + 1) begin
      set_d(4'b1111); clk_rise;
      set_d(~(4'b0001 << b)); clk_rise;
      check_all("C_WALK0");
    end

    // ---- D. edge sensitivity ------------------------------------------
    set_d(4'b1010); clk_rise;              // Q = 1010
    set_d(4'b0101);
    clk_fall;                              // falling edge: must HOLD 1010
    check_all("D_FALL_HOLDS");

    #5;                                    // static clock low, D=0101
    check_all("D_STATIC_LOW_HOLDS");

    C_H05 = 1'b1; #2;                      // rising edge captures 0101
    expect_q = 4'b0101; #1;
    check_all("D_RISE_CAPTURES");

    set_d(4'b1111);                        // D changes while clock stays high
    #5;
    check_all("D_STATIC_HIGH_HOLDS");

    C_H05 = 1'b0; #2;                      // clock back low: still holds
    #1;
    check_all("D_RETURN_LOW_HOLDS");

    // ---- E. fixed-seed soak, irregular clocking -----------------------
    lfsr = 32'h5EED_F924;
    for (st = 0; st < 2000; st = st + 1) begin
      lfsr = lfsr ^ (lfsr << 13);
      lfsr = lfsr ^ (lfsr >> 17);
      lfsr = lfsr ^ (lfsr << 5);
      dnext = lfsr[3:0];
      set_d(dnext);
      #1;
      case (lfsr[5:4])
        2'b00: begin  // no edge at all - clock left where it was
          #2;
        end
        2'b01: begin  // drive the clock low: a falling edge if it was
          C_H05 = 1'b0; #2; #1;  // high, otherwise nothing. Never captures.
        end
        default: clk_rise;
      endcase
      check_all("E_SOAK");
    end

    $display("-----------------------------------------------------");
    if (checks !== EXPECTED_CHECKS) begin
      errors = errors + 1;
      $display("FAIL CHECK_COUNT: ran %0d checks, expected %0d", checks, EXPECTED_CHECKS);
    end
    $display(" checks run : %0d", checks);
    $display(" failures   : %0d", errors);
    if (errors == 0) $display("TB_RESULT: PASS");
    else             $display("TB_RESULT: FAIL");
    $display("=====================================================");
    $finish;
  end

endmodule

`default_nettype wire
