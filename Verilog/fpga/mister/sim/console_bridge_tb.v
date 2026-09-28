//============================================================================
//! MiSTer console UART bridge - end-to-end byte test (31-AUG-2026)
//!
//! Full path: Verilog/fpga/mister/sim/console_bridge_tb.v
//!
//! WHY: the MiSTer board reached neither an OPCOM '#' prompt nor keyboard
//! echo, while the SAME core in Verilog/sim reached both - including with
//! this board's exact 192 KB block-RAM memory. Everything inside the core is
//! therefore exonerated, and what is left is the board glue in nd120.sv. The
//! console bridge is the only path the prompt travels on this board and the
//! one piece never tested: nd120_console_mister_tb.v drives the byte seam
//! directly and never exercises a UART at all.
//!
//! The bridge is ASYMMETRIC and that is the risk this checks:
//!   CPU side      SC2661_UART on clk_cpu   = 20 MHz  (BOARD_CLK_FREQ)
//!   terminal side console_uart_rx/tx       = 40 MHz  (CLK_HZ, the pixel clock)
//! Both are meant to be 115200 8N1. If BOARD_CLK_FREQ does not reach
//! SC2661_UART, it falls back to its 100 MHz default and transmits at
//! 20e6/868 = 23 kbaud into a receiver expecting 115200 - which produces
//! EXACTLY "no prompt, no echo" while the rest of the board works.
//============================================================================

