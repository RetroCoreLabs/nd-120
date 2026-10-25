//============================================================================
//! Full-machine boot + keyboard test for the MEGA65 core (Verilator --timing)
//!
//! Full path: Verilog/fpga/mega65/sim/nd120_mega65_machine_tb.v
//!
//! WHY THIS EXISTS. The first MEGA65 R6 tester reported the console keyboard
//! dead: the CPU printed its OPCOM '#' prompt, nothing typed had any
//! effect, while the framework's own HELP menu read the same keyboard
//! fine. Every piece of the path had a unit test and every unit test was
//! green - which only proved each piece against the model of its
//! neighbour that its testbench carried. What had never been run anywhere
//! was the WHOLE path on this board's wiring: the framework's key scan ->
//! m65_keys_to_ps2 -> the shared TDV decoder and expander -> the console
//! UART bridge -> the CPU board's SC2661 -> MOPC answering. This bench runs
//! exactly that, on the real machine RTL in the R6 configuration, with the
//! framework's scan modelled from its source (matrix_to_keynum.vhdl:
//! key_num and key_pressed_n change on the same edge and hold for one
//! dwell of clock/(72*1000) cycles).
//!
//! THE ORACLE is MOPC itself, as in the Tang's nd120_tang20k_tb.v: a
//! RETURN at the '#' prompt makes MOPC print a fresh '#' (Run120.cpp and
//! the Tang bench both rely on it). So the pass criterion is "the CPU
//! answered the key", not "a byte left the keyboard decoder" - and every
//! intermediate stage is reported too, so a failure says WHERE the key died:
//!   stage 1  a PS/2 event left m65_keys_to_ps2        (CONSOLE.s_code_valid)
//!   stage 2  the decoder produced a character         (CONSOLE.s_kbd_ascii_valid)
//!   stage 3  the byte was handed to the console UART  (s_kbd_valid, 0x0D)
//!   stage 4  MOPC printed a new '#'                   (s_cpu_byte_data)
//!
//! What is NOT in here: the framework's QNICE firmware and its keyboard
//! enable (CSR bit 3) - the scan is fed as the framework feeds it once that
//! bit is set. Nor the VHDL skin (main.vhd / mega65.vhd): the machine's own
//! port list is driven directly, as main.vhd drives it.
//!
//! Prints "TB_RESULT: PASS" or "TB_RESULT: FAIL". Run through
//! sim/lint_machine.sh vtest (Verilator --binary --timing; iverilog cannot
//! boot the CPU in reasonable time).
//============================================================================

`timescale 1ns / 1ps
`default_nettype none

