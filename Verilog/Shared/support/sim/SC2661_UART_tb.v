/****************************************************************************
** SC2661_UART_tb -- transmit-path timing testbench                        **
**                                                                         **
** Purpose: verify the TX "buffer empty" status flags set CORRECTLY and    **
** QUICKLY after a character write, so OPCOM does not stall between chars.  **
**   TxRDY  = status bit 0 = Transmit Holding Register empty (TXDRDY_n low) **
**   TxEMT  = status bit 2 = Transmit Shift Register empty   (TXEMT_n  low) **
**                                                                         **
** Uses a small DELAY_FRAMES (BOARD_CLK_FREQ/UART_BAUD_RATE = 200000/9600   **
** ~= 20 clks/bit) so a character = ~10 bits = ~200 clks, fast to simulate  **
** while exercising the exact same state machine as the FPGA (1736 clks).   **
****************************************************************************/
`timescale 1ns / 1ps
`define BOARD_CLK_FREQ 200000
`define UART_BAUD_RATE 9600
// DELAY_FRAMES = 200000/9600 = 20 clocks per bit ; char ~= 10*20 = 200 clocks

module SC2661_UART_tb;

  localparam integer DF   = `BOARD_CLK_FREQ / `UART_BAUD_RATE;   // 20
  localparam integer CHAR = 10 * DF;                             // ~200 (start+8+stop)

  reg        sysclk = 1'b0;
  reg        sys_rst_n = 1'b1;
  reg  [1:0] ADDRESS = 2'b00;
  reg        CE_n = 1'b1;
  reg        READ_n = 1'b1;
  reg        RESET = 1'b0;
  reg  [7:0] D = 8'h00;
  wire [7:0] D_OUT;
  wire       TXD, TXDRDY_n, TXEMT_n, RXDRDY_n, DTR_n, RTS_n;

  SC2661_UART dut (
      .sysclk   (sysclk),
      .sys_rst_n(sys_rst_n),
      .BAUD_9600(1'b0),     // build-default divisor; an open input is z, not 0
      .ADDRESS  (ADDRESS),
      .BRCLK    (1'b0),
      .CE_n     (CE_n),
      .CTS_n    (1'b0),      // asserted (transmit allowed)
      .DCD_n    (1'b0),
      .DSR_n    (1'b0),
      .READ_n   (READ_n),
      .RESET    (RESET),
      .RXC_n    (1'b1),
      .RXD      (1'b1),
      .TXC_n    (1'b1),
      .D        (D),
      .D_OUT    (D_OUT),
      .DTR_n    (DTR_n),
      .RTS_n    (RTS_n),
      .RXDRDY_n (RXDRDY_n),
      .TXD      (TXD),
      .TXDRDY_n (TXDRDY_n),
      .TXEMT_n  (TXEMT_n)
  );

  always #5 sysclk = ~sysclk;   // 100 MHz-ish

  integer cyc = 0;
  always @(posedge sysclk) cyc = cyc + 1;

  // --- register write: one CE_n-low pulse (READ_n=1 => write) ---
  task wr(input [1:0] a, input [7:0] d);
    begin
      @(negedge sysclk); ADDRESS = a; D = d; READ_n = 1'b1; CE_n = 1'b0;
      @(negedge sysclk); CE_n = 1'b1;
      @(negedge sysclk);
    end
  endtask

  // --- register read (status): returns D_OUT ---
  task rd(input [1:0] a, output [7:0] q);
    begin
      @(negedge sysclk); ADDRESS = a; READ_n = 1'b0; CE_n = 1'b0;
      @(negedge sysclk); q = D_OUT; CE_n = 1'b1; READ_n = 1'b1;
      @(negedge sysclk);
    end
  endtask

  integer t_write, t_txrdy, t_txemt;
  reg [7:0] st;
  integer i;

  initial begin
    $dumpfile("SC2661_UART_tb.vcd");
    $dumpvars(0, SC2661_UART_tb);

    $display("DELAY_FRAMES=%0d  char~=%0d clocks", DF, CHAR);

    // Master reset
    RESET = 1'b1; repeat (6) @(negedge sysclk); RESET = 1'b0;
    repeat (4) @(negedge sysclk);

    // Configure: mode regs (cosmetic in this model) + command reg TxEN=1 (bit0)
    wr(2'b10, 8'h4E);   // mode 1
    wr(2'b10, 8'h37);   // mode 2
    wr(2'b11, 8'h01);   // command: TxEN=1
    repeat (4) @(negedge sysclk);

    $display("\n--- TEST 1: single char, measure flag timing ---");
    $display("[cyc %0d] TXDRDY_n=%b TXEMT_n=%b (idle: both should read 'empty' = low)",
             cyc, TXDRDY_n, TXEMT_n);

    // Write a character
    wr(2'b00, 8'h41);   // 'A'
    t_write = cyc;
    $display("[cyc %0d] wrote 'A' to THR", t_write);

    // Wait for TxRDY (TXDRDY_n low) to re-assert = "ready for next char"
    t_txrdy = -1; t_txemt = -1;
    for (i = 0; i < 4*CHAR; i = i + 1) begin
      @(posedge sysclk);
      if (t_txrdy < 0 && TXDRDY_n == 1'b0 && cyc > t_write + 2) t_txrdy = cyc;
      if (t_txemt < 0 && TXEMT_n  == 1'b0 && cyc > t_write + 2) t_txemt = cyc;
    end
    $display("[result] TxRDY re-asserted after %0d clocks (~%0d char-times)",
             (t_txrdy<0)?-1:(t_txrdy - t_write), (t_txrdy<0)?-1:((t_txrdy - t_write)/CHAR));
    $display("[result] TxEMT asserted    after %0d clocks (~%0d char-times)",
             (t_txemt<0)?-1:(t_txemt - t_write), (t_txemt<0)?-1:((t_txemt - t_write)/CHAR));
    if (t_txrdy - t_write > CHAR + 2*DF)
      $display("  >> TxRDY held busy for the WHOLE char (no double-buffer) -- CPU cannot queue ahead");

    $display("\n--- TEST 2: does reading STATUS clear TxEMT (bit2)? ---");
    rd(2'b01, st);
    $display("[cyc %0d] status read #1 = %02h (TxRDY=bit0=%b TxEMT=bit2=%b)", cyc, st, st[0], st[2]);
    rd(2'b01, st);
    $display("[cyc %0d] status read #2 = %02h (TxEMT=bit2=%b) %s",
             cyc, st, st[2], (st[2]==1'b0) ? ">> TxEMT was CLEARED by the previous read!" : "");

    $display("\n--- TEST 3: send 8 chars back-to-back polling TxRDY, measure total ---");
    t_write = cyc;
    for (i = 0; i < 8; i = i + 1) begin
      // poll TxRDY (bit0) via status read
      st = 8'h00;
      while (st[0] !== 1'b1) rd(2'b01, st);
      wr(2'b00, 8'h30 + i[7:0]);   // '0'..'7'
    end
    // wait last char done
    while (TXEMT_n == 1'b1) @(posedge sysclk);
    $display("[result] 8 chars took %0d clocks = %0d clocks/char (ideal ~%0d = 1 char-time)",
             cyc - t_write, (cyc - t_write)/8, CHAR);

    $display("\nDONE");
    $finish;
  end

  // safety timeout
  initial begin
    #2000000;
    $display("TIMEOUT -- a flag likely never asserted (TX stuck)");
    $finish;
  end

endmodule
