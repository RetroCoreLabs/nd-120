/****************************************************************************
** Tang Nano 20K - sdram18.v hardware validation test                      **
**                                                                         **
** Drives the ND-120 18-bit-word SDRAM controller                          **
** (../sdram-bridge/sdram18.v) EXACTLY as the full ND-120 build does:      **
** same PLL (Gowin_rPLL_ND120 with TANG_SLOW_BRINGUP -> 13.5 MHz clk +     **
** 13.5 MHz shifted chip clock), same FREQ parameter, same one-word        **
** rd/wr/refresh handshake. The original sdram-test validated the 32-bit   **
** byte-based sdram.v at 27 MHz; THIS test validates the 18-bit adaptation **
** at the slow-bring-up frequency - the exact configuration the deposit    **
** bug was localized to (fixed 10-JUL-2026, see                            **
** docs/plan-fix-unconstrained-clocks.md).                                 **
**                                                                         **
** Test sequence (started by S1 or any UART character, 9600 8N1):          **
**   1. Verbose demo: 4 words at spread WORD addresses (col[9:8] bits      **
**      exercised, bank bit, last word), written then read back, each op   **
**      printed as "W aaaaaa=ddddd" / "R aaaaaa=ddddd OK|ERR" (hex,        **
**      6-digit word address, 5-digit 18-bit data).                        **
**   2. Block test: write ALL 2M words with an address-derived 18-bit      **
**      pattern (parity bits included), read back and verify.              **
**      Progress dot every 64K words. Ends with PASS or FAIL.              **
**                                                                         **
** Last reviewed: 9-JUL-2026                                               **
** Ronny Hansen                                                            **
*****************************************************************************/

module sdram18_test_top #(
    parameter CLK_FREQ   = 13_500_000,  // PLL clkout in slow-bring-up mode
    parameter BAUD       = 9600,
    parameter BLOCK_SIZE = 22'h200000,  // block test size in WORDS (all 2M), power of 2
    parameter DOT_STEP   = 22'h010000   // progress dot interval (64K words -> 32 dots)
) (
    input sys_clk,   // 27 MHz crystal
    input s1,        // S1 push button (pin 88) - start / restart
    input uart_rxp,  // from BL616 USB serial
    output uart_txp, // to BL616 USB serial

    // "Magic" port names - the Gowin toolchain connects these to the
    // on-package SDRAM die. For the OSS flow the same names are pinned
    // explicitly in ../sdram-test/src/sdram_pins_oss.cst.
    output        O_sdram_clk,
    output        O_sdram_cke,
    output        O_sdram_cs_n,
    output        O_sdram_cas_n,
    output        O_sdram_ras_n,
    output        O_sdram_wen_n,
    inout  [31:0] IO_sdram_dq,
    output [10:0] O_sdram_addr,
    output [ 1:0] O_sdram_ba,
    output [ 3:0] O_sdram_dqm,

    output [5:0] led  // active low: {error, pass, state[3:0]}
);

  localparam DELAY_FRAMES = CLK_FREQ / BAUD;

  /*******************************************************************************
   ** Clocking: the FULL BUILD's PLL, slow-bring-up mode (build defines          **
   ** TANG_SLOW_BRINGUP): clkout = 13.5 MHz, clkoutp = 13.5 MHz shifted          **
   *******************************************************************************/
  wire clk, clk_sdram, pll_lock;

`ifdef SIM
  // Simulation: no rPLL primitive; a plain inverted clock is exactly 180 degrees
  assign clk       = sys_clk;
  assign clk_sdram = ~sys_clk;
  assign pll_lock  = 1'b1;
`else
  wire unused_clkoutd;
  Gowin_rPLL_ND120 pll (
      .clkout (clk),             // 13.5 MHz controller clock
      .clkoutp(clk_sdram),       // 13.5 MHz shifted chip clock
      .clkoutd(unused_clkoutd),  // 6.75 MHz (CPU domain in the full build; unused)
      .lock   (pll_lock),
      .clkin  (sys_clk)
  );
