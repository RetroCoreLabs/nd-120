/**************************************************************************
** IO_UART_42 - UART and IOR status register testbench                   **
** (sheet 42, chips 33G AM29C821 + 32H SC2661/68661 EPCI)                **
**                                                                       **
** Two things live on this sheet and both put bits on the same IDB:      **
** the console UART, and the 10-bit IOR status snapshot the microcode    **
** reads to find out the baud switch setting and the terminal state.     **
**                                                                       **
** WHAT THIS WOULD CATCH                                                 **
**   1. THE IOR STATUS BIT MAP. The AM29C821 is wired with its D and Y   **
**      vectors SPLIT across two non-adjacent IDB fields:                **
**          D = {TBMT~, DA~, EAUTO~, LOCK~, CONSOLE~, 1, BAUD[3:0]}      **
**          Y = { IDB[15:11]          ,        IDB[4:0]          }       **
**      so a single misplaced element silently moves a status flag into  **
**      the baud field or vice versa. The test walks each driveable      **
**      input on its own and asserts it appears at ONE named IDB bit and **
**      moves nothing else - the check that would have caught the        **
**      CGA_INTR_CNTLR bit-1/bit-2 swap.                                 **
**   2. IDB[10:5] MUST BE HARD ZERO on this sheet (the RTL ties them),   **
**      and IDB4 must be the constant 1. Both are asserted across the    **
**      whole sweep, so a stray connection into that hole is caught.     **
**   3. THE OUTPUT ENABLE. With EIOR~ high the 29C821 must contribute    **
**      EXACTLY ZERO - this IDB is OR-ed, not tri-stated.                **
**   4. THE CAPTURE IS A REGISTER, NOT A WIRE: the status word must not  **
**      follow the inputs while the capture clock is inactive.           **
**   5. THE UART ITSELF: one byte out (the TXD frame is decoded bit by   **
**      bit and compared) and one byte in (a driven RXD frame must raise **
**      DA~ and be readable back on IDB[7:0]). This proves ADDRESS,      **
**      CE~ and READ~ are wired to MIS/CEUART~/RUART~ the right way      **
**      round - RUART~ HIGH is a WRITE on this chip, an easy inversion   **
**      to get wrong.                                                    **
**   6. THE UART READ PATH IS GATED: with CEUART~ high the UART must     **
**      contribute zero to the IDB.                                      **
**                                                                       **
** BOTH BUILD MODES: chip 33G takes its capture clock from CLK in the    **
** default build and from the CLK_EN pulse under `FPGA_FF_MODE. The      **
** stimulus drives both, and every assertion above must hold either way. **
**                                                                       **
** The IOR bit map is a SPECIFICATION test (the port wiring in the RTL   **
** is the spec). The UART frame timing is CHARACTERISED against the      **
** SC2661_UART model as built, not against the real 68661 datasheet.     **
**                                                                       **
** Run: cd Verilog/CPU-BOARD-3202/sim && make test-iouart42              **
**                                                                       **
** Last reviewed: 20-AUG-2026                                            **
** Ronny Hansen                                                          **
***************************************************************************/
`timescale 1ns / 1ps
`default_nettype none

module IO_UART_42_tb;

  reg         sysclk = 1'b0;
  reg         sys_rst_n = 1'b0;
  reg         CEUART_n, CLK, CLK_EN, CONSOLE_n, EAUTO_n, EIOR_n, LCS_n, LOCK_n;
  reg  [1:0]  MIS_1_0;
  reg         PPOSC = 1'b0;
  reg         RUART_n, XTR;
  reg         RXD;
  reg  [3:0]  BAUD_RATE_SWITCH;
  reg  [7:0]  IDB_7_0_IN;
  wire        TXD;
  wire [15:0] IDB_15_0_OUT;
  wire        DA_n, TBMT_n;

  integer errors = 0;
  integer checks = 0;
  integer i, v;
  reg [15:0] snap, snap2;
  reg [7:0]  rxbyte;

  // 868 sysclk per bit is what SC2661_UART.v computes from its default
  // 100 MHz / 115200 with no BOARD_CLK_FREQ override - read from the model,
  // not assumed.
  localparam integer BIT_CYCLES = 100000000 / 115200;

  always #5 sysclk = ~sysclk;

`ifdef FPGA_FF_MODE
  localparam [8*5:1] MODE = "FF   ";
`else
  localparam [8*5:1] MODE = "LATCH";
