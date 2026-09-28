/****************************************************************************
** SC2661_TXINT_tb -- TBMT drop-on-write regression (level-10 flood bug)   **
**                                                                         **
** BINT10 (console TX interrupt) is level-sensitive: BINT10 = IOC2 & TBMT  **
** (IO_REG_41.v). The interrupt handler writes THR; TBMT must drop the     **
** SAME cycle so BINT10 deasserts before the handler can re-enter. The old **
** SC2661 cleared TBMT only later in the TX state machine (and the         **
** TX_STATE_IDLE else re-asserted it the write cycle), so an interrupt-    **
** driven writer (the INSTRUCTION-B "dummy output" stress on level 10)     **
** re-fired and flooded/overwrote THR. Polled output was unaffected.       **
**                                                                         **
** This bench FAILS against the old model and PASSES with the fix.         **
** TB_RESULT: PASS / FAIL.                                                 **
****************************************************************************/
`timescale 1ns / 1ps
`define BOARD_CLK_FREQ 200000
`define UART_BAUD_RATE 9600

module SC2661_TXINT_tb;
  localparam integer DF   = `BOARD_CLK_FREQ / `UART_BAUD_RATE;   // 20
  localparam integer CHAR = 10 * DF;                             // ~200

  reg        sysclk = 1'b0, sys_rst_n = 1'b1;
  reg  [1:0] ADDRESS = 2'b00;
  reg        CE_n = 1'b1, READ_n = 1'b1, RESET = 1'b0;
  reg  [7:0] D = 8'h00;
  wire [7:0] D_OUT;
  wire       TXD, TXDRDY_n, TXEMT_n, RXDRDY_n, DTR_n, RTS_n;

  SC2661_UART dut (
      .sysclk(sysclk), .sys_rst_n(sys_rst_n), .ADDRESS(ADDRESS),
      .BAUD_9600(1'b0),   // build-default divisor; an open input is z, not 0
      .BRCLK(1'b0), .CE_n(CE_n), .CTS_n(1'b0), .DCD_n(1'b0), .DSR_n(1'b0),
      .READ_n(READ_n), .RESET(RESET), .RXC_n(1'b1), .RXD(1'b1), .TXC_n(1'b1),
      .D(D), .D_OUT(D_OUT), .DTR_n(DTR_n), .RTS_n(RTS_n),
      .RXDRDY_n(RXDRDY_n), .TXD(TXD), .TXDRDY_n(TXDRDY_n), .TXEMT_n(TXEMT_n));

  always #5 sysclk = ~sysclk;

  integer errors = 0, i, low_after_write;

  task wr(input [1:0] a, input [7:0] d);
    begin
      @(negedge sysclk); ADDRESS=a; D=d; READ_n=1'b1; CE_n=1'b0;
      @(negedge sysclk); CE_n=1'b1;
      @(negedge sysclk);
    end
  endtask

  initial begin
    RESET=1'b1; sys_rst_n=1'b0; repeat(4) @(negedge sysclk);
    RESET=1'b0; sys_rst_n=1'b1; repeat(4) @(negedge sysclk);

    wr(2'b11, 8'h01);          // command: TxEN=1
    repeat(4) @(negedge sysclk);

    // TBMT (TXDRDY_n low = ready) must be READY before the write
    if (TXDRDY_n !== 1'b0) begin
      $display("FAIL: TXDRDY_n not ready before write (got %b)", TXDRDY_n);
      errors = errors + 1;
    end

    // Write a character to THR (address 0), sampling TXDRDY_n on EVERY cycle
    // from the write strobe onward. This models the level-10 ISR: TBMT must
    // drop the same cycle the THR is loaded, or BINT10 stays asserted and the
    // handler re-fires. Drive the CE pulse inline so the sampling is exact.
    @(negedge sysclk); ADDRESS=2'b00; D=8'h41; READ_n=1'b1; CE_n=1'b0;  // write strobe
    // the write latches on the NEXT posedge; from the following negedge on,
    // TXDRDY_n must already be HIGH (busy) and stay high the whole character.
    low_after_write = 0;
    for (i = 0; i < CHAR - DF; i = i + 1) begin
      @(negedge sysclk);
      if (i == 0) CE_n = 1'b1;          // one-cycle CE pulse
      if (TXDRDY_n === 1'b0) low_after_write = low_after_write + 1;
    end
    if (low_after_write != 0) begin
      $display("FAIL: TXDRDY_n was READY %0d cycles after the THR write (re-fire/flood window)", low_after_write);
      errors = errors + 1;
    end else
      $display("OK: TXDRDY_n dropped BUSY on the write and stayed busy (no re-fire window)");

    // After the character completes it must return to ready exactly once.
    for (i = 0; i < 3*CHAR; i = i + 1) begin
      @(negedge sysclk);
      if (TXDRDY_n === 1'b0) i = 3*CHAR;   // saw ready again
    end
    if (TXDRDY_n !== 1'b0) begin
      $display("FAIL: TXDRDY_n never returned ready after the character");
      errors = errors + 1;
    end else
      $display("OK: TXDRDY_n returned ready after the character sent");

    if (errors == 0) $display("TB_RESULT: PASS");
    else             $display("TB_RESULT: FAIL (%0d errors)", errors);
    $finish;
  end

  initial begin #500000; $display("FAIL: timeout"); $display("TB_RESULT: FAIL"); $finish; end
endmodule