`endif

  // Power-on reset: hold everything ~1k cycles after PLL lock
  reg [10:0] rst_cnt = 0;
  reg rst_n = 0;
  always @(posedge clk) begin
    if (!pll_lock) begin
      rst_cnt <= 0;
      rst_n   <= 0;
    end else if (!rst_cnt[10]) begin
      rst_cnt <= rst_cnt + 1;
      rst_n   <= 0;
    end else begin
      rst_n <= 1;
    end
  end

  /*******************************************************************************
   ** Start events: S1 button (synchronized) or any received UART byte          **
   *******************************************************************************/
  reg s1_r1, s1_r2, s1_r3;
  always @(posedge clk) begin
    s1_r1 <= s1;
    s1_r2 <= s1_r1;
    s1_r3 <= s1_r2;
  end
  wire s1_press = s1_r2 & ~s1_r3;

  wire [7:0] rx_data;  // received byte (only used as a start trigger)
  wire rx_valid;

  uart_rx #(
      .DELAY_FRAMES(DELAY_FRAMES)
  ) u_rx (
      .clk(clk),
      .rst_n(rst_n),
      .rxd(uart_rxp),
      .rx_data(rx_data),
      .rx_valid(rx_valid)
  );

  wire start_evt = s1_press | rx_valid;

  /*******************************************************************************
   ** UART message printer (9600 8N1) - 21-bit word address, 18-bit data         **
   *******************************************************************************/
  localparam MSG_BANNER   = 4'd0;
  localparam MSG_PROMPT   = 4'd1;
  localparam MSG_WRITE    = 4'd2;
  localparam MSG_READ_OK  = 4'd3;
  localparam MSG_READ_ERR = 4'd4;
  localparam MSG_BLOCK    = 4'd5;
  localparam MSG_VERIFY   = 4'd6;
  localparam MSG_DOT      = 4'd7;
  localparam MSG_PASS     = 4'd8;
  localparam MSG_FAIL     = 4'd9;

  reg        p_start;
  reg [ 3:0] p_msg;
  reg [20:0] p_addr;
  reg [17:0] p_data;
  wire p_busy;

  msg_printer18 #(
      .DELAY_FRAMES(DELAY_FRAMES)
  ) u_printer (
      .clk(clk),
      .rst_n(rst_n),
      .start(p_start),
      .msg(p_msg),
      .addr(p_addr),
      .data(p_data),
      .busy(p_busy),
      .txd(uart_txp)
  );

  /*******************************************************************************
   ** SDRAM controller under test: sdram18 (18-bit word, same FREQ as the        **
   ** full build's MEM_RAM_49_SDRAM instantiation)                               **
   *******************************************************************************/
  reg rd, wr, refresh;
  reg [20:0] mem_addr;
  reg [17:0] mem_din;
  wire [17:0] dout;
  wire data_ready, busy;

  sdram18 #(
      .FREQ(CLK_FREQ)
  ) u_sdram (
      .clk(clk),
      .clk_sdram(clk_sdram),
      .resetn(rst_n),
      .addr(mem_addr),
      .rd(rd),
      .wr(wr),
      .refresh(refresh),
      .din(mem_din),
      .dout(dout),
      .data_ready(data_ready),
      .busy(busy),

      .SDRAM_DQ(IO_sdram_dq),
      .SDRAM_A(O_sdram_addr),
      .SDRAM_BA(O_sdram_ba),
      .SDRAM_nCS(O_sdram_cs_n),
      .SDRAM_nWE(O_sdram_wen_n),
      .SDRAM_nRAS(O_sdram_ras_n),
      .SDRAM_nCAS(O_sdram_cas_n),
      .SDRAM_CLK(O_sdram_clk),
      .SDRAM_CKE(O_sdram_cke),
      .SDRAM_DQM(O_sdram_dqm)
  );

  /*******************************************************************************
   ** Refresh scheduling: request one auto-refresh every 15 us                   **
   *******************************************************************************/
  localparam REFRESH_INTERVAL = CLK_FREQ / 1_000_000 * 15;  // cycles per 15 us

  reg [9:0] ref_cnt;
  reg refresh_needed;
  always @(posedge clk) begin
    if (!rst_n) begin
      ref_cnt        <= 0;
      refresh_needed <= 0;
    end else begin
      ref_cnt <= ref_cnt + 1;
      if (ref_cnt >= REFRESH_INTERVAL[9:0]) refresh_needed <= 1;
      if (refresh) begin
        ref_cnt        <= 0;
        refresh_needed <= 0;
      end
    end
  end

  /*******************************************************************************
   ** Test state machine                                                         **
   *******************************************************************************/
  localparam ST_RESET     = 5'd0;
  localparam ST_BANNER    = 5'd1;
  localparam ST_PROMPT    = 5'd2;
  localparam ST_WAIT      = 5'd3;
  localparam ST_WR        = 5'd4;
  localparam ST_WR_WAIT   = 5'd5;
  localparam ST_RD        = 5'd6;
  localparam ST_RD_WAIT   = 5'd7;
  localparam ST_RD_PRINT  = 5'd8;
  localparam ST_BLOCK_MSG = 5'd9;
  localparam ST_BW        = 5'd10;
  localparam ST_BW_WAIT   = 5'd11;
  localparam ST_VER_MSG   = 5'd12;
  localparam ST_VR        = 5'd13;
  localparam ST_VR_WAIT   = 5'd14;
  localparam ST_ERR_PRINT = 5'd15;
  localparam ST_PASS      = 5'd16;
  localparam ST_FAIL      = 5'd17;
  localparam ST_DONE      = 5'd18;

  // Verbose demo: 4 spread WORD addresses. The ND-120 bridge packs addresses
  // as {bank, row[9:0], col[9:0]} while sdram18 slices {ba[1:0], row[10:0],
  // col[7:0]} - addresses with col[9:8] != 0 (bits [9:8] of the low 10) and
  // the bank bit [20] exercise exactly the differing interpretations.
  function [20:0] demo_addr(input [1:0] i);
    case (i)
      2'd0: demo_addr = 21'h000000;
      2'd1: demo_addr = 21'h000355;  // bits [9:8] set: bridge col high bits
      2'd2: demo_addr = 21'h100000;  // bank bit (bridge bank / sdram18 ba[1])
      2'd3: demo_addr = 21'h1FFFFF;  // last word of the 2M
    endcase
  endfunction

  function [17:0] demo_data(input [1:0] i);
    case (i)
      2'd0: demo_data = 18'h0A5A5;
      2'd1: demo_data = 18'h35A5A;   // parity bits [17:16] set
      2'd2: demo_data = 18'h3E3E3;
      2'd3: demo_data = 18'h12345;
    endcase
  endfunction

  // Address-derived 18-bit pattern for the block test (top bits folded in
  // so every word, including the parity lanes, carries address information)
  function [17:0] pattern(input [20:0] a);
    pattern = a[17:0] ^ {a[20:15], a[20:9]};
  endfunction

  reg [ 4:0] state;
  reg [ 1:0] demo_i;
  reg [21:0] taddr;  // one bit wider than the word address, reaches BLOCK_SIZE
  reg [17:0] actual;
  reg error_f, pass_f, dot_pending;

  // Issue a rd/wr only when the controller is free and no refresh is pending
  wire can_op = !busy && !refresh_needed && !wr && !rd && !refresh;
  // A print may be started only when the printer is free (and no start in flight)
  wire can_print = !p_busy && !p_start;

  assign led = ~{error_f, pass_f, state[3:0]};

  always @(posedge clk) begin
    if (!rst_n) begin
      state       <= ST_RESET;
      wr          <= 0;
      rd          <= 0;
      refresh     <= 0;
      p_start     <= 0;
      p_msg       <= MSG_BANNER;
      p_addr      <= 0;
      p_data      <= 0;
      mem_addr    <= 0;
      mem_din     <= 0;
      demo_i      <= 0;
      taddr       <= 0;
      actual      <= 0;
      error_f     <= 0;
      pass_f      <= 0;
      dot_pending <= 0;
    end else begin
      // command outputs are 1-cycle pulses
      wr      <= 0;
      rd      <= 0;
      refresh <= 0;
      p_start <= 0;

      // global refresh: runs in every state, whenever the controller is free.
      // can_op excludes refresh_needed, so this never collides with a rd/wr.
      if (refresh_needed && !busy && !wr && !rd && !refresh) refresh <= 1;

      case (state)
        // wait for the SDRAM init/config sequence (~200 us) to finish
        ST_RESET: if (!busy) state <= ST_BANNER;

        ST_BANNER:
        if (can_print) begin
          p_start <= 1;
          p_msg   <= MSG_BANNER;
          state   <= ST_PROMPT;
        end

        ST_PROMPT:
        if (can_print) begin
          p_start <= 1;
          p_msg   <= MSG_PROMPT;
          state   <= ST_WAIT;
        end

        ST_WAIT:
        if (start_evt) begin
          demo_i  <= 0;
          error_f <= 0;
          pass_f  <= 0;
          dot_pending <= 0;
          state   <= ST_WR;
        end

        // ---- verbose demo: 4 writes, each printed ----
        ST_WR:
        if (can_op && can_print) begin
          wr       <= 1;
          mem_addr <= demo_addr(demo_i);
          mem_din  <= demo_data(demo_i);
          p_start  <= 1;
          p_msg    <= MSG_WRITE;
          p_addr   <= demo_addr(demo_i);
          p_data   <= demo_data(demo_i);
          state    <= ST_WR_WAIT;
        end

        ST_WR_WAIT:
        if (!wr && !busy) begin
          if (demo_i == 2'd3) begin
            demo_i <= 0;
            state  <= ST_RD;
          end else begin
            demo_i <= demo_i + 1;
            state  <= ST_WR;
          end
        end

        // ---- verbose demo: 4 reads, each printed with OK/ERR ----
        ST_RD:
        if (can_op) begin
          rd       <= 1;
          mem_addr <= demo_addr(demo_i);
          state    <= ST_RD_WAIT;
        end

        ST_RD_WAIT:
        if (data_ready) begin
          actual <= dout;
          state  <= ST_RD_PRINT;
        end

        ST_RD_PRINT:
        if (can_print && !busy) begin
          p_start <= 1;
          p_addr  <= demo_addr(demo_i);
          p_data  <= actual;
          if (actual == demo_data(demo_i)) begin
            p_msg <= MSG_READ_OK;
          end else begin
            p_msg   <= MSG_READ_ERR;
            error_f <= 1;
          end
          if (demo_i == 2'd3) begin
            state <= (error_f || (actual != demo_data(demo_i))) ? ST_FAIL : ST_BLOCK_MSG;
          end else begin
            demo_i <= demo_i + 1;
            state  <= ST_RD;
          end
        end

        // ---- block test: write BLOCK_SIZE words ----
        ST_BLOCK_MSG:
        if (can_print) begin
          p_start <= 1;
          p_msg   <= MSG_BLOCK;
          taddr   <= 0;
          state   <= ST_BW;
        end

        ST_BW:
        if (dot_pending) begin
          if (can_print) begin
            p_start     <= 1;
            p_msg       <= MSG_DOT;
            dot_pending <= 0;
          end
        end else if (taddr == BLOCK_SIZE) begin
          taddr <= 0;
          state <= ST_VER_MSG;
        end else if (can_op) begin
          wr       <= 1;
          mem_addr <= taddr[20:0];
          mem_din  <= pattern(taddr[20:0]);
          state    <= ST_BW_WAIT;
        end

        ST_BW_WAIT:
        if (!wr && !busy) begin
          taddr <= taddr + 1;
          if (((taddr + 22'd1) & (DOT_STEP - 22'd1)) == 0) dot_pending <= 1;
          state <= ST_BW;
        end

        // ---- block test: read back and verify ----
        ST_VER_MSG:
        if (can_print) begin
          p_start <= 1;
          p_msg   <= MSG_VERIFY;
          state   <= ST_VR;
        end

        ST_VR:
        if (dot_pending) begin
          if (can_print) begin
            p_start     <= 1;
            p_msg       <= MSG_DOT;
            dot_pending <= 0;
          end
        end else if (taddr == BLOCK_SIZE) begin
          state <= ST_PASS;
        end else if (can_op) begin
          rd       <= 1;
          mem_addr <= taddr[20:0];
          state    <= ST_VR_WAIT;
        end

        ST_VR_WAIT:
        if (data_ready) begin
          if (dout != pattern(taddr[20:0])) begin
            actual  <= dout;
            error_f <= 1;
            state   <= ST_ERR_PRINT;
          end else begin
            taddr <= taddr + 1;
            if (((taddr + 22'd1) & (DOT_STEP - 22'd1)) == 0) dot_pending <= 1;
            state <= ST_VR;
          end
        end

        ST_ERR_PRINT:
        if (can_print && !busy) begin
          p_start <= 1;
          p_msg   <= MSG_READ_ERR;
          p_addr  <= taddr[20:0];
          p_data  <= actual;
          state   <= ST_FAIL;
        end

        // ---- result ----
        ST_PASS:
        if (can_print) begin
          p_start <= 1;
          p_msg   <= MSG_PASS;
          pass_f  <= 1;
          state   <= ST_DONE;
        end

        ST_FAIL:
        if (can_print) begin
          p_start <= 1;
          p_msg   <= MSG_FAIL;
          state   <= ST_DONE;
        end

        ST_DONE:
        if (start_evt && !p_busy) begin
          state <= ST_BANNER;
        end

        default: state <= ST_RESET;
      endcase
    end
  end

endmodule
