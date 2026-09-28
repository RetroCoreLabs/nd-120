/****************************************************************************
** SC2661_UART_tb -- transmit-path timing testbench                        **
**                                                                         **
** Purpose: verify the TX "buffer empty" status flags set CORRECTLY and    **
** QUICKLY after a character write, so OPCOM does not stall between chars.  **
**   TxRDY  = status bit 0 = Transmit Holding Register empty (TXDRDY_n low) **
**   TxEMT  = status bit 2 = Transmit Shift Register empty   (TXEMT_n  low) **
**                                                                         **
** Uses a small DELAY_FRAMES (BOARD_CLK_FREQ/UART_BAUD_RATE = 400000/20000  **
** = 20 clks/bit) so a character = ~10 bits = ~200 clks, fast to simulate   **
** while exercising the exact same state machine as the FPGA (1736 clks).   **
** (Was 200000/9600 until 28-SEP-2026. That made the build-default divisor **
** and the BAUD_9600 divisor BOTH 20, so the BAUD_9600 select could not    **
** matter here: with the input left open (z) iverilog merges the two equal **
** arms of "BAUD_9600 ? 20 : 20" to 20 and the bench passed. The default   **
** rate is now 20000 so the 9600 arm is 400000/9600 = 41 clocks/bit, and   **
** an open or wrong BAUD_9600 changes - or breaks - the bit time.)         **
**                                                                         **
** Self-checking (28-SEP-2026). The bench used to print its measurements   **
** and then "DONE", and the registry only looked for "DONE" - a test that  **
** can pass silently can fail silently. It now CHECKS what it drives,      **
** counts every mismatch, and ends with one verdict line:                  **
**   TB_RESULT: PASS               - zero errors                           **
**   TB_RESULT: FAIL (<n> errors)  - anything wrong, incl. the timeout     **
** Checked:                                                                **
**   - idle after set-up: TxRDY and TxEMT both "empty", TXD at MARK (1);   **
**   - TxRDY drops (THR busy) straight after a THR write;                   **
**   - a serial monitor decodes every frame on TXD: start bit 0, 8 data    **
**     bits LSB first, stop bit 1, every bit exactly DF clocks long with   **
**     no glitch inside it, and the byte equal to the one written;         **
**   - TxRDY and TxEMT come back once the whole frame is out, and not      **
**     later than one frame plus a few clocks;                             **
**   - status reads: TxRDY, TxEMT, DCD and DSR bits set, and reading the   **
**     status does NOT clear TxEMT; command register reads back;           **
**   - 8 characters back to back, polling TxRDY, all arrive in order and   **
**     each takes no more than one frame plus two bit times (no stall);    **
**   - BAUD_9600 = 1 switches the divisor: one more char, every bit        **
**     exactly D96 = 41 clocks long, and the right byte.                   **
** Registry entry: test-uart in tests/run_all_tests.sh.                    **
****************************************************************************/
`timescale 1ns / 1ps
`define BOARD_CLK_FREQ 400000
`define UART_BAUD_RATE 20000
// DELAY_FRAMES = 400000/20000 = 20 clocks per bit ; char ~= 10*20 = 200 clocks
// BAUD_9600=1  : 400000/9600  = 41 clocks per bit (integer division)

module SC2661_UART_tb;

  localparam integer DF   = `BOARD_CLK_FREQ / `UART_BAUD_RATE;   // 20
  localparam integer CHAR = 10 * DF;                             // ~200 (start+8+stop)
  localparam integer D96  = `BOARD_CLK_FREQ / 9600;              // 41

  // Slack allowed after the last frame bit before TxRDY/TxEMT must be back:
  // the model spends one clock in TX_STATE_DONE and one in TX_STATE_IDLE.
  // A few clocks of headroom, far less than one bit time, so a flag that
  // comes back a whole bit (or char) late still fails.
  localparam integer FLAG_SLACK = 4;

  reg        sysclk = 1'b0;
  reg        sys_rst_n = 1'b1;
  reg  [1:0] ADDRESS = 2'b00;
  reg        CE_n = 1'b1;
  reg        READ_n = 1'b1;
  reg        RESET = 1'b0;
  reg  [7:0] D = 8'h00;
  reg        baud_9600 = 1'b0;   // 0 = build-default divisor; TEST 4 sets 1
  wire [7:0] D_OUT;
  wire       TXD, TXDRDY_n, TXEMT_n, RXDRDY_n, DTR_n, RTS_n;

  SC2661_UART dut (
      .sysclk   (sysclk),
      .sys_rst_n(sys_rst_n),
      .BAUD_9600(baud_9600), // driven, never open: an open input is z, not 0
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

  // Every failed check adds one here; the verdict line is printed from it.
  integer errors = 0;

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

  // --- one check: print what was wrong and count it ---
  task check(input ok, input [8*64-1:0] what);
    begin
      if (!ok) begin
        errors = errors + 1;
        $display("  ERROR [cyc %0d]: %0s", cyc, what);
      end
    end
  endtask

  // ------------------------------------------------------------------------
  // Serial monitor on TXD. Decodes each frame independently of the UART's
  // own state, so it checks what actually leaves the pin. Samples on the
  // FALLING clock edge, half a clock after the UART updates TXD, so there
  // is no same-edge race. A frame is 10 windows of exactly bt clocks
  // (bt = DF normally, D96 while TEST 4 runs with BAUD_9600 = 1):
  // window 0 = start bit (0), 1..8 = data bits LSB first, 9 = stop bit (1).
  // TXD must hold one level for the whole of each window; a change inside
  // a window means a wrong bit time or a glitch.
  // ------------------------------------------------------------------------
  reg  [7:0] expect_q [0:15];   // bytes the stimulus wrote, in order
  integer    n_expect = 0;       // how many have been written
  integer    n_rx     = 0;       // how many frames the monitor has decoded

  integer    bt       = DF;      // expected bit time in clocks (set by stimulus)
  reg        mon_busy = 1'b0;
  integer    mon_pos  = 0;       // clocks since the start-bit edge
  reg  [9:0] mon_bits;           // level at the start of each window
  reg        mon_glitch;         // a level change inside a window

  // Blocking assignments throughout: the monitor is the only writer of its
  // own state and reads each value back within the same clock.
  always @(negedge sysclk) begin
    if (!mon_busy) begin
      if (TXD === 1'b0) begin
        // Start-bit edge: this clock is position 0 of window 0.
        mon_busy   = 1'b1;
        mon_pos    = 0;
        mon_bits   = 10'b0;
        mon_glitch = 1'b0;
      end else if (TXD !== 1'b1) begin
        errors = errors + 1;
        $display("  ERROR [cyc %0d]: TXD is %b while idle (not 0/1)", cyc, TXD);
      end
    end else begin
      mon_pos = mon_pos + 1;
      if ((mon_pos % bt) == 0)
        mon_bits[mon_pos / bt] = TXD;             // first clock of a window
      else if (TXD !== mon_bits[mon_pos / bt])
        mon_glitch = 1'b1;                         // changed inside a window

      if (mon_pos == 10*bt - 1) begin
        // Last clock of the stop-bit window: the frame is complete.
        mon_busy = 1'b0;
        if (mon_glitch) begin
          errors = errors + 1;
          $display("  ERROR [cyc %0d]: frame %0d - TXD changed inside a bit window (bit time is not %0d clocks)",
                   cyc, n_rx, bt);
        end
        if (mon_bits[9] !== 1'b1) begin
          errors = errors + 1;
          $display("  ERROR [cyc %0d]: frame %0d - stop bit is %b, expected 1 (framing)",
                   cyc, n_rx, mon_bits[9]);
        end
        if (n_rx >= n_expect) begin
          errors = errors + 1;
          $display("  ERROR [cyc %0d]: frame %0d decoded (%o octal) but nothing was written for it",
                   cyc, n_rx, mon_bits[8:1]);
        end else if (mon_bits[8:1] !== expect_q[n_rx]) begin
          errors = errors + 1;
          $display("  ERROR [cyc %0d]: frame %0d - TXD sent %o, expected %o (octal)",
                   cyc, n_rx, mon_bits[8:1], expect_q[n_rx]);
        end else begin
          $display("  [monitor] frame %0d on TXD = %o octal, framing OK", n_rx, mon_bits[8:1]);
        end
        n_rx = n_rx + 1;
      end
    end
  end

  // Write one character to THR and remember it for the monitor.
  task send(input [7:0] c);
    begin
      expect_q[n_expect] = c;
      n_expect = n_expect + 1;
      wr(2'b00, c);
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
    check(TXDRDY_n === 1'b0, "idle: TXDRDY_n should be 0 (THR empty)");
    check(TXEMT_n  === 1'b0, "idle: TXEMT_n should be 0 (shift register empty)");
    check(TXD      === 1'b1, "idle: TXD should be 1 (MARK)");

    // Command register reads back what was written (TxEN only = 1 octal).
    rd(2'b11, st);
    check(st === 8'o001, "command register does not read back as 001 octal");

    // Write a character
    send(8'h41);   // 'A'
    t_write = cyc;
    $display("[cyc %0d] wrote 'A' to THR", t_write);
    // The THR is now full: TxRDY must read busy at once (wr() already took
    // two clock edges after the write strobe).
    check(TXDRDY_n === 1'b1, "TXDRDY_n should be 1 (THR busy) right after a THR write");

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

    // Both flags must come back, and only once the frame has left the pin:
    // this model has no separate shift register, so the THR stays busy for
    // the whole frame (CHAR clocks) and both flags return together at the
    // end of it. Earlier = a flag lying about a busy transmitter; later
    // than FLAG_SLACK = the stall this bench was written to catch.
    check(t_txrdy >= 0, "TxRDY never came back after the write (TX stuck)");
    check(t_txemt >= 0, "TxEMT never came back after the write (TX stuck)");
    check(t_txrdy < 0 || (t_txrdy - t_write >= CHAR),
          "TxRDY came back before the whole frame was sent");
    check(t_txrdy < 0 || (t_txrdy - t_write <= CHAR + FLAG_SLACK),
          "TxRDY came back later than one frame + FLAG_SLACK clocks");
    check(t_txemt < 0 || (t_txemt - t_write >= CHAR),
          "TxEMT came back before the whole frame was sent");
    check(t_txemt < 0 || (t_txemt - t_write <= CHAR + FLAG_SLACK),
          "TxEMT came back later than one frame + FLAG_SLACK clocks");
    check(n_rx == 1, "monitor did not decode exactly one frame for 'A'");

    $display("\n--- TEST 2: does reading STATUS clear TxEMT (bit2)? ---");
    rd(2'b01, st);
    $display("[cyc %0d] status read #1 = %02h (TxRDY=bit0=%b TxEMT=bit2=%b)", cyc, st, st[0], st[2]);
    // Expected 305 octal: bit0 TxRDY, bit2 TxEMT, bit6 DCD, bit7 DSR (both
    // DCD_n and DSR_n are tied low = asserted). Receiver is off, so bit1
    // (RxRDY) is 0, and no error bits (3,4,5) may be set.
    check(st === 8'o305, "status read #1 is not 305 octal (TxRDY+TxEMT+DCD+DSR)");
    rd(2'b01, st);
    $display("[cyc %0d] status read #2 = %02h (TxEMT=bit2=%b) %s",
             cyc, st, st[2], (st[2]==1'b0) ? ">> TxEMT was CLEARED by the previous read!" : "");
    check(st[2] === 1'b1, "reading the status register cleared TxEMT (bit 2)");
    check(st === 8'o305, "status read #2 is not 305 octal");

    $display("\n--- TEST 3: send 8 chars back-to-back polling TxRDY, measure total ---");
    t_write = cyc;
    for (i = 0; i < 8; i = i + 1) begin
      // poll TxRDY (bit0) via status read
      st = 8'h00;
      while (st[0] !== 1'b1) rd(2'b01, st);
      send(8'h30 + i[7:0]);   // '0'..'7'
    end
    // wait last char done
    while (TXEMT_n == 1'b1) @(posedge sysclk);
    $display("[result] 8 chars took %0d clocks = %0d clocks/char (ideal ~%0d = 1 char-time)",
             cyc - t_write, (cyc - t_write)/8, CHAR);
    // A char cannot go faster than its frame; more than two extra bit
    // times per char is a stall between characters.
    check((cyc - t_write) >= 8*CHAR, "8 chars went out faster than 8 frames - impossible");
    check((cyc - t_write) <= 8*(CHAR + 2*DF), "8 chars took more than 8*(frame + 2 bit times) - stall");

    // Let the monitor finish the last frame, then all 9 bytes must be in.
    repeat (4) @(negedge sysclk);
    check(n_rx == 9, "monitor did not decode all 9 characters written");
    check(TXD === 1'b1, "TXD is not back at MARK (1) after the last frame");
    check(!mon_busy, "monitor still inside a frame after TX went idle");
    $display("[result] %0d of %0d characters decoded on TXD", n_rx, n_expect);

    $display("\n--- TEST 4: BAUD_9600 = 1 selects the 9600 divisor (%0d clocks/bit) ---", D96);
    // Switched while TX is idle (a board switch, not a mid-frame change).
    // The monitor now expects D96-clock bits; a divisor that did not switch
    // (or went undefined) shows up as a glitch/wrong byte or as a timeout.
    baud_9600 = 1'b1;
    bt = D96;
    repeat (2) @(negedge sysclk);
    send(8'o132);   // 'Z'
    t_write = cyc;
    while (TXEMT_n == 1'b1) @(posedge sysclk);
    $display("[result] one char at 9600 took %0d clocks (frame = %0d)", cyc - t_write, 10*D96);
    check((cyc - t_write) >= 10*D96, "9600 char finished before a 10*D96 frame");
    check((cyc - t_write) <= 10*D96 + FLAG_SLACK, "9600 char took longer than a 10*D96 frame + FLAG_SLACK");
    repeat (4) @(negedge sysclk);
    check(n_rx == 10, "monitor did not decode the 9600-baud character");
    baud_9600 = 1'b0;

    $display("\nDONE");
    if (errors == 0) $display("TB_RESULT: PASS");
    else             $display("TB_RESULT: FAIL (%0d errors)", errors);
    $finish;
  end

  // safety timeout
  initial begin
    #2000000;
    $display("TIMEOUT -- a flag likely never asserted (TX stuck)");
    $display("TB_RESULT: FAIL (timeout, %0d errors before it)", errors);
    $finish;
  end

endmodule