module nd120_mega65_machine_tb;

  //--------------------------------------------------------------------------
  // Clocks: the values CORE/vhdl/clk.vhd makes for an R6
  //--------------------------------------------------------------------------
  reg clk_cpu   = 1'b0;  always #25.000 clk_cpu   = ~clk_cpu;    // 20 MHz
  reg clk_2x    = 1'b0;  always #12.500 clk_2x    = ~clk_2x;     // 40 MHz
  wire clk_2x_sdram = ~clk_2x;                                   // 40 MHz, 180 degrees
  reg clk_pix   = 1'b0;  always #19.843 clk_pix   = ~clk_pix;    // 25.197 MHz
  reg clk_qnice = 1'b0;  always #10.000 clk_qnice = ~clk_qnice;  // 50 MHz
  reg hr_clk    = 1'b0;  always #5.000  hr_clk    = ~hr_clk;     // 100 MHz

  reg rst_n       = 1'b0;
  reg rst_qnice_n = 1'b0;

  //--------------------------------------------------------------------------
  // The framework's keyboard scan, modelled from matrix_to_keynum.vhdl:
  // key_num 0..79, each held for DWELL clocks of the 40 MHz main clock
  // (clock_frequency / (72 * scan_frequency) = 40e6 / 72000 = 555), and
  // key_pressed_n updated on the SAME edge as key_num. `down` is the
  // physical keyboard; `kb_enable` plays the framework's CSR keyboard bit
  // (m2m_keyb.vhd: key_pressed_n_o <= key_status_n when enable_core_i
  // else '1').
  //--------------------------------------------------------------------------
  localparam integer DWELL = 555;
  reg  [79:0] down      = 80'd0;
  reg         kb_enable = 1'b0;
  reg  [6:0]  key_num   = 7'd0;
  reg         key_pressed_n = 1'b1;
  integer     dwell_cnt = 0;

  always @(posedge clk_2x) begin
    if (dwell_cnt == DWELL - 1) begin
      dwell_cnt     <= 0;
      key_num       <= (key_num == 7'd79) ? 7'd0 : key_num + 7'd1;
      key_pressed_n <= kb_enable ? ~down[(key_num == 7'd79) ? 7'd0 : key_num + 7'd1] : 1'b1;
    end else begin
      dwell_cnt <= dwell_cnt + 1;
    end
  end

  //--------------------------------------------------------------------------
  // The machine, R6 configuration (MAIN_RAM_SDRAM + PACK16 + DQ16 from the
  // command line), on a 16-bit SDRAM model. Virtual drives idle (nothing
  // mounted), the HyperRAM port idle (unused in this configuration).
  //--------------------------------------------------------------------------
  localparam integer N = 5;

  wire [7:0] video_r, video_g, video_b;
  wire       video_hs, video_vs, video_hblank, video_vblank;

  wire [N*32-1:0] sd_lba;
  wire [N*6-1:0]  sd_blk_cnt;
  wire [N-1:0]    sd_rd, sd_wr;
  wire [7:0]      sd_buff_din;

  wire        sdram_clk, sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n;
  wire [12:0] sdram_a;
  wire [1:0]  sdram_ba;
  wire        sdram_dqml, sdram_dqmh;
  wire [15:0] sdram_dq;

  wire hr_write, hr_read;
  wire [31:0] hr_address;
  wire [15:0] hr_writedata;
  wire [1:0]  hr_byteenable;
  wire [7:0]  hr_burstcount;

  wire cpu_red, cpu_green, cpu_running, disc_activity;

  nd120_mega65_machine #(
      .N_CLIENTS (N),
      .LOCAL_ECHO(0)
  ) DUT (
      .clk_cpu      (clk_cpu),
      .clk_2x       (clk_2x),
      .clk_2x_sdram (clk_2x_sdram),
      .clk_pix      (clk_pix),
      .rst_n        (rst_n),
      .rst_pix_n    (rst_n),
      .cache_on     (1'b1),

      .key_num      (key_num),
      .key_pressed_n(key_pressed_n),
      .text_colour  (2'd0),
      .panel_enable (1'b1),

      .video_r(video_r), .video_g(video_g), .video_b(video_b),
      .video_hs(video_hs), .video_vs(video_vs),
      .video_hblank(video_hblank), .video_vblank(video_vblank),

      .clk_qnice   (clk_qnice),
      .rst_qnice_n (rst_qnice_n),
      .img_mounted ({N{1'b0}}),
      .img_readonly(1'b0),
      .img_size    (32'd0),
      .sd_lba      (sd_lba),
      .sd_blk_cnt  (sd_blk_cnt),
      .sd_rd       (sd_rd),
      .sd_wr       (sd_wr),
      .sd_ack      ({N{1'b0}}),
      .sd_buff_addr(14'd0),
      .sd_buff_dout(8'd0),
      .sd_buff_din (sd_buff_din),
      .sd_buff_wr  (1'b0),

      .sdram_clk  (sdram_clk),
      .sdram_cke  (sdram_cke),
      .sdram_cs_n (sdram_cs_n),
      .sdram_ras_n(sdram_ras_n),
      .sdram_cas_n(sdram_cas_n),
      .sdram_we_n (sdram_we_n),
      .sdram_a    (sdram_a),
      .sdram_ba   (sdram_ba),
      .sdram_dqml (sdram_dqml),
      .sdram_dqmh (sdram_dqmh),
      .sdram_dq   (sdram_dq),

      .hr_clk          (hr_clk),
      .hr_rst          (1'b0),
      .hr_write        (hr_write),
      .hr_read         (hr_read),
      .hr_address      (hr_address),
      .hr_writedata    (hr_writedata),
      .hr_byteenable   (hr_byteenable),
      .hr_burstcount   (hr_burstcount),
      .hr_readdata     (16'd0),
      .hr_readdatavalid(1'b0),
      .hr_waitrequest  (1'b0),

      .cpu_red      (cpu_red),
      .cpu_green    (cpu_green),
      .cpu_running  (cpu_running),
      .disc_activity(disc_activity)
  );

  sdram16_model SDRAM (
      .clk  (sdram_clk),
      .cke  (sdram_cke),
      .cs_n (sdram_cs_n),
      .ras_n(sdram_ras_n),
      .cas_n(sdram_cas_n),
      .we_n (sdram_we_n),
      .a    (sdram_a[10:0]),
      .ba   (sdram_ba),
      .dqm  ({sdram_dqmh, sdram_dqml}),
      .dq   (sdram_dq)
  );

  //--------------------------------------------------------------------------
  // Taps - the machine's own seams, through the hierarchy
  //--------------------------------------------------------------------------
  // CPU -> console: every byte the console UART receiver hands the terminal
  integer rx_count = 0;
  integer hash_count = 0;
  always @(posedge clk_pix) begin
    if (DUT.s_cpu_byte_valid) begin
      rx_count = rx_count + 1;
      if (DUT.s_cpu_byte_data == 8'h23) hash_count = hash_count + 1;
      if (DUT.s_cpu_byte_data >= 8'h20 && DUT.s_cpu_byte_data < 8'h7F)
        $write("%c", DUT.s_cpu_byte_data);
      else
        $write("<%02x>", DUT.s_cpu_byte_data);
      $fflush;
    end
  end

  // keyboard -> CPU: the three stages before the wire
  integer n_ps2 = 0, n_ascii = 0, n_seam = 0;
  reg [7:0] last_ps2 = 8'h00, last_ascii = 8'h00, last_seam = 8'h00;
  always @(posedge clk_pix) begin
    if (DUT.CONSOLE.s_code_valid)      begin n_ps2   = n_ps2 + 1;   last_ps2   = DUT.CONSOLE.s_code_data; end
    if (DUT.CONSOLE.s_kbd_ascii_valid) begin n_ascii = n_ascii + 1; last_ascii = DUT.CONSOLE.s_kbd_ascii_data; end
    if (DUT.s_kbd_valid && DUT.s_kbd_ready) begin n_seam = n_seam + 1; last_seam = DUT.s_kbd_data; end
  end

  // the serial line itself: count start bits on the CPU's RXD
  integer n_rxd_starts = 0;
  reg rxd_d = 1'b1;
  always @(posedge clk_cpu) begin
    rxd_d <= DUT.s_cpu_rxd;
    if (rxd_d && !DUT.s_cpu_rxd) n_rxd_starts = n_rxd_starts + 1;
  end

  //--------------------------------------------------------------------------
  // The run
  //--------------------------------------------------------------------------
  integer errors = 0;
  integer t;
  integer hashes_before;

  task press(input integer key, input integer sweeps);
    begin
      down[key] = 1'b1;
      repeat (sweeps * 80 * DWELL) @(posedge clk_2x);
      down[key] = 1'b0;
      repeat (2 * 80 * DWELL) @(posedge clk_2x);
    end
  endtask

  initial begin
    $display("TB: MEGA65 R6 machine, 16-bit SDRAM model, framework scan at %0d clocks per key", DWELL);
    #1000;
    rst_n       = 1'b1;
    rst_qnice_n = 1'b1;

    //------------------------------------------------------------------
    // 1. Boot to the OPCOM prompt (preloaded WCS: master clear + self-test)
    //------------------------------------------------------------------
    $display("TB: booting (waiting for '#')...");
    t = 0;
    while (hash_count == 0 && t < 60_000) begin   // 60000 x 100 us = 6 s
      #100_000;
      t = t + 1;
    end
    if (hash_count == 0) begin
      $display("");
      $display("FAIL: no OPCOM prompt within 6 s (cpu_green=%0d cpu_red=%0d running=%0d, %0d bytes)",
               cpu_green, cpu_red, cpu_running, rx_count);
      $display("TB_RESULT: FAIL (no prompt)");
      $finish;
    end
    $display("");
    $display("TB: OPCOM prompt seen after %0d x 100 us (%0d bytes so far)", t, rx_count);

    //------------------------------------------------------------------
    // 2. The framework connects the keyboard 333 ms after the welcome
    //    screen; let MOPC settle the same way.
    //------------------------------------------------------------------
    #333_000_000;
    kb_enable = 1'b1;
    #10_000_000;

    //------------------------------------------------------------------
    // 3. RETURN (MEGA65 key 1), held for three scans. MOPC answers a CR
    //    with a new '#'. It polls the console once per RTC tick, so allow
    //    a generous 400 ms for the answer.
    //------------------------------------------------------------------
    hashes_before = hash_count;
    n_ps2 = 0; n_ascii = 0; n_seam = 0; n_rxd_starts = 0;
    $display("TB: pressing RETURN (key 1)...");
    press(1, 3);
    #400_000_000;
    $display("");
    $display("TB: stage 1 PS/2 events from m65_keys_to_ps2: %0d (last code 0x%02X)", n_ps2, last_ps2);
    $display("TB: stage 2 characters from ps2_decoder_tdv:   %0d (last 0x%02X)", n_ascii, last_ascii);
    $display("TB: stage 3 bytes handed to the console UART:  %0d (last 0x%02X)", n_seam, last_seam);
    $display("TB: stage 3b start bits seen on the CPU's RXD: %0d", n_rxd_starts);
    $display("TB: stage 4 new '#' from MOPC:                 %0d", hash_count - hashes_before);

    if (n_ps2 == 0)   begin errors = errors + 1; $display("FAIL: stage 1 - no PS/2 event left m65_keys_to_ps2"); end
    if (n_ascii == 0) begin errors = errors + 1; $display("FAIL: stage 2 - the decoder produced no character"); end
    if (n_seam == 0 || last_seam !== 8'h0D)
                      begin errors = errors + 1; $display("FAIL: stage 3 - no CR handed to the console UART"); end
    if (n_rxd_starts == 0)
                      begin errors = errors + 1; $display("FAIL: stage 3b - nothing on the CPU's RXD line"); end
    if (hash_count == hashes_before)
                      begin errors = errors + 1; $display("FAIL: stage 4 - MOPC did not answer the RETURN with a new '#'"); end

    //------------------------------------------------------------------
    // 4. A second RETURN, to catch a path that works exactly once.
    //------------------------------------------------------------------
    hashes_before = hash_count;
    $display("TB: pressing RETURN again...");
    press(1, 3);
    #400_000_000;
    $display("");
    if (hash_count == hashes_before) begin
      errors = errors + 1;
      $display("FAIL: the second RETURN got no '#'");
    end else begin
      $display("TB: second RETURN answered");
    end

    if (errors == 0) $display("TB_RESULT: PASS (MEGA65 machine: RETURN at '#' answered by MOPC, twice)");
    else             $display("TB_RESULT: FAIL (%0d errors)", errors);
    $finish;
  end

endmodule

`default_nettype wire