`timescale 1ns / 1ps

module console_bridge_tb;

  // 20 MHz CPU clock (50 ns period), 40 MHz pixel clock (25 ns period) -
  // the same two clocks nd120.sv generates.
  reg clk_cpu = 1'b0;
  reg clk_pix = 1'b0;
  always #25 clk_cpu = ~clk_cpu;
  always #12.5 clk_pix = ~clk_pix;

  reg rst_n = 1'b0;

  integer errors = 0;

  //--------------------------------------------------------------------------
  // CPU side: the real console UART out of the ND-120
  //--------------------------------------------------------------------------
  wire cpu_txd;
  reg  [7:0] cpu_wdata = 8'h00;
  reg        cpu_we_n  = 1'b1;
  reg        cpu_ce_n  = 1'b1;
  reg  [1:0] cpu_addr  = 2'b00;

  SC2661_UART CPU_UART (
      .sysclk   (clk_cpu),
      .sys_rst_n(rst_n),
      // Build-default baud (UART_BAUD_RATE), as nd120.sv wires it. Left
      // unconnected (the first version of this bench) the port floats to z,
      // so SC2661_UART's DELAY_FRAMES mux (BAUD_9600 ? 9600 : default) gives
      // x and no byte ever arrived (measured 28-SEP-2026: 3 TXD edges, all
      // four checks FAIL). A bench fault, not a board one.
      .BAUD_9600(1'b0),
      .ADDRESS  (cpu_addr),   // 00 = data register, 11 = command register
      .BRCLK    (1'b0),
      .CE_n     (cpu_ce_n),
      .CTS_n    (1'b0),
      .DCD_n    (1'b0),
      .DSR_n    (1'b0),
      .READ_n   (cpu_we_n),   // low = write
      .RESET    (~rst_n),
      .RXC_n    (1'b0),
      .RXD      (1'b1),
      .TXC_n    (1'b0),
      .D        (cpu_wdata),
      .D_OUT    (),
      .DTR_n    (),
      .RTS_n    (),
      .RXDRDY_n (),
      .TXD      (cpu_txd),
      .TXDRDY_n (),
      .TXEMT_n  ()
  );

  //--------------------------------------------------------------------------
  // Terminal side: exactly how nd120.sv instantiates it
  //--------------------------------------------------------------------------
  // 7 data bits + a parity bit that is read and dropped (7E1), as nd120.sv
  // has done since 02-SEP-2026: SINTRAN's boot text puts SOFTWARE parity in
  // bit 7, and the terminal drops every byte >= 7F. The SC2661 still sends
  // 8N1 - the receiver takes the eighth bit as the parity slot - so what
  // arrives is the byte with bit 7 cleared. (This bench was written 31-AUG
  // against the 8N1 receiver of that day.)
  wire       term_valid;
  wire [7:0] term_data;

  console_uart_rx #(
      .CLK_HZ   (40_000_000),
      .BAUD     (115_200),
      .DATA_BITS(7),
      .PARITY   (1'b1)
  ) CONSOLE_UART_RX (
      .clk        (clk_pix),
      .rst_n      (rst_n),
      .divisor_ovr(16'd0),
      .rxd        (cpu_txd),
      .byte_valid (term_valid),
      .byte_data  (term_data)
  );

  //--------------------------------------------------------------------------
  // Capture whatever the terminal side receives
  //--------------------------------------------------------------------------
  // Does the CPU's TXD line move at all? This separates "the UART never
  // transmitted" from "it transmitted and the receiver could not decode it".
  integer txd_edges = 0;
  reg     txd_prev  = 1'b1;
  always @(posedge clk_pix) begin
    if (cpu_txd !== txd_prev) txd_edges = txd_edges + 1;
    txd_prev <= cpu_txd;
  end

  reg [7:0] got      = 8'h00;
  reg       got_any  = 1'b0;
  always @(posedge clk_pix) begin
    if (term_valid) begin
      got     <= term_data;
      got_any <= 1'b1;
    end
  end

  // Write one of the SC2661's registers. The chip latches on CE_n low with
  // READ_n low, and regCommandExecuted gates a repeat, so the strobe has to
  // go away again between writes.
  task cpu_write(input [1:0] addr, input [7:0] val);
    begin
      @(posedge clk_cpu);
      cpu_addr  = addr;
      cpu_wdata = val;
      cpu_ce_n  = 1'b0;
      // READ_n HIGH is a WRITE here: SC2661_UART.v:262 gates the transmit
      // holding register on `s_thr_write = !s_ce_n & !regCommandExecuted &
      // s_read_n & (s_address == 2'b00)`, i.e. s_read_n must be 1.
      cpu_we_n  = 1'b1;
      @(posedge clk_cpu);
      @(posedge clk_cpu);
      cpu_ce_n = 1'b1;
      @(posedge clk_cpu);
    end
  endtask

  // Address 3 is the command register: bit 0 = transmit enable, bit 2 =
  // receive enable. On the real machine the microcode does this; without it
  // cmd_txEnabled stays 0 and the chip never transmits at all.
  task cpu_enable_uart;
    begin
      cpu_write(2'b11, 8'h05);   // TxEN | RxEN
    end
  endtask

  // Write one byte into the transmit holding register.
  task cpu_send(input [7:0] ch);
    begin
      cpu_write(2'b00, ch);
    end
  endtask

  integer passed = 0;

  // The 7E1 receiver hands over bit 7 cleared, so that is what must arrive.
  task expect_byte(input [7:0] ch, input [127:0] name);
    begin
      got_any = 1'b0;
      cpu_send(ch);
      // One 8N1 frame at 115200 is ~87 us. Allow generous margin.
      repeat (40000) @(posedge clk_pix);
      if (!got_any) begin
        $display("FAIL: %0s (%02x) - terminal received NOTHING (TXD edges seen: %0d)", name, ch,
                 txd_edges);
        errors = errors + 1;
      end else if (got !== {1'b0, ch[6:0]}) begin
        $display("FAIL: %0s - sent %02x, terminal got %02x, expected %02x", name, ch, got,
                 {1'b0, ch[6:0]});
        errors = errors + 1;
      end else begin
        $display("  ok: %0s - sent %02x, %02x arrived", name, ch, got);
        passed = passed + 1;
      end
    end
  endtask

  initial begin
    $dumpfile("console_bridge_tb.vcd");
    $dumpvars(1, console_bridge_tb);

    repeat (20) @(posedge clk_cpu);
    rst_n = 1'b1;
    repeat (200) @(posedge clk_cpu);

    $display("--- MiSTer console bridge: CPU SC2661 @20MHz -> console_uart_rx @40MHz ---");

    cpu_enable_uart;
    repeat (50) @(posedge clk_cpu);

    // '#' is the OPCOM prompt - the exact byte the board never showed.
    expect_byte(8'h23, "OPCOM prompt '#'");
    expect_byte(8'h41, "letter 'A'");
    expect_byte(8'h0D, "carriage return");
    expect_byte(8'h55, "0x55 alternating");
    // CR as SINTRAN's boot text sends it: software parity in bit 7 (8D, as
    // captured on the board's serial line 02-SEP-2026) - must arrive as 0D.
    expect_byte(8'h8D, "CR + parity bit");

    if (errors == 0 && passed == 5) $display("TB_RESULT: PASS (console bridge carries bytes intact)");
    else $display("TB_RESULT: FAIL (%0d errors)", errors);

    $finish;
  end

endmodule
