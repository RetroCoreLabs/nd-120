/**************************************************************************
** ND120 Shared                                                          **
** SC2661 UART - receive-register overrun regression                    **
**                                                                       **
** 31-AUG-2026. regReceiveHoldingRegister used to be both the live       **
** shift-in register AND the CPU-visible holding register. A new start   **
** bit cleared it immediately, then shifted the incoming byte in live -  **
** a CPU read landing mid-shift got a torn value matching neither the    **
** old nor the new byte. Measured on real hardware: "PED\r" sent with no **
** inter-character gap landed at the ND-120 as a single byte 0x28 '(' -  **
** not P, E, D or CR. Fixed by adding a separate regRxShift register and **
** only transferring a complete byte atomically at end-of-frame.         **
**                                                                       **
** Same day, second measurement: even with that fix, a real TDV2200      **
** escape sequence (up to 6 bytes, zero inter-byte gap - key_tdv2200.v)  **
** at 115200 baud outran SINTRAN's interrupt handler with only ONE       **
** holding register - Alt+H (meant to send ESC[46_) landed as just "6_", **
** each earlier byte overwritten before the CPU's read reached it. Fixed **
** by adding a 16-byte RX FIFO between the receiver and the CPU-visible  **
** read port (see SC2661_UART.v's s_rx_fifo declaration) - register-     **
** level behavior is unchanged, only WHEN Overrun fires moves from       **
** "past 1 unread byte" to "past 16".                                    **
**                                                                       **
** Uses local loopback (TXD internally wired to RXD) to drive real       **
** back-to-back receive frames with zero gap, same as the failures.      **
**                                                                       **
** TEST 1: one character, read before the next one starts - must read    **
**         back exactly what was sent, no overrun flagged.               **
** TEST 2: two characters back-to-back, held WITHOUT reading the first - **
**         the FIFO must preserve BOTH, in order (B then D), no Overrun. **
** TEST 3: read RHR repeatedly WHILE the second byte is still shifting   **
**         in (the actual mid-shift failure mode). Every value seen      **
**         while RXRDY is set must be a whole byte from the stream,      **
**         never torn - the FIFO must never expose a partial value.      **
** TEST 4: 16 characters back-to-back, no reads until all 16 have        **
**         landed - every one must come back in order, no Overrun (the   **
**         FIFO is exactly full, not over).                              **
** TEST 5: 17 characters back-to-back, no reads - Overrun must be set,   **
**         and the FIRST 16 must still be readable in order (byte 17 is  **
**         the one dropped - "drop the newest when full" is the policy,  **
**         opposite of the old single-register "keep the newest").       **
**                                                                       **
** Verdict: TB_RESULT: PASS / TB_RESULT: FAIL (run_all_tests.sh entry     **
** test-uart-rxoverrun).                                                 **
***************************************************************************/
`timescale 1ns / 1ps

module SC2661_RX_OVERRUN_tb;

  reg sysclk = 0;
  reg sys_rst_n = 0;
  reg [1:0] address = 2'b00;
  reg reset = 0;
  reg ce_n = 1;
  reg read_n = 1;      // 1 = write access when chip enabled
  reg [7:0] d_in = 8'h00;

  wire [7:0] d_out;
  wire rxdrdy_n, txdrdy_n, txemt_n;

  integer errors = 0;

  // No defines -> DELAY_FRAMES = 100e6/115200 = 868 clocks/bit (see other UART tbs).
  localparam integer BITCLKS = 868;
  localparam integer FRAMECLKS = 10 * BITCLKS; // start + 8 data + stop

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
      .RXD(1'b1),   // unused: local loopback feeds TXD -> receiver internally
      .RXDRDY_n(rxdrdy_n),
      .TXC_n(1'b0),
      .TXD(),
      .TXDRDY_n(txdrdy_n),
      .TXEMT_n(txemt_n)
  );

  always #5 sysclk = ~sysclk;

  task uart_write(input [1:0] a, input [7:0] v);
    begin
      @(negedge sysclk);
      address = a; d_in = v; read_n = 1; ce_n = 0;
      @(negedge sysclk);
      ce_n = 1;
      @(negedge sysclk);
    end
  endtask

  task uart_read(input [1:0] a, output [7:0] v);
    begin
      @(negedge sysclk);
      address = a; read_n = 0; ce_n = 0;
      @(negedge sysclk);
      v = d_out;
      ce_n = 1;
      read_n = 1;
      @(negedge sysclk);
    end
  endtask

  reg [7:0] rhr;
  reg [7:0] status;

  initial begin
    // reset
    repeat (4) @(negedge sysclk);
    sys_rst_n = 1;
    repeat (4) @(negedge sysclk);

    // Command register: TxEN=bit0, RxEN=bit2, OperatingMode=bits7:6=10 (Local Loopback)
    uart_write(2'b11, 8'b1000_0101);
    repeat (8) @(negedge sysclk);

    // ---- TEST 1: single char, read before the next one starts
    uart_write(2'b00, 8'h41); // THR = 'A'
    // one full TX frame + one full RX frame to land in RHR, plus margin
    repeat (2 * FRAMECLKS + 4 * BITCLKS) @(posedge sysclk);

    uart_read(2'b01, status);
    if (status[1] !== 1'b1) begin
      $display("TEST1 FAIL: RXRDY not set after one character (status=%02x)", status);
      errors = errors + 1;
    end else begin
      uart_read(2'b00, rhr);
      if (rhr === 8'h41 && status[4] === 1'b0) begin
        $display("TEST1 PASS: single char round-tripped clean (got=%02x, overrun=%0d)", rhr, status[4]);
      end else begin
        $display("TEST1 FAIL: got=%02x overrun=%0d (expected 41, 0)", rhr, status[4]);
        errors = errors + 1;
      end
    end

    repeat (4 * BITCLKS) @(posedge sysclk);

    // ---- TEST 2: two chars back-to-back, RHR never read until both are
    // fully done. Queue 'B' then 'D' one right after the other via THR,
    // polling TxRDY (status bit0) so the second write lands the instant
    // the transmitter accepts it - reproducing the zero-gap "PED\r" burst.
    // With the FIFO, both must survive in order - no overrun for a burst
    // this small (16 deep).
    uart_write(2'b00, 8'h42); // THR = 'B'
    // wait for TxRDY (THR empty again, i.e. shifted into the tx shift reg)
    status = 8'h00;
    while (status[0] !== 1'b1) begin
      uart_read(2'b01, status);
    end
    uart_write(2'b00, 8'h44); // THR = 'D', queued back-to-back with no gap

    // let both frames fully transmit and receive, no reads in between
    repeat (3 * FRAMECLKS + 4 * BITCLKS) @(posedge sysclk);

    begin : t2v
      integer t2_before;
      t2_before = errors;

      uart_read(2'b01, status);
      if (status[4] !== 1'b0) begin
        $display("TEST2 FAIL: Overrun set for a 2-byte burst into a 16-deep FIFO (status=%02x)", status);
        errors = errors + 1;
      end
      uart_read(2'b00, rhr);
      if (rhr !== 8'h42) begin
        $display("TEST2 FAIL: first read got %02x, expected 42 ('B', FIFO order)", rhr);
        errors = errors + 1;
      end
      uart_read(2'b00, rhr);
      if (rhr !== 8'h44) begin
        $display("TEST2 FAIL: second read got %02x, expected 44 ('D', FIFO order)", rhr);
        errors = errors + 1;
      end
      if (errors == t2_before)
        $display("TEST2 PASS: both bytes (42, 44) preserved in order, no Overrun");
    end

    repeat (4 * BITCLKS) @(posedge sysclk);

    // ---- TEST 3: a FRESH byte pair ('X' then 'Y'), this time polling RHR
    // repeatedly WHILE the second byte is still shifting in - the actual
    // failure mode measured on hardware: a CPU read landing mid-frame.
    // The pre-fix RTL cleared regReceiveHoldingRegister the instant the
    // new start bit arrived, then shifted bits into that SAME CPU-visible
    // register live, so a read mid-shift saw neither the old nor the new
    // byte. Every read here that finds RXRDY set (which itself clears it,
    // same as real CPU polling, only when the FIFO drains to empty) must
    // return a whole byte, never a torn value. A read landing while the
    // FIFO is genuinely empty is skipped - the FIFO's held-back queue
    // slots are stale between tests, not the mid-shift failure this test
    // is checking for.
    uart_write(2'b00, 8'h58); // THR = 'X'
    status = 8'h00;
    while (status[0] !== 1'b1) begin
      uart_read(2'b01, status);
    end
    uart_write(2'b00, 8'h59); // THR = 'Y', queued back-to-back with no gap

    begin : t3
      integer i;
      integer t3_before;
      reg [7:0] v;
      t3_before = errors;
      // second RX frame starts roughly one TX-frame-time after the first
      // THR write; sample across a window spanning its start bit through
      // its data bits.
      repeat (FRAMECLKS - 4 * BITCLKS) @(posedge sysclk);
      for (i = 0; i < 12; i = i + 1) begin
        uart_read(2'b01, status);
        if (status[1] === 1'b1) begin
          uart_read(2'b00, v);
          if (v !== 8'h58 && v !== 8'h59) begin
            $display("TEST3 FAIL: mid-shift read got a torn value %02x (neither 58 nor 59)", v);
            errors = errors + 1;
          end
        end
        repeat (BITCLKS) @(posedge sysclk);
      end
      if (errors == t3_before)
        $display("TEST3 PASS: every mid-shift read was a whole byte (58 or 59), never torn");
    end

    // let the second frame finish fully
    repeat (2 * FRAMECLKS) @(posedge sysclk);

    // drain TEST3's leftover bytes so TEST4 starts from an empty FIFO
    uart_read(2'b01, status);
    while (status[1] === 1'b1) begin
      uart_read(2'b00, rhr);
      uart_read(2'b01, status);
    end

    // ---- TEST 4: exactly 16 characters back-to-back, no reads until all
    // 16 have landed - the FIFO is exactly full, not over, so every byte
    // must come back in order and Overrun must NOT be set.
    begin : t4
      integer i;
      integer t4_before;
      reg [7:0] v;
      t4_before = errors;
      for (i = 0; i < 16; i = i + 1) begin
        status = 8'h00;
        while (status[0] !== 1'b1) uart_read(2'b01, status);
        uart_write(2'b00, 8'h60 + i[7:0]); // '`'..'o', 16 distinct bytes
      end
      // let the last frame fully receive
      repeat (2 * FRAMECLKS) @(posedge sysclk);

      uart_read(2'b01, status);
      if (status[4] !== 1'b0) begin
        $display("TEST4 FAIL: Overrun set for an exactly-16-byte burst (status=%02x)", status);
        errors = errors + 1;
      end
      for (i = 0; i < 16; i = i + 1) begin
        uart_read(2'b00, v);
        if (v !== 8'h60 + i[7:0]) begin
          $display("TEST4 FAIL: byte %0d got %02x, expected %02x", i, v, 8'h60 + i[7:0]);
          errors = errors + 1;
        end
      end
      if (errors == t4_before)
        $display("TEST4 PASS: all 16 bytes preserved in order, no Overrun");
    end

    repeat (4 * BITCLKS) @(posedge sysclk);

    // ---- TEST 5: 17 characters back-to-back, no reads - one past the FIFO
    // depth. Overrun must be set, and the FIRST 16 must still be readable
    // in order - byte 17 is the one dropped (drop-newest-when-full, the
    // deliberate opposite of the old single-register keep-newest policy).
    begin : t5
      integer i;
      integer t5_before;
      reg [7:0] v;
      t5_before = errors;
      for (i = 0; i < 17; i = i + 1) begin
        status = 8'h00;
        while (status[0] !== 1'b1) uart_read(2'b01, status);
        uart_write(2'b00, 8'h70 + i[7:0]); // 'p'.., 17 distinct bytes
      end
      repeat (2 * FRAMECLKS) @(posedge sysclk);

      uart_read(2'b01, status);
      if (status[4] !== 1'b1) begin
        $display("TEST5 FAIL: Overrun NOT set for a 17-byte burst into a 16-deep FIFO (status=%02x)", status);
        errors = errors + 1;
      end
      for (i = 0; i < 16; i = i + 1) begin
        uart_read(2'b00, v);
        if (v !== 8'h70 + i[7:0]) begin
          $display("TEST5 FAIL: byte %0d got %02x, expected %02x (the first 16 must survive)", i, v, 8'h70 + i[7:0]);
          errors = errors + 1;
        end
      end
      if (errors == t5_before)
        $display("TEST5 PASS: Overrun set, first 16 of 17 bytes preserved in order");
    end

    if (errors == 0) $display("TB_RESULT: PASS");
    else $display("TB_RESULT: FAIL (%0d errors)", errors);
    $finish;
  end

endmodule