`endif

  IO_UART_42 DUT (
      .sysclk(sysclk), .sys_rst_n(sys_rst_n),
      .BAUD_9600(1'b0),   // build-default divisor; an open input is z, not 0
      .CEUART_n(CEUART_n), .CLK(CLK), .CLK_EN(CLK_EN), .CONSOLE_n(CONSOLE_n),
      .EAUTO_n(EAUTO_n), .EIOR_n(EIOR_n), .LCS_n(LCS_n), .LOCK_n(LOCK_n),
      .MIS_1_0(MIS_1_0), .PPOSC(PPOSC), .RUART_n(RUART_n), .XTR(XTR),
      .RXD(RXD), .TXD(TXD), .BAUD_RATE_SWITCH(BAUD_RATE_SWITCH),
      .IDB_7_0_IN(IDB_7_0_IN), .IDB_15_0_OUT(IDB_15_0_OUT),
      .DA_n(DA_n), .TBMT_n(TBMT_n)
  );

  // Take a status snapshot into chip 33G. In the default build the capture
  // clock is CLK (level, sampled by sysclk); in FF mode it is the CLK_EN
  // one-sysclk pulse. Drive both so the same task works in both modes.
  task capture_status;
    begin
      CLK = 1'b1; CLK_EN = 1'b1;
      @(posedge sysclk); #1;
      CLK = 1'b0; CLK_EN = 1'b0;
      @(posedge sysclk); #1;
    end
  endtask

  // one CE~ pulse, RUART~ high = write to the UART register at MIS
  task uart_wr;
    input [1:0] a;
    input [7:0] d;
    begin
      @(negedge sysclk); MIS_1_0 = a; IDB_7_0_IN = d; RUART_n = 1'b1; CEUART_n = 1'b0;
      @(negedge sysclk); CEUART_n = 1'b1;
      @(negedge sysclk); @(negedge sysclk);
    end
  endtask

  // one CE~ pulse, RUART~ low = read; the byte appears on IDB[7:0]
  task uart_rd;
    input  [1:0] a;
    output [7:0] q;
    begin
      @(negedge sysclk); MIS_1_0 = a; RUART_n = 1'b0; CEUART_n = 1'b0;
      @(negedge sysclk); q = IDB_15_0_OUT[7:0]; CEUART_n = 1'b1; RUART_n = 1'b1;
      @(negedge sysclk); @(negedge sysclk);
    end
  endtask

  task expect1;
    input [255:0] name;
    input got, want;
    begin
      checks = checks + 1;
      if (got !== want) begin
        errors = errors + 1;
        if (errors < 25) $display("FAIL %0s: got %b want %b", name, got, want);
      end
    end
  endtask

  initial begin
    $dumpfile("IO_UART_42_tb.vcd");
    $dumpvars(0, IO_UART_42_tb);
    // Keep the committed waveform SHORT and readable: this testbench
    // runs far more stimulus than anyone wants to open in GTKWave, so
    // only the opening 60000 ns is recorded. The pass/fail verdict comes
    // from the text output, never from the waveform.
    #60000 $dumpoff;
  end

  initial begin
    $display("=====================================================");
    $display(" IO_UART_42 (sheet 42) - mode %0s, %0d sysclk per bit",
             MODE, BIT_CYCLES);
    $display("=====================================================");

    CEUART_n = 1'b1; CLK = 1'b0; CLK_EN = 1'b0; CONSOLE_n = 1'b1;
    EAUTO_n = 1'b1; EIOR_n = 1'b1; LCS_n = 1'b0; LOCK_n = 1'b1;
    MIS_1_0 = 2'b00; RUART_n = 1'b1; XTR = 1'b0; RXD = 1'b1;
    BAUD_RATE_SWITCH = 4'b0000; IDB_7_0_IN = 8'h00;

    repeat (5) @(posedge sysclk);
    sys_rst_n = 1'b1;
    LCS_n = 1'b1;                // release the UART reset (RESET = !LCS_n)
    repeat (5) @(posedge sysclk); #1;

    // =================================================================
    // 1. the IOR status word - every driveable input, one at a time
    // =================================================================
    EIOR_n = 1'b0;

    // baseline: everything inactive high, baud 0
    CONSOLE_n = 1'b1; EAUTO_n = 1'b1; LOCK_n = 1'b1; BAUD_RATE_SWITCH = 4'h0;
    capture_status;
    snap = IDB_15_0_OUT;

    // IDB13 <- EAUTO~
    EAUTO_n = 1'b0; capture_status;
    checks = checks + 1;
    if ((snap ^ IDB_15_0_OUT) !== 16'h2000) begin
      errors = errors + 1;
      $display("FAIL EAUTO_BIT: expected only IDB13 to move, moved %04h",
               snap ^ IDB_15_0_OUT);
    end
    EAUTO_n = 1'b1; capture_status;

    // IDB12 <- LOCK~
    LOCK_n = 1'b0; capture_status;
    checks = checks + 1;
    if ((snap ^ IDB_15_0_OUT) !== 16'h1000) begin
      errors = errors + 1;
      $display("FAIL LOCK_BIT: expected only IDB12 to move, moved %04h",
               snap ^ IDB_15_0_OUT);
    end
    LOCK_n = 1'b1; capture_status;

    // IDB11 <- CONSOLE~
    CONSOLE_n = 1'b0; capture_status;
    checks = checks + 1;
    if ((snap ^ IDB_15_0_OUT) !== 16'h0800) begin
      errors = errors + 1;
      $display("FAIL CONSOLE_BIT: expected only IDB11 to move, moved %04h",
               snap ^ IDB_15_0_OUT);
    end
    CONSOLE_n = 1'b1; capture_status;

    // IDB[3:0] <- BAUD_RATE_SWITCH, one-hot, and nothing else moves
    for (i = 0; i < 4; i = i + 1) begin
      BAUD_RATE_SWITCH = 4'b1 << i;
      capture_status;
      checks = checks + 1;
      if ((snap ^ IDB_15_0_OUT) !== (16'b1 << i)) begin
        errors = errors + 1;
        $display("FAIL BAUD_BIT_%0d: expected only IDB%0d to move, moved %04h",
                 i, i, snap ^ IDB_15_0_OUT);
      end
    end
    BAUD_RATE_SWITCH = 4'h0;

    // full sweep of the 7 driveable status bits: the whole word must match
    // the wiring, IDB[10:5] must be zero, IDB4 must be 1, and IDB15/IDB14
    // must track the UART's own live TBMT~/DA~ (idle, so stable).
    for (v = 0; v < 128; v = v + 1) begin
      {EAUTO_n, LOCK_n, CONSOLE_n, BAUD_RATE_SWITCH} = v[6:0];
      capture_status;
      checks = checks + 1;
      if (IDB_15_0_OUT !== {TBMT_n, DA_n, EAUTO_n, LOCK_n, CONSOLE_n,
                            6'b000000, 1'b1, BAUD_RATE_SWITCH}) begin
        errors = errors + 1;
        if (errors < 25)
          $display("FAIL IOR_WORD: got %04h want %04h", IDB_15_0_OUT,
                   {TBMT_n, DA_n, EAUTO_n, LOCK_n, CONSOLE_n,
                    6'b000000, 1'b1, BAUD_RATE_SWITCH});
      end
      checks = checks + 2;
      if (IDB_15_0_OUT[10:5] !== 6'b000000) begin
        errors = errors + 1;
        $display("FAIL IDB_10_5_NOT_ZERO: %b", IDB_15_0_OUT[10:5]);
      end
      if (IDB_15_0_OUT[4] !== 1'b1) begin
        errors = errors + 1;
        $display("FAIL IDB4_NOT_ONE: %b", IDB_15_0_OUT[4]);
      end
    end

    // =================================================================
    // 2. the output enable, and the register-not-a-wire property
    // =================================================================
    EAUTO_n = 1'b0; LOCK_n = 1'b0; CONSOLE_n = 1'b0; BAUD_RATE_SWITCH = 4'hF;
    capture_status;
    snap = IDB_15_0_OUT;
    EIOR_n = 1'b1;
    #1;
    checks = checks + 1;
    if (IDB_15_0_OUT !== 16'h0000) begin
      errors = errors + 1;
      $display("FAIL EIOR_DISABLED_NOT_ZERO: IDB=%04h", IDB_15_0_OUT);
    end
    EIOR_n = 1'b0; #1;
    checks = checks + 1;
    if (IDB_15_0_OUT !== snap) begin
      errors = errors + 1;
      $display("FAIL LOST_WHILE_DISABLED: %04h -> %04h", snap, IDB_15_0_OUT);
    end

    // change the inputs WITHOUT a capture: the published word must not move
    EAUTO_n = 1'b1; LOCK_n = 1'b1; CONSOLE_n = 1'b1; BAUD_RATE_SWITCH = 4'h0;
    repeat (4) @(posedge sysclk); #1;
    checks = checks + 1;
    if (IDB_15_0_OUT !== snap) begin
      errors = errors + 1;
      $display("FAIL NOT_REGISTERED: status word followed its inputs, %04h -> %04h",
               snap, IDB_15_0_OUT);
    end
    EIOR_n = 1'b1;

    // =================================================================
    // 3. the UART - one byte out, decoded off TXD
    // =================================================================
    uart_wr(2'b10, 8'h4E);   // mode register 1
    uart_wr(2'b10, 8'h37);   // mode register 2
    uart_wr(2'b11, 8'h05);   // command: TxEN + RxEN

    checks = checks + 1;
    if (TXD !== 1'b1) begin
      errors = errors + 1;
      $display("FAIL TXD_IDLE: TXD=%b, an idle line must be high", TXD);
    end

    uart_wr(2'b00, 8'h5A);   // transmit 'Z'
    decode_txd(8'h5A);

    // =================================================================
    // 4. the UART - one byte in, driven onto RXD, read back on the IDB
    // =================================================================
    send_rxd(8'hC3);
    // wait for the receiver to post it
    for (i = 0; i < 20 * BIT_CYCLES; i = i + 1) begin
      @(posedge sysclk);
      if (DA_n === 1'b0) i = 20 * BIT_CYCLES;
    end
    checks = checks + 1;
    if (DA_n !== 1'b0) begin
      errors = errors + 1;
      $display("FAIL RX_NO_DATA_AVAILABLE: DA_n stayed high after a full frame");
    end
    uart_rd(2'b00, rxbyte);
    checks = checks + 1;
    if (rxbyte !== 8'hC3) begin
      errors = errors + 1;
      $display("FAIL RX_BYTE: read %02h expected C3", rxbyte);
    end

    // =================================================================
    // 5. with CE~ high the UART must contribute exactly zero to the IDB
    // =================================================================
    CEUART_n = 1'b1; RUART_n = 1'b1; EIOR_n = 1'b1;
    repeat (3) @(posedge sysclk); #1;
    checks = checks + 1;
    if (IDB_15_0_OUT !== 16'h0000) begin
      errors = errors + 1;
      $display("FAIL UART_DESELECTED_NOT_ZERO: IDB=%04h", IDB_15_0_OUT);
    end

    $display("-----------------------------------------------------");
    $display(" mode       : %0s", MODE);
    $display(" checks run : %0d", checks);
    $display(" failures   : %0d", errors);
    if (errors == 0) $display("TB_RESULT: PASS");
    else             $display("TB_RESULT: FAIL");
    $display("=====================================================");
    $finish;
  end

  // wait for the start bit, then sample the middle of each of the 8 data
  // bits and the stop bit
  task decode_txd;
    input [7:0] want;
    integer b, guard;
    reg [7:0] got;
    begin
      guard = 0;
      while (TXD === 1'b1 && guard < 40 * BIT_CYCLES) begin
        @(posedge sysclk);
        guard = guard + 1;
      end
      checks = checks + 1;
      if (TXD !== 1'b0) begin
        errors = errors + 1;
        $display("FAIL TX_NO_START_BIT: TXD never went low");
      end else begin
        repeat (BIT_CYCLES + (BIT_CYCLES / 2)) @(posedge sysclk);
        for (b = 0; b < 8; b = b + 1) begin
          got[b] = TXD;
          repeat (BIT_CYCLES) @(posedge sysclk);
        end
        checks = checks + 2;
        if (got !== want) begin
          errors = errors + 1;
          $display("FAIL TX_BYTE: TXD carried %02h, expected %02h", got, want);
        end
        if (TXD !== 1'b1) begin
          errors = errors + 1;
          $display("FAIL TX_NO_STOP_BIT: TXD=%b at the stop bit position", TXD);
        end
      end
    end
  endtask

  // drive one 8N1 frame onto RXD
  task send_rxd;
    input [7:0] d;
    integer b;
    begin
      RXD = 1'b0;
      repeat (BIT_CYCLES) @(posedge sysclk);
      for (b = 0; b < 8; b = b + 1) begin
        RXD = d[b];
        repeat (BIT_CYCLES) @(posedge sysclk);
      end
      RXD = 1'b1;
      repeat (2 * BIT_CYCLES) @(posedge sysclk);
    end
  endtask

endmodule

`default_nettype wire
