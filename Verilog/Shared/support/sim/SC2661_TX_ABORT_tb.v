/**************************************************************************
** ND120 Shared                                                          **
** SC2661 UART - TX abort-on-command-write regression                    **
**                                                                       **
** 24-AUG-2026 (Nexys LIST-FILE-NAMES campaign). The real 2661 completes **
** the character in progress when TxEN is dropped and never destroys the **
** transmit holding register. The old model reset the whole TX machine   **
** on !TxEN:                                                             **
**   1) a command-register write with TxEN=0 during transmission chopped **
**      the character -> misframed console garbage (measured on silicon  **
**      during HELP, reproduced in the dmaSim real-timing LFN run);      **
**   2) a THR character written in the same window was stranded forever  **
**      (txhold full, insend=0, status ready) -> console dead, FILSYS    **
**      spinning in its DEVICE NEVER READY retry loop.                   **
**                                                                       **
** TEST 1: write a char, then mid-character write the command register   **
**         with TxEN=0 followed by TxEN=1 (the shape of a status-poll    **
**         control write). The full 10-bit frame on TXD must be intact.  **
** TEST 2: write a second char while TxEN is 0. After TxEN returns 1,    **
**         that char must be transmitted (not lost).                     **
**                                                                       **
** Verdict: TB_RESULT: PASS / TB_RESULT: FAIL (run_all_tests.sh entry    **
** test-uart-txabort).                                                   **
***************************************************************************/
`timescale 1ns / 1ps

module SC2661_TX_ABORT_tb;

  reg sysclk = 0;
  reg sys_rst_n = 0;
  reg [1:0] address = 2'b00;
  reg reset = 0;
  reg ce_n = 1;
  reg read_n = 1;      // 1 = write access when chip enabled
  reg [7:0] d_in = 8'h00;

  wire [7:0] d_out;
  wire txd;
  wire rxdrdy_n, txdrdy_n, txemt_n;

  integer errors = 0;

  // DELAY_FRAMES defaults to 16 under VERILATOR_SIM; without defines the
  // BOARD_CLK_FREQ/UART_BAUD_RATE path gives 868. Use iverilog with no
  // defines -> DELAY_FRAMES = 100e6/115200 = 868 clocks/bit.
  localparam integer BITCLKS = 868;

  SC2661_UART dut (
      .sysclk(sysclk),
      .sys_rst_n(sys_rst_n),
      .BAUD_9600(1'b0),   // build-default divisor; an open input is z, not 0
      .ADDRESS(address),
      .BRCLK(1'b0),
      .RESET(reset),
      .CE_n(ce_n),
      .READ_n(read_n),
      .CTS_n(1'b0),
      .DCD_n(1'b0),
      .DSR_n(1'b0),
      .DTR_n(),
      .RTS_n(),
      .D(d_in),
      .D_OUT(d_out),
      .RXC_n(1'b0),
      .RXD(1'b1),
      .RXDRDY_n(rxdrdy_n),
      .TXC_n(1'b0),
      .TXD(txd),
      .TXDRDY_n(txdrdy_n),
      .TXEMT_n(txemt_n)
  );

  always #5 sysclk = ~sysclk;

  // one register write: chip-select for a few clocks, then release
  task uart_write(input [1:0] a, input [7:0] v);
    begin
      @(negedge sysclk);
      address = a; d_in = v; read_n = 1; ce_n = 0;
      @(negedge sysclk);
      ce_n = 1;
      @(negedge sysclk);
    end
  endtask

  // sample TXD mid-bit and rebuild the 8 data bits of one frame; call at
  // (or just before) the falling start edge
  task rx_frame(output [7:0] ch, output reg framing_ok);
    integer b;
    begin
      // wait for start bit
      wait (txd == 1'b0);
      // move to middle of start bit
      repeat (BITCLKS / 2) @(posedge sysclk);
      if (txd !== 1'b0) begin
        framing_ok = 0;
        ch = 8'hXX;
      end else begin
        ch = 8'h00;
        for (b = 0; b < 8; b = b + 1) begin
          repeat (BITCLKS) @(posedge sysclk);
          ch[b] = txd;
        end
        // stop bit
        repeat (BITCLKS) @(posedge sysclk);
        framing_ok = (txd === 1'b1);
      end
    end
  endtask

  reg [7:0] got;
  reg fok;

  initial begin
    // reset
    repeat (4) @(negedge sysclk);
    sys_rst_n = 1;
    repeat (4) @(negedge sysclk);

    // enable TX+RX: command register (address 3), TxEN=bit0, RxEN=bit2
    uart_write(2'b11, 8'h05);
    repeat (8) @(negedge sysclk);

    // ---- TEST 1: command write with TxEN=0 mid-character must not chop it
    uart_write(2'b00, 8'h41);            // THR = 'A'
    // let the character get ~3 bit times in
    repeat (3 * BITCLKS) @(posedge sysclk);
    uart_write(2'b11, 8'h04);            // TxEN=0 (RxEN stays 1)
    repeat (20) @(negedge sysclk);
    uart_write(2'b11, 8'h05);            // TxEN=1 again
    // now receive the frame that SHOULD have started before the writes:
    // we are mid-frame already, so rebuild from the start we know: instead,
    // watch that TXD keeps a legal frame: wait for the line to go idle and
    // count total low time. Simpler check: receive the NEXT full frame by
    // sending a fresh char after the line idles, but FIRST verify the line
    // returns to mark within one frame time of the original start (i.e. the
    // char was not restarted or chopped short).
    begin : t1
      integer lowclks;
      integer i;
      lowclks = 0;
      // watch for 11 bit times from now (rest of the frame)
      for (i = 0; i < 11 * BITCLKS; i = i + 1) begin
        @(posedge sysclk);
        if (txd == 1'b0) lowclks = lowclks + 1;
      end
      if (txd !== 1'b1) begin
        $display("TEST1 FAIL: TXD not idle after one frame time (char chopped or restarted)");
        errors = errors + 1;
      end else if (lowclks < BITCLKS) begin
        // 'A' = 0x41 still has several 0 data bits left after 3 bit times;
        // fewer than one full bit time of low = the character was aborted,
        // not completed (pre-fix RTL measures lowclks=0 here)
        $display("TEST1 FAIL: char aborted - only %0d low clocks in the rest of the frame", lowclks);
        errors = errors + 1;
      end else begin
        $display("TEST1 PASS: frame completed after the TxEN=0 window (lowclks=%0d)", lowclks);
      end
    end

    // ---- TEST 2: char written while TxEN=0 must be sent once TxEN=1
    uart_write(2'b11, 8'h04);            // TxEN=0
    repeat (8) @(negedge sysclk);
    uart_write(2'b00, 8'h5A);            // THR = 'Z' while disabled
    repeat (4 * BITCLKS) @(posedge sysclk);  // stay disabled a while
    if (txd !== 1'b1) begin
      $display("TEST2 FAIL: transmitter started while TxEN=0");
      errors = errors + 1;
    end
    uart_write(2'b11, 8'h05);            // TxEN=1
    fork : t2
      begin
        rx_frame(got, fok);
        if (got === 8'h5A && fok) begin
          $display("TEST2 PASS: pending char 5A transmitted after TxEN returned (got=%02x)", got);
        end else begin
          $display("TEST2 FAIL: got=%02x framing_ok=%0d (expected 5A, ok)", got, fok);
          errors = errors + 1;
        end
        disable t2;
      end
      begin
        repeat (30 * BITCLKS) @(posedge sysclk);
        $display("TEST2 FAIL: pending char never transmitted (stranded THR)");
        errors = errors + 1;
        disable t2;
      end
    join

    if (errors == 0) $display("TB_RESULT: PASS");
    else $display("TB_RESULT: FAIL (%0d errors)", errors);
    $finish;
  end

endmodule
